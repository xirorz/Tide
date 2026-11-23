"""Dial mode helpers shared by UI and runtime remapping."""

from __future__ import annotations


LEGACY_MODE_DEFS = {
    "dial_scroll": {
        "label": "Scroll",
        "ccw": "scroll_up",
        "cw": "scroll_down",
    },
    "dial_zoom": {
        "label": "Zoom",
        "ccw": "zoom_out",
        "cw": "zoom_in",
    },
    "dial_brush": {
        "label": "Brush Size",
        "ccw": "leftbrace",
        "cw": "rightbrace",
    },
    "blender_orbit": {
        "label": "Orbit",
        "ccw": "kp4",
        "cw": "kp6",
    },
    "blender_pan": {
        "label": "Pan",
        "ccw": "ctrl+kp4",
        "cw": "ctrl+kp6",
    },
    "blender_roll": {
        "label": "Roll",
        "ccw": "shift+kp4",
        "cw": "shift+kp6",
    },
    "blender_brush_strength": {
        "label": "Brush Strength",
        "ccw": "blender_brush_strength_ccw",
        "cw": "blender_brush_strength_cw",
    },
}


def make_mode(label: str, ccw: str, cw: str) -> dict[str, str]:
    return {
        "label": label.strip(),
        "ccw": ccw.strip(),
        "cw": cw.strip(),
    }


def clone_mode(mode) -> dict[str, str] | None:
    if isinstance(mode, str):
        preset = LEGACY_MODE_DEFS.get(mode)
        if preset is None:
            return None
        return dict(preset)
    if isinstance(mode, dict):
        label = str(mode.get("label", "")).strip()
        ccw = str(mode.get("ccw", "")).strip()
        cw = str(mode.get("cw", "")).strip()
        if not label and not ccw and not cw:
            return None
        return make_mode(label, ccw, cw)
    return None


def sanitize_modes(modes: list) -> list[dict[str, str]]:
    cleaned: list[dict[str, str]] = []
    for mode in modes:
        normalized = clone_mode(mode)
        if normalized is None:
            continue
        if not normalized["ccw"] and not normalized["cw"]:
            continue
        if not normalized["label"]:
            normalized["label"] = f"Mode {len(cleaned) + 1}"
        cleaned.append(normalized)
    return cleaned


def mode_label(mode) -> str:
    normalized = clone_mode(mode)
    if normalized is None:
        return str(mode)
    return normalized["label"]


def mode_pair(mode) -> tuple[str, str] | None:
    normalized = clone_mode(mode)
    if normalized is None:
        return None
    if not normalized["ccw"] or not normalized["cw"]:
        return None
    return normalized["ccw"], normalized["cw"]


def default_modes_for_app(app_class: str) -> list[dict[str, str]]:
    app = app_class.lower()
    if "blender" in app:
        return [
            make_mode("Orbit", "kp4", "kp6"),
            make_mode("Zoom", "kpminus", "kpplus"),
            make_mode("Brush Size", "leftbrace", "rightbrace"),
            make_mode(
                "Brush Strength",
                "blender_brush_strength_ccw",
                "blender_brush_strength_cw",
            ),
        ]
    if "gimp" in app:
        return [
            make_mode("Brush Size", "leftbrace", "rightbrace"),
            make_mode("Zoom", "zoom_out", "zoom_in"),
            make_mode("Scroll", "scroll_up", "scroll_down"),
        ]
    if "inkscape" in app:
        return [
            make_mode("Zoom", "zoom_out", "zoom_in"),
            make_mode("Scroll", "scroll_up", "scroll_down"),
            make_mode("Nudge", "left", "right"),
        ]
    return [
        make_mode("Scroll", "scroll_up", "scroll_down"),
        make_mode("Zoom", "zoom_out", "zoom_in"),
        make_mode("Brush Size", "leftbrace", "rightbrace"),
    ]
