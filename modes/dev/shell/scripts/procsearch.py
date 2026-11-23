#!/usr/bin/env python3
# The resource center's search: every running process whose name, command line or
# user matches (case-insensitive), grouped by name, and the systemd user services
# that match.
#   procsearch.py QUERY  ->  {"procs": [...], "services": [...]}
# procs: {name, note, pids, count, cpu, ram, user, cmd, own}; own = all yours and none
# of them protected (Tide's shell, the session, PID 1, root and system processes never
# get End). services: {unit, desc, active, sub, own}.
import json, os, pwd, re, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from resources import PROTECTED  # the same list the process table uses

HZ = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
UID = os.getuid()
ME = os.getpid()
# services that keep the session, sound and portals running
PROTECTED_UNITS = ("pipewire", "wireplumber", "dbus", "xdg-desktop-portal", "xdg-document-portal", "xdg-permission-store",
                   "at-spi", "gnome-keyring", "hypr", "uwsm", "wayland-wm", "graphical-session", "app-org.quickshell",
                   "systemd-", "gvfs", "dconf", "kwalletd", "plasma", "waybar", "mako", "swaync")


def read(p, default=""):
    try:
        with open(p) as f:
            return f.read()
    except OSError:
        return default


def users():
    cache = {}
    def name(uid):
        if uid not in cache:
            try:
                cache[uid] = pwd.getpwuid(uid).pw_name
            except KeyError:
                cache[uid] = str(uid)
        return cache[uid]
    return name


def ticks():
    out = {}
    for p in os.listdir("/proc"):
        if p.isdigit():
            st = read(f"/proc/{p}/stat")
            if st:
                f = st[st.rfind(")") + 2:].split()
                out[int(p)] = int(f[11]) + int(f[12])
    return out


# the session's own family, by name: never End (whoever owns them)
CRITICAL = re.compile(r"hypr|uwsm|sddm|systemd|dbus|pipewire|wireplumber|portal|polkit|keyring|xwayland|login|seatd|greetd", re.I)


def session_parents():
    """Hyprland and everything above it (start-hyprland, uwsm…): ending one ends the session."""
    out = set()
    for p in os.listdir("/proc"):
        if p.isdigit() and read(f"/proc/{p}/comm").strip() == "Hyprland":
            pid = int(p)
            while pid > 1 and pid not in out:
                out.add(pid)
                st = read(f"/proc/{pid}/stat")
                pid = int(st[st.rfind(")") + 2:].split()[1]) if st else 1
    return out


def tide_shell(cmd):
    return cmd.startswith(("qs -p", "/usr/bin/qs -p", "quickshell")) or "/.config/Tide/" in cmd and "/scripts/" in cmd


def main(q):
    q = q.strip().lower()
    name_of = users()
    t0, a = time.time(), ticks()
    time.sleep(0.25)
    dt, b = time.time() - t0, ticks()
    groups = {}
    guard = session_parents()
    for pid, tk in b.items():
        st = read(f"/proc/{pid}/stat")
        if not st:
            continue
        comm = st[st.find("(") + 1:st.rfind(")")]
        f = st[st.rfind(")") + 2:].split()
        cmd = read(f"/proc/{pid}/cmdline").replace("\0", " ").strip()
        try:
            uid = os.stat(f"/proc/{pid}").st_uid
        except OSError:
            continue
        user = name_of(uid)
        # grouped by program, so a browser's helpers ("Web Content", "RDD Process"…)
        # sit under the browser; interpreters keep their own name
        try:
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe")).removesuffix(" (deleted)")
        except OSError:
            exe = ""             # someone else's process: its own name will do
        interp = exe.startswith(("python", "node", "java", "perl", "ruby")) or exe in ("sh", "bash", "zsh", "fish", "env")
        name = exe if exe and not interp else comm
        if q and q not in name.lower() and q not in cmd.lower() and q not in user.lower():
            continue
        if "procsearch.py" in cmd:
            continue             # this search itself
        cpu = 100.0 * (tk - a.get(pid, tk)) / (dt * HZ * (os.cpu_count() or 1)) if dt > 0 else 0
        own = (uid == UID and pid != 1 and pid != ME and pid not in guard and comm not in PROTECTED and name not in PROTECTED
               and not CRITICAL.search(name) and not CRITICAL.search(comm) and not tide_shell(cmd))
        g = groups.setdefault((name, user), {"name": name, "note": "", "pids": [], "count": 0, "cpu": 0.0, "ram": 0,
                                              "user": user, "cmd": cmd[:160], "own": True})
        g["pids"].append(pid)
        g["count"] += 1
        g["cpu"] += cpu
        g["ram"] += int(f[21]) * PAGE
        g["own"] = g["own"] and own
    procs = sorted(groups.values(), key=lambda g: (g["cpu"], g["ram"]), reverse=True)
    for g in procs:
        g["cpu"] = round(g["cpu"], 1)
        if g["user"] != name_of(UID):
            g["note"] = g["user"]
    services = []
    r = subprocess.run(["systemctl", "--user", "list-units", "--type=service", "--all", "--no-legend", "--plain", "--no-pager"],
                       capture_output=True, text=True)
    for line in r.stdout.splitlines():
        parts = line.split(None, 4)
        if len(parts) < 4:
            continue
        unit, _load, active, sub = parts[:4]
        desc = parts[4] if len(parts) > 4 else ""
        if q and q not in unit.lower() and q not in desc.lower():
            continue
        services.append({"unit": unit, "desc": desc, "active": active, "sub": sub,
                         "own": not unit.startswith(PROTECTED_UNITS) and active == "active"})
    services.sort(key=lambda s: (s["active"] != "active", s["unit"]))
    print(json.dumps({"procs": procs[:60], "services": services[:20]}))


if __name__ == "__main__":
    main(" ".join(sys.argv[1:]))
