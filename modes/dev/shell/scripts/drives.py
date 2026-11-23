#!/usr/bin/env python3
# Drives for the System widget, the resource center and the fill alerts. One JSON list
# [{mount, device, fs, size, used, pct, label, path}].
#   drives.py                 every mounted drive, one entry per device (btrfs
#                             subvolumes of the same disk count once, under their
#                             shortest mount point); used to seed theme.json "drives"
#   drives.py --paths JSON    the drives in that list of paths, in that order; a path
#                             that's missing comes back as {path, missing: true}
#   drives.py --resolve PATH  the drive that holds PATH (or {path, error})
import json, os, subprocess, sys

SKIP = {"tmpfs", "devtmpfs", "efivarfs", "overlay", "squashfs", "proc", "sysfs", "ramfs", "fuse.portal", "nsfs"}


def df(*paths):
    r = subprocess.run(["df", "-B1", "--output=source,target,fstype,size,used", *paths], capture_output=True, text=True)
    rows = []
    for line in r.stdout.splitlines()[1:]:
        f = line.split()
        if len(f) >= 5:
            size, used = int(f[3]), int(f[4])
            rows.append({"mount": f[1], "device": f[0], "fs": f[2], "size": size, "used": used,
                         "pct": round(used * 100 / size) if size else 0})
    return rows


def label(mount):
    return "System" if mount == "/" else mount.rstrip("/").split("/")[-1]


def one(path):
    p = os.path.realpath(os.path.expanduser(path))
    if not os.path.exists(p):
        return {"path": path, "error": "That path doesn't exist"}
    rows = df(p)
    if not rows:
        return {"path": path, "error": "Couldn't read that drive"}
    d = rows[0]
    if d["fs"] in SKIP:
        return {"path": path, "error": "That's a " + d["fs"] + " mount, not a drive"}
    d["path"] = p
    d["label"] = label(d["mount"])
    return d


def detect():
    seen = {}
    for d in df():
        if d["fs"] in SKIP or not d["device"].startswith("/dev/"):
            continue
        if d["size"] < 2 * 1024**3:  # boot and EFI partitions
            continue
        src = d["device"]
        if src in seen and len(seen[src]["mount"]) <= len(d["mount"]):
            continue
        seen[src] = d
    for d in seen.values():
        d["label"] = label(d["mount"])
        d["path"] = d["mount"]
    return sorted(seen.values(), key=lambda d: (d["mount"] != "/", d["mount"]))


if len(sys.argv) > 2 and sys.argv[1] == "--resolve":
    print(json.dumps(one(sys.argv[2])))
elif len(sys.argv) > 2 and sys.argv[1] == "--paths":
    out = []
    for p in json.loads(sys.argv[2]):
        d = one(p)
        out.append({"path": p, "missing": True} if "error" in d else d)
    print(json.dumps(out))
else:
    print(json.dumps(detect()))
