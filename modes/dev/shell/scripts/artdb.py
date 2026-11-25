#!/usr/bin/env python3
# Game art from SteamGridDB (the game launcher: right-click a game → Choose art).
# A free API key from steamgriddb.com (Settings → Games) is kept in
# ~/.local/state/tide/steamgriddb-key (only you can read it). Picked art is downloaded
# to ~/.local/share/tide/art/ and remembered per game in ~/.local/state/tide/art.json
# ({game id: {cover, hero}}), which scripts/games.py puts over the game's own art.
#
#   artdb.py has-key                     true / false
#   artdb.py set-key                     the key on standard input ("" removes it)
#   artdb.py find <kind> <title> [appid] up to 12 choices: [{thumb, url}]
#                                        kind: cover (600x900) | hero (wide banner)
#   artdb.py set <game id> <kind> <url>  download it and use it for that game
#   artdb.py reset <game id>             back to the game's own art
import hashlib, json, os, sys, urllib.parse, urllib.request
from pathlib import Path

STATE = Path.home() / ".local/state/tide"
KEY = STATE / "steamgriddb-key"
CHOSEN = STATE / "art.json"
ART = Path.home() / ".local/share/tide/art"
API = "https://www.steamgriddb.com/api/v2"


def out(v):
    print(json.dumps(v))


def key():
    try:
        return KEY.read_text().strip()
    except OSError:
        return ""


def get(path):
    req = urllib.request.Request(API + path, headers={"Authorization": "Bearer " + key(), "User-Agent": "Tide"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def find(kind, title, appid=""):
    if not key():
        return out({"error": "Add your SteamGridDB API key in Settings → Games first"})
    what = "grids" if kind == "cover" else "heroes"
    q = "?dimensions=600x900" if kind == "cover" else ""
    try:
        d = None
        if appid and appid.isdigit():
            try:
                d = get(f"/{what}/steam/{appid}{q}")
            except urllib.error.HTTPError:
                d = None
        if not d or not d.get("data"):
            s = get("/search/autocomplete/" + urllib.parse.quote(title, safe=""))
            if not s.get("data"):
                return out({"error": f"SteamGridDB doesn't know \"{title}\""})
            d = get(f"/{what}/game/{s['data'][0]['id']}{q}")
    except urllib.error.HTTPError as e:
        return out({"error": "SteamGridDB refused the key (check it in Settings → Games)" if e.code in (401, 403) else f"SteamGridDB answered {e.code}"})
    except (urllib.error.URLError, TimeoutError, ValueError) as e:
        return out({"error": "Couldn't reach SteamGridDB"})
    items = [{"thumb": a.get("thumb") or a.get("url"), "url": a.get("url")}
             for a in d.get("data", []) if a.get("url") and not a.get("nsfw") and not a.get("humor")]
    out(items[:12])


def chosen():
    try:
        return json.loads(CHOSEN.read_text())
    except (OSError, ValueError):
        return {}


def save(c):
    STATE.mkdir(parents=True, exist_ok=True)
    tmp = CHOSEN.with_suffix(".tmp")
    tmp.write_text(json.dumps(c, indent=1))
    tmp.replace(CHOSEN)


def set_art(gid, kind, url):
    u = urllib.parse.urlparse(url)
    if u.scheme != "https" or not u.netloc.endswith("steamgriddb.com"):
        return out({"error": "Not a SteamGridDB picture"})
    ext = os.path.splitext(u.path)[1].lower()
    ext = ext if ext in (".png", ".jpg", ".jpeg", ".webp") else ".png"
    ART.mkdir(parents=True, exist_ok=True)
    dest = ART / (hashlib.sha1(gid.encode()).hexdigest()[:16] + "-" + kind + ext)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Tide"})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = r.read(30_000_000)
    except (urllib.error.URLError, TimeoutError) as e:
        return out({"error": "Couldn't download it"})
    dest.write_bytes(data)
    c = chosen()
    c.setdefault(gid, {})[kind] = str(dest)
    save(c)
    out({"ok": True, "path": str(dest)})


def reset(gid):
    c = chosen()
    for p in (c.pop(gid, {}) or {}).values():
        try:
            Path(p).unlink()
        except OSError:
            pass
    save(c)
    out({"ok": True})


def main(a):
    if a[:1] == ["has-key"]:
        return out(bool(key()))
    if a[:1] == ["set-key"]:
        k = sys.stdin.readline().strip()
        STATE.mkdir(parents=True, exist_ok=True)
        if not k:
            KEY.unlink(missing_ok=True)
        else:
            fd = os.open(KEY, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as f:
                f.write(k + "\n")
        return out({"ok": True})
    if a[:1] == ["find"] and len(a) >= 3 and a[1] in ("cover", "hero"):
        return find(a[1], a[2], a[3] if len(a) > 3 else "")
    if a[:1] == ["set"] and len(a) == 4 and a[2] in ("cover", "hero"):
        return set_art(a[1], a[2], a[3])
    if a[:1] == ["reset"] and len(a) == 2:
        return reset(a[1])
    print(__doc__ if __doc__ else "usage: see the top of this file", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]) or 0)
