"""Tablet device detection and key remapping via evdev/uinput."""
import os
from pathlib import Path
import selectors
import threading
import time
from typing import Callable, Optional

import evdev
from evdev import AbsInfo, ecodes, UInput
try:
    import usb.core
    import usb.util
except ImportError:  # pragma: no cover - optional runtime dependency
    usb = None

from dial_actions import mode_label, mode_pair
from models import ButtonAction, Profile

# Modifier key name -> evdev keycode
_MODIFIER_MAP = {
    "ctrl": ecodes.KEY_LEFTCTRL,
    "control": ecodes.KEY_LEFTCTRL,
    "lctrl": ecodes.KEY_LEFTCTRL,
    "rctrl": ecodes.KEY_RIGHTCTRL,
    "shift": ecodes.KEY_LEFTSHIFT,
    "lshift": ecodes.KEY_LEFTSHIFT,
    "rshift": ecodes.KEY_RIGHTSHIFT,
    "alt": ecodes.KEY_LEFTALT,
    "lalt": ecodes.KEY_LEFTALT,
    "ralt": ecodes.KEY_RIGHTALT,
    "altgr": ecodes.KEY_RIGHTALT,
    "meta": ecodes.KEY_LEFTMETA,
    "super": ecodes.KEY_LEFTMETA,
    "win": ecodes.KEY_LEFTMETA,
}

_MOUSE_BUTTON_MAP = {
    "mouse_left": ecodes.BTN_LEFT,
    "mouse_right": ecodes.BTN_RIGHT,
    "mouse_middle": ecodes.BTN_MIDDLE,
    "mouse_back": ecodes.BTN_BACK,
    "mouse_forward": ecodes.BTN_FORWARD,
    "mouse_side": ecodes.BTN_SIDE,
    "mouse_extra": ecodes.BTN_EXTRA,
}

SPECIAL_ACTIONS = {
    "scroll_up",
    "scroll_down",
    "scroll_left",
    "scroll_right",
    "zoom_in",
    "zoom_out",
    # Blender: Shift+F strength adjust — uses REL_X bursts (see _emit_blender_brush_strength)
    "blender_brush_strength_ccw",
    "blender_brush_strength_cw",
}

# Re-tap Shift+F if no strength adjust for this long (Blender exits the modal).
_BLENDER_STRENGTH_SESSION_S = 1.25

_SOURCE_BURST_TIMEOUT = 0.18
_KEYBOARD_SUPPRESS_TIMEOUT = 0.25
_DIAL_MENU_TIMEOUT = 3.0
_DIAL_SWITCH_CONTEXT_WINDOW = 8.0
# Pen dual-binding: hold primary vs double-tap second hold (seconds)
# Hold commit: non-modifier primaries need a short hold vs tap; modifiers use instant hold (below).
_PEN_HOLD_COMMIT_S = 0.14
_PEN_DOUBLE_GAP_S = 0.33
# Modifier-only instant hold: release sooner than this → double-tap window (timer skips extra primary tap).
_PEN_MOD_INSTANT_MAX_HOLD_FOR_DOUBLE_S = 0.52
_RAW_DIAL_REPORT_ID = 0x11
_RAW_DIAL_DESC_MARKERS = (
    b"\x05\x01\x09\x0e",
    b"\x09\x37",
)
_VENDOR_PAD_DESC_PREFIX = b"\x06\x00\xff\x09\x01\xa1\x01\x85\x08"
_HUION_VENDOR_ID = 0x256C
_HUION_PRODUCT_ID = 0x2008
_HUION_US_ENGLISH = 0x0409
_HUION_VENDOR_DESCRIPTOR_INDEXES = (201, 200)
_HUION_VENDOR_REPORT_ID = 0x08
_HUION_VENDOR_REPORT_SUBTYPE_PEN = 0x08
_HUION_VENDOR_REPORT_SUBTYPE_PEN_OUT = 0x00
_HUION_VENDOR_BUTTONS = 0xE0
_HUION_VENDOR_WHEELS = 0xF0
_HUION_VENDOR_ENABLE = os.environ.get("AUTSWITCH_DISABLE_HUION_VENDOR") != "1"
_VENDOR_SLOT_BY_BUTTON_MASK = {
    0x01: 3,
    0x02: 4,
    0x04: 5,
    0x08: 6,
    0x10: 7,
}
_VENDOR_DIAL_BY_WHEEL_INDEX = {
    1: "0",
    2: "8",
}
_VENDOR_DIAL_BY_BUTTON_MASK = {
    0x20: "0",
    0x40: "8",
}
# Vendor report (data[1] low nibble, pen in range): which physical control each bit is.
# Evdev path (test_pen_buttons.py): BTN_TOOL_RUBBER=barrel, BTN_TOUCH=upper rocker,
# BTN_STYLUS=lower rocker — slots 11 / 12 / 13 in definitions.py.
# The HID nibble order does *not* follow low-bit-first = barrel: on Kamvas 13 Gen 3
# firmware, 0x08 is the rubber/barrel and 0x02 is the lower rocker; swapping vs
# the initial guess fixes rubber firing the "Rocker ↓" binding.
_PEN_SLOT_BY_MASK = {
    0x02: 13,
    0x04: 12,
    0x08: 11,
}
# Actual evdev codes fired by the Kamvas Gen 3 pen physical buttons.
# Confirmed via test_pen_buttons.py on hardware:
#   BTN_TOOL_RUBBER (321) = barrel button
#   BTN_TOUCH       (330) = upper rocker
#   BTN_STYLUS      (331) = lower rocker
# Note: pressing the barrel also toggles BTN_TOOL_PEN (320) — we suppress
# those tool-switch events while the barrel is held so apps don't think
# the pen left proximity.
_PEN_EVDEV_SLOT = {
    ecodes.BTN_TOOL_RUBBER: 11,  # barrel button → Barrel
    ecodes.BTN_TOUCH:        12,  # upper rocker  → Rocker ↑
    ecodes.BTN_STYLUS:       13,  # lower rocker  → Rocker ↓
}
_PEN_MAX_X = 0xE588
_PEN_MAX_Y = 0x8110
_PEN_MAX_PRESSURE = 0x3FFF
_PEN_TILT_MIN = -90
_PEN_TILT_MAX = 90
# Dial IDs assigned to raw HID devices in USB enumeration order.
# Must match the order the firmware exposes them on the dial HID interface.
_RAW_DIAL_ID_SEQUENCE = ["0", "8"]


def physical_binding_id(code: int, scan_code: Optional[int]) -> str:
    """Return a stable identifier for a physical tablet control when possible."""
    if scan_code is not None:
        return f"MSC_SCAN_{scan_code:x}"
    return keycode_name(code)


def sequence_binding_id(parts: list[str]) -> str:
    """Collapse a burst of key presses into a stable binding identifier."""
    tokens = [part for part in parts if part]
    if not tokens:
        return ""
    if len(tokens) == 1:
        return tokens[0]
    return "SEQ:" + "+".join(tokens)


