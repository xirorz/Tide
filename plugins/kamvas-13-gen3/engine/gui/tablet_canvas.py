"""TabletCanvas — tablet SVG with label lines and clickable hotspots."""
from __future__ import annotations
import math
from pathlib import Path
from typing import Optional

from PyQt6.QtCore import QPointF, QRect, QRectF, QSize, Qt, pyqtSignal
from PyQt6.QtGui import (
    QBrush, QColor, QFont, QFontMetrics,
    QPainter, QPainterPath, QPen, QRadialGradient,
)
from PyQt6.QtSvg import QSvgRenderer
from PyQt6.QtWidgets import QToolTip, QWidget

from gui.theme import (
    BG,
    BG_ELEV,
    SURFACE,
    SURFACE_HOVER,
    BORDER,
    BORDER_SUBTLE,
    ACCENT,
    ACCENT_CYAN,
    TEXT,
    TEXT_MUTED,
    TEXT_FAINT,
    qc,
    qc_alpha,
)

_LABEL_W   = 12
_RIGHT_PAD = 16
_V_PAD     = 20
_CHIP_H    = 24
_CHIP_R    = 4
_DOT_R     = 6
_BTN_W_FRAC = 56 / 860
_BTN_H_FRAC = 44 / 500
_POPUP_GAP = 28
_DIAL_RING_INNER_FRAC = 24 / 38
_DIAL_CENTER_FRAC = 13 / 38

_BG = qc(BG)
_LINE = qc(BORDER)
_LINE_HOV = qc(ACCENT)
_DOT_BOUND_BG = qc(SURFACE)
_DOT_BOUND_BD = qc_alpha(ACCENT, 110)
_DOT_EMPTY_BG = qc(BG_ELEV)
_DOT_EMPTY_BD = qc(BORDER)
_DOT_HOV_BG = qc(SURFACE_HOVER)
_DOT_HOV_BD = qc(ACCENT)
_CHIP_BOUND_BG = qc(SURFACE)
_CHIP_BOUND_BD = qc_alpha(ACCENT, 90)
_CHIP_EMPTY_BG = qc(BG_ELEV)
_CHIP_EMPTY_BD = qc(BORDER)
_CHIP_HOV_BG = qc(SURFACE_HOVER)
_CHIP_HOV_BD = qc(ACCENT)
_TXT = qc(TEXT)
_TXT_DIM = qc(TEXT_MUTED)
_TXT_EMPTY = qc(TEXT_FAINT)
_ACTIVE_RIM = qc(ACCENT)
_RING_BOUND_BG = qc(BG_ELEV)
_RING_HOV_BG = qc(SURFACE_HOVER)
_CTR_BOUND_BG = qc(SURFACE)
_CTR_HOV_BG = qc(SURFACE_HOVER)
_SPECIAL_LABELS = {
    "scroll_up": "Scroll Up",
    "scroll_down": "Scroll Down",
    "scroll_left": "Scroll Left",
    "scroll_right": "Scroll Right",
    "zoom_in": "Zoom In",
    "zoom_out": "Zoom Out",
    "leftbrace": "Brush -",
    "rightbrace": "Brush +",
}


