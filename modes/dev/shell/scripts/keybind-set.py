#!/usr/bin/env python3
# Changes one shortcut in Tide's Hyprland config (Settings → Keybinds).
#   keybind-set.py <line> "<old keys>" "<new keys>"     e.g. 72 "SUPER + T" "SUPER + SHIFT + T"
# Refuses if another bind already uses the new keys. Keeps a daily backup
# (hyprland.lua.before-tide-YYYYMMDD), checks the config with Hyprland --verify-config
# and puts the old file back if it fails, then reloads Hyprland.
# Prints one JSON line: {"ok": true} or {"ok": false, "error": "..."}.
import json, os, re, shutil, subprocess, sys, time

PATH = os.path.expanduser("~/.config/Tide/hypr/hyprland.lua")
LOADER = os.path.expanduser("~/.config/hypr/hyprland.lua")


def norm(k):
    return " + ".join(p.strip().upper() if len(p.strip()) == 1 else p.strip() for p in k.split("+"))


def done(ok, error=""):
    print(json.dumps({"ok": ok, "error": error}))
    sys.exit(0)


line_no, old, new = int(sys.argv[1]), sys.argv[2], sys.argv[3]
lines = open(PATH).read().split("\n")
if not (0 < line_no <= len(lines)) or f'hl.bind("{old}"' not in lines[line_no - 1]:
    done(False, "The config changed since Settings read it. Reopen Keybinds and try again.")
for i, l in enumerate(lines, 1):
    m = re.match(r'\s*hl\.bind\("([^"]+)"', l)
    if m and i != line_no and norm(m.group(1)).lower() == norm(new).lower():
        done(False, f"{new} is already used (line {i}).")

backup = f"{PATH}.before-tide-{time.strftime('%Y%m%d')}"
if not os.path.exists(backup):
    shutil.copy2(PATH, backup)
before = "\n".join(lines)
lines[line_no - 1] = lines[line_no - 1].replace(f'hl.bind("{old}"', f'hl.bind("{new}"', 1)
with open(PATH, "w") as f:
    f.write("\n".join(lines))
r = subprocess.run(["Hyprland", "--verify-config", "-c", LOADER], capture_output=True, text=True)
if "config ok" not in r.stdout + r.stderr:
    with open(PATH, "w") as f:
        f.write(before)
    done(False, "Hyprland didn't accept that key, so nothing changed.")
subprocess.run(["hyprctl", "reload"], capture_output=True)
done(True)
