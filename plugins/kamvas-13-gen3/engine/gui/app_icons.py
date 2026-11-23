"""Resolve application icons from WM_CLASS using Freedesktop .desktop entries and icon themes."""
from __future__ import annotations

import os
from pathlib import Path
from functools import lru_cache

from PyQt6.QtGui import QIcon

_DESKTOP_DIRS: tuple[Path, ...] = (
    Path.home() / ".local/share/applications",
    Path("/usr/local/share/applications"),
    Path("/usr/share/applications"),
    Path("/var/lib/flatpak/exports/share/applications"),
    Path.home() / ".local/share/flatpak/exports/share/applications",
)

_index: dict[str, str] | None = None


def _parse_desktop_entry(path: Path) -> dict[str, str] | None:
    """Read [Desktop Entry]: Icon, StartupWMClass, NoDisplay."""
    section: str | None = None
    out: dict[str, str] = {}
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if section != "desktop entry":
            continue
        if "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        if "[" in key:
            continue
        val = val.strip()
        if key and val:
            out[key] = val
    return out or None


def _iter_desktop_files() -> list[Path]:
    found: list[Path] = []
    for base in _DESKTOP_DIRS:
        if not base.is_dir():
            continue
        try:
            found.extend(p for p in base.glob("*.desktop") if p.is_file())
        except OSError:
            continue
    return found


def _build_wmclass_index() -> dict[str, str]:
    """Map lowercased StartupWMClass -> Icon value (first wins; dirs are ordered user-first)."""
    idx: dict[str, str] = {}
    for path in _iter_desktop_files():
        data = _parse_desktop_entry(path)
        if not data:
            continue
        if data.get("NoDisplay", "").lower() == "true":
            continue
        if data.get("Type", "Application").lower() == "link":
            continue
        wm = (data.get("StartupWMClass") or "").strip()
        icon = (data.get("Icon") or "").strip()
        if not wm or not icon:
            continue
        key = wm.lower()
        if key not in idx:
            idx[key] = icon
    return idx


def _ensure_index() -> dict[str, str]:
    global _index
    if _index is None:
        _index = _build_wmclass_index()
    return _index


def invalidate_desktop_index() -> None:
    """Call after installing apps if icons never update in the same session."""
    global _index
    _index = None
    icon_from_stored.cache_clear()


def icon_name_for_wm_class(wm_class: str) -> str:
    """Return the Icon= string from a matching .desktop, or ''."""
    wc = wm_class.strip()
    if not wc:
        return ""
    return _ensure_index().get(wc.lower(), "")


def icon_name_for_pid(pid: int) -> str:
    """Fallback: match /proc/PID/exe basename against Exec= lines in .desktop files."""
    if pid <= 0:
        return ""
    try:
        exe = os.readlink(f"/proc/{pid}/exe")
    except OSError:
        return ""
    base = Path(exe).name.lower()
    if not base or base.startswith("deleted"):
        return ""
    for path in _iter_desktop_files():
        data = _parse_desktop_entry(path)
        if not data:
            continue
        if data.get("NoDisplay", "").lower() == "true":
            continue
        exec_line = (data.get("Exec") or "").lower()
        if base not in exec_line:
            continue
        icon = (data.get("Icon") or "").strip()
        if icon:
            return icon
    return ""


@lru_cache(maxsize=128)
def icon_from_stored(icon_str: str, wm_class: str) -> QIcon:
    """Build a QIcon from a stored profile icon string plus WM_CLASS fallback."""
    wm = wm_class.strip()
    for candidate in (icon_str.strip(), icon_name_for_wm_class(wm)):
        if not candidate:
            continue
        p = Path(candidate)
        if p.is_file():
            ic = QIcon(str(p))
            if not ic.isNull():
                return ic
        ic = QIcon.fromTheme(candidate)
        if not ic.isNull():
            return ic
        base = candidate.split("/")[-1]
        if base != candidate:
            ic = QIcon.fromTheme(base)
            if not ic.isNull():
                return ic
    if wm:
        ic = QIcon.fromTheme(wm.lower())
        if not ic.isNull():
            return ic
    return QIcon.fromTheme("application-x-executable")


def resolve_icon_for_profile(wm_class: str, pid: int = 0) -> str:
    """Pick an icon string to store when creating/updating a profile (theme name or path)."""
    name = icon_name_for_wm_class(wm_class)
    if name:
        return name
    return icon_name_for_pid(pid)
