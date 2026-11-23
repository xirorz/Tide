#!/usr/bin/env python3
"""Where and when each clipboard entry came from, next to cliphist.

The metadata lives in ~/.local/state/tide/clipmeta.json as
{"<cliphist id>": {"app": "<window class>", "time": <unix seconds>}}.

  clipmeta.py add <id> <app>    record a new clip (no-op if the id is known)
  clipmeta.py delete <id>       delete one entry from cliphist and the metadata
  clipmeta.py clear             wipe cliphist and the metadata
  clipmeta.py cleanup           keep clipboardMax entries, drop ones older than
                                clipboardDays (theme.json); only if clipboardCleanup is true
"""
import fcntl
import json
import os
import subprocess
import sys
import time

STATE = os.environ.get("TIDE_CLIPMETA", os.path.expanduser("~/.local/state/tide/clipmeta.json"))
THEME = os.environ.get("TIDE_THEME", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "theme.json"))


def load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save(meta):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(meta, f)
    os.replace(tmp, STATE)


def cliphist_ids():
    out = subprocess.run(["cliphist", "list"], capture_output=True, text=True).stdout
    return [line.split("\t", 1)[0] for line in out.splitlines() if "\t" in line]


def cliphist_delete(ids):
    if ids:
        subprocess.run(["cliphist", "delete"], input="".join(i + "\t\n" for i in ids), text=True)


def theme():
    try:
        with open(THEME) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        meta = load()
        if cmd == "add" and len(sys.argv) >= 3:
            cid = sys.argv[2]
            if cid not in meta:
                meta[cid] = {"app": sys.argv[3] if len(sys.argv) > 3 else "", "time": int(time.time())}
                save(meta)
        elif cmd == "delete" and len(sys.argv) >= 3:
            cliphist_delete([sys.argv[2]])
            meta.pop(sys.argv[2], None)
            save(meta)
        elif cmd == "clear":
            subprocess.run(["cliphist", "wipe"])
            save({})
        elif cmd == "cleanup":
            cfg = theme()
            if not cfg.get("clipboardCleanup", False):
                return
            keep = int(cfg.get("clipboardMax", 50))
            days = float(cfg.get("clipboardDays", 7))
            ids = cliphist_ids()
            cutoff = time.time() - days * 86400
            drop = set(ids[keep:])
            drop |= {i for i in ids if i in meta and meta[i].get("time", 0) < cutoff}
            cliphist_delete(sorted(drop))
            alive = set(ids) - drop
            save({k: v for k, v in meta.items() if k in alive})
        else:
            print(__doc__.strip(), file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
