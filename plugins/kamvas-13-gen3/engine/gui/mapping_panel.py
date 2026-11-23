"""Floating mapping panel shown when a control is selected."""
import json

from PyQt6.QtCore import QEvent, Qt, pyqtSignal
from PyQt6.QtGui import QWheelEvent
from PyQt6.QtWidgets import (
    QApplication, QFrame, QHBoxLayout, QLabel, QLineEdit, QPushButton, QScrollArea,
    QVBoxLayout, QWidget,
)

from gui.theme import MAPPING_PANEL_QSS

_QT_KEY_TOKENS = {
    Qt.Key.Key_Space: "space",
    Qt.Key.Key_Left: "left",
    Qt.Key.Key_Right: "right",
    Qt.Key.Key_Up: "up",
    Qt.Key.Key_Down: "down",
    Qt.Key.Key_PageUp: "pageup",
    Qt.Key.Key_PageDown: "pagedown",
    Qt.Key.Key_Home: "home",
    Qt.Key.Key_End: "end",
    Qt.Key.Key_Insert: "insert",
    Qt.Key.Key_Delete: "delete",
    Qt.Key.Key_Backspace: "backspace",
    Qt.Key.Key_Return: "enter",
    Qt.Key.Key_Enter: "enter",
    Qt.Key.Key_Tab: "tab",
    Qt.Key.Key_Backtab: "tab",
    Qt.Key.Key_Minus: "minus",
    Qt.Key.Key_Equal: "equal",
    Qt.Key.Key_BracketLeft: "leftbrace",
    Qt.Key.Key_BracketRight: "rightbrace",
    Qt.Key.Key_Backslash: "backslash",
    Qt.Key.Key_Slash: "slash",
    Qt.Key.Key_Comma: "comma",
    Qt.Key.Key_Period: "dot",
    Qt.Key.Key_Semicolon: "semicolon",
    Qt.Key.Key_Apostrophe: "apostrophe",
    Qt.Key.Key_QuoteLeft: "grave",
    Qt.Key.Key_Plus: "plus",
}

_QT_MOUSE_BUTTON_TOKENS = {
    Qt.MouseButton.LeftButton: "mouse_left",
    Qt.MouseButton.RightButton: "mouse_right",
    Qt.MouseButton.MiddleButton: "mouse_middle",
    Qt.MouseButton.BackButton: "mouse_back",
    Qt.MouseButton.ForwardButton: "mouse_forward",
}


