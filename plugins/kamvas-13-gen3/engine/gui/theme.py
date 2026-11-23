"""Central UI tokens — dark, minimal, single cool accent."""

from __future__ import annotations

from PyQt6.QtGui import QColor

# ── hex tokens (stylesheets & reference) ─────────────────────────────────────
BG = "#0c0d10"
BG_ELEV = "#111218"
SURFACE = "#15161d"
SURFACE_HOVER = "#1a1b24"
# Brighter than SURFACE_HOVER — clear hover lift while keeping the same radii/shapes
HOVER_LIFT = "#2e303c"
BORDER = "#2a2c38"
BORDER_SUBTLE = "#1e2028"
ACCENT = "#7a9fd9"
ACCENT_DIM = "#5a6d9a"
ACCENT_GLOW = "rgba(122, 159, 217, 0.18)"
# Cyan rail (Obsidian-style HUD) — sidebar selection bar + highlights
ACCENT_CYAN = "#22d4ee"
ACCENT_CYAN_DIM = "rgba(34, 211, 238, 0.12)"
ACCENT_CYAN_GLOW = "rgba(34, 211, 238, 0.18)"
TEXT = "#e9e9ee"
TEXT_MUTED = "#8b8c98"
TEXT_FAINT = "#5a5b66"
DANGER = "#c47a7a"
SUCCESS = "#8fb89a"

# Qt stylesheet fragments
MAIN_WINDOW_QSS = f"""
QMainWindow {{
    background: {BG};
}}
QToolBar {{
    background: {BG_ELEV};
    border: none;
    border-bottom: 1px solid {BORDER_SUBTLE};
    padding: 6px 8px;
    spacing: 6px;
}}
QToolBar QToolButton {{
    background: transparent;
    color: {TEXT_MUTED};
    border: 1px solid transparent;
    border-radius: 6px;
    padding: 6px 12px;
    font-size: 12px;
}}
QToolBar QToolButton:hover {{
    background: {HOVER_LIFT};
    color: {TEXT};
}}
QToolBar QToolButton:checked {{
    background: {SURFACE};
    color: {ACCENT_CYAN};
    border: 1px solid {BORDER};
}}
QLabel#toolbarBrand {{
    color: {TEXT};
    font-size: 13px;
    font-weight: 700;
    letter-spacing: 0.06em;
    padding: 0 8px 0 4px;
}}
QToolButton#tabBtn {{
    background: transparent;
    color: {TEXT_MUTED};
    border: 1px solid transparent;
    border-radius: 6px;
    padding: 5px 16px;
    font-size: 12px;
    font-weight: 500;
}}
QToolButton#tabBtn:checked {{
    background: {SURFACE};
    color: {ACCENT_CYAN};
    border: 1px solid {BORDER};
}}
QToolButton#tabBtn:hover:!checked {{
    background: {HOVER_LIFT};
    color: {TEXT};
}}
QSplitter#mainSplitter::handle:horizontal {{
    background: transparent;
    width: 0px;
}}
QStatusBar {{
    background: {BG};
    color: {TEXT_FAINT};
    border-top: 1px solid {BORDER_SUBTLE};
    font-size: 11px;
    padding: 4px 8px;
}}
"""

