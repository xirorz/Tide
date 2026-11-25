#!/usr/bin/env python3
# Settings → System → Free up space: what can be removed safely, and how much it frees.
# Only known, safe things: nothing here hunts through your files. The big folders in
# your home are listed for you to look at, never deleted.
#
#   cleanup.py scan          {"items": [...], "caches": [...], "big": [...]}
#     items: {id, label, sub, bytes, count, how: "terminal" | "here", cmd (terminal ones)}
#     caches: ~/.cache folders, biggest first {name, bytes} (a few are left out: they
#             hold your data, not a cache: clipboard history, Tide's own state)
#     big: the biggest folders in your home {path, bytes}, to look at
#   cleanup.py clean <id>    the "here" ones: aur, npm, trash, cache:<name>
#
# "terminal" steps need the password or a package manager's own question: Settings runs
# their cmd in your terminal, where pacman / flatpak list what goes and ask first.
import json, os, re, shutil, subprocess, sys
from pathlib import Path

HOME = Path.home()
CACHE = HOME / ".cache"
TRASH = HOME / ".local/share/Trash"
# not caches, whatever the folder says: your clipboard history, Tide's own state, the
# AUR helpers (their own row)
KEEP = {"cliphist", "tide", "yay", "paru"}


def run(cmd, timeout=60):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def size(p):
    """Bytes under p (no following links, one filesystem)."""
    out = run(["du", "-sxb", str(p)], timeout=120)
    try:
        return int(out.split()[0])
    except (IndexError, ValueError):
        return 0


def human_to_bytes(n, unit):
    mult = {"B": 1, "KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3, "TiB": 1024 ** 4,
            "K": 1024, "M": 1024 ** 2, "G": 1024 ** 3, "T": 1024 ** 4}
    return int(float(n) * mult.get(unit, 1))


def pkg_cache():
    """Old package files pacman keeps: all but the newest two of each installed one,
    and every version of uninstalled ones (paccache's dry runs)."""
    if not shutil.which("paccache"):
        return None
    total, count = 0, 0
    for args in (["-dk2"], ["-duk0"]):
        out = run(["paccache"] + args)
        m = re.search(r"(\d+) candidates? \(disk space saved: ([\d.]+) (\w+)\)", out)
        if m:
            count += int(m.group(1))
            total += human_to_bytes(m.group(2), m.group(3))
    return {"id": "pkgcache", "label": "Package cache",
            "sub": "Old downloaded packages: the newest two of each are kept, and none of ones you've uninstalled",
            "bytes": total, "count": count, "how": "terminal",
            "cmd": "sudo paccache -rk2 && sudo paccache -ruk0"}


def orphans():
    names = run(["pacman", "-Qdtq"]).split()
    total = 0
    if names:
        for line in run(["pacman", "-Qi"] + names).splitlines():
            m = re.match(r"Installed Size\s*:\s*([\d.]+)\s*(\w+)", line)
            if m:
                total += human_to_bytes(m.group(1), m.group(2))
    return {"id": "orphans", "label": "Packages nothing needs",
            "sub": "Installed as a dependency, and nothing uses them now. pacman lists them and asks before removing",
            "bytes": total, "count": len(names), "how": "terminal",
            "cmd": "sudo pacman -Rns $(pacman -Qdtq)"}


def aur_cache():
    dirs = [d for d in (CACHE / "yay", CACHE / "paru") if d.is_dir()]
    if not dirs:
        return None
    return {"id": "aur", "label": "AUR build files",
            "sub": "What yay / paru kept from building AUR packages (they download again when needed)",
            "bytes": sum(size(d) for d in dirs), "count": 0, "how": "here"}


