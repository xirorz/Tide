#!/usr/bin/env python3
# What Settings → Tablet and the tablet plugins need to know, as one JSON line:
#   tablets   drawing tablets Hyprland sees (any brand)
#   screen    the monitor that is a tablet's own screen, if any (name matches a
#             tablet brand in its description)
#   plugins   every ~/.config/Tide/plugins/*/plugin.json, with `connected` (one of its
#             USB ids is plugged in) and `appRunning` (its own app window is open)
import json, os, re, subprocess

PLUGINS = os.path.expanduser("~/.config/Tide/plugins")


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return ""


try:
    devices = json.loads(run(["hyprctl", "devices", "-j"]) or "{}")
except json.JSONDecodeError:
    devices = {}
tablets = [t.get("name", "") for t in devices.get("tablets", [])]

usb = set()
for d in os.listdir("/sys/bus/usb/devices"):
    try:
        with open(f"/sys/bus/usb/devices/{d}/idVendor") as v, open(f"/sys/bus/usb/devices/{d}/idProduct") as p:
            usb.add(f"{v.read().strip()}:{p.read().strip()}".lower())
    except OSError:
        pass

try:
    monitors = json.loads(run(["hyprctl", "monitors", "-j"]) or "[]")
except json.JSONDecodeError:
    monitors = []
screen = ""
for m in monitors:
    if re.search(r"kamvas|huion|wacom|cintiq|xp-?pen|artist|gaomon|tablet", (m.get("description", "") + " " + m.get("model", "")), re.I):
        screen = m["name"]
        break

procs = run(["ps", "-eo", "args"])
plugins = []
if os.path.isdir(PLUGINS):
    for name in sorted(os.listdir(PLUGINS)):
        path = os.path.join(PLUGINS, name)
        try:
            with open(os.path.join(path, "plugin.json")) as f:
                man = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        ids = [i.lower() for i in man.get("match", {}).get("usb", [])]
        app = man.get("appMatch", "")
        man.update({
            "id": name, "dir": path,
            "connected": any(i in usb for i in ids),
            "appRunning": bool(app) and any(re.search(app, l.strip()) and "--daemon" not in l for l in procs.splitlines()),
        })
        plugins.append(man)

print(json.dumps({"tablets": tablets, "screen": screen, "plugins": plugins}))
