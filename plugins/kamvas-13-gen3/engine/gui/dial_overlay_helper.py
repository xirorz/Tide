#!/usr/bin/env python3
"""Layer-shell radial dial picker for Hyprland/Wayland.

Dark semi-transparent pie menu: thin wedge dividers and a center × hub.
Ring inner edge sits 5px outside the hub (gap for the “donut” hole).
"""
from __future__ import annotations

import json
import math
import subprocess
import sys
import threading
from dataclasses import dataclass

import cairo
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")

from gi.repository import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

# Layout (px) — ring + hub centered in window; no title bar
OUTER_RADIUS = 114
# Gap between center × circle and inner edge of wedge ring (donut hole)
HUB_RING_GAP_PX = 5
CENTER_HUB_RADIUS = 26
INNER_RADIUS = CENTER_HUB_RADIUS + HUB_RING_GAP_PX
RING_MARGIN = 14  # space from window edge to outer arc (room for soft shadow)

WINDOW_WIDTH = int(2 * (OUTER_RADIUS + RING_MARGIN))
WINDOW_HEIGHT = WINDOW_WIDTH
_CX = WINDOW_WIDTH / 2
_CY = WINDOW_HEIGHT / 2

# Colors (linear RGB) — dark glass; active wedge reads clearly vs idle/hover
_COL_WEDGE = (0.06, 0.06, 0.07, 0.78)
_COL_WEDGE_HOVER = (0.12, 0.12, 0.14, 0.84)  # unselected wedge under cursor
# Current / default mode (payload selected_index) — cool blue, unmistakable vs gray wedges
_COL_WEDGE_ACTIVE = (0.14, 0.36, 0.58, 0.92)
_COL_WEDGE_ACTIVE_STROKE = (0.45, 0.72, 0.95, 0.75)
_COL_DIVIDER = (0.92, 0.92, 0.94, 0.55)
_COL_HUB = (0.05, 0.05, 0.06, 0.94)
_COL_HUB_HOVER = (0.12, 0.13, 0.16, 0.96)
_COL_HUB_STROKE = (0.35, 0.35, 0.38, 0.9)
_COL_HUB_STROKE_HOVER = (0.55, 0.62, 0.72, 0.95)
_COL_TEXT = (0.98, 0.98, 0.99, 0.95)
_COL_TEXT_MUTED = (0.78, 0.78, 0.80, 0.85)


@dataclass
class Payload:
    app_class: str
    dial_id: str
    dial_label: str
    modes: list[str]
    selected_index: int
    timeout_ms: int


def _hit_test(x: float, y: float, count: int) -> str | int | None:
    """Return sector index, 'hub' for center × (dismiss), or None."""
    if count <= 0:
        return None
    dx = x - _CX
    dy = y - _CY
    radius = math.hypot(dx, dy)
    if radius <= CENTER_HUB_RADIUS:
        return "hub"
    if radius < INNER_RADIUS or radius > OUTER_RADIUS:
        return None
    base_angle = -math.pi / 2
    step = math.tau / count
    angle = math.atan2(dy, dx)
    rel = (angle - base_angle) % math.tau
    return int(rel / step) % count


def _cursor_pos() -> tuple[int, int]:
    try:
        out = subprocess.check_output(
            ["hyprctl", "cursorpos", "-j"],
            text=True,
            timeout=0.5,
            stderr=subprocess.DEVNULL,
        )
        data = json.loads(out)
        return int(data.get("x", 0)), int(data.get("y", 0))
    except Exception:
        display = Gdk.Display.get_default()
        if display is not None:
            seat = display.get_default_seat()
            if seat is not None:
                pointer = seat.get_pointer()
                if pointer is not None:
                    _screen, x, y = pointer.get_position()
                    return int(x), int(y)
        return 0, 0