class TabletCanvas(QWidget):
    slot_clicked = pyqtSignal(int)
    empty_clicked = pyqtSignal()

    def __init__(self, tablet_def: dict, parent=None):
        super().__init__(parent)
        self._def      = tablet_def
        self._controls = tablet_def.get("controls", [])
        self._total    = tablet_def.get("total_slots", 0)

        self._slots: list[tuple[str, str, str]] = [("", "", "")] * self._total
        self._active  = False
        self._hovered = -1
        self._selected = -1
        self._editor_rect: Optional[QRectF] = None

        self._renderer: Optional[QSvgRenderer] = None
        img = tablet_def.get("image")
        if img and img.exists():
            self._renderer = QSvgRenderer(str(img))
        # If set, side-button hover/active use the SVG pill shape (clip) instead of a loose rounded rect.
        self._button_strip: Optional[dict[str, float]] = tablet_def.get("button_strip")

        self.setMinimumSize(720, 400)
        self.setMouseTracking(True)
        self.setAttribute(Qt.WidgetAttribute.WA_OpaquePaintEvent)

    # ── public ────────────────────────────────────────────────────────────────

    def set_profile(self, slots: list[tuple[str, str, str]], active: bool) -> None:
        cap = len(self._slots)
        self._slots  = (slots + [("", "", "")] * cap)[:cap]
        self._active = active
        self.update()

    def clear(self) -> None:
        self._slots  = [("", "", "")] * len(self._slots)
        self._active = False
        self._selected = -1
        self._editor_rect = None
        self.update()

    def set_selected_slot(self, sid: int) -> None:
        self._selected = sid
        self.update()

    def set_editor_rect(self, rect: Optional[QRect | QRectF]) -> None:
        self._editor_rect = QRectF(rect) if rect is not None else None
        self.update()

    # ── geometry ─────────────────────────────────────────────────────────────

    def _tablet_rect(self) -> QRectF:
        w = self.width()
        h = self.height()
        aw = w - _LABEL_W - _RIGHT_PAD
        ah = h - _V_PAD * 2
        aspect = 860 / 500
        if aw / ah > aspect:
            aw = ah * aspect
        else:
            ah = aw / aspect
        tx = _LABEL_W + (w - _LABEL_W - _RIGHT_PAD - aw) / 2
        ty = _V_PAD + (h - _V_PAD * 2 - ah) / 2
        return QRectF(tx, ty, aw, ah)

    def _ctrl_pt(self, ctrl: dict, tr: QRectF) -> QPointF:
        return QPointF(tr.x() + ctrl["cx"] * tr.width(),
                       tr.y() + ctrl["cy"] * tr.height())

    def _dial_r(self, ctrl: dict, tr: QRectF) -> float:
        return ctrl.get("r_frac", 0.054) * tr.width()

    def _button_rect(self, ctrl: dict, tr: QRectF) -> QRectF:
        c = self._ctrl_pt(ctrl, tr)
        bw = _BTN_W_FRAC * tr.width()
        bh = _BTN_H_FRAC * tr.height()
        return QRectF(c.x() - bw / 2, c.y() - bh / 2, bw, bh)

    # ── hit zones ────────────────────────────────────────────────────────────

    def _hit_zones(self, tr: QRectF) -> dict[int, QRectF]:
        zones: dict[int, QRectF] = {}
        for ctrl in self._controls:
            if ctrl["type"] == "button":
                zones[ctrl["id"]] = self._button_rect(ctrl, tr)
        return zones

    # ── paint ─────────────────────────────────────────────────────────────────

    def paintEvent(self, _) -> None:
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        p.setRenderHint(QPainter.RenderHint.TextAntialiasing)
        p.fillRect(self.rect(), _BG)

        tr = self._tablet_rect()
        if self._renderer:
            self._renderer.render(p, tr)
        else:
            self._draw_fallback(p, tr)

        if self._active:
            p.setPen(QPen(_ACTIVE_RIM, 1.5))
            p.setBrush(Qt.BrushStyle.NoBrush)
            p.drawRoundedRect(tr.adjusted(1, 1, -1, -1), 14, 14)

        for ctrl in self._controls:
            c = self._ctrl_pt(ctrl, tr)
            if ctrl["type"] == "button":
                self._draw_button_highlight(p, ctrl, tr)
            else:
                self._draw_dial_highlight(p, c, ctrl, tr)

        if self._selected >= 0 and self._editor_rect is not None:
            self._draw_editor_connector(p, tr)

        p.end()

    # ── dial ─────────────────────────────────────────────────────────────────

    def _draw_dial_highlight(self, p: QPainter, c: QPointF, ctrl: dict, tr: QRectF) -> None:
        outer_r = self._dial_r(ctrl, tr)
        inner_r = outer_r * _DIAL_RING_INNER_FRAC

        ring_sid = ctrl["slots"][0]["id"]
        ring_hov = self._hovered == ring_sid
        ring_sel = self._selected == ring_sid

        if ring_hov or ring_sel:
            g = QRadialGradient(c, outer_r * 1.3)
            g.setColorAt(0, qc_alpha(ACCENT, 45))
            g.setColorAt(1, QColor(0, 0, 0, 0))
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(QBrush(g))
            p.drawEllipse(c, outer_r * 1.3, outer_r * 1.3)
            self._draw_dial_ring(p, self._dial_ring_path(c, outer_r, inner_r))

    def _draw_dial_ring(self, p: QPainter, path: QPainterPath) -> None:
        ring_col = _RING_HOV_BG
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor(ring_col.red(), ring_col.green(),
                          ring_col.blue(), 130))
        p.drawPath(path)
        p.setPen(QPen(_DOT_HOV_BD, 1.5))
        p.setBrush(Qt.BrushStyle.NoBrush)
        p.drawPath(path)

    def _dial_ring_path(self, c: QPointF, outer_r: float, inner_r: float) -> QPainterPath:
        outer = QRectF(c.x() - outer_r, c.y() - outer_r, outer_r * 2, outer_r * 2)
        inner = QRectF(c.x() - inner_r, c.y() - inner_r, inner_r * 2, inner_r * 2)
        path = QPainterPath()
        path.addEllipse(outer)
        hole = QPainterPath()
        hole.addEllipse(inner)
        return path.subtracted(hole)

    def _draw_button_highlight(self, p: QPainter, ctrl: dict, tr: QRectF) -> None:
        sid = ctrl["id"]
        rect = self._button_rect(ctrl, tr)
        hovered = self._hovered == sid
        selected = self._selected == sid
        if not (hovered or selected):
            return

        bs = self._button_strip
        if bs:
            pill = QRectF(
                tr.x() + bs["x"] * tr.width(),
                tr.y() + bs["y"] * tr.height(),
                bs["w"] * tr.width(),
                bs["h"] * tr.height(),
            )
            rx_pill = pill.width() / 2.0
            clip = rect.intersected(pill)
            if clip.isEmpty():
                clip = rect
            self._draw_pill_segment_highlight(p, pill, rx_pill, clip, hovered, selected)
            return

        rx = max(4.0, min(rect.width(), rect.height()) * 0.14)
        color = _DOT_HOV_BG
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor(color.red(), color.green(), color.blue(), 120))
        p.drawRoundedRect(rect, rx, rx)

        if hovered or selected:
            glow = rect.adjusted(-5, -5, 5, 5)
            grx = max(6.0, min(glow.width(), glow.height()) * 0.12)
            g = QRadialGradient(glow.center(), max(glow.width(), glow.height()) * 0.75)
            g.setColorAt(0, qc_alpha(ACCENT, 55))
            g.setColorAt(1, QColor(0, 0, 0, 0))
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(QBrush(g))
            p.drawRoundedRect(glow, grx, grx)

            p.setPen(QPen(_DOT_HOV_BD, 1.4))
            p.setBrush(Qt.BrushStyle.NoBrush)
            p.drawRoundedRect(rect, rx, rx)

    def _draw_pill_segment_highlight(
        self,
        p: QPainter,
        pill: QRectF,
        rx: float,
        clip: QRectF,
        hovered: bool,
        selected: bool,
    ) -> None:
        """Fill/stroke the shared vertical pill clipped to one button band (matches SVG)."""
        p.save()
        p.setClipRect(clip)

        color = _DOT_HOV_BG
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor(color.red(), color.green(), color.blue(), 120))
        p.drawRoundedRect(pill, rx, rx)

        if hovered or selected:
            gc = clip.center()
            g = QRadialGradient(gc, max(clip.width(), clip.height()) * 0.85)
            g.setColorAt(0, qc_alpha(ACCENT, 55))
            g.setColorAt(1, QColor(0, 0, 0, 0))
            p.setBrush(QBrush(g))
            p.drawRoundedRect(pill, rx, rx)

        p.setPen(QPen(_DOT_HOV_BD, 1.4))
        p.setBrush(Qt.BrushStyle.NoBrush)
        p.drawRoundedRect(pill, rx, rx)
        p.restore()

    def _draw_editor_connector(self, p: QPainter, tr: QRectF) -> None:
        anchor = self._slot_anchor(self._selected, tr)
        if anchor is None or self._editor_rect is None:
            return
        rect = self._editor_rect
        target = QPointF(rect.left(), rect.center().y())
        if target.x() < anchor.x():
            target = QPointF(rect.right(), rect.center().y())
        path = QPainterPath(anchor)
        mid_x = anchor.x() + (target.x() - anchor.x()) * 0.45
        path.lineTo(mid_x, anchor.y())
        path.lineTo(mid_x, target.y())
        path.lineTo(target.x(), target.y())
        p.setPen(QPen(_LINE_HOV, 1.6, Qt.PenStyle.SolidLine,
                      Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin))
        p.setBrush(Qt.BrushStyle.NoBrush)
        p.drawPath(path)
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(_LINE_HOV)
        p.drawEllipse(anchor, 4, 4)

    # ── button label + dot ────────────────────────────────────────────────────

    def _draw_btn_label(self, p: QPainter, c: QPointF, name: str,
                        slot: tuple, hov: bool) -> None:
        chip = self._chip_rect(c.y())
        self._draw_chip_line(p, chip, c, slot, hov, prefix=name)

    def _draw_dot(self, p: QPainter, c: QPointF, slot: tuple, hov: bool) -> None:
        _, combo, _ = slot
        bound = bool(combo)
        if hov:
            bg, bd = _DOT_HOV_BG, _DOT_HOV_BD
        elif bound:
            bg, bd = _DOT_BOUND_BG, _DOT_BOUND_BD
        else:
            bg, bd = _DOT_EMPTY_BG, _DOT_EMPTY_BD

        if hov:
            g = QRadialGradient(c, _DOT_R * 2.8)
            g.setColorAt(0, qc_alpha(ACCENT, 60))
            g.setColorAt(1, QColor(0, 0, 0, 0))
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(QBrush(g))
            p.drawEllipse(c, _DOT_R * 2.8, _DOT_R * 2.8)

        p.setPen(QPen(bd, 1.3))
        p.setBrush(bg)
        p.drawEllipse(c, _DOT_R, _DOT_R)
        p.setPen(Qt.PenStyle.NoPen)
        pip = qc(ACCENT) if hov else (qc_alpha(ACCENT, 200) if bound else qc(BORDER))
        p.setBrush(pip)
        p.drawEllipse(c, 2.2, 2.2)

    # ── chip + line ───────────────────────────────────────────────────────────

    def _chip_rect(self, cy: float) -> QRectF:
        return QRectF(7, cy - _CHIP_H / 2, _LABEL_W - 16, _CHIP_H)

    def _draw_chip_line(self, p: QPainter, chip: QRectF, conn: QPointF,
                        slot: tuple, hov: bool, prefix: str = "") -> None:
        kc, combo, label = slot
        bound = bool(combo)

        if hov:
            bg, bd = _CHIP_HOV_BG, _CHIP_HOV_BD
        elif bound:
            bg, bd = _CHIP_BOUND_BG, _CHIP_BOUND_BD
        else:
            bg, bd = _CHIP_EMPTY_BG, _CHIP_EMPTY_BD

        p.setPen(QPen(bd, 1.0))
        p.setBrush(bg)
        p.drawRoundedRect(chip, _CHIP_R, _CHIP_R)

        # Text
        if combo == "__passthrough__":
            value = "pass-through"
        elif combo:
            value = label if label else _SPECIAL_LABELS.get(combo, combo)
        else:
            value = ""

        if prefix and value:
            text = f"{prefix}: {value}"
        elif prefix:
            text = f"{prefix}: click to bind"
        else:
            text = value or "click to bind"

        fnt = QFont("sans-serif", 8,
                    QFont.Weight.Bold if bound else QFont.Weight.Normal)
        p.setFont(fnt)
        p.setPen(_TXT if bound else _TXT_EMPTY)
        inner = chip.adjusted(7, 0, -42, 0)
        p.drawText(inner,
                   Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft,
                   _elide(text, fnt, int(inner.width())))

        if kc and bound:
            p.setFont(QFont("monospace", 7))
            p.setPen(_TXT_DIM)
            p.drawText(QRectF(chip.right()-44, chip.top(), 40, chip.height()),
                       Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignRight,
                       _short_keycode(kc))

        # Connector line
        col = _LINE_HOV if hov else _LINE
        p.setPen(QPen(col, 1.1, Qt.PenStyle.SolidLine,
                      Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin))
        p.setBrush(Qt.BrushStyle.NoBrush)
        cr = QPointF(chip.right() + 4, chip.center().y())
        ex = conn.x() - _DOT_R - 10
        path = QPainterPath()
        path.moveTo(cr)
        path.lineTo(ex, cr.y())
        path.lineTo(ex, conn.y())
        path.lineTo(conn.x(), conn.y())
        p.drawPath(path)

    def _draw_fallback(self, p: QPainter, tr: QRectF) -> None:
        p.setPen(QPen(qc(BORDER), 1))
        p.setBrush(qc(SURFACE))
        p.drawRoundedRect(tr, 12, 12)
        p.setPen(qc(TEXT_MUTED))
        p.drawText(tr.toRect(), Qt.AlignmentFlag.AlignCenter,
                   self._def.get("name", "Tablet"))

    def popup_geometry(self, sid: int, size: QSize) -> QRect:
        tr = self._tablet_rect()
        anchor = self._slot_anchor(sid, tr) or QPointF(tr.center())
        width = size.width()
        height = size.height()

        x = int(anchor.x() + _POPUP_GAP)
        if x + width > self.width() - 12:
            x = max(12, int(anchor.x() - _POPUP_GAP - width))

        max_y = min(self.height() - height - 12, int(tr.bottom() - height - 8))
        min_y = 12
        y = int(anchor.y() - height / 2)
        y = max(min_y, min(y, max_y))
        return QRect(x, y, width, height)

    def _slot_anchor(self, sid: int, tr: QRectF) -> Optional[QPointF]:
        for ctrl in self._controls:
            if ctrl["type"] == "button" and ctrl["id"] == sid:
                rect = self._button_rect(ctrl, tr)
                return QPointF(rect.right(), rect.center().y())
            if ctrl["type"] == "dial":
                c = self._ctrl_pt(ctrl, tr)
                outer_r = self._dial_r(ctrl, tr)
                if sid in {s["id"] for s in ctrl["slots"]}:
                    return QPointF(c.x() + outer_r * 0.25, c.y())
        return None

    # ── mouse ─────────────────────────────────────────────────────────────────

    def mouseMoveEvent(self, event) -> None:
        pos = QPointF(event.pos())
        sid = self._hit_slot(pos)
        if sid != self._hovered:
            self._hovered = sid
            self.update()
            if sid >= 0:
                name = self._slot_name(sid)
                display = self._slot_display_text(sid)
                tip = f"{name}: {display}" if display else f"{name}: unbound"
                kc = self._slot(sid)[0] if self.slot_mode(sid) != "dial_modes" else ""
                if kc:
                    tip += f"  ({kc})"
                QToolTip.showText(event.globalPosition().toPoint(), tip, self)

    def leaveEvent(self, _) -> None:
        if self._hovered != -1:
            self._hovered = -1
            self.update()

    def mousePressEvent(self, event) -> None:
        if event.button() != Qt.MouseButton.LeftButton:
            return
        sid = self._hit_slot(QPointF(event.pos()))
        if sid >= 0:
            self.slot_clicked.emit(sid)
        else:
            self.empty_clicked.emit()

    def _hit_slot(self, pos: QPointF) -> int:
        """Return the slot id under pos, or -1."""
        tr = self._tablet_rect()

        for ctrl in self._controls:
            if ctrl["type"] == "dial":
                c = self._ctrl_pt(ctrl, tr)
                outer_r = self._dial_r(ctrl, tr)
                dist = math.hypot(pos.x() - c.x(), pos.y() - c.y())
                if dist <= outer_r:
                    return ctrl["slots"][0]["id"]

        zones = self._hit_zones(tr)
        for sid, rect in zones.items():
            if rect.contains(pos):
                return sid

        return -1

    # ── helpers ───────────────────────────────────────────────────────────────

    def _slot(self, sid: int) -> tuple[str, str, str]:
        return self._slots[sid] if 0 <= sid < len(self._slots) else ("", "", "")

    def _slot_name(self, sid: int) -> str:
        for ctrl in self._controls:
            if ctrl["type"] == "button" and ctrl["id"] == sid:
                return ctrl["label"]
            if ctrl["type"] == "dial":
                if sid in {s["id"] for s in ctrl["slots"]}:
                    return ctrl["label"]
        return f"Slot {sid}"

    def slot_mode(self, sid: int) -> str:
        for ctrl in self._controls:
            if ctrl["type"] == "dial":
                for s in ctrl["slots"]:
                    if s["id"] == sid:
                        return "dial_modes"
            elif ctrl["type"] == "button" and ctrl["id"] == sid:
                return "button"
        return "button"

    def slot_members(self, sid: int) -> tuple[int, ...]:
        for ctrl in self._controls:
            if ctrl["type"] == "dial":
                ccw_id, cw_id, press_id = [s["id"] for s in ctrl["slots"]]
                if sid in {ccw_id, cw_id, press_id}:
                    return (press_id, ccw_id, cw_id)
            elif ctrl["type"] == "button" and ctrl["id"] == sid:
                return (sid,)
        return (sid,)

    def _slot_display_text(self, sid: int) -> str:
        if self.slot_mode(sid) == "dial_modes":
            _switch_id, ccw_id, _cw_id = self.slot_members(sid)
            _kc, combo, label = self._slot(ccw_id)
            if combo or label:
                return label or combo
            return ""
        kc, combo, label = self._slot(sid)
        return label or _SPECIAL_LABELS.get(combo, combo if kc or combo else "")


def _elide(text: str, font: QFont, max_px: int) -> str:
    return QFontMetrics(font).elidedText(text, Qt.TextElideMode.ElideRight, max_px)


def _short_keycode(keycode: str) -> str:
    if keycode.startswith("RAWDIAL:"):
        body = keycode.removeprefix("RAWDIAL:")
        _device, _, event = body.rpartition(":")
        return {
            "press": "PRESS",
            "pos": "D+",
            "neg": "D-",
        }.get(event, "DIAL")
    if keycode.startswith("SEQ:"):
        parts = [_short_keycode(part) for part in keycode.removeprefix("SEQ:").split("+") if part]
        if not parts:
            return "SEQ"
        if len(parts) == 1:
            return parts[0]
        return f"{parts[0]}+{len(parts) - 1}"
    if keycode.startswith("MSC_SCAN_"):
        return keycode.removeprefix("MSC_SCAN_").upper()
    return keycode.replace("KEY_", "")
