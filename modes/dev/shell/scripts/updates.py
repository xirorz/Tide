#!/usr/bin/env python3
# Lists pending updates as one JSON object, without touching the live pacman
# database: checkupdates (pacman-contrib, its own temporary copy of the sync dbs),
# yay or paru -Qua (AUR; scripts/aur-helper.sh) and flatpak. Also lists Arch and CachyOS news posted since the
# last full upgrade.
import html, json, os, re, shutil, subprocess, sys, urllib.request
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

# packages that only take effect after a restart
SYSTEM = re.compile(r"^(linux(-[a-z0-9-]+)?|linux-firmware.*|nvidia.*|lib32-nvidia.*|mesa|lib32-mesa|vulkan-radeon|"
                    r"systemd|systemd-libs|glibc|lib32-glibc|amd-ucode|intel-ucode|dbus|dbus-broker)$")


def run(cmd, env=None):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=180, env=env).stdout
    except Exception:
        return ""


def size_mb(text):
    m = re.match(r"([\d.]+)\s*([KMG]i?B|B)", text.strip())
    if not m:
        return 0
    n, u = float(m.group(1)), m.group(2)[0]
    return n / 1024 if u == "K" else n * 1024 if u == "G" else n / 1048576 if u == "B" else n


def repo():
    if not shutil.which("checkupdates"):
        return []
    rows = []
    for line in run(["checkupdates"]).splitlines():
        f = line.split()
        if len(f) >= 4 and f[2] == "->":
            rows.append({"name": f[0], "from": f[1], "to": f[3], "repo": "", "mb": 0})
    if rows:
        # repository and download size from checkupdates' synced copy of the dbs
        db = os.environ.get("CHECKUPDATES_DB") or f"{os.environ.get('TMPDIR', '/tmp')}/checkup-db-{os.getuid()}/"
        info = run(["pacman", "-Si", "--dbpath", db] + [r["name"] for r in rows])
        by = {}
        cur = {}
        for line in info.splitlines():
            k, _, v = line.partition(":")
            k, v = k.strip(), v.strip()
            if k == "Repository":
                cur = {"repo": v}
            elif k == "Name":
                by[v] = cur
            elif k == "Download Size":
                cur["mb"] = size_mb(v)
        for r in rows:
            r["repo"] = by.get(r["name"], {}).get("repo", "")
            r["mb"] = by.get(r["name"], {}).get("mb", 0)
    return rows


def aur_helper():
    """yay or paru: scripts/aur-helper.sh with the Settings → System choice."""
    here = os.path.dirname(os.path.abspath(__file__))
    return run(["bash", os.path.join(here, "aur-helper.sh"), os.environ.get("TIDE_AUR_HELPER", "auto")]).strip()


def aur():
    helper = aur_helper()
    if not helper:
        return []
    rows = []
    for line in run([helper, "-Qua"]).splitlines():
        f = line.split()
        if len(f) >= 4 and f[2] == "->":
            rows.append({"name": f[0], "from": f[1], "to": f[3], "repo": "aur", "mb": 0})
    return rows


def flatpak():
    if not shutil.which("flatpak"):
        return []
    have = {}
    for line in run(["flatpak", "list", "--columns=application,version"]).splitlines():
        f = line.split("\t")
        if len(f) >= 2:
            have[f[0]] = f[1]
    rows = []
    for line in run(["flatpak", "remote-ls", "--updates", "--columns=name,application,version,download-size,origin"]).splitlines():
        f = line.split("\t")
        if len(f) < 5:
            continue
        rows.append({"name": f[0] or f[1], "from": have.get(f[1], ""), "to": f[2], "repo": f[4], "mb": size_mb(f[3])})
    return rows


def last_upgrade():
    try:
        with open("/var/log/pacman.log", errors="replace") as fh:
            last = None
            for line in fh:
                if "starting full system upgrade" in line:
                    last = line
        if last:
            return datetime.fromisoformat(last[1:last.index("]")].replace("Z", "+00:00"))
    except Exception:
        pass
    return None


FEEDS = {"arch": "https://archlinux.org/feeds/news/", "cachyos": "https://cachyos.org/rss.xml"}


def news(sources):
    since = last_upgrade()
    posts, ok = [], False
    for src in sources:
        try:
            req = urllib.request.Request(FEEDS[src], headers={"User-Agent": "tide-updates"})
            xml = urllib.request.urlopen(req, timeout=10).read().decode("utf-8", "replace")
        except Exception:
            continue
        ok = True
        for item in re.findall(r"<item>(.*?)</item>", xml, re.S):
            title = re.search(r"<title>(.*?)</title>", item, re.S)
            link = re.search(r"<link>(.*?)</link>", item, re.S)
            date = re.search(r"<pubDate>(.*?)</pubDate>", item, re.S)
            try:
                when = parsedate_to_datetime(date.group(1))
            except Exception:
                continue
            if since and when > since:
                posts.append({"source": src, "title": html.unescape(title.group(1).strip()) if title else "",
                              "link": link.group(1).strip() if link else "", "when": int(when.timestamp())})
    posts.sort(key=lambda p: -p["when"])
    return {"ok": ok, "posts": posts}


r = repo()
out = {
    "system": [x for x in r if SYSTEM.match(x["name"])],
    "apps": [x for x in r if not SYSTEM.match(x["name"])],
    "aur": aur(),
    "flatpak": flatpak(),
    # --news arch,cachyos (which feeds to read; none with --news "")
    "news": news([s for s in (sys.argv[sys.argv.index("--news") + 1] if "--news" in sys.argv else "arch,cachyos").split(",") if s in FEEDS]),
    "checked": int(datetime.now(timezone.utc).timestamp()),
}
print(json.dumps(out))
