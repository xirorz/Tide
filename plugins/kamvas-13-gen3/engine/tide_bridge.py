#!/usr/bin/env python3
"""Tide's Settings page ↔ this plugin's profiles, through the engine's own model
(so saving works exactly like the tablet app does).

  tide_bridge.py dump
      one JSON object: the tablet layout (definitions.py), the profiles with what
      every control does, and which one is the default ("Desktop")
  tide_bridge.py set-key <profile> <slot> <keys> [<double keys>]
      map an express key (slots 3–7) or pen button (11–13); empty keys clears it.
      The "desktop" profile is created on first use and becomes the default.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from assets.tablets.definitions import TABLETS  # noqa: E402
from models import ButtonAction, Profile  # noqa: E402
from profiles import CONFIG_FILE, load_config, save_config  # noqa: E402

TABLET = TABLETS[("256c", "2008")]


def layout():
    controls = []
    for c in TABLET["controls"]:
        item = {k: c[k] for k in ("type", "label", "cx", "cy")}
        if c["type"] == "dial":
            item["r"] = c["r_frac"]
            item["id"] = str(c["slots"][0]["id"])
        else:
            item["id"] = c["id"]
        controls.append(item)
    return {"name": TABLET["name"], "strip": TABLET["button_strip"], "controls": controls,
            "pen": TABLET["pen_buttons"]}


def default_keycode(slot):
    return f"PENBTN:{slot - 10}" if slot >= 11 else f"VENDORBTN:{slot}"


def describe(profile):
    keys = {}
    for c in TABLET["controls"]:
        if c["type"] == "button":
            keys[str(c["id"])] = None
    for p in TABLET["pen_buttons"]:
        keys[str(p["id"])] = None
    if profile:
        for slot in list(keys):
            kc, action = profile.get_slot(int(slot))
            if action:
                keys[slot] = {"keys": action.keys, "double": action.keys_double, "passthrough": action.passthrough}
    dials = {}
    if profile:
        for dial_id, d in profile.dials.items():
            dials[dial_id] = [{"label": m.get("label", ""), "ccw": m.get("ccw", ""), "cw": m.get("cw", "")} for m in d.modes]
    return {"keys": keys, "dials": dials}


def dump():
    cfg = load_config()
    profiles = []
    for cls, p in cfg.profiles.items():
        if cls == "desktop":
            continue
        profiles.append({"id": cls, "name": p.app_name[:1].upper() + p.app_name[1:], **describe(p)})
    desktop = cfg.profiles.get(cfg.default_profile or "desktop")
    profiles.append({"id": "desktop", "name": "Desktop", "isDefault": True, **describe(desktop)})
    print(json.dumps({"layout": layout(), "profiles": profiles, "enabled": cfg.enabled, "file": str(CONFIG_FILE)}))


def set_key(profile_id, slot, keys, double=""):
    cfg = load_config()
    if profile_id == "desktop":
        pid = cfg.default_profile or "desktop"
        if pid not in cfg.profiles:
            cfg.profiles[pid] = Profile(app_class="desktop", app_name="Desktop")
        cfg.default_profile = pid
        profile_id = pid
    profile = cfg.profiles[profile_id]
    slot = int(slot)
    if not keys.strip():
        profile.clear_slot(slot)
    else:
        kc = profile.slots.get(slot) or default_keycode(slot)
        action = ButtonAction(keys=keys.strip(), label=keys.strip(), keys_double=double.strip(), label_double=double.strip())
        profile.set_slot(slot, kc, action)
    save_config(cfg)
    print("saved")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "dump"
    if cmd == "dump":
        dump()
    elif cmd == "set-key":
        set_key(*sys.argv[2:6])
    else:
        sys.exit(__doc__)
