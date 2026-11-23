"""Main application window."""
import json
import re
import sys
import subprocess
import threading
from pathlib import Path
from typing import Optional

from PyQt6.QtCore import Qt, QPoint, QSize, pyqtSignal, pyqtSlot
from PyQt6.QtGui import QAction, QIcon
from PyQt6.QtWidgets import (
    QApplication, QFrame, QHBoxLayout, QLabel, QListWidget, QListWidgetItem,
    QMainWindow, QPushButton, QSizePolicy, QSplitter, QStackedWidget, QStatusBar,
    QSystemTrayIcon, QToolBar, QToolButton, QVBoxLayout, QWidget, QMenu, QMessageBox,
)

from daemon import Daemon
from dial_actions import default_modes_for_app, mode_label, sanitize_modes
from models import ButtonAction, DialConfig, Profile
from assets.tablets.definitions import get_definition
from gui.tablet_canvas import TabletCanvas
from gui.pen_canvas import PenCanvas
from gui.dial_popup import DialModePopup
from gui.mapping_panel import MappingPanel
from gui.profile_dialog import ProfileDialog
from gui.app_icons import icon_from_stored
from gui import theme


_PROFILE_ROW_H = 44
# Total list row height (matches QSS margin + min-height so content stays vertically centered).
_PROFILE_ITEM_H = 54


def _pen_profile_combo_label(act: Optional[ButtonAction]) -> tuple[str, str]:
    """Serialize profile ButtonAction into mapping panel combo + summary label."""
    if act is None:
        return "", ""
    if getattr(act, "keys_double", "") or getattr(act, "label_double", ""):
        combo = json.dumps(
            {
                "single": act.keys,
                "double": act.keys_double,
                "label": act.label,
                "label_double": act.label_double,
            }
        )
        lb = act.label or act.keys or "—"
        ld = act.label_double or act.keys_double or "—"
        return combo, f"{lb} / {ld}"
    return act.keys, act.label


def _button_action_from_mapping_combo(
    combo: str, label: str, *, allow_dual_json: bool
) -> ButtonAction:
    combo = (combo or "").strip()
    if allow_dual_json and combo.startswith("{"):
        try:
            o = json.loads(combo)
            sk = str(o.get("single", ""))
            dk = str(o.get("double", ""))
            return ButtonAction(
                keys=sk,
                label=str(o.get("label", sk)),
                keys_double=dk,
                label_double=str(o.get("label_double", dk)),
                passthrough=False,
            )
        except json.JSONDecodeError:
            pass
    return ButtonAction(
        keys=combo,
        label=label or combo,
        passthrough=(combo == "__passthrough__"),
    )


def _slot_supports_dual_binding(tablet_def: dict, slot_id: int) -> bool:
    """Pen side buttons and tablet express keys (not dials) can use keys_double."""
    if slot_id in {pb["id"] for pb in tablet_def.get("pen_buttons", [])}:
        return True
    for c in tablet_def.get("controls", []):
        if c.get("type") == "button" and c.get("id") == slot_id:
            return True
    return False


def _make_profile_row_wrap(row: "ProfileListRow") -> QWidget:
    """Center the fixed-height row inside the list item (hover / selected backgrounds)."""
    wrap = QWidget()
    wrap.setObjectName("profileRowWrap")
    wrap.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
    vl = QVBoxLayout(wrap)
    vl.setContentsMargins(0, 0, 0, 0)
    vl.setSpacing(0)
    vl.addStretch(1)
    vl.addWidget(row)
    vl.addStretch(1)
    return wrap


class ProfileListRow(QWidget):
    """One profile row: icon, name, remove (visible when row is selected)."""

    removeRequested = pyqtSignal(str)

    def __init__(
        self,
        app_name: str,
        app_class: str,
        icon: QIcon,
        parent: Optional[QWidget] = None,
    ) -> None:
        super().__init__(parent)
        self._app_class = app_class
        self.setObjectName("profileListRow")
        self.setFixedHeight(_PROFILE_ROW_H)
        self.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed
        )

        lay = QHBoxLayout(self)
        lay.setContentsMargins(10, 0, 10, 0)
        lay.setSpacing(10)
        lay.setAlignment(Qt.AlignmentFlag.AlignVCenter)

        self._ic = QLabel()
        self._ic.setFixedSize(22, 22)
        self._ic.setScaledContents(True)
        self._ic.setAlignment(Qt.AlignmentFlag.AlignCenter)
        pm = icon.pixmap(QSize(22, 22))
        if pm and not pm.isNull():
            self._ic.setPixmap(pm)

        self._name = QLabel(app_name)
        self._name.setObjectName("profileRowName")
        self._name.setWordWrap(False)
        self._name.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter
        )
        self._name.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
        )

        self._remove = QToolButton()
        self._remove.setObjectName("profileRowRemoveBtn")
        self._remove.setText("✕")
        self._remove.setAutoRaise(True)
        self._remove.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextOnly)
        self._remove.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self._remove.setCursor(Qt.CursorShape.PointingHandCursor)
        self._remove.setToolTip("Remove profile")
        self._remove.setFixedSize(22, 22)
        self._remove.clicked.connect(lambda: self.removeRequested.emit(self._app_class))

        lay.addWidget(self._ic, 0, Qt.AlignmentFlag.AlignVCenter)
        lay.addWidget(self._name, 1, Qt.AlignmentFlag.AlignVCenter)
        lay.addWidget(self._remove, 0, Qt.AlignmentFlag.AlignVCenter)

        self.set_selected(False)

    def set_selected(self, selected: bool) -> None:
        self._remove.setVisible(selected)
        if selected:
            self._name.setStyleSheet(
                f"color: {theme.ACCENT_CYAN}; font-weight: 600;"
            )
        else:
            self._name.setStyleSheet(
                f"color: {theme.TEXT_MUTED}; font-weight: 500;"
            )


