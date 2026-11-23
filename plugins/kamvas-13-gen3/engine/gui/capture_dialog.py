"""Dialog for capturing a tablet button keycode and assigning a shortcut."""
from PyQt6.QtCore import Qt, QTimer, pyqtSignal
from PyQt6.QtWidgets import (
    QDialog, QDialogButtonBox, QLabel, QLineEdit,
    QPushButton, QVBoxLayout, QHBoxLayout, QFrame,
)


class CaptureDialog(QDialog):
    """Two-step dialog: first capture the tablet button, then enter the output shortcut."""

    captured = pyqtSignal(str, str, str)  # (keycode_name, combo, label)

    def __init__(self, existing_keycode: str = "", existing_combo: str = "",
                 existing_label: str = "", parent=None):
        super().__init__(parent)
        self.setWindowTitle("Edit Button Binding")
        self.setMinimumWidth(380)
        self.setModal(True)
        self._keycode = existing_keycode
        self._timer: QTimer | None = None

        layout = QVBoxLayout(self)
        layout.setSpacing(12)

        # --- Tablet button capture section ---
        layout.addWidget(QLabel("<b>Step 1: Tablet Button</b>"))

        capture_frame = QFrame()
        capture_frame.setFrameStyle(QFrame.Shape.StyledPanel)
        capture_frame.setStyleSheet("background: #1e1e1e; border-radius: 6px; padding: 4px;")
        cap_layout = QVBoxLayout(capture_frame)

        self._capture_lbl = QLabel(
            f"Current: <b>{existing_keycode or 'none'}</b>"
            if existing_keycode else "No button captured yet."
        )
        self._capture_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        cap_layout.addWidget(self._capture_lbl)

        self._capture_btn = QPushButton("Press tablet button to capture...")
        self._capture_btn.setCheckable(True)
        self._capture_btn.toggled.connect(self._on_capture_toggle)
        cap_layout.addWidget(self._capture_btn)

        layout.addWidget(capture_frame)

        # --- Output key combo section ---
        layout.addWidget(QLabel("<b>Step 2: Output Shortcut</b>"))

        combo_row = QHBoxLayout()
        self._combo_edit = QLineEdit(existing_combo)
        self._combo_edit.setPlaceholderText("e.g.  ctrl+z  or  ctrl+shift+alt+r")
        combo_row.addWidget(QLabel("Shortcut:"))
        combo_row.addWidget(self._combo_edit)
        layout.addLayout(combo_row)

        label_row = QHBoxLayout()
        self._label_edit = QLineEdit(existing_label)
        self._label_edit.setPlaceholderText("e.g.  Undo  (optional)")
        label_row.addWidget(QLabel("Label:   "))
        label_row.addWidget(self._label_edit)
        layout.addLayout(label_row)

        # --- Passthrough option ---
        pass_row = QHBoxLayout()
        self._pass_btn = QPushButton("Set as pass-through (no remap)")
        self._pass_btn.setCheckable(True)
        self._pass_btn.toggled.connect(self._on_passthrough)
        pass_row.addWidget(self._pass_btn)
        layout.addLayout(pass_row)

        # --- Clear binding ---
        clear_btn = QPushButton("Clear binding")
        clear_btn.clicked.connect(self._clear)
        layout.addWidget(clear_btn)

        # --- Buttons ---
        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    # ------------------------------------------------------------------ slots

    def _on_capture_toggle(self, checked: bool) -> None:
        if checked:
            self._capture_btn.setText("Waiting for tablet button press...")
            # Ask parent (main_window) to activate capture mode
            self.parent().start_capture(self._on_captured)
        else:
            self._capture_btn.setText("Press tablet button to capture...")
            if hasattr(self.parent(), "stop_capture"):
                self.parent().stop_capture()

    def _on_captured(self, keycode_name: str) -> None:
        self._keycode = keycode_name
        self._capture_lbl.setText(f"Captured: <b>{keycode_name}</b>")
        self._capture_btn.setChecked(False)
        self._capture_btn.setText("Captured! Click to re-capture.")

    def _on_passthrough(self, checked: bool) -> None:
        self._combo_edit.setEnabled(not checked)
        self._label_edit.setEnabled(not checked)
        if checked:
            self._combo_edit.setText("__passthrough__")
        else:
            if self._combo_edit.text() == "__passthrough__":
                self._combo_edit.setText("")

    def _clear(self) -> None:
        self._keycode = ""
        self._combo_edit.setText("")
        self._label_edit.setText("")
        self._capture_lbl.setText("No button captured yet.")
        self._accept()

    def _accept(self) -> None:
        self.captured.emit(
            self._keycode,
            self._combo_edit.text().strip(),
            self._label_edit.text().strip(),
        )
        self.accept()
