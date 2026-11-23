#!/usr/bin/env python3
# Settings → Apps and Hyprland → Idle and lock, in ~/.config/hypr/hypridle.conf.
#   hypridle.py read                     {"timings": {dim, lock, dpms, suspend}, "running"}
#   hypridle.py write '<json timings>'   minutes, 0 = never
# Writing keeps the file's general { } block as it is, rewrites the four listeners,
# backs the file up once a day (hypridle.conf.before-tide-YYYYMMDD) and restarts
# hypridle (its systemd user unit, which brings it back if it fails).
# Dim is Tide's own overlay (`qs ipc call idle dim`): these monitors have no backlight
# brightnessctl can reach.
import json, os, re, shutil, subprocess, sys, time

PATH = os.path.expanduser("~/.config/hypr/hypridle.conf")
NEVER = 99999  # seconds; anything this long counts as "never"


SHELL = os.path.expanduser("~/.config/Tide/modes/dev/shell")
# every step asks Tide first (scripts/idle-step.sh), which applies the keep-awake rules
STEP = SHELL + "/scripts/idle-step.sh "
# hypridle can only honor every app's keep-awake or none; Tide decides per app instead.
# (D-Bus ScreenSaver requests can't be traced to an app, so those stay honored here.)
IGNORE = ["ignore_systemd_inhibit = true", "ignore_wayland_inhibit = true"]


def running():
    return subprocess.run(["pgrep", "-x", "hypridle"], capture_output=True).returncode == 0


def parse(text):
    general = ""
    m = re.search(r"general\s*\{.*?\n\}", text, re.S)
    if m:
        general = m.group(0)
    t = {"dim": 0, "lock": 0, "dpms": 0, "suspend": 0}
    for block in re.findall(r"listener\s*\{(.*?)\n\}", text, re.S):
        tm = re.search(r"^\s*timeout\s*=\s*(\d+)", block, re.M)
        act = re.search(r"^\s*on-timeout\s*=\s*([^#\n]*)", block, re.M)
        if not tm or not act:
            continue
        secs, cmd = int(tm.group(1)), act.group(1)
        mins = 0 if secs >= NEVER else max(1, round(secs / 60))
        if "brightnessctl" in cmd or "call idle dim" in cmd or "idle-step.sh dim" in cmd:
            t["dim"] = mins
        elif "lock" in cmd:
            t["lock"] = mins
        elif "dpms off" in cmd or "idle-step.sh dpms" in cmd:
            t["dpms"] = mins
        elif "suspend" in cmd:
            t["suspend"] = mins
    return general, t


def read():
    try:
        text = open(PATH).read()
    except OSError:
        text = ""
    _, t = parse(text)
    print(json.dumps({"timings": t, "running": running()}))


def write(t):
    try:
        text = open(PATH).read()
    except OSError:
        text = ""
    general, _ = parse(text)
    if not general:
        general = ("general {\n    lock_cmd = pidof hyprlock || hyprlock\n"
                   "    before_sleep_cmd = loginctl lock-session\n"
                   "    after_sleep_cmd = hyprctl dispatch dpms on\n}")
    # Tide's keep-awake rules: hypridle leaves systemd and Wayland keep-awake to Tide
    general = re.sub(r"\n\s*ignore_(systemd|wayland)_inhibit\s*=.*", "", general)
    general = general.rstrip()[:-1].rstrip() + "\n" + "".join("    %s    # Tide decides (Settings → Idle)\n" % l for l in IGNORE) + "}"
    parts = ["# Written by Tide (Settings → Apps and Hyprland → Idle and lock).", general]

    def listener(mins, lines, note):
        if mins:
            parts.append("listener {\n    timeout = %d%s\n%s\n}" % (mins * 60, " " * 4 + "# " + note, "\n".join("    " + l for l in lines)))

    listener(int(t.get("dim", 0)), ["on-timeout = " + STEP + "dim", "on-resume = " + STEP + "resume"], "dim")
    listener(int(t.get("lock", 0)), ["on-timeout = " + STEP + "lock"], "lock")
    listener(int(t.get("dpms", 0)), ["on-timeout = " + STEP + "dpms", "on-resume = hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'"], "screens off")
    listener(int(t.get("suspend", 0)), ["on-timeout = " + STEP + "suspend"], "suspend")

    if os.path.exists(PATH):
        backup = f"{PATH}.before-tide-{time.strftime('%Y%m%d')}"
        if not os.path.exists(backup):
            shutil.copy2(PATH, backup)
    was = running()
    tmp = PATH + ".tmp"
    with open(tmp, "w") as f:
        f.write("\n\n".join(parts) + "\n")
    os.replace(tmp, PATH)
    if was:
        # a copy started outside the unit (older Tide) goes; the unit takes over
        if subprocess.run(["systemctl", "--user", "is-active", "--quiet", "hypridle.service"]).returncode != 0:
            subprocess.run(["pkill", "-x", "hypridle"])
            time.sleep(0.5)
        subprocess.run(["systemctl", "--user", "restart", "hypridle.service"])
    print("saved")


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "write":
        write(json.loads(sys.argv[2]))
    else:
        read()
