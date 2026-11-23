#!/usr/bin/env python3
# Reads the hl.bind(...) lines of a Hyprland Lua config and prints them as JSON for
# Settings → Keybinds: [{group, action, keys}], in the file's order. Names come from
# the action (Tide's own shortcuts, window and workspace dispatchers, known
# commands) or from a trailing "-- comment".
#   keybinds.py [config]   (default ~/.config/Tide/hypr/hyprland.lua)
import json, os, re, sys

path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.config/Tide/hypr/hyprland.lua")

TIDE = {
    "launcher": "Open the launcher", "calculator": "Calculator", "controlcenter": "Control center",
    "clipboard": "Clipboard history", "capture": "Capture tools", "power": "Power menu",
    "resources": "Resource center", "wallpapers": "Wallpapers", "themes": "Switch theme",
    "eve": "Talk to Eve", "updates": "Updates",
}
KEYS = {"SUPER": "Mod", "RETURN": "Enter", "ESCAPE": "Esc", "SPACE": "Space", "mouse_down": "Wheel down",
        "mouse_up": "Wheel up", "mouse:272": "Left drag", "mouse:273": "Right drag", "left": "←", "right": "→",
        "up": "↑", "down": "↓", "CTRL": "Ctrl", "SHIFT": "Shift", "ALT": "Alt"}
MEDIA = {"XF86AudioRaiseVolume": "Volume up", "XF86AudioLowerVolume": "Volume down", "XF86AudioMute": "Mute",
         "XF86AudioMicMute": "Mute microphone", "XF86MonBrightnessUp": "Brightness up",
         "XF86MonBrightnessDown": "Brightness down", "XF86AudioNext": "Next track", "XF86AudioPrev": "Previous track",
         "XF86AudioPlay": "Play or pause", "XF86AudioPause": "Play or pause"}


def keys(k):
    parts = [p.strip() for p in k.split("+")]
    if len(parts) == 1 and parts[0] in MEDIA:
        return "Media key"
    return " + ".join(KEYS.get(p, p.upper() if len(p) == 1 else p) for p in parts)


def name(k, act, comment):
    m = re.match(r'hl\.dsp\.global\("tide:(\w+)"\)', act)
    if m:
        g = "Screens and modes" if m.group(1) in ("themes", "wallpapers") else "Island and tools"
        return g, TIDE.get(m.group(1), m.group(1).capitalize())
    if k.strip() in MEDIA:
        return "Media and hardware", MEDIA[k.strip()]
    if m := re.search(r'workspace = "(special:)?(\w[\w+-]*)", follow', act):
        return "Windows and workspaces", ("Move window to the scratchpad" if m.group(1) else f"Move window to workspace {m.group(2)}")
    if m := re.search(r'focus\(\{ workspace = "([^"]+)"', act):
        w = m.group(1)
        return "Windows and workspaces", {"e+1": "Next workspace", "e-1": "Previous workspace"}.get(w, f"Workspace {w}")
    if m := re.search(r'focus\(\{ direction = "(\w+)"', act):
        return "Windows and workspaces", f"Focus window {m.group(1)}"
    simple = {"window.close()": "Close window", "window.pseudo()": "Pseudo-tile", 'layout("togglesplit")': "Toggle split",
              "window.drag(": "Move window", "window.resize(": "Resize window",
              'workspace.toggle_special("magic")': "Show scratchpad"}
    for s, n in simple.items():
        if s in act:
            return "Windows and workspaces", n
    if "window.float" in act:
        return "Windows and workspaces", "Float or tile window"
    if "fullscreen_state" in act:
        return "Windows and workspaces", "Fake fullscreen (window keeps its size)"
    if "fullscreen" in act:
        return "Windows and workspaces", "Fullscreen" if '"fullscreen"' in act else "Maximize"
    if m := re.search(r"tide-open (\w+)", act):
        return "Apps and scripts", {"terminal": "Terminal", "files": "Files", "audio": "Audio settings"}.get(m.group(1), m.group(1))
    if comment:
        c = comment.strip()
        return "Apps and scripts", c[0].upper() + c[1:]
    m = re.search(r'exec_cmd\("([^"]+)"\)', act)
    cmd = m.group(1) if m else act
    if "restart.sh" in cmd:
        return "Island and tools", "Restart the shell"
    if "switch-monitor-input" in cmd:
        arg = cmd.split()[-1]
        return "Screens and modes", "Switch monitor input" + ("" if arg.endswith(".sh") else f" ({arg})")
    if "screen-reader" in cmd:
        return "Apps and scripts", "Eve screen reader"
    if "padkeys" in cmd:
        return "Apps and scripts", "Pad keys settings"
    prog = os.path.basename(cmd.split()[0]) if cmd.split() else cmd
    friendly = {"alacritty": "Terminal", "kitty": "Terminal", "nemo": "Files", "foot": "Terminal"}
    return "Apps and scripts", friendly.get(prog, prog) + ("" if prog not in friendly else f" ({prog})")


out = []
for n, line in enumerate(open(path, errors="replace"), 1):
    m = re.match(r'\s*hl\.bind\("([^"]+)",\s*(.*?)\)\s*(?:,\s*\{[^}]*\}\s*\))?\s*(?:--\s*(.*))?$', line)
    if not m:
        continue
    k, act, comment = m.group(1), m.group(2), m.group(3)
    group, action = name(k, act, comment)
    out.append({"group": group, "action": action, "keys": keys(k), "raw": k, "line": n,
                "editable": k.strip() not in MEDIA})
print(json.dumps(out))