class MappingPanel(QFrame):
    """Floating editor for the currently selected tablet control."""

    binding_changed = pyqtSignal(str, str, str)   # (keycode, combo, label)
    capture_requested = pyqtSignal()
    close_requested = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("mappingPopup")
        self.setMinimumWidth(300)
        self.setMaximumWidth(460)
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setAttribute(Qt.WidgetAttribute.WA_StyledBackground, True)
        self._slot: int = -1
        self._keycode: str = ""
        self._slot_mode: str = "button"
        self._is_pen: bool = False
        self._dual_binding: bool = False
        self._listen_target: QLineEdit | None = None
        self._listen_button: QPushButton | None = None
        self._build_ui()
        self.setProperty("editorSurface", "tablet")
        self.setStyleSheet(MAPPING_PANEL_QSS)
        app = QApplication.instance()
        if app is not None:
            app.installEventFilter(self)

    # ── UI ─────────────────────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 14, 16, 16)
        layout.setSpacing(10)

        header = QHBoxLayout()
        header.setContentsMargins(0, 0, 0, 0)
        title = QLabel("Edit Control")
        title.setObjectName("mpTitle")
        header.addWidget(title)
        header.addStretch()
        close_btn = QPushButton("×")
        close_btn.setObjectName("mpClose")
        close_btn.setFixedSize(28, 28)
        close_btn.clicked.connect(self.close_requested.emit)
        header.addWidget(close_btn)
        layout.addLayout(header)

        # Slot info
        self._slot_lbl = QLabel("No button selected")
        self._slot_lbl.setObjectName("mpSlot")
        layout.addWidget(self._slot_lbl)

        # Tablet key capture
        self._capture_prompt = QLabel("Link this on-screen control to its real device event:")
        self._capture_prompt.setObjectName("mpPrompt")
        self._capture_prompt.setWordWrap(True)
        layout.addWidget(self._capture_prompt)

        self._kc_wrap = QFrame()
        self._kc_wrap.setObjectName("mpKcWrap")
        kc_row = QHBoxLayout(self._kc_wrap)
        kc_row.setContentsMargins(6, 4, 6, 4)
        self._kc_lbl = QLabel("—")
        self._kc_lbl.setObjectName("mpKc")
        kc_row.addWidget(self._kc_lbl, 1)
        self._cap_btn = QPushButton("Link")
        self._cap_btn.setObjectName("mpGhost")
        self._cap_btn.setFixedWidth(76)
        self._cap_btn.setCheckable(True)
        self._cap_btn.toggled.connect(self._on_capture_toggle)
        kc_row.addWidget(self._cap_btn)
        layout.addWidget(self._kc_wrap)

        self._dial_mode_lbl = QLabel("Dial modes")
        self._dial_mode_lbl.setObjectName("mpSection")
        layout.addWidget(self._dial_mode_lbl)

        self._dial_mode_rows: list[dict[str, object]] = []
        self._dial_scroll = QScrollArea()
        self._dial_scroll.setWidgetResizable(True)
        self._dial_scroll.setFrameShape(QFrame.Shape.NoFrame)
        self._dial_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self._dial_scroll.setMaximumHeight(280)
        self._dial_modes_inner = QWidget()
        self._dial_modes_layout = QVBoxLayout(self._dial_modes_inner)
        self._dial_modes_layout.setContentsMargins(0, 0, 4, 0)
        self._dial_modes_layout.setSpacing(8)
        self._dial_scroll.setWidget(self._dial_modes_inner)
        layout.addWidget(self._dial_scroll)

        self._add_mode_btn = QPushButton("+ Add mode")
        self._add_mode_btn.setObjectName("mpGhost")
        self._add_mode_btn.clicked.connect(self._on_add_dial_mode)
        layout.addWidget(self._add_mode_btn)

        self._shortcut_lbl = QLabel("Shortcut")
        self._shortcut_lbl.setObjectName("mpSection")
        layout.addWidget(self._shortcut_lbl)
        shortcut_row = QHBoxLayout()
        shortcut_row.setContentsMargins(0, 0, 0, 0)
        self._shortcut_edit = QLineEdit()
        self._shortcut_edit.setPlaceholderText("e.g. ctrl+z")
        shortcut_row.addWidget(self._shortcut_edit, 1)
        self._shortcut_listen_btn = QPushButton("Listen")
        self._shortcut_listen_btn.setObjectName("mpGhost")
        self._shortcut_listen_btn.setFixedWidth(72)
        self._shortcut_listen_btn.clicked.connect(
            lambda: self._start_shortcut_listen(self._shortcut_edit, self._shortcut_listen_btn)
        )
        shortcut_row.addWidget(self._shortcut_listen_btn)
        layout.addLayout(shortcut_row)

        self._pen_double_lbl = QLabel("Double‑tap (2nd press) & hold")
        self._pen_double_lbl.setObjectName("mpSection")
        layout.addWidget(self._pen_double_lbl)
        pen_double_row = QHBoxLayout()
        pen_double_row.setContentsMargins(0, 0, 0, 0)
        self._shortcut_double_edit = QLineEdit()
        self._shortcut_double_edit.setPlaceholderText("e.g. shift (optional)")
        pen_double_row.addWidget(self._shortcut_double_edit, 1)
        self._shortcut_double_listen_btn = QPushButton("Listen")
        self._shortcut_double_listen_btn.setObjectName("mpGhost")
        self._shortcut_double_listen_btn.setFixedWidth(72)
        self._shortcut_double_listen_btn.clicked.connect(
            lambda: self._start_shortcut_listen(
                self._shortcut_double_edit, self._shortcut_double_listen_btn
            )
        )
        pen_double_row.addWidget(self._shortcut_double_listen_btn)
        layout.addLayout(pen_double_row)

        hint = QLabel("Choose one dial behavior. The app applies both directions for you.")
        hint.setObjectName("mpHint")
        hint.setWordWrap(True)
        self._hint_lbl = hint
        layout.addWidget(self._hint_lbl)

        # Apply / Clear
        btn_row = QHBoxLayout()
        self._apply_btn = QPushButton("Apply")
        self._apply_btn.setObjectName("mpPrimary")
        self._apply_btn.clicked.connect(self._apply)
        self._clear_btn = QPushButton("Clear")
        self._clear_btn.setObjectName("mpDanger")
        self._clear_btn.clicked.connect(self._clear)
        btn_row.addWidget(self._apply_btn)
        btn_row.addWidget(self._clear_btn)
        layout.addLayout(btn_row)

        self._set_enabled(False)

    def _append_dial_mode_row(self, mode: dict | None = None) -> None:
        """Append one dial mode card (label + ccw/cw shortcuts)."""
        if mode is None:
            mode = {}
        idx = len(self._dial_mode_rows)
        card = QFrame()
        card.setObjectName("dialCard")
        card_layout = QVBoxLayout(card)
        card_layout.setContentsMargins(8, 8, 8, 8)
        card_layout.setSpacing(6)

        head = QHBoxLayout()
        head.setContentsMargins(0, 0, 0, 0)
        mode_idx = QLabel(f"Mode {idx + 1}")
        mode_idx.setMinimumWidth(52)
        name_edit = QLineEdit()
        name_edit.setPlaceholderText("Label, e.g. Brush Size")
        name_edit.setText(str(mode.get("label", "")))
        remove_btn = QPushButton("×")
        remove_btn.setObjectName("mpClose")
        remove_btn.setFixedSize(26, 26)
        remove_btn.setToolTip("Remove this mode")
        remove_btn.clicked.connect(lambda _=False, f=card: self._remove_dial_mode_row(f))
        head.addWidget(mode_idx)
        head.addWidget(name_edit, 1)
        head.addWidget(remove_btn)
        card_layout.addLayout(head)

        keys = QHBoxLayout()
        keys.setContentsMargins(0, 0, 0, 0)
        keys.setSpacing(6)
        left_lbl = QLabel("Left")
        left_lbl.setMinimumWidth(28)
        ccw_edit = QLineEdit()
        ccw_edit.setPlaceholderText("e.g. leftbrace")
        ccw_edit.setText(str(mode.get("ccw", "")))
        ccw_btn = QPushButton("Pick")
        ccw_btn.setObjectName("mpGhost")
        ccw_btn.setFixedWidth(48)
        ccw_btn.clicked.connect(
            lambda _=False, e=ccw_edit, b=ccw_btn: self._start_shortcut_listen(e, b)
        )
        right_lbl = QLabel("Right")
        right_lbl.setMinimumWidth(36)
        cw_edit = QLineEdit()
        cw_edit.setPlaceholderText("e.g. rightbrace")
        cw_edit.setText(str(mode.get("cw", "")))
        cw_btn = QPushButton("Pick")
        cw_btn.setObjectName("mpGhost")
        cw_btn.setFixedWidth(48)
        cw_btn.clicked.connect(
            lambda _=False, e=cw_edit, b=cw_btn: self._start_shortcut_listen(e, b)
        )
        keys.addWidget(left_lbl)
        keys.addWidget(ccw_edit, 1)
        keys.addWidget(ccw_btn)
        keys.addWidget(right_lbl)
        keys.addWidget(cw_edit, 1)
        keys.addWidget(cw_btn)
        card_layout.addLayout(keys)

        self._dial_modes_layout.addWidget(card)
        self._dial_mode_rows.append(
            {
                "frame": card,
                "mode_idx": mode_idx,
                "name": name_edit,
                "ccw": ccw_edit,
                "ccw_btn": ccw_btn,
                "cw": cw_edit,
                "cw_btn": cw_btn,
                "remove": remove_btn,
            }
        )
        self._sync_remove_buttons()

    def _clear_dial_mode_rows(self) -> None:
        while self._dial_modes_layout.count():
            item = self._dial_modes_layout.takeAt(0)
            w = item.widget()
            if w is not None:
                w.deleteLater()
        self._dial_mode_rows.clear()

    def _remove_dial_mode_row(self, frame: QFrame) -> None:
        if len(self._dial_mode_rows) <= 1:
            return
        for i, row in enumerate(self._dial_mode_rows):
            if row["frame"] is frame:
                self._dial_modes_layout.removeWidget(frame)
                frame.deleteLater()
                del self._dial_mode_rows[i]
                self._renumber_mode_labels()
                self._sync_remove_buttons()
                break

    def _renumber_mode_labels(self) -> None:
        for i, row in enumerate(self._dial_mode_rows):
            row["mode_idx"].setText(f"Mode {i + 1}")

    def _sync_remove_buttons(self) -> None:
        sole = len(self._dial_mode_rows) <= 1
        for row in self._dial_mode_rows:
            row["remove"].setEnabled(not sole)

    def _on_add_dial_mode(self) -> None:
        self._append_dial_mode_row({})

    # ── public API ─────────────────────────────────────────────────────────────

    def show_slot(self, slot: int, slot_name: str,
                  keycode: str, combo: str, label: str, slot_mode: str,
                  is_pen: bool = False, dual_binding: bool = False) -> None:
        self._stop_shortcut_listen()
        self._slot = slot
        self._keycode = keycode
        self._slot_mode = slot_mode
        self._is_pen = is_pen
        self._dual_binding = dual_binding
        self._slot_lbl.setText(slot_name)
        if slot_mode == "dial_modes":
            self._kc_lbl.setText("Automatic")
        elif is_pen:
            self._kc_lbl.setText("Auto-linked")
        else:
            self._kc_lbl.setText(self._display_binding_id(keycode))
        self._shortcut_edit.setText("" if slot_mode == "dial_modes" else self._pen_single_combo(combo))
        self._shortcut_double_edit.setText(self._pen_double_combo(combo))
        self._set_dial_modes(self._decode_dial_modes(combo) if combo and slot_mode == "dial_modes" else [])
        self._apply_mode(is_pen=is_pen, dual_binding=dual_binding)
        self._set_enabled(True)

    def set_captured_key(self, keycode: str) -> None:
        self._keycode = keycode
        self._kc_lbl.setText(self._display_binding_id(keycode))
        self._cap_btn.setChecked(False)
        self._cap_btn.setText("Link")

    def set_capture_active(self, active: bool) -> None:
        self._cap_btn.blockSignals(True)
        self._cap_btn.setChecked(active)
        self._cap_btn.setText("Waiting…" if active else "Link")
        self._cap_btn.blockSignals(False)

    # ── slots ──────────────────────────────────────────────────────────────────

    def _on_capture_toggle(self, checked: bool) -> None:
        self._cap_btn.setText("Waiting…" if checked else "Link")
        self.capture_requested.emit()

    def _apply(self) -> None:
        if self._slot < 0:
            return
        if self._slot_mode == "dial_modes":
            modes = self._collect_dial_modes()
            combo = json.dumps(modes)
            label = " / ".join(mode["label"] for mode in modes)
        else:
            sk = self._shortcut_edit.text().strip()
            dk = self._shortcut_double_edit.text().strip()
            if self._dual_binding and dk:
                combo = json.dumps(
                    {"single": sk, "double": dk, "label": sk, "label_double": dk}
                )
                label = f"{sk or '—'} / {dk}"
            else:
                combo = sk
                label = sk
        self.binding_changed.emit(
            self._keycode,
            combo,
            label,
        )

    def _clear(self) -> None:
        if self._slot < 0:
            return
        self._stop_shortcut_listen()
        self._keycode = ""
        self._kc_lbl.setText("Automatic" if self._slot_mode == "dial_modes" else "—")
        self._set_dial_modes([])
        self._shortcut_edit.clear()
        self._shortcut_double_edit.clear()
        self.binding_changed.emit("", "", "")

    def _set_enabled(self, on: bool) -> None:
        for w in (
            self._cap_btn,
            self._shortcut_edit,
            self._shortcut_listen_btn,
            self._shortcut_double_edit,
            self._shortcut_double_listen_btn,
            self._apply_btn,
            self._clear_btn,
            self._add_mode_btn,
        ):
            w.setEnabled(on)
        for row in self._dial_mode_rows:
            row["name"].setEnabled(on)
            row["ccw"].setEnabled(on)
            row["ccw_btn"].setEnabled(on)
            row["cw"].setEnabled(on)
            row["cw_btn"].setEnabled(on)
            row["remove"].setEnabled(on and len(self._dial_mode_rows) > 1)

    def _display_binding_id(self, keycode: str) -> str:
        if not keycode:
            return "—"
        if keycode.startswith("DIAL:"):
            switch_key, ccw_key, cw_key = self._parse_dial_keycode(keycode)
            return (
                f"Press {self._short_binding(switch_key)} | "
                f"CCW {self._short_binding(ccw_key)} | "
                f"CW {self._short_binding(cw_key)}"
            )
        if keycode.startswith("VENDORDIAL:"):
            return self._format_vendor_dial_binding(keycode)
        if keycode.startswith("VENDORBTN:"):
            return self._format_vendor_button_binding(keycode)
        if keycode.startswith("PENBTN:"):
            return self._format_pen_button_binding(keycode)
        if keycode.startswith("RAWDIAL:"):
            return self._format_raw_dial_binding(keycode)
        if keycode.startswith("SEQ:"):
            return "Tablet " + self._short_binding(keycode)
        if keycode.startswith("MSC_SCAN_"):
            return "Tablet " + keycode.removeprefix("MSC_SCAN_").upper()
        return keycode

    def _apply_mode(self, is_pen: bool = False, dual_binding: bool = False) -> None:
        is_dial_modes = self._slot_mode == "dial_modes"
        self._dial_mode_lbl.setVisible(is_dial_modes)
        self._dial_scroll.setVisible(is_dial_modes)
        self._add_mode_btn.setVisible(is_dial_modes)
        for row in self._dial_mode_rows:
            row["frame"].setVisible(is_dial_modes)
        # For pen buttons the Link row is hidden — keycode is always auto-filled
        self._kc_wrap.setVisible(not is_dial_modes and not is_pen)
        self._capture_prompt.setVisible(not is_pen)
        self._shortcut_lbl.setVisible(not is_dial_modes)
        self._shortcut_edit.setVisible(not is_dial_modes)
        self._pen_double_lbl.setVisible(dual_binding and not is_dial_modes)
        self._shortcut_double_edit.setVisible(dual_binding and not is_dial_modes)
        self._shortcut_double_listen_btn.setVisible(dual_binding and not is_dial_modes)
        if is_pen and not is_dial_modes:
            self._shortcut_lbl.setText("Press & hold (single)")
        else:
            self._shortcut_lbl.setText("Shortcut")
        self._capture_prompt.setText(
            "This dial is detected automatically. Just set the radial menu options you want."
            if is_dial_modes else
            "Link this on-screen control to its real device event:"
        )
        self._hint_lbl.setText(
            "Add as many modes as you need. Each row needs left and right shortcuts; "
            "incomplete rows are ignored when you apply."
            if is_dial_modes else
            "Enter any shortcut you want for this button."
            if not dual_binding else
            (
                "If the first shortcut is only modifiers (Ctrl, Shift, …), they apply as soon as you press. "
                "Otherwise hold briefly (~0.15s) for the first shortcut, or quick-tap once and wait for the short window "
                "if you don’t double-press. Press again within that window and hold for the second shortcut."
                if is_pen else
                "Hold for the first shortcut, quick-tap once for a single fire after the short window, "
                "or press again within that window and hold for the second shortcut."
            )
        )
        self.setProperty("editorSurface", "pen" if is_pen else "tablet")
        self.style().unpolish(self)
        self.style().polish(self)

    def _short_binding(self, keycode: str) -> str:
        if not keycode or keycode == "?":
            return "?"
        if keycode.startswith("DIALSW:"):
            return self._format_dial_switch_binding(keycode, compact=True)
        if keycode.startswith("VENDORDIAL:"):
            return self._format_vendor_dial_binding(keycode, compact=True)
        if keycode.startswith("VENDORBTN:"):
            return self._format_vendor_button_binding(keycode, compact=True)
        if keycode.startswith("PENBTN:"):
            return self._format_pen_button_binding(keycode, compact=True)
        if keycode.startswith("RAWDIAL:"):
            return self._format_raw_dial_binding(keycode, compact=True)
        if keycode.startswith("SEQ:"):
            parts = [self._format_binding_token(part) for part in keycode.removeprefix("SEQ:").split("+") if part]
            return " + ".join(parts)
        if keycode.startswith("MSC_SCAN_"):
            return keycode.removeprefix("MSC_SCAN_").upper()
        return self._format_binding_token(keycode)

    def _format_raw_dial_binding(self, keycode: str, compact: bool = False) -> str:
        body = keycode.removeprefix("RAWDIAL:")
        device_key, _, event = body.rpartition(":")
        device_label = device_key.replace("_", ":")
        event_label = {
            "press": "Press",
            "pos": "+" if compact else "Rotate +",
            "neg": "-" if compact else "Rotate -",
        }.get(event, event)
        if compact:
            return f"{device_label} {event_label}".strip()
        return f"Dial {device_label} {event_label}".strip()

    def _format_dial_switch_binding(self, keycode: str, compact: bool = False) -> str:
        body = keycode.removeprefix("DIALSW:")
        dial_id, _, raw = body.partition(":")
        raw_label = self._format_raw_dial_binding(raw, compact=True) if raw.startswith("RAWDIAL:") else self._format_binding_token(raw)
        if compact:
            return f"S{dial_id} {raw_label}".strip()
        return f"Dial Switch {dial_id} {raw_label}".strip()

    def _format_vendor_button_binding(self, keycode: str, compact: bool = False) -> str:
        slot = keycode.removeprefix("VENDORBTN:")
        label = f"Button {int(slot) - 2}" if slot.isdigit() else slot
        if compact:
            return label
        return f"Tablet {label}"

    def _format_pen_button_binding(self, keycode: str, compact: bool = False) -> str:
        slot = keycode.removeprefix("PENBTN:")
        label = f"Pen Button {slot}"
        if compact:
            return label
        return label

    def _format_vendor_dial_binding(self, keycode: str, compact: bool = False) -> str:
        _, dial_id, part = keycode.split(":", 2)
        dial_label = {
            "0": "Upper Dial",
            "8": "Lower Dial",
        }.get(dial_id, f"Dial {dial_id}")
        part_label = {
            "press": "Center",
            "ccw": "CCW",
            "cw": "CW",
        }.get(part, part.upper())
        return f"{dial_label} {part_label}"

    def _format_binding_token(self, keycode: str) -> str:
        if keycode.startswith("MSC_SCAN_"):
            return keycode.removeprefix("MSC_SCAN_").upper()
        if keycode.startswith("mouse_"):
            return keycode.replace("mouse_", "mouse ").title()
        return keycode.removeprefix("KEY_")

    def _set_dial_modes(self, modes: list[dict]) -> None:
        self._clear_dial_mode_rows()
        if not modes:
            self._append_dial_mode_row({})
            return
        for item in modes:
            self._append_dial_mode_row(item if isinstance(item, dict) else {})

    def _pen_single_combo(self, raw: str) -> str:
        raw = (raw or "").strip()
        if raw.startswith("{"):
            try:
                o = json.loads(raw)
                return str(o.get("single", ""))
            except json.JSONDecodeError:
                pass
        return raw

    def _pen_double_combo(self, raw: str) -> str:
        raw = (raw or "").strip()
        if raw.startswith("{"):
            try:
                o = json.loads(raw)
                return str(o.get("double", ""))
            except json.JSONDecodeError:
                pass
        return ""

    def _decode_dial_modes(self, raw: str) -> list[dict]:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            return []
        if not isinstance(data, list):
            return []
        modes: list[dict] = []
        for idx, item in enumerate(data):
            if not isinstance(item, dict):
                continue
            label = str(item.get("label", "")).strip() or f"Mode {idx + 1}"
            ccw = str(item.get("ccw", "")).strip()
            cw = str(item.get("cw", "")).strip()
            modes.append({"label": label, "ccw": ccw, "cw": cw})
        return modes

    def _collect_dial_modes(self) -> list[dict]:
        modes: list[dict] = []
        for idx, row in enumerate(self._dial_mode_rows):
            label = row["name"].text().strip()
            ccw = row["ccw"].text().strip()
            cw = row["cw"].text().strip()
            if not label and not ccw and not cw:
                continue
            if not ccw or not cw:
                continue
            modes.append(
                {
                    "label": label or f"Mode {idx + 1}",
                    "ccw": ccw,
                    "cw": cw,
                }
            )
        return modes

    def _start_shortcut_listen(self, target: QLineEdit, button: QPushButton) -> None:
        if self._listen_target is target and self._listen_button is button:
            self._stop_shortcut_listen()
            return
        self._stop_shortcut_listen()
        self._listen_target = target
        self._listen_button = button
        button.setText("Press / scroll…")
        target.setFocus()

    def _stop_shortcut_listen(self) -> None:
        if self._listen_button is not None:
            self._listen_button.setText("Listen" if self._listen_button is self._shortcut_listen_btn else "Pick")
        self._listen_target = None
        self._listen_button = None

    def eventFilter(self, obj, event) -> bool:
        if self._listen_target is None:
            return super().eventFilter(obj, event)
        if event.type() == QEvent.Type.KeyRelease:
            return True
        if event.type() == QEvent.Type.KeyPress:
            key = event.key()
            if key == Qt.Key.Key_Escape:
                self._stop_shortcut_listen()
                return True
            if key in {
                Qt.Key.Key_Control,
                Qt.Key.Key_Shift,
                Qt.Key.Key_Alt,
                Qt.Key.Key_Meta,
                Qt.Key.Key_AltGr,
            }:
                return True
            combo = self._shortcut_from_key_event(event)
            if combo:
                self._listen_target.setText(combo)
            self._stop_shortcut_listen()
            return True
        if event.type() == QEvent.Type.MouseButtonPress:
            combo = self._shortcut_from_mouse_event(event)
            if combo:
                self._listen_target.setText(combo)
            self._stop_shortcut_listen()
            return True
        if event.type() == QEvent.Type.MouseButtonRelease:
            return True
        if event.type() == QEvent.Type.Wheel:
            if isinstance(event, QWheelEvent):
                combo = self._shortcut_from_wheel_event(event)
                if combo:
                    self._listen_target.setText(combo)
                    self._stop_shortcut_listen()
            return True
        return super().eventFilter(obj, event)

    def _shortcut_from_key_event(self, event) -> str:
        key = event.key()
        mods = self._modifier_tokens(event.modifiers())
        token = self._key_token(key, event.modifiers())
        if not token:
            return ""
        return "+".join([*mods, token])

    def _shortcut_from_mouse_event(self, event) -> str:
        token = _QT_MOUSE_BUTTON_TOKENS.get(event.button())
        if not token:
            return ""
        return "+".join([*self._modifier_tokens(event.modifiers()), token])

    def _shortcut_from_wheel_event(self, event: QWheelEvent) -> str:
        """Map wheel / trackpad scroll to the same tokens the daemon understands.

        Uses angleDelta first, then pixelDelta so high-resolution touchpads work
        when the legacy angle delta is zero.
        """
        ad = event.angleDelta()
        pd = event.pixelDelta()
        vx = ad.x() if ad.x() != 0 else pd.x()
        vy = ad.y() if ad.y() != 0 else pd.y()
        if vx == 0 and vy == 0:
            return ""
        # Match the dominant axis when both move (e.g. diagonal trackpad gestures).
        if abs(vy) >= abs(vx):
            return "scroll_up" if vy > 0 else "scroll_down"
        return "scroll_right" if vx > 0 else "scroll_left"

    def _modifier_tokens(self, modifiers) -> list[str]:
        tokens: list[str] = []
        if modifiers & Qt.KeyboardModifier.ControlModifier:
            tokens.append("ctrl")
        if modifiers & Qt.KeyboardModifier.ShiftModifier:
            tokens.append("shift")
        if modifiers & Qt.KeyboardModifier.AltModifier:
            tokens.append("alt")
        if modifiers & Qt.KeyboardModifier.MetaModifier:
            tokens.append("meta")
        return tokens

    def _key_token(self, key: int, modifiers) -> str:
        if modifiers & Qt.KeyboardModifier.KeypadModifier:
            if Qt.Key.Key_0 <= key <= Qt.Key.Key_9:
                return f"kp{key - Qt.Key.Key_0}"
            if key == Qt.Key.Key_Plus:
                return "kpplus"
            if key == Qt.Key.Key_Minus:
                return "kpminus"
            if key == Qt.Key.Key_Slash:
                return "kpslash"
            if key == Qt.Key.Key_Asterisk:
                return "kpasterisk"
            if key in {Qt.Key.Key_Period, Qt.Key.Key_Comma}:
                return "kpdot"
            if key in {Qt.Key.Key_Return, Qt.Key.Key_Enter}:
                return "kpenter"
        if Qt.Key.Key_A <= key <= Qt.Key.Key_Z:
            return chr(ord("a") + key - Qt.Key.Key_A)
        if Qt.Key.Key_0 <= key <= Qt.Key.Key_9:
            return str(key - Qt.Key.Key_0)
        if Qt.Key.Key_F1 <= key <= Qt.Key.Key_F35:
            return f"f{key - Qt.Key.Key_F1 + 1}"
        return _QT_KEY_TOKENS.get(Qt.Key(key), "")

    def _parse_dial_keycode(self, keycode: str) -> tuple[str, str, str]:
        raw = keycode.removeprefix("DIAL:")
        switch_key, _, rest = raw.partition("|")
        ccw_key, _, cw_key = rest.partition("|")
        return switch_key, ccw_key, cw_key