class RadialOverlay(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_accept_focus(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_keep_above(True)
        self.set_app_paintable(True)
        self.set_size_request(WINDOW_WIDTH, WINDOW_HEIGHT)
        self.set_type_hint(Gdk.WindowTypeHint.NOTIFICATION)
        self.add_events(
            Gdk.EventMask.BUTTON_PRESS_MASK
            | Gdk.EventMask.POINTER_MOTION_MASK
            | Gdk.EventMask.LEAVE_NOTIFY_MASK
        )
        self.connect("draw", self._on_draw)
        self.connect("button-press-event", self._on_button_press)
        self.connect("motion-notify-event", self._on_motion)
        self.connect("leave-notify-event", self._on_leave)
        self.connect("destroy", self._on_destroy)

        screen = self.get_screen()
        if screen is not None:
            visual = screen.get_rgba_visual()
            if visual is not None:
                self.set_visual(visual)

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "autswitch-radial")
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, False)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, False)

        self._payload = Payload("", "", "Dial", [], 0, 3000)
        self._timeout_id = 0
        self._alive = True
        self._hover_index: int | None = None
        self._hover_hub: bool = False

    def apply_payload(self, raw_payload: dict) -> bool:
        modes = [str(mode) for mode in raw_payload.get("modes", []) if mode]
        if not modes:
            return False

        timeout_ms = max(400, int(raw_payload.get("timeout_ms", 3000)))
        selected = int(raw_payload.get("selected_index", 0)) % len(modes)
        self._payload = Payload(
            app_class=str(raw_payload.get("app_class") or ""),
            dial_id=str(raw_payload.get("dial_id") or ""),
            dial_label=str(raw_payload.get("dial_label") or "Dial"),
            modes=modes,
            selected_index=selected,
            timeout_ms=timeout_ms,
        )

        self._reposition()
        self._hover_index = None
        self._hover_hub = False
        self.queue_draw()
        self.show_all()

        if self._timeout_id:
            GLib.source_remove(self._timeout_id)
        self._timeout_id = GLib.timeout_add(timeout_ms, self._on_timeout)
        return False

    def _reposition(self) -> None:
        x, y = _cursor_pos()
        display = Gdk.Display.get_default()
        monitor = display.get_monitor_at_point(x, y) if display is not None else None
        if monitor is not None:
            GtkLayerShell.set_monitor(self, monitor)
            geometry = monitor.get_geometry()
            left = max(
                8,
                min(
                    x - geometry.x - WINDOW_WIDTH // 2,
                    geometry.width - WINDOW_WIDTH - 8,
                ),
            )
            top = max(
                8,
                min(
                    y - geometry.y - WINDOW_HEIGHT // 2,
                    geometry.height - WINDOW_HEIGHT - 8,
                ),
            )
        else:
            left = max(8, x - WINDOW_WIDTH // 2)
            top = max(8, y - WINDOW_HEIGHT // 2)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, left)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, top)

    def _on_motion(self, _widget, event) -> bool:
        count = len(self._payload.modes)
        hit = _hit_test(event.x, event.y, count)
        new_hover: int | None = hit if isinstance(hit, int) else None
        new_hub = hit == "hub"
        if new_hover != self._hover_index or new_hub != self._hover_hub:
            self._hover_index = new_hover
            self._hover_hub = new_hub
            self.queue_draw()
        return False

    def _on_leave(self, _widget, _event) -> bool:
        if self._hover_index is not None or self._hover_hub:
            self._hover_index = None
            self._hover_hub = False
            self.queue_draw()
        return False

    def _on_button_press(self, _widget, event) -> bool:
        if getattr(event, "button", 0) != 1:
            return False
        count = len(self._payload.modes)
        hit = _hit_test(event.x, event.y, count)
        if hit == "hub":
            Gtk.main_quit()
            return True
        if hit is None or not isinstance(hit, int):
            return False
        self._payload.selected_index = hit
        self.queue_draw()
        print(
            json.dumps(
                {
                    "type": "select",
                    "app_class": self._payload.app_class,
                    "dial_id": self._payload.dial_id,
                    "selected_index": hit,
                }
            ),
            flush=True,
        )
        Gtk.main_quit()
        return True

    def _on_timeout(self) -> bool:
        Gtk.main_quit()
        return False

    def _on_destroy(self, *_args) -> None:
        self._alive = False
        if self._timeout_id:
            GLib.source_remove(self._timeout_id)
            self._timeout_id = 0

    def _on_draw(self, _widget, cr: cairo.Context) -> bool:
        cr.set_source_rgba(0, 0, 0, 0)
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)

        self._draw_ring_background(cr)
        self._draw_sectors(cr)
        self._draw_radial_dividers(cr)
        self._draw_outer_ring_stroke(cr)
        self._draw_center_hub(cr, self._hover_hub)
        return False

    def _draw_ring_background(self, cr: cairo.Context) -> None:
        """Soft shadow under the ring."""
        grad = cairo.RadialGradient(_CX, _CY, INNER_RADIUS, _CX, _CY, OUTER_RADIUS + 18)
        grad.add_color_stop_rgba(0.0, 0, 0, 0, 0.0)
        grad.add_color_stop_rgba(0.85, 0, 0, 0, 0.18)
        grad.add_color_stop_rgba(1.0, 0, 0, 0, 0.0)
        cr.set_source(grad)
        cr.arc(_CX, _CY, OUTER_RADIUS + 18, 0, math.tau)
        cr.fill()

    def _draw_sectors(self, cr: cairo.Context) -> None:
        count = len(self._payload.modes)
        if count == 0:
            return
        base_angle = -math.pi / 2
        step = math.tau / count
        gap = 0.012
        for idx, label in enumerate(self._payload.modes):
            start = base_angle + idx * step + gap
            end = base_angle + (idx + 1) * step - gap
            selected = idx == self._payload.selected_index
            hovered = self._hover_index == idx and not selected
            if selected:
                fill = _COL_WEDGE_ACTIVE
            elif hovered:
                fill = _COL_WEDGE_HOVER
            else:
                fill = _COL_WEDGE
            cr.new_path()
            cr.arc(_CX, _CY, OUTER_RADIUS, start, end)
            cr.arc_negative(_CX, _CY, INNER_RADIUS, end, start)
            cr.close_path()
            cr.set_source_rgba(*fill)
            cr.fill()
            if selected:
                cr.new_path()
                cr.arc(_CX, _CY, OUTER_RADIUS, start, end)
                cr.arc_negative(_CX, _CY, INNER_RADIUS, end, start)
                cr.close_path()
                cr.set_source_rgba(*_COL_WEDGE_ACTIVE_STROKE)
                cr.set_line_width(1.4)
                cr.stroke()
            self._draw_sector_label(
                cr, (start + end) / 2, label, selected, hovered
            )

    def _draw_radial_dividers(self, cr: cairo.Context) -> None:
        count = len(self._payload.modes)
        if count < 2:
            return
        base_angle = -math.pi / 2
        step = math.tau / count
        cr.set_source_rgba(*_COL_DIVIDER)
        cr.set_line_width(0.85)
        for i in range(count):
            ang = base_angle + i * step
            x1 = _CX + math.cos(ang) * INNER_RADIUS
            y1 = _CY + math.sin(ang) * INNER_RADIUS
            x2 = _CX + math.cos(ang) * OUTER_RADIUS
            y2 = _CY + math.sin(ang) * OUTER_RADIUS
            cr.move_to(x1, y1)
            cr.line_to(x2, y2)
            cr.stroke()

    def _draw_outer_ring_stroke(self, cr: cairo.Context) -> None:
        count = len(self._payload.modes)
        if count == 0:
            return
        cr.new_path()
        cr.arc(_CX, _CY, OUTER_RADIUS, 0, math.tau)
        cr.set_source_rgba(0.4, 0.4, 0.42, 0.35)
        cr.set_line_width(1.0)
        cr.stroke()
        cr.new_path()
        cr.arc(_CX, _CY, INNER_RADIUS, 0, math.tau)
        cr.set_source_rgba(0.35, 0.35, 0.37, 0.45)
        cr.set_line_width(0.9)
        cr.stroke()

    def _draw_sector_label(
        self,
        cr: cairo.Context,
        angle: float,
        label: str,
        selected: bool,
        hovered: bool = False,
    ) -> None:
        radius = (OUTER_RADIUS + INNER_RADIUS) / 2
        x = _CX + math.cos(angle) * radius
        y = _CY + math.sin(angle) * radius

        cr.select_font_face(
            "Sans",
            cairo.FONT_SLANT_NORMAL,
            cairo.FONT_WEIGHT_NORMAL,
        )
        max_chars = 22
        if len(label) > max_chars:
            label = label[: max_chars - 1] + "…"

        # Word-wrap very long labels into two lines (simple)
        words = label.split()
        lines: list[str] = []
        if len(words) <= 2:
            lines = [label]
        else:
            mid = len(words) // 2
            lines = [" ".join(words[:mid]), " ".join(words[mid:])]

        cr.set_font_size(11 if (selected or hovered) else 10)
        line_height = 13
        total_h = len(lines) * line_height
        start_y = y - total_h / 2 + line_height * 0.35

        if selected:
            col = _COL_TEXT
        elif hovered:
            col = _COL_TEXT
        else:
            col = _COL_TEXT_MUTED

        for li, line in enumerate(lines):
            ext = cr.text_extents(line)
            ly = start_y + li * line_height
            cr.move_to(x - ext.width / 2 - ext.x_bearing, ly - ext.y_bearing)
            cr.set_source_rgba(*col)
            cr.show_text(line)

    def _draw_center_hub(self, cr: cairo.Context, hovered: bool) -> None:
        cr.arc(_CX, _CY, CENTER_HUB_RADIUS, 0, math.tau)
        cr.set_source_rgba(*(_COL_HUB_HOVER if hovered else _COL_HUB))
        cr.fill_preserve()
        cr.set_source_rgba(
            *(_COL_HUB_STROKE_HOVER if hovered else _COL_HUB_STROKE)
        )
        cr.set_line_width(1.15 if hovered else 1.0)
        cr.stroke()

        # × dismiss — brighter on hub hover
        cr.set_source_rgba(*(0.98, 0.99, 1.0, 1.0) if hovered else _COL_TEXT)
        cr.set_line_width(2.2 if hovered else 2.0)
        s = 8.0
        cr.move_to(_CX - s, _CY - s)
        cr.line_to(_CX + s, _CY + s)
        cr.move_to(_CX + s, _CY - s)
        cr.line_to(_CX - s, _CY + s)
        cr.stroke()


def _stdin_reader(window: RadialOverlay) -> None:
    for line in sys.stdin:
        text = line.strip()
        if not text:
            continue
        try:
            payload = json.loads(text)
        except json.JSONDecodeError:
            continue
        GLib.idle_add(window.apply_payload, payload)
    GLib.idle_add(Gtk.main_quit)


def main() -> int:
    ok, _args = Gtk.init_check()
    if not ok:
        print("dial overlay: Gtk could not initialize", file=sys.stderr)
        return 1
    window = RadialOverlay()
    threading.Thread(target=_stdin_reader, args=(window,), daemon=True).start()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