SIDEBAR_QSS = f"""
QWidget#profileSidebar {{
    background: {BG_ELEV};
    border: none;
}}
QLabel#sidebarTitle {{
    color: {TEXT_MUTED};
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    padding: 4px 2px 8px 2px;
}}
QWidget#profileRowWrap {{
    background: transparent;
}}
QWidget#profileListRow {{
    background: transparent;
}}
QLabel#profileRowName {{
    font-size: 13px;
    padding: 0px;
    margin: 0px;
}}
QToolButton#profileRowRemoveBtn {{
    background: transparent;
    color: {TEXT_MUTED};
    border: none;
    border-radius: 3px;
    font-size: 12px;
    font-weight: 600;
    padding: 0px;
    margin: 0px;
    min-width: 22px;
    min-height: 22px;
    max-width: 22px;
    max-height: 22px;
}}
QToolButton#profileRowRemoveBtn:hover {{
    background: rgba(196, 122, 122, 0.22);
    color: {DANGER};
}}
QToolButton#profileRowRemoveBtn:focus {{
    outline: none;
}}
QListWidget {{
    background: transparent;
    border: none;
    outline: none;
    padding: 0px;
}}
QListWidget::item {{
    padding: 0px;
    color: {TEXT_MUTED};
    border-radius: 6px;
    margin: 5px 8px;
    min-height: 54px;
    border-left: 3px solid transparent;
}}
QListWidget::item:selected {{
    background: {ACCENT_CYAN_DIM};
    color: {ACCENT_CYAN};
    border: 1px solid rgba(34, 211, 238, 0.25);
    border-left: 3px solid {ACCENT_CYAN};
}}
QListWidget::item:hover:!selected {{
    background: {HOVER_LIFT};
    color: {TEXT};
}}
QPushButton#sidebarAdd {{
    background: transparent;
    color: {ACCENT_CYAN};
    border: 1px dashed rgba(34, 211, 238, 0.35);
    border-radius: 8px;
    padding: 10px 12px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.06em;
}}
QPushButton#sidebarAdd:hover {{
    background: {ACCENT_CYAN_GLOW};
    border-style: solid;
}}
"""

RIGHT_RAIL_QSS = f"""
QWidget#rightRail {{
    background: {BG_ELEV};
    border-left: 1px solid {BORDER_SUBTLE};
}}
QLabel#railSection {{
    color: {TEXT_MUTED};
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    padding: 0 0 8px 0;
}}
QLabel#railTitle {{
    color: {TEXT};
    font-size: 14px;
    font-weight: 600;
    letter-spacing: -0.02em;
    padding-bottom: 6px;
}}
QLabel#railBody {{
    color: {TEXT_MUTED};
    font-size: 12px;
    line-height: 1.45;
}}
QLabel#railMeta {{
    color: {TEXT_FAINT};
    font-size: 11px;
    padding-top: 12px;
}}
QFrame#deviceFrame {{
    background: {BG};
    border: none;
}}
QFrame#profileRule {{
    background: {BORDER_SUBTLE};
    border: none;
    min-height: 1px;
    max-height: 1px;
}}
QLabel#deviceKicker {{
    color: {ACCENT_CYAN};
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.2em;
}}
QLabel#deviceName {{
    color: {TEXT};
    font-size: 16px;
    font-weight: 600;
}}
"""


HEADER_QSS = f"""
QWidget#profileHeader {{
    background: {BG};
    border: none;
}}
QLabel#profileTitle {{
    font-size: 15px;
    font-weight: 600;
    color: {TEXT};
    letter-spacing: -0.02em;
}}
QLabel#activePill {{
    color: {ACCENT_CYAN};
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.06em;
    padding: 4px 10px;
    border-radius: 6px;
    background: {ACCENT_CYAN_GLOW};
    border: none;
}}
QLabel#keysMeta {{
    color: {TEXT_FAINT};
    font-size: 11px;
}}
"""