def parse_key_combo(combo: str) -> tuple[list[int], Optional[int]]:
    """Parse a key combo string like 'ctrl+z' into (modifiers, key_code).

    Returns ([], None) if parsing fails.
    """
    parts = [p.strip().lower() for p in combo.split("+") if p.strip()]
    modifiers: list[int] = []
    key_code: Optional[int] = None

    for part in parts:
        if part in _MODIFIER_MAP:
            modifiers.append(_MODIFIER_MAP[part])
        elif part in _MOUSE_BUTTON_MAP:
            key_code = _MOUSE_BUTTON_MAP[part]
        else:
            # Try KEY_<name> first, then direct name
            attr = f"KEY_{part.upper()}"
            code = getattr(ecodes, attr, None)
            if code is None:
                # Try looking up by number
                try:
                    code = int(part)
                except ValueError:
                    pass
            if code is not None:
                key_code = code

    return modifiers, key_code


def combo_is_modifier_only(combo: str) -> bool:
    """True if combo is only modifier keys (e.g. ctrl, shift) — no letter/mouse key."""
    modifiers, key_code = parse_key_combo(combo.strip())
    return bool(modifiers) and key_code is None


def keycode_name(code: int) -> str:
    """Get a human-readable name for an evdev keycode."""
    names = ecodes.bytype.get(ecodes.EV_KEY, {}).get(code)
    if names is None:
        names = ecodes.KEY.get(code)
    if isinstance(names, list):
        return names[0]
    return names or f"KEY_{code}"


def parse_dial_switch_binding(binding: str) -> tuple[str, str] | None:
    if not binding.startswith("DIALSW:"):
        return None
    body = binding.removeprefix("DIALSW:")
    dial_id, sep, raw = body.partition(":")
    if not sep or not dial_id or not raw:
        return None
    return dial_id, raw


