#!/usr/bin/env python3
# Who is keeping the screen awake right now, for Tide's idle rules (Idle.qml):
#   [{"kind", "name", "cls", "rule"}]
# kind: "inhibitor" (a systemd "block idle" lock, e.g. Claude's "Keep computer awake"),
#       "window" (a window holding Hyprland's idle-inhibit), "game" or "video".
# rule: "game" / "video" for the built-in "always keeps awake" ones, else "".
# Games: a visible window from Steam/Proton, Lutris, Heroic or gamescope (or a child
# of those launchers), or with Hyprland's content type "game". Fullscreen video: a
# fullscreen window with content type "video", or fullscreen and holding idle-inhibit.
# Tide's own Stay awake isn't listed.
import json, os, re, subprocess

LAUNCHERS = re.compile(r"steam|lutris|heroic|gamescope|proton|wine", re.I)
GAME_CLASS = re.compile(r"^(steam_app_\d+|gamescope|steam_proton)$|^lutris|^heroic", re.I)


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def parent_is_launcher(pid):
    for _ in range(8):
        try:
            st = open(f"/proc/{pid}/stat").read()
        except OSError:
            return False
        pid = int(st[st.rfind(")") + 2:].split()[1])
        if pid <= 1:
            return False
        try:
            if LAUNCHERS.search(open(f"/proc/{pid}/comm").read()):
                return True
        except OSError:
            return False
    return False


out = []
for line in run(["systemd-inhibit", "--list", "--no-legend", "--no-pager"]).splitlines():
    f = line.split()
    # WHO UID USER PID COMM WHAT WHY... MODE
    if len(f) >= 7 and "idle" in f[5].split(":") and f[-1] == "block" and f[0] != "Tide":
        out.append({"kind": "inhibitor", "name": f[0], "cls": f[4], "rule": ""})

try:
    clients = json.loads(run(["hyprctl", "clients", "-j"]) or "[]")
    shown = {m["activeWorkspace"]["id"] for m in json.loads(run(["hyprctl", "monitors", "-j"]) or "[]")}
except (ValueError, KeyError):
    clients, shown = [], set()
for c in clients:
    cls = c.get("class", "")
    visible = c.get("workspace", {}).get("id") in shown and not c.get("hidden")
    full = bool(c.get("fullscreen"))
    game = visible and (GAME_CLASS.search(cls) or c.get("contentType") == "game" or parent_is_launcher(c.get("pid", 0)))
    video = full and (c.get("contentType") == "video" or c.get("inhibitingIdle"))
    if game:
        out.append({"kind": "game", "name": c.get("title") or cls, "cls": cls, "rule": "game"})
    elif video:
        out.append({"kind": "video", "name": cls, "cls": cls, "rule": "video"})
    elif c.get("inhibitingIdle"):
        out.append({"kind": "window", "name": cls, "cls": cls, "rule": ""})
print(json.dumps(out))