MAPPING_PANEL_QSS = f"""
#mappingPopup {{
    background: {BG_ELEV};
    border: 1px solid {BORDER};
    border-radius: 12px;
}}
QLabel#mpTitle {{
    font-size: 14px;
    font-weight: 600;
    color: {TEXT};
}}
QLabel#mpSlot {{
    color: {TEXT_MUTED};
    font-size: 11px;
}}
QLabel#mpHint {{
    color: {TEXT_FAINT};
    font-size: 10px;
}}
QLabel#mpPrompt {{
    color: {TEXT_MUTED};
    font-size: 10px;
}}
QLabel#mpSection {{
    color: {TEXT};
    font-size: 12px;
    font-weight: 600;
}}
#dialCard QLabel {{
    color: {TEXT_MUTED};
    font-size: 11px;
}}
QFrame#mpKcWrap {{
    background: {SURFACE};
    border: 1px solid {BORDER_SUBTLE};
    border-radius: 8px;
}}
QLabel#mpKc {{
    background: transparent;
    border: none;
    color: {TEXT_MUTED};
    font-family: monospace;
    padding: 6px 8px;
}}
QFrame#dialCard {{
    background: {SURFACE};
    border: 1px solid {BORDER_SUBTLE};
    border-radius: 8px;
}}
QLineEdit {{
    background: {SURFACE};
    border: 1px solid {BORDER_SUBTLE};
    border-radius: 6px;
    padding: 7px 9px;
    color: {TEXT};
    selection-background-color: {ACCENT_DIM};
}}
QLineEdit:focus {{
    border: 1px solid {ACCENT};
}}
QPushButton#mpPrimary {{
    background: {ACCENT_DIM};
    border: 1px solid {BORDER};
    border-radius: 8px;
    padding: 8px 14px;
    color: {TEXT};
    font-weight: 500;
}}
QPushButton#mpPrimary:hover {{
    background: #93b5ec;
    color: #0c0d10;
    border-color: #a8c4f0;
}}
QPushButton#mpGhost {{
    background: transparent;
    border: 1px solid {BORDER};
    border-radius: 8px;
    padding: 6px 10px;
    color: {TEXT_MUTED};
}}
QPushButton#mpGhost:hover {{
    background: {HOVER_LIFT};
    color: {TEXT};
    border-color: {BORDER};
}}
QPushButton#mpDanger {{
    background: transparent;
    border: 1px solid rgba(196, 122, 122, 0.4);
    border-radius: 8px;
    padding: 8px 14px;
    color: {DANGER};
}}
QPushButton#mpDanger:hover {{
    background: rgba(196, 122, 122, 0.22);
    border-color: rgba(196, 122, 122, 0.55);
}}
QPushButton#mpClose {{
    background: transparent;
    border: 1px solid {BORDER_SUBTLE};
    border-radius: 10px;
    color: {TEXT_MUTED};
    font-size: 16px;
}}
QPushButton#mpClose:hover {{
    background: {HOVER_LIFT};
    color: {TEXT};
}}
/* Pen tab: flat text — no filled panels behind slot / section headings */
#mappingPopup[editorSurface="pen"] QLabel#mpSlot,
#mappingPopup[editorSurface="pen"] QLabel#mpSection,
#mappingPopup[editorSurface="pen"] QLabel#mpHint {{
    background: transparent;
    border: none;
    padding: 0px;
}}
"""

DIAL_POPUP_QSS = f"""
#dialModePopup {{
    background: {SURFACE};
    border: 1px solid {BORDER};
    border-radius: 12px;
}}
"""

PROFILE_DIALOG_QSS = f"""
QDialog {{
    background: {BG};
    color: {TEXT};
}}
QLabel {{
    color: {TEXT_MUTED};
}}
QLineEdit {{
    background: {BG_ELEV};
    border: 1px solid {BORDER};
    border-radius: 8px;
    padding: 8px 10px;
    color: {TEXT};
}}
QLineEdit:focus {{
    border: 1px solid {ACCENT};
}}
QListWidget {{
    background: {SURFACE};
    border: 1px solid {BORDER_SUBTLE};
    border-radius: 10px;
    padding: 4px;
}}
QListWidget::item {{
    padding: 8px;
    border-radius: 6px;
}}
QListWidget::item:hover:!selected {{
    background: {HOVER_LIFT};
    color: {TEXT};
}}
QListWidget::item:selected {{
    background: {SURFACE_HOVER};
    color: {TEXT};
}}
QPushButton {{
    background: {SURFACE};
    border: 1px solid {BORDER};
    border-radius: 8px;
    padding: 6px 12px;
    color: {TEXT_MUTED};
}}
QPushButton:hover {{
    background: {HOVER_LIFT};
    color: {TEXT};
}}
QDialogButtonBox QPushButton {{
    min-width: 72px;
    padding: 8px 16px;
}}
"""


def qc(hex_color: str) -> QColor:
    """QColor from #RRGGBB or #AARRGGBB."""
    return QColor(hex_color)


def qc_alpha(hex_rgb: str, alpha: int) -> QColor:
    c = QColor(hex_rgb)
    c.setAlpha(alpha)
    return c
