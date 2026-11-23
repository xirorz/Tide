"""Widget representing a single tablet express key button."""
from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtWidgets import QFrame, QLabel, QVBoxLayout


class ButtonWidget(QFrame):
    """Clickable card representing one tablet express key."""

    clicked = pyqtSignal(str)  # emits keycode_name

    def __init__(self, number: int, keycode_name: str = "", parent=None):
        super().__init__(parent)
        self._number = number
        self._keycode = keycode_name
        self._action_label = ""

        self.setFixedSize(140, 60)
        self.setFrameStyle(QFrame.Shape.StyledPanel)
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self._apply_style(False)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 4, 8, 4)
        layout.setSpacing(2)

        self._top = QLabel(f"Button {number}")
        self._top.setStyleSheet("font-size: 10px; color: #888;")
        self._top.setAlignment(Qt.AlignmentFlag.AlignHCenter)

        self._mid = QLabel(keycode_name or "unbound")
        self._mid.setStyleSheet("font-size: 11px; font-weight: bold;")
        self._mid.setAlignment(Qt.AlignmentFlag.AlignHCenter)

        self._bot = QLabel("")
        self._bot.setStyleSheet("font-size: 10px; color: #aaa;")
        self._bot.setAlignment(Qt.AlignmentFlag.AlignHCenter)
        self._bot.setWordWrap(True)

        layout.addWidget(self._top)
        layout.addWidget(self._mid)
        layout.addWidget(self._bot)

    def set_binding(self, keycode_name: str, action_label: str, combo: str) -> None:
        self._keycode = keycode_name
        self._action_label = action_label
        self._mid.setText(keycode_name or "unbound")
        if action_label:
            self._bot.setText(f"{action_label}  ({combo})")
        else:
            self._bot.setText(combo if combo else "")

    def set_highlighted(self, active: bool) -> None:
        self._apply_style(active)

    def _apply_style(self, active: bool) -> None:
        if active:
            self.setStyleSheet("""
                QFrame {
                    background: #2a4a6a;
                    border: 2px solid #5599cc;
                    border-radius: 6px;
                }
            """)
        else:
            self.setStyleSheet("""
                QFrame {
                    background: #2b2b2b;
                    border: 1px solid #444;
                    border-radius: 6px;
                }
                QFrame:hover {
                    border: 1px solid #777;
                    background: #333;
                }
            """)

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            self.clicked.emit(self._keycode)
        super().mousePressEvent(event)
