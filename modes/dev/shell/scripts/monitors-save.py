#!/usr/bin/env python3
# Saves Settings → Monitors to ~/.config/hypr/monitors.conf, which Tide's Hyprland
# config reads. The first save of a day keeps a copy as
# monitors.conf.before-tide-YYYYMMDD.
#   monitors-save.py '<json: [{name, mode, x, y, scale, transform, vrr, bitdepth, cm,
#                               sdrbrightness, sdrsaturation}]>'
# Extras are written only when they differ from Hyprland's defaults.
import json, os, shutil, sys, time

path = os.path.expanduser("~/.config/hypr/monitors.conf")
mons = json.loads(sys.argv[1])
if os.path.exists(path):
    backup = f"{path}.before-tide-{time.strftime('%Y%m%d')}"
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
lines = []
for m in mons:
    line = f"monitor={m['name']},{m['mode']},{int(m['x'])}x{int(m['y'])},{float(m['scale']):.2f}"
    if int(m.get("transform", 0)):
        line += f",transform,{int(m['transform'])}"
    if int(m.get("vrr", 0)):
        line += f",vrr,{int(m['vrr'])}"
    if int(m.get("bitdepth", 8)) == 10:
        line += ",bitdepth,10"
    if m.get("cm", "srgb") not in ("srgb", ""):
        line += f",cm,{m['cm']}"
    if abs(float(m.get("sdrbrightness", 1)) - 1) > 0.001:
        line += f",sdrbrightness,{float(m['sdrbrightness']):.2f}"
    if abs(float(m.get("sdrsaturation", 1)) - 1) > 0.001:
        line += f",sdrsaturation,{float(m['sdrsaturation']):.2f}"
    lines.append(line)
tmp = path + ".tmp"
with open(tmp, "w") as f:
    f.write("\n".join(lines) + "\n")
os.replace(tmp, path)
print(path)