def flatpak_unused():
    if not shutil.which("flatpak"):
        return None
    out = run(["flatpak", "uninstall", "--unused", "--assumeno"], timeout=60)
    refs = [l for l in out.splitlines() if re.match(r"^\s*\d+\.\s", l)]
    return {"id": "flatpak", "label": "Unused Flatpak runtimes",
            "sub": "Runtimes no installed Flatpak app uses any more. Flatpak lists them and asks first",
            "bytes": 0, "count": len(refs), "how": "terminal", "cmd": "flatpak uninstall --unused"}


def npm_cache():
    d = HOME / ".npm/_cacache"
    if not d.is_dir():
        return None
    return {"id": "npm", "label": "npm download cache",
            "sub": "Packages npm downloaded once; it downloads them again when needed",
            "bytes": size(d), "count": 0, "how": "here"}


def journal():
    total = 0
    for args in (["--disk-usage"], ["--user", "--disk-usage"]):
        m = re.search(r"take up ([\d.]+)(\w)", run(["journalctl"] + args))
        if m:
            total += human_to_bytes(m.group(1), m.group(2))
    return {"id": "journal", "label": "System logs",
            "sub": "Logs older than two weeks",
            "bytes": total, "count": 0, "how": "terminal",
            "cmd": "sudo journalctl --vacuum-time=2weeks && journalctl --user --vacuum-time=2weeks"}


def trash():
    if not TRASH.is_dir():
        return None
    files = TRASH / "files"
    n = len(list(files.iterdir())) if files.is_dir() else 0
    return {"id": "trash", "label": "Trash", "sub": "Files you deleted from your file manager",
            "bytes": size(TRASH), "count": n, "how": "here"}


def caches():
    out = []
    if not CACHE.is_dir():
        return out
    for d in CACHE.iterdir():
        if d.is_dir() and not d.is_symlink() and d.name not in KEEP:
            b = size(d)
            if b >= 20 * 1024 ** 2:
                out.append({"name": d.name, "bytes": b})
    return sorted(out, key=lambda x: -x["bytes"])[:15]


def big():
    """The biggest folders in your home (one level, hidden ones too), to look at."""
    out = run(["du", "-x", "-d1", "-b", str(HOME)], timeout=180)
    rows = []
    for line in out.splitlines():
        try:
            b, p = line.split("\t", 1)
        except ValueError:
            continue
        if p != str(HOME):
            rows.append({"path": p, "bytes": int(b)})
    return sorted(rows, key=lambda x: -x["bytes"])[:10]


def empty_dir(p):
    for c in p.iterdir():
        if c.is_dir() and not c.is_symlink():
            shutil.rmtree(c, ignore_errors=True)
        else:
            try:
                c.unlink()
            except OSError:
                pass


def clean(what):
    if what == "aur":
        for d in (CACHE / "yay", CACHE / "paru"):
            if d.is_dir():
                empty_dir(d)
    elif what == "npm":
        d = HOME / ".npm/_cacache"
        if d.is_dir() and not d.is_symlink():
            shutil.rmtree(d, ignore_errors=True)
    elif what == "trash":
        for sub in ("files", "info", "expunged"):
            if (TRASH / sub).is_dir():
                empty_dir(TRASH / sub)
    elif what.startswith("cache:"):
        name = what[6:]
        d = CACHE / name
        # one folder directly in ~/.cache, by its plain name, never the kept ones
        if "/" in name or name in ("", ".", "..") or name in KEEP or not d.is_dir() or d.is_symlink():
            print(json.dumps({"error": "Not a cache Tide clears"}))
            return 1
        empty_dir(d)
    else:
        print(json.dumps({"error": "Unknown"}))
        return 1
    print(json.dumps({"ok": True}))
    return 0


def main(a):
    if a == ["scan"]:
        items = [x for x in (pkg_cache(), orphans(), aur_cache(), npm_cache(), flatpak_unused(), journal(), trash()) if x]
        print(json.dumps({"items": items, "caches": caches(), "big": big()}))
        return 0
    if a[:1] == ["clean"] and len(a) == 2:
        return clean(a[1])
    print("usage: cleanup.py scan | clean <aur|npm|trash|cache:NAME>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
