"""Transient dial mode picker shown near the mouse cursor."""
from PyQt6.QtCore import QPoint, QTimer, Qt
from PyQt6.QtGui import QCursor, QGuiApplication
from PyQt6.QtWidgets import QFrame, QLabel, QVBoxLayout, QWidget

from gui import theme


class DialModePopup(QFrame):
    """Small overlay that previews dial modes while the picker is active."""

    def __init__(self, parent: QWidget | None = None) -> None:
        flags = (
            Qt.WindowType.Dialog
            | Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
        )
        if hasattr(Qt.WindowType, "WindowDoesNotAcceptFocus"):
            flags |= Qt.WindowType.WindowDoesNotAcceptFocus
        super().__init__(parent, flags)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating, True)
        self.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.setObjectName("dialModePopup")
        self.setStyleSheet(theme.DIAL_POPUP_QSS)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(14, 12, 14, 12)
        layout.setSpacing(6)

        self._title = QLabel("Dial")
        self._title.setStyleSheet(
            f"color:{theme.TEXT}; font-size:14px; font-weight:700;"
        )
        layout.addWidget(self._title)

        self._subtitle = QLabel("Rotate the dial to choose a mode")
        self._subtitle.setStyleSheet(
            f"color:{theme.TEXT_MUTED}; font-size:10px;"
        )
        layout.addWidget(self._subtitle)

        self._rows_host = QWidget()
        self._rows_layout = QVBoxLayout(self._rows_host)
        self._rows_layout.setContentsMargins(0, 0, 0, 0)
        self._rows_layout.setSpacing(6)
        layout.addWidget(self._rows_host)

        self._timer = QTimer(self)
        self._timer.setSingleShot(True)
        self._timer.timeout.connect(self.hide)

    def show_payload(self, payload: dict) -> None:
        modes = [str(mode) for mode in payload.get("modes", []) if mode]
        if not modes:
            self.hide()
            return

        selected = int(payload.get("selected_index", 0)) % len(modes)
        self._title.setText(str(payload.get("dial_label") or "Dial"))
        self._subtitle.setText(
            f"{payload.get('profile_name', '')}  Rotate to choose, wait to keep"
        )
        self._sync_rows(modes, selected)
        self.adjustSize()
        self._sync_transient_parent()
        self._place_near_cursor()
        self.show()
        self.raise_()
        self._timer.start(max(400, int(payload.get("timeout_ms", 3000))))

    def _sync_rows(self, modes: list[str], selected: int) -> None:
        while self._rows_layout.count():
            item = self._rows_layout.takeAt(0)
            w = item.widget()
            if w is not None:
                w.deleteLater()

        for idx, text in enumerate(modes):
            row = QLabel(text)
            row.setMinimumWidth(180)
            if idx == selected:
                row.setStyleSheet(
                    f"background:{theme.ACCENT_GLOW}; border:1px solid {theme.ACCENT};"
                    f"border-radius:8px; padding:7px 10px; color:{theme.TEXT};"
                    "font-size:12px; font-weight:700;"
                )
            else:
                row.setStyleSheet(
                    f"background:{theme.BG}; border:1px solid {theme.BORDER_SUBTLE};"
                    f"border-radius:8px; padding:7px 10px; color:{theme.TEXT_MUTED};"
                    "font-size:12px;"
                )
            self._rows_layout.addWidget(row)

    def _place_near_cursor(self) -> None:
        anchor = QCursor.pos()
        screen = QGuiApplication.screenAt(anchor) or QGuiApplication.primaryScreen()
        if screen is None:
            self.move(anchor + QPoint(20, 20))
            return

        bounds = screen.availableGeometry()
        x = anchor.x() + 20
        y = anchor.y() + 18
        if x + self.width() > bounds.right() - 8:
            x = anchor.x() - self.width() - 20
        if y + self.height() > bounds.bottom() - 8:
            y = anchor.y() - self.height() - 18

        x = max(bounds.left() + 8, x)
        y = max(bounds.top() + 8, y)
        self.move(x, y)

    def _sync_transient_parent(self) -> None:
        parent = self.parentWidget()
        if parent is None:
            return
        self.winId()
        window = self.windowHandle()
        parent_window = parent.windowHandle()
        if window is not None and parent_window is not None:
            window.setTransientParent(parent_window)
