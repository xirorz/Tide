"""Dialog for creating or editing a profile, with live open-window search."""
import json
import subprocess

from PyQt6.QtCore import Qt, QSize, pyqtSignal
from PyQt6.QtGui import QBrush, QColor
from PyQt6.QtWidgets import (
    QDialog, QDialogButtonBox, QLabel, QLineEdit, QPushButton,
    QVBoxLayout, QHBoxLayout, QListWidget, QListWidgetItem, QFrame,
)

from gui.app_icons import icon_from_stored, resolve_icon_for_profile
from gui.theme import ACCENT, PROFILE_DIALOG_QSS, TEXT, TEXT_MUTED


def _get_open_windows() -> list[dict]:
    """Return list of {class, title, pid} dicts from hyprctl."""
    try:
        out = subprocess.check_output(["hyprctl", "-j", "clients"], text=True, timeout=2)
        clients = json.loads(out)
        # Deduplicate by class, keep first window per class (title + pid for debugging)
        seen: dict[str, tuple[str, int]] = {}
        for c in clients:
            cls = c.get("class", "").strip()
            title = c.get("title", "").strip()
            pid = int(c.get("pid") or 0)
            if cls and cls not in seen:
                seen[cls] = (title, pid)
        return [
            {"class": k, "title": t[0], "pid": t[1]}
            for k, t in seen.items()
        ]
    except Exception:
        return []


class ProfileDialog(QDialog):
    """Create or rename a profile with a live-filtered list of open windows."""

    saved = pyqtSignal(str, str, str)  # (app_class, app_name, icon)

    def __init__(self, app_class: str = "", app_name: str = "",
                 active_class: str = "", parent=None):
        super().__init__(parent)
        self.setWindowTitle("Create Profile" if not app_class else "Edit Profile")
        self.setMinimumWidth(420)
        self.setMinimumHeight(380)
        self.setModal(True)

        self._windows = _get_open_windows()

        layout = QVBoxLayout(self)
        layout.setContentsMargins(18, 16, 18, 16)
        layout.setSpacing(10)

        # --- Search / app class field ---
        ac = QLabel("App class")
        ac.setStyleSheet(f"color:{TEXT}; font-weight:600; font-size:12px;")
        layout.addWidget(ac)
        sub = QLabel("Type to filter open windows")
        sub.setStyleSheet(f"color:{TEXT_MUTED}; font-size:11px; margin-bottom:4px;")
        layout.addWidget(sub)

        self._class_edit = QLineEdit(app_class)
        self._class_edit.setPlaceholderText("e.g.  krita  or  firefox")
        self._class_edit.textChanged.connect(self._on_search)
        layout.addWidget(self._class_edit)

        # --- Live results list ---
        self._results = QListWidget()
        self._results.setIconSize(QSize(20, 20))
        self._results.setMaximumHeight(160)
        self._results.itemClicked.connect(self._on_item_clicked)
        layout.addWidget(self._results)

        # Populate with all windows initially
        self._populate(app_class)

        # --- Currently active window shortcut ---
        if active_class:
            act_row = QHBoxLayout()
            act_lbl = QLabel(f"Active window:  <b>{active_class}</b>")
            act_lbl.setStyleSheet(f"color:{ACCENT};")
            use_btn = QPushButton("Use")
            use_btn.setFixedWidth(50)
            use_btn.clicked.connect(lambda: self._class_edit.setText(active_class))
            act_row.addWidget(act_lbl)
            act_row.addStretch()
            act_row.addWidget(use_btn)
            layout.addLayout(act_row)

        sep = QFrame()
        sep.setFrameShape(QFrame.Shape.HLine)
        layout.addWidget(sep)

        # --- Display name ---
        name_row = QHBoxLayout()
        nl = QLabel("Display name")
        nl.setStyleSheet(f"color:{TEXT_MUTED}; font-size:11px;")
        name_row.addWidget(nl)
        self._name_edit = QLineEdit(app_name)
        self._name_edit.setPlaceholderText("e.g.  Krita  (leave blank to use class)")
        name_row.addWidget(self._name_edit)
        layout.addLayout(name_row)

        # --- Buttons ---
        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

        if not app_class:
            self._class_edit.setFocus()

        self.setStyleSheet(PROFILE_DIALOG_QSS)

    # ------------------------------------------------------------------ helpers

    def _populate(self, query: str = "") -> None:
        self._results.clear()
        q = query.lower().strip()
        for w in self._windows:
            cls = w["class"]
            title = w["title"]
            if q and q not in cls.lower() and q not in title.lower():
                continue
            item = QListWidgetItem(f"{cls}  —  {title[:45]}")
            item.setData(Qt.ItemDataRole.UserRole, cls)
            item.setIcon(icon_from_stored("", cls))
            # Highlight exact match
            if cls.lower() == q:
                item.setForeground(QBrush(QColor(ACCENT)))
            self._results.addItem(item)

    def _on_search(self, text: str) -> None:
        self._populate(text)
        # Auto-fill display name if there's one matching window
        if not self._name_edit.text():
            for w in self._windows:
                if w["class"].lower() == text.lower():
                    self._name_edit.setText(w["class"])
                    break

    def _on_item_clicked(self, item: QListWidgetItem) -> None:
        cls = item.data(Qt.ItemDataRole.UserRole)
        self._class_edit.setText(cls)
        # Auto-fill display name with the class if empty
        if not self._name_edit.text():
            self._name_edit.setText(cls)

    def _accept(self) -> None:
        app_class = self._class_edit.text().strip()
        app_name = self._name_edit.text().strip() or app_class
        if app_class:
            pid = next((w["pid"] for w in self._windows if w["class"] == app_class), 0)
            icon = resolve_icon_for_profile(app_class, pid)
            self.saved.emit(app_class, app_name, icon)
            self.accept()
