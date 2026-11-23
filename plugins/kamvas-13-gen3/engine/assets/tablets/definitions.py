"""Tablet definitions.

Kamvas 13 Gen 3 controls:
  - 2 dial controllers
  - 5 press keys
  - each dial exposes counter-clockwise, clockwise, and center-press actions

SVG viewBox is 860 × 500. cx/cy are fractions of that.
"""
import sys
from pathlib import Path

def resource_path(relative_path: str):
    """Get absolute path to resource, works for dev and for PyInstaller"""
    try:
        # PyInstaller creates a temp folder and stores path in _MEIPASS
        base_path = Path(sys._MEIPASS)
    except AttributeError:
        base_path = Path(__file__).parent.parent.parent
    return base_path / relative_path

ASSETS_DIR = resource_path("assets/tablets")


def _dial(slot: int, label: str, cx: float, cy: float, r_frac: float = 0.054):
    return {
        "type":   "dial",
        "label":  label,
        "cx": cx, "cy": cy,
        "r_frac": r_frac,   # outer radius as fraction of tablet width
        "slots": [
            {"id": slot,     "part": "ccw",    "label": "Rotate CCW"},
            {"id": slot + 1, "part": "cw",     "label": "Rotate CW"},
            {"id": slot + 2, "part": "center", "label": "Press"},
        ],
    }


def _btn(slot: int, label: str, cx: float, cy: float):
    return {"type": "button", "label": label, "cx": cx, "cy": cy, "id": slot}


TABLETS = {
    ("256c", "2008"): {
        "name":  "Huion Kamvas 13 Gen 3",
        "image": ASSETS_DIR / "kamvas_13_gen3.svg",
        # SVG viewBox 860 × 500
        # Layout based on the Kamvas 13 Gen 3 hardware:
        # 2 dial controllers, 5 press keys, 3 pen side buttons.
        # Side keys share one vertical pill in kamvas_13_gen3.svg (rect x=38 y=152 w=56 h=196 rx=28).
        "button_strip": {"x": 38 / 860, "y": 152 / 500, "w": 56 / 860, "h": 196 / 500},
        "controls": [
            _dial(0, "Upper Dial",  cx=56/860, cy=100/500, r_frac=38/860),
            _btn( 3, "Button 1",    cx=66/860, cy=174/500),
            _btn( 4, "Button 2",    cx=66/860, cy=212/500),
            _btn( 5, "Button 3",    cx=66/860, cy=250/500),
            _btn( 6, "Button 4",    cx=66/860, cy=288/500),
            _btn( 7, "Button 5",    cx=66/860, cy=326/500),
            _dial(8, "Lower Dial",  cx=56/860, cy=400/500, r_frac=38/860),
        ],
        "total_slots": 11,
        "pen_svg": ASSETS_DIR / "pen.svg",
        "pen_buttons": [
            {"id": 11, "label": "Barrel button"},
            {"id": 12, "label": "Rocker ↑"},
            {"id": 13, "label": "Rocker ↓"},
        ],
    },
}

GENERIC_TABLET = {
    "name":  "Generic Tablet",
    "image": None,
    "pen_svg": ASSETS_DIR / "pen.svg",
    "controls": [_btn(i, f"Button {i+1}", cx=0.09, cy=0.07 + i*0.125) for i in range(8)],
    "total_slots": 8,
    "pen_buttons": [
        {"id": 8,  "label": "Side Button 1"},
        {"id": 9,  "label": "Side Button 2"},
        {"id": 10, "label": "Side Button 3"},
    ],
}


def get_definition(vendor_id: str, product_id: str) -> dict:
    return TABLETS.get((vendor_id.lower(), product_id.lower()), GENERIC_TABLET)