class TabletRemapper:
    """Intercepts Huion tablet express key events and remaps them per-profile."""

    TABLET_NAME_HINT = "HUION"
    KEYBOARD_HINT = "Keyboard"

    def __init__(
        self,
        get_active_profile: Callable[[], Optional[Profile]],
        on_status_change: Optional[Callable[[str], None]] = None,
        on_dial_popup: Optional[Callable[[dict], None]] = None,
    ):
        self._get_profile = get_active_profile
        self._on_status = on_status_change or (lambda _: None)
        self._on_dial_popup = on_dial_popup or (lambda _: None)
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._raw_thread: Optional[threading.Thread] = None
        self._vendor_thread: Optional[threading.Thread] = None
        self._device: Optional[evdev.InputDevice] = None
        self._uinput: Optional[UInput] = None
        self._pen_uinput: Optional[UInput] = None
        self._capture_cb: Optional[Callable[[str], None]] = None
        self._lock = threading.Lock()
        self._last_scan_code: Optional[int] = None
        self._dial_mode_index: dict[tuple[str, str], int] = {}
        self._capture_presses: list[str] = []
        self._capture_pressed_codes: dict[int, int] = {}
        self._capture_last_event_at = 0.0
        self._pending_events: list[tuple[int, int]] = []
        self._pending_press_ids: list[str] = []
        self._pending_press_names: list[str] = []
        self._pending_pressed_codes: dict[int, int] = {}
        self._pending_last_event_at = 0.0
        self._raw_button_active: dict[str, bool] = {}
        self._suppress_keyboard_until = 0.0
        self._dial_menu_deadline: dict[tuple[str, str], float] = {}
        self._dial_last_active_at: dict[tuple[str, str], float] = {}
        self._vendor_button_state = 0
        self._vendor_recent_until = 0.0
        self._vendor_mode_warned = False
        self._vendor_mode_switched = False
        self._last_ambiguous_notice_at = 0.0
        self._last_pen_switch_bits = 0
        self._pen_thread: Optional[threading.Thread] = None
        self._blender_strength_last_at = 0.0
        # slot_id -> {phase, t_down, ...} for pen buttons with keys_double
        self._pen_dual_fsm: dict[int, dict[str, object]] = {}
        self._pen_fsm_lock = threading.RLock()
        self._pen_await_timers: dict[int, threading.Timer] = {}
        # evdev pen: last physical down per slot (vendor uses _last_pen_switch_bits)
        self._pen_evdev_pressed: dict[int, bool] = {}

    # ------------------------------------------------------------------ public

    def start(self) -> None:
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True, name="tablet-remapper-kbd")
        self._thread.start()
        self._raw_thread = threading.Thread(
            target=self._run_raw_dials,
            daemon=True,
            name="tablet-remapper-raw",
        )
        self._raw_thread.start()
        self._vendor_thread = threading.Thread(
            target=self._run_vendor_pad,
            daemon=True,
            name="tablet-remapper-vendor",
        )
        self._vendor_thread.start()
        self._pen_thread = threading.Thread(
            target=self._run_pen_evdev,
            daemon=True,
            name="tablet-remapper-pen",
        )
        self._pen_thread.start()

    def stop(self) -> None:
        self._running = False
        with self._pen_fsm_lock:
            for sid in list(self._pen_await_timers.keys()):
                self._cancel_pen_await_timer(sid)
        self._restore_firmware_mode()
        self._ungrab()

    def set_capture_mode(self, callback: Optional[Callable[[str], None]]) -> None:
        """Enable capture mode. callback receives a stable button burst identifier."""
        with self._lock:
            self._capture_cb = callback
        if callback is None:
            self._clear_capture_state()

    def set_dial_mode_selection(self, app_class: str, dial_id: str, selected_index: int) -> None:
        profile = self._get_profile()
        if not profile or profile.app_class != app_class:
            return
        dial = profile.dials.get(dial_id)
        if not dial:
            return
        modes = [mode for mode in dial.modes if mode]
        if not modes:
            return
        idx = int(selected_index) % len(modes)
        state_key = (app_class, dial_id)
        with self._lock:
            self._dial_mode_index[state_key] = idx
            self._dial_menu_deadline[state_key] = 0.0
            self._dial_last_active_at[state_key] = time.monotonic()
        self._on_status(f"{profile.app_name}: {dial.label or 'Dial'} → {mode_label(modes[idx])}")

    @property
    def is_running(self) -> bool:
        return self._running and any(
            thread is not None and thread.is_alive()
            for thread in (self._thread, self._raw_thread)
        )

    # ----------------------------------------------------------------- private

    def _find_tablet_keyboard(self) -> Optional[evdev.InputDevice]:
        for path in evdev.list_devices():
            try:
                dev = evdev.InputDevice(path)
                if self.TABLET_NAME_HINT in dev.name.upper() and self.KEYBOARD_HINT in dev.name:
                    return dev
            except (PermissionError, OSError):
                pass
        return None

    def _find_raw_dial_devices(self) -> list[tuple[str, str]]:
        """Return (dial_id, path) pairs for raw HID dial interfaces.

        Dial IDs are assigned in USB enumeration order using _RAW_DIAL_ID_SEQUENCE
        so they align with the profile dial configs ("0", "8").
        """
        found: list[tuple[str, str]] = []  # (interface_key, path) for ordering
        hidraw_root = Path("/sys/class/hidraw")
        if not hidraw_root.exists():
            return found

        for hidraw in sorted(hidraw_root.glob("hidraw*")):
            try:
                uevent = (hidraw / "device" / "uevent").read_text()
                desc = (hidraw / "device" / "report_descriptor").read_bytes()
            except OSError:
                continue

            if "HID_NAME=HUION" not in uevent.upper():
                continue
            if not all(marker in desc for marker in _RAW_DIAL_DESC_MARKERS):
                continue

            device_dir = (hidraw / "device").resolve()
            interface_key = hidraw.name
            for parent in device_dir.parents:
                if ":1." in parent.name:
                    interface_key = parent.name.replace(":", "_")
                    break
            found.append((interface_key, f"/dev/{hidraw.name}"))

        # Assign known dial IDs in enumeration order so events match profile configs.
        devices: list[tuple[str, str]] = []
        for idx, (_, path) in enumerate(found):
            dial_id = _RAW_DIAL_ID_SEQUENCE[idx] if idx < len(_RAW_DIAL_ID_SEQUENCE) else str(idx)
            devices.append((dial_id, path))
        return devices

    def _find_vendor_pad_devices(self) -> list[str]:
        devices: list[str] = []
        hidraw_root = Path("/sys/class/hidraw")
        if not hidraw_root.exists():
            return devices

        for hidraw in sorted(hidraw_root.glob("hidraw*")):
            try:
                uevent = (hidraw / "device" / "uevent").read_text()
                desc = (hidraw / "device" / "report_descriptor").read_bytes()
            except OSError:
                continue

            if f"HID_ID=0003:{_HUION_VENDOR_ID:08X}:{_HUION_PRODUCT_ID:08X}" not in uevent.upper():
                continue
            if not desc.startswith(_VENDOR_PAD_DESC_PREFIX):
                continue
            devices.append(f"/dev/{hidraw.name}")
        return devices

    def _ungrab(self) -> None:
        if self._device:
            try:
                self._device.ungrab()
            except Exception:
                pass
            self._device = None
        if self._uinput:
            try:
                self._uinput.close()
            except Exception:
                pass
            self._uinput = None
        if self._pen_uinput:
            try:
                self._pen_uinput.close()
            except Exception:
                pass
            self._pen_uinput = None

    def _ensure_pen_uinput(self) -> bool:
        if self._pen_uinput is not None:
            return True
        caps = {
            ecodes.EV_KEY: [
                ecodes.BTN_TOOL_PEN,
                ecodes.BTN_TOUCH,
                ecodes.BTN_STYLUS,
                ecodes.BTN_STYLUS2,
                ecodes.BTN_STYLUS3,
            ],
            ecodes.EV_ABS: [
                (ecodes.ABS_X, AbsInfo(value=0, min=0, max=_PEN_MAX_X, fuzz=0, flat=0, resolution=0)),
                (ecodes.ABS_Y, AbsInfo(value=0, min=0, max=_PEN_MAX_Y, fuzz=0, flat=0, resolution=0)),
                (ecodes.ABS_PRESSURE, AbsInfo(value=0, min=0, max=_PEN_MAX_PRESSURE, fuzz=0, flat=0, resolution=0)),
                (ecodes.ABS_TILT_X, AbsInfo(value=0, min=_PEN_TILT_MIN, max=_PEN_TILT_MAX, fuzz=0, flat=0, resolution=0)),
                (ecodes.ABS_TILT_Y, AbsInfo(value=0, min=_PEN_TILT_MIN, max=_PEN_TILT_MAX, fuzz=0, flat=0, resolution=0)),
            ],
        }
        try:
            self._pen_uinput = UInput(
                caps,
                name="autswitch-virtual-pen",
                version=0x3,
                vendor=_HUION_VENDOR_ID,
                product=_HUION_PRODUCT_ID,
                bustype=0x03,
            )
            return True
        except Exception as exc:
            self._on_status(f"virtual pen error: {exc}")
            self._pen_uinput = None
            return False

    def _switch_to_vendor_mode(self) -> bool:
        if usb is None or self._vendor_mode_switched:
            return self._vendor_mode_switched
        try:
            device = usb.core.find(idVendor=_HUION_VENDOR_ID, idProduct=_HUION_PRODUCT_ID)
            if device is None:
                return False
            for index in _HUION_VENDOR_DESCRIPTOR_INDEXES:
                device.ctrl_transfer(
                    0x80,
                    0x06,
                    (0x03 << 8) | index,
                    _HUION_US_ENGLISH,
                    255,
                    timeout=250,
                )
            usb.util.dispose_resources(device)
            self._vendor_mode_switched = True
            self._on_status("Kamvas vendor mode active.")
            return True
        except Exception as exc:
            if not self._vendor_mode_warned:
                self._on_status(f"Huion vendor mode switch failed: {exc}")
                self._vendor_mode_warned = True
            return False

    def _restore_firmware_mode(self) -> None:
        if usb is None or not self._vendor_mode_switched:
            return
        try:
            device = usb.core.find(idVendor=_HUION_VENDOR_ID, idProduct=_HUION_PRODUCT_ID)
            if device is not None:
                device.reset()
                usb.util.dispose_resources(device)
        except Exception:
            pass
        self._vendor_mode_switched = False

    def _run(self) -> None:
        while self._running:
            dev = self._find_tablet_keyboard()
            if not dev:
                self._on_status("Tablet not found – waiting...")
                time.sleep(2)
                continue

            # Virtual output supports keyboard shortcuts and wheel actions.
            caps = {
                ecodes.EV_KEY: list(range(1, 256)) + [
                    ecodes.KEY_PLAYPAUSE,
                    ecodes.BTN_LEFT,
                    ecodes.BTN_RIGHT,
                    ecodes.BTN_MIDDLE,
                    ecodes.BTN_SIDE,
                    ecodes.BTN_EXTRA,
                    ecodes.BTN_BACK,
                    ecodes.BTN_FORWARD,
                ],
                ecodes.EV_REL: [
                    ecodes.REL_X,
                    ecodes.REL_Y,
                    ecodes.REL_WHEEL,
                    ecodes.REL_HWHEEL,
                ],
            }
            try:
                ui = UInput(caps, name="autswitch-virtual-kb", version=0x3)
            except Exception as e:
                self._on_status(f"uinput error: {e}")
                time.sleep(2)
                continue

            self._device = dev
            self._uinput = ui

            try:
                dev.grab()
                self._on_status(f"Active – remapping {dev.name}")
                for event in dev.read_loop():
                    if not self._running:
                        break
                    self._flush_stale_state(time.monotonic())
                    if event.type == ecodes.EV_MSC and event.code == ecodes.MSC_SCAN:
                        self._last_scan_code = event.value
                    elif event.type == ecodes.EV_KEY:
                        self._handle(event, self._last_scan_code)
                        self._last_scan_code = None
            except OSError as e:
                self._on_status(f"Device error: {e}")
            finally:
                self._flush_pending_burst(force=True)
                self._clear_capture_state()
                self._ungrab()

            if self._running:
                time.sleep(1)

    def _handle(self, event: evdev.events.InputEvent, scan_code: Optional[int]) -> None:
        if time.monotonic() < max(self._suppress_keyboard_until, self._vendor_recent_until):
            self._clear_pending_burst()
            return

        code = event.code
        value = event.value  # 0=up, 1=down, 2=repeat
        name = keycode_name(code)
        binding_id = physical_binding_id(code, scan_code)

        with self._lock:
            cb = self._capture_cb
        if cb is not None:
            self._record_capture_event(code, value, binding_id)
            return

        self._record_source_event(code, value, binding_id, name)

    def _run_vendor_pad(self) -> None:
        if not _HUION_VENDOR_ENABLE:
            return

        while self._running:
            self._ensure_pen_uinput()
            if not self._vendor_mode_switched:
                if self._switch_to_vendor_mode():
                    time.sleep(0.25)
            vendor_devices = self._find_vendor_pad_devices()
            if not vendor_devices:
                time.sleep(2)
                continue

            selector = selectors.DefaultSelector()
            opened: list[int] = []
            try:
                self._vendor_button_state = 0
                for device_path in vendor_devices:
                    fd = os.open(device_path, os.O_RDONLY | os.O_NONBLOCK)
                    opened.append(fd)
                    selector.register(fd, selectors.EVENT_READ, device_path)

                while self._running:
                    for key, _ in selector.select(timeout=0.25):
                        try:
                            data = os.read(key.fd, 64)
                        except BlockingIOError:
                            continue
                        except OSError:
                            data = b""
                        if data:
                            self._handle_vendor_report(data)
            except Exception as exc:
                if not self._vendor_mode_warned:
                    self._on_status(f"Huion vendor dial path unavailable: {exc}")
                    self._vendor_mode_warned = True
            finally:
                try:
                    selector.close()
                except Exception:
                    pass
                for fd in opened:
                    try:
                        os.close(fd)
                    except OSError:
                        pass

            if self._running:
                time.sleep(2)

    def _handle_vendor_report(self, data: bytes) -> None:
        if len(data) < 6 or data[0] != _HUION_VENDOR_REPORT_ID:
            return

        report_subtype = (data[1] >> 4) & 0x0F
        if report_subtype in {_HUION_VENDOR_REPORT_SUBTYPE_PEN, _HUION_VENDOR_REPORT_SUBTYPE_PEN_OUT}:
            self._handle_vendor_pen(data, in_range=(report_subtype == _HUION_VENDOR_REPORT_SUBTYPE_PEN))
            return

        subtype = data[1] & 0xF0
        if subtype == _HUION_VENDOR_BUTTONS:
            self._handle_vendor_buttons(data[4])
            return
        if subtype == _HUION_VENDOR_WHEELS:
            dial_id = _VENDOR_DIAL_BY_WHEEL_INDEX.get(data[3])
            direction = {1: "cw", 2: "ccw"}.get(data[5])
            if dial_id and direction:
                self._dispatch_vendor_binding(f"VENDORDIAL:{dial_id}:{direction}")

    def _handle_vendor_buttons(self, buttons: int) -> None:
        buttons &= 0x7F
        prev = self._vendor_button_state
        if buttons == prev:
            return

        profile = self._get_profile()
        with self._lock:
            capture_active = self._capture_cb is not None

        # Capture: first new express-key press wins (same as legacy behavior).
        for mask, slot_id in _VENDOR_SLOT_BY_BUTTON_MASK.items():
            pressed_b = bool(buttons & mask)
            was_pressed = bool(prev & mask)
            if pressed_b and not was_pressed:
                if capture_active:
                    self._vendor_button_state = buttons
                    self._dispatch_vendor_binding(f"VENDORBTN:{slot_id}")
                    return

        # Dial center: edge down only
        pressed_new = buttons & ~prev
        for mask, dial_id in _VENDOR_DIAL_BY_BUTTON_MASK.items():
            if pressed_new & mask:
                self._dispatch_vendor_binding(f"VENDORDIAL:{dial_id}:press")

        # Suppress physical keyboard routing while express keys change (once per report)
        any_express_edge = False
        for mask, slot_id in _VENDOR_SLOT_BY_BUTTON_MASK.items():
            pressed_b = bool(buttons & mask)
            was_pressed = bool(prev & mask)
            if pressed_b != was_pressed:
                any_express_edge = True
                break
        if any_express_edge:
            now = time.monotonic()
            self._vendor_recent_until = now + _KEYBOARD_SUPPRESS_TIMEOUT
            self._suppress_keyboard_until = now + _KEYBOARD_SUPPRESS_TIMEOUT

        for mask, slot_id in _VENDOR_SLOT_BY_BUTTON_MASK.items():
            pressed_b = bool(buttons & mask)
            was_pressed = bool(prev & mask)
            if not pressed_b and not was_pressed:
                continue
            edge_down = pressed_b and not was_pressed
            edge_up = not pressed_b and was_pressed

            if profile is None:
                continue
            _kc, action = profile.get_slot(slot_id)
            if action is None or action.passthrough:
                continue
            kd = (getattr(action, "keys_double", "") or "").strip()
            if kd:
                self._handle_pen_dual_fsm(
                    slot_id,
                    action,
                    pressed=pressed_b,
                    was_pressed=was_pressed,
                    edge_down=edge_down,
                    edge_up=edge_up,
                )
            elif edge_down:
                self._emit_action(action.keys, 1)

        self._vendor_button_state = buttons

    def _dispatch_vendor_binding(self, binding_id: str) -> None:
        now = time.monotonic()
        self._vendor_recent_until = now + _KEYBOARD_SUPPRESS_TIMEOUT
        self._suppress_keyboard_until = now + _KEYBOARD_SUPPRESS_TIMEOUT

        with self._lock:
            cb = self._capture_cb
            if cb is not None:
                self._capture_cb = None
        if cb is not None:
            self._clear_capture_state()
            cb(binding_id)
            return

        profile = self._get_profile()
        if not profile:
            return

        if binding_id.startswith("VENDORDIAL:"):
            _, dial_id, part = binding_id.split(":", 2)
            if dial_id in profile.dials:
                self._handle_dial_match(profile, (dial_id, "switch" if part == "press" else part))
            return

        action = self._match_button_action(profile, binding_id, [binding_id], [])
        if action is not None and not action.passthrough:
            self._emit_action(action.keys, 1)

    def _handle_vendor_pen(self, data: bytes, in_range: bool) -> None:
        if len(data) < 12:
            return

        profile = self._get_profile()
        bits = (data[1] & 0x0F) if in_range else 0
        suppressed_mask = 0
        for mask, slot_id in _PEN_SLOT_BY_MASK.items():
            pressed = bool(bits & mask)
            was_pressed = bool(self._last_pen_switch_bits & mask)
            if not pressed and not was_pressed:
                continue

            edge_down = pressed and not was_pressed
            edge_up = not pressed and was_pressed

            with self._lock:
                capture_active = self._capture_cb is not None
            if capture_active and edge_down:
                suppressed_mask |= mask
                self._dispatch_pen_binding(mask)
                continue

            if profile is not None:
                _keycode, action = profile.get_slot(slot_id)
                if action is not None and not action.passthrough:
                    suppressed_mask |= mask
                    kd = (getattr(action, "keys_double", "") or "").strip()
                    if kd:
                        self._handle_pen_dual_fsm(
                            slot_id,
                            action,
                            pressed=pressed,
                            was_pressed=was_pressed,
                            edge_down=edge_down,
                            edge_up=edge_up,
                        )
                    else:
                        if edge_down:
                            self._emit_action(action.keys, 1)
                    continue

            if edge_down:
                self._dispatch_pen_binding(mask)

        self._last_pen_switch_bits = bits

        x = int.from_bytes(data[2:4], "little")
        y = int.from_bytes(data[4:6], "little")
        pressure = int.from_bytes(data[6:8], "little")
        tilt_x = int.from_bytes(data[10:11], "little", signed=True)
        tilt_y = -int.from_bytes(data[11:12], "little", signed=True)
        self._emit_pen_state(
            in_range=in_range,
            x=x,
            y=y,
            pressure=pressure if (bits & 0x01) else 0,
            tilt_x=tilt_x,
            tilt_y=tilt_y,
            tip=bool(bits & 0x01),
            side1=bool(bits & 0x02 and not suppressed_mask & 0x02),
            side2=bool(bits & 0x04 and not suppressed_mask & 0x04),
            side3=bool(bits & 0x08 and not suppressed_mask & 0x08),
        )

    def _find_pen_device(self) -> Optional[evdev.InputDevice]:
        for path in evdev.list_devices():
            try:
                dev = evdev.InputDevice(path)
                caps = dev.capabilities()
                if (
                    self.TABLET_NAME_HINT in dev.name.upper()
                    and self.KEYBOARD_HINT not in dev.name
                    and ecodes.BTN_STYLUS in caps.get(ecodes.EV_KEY, [])
                ):
                    return dev
            except (PermissionError, OSError):
                pass
        return None

    def _run_pen_evdev(self) -> None:
        """Evdev fallback for pen buttons when vendor HID path is unavailable."""
        while self._running:
            # Vendor path already handles pen buttons when active; skip.
            if self._vendor_mode_switched:
                time.sleep(2)
                continue
            dev = self._find_pen_device()
            if not dev:
                time.sleep(2)
                continue
            self._ensure_pen_uinput()
            try:
                dev.grab()
                barrel_held = False
                for event in dev.read_loop():
                    if not self._running:
                        break
                    ui = self._pen_uinput
                    if ui is None:
                        continue
                    # Pen button events are handled entirely by autswitch —
                    # never forwarded to the virtual pen so Wayland/apps
                    # don't see raw stylus button codes.
                    if (
                        event.type == ecodes.EV_KEY
                        and event.code in _PEN_EVDEV_SLOT
                    ):
                        if event.code == ecodes.BTN_TOOL_RUBBER:
                            barrel_held = event.value == 1
                        slot_id = _PEN_EVDEV_SLOT[event.code]
                        pressed = event.value == 1
                        was_pressed = self._pen_evdev_pressed.get(slot_id, False)
                        edge_down = pressed and not was_pressed
                        edge_up = not pressed and was_pressed
                        self._pen_evdev_pressed[slot_id] = pressed

                        with self._lock:
                            cb = self._capture_cb
                            if cb is not None:
                                self._capture_cb = None
                        if cb is not None and edge_down:
                            self._clear_capture_state()
                            cb(f"PENBTN:{slot_id - 10}")
                            continue
                        profile = self._get_profile()
                        if profile is not None:
                            _, action = profile.get_slot(slot_id)
                            if action is not None and not action.passthrough:
                                kd = (getattr(action, "keys_double", "") or "").strip()
                                if kd:
                                    self._handle_pen_dual_fsm(
                                        slot_id,
                                        action,
                                        pressed=pressed,
                                        was_pressed=was_pressed,
                                        edge_down=edge_down,
                                        edge_up=edge_up,
                                    )
                                elif edge_down:
                                    self._emit_action(action.keys, 1)
                        # Drop both press and release — never reach uinput
                        continue
                    # Suppress BTN_TOOL_PEN tool-switch events that pair with
                    # the barrel button so apps don't think the pen left proximity.
                    if (
                        barrel_held
                        and event.type == ecodes.EV_KEY
                        and event.code == ecodes.BTN_TOOL_PEN
                    ):
                        continue
                    # Forward everything else through pen uinput unchanged
                    try:
                        ui.write(event.type, event.code, event.value)
                        if event.type == ecodes.EV_SYN:
                            ui.syn()
                    except OSError:
                        break
            except OSError:
                pass
            finally:
                try:
                    dev.ungrab()
                except Exception:
                    pass
            if self._running:
                time.sleep(1)

    def _dispatch_pen_binding(self, mask: int) -> None:
        slot_id = _PEN_SLOT_BY_MASK.get(mask)
        if slot_id is None:
            return
        binding_id = f"PENBTN:{slot_id - 10}"
        with self._lock:
            cb = self._capture_cb
            if cb is not None:
                self._capture_cb = None
        if cb is not None:
            self._clear_capture_state()
            cb(binding_id)

    def _emit_pen_state(
        self,
        *,
        in_range: bool,
        x: int,
        y: int,
        pressure: int,
        tilt_x: int,
        tilt_y: int,
        tip: bool,
        side1: bool,
        side2: bool,
        side3: bool,
    ) -> None:
        ui = self._pen_uinput
        if ui is None:
            return

        ui.write(ecodes.EV_ABS, ecodes.ABS_X, x)
        ui.write(ecodes.EV_ABS, ecodes.ABS_Y, y)
        ui.write(ecodes.EV_ABS, ecodes.ABS_PRESSURE, pressure if in_range else 0)
        ui.write(ecodes.EV_ABS, ecodes.ABS_TILT_X, tilt_x)
        ui.write(ecodes.EV_ABS, ecodes.ABS_TILT_Y, tilt_y)
        ui.write(ecodes.EV_KEY, ecodes.BTN_TOOL_PEN, 1 if in_range else 0)
        ui.write(ecodes.EV_KEY, ecodes.BTN_TOUCH, 1 if (in_range and tip) else 0)
        ui.write(ecodes.EV_KEY, ecodes.BTN_STYLUS, 1 if (in_range and side1) else 0)
        ui.write(ecodes.EV_KEY, ecodes.BTN_STYLUS2, 1 if (in_range and side2) else 0)
        ui.write(ecodes.EV_KEY, ecodes.BTN_STYLUS3, 1 if (in_range and side3) else 0)
        ui.syn()

    def _run_raw_dials(self) -> None:
        while self._running:
            raw_devices = self._find_raw_dial_devices()
            if not raw_devices:
                time.sleep(2)
                continue

            selector = selectors.DefaultSelector()
            opened: list[int] = []
            try:
                for dial_id, device_path in raw_devices:
                    fd = os.open(device_path, os.O_RDONLY | os.O_NONBLOCK)
                    opened.append(fd)
                    selector.register(fd, selectors.EVENT_READ, dial_id)
                    self._raw_button_active.setdefault(dial_id, False)

                while self._running:
                    for key, _ in selector.select(timeout=0.25):
                        try:
                            data = os.read(key.fd, 64)
                        except BlockingIOError:
                            continue
                        except OSError:
                            data = b""
                        if data:
                            self._handle_raw_report(key.data, data)
            except OSError:
                pass
            finally:
                try:
                    selector.close()
                except Exception:
                    pass
                for fd in opened:
                    try:
                        os.close(fd)
                    except OSError:
                        pass
                self._raw_button_active.clear()

            if self._running:
                time.sleep(1)

    def _handle_raw_report(self, dial_id: str, data: bytes) -> None:
        if len(data) < 4 or data[0] != _RAW_DIAL_REPORT_ID:
            return

        flags = data[1]
        delta = int.from_bytes(data[2:4], "little", signed=True)

        # Center button press: raw HID cannot distinguish upper from lower dial
        # (both produce identical bytes). Fire the shared switch binding once —
        # the heuristic in _resolve_switch_match picks the right dial.
        if flags and delta == 0:
            if not self._raw_button_active.get(dial_id, False):
                self._raw_button_active[dial_id] = True
                self._handle_raw_binding("VENDORDIAL:0:press")
            return

        if flags == 0:
            self._raw_button_active[dial_id] = False

        if delta > 0:
            self._handle_raw_binding(f"VENDORDIAL:{dial_id}:cw")
        elif delta < 0:
            self._handle_raw_binding(f"VENDORDIAL:{dial_id}:ccw")

    def _handle_raw_binding(self, binding_id: str) -> None:
        if time.monotonic() < self._vendor_recent_until:
            return
        self._suppress_keyboard_until = time.monotonic() + _KEYBOARD_SUPPRESS_TIMEOUT

        with self._lock:
            cb = self._capture_cb
            if cb is not None:
                self._capture_cb = None
        if cb is not None:
            self._clear_capture_state()
            cb(binding_id)
            return

        profile = self._get_profile()
        if not profile:
            return

        dial_match = self._match_dial_event(profile, binding_id, [binding_id], [])
        if dial_match is not None:
            self._handle_dial_match(profile, dial_match)
            return

        action = self._match_button_action(profile, binding_id, [binding_id], [])
        if action is not None and not action.passthrough:
            self._emit_action(action.keys, 1)

    def _flush_stale_state(self, now: float) -> None:
        if (
            self._capture_presses
            and self._capture_last_event_at
            and now - self._capture_last_event_at > _SOURCE_BURST_TIMEOUT
        ):
            self._finish_capture()
        if (
            self._pending_events
            and self._pending_last_event_at
            and now - self._pending_last_event_at > _SOURCE_BURST_TIMEOUT
        ):
            self._flush_pending_burst(force=True)

    def _record_capture_event(self, code: int, value: int, binding_id: str) -> None:
        self._capture_last_event_at = time.monotonic()
        self._update_pressed_codes(self._capture_pressed_codes, code, value)
        if value == 1:
            self._append_press(self._capture_presses, binding_id)
        if self._capture_presses and not self._capture_pressed_codes:
            self._finish_capture()

    def _finish_capture(self) -> None:
        binding = sequence_binding_id(self._capture_presses)
        self._clear_capture_state()
        if not binding:
            return
        with self._lock:
            cb = self._capture_cb
            self._capture_cb = None
        if cb is not None:
            cb(binding)

    def _clear_capture_state(self) -> None:
        self._capture_presses.clear()
        self._capture_pressed_codes.clear()
        self._capture_last_event_at = 0.0

    def _record_source_event(self, code: int, value: int, binding_id: str, name: str) -> None:
        self._pending_last_event_at = time.monotonic()
        self._pending_events.append((code, value))
        self._update_pressed_codes(self._pending_pressed_codes, code, value)
        if value == 1:
            self._append_press(self._pending_press_ids, binding_id)
            self._append_press(self._pending_press_names, name)
        if self._pending_press_ids and not self._pending_pressed_codes:
            self._flush_pending_burst(force=True)

    def _flush_pending_burst(self, force: bool = False) -> None:
        if not self._pending_events:
            return
        if not force and self._pending_pressed_codes:
            return

        events = list(self._pending_events)
        press_ids = list(self._pending_press_ids)
        press_names = list(self._pending_press_names)
        self._clear_pending_burst()
        if not press_ids:
            return

        profile = self._get_profile()
        sequence_id = sequence_binding_id(press_ids)
        if profile:
            dial_match = self._match_dial_event(profile, sequence_id, press_ids, press_names)
            if dial_match is not None:
                self._handle_dial_match(profile, dial_match)
                return

            action = self._match_button_action(profile, sequence_id, press_ids, press_names)
            if action is not None:
                if action.passthrough:
                    self._forward_raw_events(events)
                else:
                    self._emit_action(action.keys, 1)
                return

        self._forward_raw_events(events)

    def _clear_pending_burst(self) -> None:
        self._pending_events.clear()
        self._pending_press_ids.clear()
        self._pending_press_names.clear()
        self._pending_pressed_codes.clear()
        self._pending_last_event_at = 0.0

    def _forward_raw_events(self, events: list[tuple[int, int]]) -> None:
        for code, value in events:
            self._emit_raw(code, value)

    def _append_press(self, target: list[str], binding: str) -> None:
        if not binding:
            return
        if not target or target[-1] != binding:
            target.append(binding)

    def _update_pressed_codes(self, pressed: dict[int, int], code: int, value: int) -> None:
        if value == 1:
            pressed[code] = pressed.get(code, 0) + 1
        elif value == 0:
            count = pressed.get(code, 0)
            if count <= 1:
                pressed.pop(code, None)
            else:
                pressed[code] = count - 1

    def _emit_raw(self, code: int, value: int) -> None:
        if self._uinput:
            self._uinput.write(ecodes.EV_KEY, code, value)
            self._uinput.syn()

    def _emit_action(self, action: str, value: int) -> None:
        normalized = action.strip().lower()
        if normalized in SPECIAL_ACTIONS:
            self._emit_special_action(normalized, value)
            return
        if value in (1, 2):
            self._tap_combo(action)

    def _emit_special_action(self, action: str, value: int) -> None:
        if not self._uinput or value not in (1, 2):
            return

        action = action.strip().lower()
        if action == "scroll_up":
            self._emit_wheel(1)
        elif action == "scroll_down":
            self._emit_wheel(-1)
        elif action == "scroll_left":
            self._emit_hwheel(-1)
        elif action == "scroll_right":
            self._emit_hwheel(1)
        elif action == "zoom_in":
            self._emit_zoom(1)
        elif action == "zoom_out":
            self._emit_zoom(-1)
        elif action == "blender_brush_strength_ccw":
            self._emit_blender_brush_strength(-1)
        elif action == "blender_brush_strength_cw":
            self._emit_blender_brush_strength(1)

    def _emit_blender_brush_strength(self, direction: int) -> None:
        """Emulate Blender Shift+F strength adjust: modal + mouse delta (see REL_*)."""
        if not self._uinput:
            return
        now = time.monotonic()
        ui = self._uinput
        if now - self._blender_strength_last_at > _BLENDER_STRENGTH_SESSION_S:
            self._tap_combo("shift+f")
        self._blender_strength_last_at = now
        rel_axis = ecodes.REL_Y if os.environ.get(
            "AUTSWITCH_BLENDER_STRENGTH_AXIS", ""
        ).lower() in ("y", "vertical", "vert") else ecodes.REL_X
        step = 14
        for _ in range(3):
            ui.write(ecodes.EV_REL, rel_axis, direction * step)
            ui.syn()

    def _emit_wheel(self, amount: int) -> None:
        if not self._uinput:
            return
        self._uinput.write(ecodes.EV_REL, ecodes.REL_WHEEL, amount)
        self._uinput.syn()

    def _emit_hwheel(self, amount: int) -> None:
        if not self._uinput:
            return
        self._uinput.write(ecodes.EV_REL, ecodes.REL_HWHEEL, amount)
        self._uinput.syn()

    def _emit_zoom(self, amount: int) -> None:
        if not self._uinput:
            return
        ui = self._uinput
        ui.write(ecodes.EV_KEY, ecodes.KEY_LEFTCTRL, 1)
        ui.syn()
        ui.write(ecodes.EV_REL, ecodes.REL_WHEEL, amount)
        ui.syn()
        ui.write(ecodes.EV_KEY, ecodes.KEY_LEFTCTRL, 0)
        ui.syn()

    def _tap_combo(self, combo: str) -> None:
        if not self._uinput:
            return
        modifiers, key_code = parse_key_combo(combo)
        if key_code is None:
            return
        ui = self._uinput
        for mod in modifiers:
            ui.write(ecodes.EV_KEY, mod, 1)
        ui.write(ecodes.EV_KEY, key_code, 1)
        ui.syn()
        ui.write(ecodes.EV_KEY, key_code, 0)
        for mod in reversed(modifiers):
            ui.write(ecodes.EV_KEY, mod, 0)
        ui.syn()

    def _press_keys_hold(self, combo: str) -> None:
        if not self._uinput:
            return
        modifiers, key_code = parse_key_combo(combo)
        if not modifiers and key_code is None:
            return
        ui = self._uinput
        for mod in modifiers:
            ui.write(ecodes.EV_KEY, mod, 1)
        if key_code is not None:
            ui.write(ecodes.EV_KEY, key_code, 1)
        ui.syn()

    def _release_keys_hold(self, combo: str) -> None:
        if not self._uinput:
            return
        modifiers, key_code = parse_key_combo(combo)
        if not modifiers and key_code is None:
            return
        ui = self._uinput
        if key_code is not None:
            ui.write(ecodes.EV_KEY, key_code, 0)
        for mod in reversed(modifiers):
            ui.write(ecodes.EV_KEY, mod, 0)
        ui.syn()

    def _cancel_pen_await_timer(self, slot_id: int) -> None:
        t = self._pen_await_timers.pop(slot_id, None)
        if t is not None:
            try:
                t.cancel()
            except Exception:
                pass

    def _schedule_pen_await_timer(self, slot_id: int, await_gen: int) -> None:
        """Fire primary tap after _PEN_DOUBLE_GAP_S if still in await_dbl (same generation).

        Without this, await_dbl never expires when no pen events arrive while the
        button is idle (vendor loop skips the slot; evdev has no events).
        """
        self._cancel_pen_await_timer(slot_id)

        def fire() -> None:
            with self._pen_fsm_lock:
                if not self._running:
                    self._pen_await_timers.pop(slot_id, None)
                    return
                self._pen_await_timers.pop(slot_id, None)
                st = self._pen_dual_fsm.get(slot_id)
                if not st or str(st.get("phase")) != "await_dbl":
                    return
                if int(st.get("await_gen", -1)) != await_gen:
                    return
                profile = self._get_profile()
                if profile is None:
                    self._pen_dual_fsm.pop(slot_id, None)
                    return
                _kc, act = profile.get_slot(slot_id)
                if act is None:
                    self._pen_dual_fsm.pop(slot_id, None)
                    return
                tap = (act.keys or "").strip()
                kd2 = (getattr(act, "keys_double", "") or "").strip()
                if not tap or not kd2:
                    self._pen_dual_fsm.pop(slot_id, None)
                    return
                if st.get("await_skip_primary_tap"):
                    # Modifier-only instant path already sent down+up; only wait for 2nd press or idle.
                    self._pen_dual_fsm[slot_id] = {"phase": "idle"}
                    return
                self._emit_action(tap, 1)
                self._pen_dual_fsm[slot_id] = {"phase": "idle"}

        timer = threading.Timer(_PEN_DOUBLE_GAP_S, fire)
        timer.daemon = True
        timer.start()
        self._pen_await_timers[slot_id] = timer

    def _pen_dual_reset_slot(self, slot_id: int) -> None:
        with self._pen_fsm_lock:
            self._cancel_pen_await_timer(slot_id)
            self._pen_dual_fsm.pop(slot_id, None)

    def _handle_pen_dual_fsm(
        self,
        slot_id: int,
        action: ButtonAction,
        *,
        pressed: bool,
        was_pressed: bool,
        edge_down: bool,
        edge_up: bool,
    ) -> None:
        """Dual binding (keys_double): pen side buttons and vendor express keys — hold / tap / second hold."""
        ks = (action.keys or "").strip()
        kd = (getattr(action, "keys_double", "") or "").strip()
        if not kd:
            if edge_down:
                self._emit_action(action.keys, 1)
            return
        if not ks:
            return

        with self._pen_fsm_lock:
            now = time.monotonic()
            st = self._pen_dual_fsm.setdefault(slot_id, {"phase": "idle"})
            phase = str(st.get("phase", "idle"))

            def release_hold() -> None:
                hc = st.pop("hold_combo", None)
                if isinstance(hc, str) and hc:
                    self._release_keys_hold(hc)

            def reset() -> None:
                release_hold()
                self._cancel_pen_await_timer(slot_id)
                self._pen_dual_fsm[slot_id] = {"phase": "idle"}

            # --- idle: wait for first press ---
            if phase == "idle":
                if edge_down:
                    if combo_is_modifier_only(ks):
                        # Ctrl/shift/etc. apply immediately while drawing (no hold delay).
                        st["phase"] = "hold_pri"
                        st["t_down"] = now
                        st["modifier_instant"] = True
                        self._press_keys_hold(ks)
                        st["hold_combo"] = ks
                    else:
                        st["phase"] = "down"
                        st["t_down"] = now
                        st.pop("modifier_instant", None)
                return

            # --- down: first finger still down; commit to primary hold or release into double window ---
            if phase == "down":
                t0 = float(st.get("t_down", now))
                if pressed and (now - t0) >= _PEN_HOLD_COMMIT_S:
                    st["phase"] = "hold_pri"
                    self._press_keys_hold(ks)
                    st["hold_combo"] = ks
                    return
                if edge_up:
                    dur = now - t0
                    if dur < _PEN_HOLD_COMMIT_S:
                        st["phase"] = "await_dbl"
                        st["deadline"] = now + _PEN_DOUBLE_GAP_S
                        st.pop("await_skip_primary_tap", None)
                        st["await_gen"] = int(st.get("await_gen", 0)) + 1
                        self._schedule_pen_await_timer(slot_id, int(st["await_gen"]))
                    else:
                        # Sparse reports: we may never see a frame while duration >= commit; pulse primary.
                        self._press_keys_hold(ks)
                        self._release_keys_hold(ks)
                        reset()
                return

            # --- hold_pri: primary keys held until release ---
            if phase == "hold_pri":
                if edge_up:
                    if st.get("modifier_instant") and kd:
                        dur = now - float(st.get("t_down", now))
                        release_hold()
                        st.pop("modifier_instant", None)
                        if dur < _PEN_MOD_INSTANT_MAX_HOLD_FOR_DOUBLE_S:
                            st["phase"] = "await_dbl"
                            st["deadline"] = now + _PEN_DOUBLE_GAP_S
                            st["await_skip_primary_tap"] = True
                            st["await_gen"] = int(st.get("await_gen", 0)) + 1
                            self._schedule_pen_await_timer(
                                slot_id, int(st["await_gen"])
                            )
                        else:
                            reset()
                    else:
                        reset()
                return

            # --- await_dbl: timer delivers primary tap; 2nd press = secondary hold ---
            if phase == "await_dbl":
                if edge_down:
                    self._cancel_pen_await_timer(slot_id)
                    release_hold()
                    st["phase"] = "hold_sec"
                    self._press_keys_hold(kd)
                    st["hold_combo"] = kd
                return

            # --- hold_sec: secondary keys held until release ---
            if phase == "hold_sec":
                if edge_up:
                    reset()
                return

            reset()

    def _match_button_action(
        self,
        profile: Profile,
        sequence_id: str,
        press_ids: list[str],
        press_names: list[str],
    ):
        for key in self._candidate_bindings(sequence_id, press_ids, press_names):
            action = profile.buttons.get(key)
            if action is not None:
                return action
        return None

    def _match_dial_event(
        self,
        profile: Profile,
        sequence_id: str,
        press_ids: list[str],
        press_names: list[str],
    ) -> Optional[tuple[str, str]]:
        keys = self._candidate_bindings(sequence_id, press_ids, press_names)
        switch_matches: list[str] = []
        for dial_id, dial in profile.dials.items():
            for key in keys:
                if not key:
                    continue
                if key == dial.ccw_key:
                    return dial_id, "ccw"
                if key == dial.cw_key:
                    return dial_id, "cw"
                if key == dial.switch_key and dial_id not in switch_matches:
                    switch_matches.append(dial_id)
                parsed_switch = parse_dial_switch_binding(dial.switch_key)
                if parsed_switch is not None:
                    switch_dial_id, raw_switch_key = parsed_switch
                    if switch_dial_id == dial_id and key == raw_switch_key and dial_id not in switch_matches:
                        switch_matches.append(dial_id)
        if switch_matches:
            return self._resolve_switch_match(profile, switch_matches), "switch"
        return None

    def _resolve_switch_match(self, profile: Profile, dial_ids: list[str]) -> str:
        if len(dial_ids) == 1:
            return dial_ids[0]

        now = time.monotonic()

        # If a menu is already open for one dial, pressing center again toggles
        # to the other dial — this lets the user reach either dial's menu
        # without needing to rotate first.
        open_dials = [
            d for d in dial_ids
            if now < self._dial_menu_deadline.get((profile.app_class, d), 0.0)
        ]
        if open_dials:
            others = [d for d in dial_ids if d not in open_dials]
            if others:
                return others[0]
            return open_dials[0]

        # No menu open — use the most recently rotated dial as context.
        # Fall back to the first dial when neither has been used recently.
        best_time = 0.0
        best_id: Optional[str] = None
        for dial_id in dial_ids:
            seen_at = self._dial_last_active_at.get((profile.app_class, dial_id), 0.0)
            if seen_at > best_time and now - seen_at <= _DIAL_SWITCH_CONTEXT_WINDOW:
                best_id = dial_id
                best_time = seen_at
        return best_id if best_id is not None else dial_ids[0]

    def _mark_dial_active(self, profile: Profile, dial_id: str) -> None:
        self._dial_last_active_at[(profile.app_class, dial_id)] = time.monotonic()

    def _handle_dial_match(self, profile: Profile, dial_match: tuple[str, str]) -> None:
        dial_id, part = dial_match
        if part == "switch":
            self._open_dial_menu(profile, dial_id)
        elif self._is_dial_menu_open(profile, dial_id):
            self._step_dial_menu(profile, dial_id, part)
        else:
            self._emit_dial_mode(profile, dial_id, part)

    def _candidate_bindings(
        self,
        sequence_id: str,
        press_ids: list[str],
        press_names: list[str],
    ) -> list[str]:
        candidates: list[str] = []
        for key in [sequence_id, *press_ids, *press_names]:
            if key and key not in candidates:
                candidates.append(key)
        return candidates

    def _open_dial_menu(self, profile: Profile, dial_id: str) -> None:
        dial = profile.dials.get(dial_id)
        if not dial:
            return
        modes = [mode for mode in dial.modes if mode]
        if not modes:
            return
        state_key = (profile.app_class, dial_id)
        current = self._dial_mode_index.get(state_key, 0) % len(modes)
        self._dial_mode_index[state_key] = current
        self._dial_menu_deadline[state_key] = time.monotonic() + _DIAL_MENU_TIMEOUT
        self._mark_dial_active(profile, dial_id)
        self._emit_dial_popup(profile, dial_id)
        self._on_status(f"{profile.app_name}: {dial.label or 'Dial'} mode picker open")

    def _step_dial_menu(self, profile: Profile, dial_id: str, direction: str) -> None:
        dial = profile.dials.get(dial_id)
        if not dial:
            return
        modes = [mode for mode in dial.modes if mode]
        if not modes:
            return
        state_key = (profile.app_class, dial_id)
        current = self._dial_mode_index.get(state_key, 0) % len(modes)
        step = -1 if direction == "ccw" else 1
        current = (current + step) % len(modes)
        self._dial_mode_index[state_key] = current
        self._dial_menu_deadline[state_key] = time.monotonic() + _DIAL_MENU_TIMEOUT
        self._mark_dial_active(profile, dial_id)
        self._emit_dial_popup(profile, dial_id)
        self._on_status(f"{profile.app_name}: {dial.label or 'Dial'} → {mode_label(modes[current])}")

    def _is_dial_menu_open(self, profile: Profile, dial_id: str) -> bool:
        state_key = (profile.app_class, dial_id)
        return time.monotonic() < self._dial_menu_deadline.get(state_key, 0.0)

    def _emit_dial_popup(self, profile: Profile, dial_id: str) -> None:
        dial = profile.dials.get(dial_id)
        if not dial:
            return
        modes = [mode for mode in dial.modes if mode]
        if not modes:
            return
        state_key = (profile.app_class, dial_id)
        current = self._dial_mode_index.get(state_key, 0) % len(modes)
        self._on_dial_popup(
            {
                "profile_name": profile.app_name,
                "app_class": profile.app_class,
                "dial_id": dial_id,
                "dial_label": dial.label or "Dial",
                "modes": [mode_label(mode) for mode in modes],
                "selected_index": current,
                "timeout_ms": int(_DIAL_MENU_TIMEOUT * 1000),
            }
        )

    def _emit_dial_mode(self, profile: Profile, dial_id: str, direction: str) -> None:
        dial = profile.dials.get(dial_id)
        if not dial:
            return
        modes = [mode for mode in dial.modes if mode]
        if not modes:
            return
        state_key = (profile.app_class, dial_id)
        idx = self._dial_mode_index.get(state_key, 0) % len(modes)
        pair = mode_pair(modes[idx])
        if not pair:
            return
        self._mark_dial_active(profile, dial_id)
        action = pair[0] if direction == "ccw" else pair[1]
        self._emit_action(action, 1)