class MainWindow(QMainWindow):

    _sig_active_app = pyqtSignal(str, object)
    _sig_status     = pyqtSignal(str)
    _sig_capture_done = pyqtSignal(str)
    _sig_dial_popup = pyqtSignal(object)
    _sig_dial_overlay_event = pyqtSignal(object)

    def __init__(self, daemon: Daemon):
        super().__init__()
        self._daemon = daemon
        self._selected_class: Optional[str] = None
        self._selected_slot: int = -1
        self._capture_plan: Optional[dict] = None
        self._dial_overlay_proc = None
        self._dial_overlay_log = None
        tablet_def = _detect_tablet_def()
        self._tablet_def  = tablet_def
        self._total_slots = tablet_def.get("total_slots", 8)
        self._num_pen     = len(tablet_def.get("pen_buttons", []))
        self._control_total = (
            sum(1 for ctrl in tablet_def.get("controls", []) if ctrl["type"] == "button") +
            sum(1 for ctrl in tablet_def.get("controls", []) if ctrl["type"] == "dial")
        )
        self._current_tab = "tablet"

        self.setWindowTitle("autoswitch")
        self.setMinimumSize(1100, 600)
        self._build_ui()
        self.setStyleSheet(theme.MAIN_WINDOW_QSS)
        self._setup_tray()
        self._refresh_profile_list()

        self._sig_active_app.connect(self._update_active)
        self._sig_status.connect(self._status_bar.showMessage)
        self._sig_capture_done.connect(self._on_capture_done)
        self._sig_dial_popup.connect(self._on_dial_popup)
        self._sig_dial_overlay_event.connect(self._on_dial_overlay_event)
        daemon.set_status_callback(self._sig_status.emit)
        daemon.set_dial_popup_callback(self._sig_dial_popup.emit)
        daemon._on_change = lambda ac, pn: self._sig_active_app.emit(ac, pn)  # type: ignore
        qapp = QApplication.instance()
        if qapp is not None:
            qapp.aboutToQuit.connect(self._stop_dial_overlay)

    # ── UI ─────────────────────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        tb = QToolBar()
        tb.setMovable(False)
        tb.setIconSize(QSize(16, 16))
        self.addToolBar(tb)

        brand = QWidget()
        br = QHBoxLayout(brand)
        br.setContentsMargins(8, 0, 16, 0)
        br.setSpacing(6)
        _brand_title = QLabel("autoswitch")
        _brand_title.setObjectName("toolbarBrand")
        br.addWidget(_brand_title)
        tb.addWidget(brand)

        # ── Tab buttons ───────────────────────────────────────────────────────
        self._tablet_tab_btn = QToolButton()
        self._tablet_tab_btn.setObjectName("tabBtn")
        self._tablet_tab_btn.setText("Tablet")
        self._tablet_tab_btn.setCheckable(True)
        self._tablet_tab_btn.setChecked(True)
        self._tablet_tab_btn.clicked.connect(lambda: self._switch_to_tab("tablet"))
        tb.addWidget(self._tablet_tab_btn)

        self._pen_tab_btn = QToolButton()
        self._pen_tab_btn.setObjectName("tabBtn")
        self._pen_tab_btn.setText("Pen")
        self._pen_tab_btn.setCheckable(True)
        self._pen_tab_btn.setChecked(False)
        self._pen_tab_btn.clicked.connect(lambda: self._switch_to_tab("pen"))
        tb.addWidget(self._pen_tab_btn)

        spacer = QWidget()
        spacer.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)
        tb.addWidget(spacer)

        self._toggle_act = QAction("⏻  Enabled", self)
        self._toggle_act.setCheckable(True)
        self._toggle_act.setChecked(self._daemon.config.enabled)
        self._toggle_act.toggled.connect(self._on_toggle)
        tb.addAction(self._toggle_act)

        # ── Stacked content pages ─────────────────────────────────────────────
        self._stack = QStackedWidget()

        # ── PAGE 0: Tablet (profiles sidebar + canvas) ────────────────────────
        root = QSplitter(Qt.Orientation.Horizontal)
        root.setObjectName("mainSplitter")
        root.setHandleWidth(0)

        left = QWidget()
        left.setObjectName("profileSidebar")
        ll = QVBoxLayout(left)
        ll.setContentsMargins(14, 18, 14, 14)
        lbl = QLabel("Profiles")
        lbl.setObjectName("sidebarTitle")
        ll.addWidget(lbl)

        self._profile_list = QListWidget()
        self._profile_list.setIconSize(QSize(22, 22))
        left.setStyleSheet(theme.SIDEBAR_QSS)
        self._profile_list.currentItemChanged.connect(self._on_profile_select)
        self._profile_list.itemSelectionChanged.connect(self._sync_profile_row_styles)
        ll.addWidget(self._profile_list, 1)

        add_btn = QPushButton("＋  ADD PROFILE")
        add_btn.setObjectName("sidebarAdd")
        add_btn.clicked.connect(self._add_profile)
        ll.addWidget(add_btn)

        left.setMinimumWidth(200)
        left.setMaximumWidth(260)
        root.addWidget(left)

        centre = QWidget()
        centre.setObjectName("mainStage")
        centre.setStyleSheet(
            f"#mainStage {{ background: {theme.BG}; }}\n" + theme.RIGHT_RAIL_QSS
        )
        cl = QVBoxLayout(centre)
        cl.setContentsMargins(0, 0, 0, 0)
        cl.setSpacing(0)

        title_block = QWidget()
        tbl = QVBoxLayout(title_block)
        tbl.setContentsMargins(20, 18, 20, 6)
        tbl.setSpacing(4)
        kicker = QLabel("HARDWARE LAYOUT MAPPING")
        kicker.setObjectName("deviceKicker")
        dev_name = QLabel(self._tablet_def.get("name", "Tablet"))
        dev_name.setObjectName("deviceName")
        tbl.addWidget(kicker)
        tbl.addWidget(dev_name)
        cl.addWidget(title_block)

        hdr = QWidget()
        hdr.setObjectName("profileHeader")
        hdrl = QHBoxLayout(hdr)
        hdrl.setContentsMargins(20, 8, 20, 12)
        self._profile_title_icon = QLabel()
        self._profile_title_icon.setFixedSize(28, 28)
        self._profile_title_icon.setScaledContents(True)
        self._profile_title_icon.hide()
        self._profile_title = QLabel("Select a profile")
        self._profile_title.setObjectName("profileTitle")
        self._active_indicator = QLabel("")
        self._active_indicator.setObjectName("activePill")
        self._keys_lbl = QLabel("")
        self._keys_lbl.setObjectName("keysMeta")
        hdr.setStyleSheet(theme.HEADER_QSS)
        hdrl.addWidget(self._profile_title_icon)
        hdrl.addWidget(self._profile_title)
        hdrl.addSpacing(10)
        hdrl.addWidget(self._active_indicator)
        hdrl.addStretch()
        hdrl.addWidget(self._keys_lbl)
        cl.addWidget(hdr)

        profile_rule = QFrame()
        profile_rule.setObjectName("profileRule")
        profile_rule.setFixedHeight(1)
        profile_rule.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        cl.addWidget(profile_rule)

        self._rail_meta = QLabel("Choose a profile to begin.")
        self._rail_meta.setObjectName("railMeta")
        self._rail_meta.setWordWrap(True)
        meta_row = QWidget()
        mrl = QHBoxLayout(meta_row)
        mrl.setContentsMargins(20, 0, 20, 10)
        mrl.setSpacing(0)
        mrl.addWidget(self._rail_meta, 1)
        cl.addWidget(meta_row)

        device_frame = QFrame()
        device_frame.setObjectName("deviceFrame")
        dfl = QVBoxLayout(device_frame)
        dfl.setContentsMargins(0, 0, 0, 0)
        dfl.setSpacing(0)

        self._canvas = TabletCanvas(self._tablet_def)
        self._canvas.slot_clicked.connect(self._on_slot_clicked)
        self._canvas.empty_clicked.connect(self._hide_mapping_popup)
        dfl.addWidget(self._canvas, 1)
        cl.addWidget(device_frame, 1)

        root.addWidget(centre)
        root.setStretchFactor(0, 0)
        root.setStretchFactor(1, 1)
        self._stack.addWidget(root)   # page 0

        # ── PAGE 1: Pen ────────────────────────────────────────────────────────
        pen_page = QWidget()
        pen_page.setStyleSheet(f"background: {theme.BG};")
        pen_pl = QVBoxLayout(pen_page)
        pen_pl.setContentsMargins(0, 0, 0, 0)
        pen_pl.setSpacing(0)

        # Profile indicator bar
        pen_hdr = QWidget()
        pen_hdr.setStyleSheet(
            f"background: {theme.BG_ELEV}; border-bottom: 1px solid {theme.BORDER_SUBTLE};"
        )
        pen_hdrl = QHBoxLayout(pen_hdr)
        pen_hdrl.setContentsMargins(20, 10, 20, 10)
        pen_profile_icon_lbl = QLabel("✒")
        pen_profile_icon_lbl.setStyleSheet(
            f"color: {theme.TEXT_FAINT}; font-size: 13px; background: transparent; border: none;"
        )
        pen_hdrl.addWidget(pen_profile_icon_lbl)
        pen_hdrl.addSpacing(6)
        self._pen_profile_lbl = QLabel("No profile selected")
        self._pen_profile_lbl.setStyleSheet(
            f"color: {theme.TEXT}; font-size: 13px; font-weight: 600; background: transparent; border: none;"
        )
        pen_hdrl.addWidget(self._pen_profile_lbl)
        pen_hdrl.addStretch()
        pen_hint = QLabel("click a button to bind")
        pen_hint.setStyleSheet(
            f"color: {theme.TEXT_FAINT}; font-size: 10px; background: transparent; border: none;"
        )
        pen_hdrl.addWidget(pen_hint)
        pen_pl.addWidget(pen_hdr)

        pen_def = self._tablet_def
        pen_btns = pen_def.get("pen_buttons", [])
        pen_svg  = pen_def.get("pen_svg")
        if hasattr(sys, "_MEIPASS"):
            base_path = Path(sys._MEIPASS)
        else:
            base_path = Path(__file__).parent.parent
        pen_svg_path = Path(pen_svg) if pen_svg else base_path / "assets/tablets/pen.svg"

        self._pen_canvas = PenCanvas(pen_btns, pen_svg_path, pen_page)
        self._pen_canvas.slot_clicked.connect(self._on_slot_clicked)
        self._pen_canvas.empty_clicked.connect(self._hide_mapping_popup)
        pen_pl.addWidget(self._pen_canvas, 1)

        self._stack.addWidget(pen_page)  # page 1

        # ── Shared mapping panel (re-parented on tab switch) ──────────────────
        self._mapping = MappingPanel(self._canvas)
        self._mapping.binding_changed.connect(self._on_binding_changed)
        self._mapping.capture_requested.connect(self._on_capture_requested)
        self._mapping.close_requested.connect(self._hide_mapping_popup)
        self._mapping.hide()
        self._mapping.raise_()
        self._dial_popup = DialModePopup(self)

        self.setCentralWidget(self._stack)

        self._status_bar = QStatusBar()
        self.setStatusBar(self._status_bar)
        self._status_bar.showMessage(f"Tablet: {self._tablet_def['name']}")

    # ── tab switching ─────────────────────────────────────────────────────────

    def _switch_to_tab(self, tab: str) -> None:
        if tab == self._current_tab:
            return
        self._current_tab = tab
        self._hide_mapping_popup()
        if tab == "pen":
            self._mapping.setParent(self._pen_canvas)
            self._tablet_tab_btn.setChecked(False)
            self._pen_tab_btn.setChecked(True)
            self._stack.setCurrentIndex(1)
        else:
            self._mapping.setParent(self._canvas)
            self._tablet_tab_btn.setChecked(True)
            self._pen_tab_btn.setChecked(False)
            self._stack.setCurrentIndex(0)
        self._mapping.hide()

    def _active_canvas(self):
        return self._pen_canvas if self._current_tab == "pen" else self._canvas

    # ── tray ───────────────────────────────────────────────────────────────────

    def _setup_tray(self) -> None:
        self._tray = QSystemTrayIcon(self)
        self._tray.setToolTip("autswitch")
        self._tray.setIcon(self.style().standardIcon(
            self.style().StandardPixmap.SP_ComputerIcon
        ))
        menu = QMenu()
        menu.addAction(QAction("Show", self, triggered=self.show))
        self._tray_toggle = QAction("Enabled", self)
        self._tray_toggle.setCheckable(True)
        self._tray_toggle.setChecked(self._daemon.config.enabled)
        self._tray_toggle.toggled.connect(self._on_toggle)
        menu.addAction(self._tray_toggle)
        menu.addSeparator()
        menu.addAction(QAction("Quit", self, triggered=QApplication.quit))
        self._tray.setContextMenu(menu)
        self._tray.activated.connect(self._on_tray_activated)
        self._tray.show()

    # ── profile list ───────────────────────────────────────────────────────────

    def _refresh_profile_list(self) -> None:
        self._profile_list.blockSignals(True)
        self._profile_list.clear()
        profiles = sorted(
            self._daemon.config.profiles.values(),
            key=lambda p: p.app_name.lower(),
        )
        for profile in profiles:
            item = QListWidgetItem()
            item.setData(Qt.ItemDataRole.UserRole, profile.app_class)
            item.setToolTip(profile.app_name)
            row = ProfileListRow(
                profile.app_name,
                profile.app_class,
                icon_from_stored(profile.icon, profile.app_class),
            )
            row.removeRequested.connect(self._on_profile_row_remove)
            self._profile_list.addItem(item)
            self._profile_list.setItemWidget(item, _make_profile_row_wrap(row))
            vw = self._profile_list.viewport().width()
            w = max(160, vw) if vw > 0 else 220
            item.setSizeHint(QSize(w, _PROFILE_ITEM_H))
        self._profile_list.blockSignals(False)
        if self._selected_class:
            self._select_class(self._selected_class)
        else:
            self._profile_list.clearSelection()
            self._clear_profile_stage()
        self._sync_profile_row_styles()

    def _profile_row_for_item(self, item: QListWidgetItem) -> Optional[ProfileListRow]:
        w = self._profile_list.itemWidget(item)
        if w is None:
            return None
        if isinstance(w, ProfileListRow):
            return w
        return w.findChild(ProfileListRow)

    def _sync_profile_row_styles(self) -> None:
        for i in range(self._profile_list.count()):
            item = self._profile_list.item(i)
            row = self._profile_row_for_item(item)
            if row is not None:
                row.set_selected(item.isSelected())

    def _select_class(self, app_class: str) -> None:
        for i in range(self._profile_list.count()):
            item = self._profile_list.item(i)
            if item.data(Qt.ItemDataRole.UserRole) == app_class:
                self._profile_list.setCurrentItem(item)
                return
        self._profile_list.clearSelection()

    def _clear_profile_stage(self) -> None:
        self._canvas.clear()
        self._pen_canvas.clear()
        self._hide_mapping_popup()
        self._profile_title.setText("Select a profile")
        self._profile_title_icon.hide()
        self._active_indicator.setText("")
        self._keys_lbl.setText("")
        self._rail_meta.setText("Choose a profile to begin.")

    @pyqtSlot()
    def _add_profile(self) -> None:
        dlg = ProfileDialog(active_class=self._daemon.active_class, parent=self)
        dlg.saved.connect(self._on_profile_saved)
        dlg.exec()

    def _remove_profile(self, app_class: Optional[str] = None) -> None:
        ac = app_class if app_class is not None else self._selected_class
        if not ac:
            return
        profile = self._daemon.config.profiles.get(ac)
        if not profile:
            return
        if QMessageBox.question(
            self, "Remove", f"Remove profile for <b>{profile.app_name}</b>?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) == QMessageBox.StandardButton.Yes:
            del self._daemon.config.profiles[ac]
            self._daemon.save()
            self._selected_class = None
            self._selected_slot = -1
            self._refresh_profile_list()

    @pyqtSlot(str)
    def _on_profile_row_remove(self, app_class: str) -> None:
        self._remove_profile(app_class)

    @pyqtSlot(str, str, str)
    def _on_profile_saved(self, app_class: str, app_name: str, icon: str) -> None:
        from models import Profile
        if app_class not in self._daemon.config.profiles:
            self._daemon.config.profiles[app_class] = Profile(
                app_class=app_class, app_name=app_name, icon=icon
            )
        else:
            p = self._daemon.config.profiles[app_class]
            p.app_name = app_name
            p.icon = icon
        self._daemon.save()
        self._selected_class = app_class
        self._refresh_profile_list()
        self._show_profile(self._daemon.config.profiles[app_class])

    @pyqtSlot(QListWidgetItem, QListWidgetItem)
    def _on_profile_select(self, current, _prev) -> None:
        if not current:
            self._selected_class = None
            self._clear_profile_stage()
            return
        app_class = current.data(Qt.ItemDataRole.UserRole)
        self._selected_class = app_class
        self._show_profile(self._daemon.config.profiles.get(app_class))

    # ── canvas population ──────────────────────────────────────────────────────

    def _show_profile(self, profile: Optional[Profile]) -> None:
        if not profile:
            self._canvas.clear()
            self._pen_canvas.clear()
            self._hide_mapping_popup()
            self._profile_title_icon.hide()
            self._rail_meta.setText("Choose a profile to begin.")
            self._pen_profile_lbl.setText("No profile selected")
            return

        is_active = profile.app_class == self._daemon.active_class
        self._profile_title.setText(profile.app_name)
        ic = icon_from_stored(profile.icon, profile.app_class)
        pm = ic.pixmap(QSize(22, 22))
        if pm and not pm.isNull():
            self._profile_title_icon.setPixmap(pm)
            self._profile_title_icon.show()
        else:
            self._profile_title_icon.hide()
        self._active_indicator.setText("● ACTIVE" if is_active else "")

        slots = self._build_slots(profile)
        self._canvas.set_profile(slots, active=is_active)

        # Feed pen button slots (positional) to the pen canvas
        pen_btns = self._tablet_def.get("pen_buttons", [])
        pen_slots = [
            slots[pb["id"]] if 0 <= pb["id"] < len(slots) else ("", "", "")
            for pb in pen_btns
        ]
        self._pen_canvas.set_profile(pen_slots, active=is_active)
        status = "  ● ACTIVE" if is_active else ""
        self._pen_profile_lbl.setText(f"{profile.app_name}{status}")

        mapped = self._mapped_count(profile)
        self._keys_lbl.setText(f"{mapped} of {self._control_total} controls mapped")
        self._rail_meta.setText(
            f"Profile · {profile.app_name}\n"
            f"Window class · {profile.app_class}"
        )

    def _build_slots(self, profile: Profile) -> list[tuple[str, str, str]]:
        """Build flat (keycode, combo, label) list indexed by slot_id."""
        total = self._total_slots + self._num_pen
        result: list[tuple[str, str, str]] = [("", "", "")] * total
        for sid in range(self._total_slots):
            kc, act = profile.get_slot(sid)
            if act:
                if (getattr(act, "keys_double", "") or "").strip():
                    lb = act.label or act.keys or "—"
                    ld = act.label_double or act.keys_double or "—"
                    result[sid] = (kc, act.keys, f"{lb} / {ld}")
                else:
                    result[sid] = (kc, act.keys, act.label)
        for dial_id, dial in profile.dials.items():
            try:
                ring_slot = int(dial_id)
            except ValueError:
                continue
            modes = sanitize_modes(dial.modes)
            summary = self._dial_modes_summary(modes)
            binding = self._dial_binding_key(*self._auto_dial_bindings(dial_id))
            if 0 <= ring_slot < len(result):
                result[ring_slot] = (binding, self._serialize_dial_modes(modes), summary)
        return result

    # ── slot click → mapping panel ─────────────────────────────────────────────

    @pyqtSlot(int)
    def _on_slot_clicked(self, slot_id: int) -> None:
        if not self._selected_class:
            return
        self._selected_slot = slot_id
        profile = self._daemon.config.profiles.get(self._selected_class)
        if not profile:
            return

        canvas = self._active_canvas()
        canvas.set_selected_slot(slot_id)
        slot_name = canvas._slot_name(slot_id)
        slot_mode = canvas.slot_mode(slot_id)
        if slot_mode == "dial_modes":
            kc, combo, label = self._dial_editor_state(profile, slot_id)
        else:
            kc, act = profile.get_slot(slot_id)
            combo, label = _pen_profile_combo_label(act)
            # Pen buttons have a fixed known keycode — auto-fill so user skips Link step
            pen_btns = self._tablet_def.get("pen_buttons", [])
            pen_ids = {pb["id"]: pb for pb in pen_btns}
            if slot_id in pen_ids and not kc:
                kc = f"PENBTN:{slot_id - 10}"
                # Persist the auto-linked keycode immediately so Apply works
                if combo:
                    profile.set_slot(
                        slot_id,
                        kc,
                        _button_action_from_mapping_combo(combo, label, allow_dual_json=True),
                    )
                    self._daemon.save()
        is_pen = slot_id in {pb["id"] for pb in self._tablet_def.get("pen_buttons", [])}
        dual_binding = _slot_supports_dual_binding(self._tablet_def, slot_id)
        self._mapping.show_slot(
            slot_id, slot_name, kc, combo, label, slot_mode,
            is_pen=is_pen, dual_binding=dual_binding,
        )
        self._position_mapping_popup(slot_id)
        self._mapping.show()
        self._mapping.raise_()
        self._mapping.activateWindow()

    def _on_binding_changed(self, keycode: str, combo: str, label: str) -> None:
        if not self._selected_class or self._selected_slot < 0:
            return
        profile = self._daemon.config.profiles.get(self._selected_class)
        if not profile:
            return

        canvas = self._active_canvas()
        slot_mode = canvas.slot_mode(self._selected_slot)
        if slot_mode == "dial_modes":
            switch_id, ccw_id, cw_id = canvas.slot_members(self._selected_slot)
            dial_id = self._dial_id_for_slot(self._selected_slot)
            if not combo:
                profile.clear_dial(dial_id)
                profile.clear_slot(switch_id)
                profile.clear_slot(ccw_id)
                profile.clear_slot(cw_id)
                self._status_bar.showMessage("Dial mapping cleared.")
            else:
                modes = self._deserialize_dial_modes(combo)
                if not modes:
                    self._status_bar.showMessage("Choose at least one dial mode.")
                    return
                switch_key, ccw_key, cw_key = self._auto_dial_bindings(dial_id)
                profile.clear_slot(switch_id)
                profile.clear_slot(ccw_id)
                profile.clear_slot(cw_id)
                profile.set_dial(
                    dial_id,
                    DialConfig(
                        label=slot_name if (slot_name := canvas._slot_name(self._selected_slot)) else "Dial",
                        switch_key=switch_key,
                        ccw_key=ccw_key,
                        cw_key=cw_key,
                        modes=modes,
                    ),
                )
                self._status_bar.showMessage("Dial radial menu saved.")
            self._daemon.save()
            self._show_profile(profile)
            self._position_mapping_popup(self._selected_slot)
            return

        if combo and not keycode:
            self._status_bar.showMessage("Link the selected control first, then apply its action.")
            return

        if keycode and combo:
            dual_slot = _slot_supports_dual_binding(self._tablet_def, self._selected_slot)
            if dual_slot and combo.strip().startswith("{"):
                try:
                    o = json.loads(combo)
                    if str(o.get("double", "")).strip() and not str(o.get("single", "")).strip():
                        self._status_bar.showMessage(
                            "Set a single (hold) shortcut when using a double-tap shortcut."
                        )
                        return
                except json.JSONDecodeError:
                    pass
            profile.set_slot(
                self._selected_slot,
                keycode,
                _button_action_from_mapping_combo(combo, label, allow_dual_json=dual_slot),
            )
        else:
            profile.clear_slot(self._selected_slot)

        self._daemon.save()
        self._show_profile(profile)
        self._position_mapping_popup(self._selected_slot)
        self._status_bar.showMessage("Button mapping saved.")

    # ── capture mode ───────────────────────────────────────────────────────────

    def _on_capture_requested(self) -> None:
        if self._mapping._cap_btn.isChecked():
            if self._selected_slot >= 0 and self._active_canvas().slot_mode(self._selected_slot) == "dial_modes":
                self._mapping.set_capture_active(False)
                self._status_bar.showMessage("Dial controls are detected automatically.")
                return
            else:
                self._capture_plan = {"type": "button", "slot": self._selected_slot}
            self._daemon.set_capture_mode(self._sig_capture_done.emit)
        else:
            self._capture_plan = None
            self._daemon.set_capture_mode(None)

    @pyqtSlot(str)
    def _on_capture_done(self, name: str) -> None:
        plan = self._capture_plan or {}
        if plan.get("type") == "dial_modes":
            self._capture_plan = None
            self._daemon.set_capture_mode(None)
            dial_key = self._updated_dial_binding_for_capture(name)
            if not dial_key:
                self._status_bar.showMessage("Could not identify that dial action. Try pressing the center or rotating once.")
                self._mapping.set_capture_active(False)
                return
            self._mapping.set_captured_key(dial_key)
            self._status_bar.showMessage(f"Linked {self._dial_capture_label(name)}.")
            return

        self._capture_plan = None
        self._daemon.set_capture_mode(None)
        self._mapping.set_captured_key(name)
        self._status_bar.showMessage(f"Linked control to {self._mapping._display_binding_id(name)}")

    def _position_mapping_popup(self, slot_id: int) -> None:
        canvas = self._active_canvas()
        self._mapping.adjustSize()
        geom = canvas.popup_geometry(slot_id, self._mapping.size())
        self._mapping.setGeometry(geom)
        canvas.set_editor_rect(geom)

    def _hide_mapping_popup(self) -> None:
        self._capture_plan = None
        self._daemon.set_capture_mode(None)
        self._mapping.set_capture_active(False)
        self._mapping.hide()
        canvas = self._active_canvas()
        canvas.set_selected_slot(-1)
        canvas.set_editor_rect(None)
        self._selected_slot = -1

    @pyqtSlot(object)
    def _on_dial_popup(self, payload: object) -> None:
        if not isinstance(payload, dict):
            return
        if payload.get("app_class") != self._daemon.active_class:
            self._dial_popup.hide()
            self._stop_dial_overlay()
            return
        self._dial_popup.hide()
        if not self._show_dial_overlay(payload):
            self._status_bar.showMessage("Could not open the dial radial menu.")

    @pyqtSlot(object)
    def _on_dial_overlay_event(self, payload: object) -> None:
        if not isinstance(payload, dict):
            return
        if payload.get("type") != "select":
            return
        app_class = str(payload.get("app_class") or "")
        dial_id = str(payload.get("dial_id") or "")
        try:
            selected_index = int(payload.get("selected_index", 0))
        except (TypeError, ValueError):
            return
        if not app_class:
            return
        if not dial_id:
            return
        self._daemon.set_dial_mode_selection(app_class, dial_id, selected_index)
        self._stop_dial_overlay()

    def _show_dial_overlay(self, payload: dict) -> bool:
        proc = self._ensure_dial_overlay()
        if proc is None or proc.stdin is None:
            return False
        try:
            proc.stdin.write(json.dumps(payload) + "\n")
            proc.stdin.flush()
            return True
        except (BrokenPipeError, OSError, ValueError):
            self._stop_dial_overlay()
            proc = self._ensure_dial_overlay()
            if proc is None or proc.stdin is None:
                return False
            try:
                proc.stdin.write(json.dumps(payload) + "\n")
                proc.stdin.flush()
                return True
            except (BrokenPipeError, OSError, ValueError):
                self._stop_dial_overlay()
                return False

    def _ensure_dial_overlay(self):
        if self._dial_overlay_proc is not None and self._dial_overlay_proc.poll() is None:
            return self._dial_overlay_proc
        self._stop_dial_overlay()
        helper = Path(__file__).with_name("dial_overlay_helper.py")
        try:
            self._dial_overlay_log = open("/tmp/autswitch-dial-overlay.log", "a", encoding="utf-8")
            self._dial_overlay_proc = subprocess.Popen(
                ["/usr/bin/python3", str(helper)],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=self._dial_overlay_log,
                text=True,
                bufsize=1,
            )
            if self._dial_overlay_proc.stdout is not None:
                threading.Thread(
                    target=self._read_dial_overlay_events,
                    args=(self._dial_overlay_proc,),
                    daemon=True,
                    name="dial-overlay-events",
                ).start()
        except OSError:
            self._dial_overlay_proc = None
            if self._dial_overlay_log is not None:
                self._dial_overlay_log.close()
                self._dial_overlay_log = None
        return self._dial_overlay_proc

    def _read_dial_overlay_events(self, proc) -> None:
        stream = proc.stdout
        if stream is None:
            return
        try:
            for line in stream:
                text = line.strip()
                if not text:
                    continue
                try:
                    payload = json.loads(text)
                except json.JSONDecodeError:
                    continue
                self._sig_dial_overlay_event.emit(payload)
        finally:
            try:
                stream.close()
            except OSError:
                pass

    def _stop_dial_overlay(self) -> None:
        proc = self._dial_overlay_proc
        self._dial_overlay_proc = None
        if proc is None:
            return
        try:
            if proc.stdin is not None:
                proc.stdin.close()
        except OSError:
            pass
        if proc.poll() is None:
            try:
                proc.terminate()
                proc.wait(timeout=0.5)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass
        if self._dial_overlay_log is not None:
            try:
                self._dial_overlay_log.close()
            except OSError:
                pass
            self._dial_overlay_log = None

    def _dial_editor_state(self, profile: Profile, slot_id: int) -> tuple[str, str, str]:
        dial_id = self._dial_id_for_slot(slot_id)
        dial = profile.dials.get(dial_id)
        if not dial:
            defaults = default_modes_for_app(profile.app_class)
            return self._dial_binding_key(*self._auto_dial_bindings(dial_id)), self._serialize_dial_modes(defaults), self._dial_modes_summary(defaults)
        binding = self._dial_binding_key(*self._auto_dial_bindings(dial_id))
        modes = sanitize_modes(dial.modes) or default_modes_for_app(profile.app_class)
        return binding, self._serialize_dial_modes(modes), self._dial_modes_summary(modes)

    def _auto_dial_bindings(self, dial_id: str) -> tuple[str, str, str]:
        return (
            f"VENDORDIAL:{dial_id}:press",
            f"VENDORDIAL:{dial_id}:ccw",
            f"VENDORDIAL:{dial_id}:cw",
        )

    def _serialize_dial_modes(self, modes: list) -> str:
        return json.dumps(sanitize_modes(modes))

    def _deserialize_dial_modes(self, raw: str) -> list[dict]:
        if not raw:
            return []
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            data = [item for item in raw.split("|") if item]
        if not isinstance(data, list):
            return []
        return sanitize_modes(data)

    def _dial_modes_summary(self, modes: list) -> str:
        return " / ".join(mode_label(mode) for mode in sanitize_modes(modes))

    def _dial_binding_key(self, switch_key: str, ccw_key: str, cw_key: str) -> str:
        return f"DIAL:{switch_key or '?'}|{ccw_key or '?'}|{cw_key or '?'}"

    def _parse_dial_binding(self, keycode: str) -> Optional[tuple[str, str, str]]:
        if not keycode.startswith("DIAL:"):
            return None
        body = keycode.removeprefix("DIAL:")
        switch_key, _, rest = body.partition("|")
        ccw_key, _, cw_key = rest.partition("|")
        return (
            "" if switch_key == "?" else switch_key,
            "" if ccw_key == "?" else ccw_key,
            "" if cw_key == "?" else cw_key,
        )

    def _merged_dial_binding(self, profile: Profile, dial_id: str, keycode: str) -> tuple[str, str, str]:
        existing = profile.dials.get(dial_id)
        parsed = self._parse_dial_binding(keycode)
        if parsed is None:
            return (
                existing.switch_key if existing else "",
                existing.ccw_key if existing else "",
                existing.cw_key if existing else "",
            )

        switch_key, ccw_key, cw_key = parsed
        return (
            switch_key or (existing.switch_key if existing else ""),
            ccw_key or (existing.ccw_key if existing else ""),
            cw_key or (existing.cw_key if existing else ""),
        )

    def _updated_dial_binding_for_capture(self, captured: str) -> str:
        if not self._selected_class or self._selected_slot < 0:
            return ""
        profile = self._daemon.config.profiles.get(self._selected_class)
        if not profile:
            return ""

        dial_id = self._dial_id_for_slot(self._selected_slot)
        switch_key, ccw_key, cw_key = self._merged_dial_binding(profile, dial_id, "")

        part = self._dial_capture_part(captured)
        if part == "switch":
            switch_key = captured if captured.startswith("VENDORDIAL:") else self._dial_switch_binding(dial_id, captured)
        elif part == "ccw":
            ccw_key = captured
        elif part == "cw":
            cw_key = captured
        else:
            return ""
        return self._dial_binding_key(switch_key, ccw_key, cw_key)

    def _dial_switch_binding(self, dial_id: str, captured: str) -> str:
        return f"DIALSW:{dial_id}:{captured}"

    def _dial_capture_part(self, captured: str) -> str:
        if captured.startswith("VENDORDIAL:"):
            _, _, part = captured.split(":", 2)
            return {
                "press": "switch",
                "ccw": "ccw",
                "cw": "cw",
            }.get(part, "")
        if captured.startswith("RAWDIAL:"):
            event = captured.rsplit(":", 1)[-1]
            return {
                "press": "switch",
                "neg": "ccw",
                "pos": "cw",
            }.get(event, "")
        return ""

    def _dial_capture_label(self, captured: str) -> str:
        return {
            "switch": "dial center button",
            "ccw": "dial counter-clockwise rotation",
            "cw": "dial clockwise rotation",
        }.get(self._dial_capture_part(captured), "dial input")

    def _dial_id_for_slot(self, slot_id: int) -> str:
        switch_id, ccw_id, cw_id = self._canvas.slot_members(slot_id)
        _ = switch_id
        return str(ccw_id)

    def _mapped_count(self, profile: Profile) -> int:
        button_ids = [
            ctrl["id"] for ctrl in self._tablet_def.get("controls", [])
            if ctrl["type"] == "button"
        ]
        button_ids.extend(pb["id"] for pb in self._tablet_def.get("pen_buttons", []))
        button_count = sum(1 for sid in button_ids if profile.get_slot(sid)[1])
        dial_count = sum(1 for dial in profile.dials.values() if sanitize_modes(dial.modes))
        return button_count + dial_count

    # ── cross-thread callbacks ─────────────────────────────────────────────────

    @pyqtSlot(str, object)
    def _update_active(self, app_class: str, profile_name) -> None:
        self._stop_dial_overlay()
        if profile_name:
            self._tray.setToolTip(f"autswitch – {profile_name}")
            self._status_bar.showMessage(f"Profile: {profile_name}  [{app_class}]")
        else:
            self._tray.setToolTip("autswitch – no profile")
            self._status_bar.showMessage(f"No profile for [{app_class}]")
            self._dial_popup.hide()

        if self._selected_class:
            profile = self._daemon.config.profiles.get(self._selected_class)
            if profile:
                is_active = profile.app_class == app_class
                self._active_indicator.setText("● ACTIVE" if is_active else "")
                slots = self._build_slots(profile)
                self._canvas.set_profile(slots, active=is_active)

    @pyqtSlot(bool)
    def _on_toggle(self, checked: bool) -> None:
        self._daemon.config.enabled = checked
        self._daemon.save()
        self._toggle_act.setChecked(checked)
        self._tray_toggle.setChecked(checked)
        self._status_bar.showMessage("Remapping " + ("enabled" if checked else "disabled"))

    def _on_tray_activated(self, reason) -> None:
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self.hide() if self.isVisible() else (self.show(), self.raise_(),
                                                  self.activateWindow())

    def resizeEvent(self, event) -> None:
        super().resizeEvent(event)
        self._sync_profile_item_widths()
        if self._mapping.isVisible() and self._selected_slot >= 0:
            self._position_mapping_popup(self._selected_slot)

    def _sync_profile_item_widths(self) -> None:
        vw = self._profile_list.viewport().width()
        w = max(160, vw) if vw > 0 else 220
        for i in range(self._profile_list.count()):
            self._profile_list.item(i).setSizeHint(QSize(w, _PROFILE_ITEM_H))

    def closeEvent(self, event) -> None:
        event.ignore()
        self.hide()
        self._tray.showMessage("autswitch", "Running in tray.",
                               QSystemTrayIcon.MessageIcon.Information, 2000)


# ── tablet detection ───────────────────────────────────────────────────────────

def _detect_tablet_def() -> dict:
    """Read USB IDs from local input metadata and match to a known tablet definition."""
    proc_devices = Path("/proc/bus/input/devices")
    if proc_devices.exists():
        try:
            text = proc_devices.read_text()
            blocks = [block for block in text.split("\n\n") if "HUION" in block.upper()]
            for block in blocks:
                match = re.search(
                    r"Vendor=([0-9a-fA-F]{4}) Product=([0-9a-fA-F]{4})",
                    block,
                )
                if not match:
                    continue
                vid, pid = (part.lower() for part in match.groups())
                defn = get_definition(vid, pid)
                if defn["name"] != "Generic Tablet":
                    return defn
        except OSError:
            pass

    try:
        import subprocess
        out = subprocess.check_output(["lsusb"], text=True, timeout=3)
        for line in out.splitlines():
            parts = line.split()
            # lsusb format: "Bus 001 Device 002: ID 256c:2008 …"
            for p in parts:
                if ":" in p and len(p) == 9:
                    vid, pid = p.lower().split(":", 1)
                    defn = get_definition(vid, pid)
                    if defn["name"] != "Generic Tablet":
                        return defn
    except Exception:
        pass
    return get_definition("", "")
