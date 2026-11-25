#!/usr/bin/env python3
# The game launcher's library (services/Games.qml), from local files only:
#   games.py            {"games": [...], "steamRunning": bool}
#   games.py running    the appids running now (a cheap check while the launcher is open)
#   games.py emulators  the known emulators: each one's platform, file types and launch
#                       arguments, copies found on this PC and game folders it suggests
# Emulators (~/.config/Tide/emulators.json, set up in the launcher's "Add a game or
# emulator"): each one's folders are scanned for its file types; a game launches as
# <program> <arguments with {rom}>. Settings stay in the emulator itself.
# Steam: installed games from each library's steamapps/appmanifest_*.acf (libraries
# listed in steamapps/libraryfolders.vdf), last played and playtime from the signed-in
# account's userdata/<id>/config/localconfig.vdf, art from the account's custom grid
# (userdata/<id>/config/grid) or appcache/librarycache/<appid>/. A game is running when
# Steam's launcher process for it (SteamLaunch AppId=<id>) exists.
import glob, json, os, re, subprocess, sys

STEAM = next((p for p in (os.path.expanduser("~/.local/share/Steam"), os.path.expanduser("~/.steam/steam"))
              if os.path.isdir(p)), "")
# installed things that aren't games
NOT_GAMES = re.compile(r"^(Proton|Steam Linux Runtime|Steamworks Common|SteamVR|Steam Audio)", re.I)


def vdf(text):
    """Valve's text KeyValues into nested dicts."""
    tokens = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', text)
    root, stack, key = {}, [], None
    cur = root
    for s, brace in tokens:
        if brace == "{":
            new = {}
            cur[key] = new
            stack.append(cur)
            cur, key = new, None
        elif brace == "}":
            cur = stack.pop() if stack else root
        elif key is None:
            key = s
        else:
            cur[key] = s
            key = None
    return root


def read(p):
    try:
        with open(p, errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def libraries():
    data = vdf(read(f"{STEAM}/steamapps/libraryfolders.vdf")).get("libraryfolders", {})
    paths = [v.get("path") for v in data.values() if isinstance(v, dict) and v.get("path")]
    return paths or [STEAM]


def account():
    """The signed-in account's userdata folder (SteamID64 → account id)."""
    users = vdf(read(f"{STEAM}/config/loginusers.vdf")).get("users", {})
    for sid, u in users.items():
        if isinstance(u, dict) and u.get("MostRecent") == "1":
            return str(int(sid) - 76561197960265728)
    dirs = [d for d in glob.glob(f"{STEAM}/userdata/*") if os.path.basename(d) != "0"]
    return os.path.basename(max(dirs, key=os.path.getmtime)) if dirs else ""


def activity(acct):
    t = read(f"{STEAM}/userdata/{acct}/config/localconfig.vdf")
    apps = vdf(t).get("UserLocalConfigStore", {}).get("Software", {}).get("Valve", {}).get("Steam", {})
    apps = apps.get("apps") or apps.get("Apps") or {}
    return {k: v for k, v in apps.items() if isinstance(v, dict)}


def art(appid, acct):
    grid = f"{STEAM}/userdata/{acct}/config/grid"
    cache = f"{STEAM}/appcache/librarycache/{appid}"
    def first(*names, where=None):
        for n in names:
            hits = glob.glob(f"{grid}/{n}") if where == "grid" else glob.glob(f"{cache}/{n}") + glob.glob(f"{cache}/*/{n}")
            if hits:
                return hits[0]
        return ""
    return {
        "cover": first(f"{appid}p.png", f"{appid}p.jpg", where="grid") or first("library_600x900.jpg", "library_capsule.jpg"),
        "hero": first(f"{appid}_hero.png", f"{appid}_hero.jpg", where="grid") or first("library_hero.jpg"),
        "logo": first(f"{appid}_logo.png", where="grid") or first("logo.png"),
        "header": first("header.jpg", "library_header.jpg"),
    }


# platform → shown name, short badge, file types; emulator → platform, launch arguments, programs to look for
PLATFORMS = {
    "switch": ("Switch", "SWITCH", ["xci", "nsp", "nca", "nro", "nso"]),
    "switch2": ("Switch 2", "SWITCH 2", ["nup", "xci", "nsp", "nca", "nro", "nso"]),
    "3ds": ("Nintendo 3DS", "3DS", ["3ds", "cci", "cia", "cxi", "3dsx", "app"]),
    "ps2": ("PlayStation 2", "PS2", ["iso", "chd", "cso", "gz"]),
    "gc": ("GameCube / Wii", "GC", ["iso", "gcm", "gcz", "rvz", "wbfs", "ciso", "wad"]),
    "ps1": ("PlayStation", "PS1", ["cue", "chd", "pbp", "m3u"]),
    "gba": ("Game Boy Advance", "GBA", ["gba", "gb", "gbc"]),
    "psp": ("PSP", "PSP", ["iso", "cso", "pbp"]),
    "wiiu": ("Wii U", "WIIU", ["wua", "wud", "wux", "rpx"]),
    "ds": ("Nintendo DS", "DS", ["nds"]),
    "ps3": ("PlayStation 3", "PS3", ["iso", "pkg"]),
    "retro": ("RetroArch", "RETRO", ["zip", "7z", "nes", "sfc", "smc", "z64", "n64", "md", "gen", "sms", "pce"]),
}
EMULATORS = {
    "lichii": ("Lichii", "switch", "-f -g {rom}", ["lichii", "Lichii"], ""),       # an Eden fork (Switch and Switch 2)
    "eden": ("Eden", "switch", "-f -g {rom}", ["eden", "Eden"], "dev.eden_emu.eden"),
    "ryujinx": ("Ryujinx", "switch", "--fullscreen {rom}", ["ryujinx", "Ryujinx"], "io.github.ryubing.Ryujinx"),
    "citron": ("Citron", "switch", "-f -g {rom}", ["citron"], ""),
    "suyu": ("Suyu", "switch", "-f -g {rom}", ["suyu"], "org.suyu_emu.suyu"),
    "azahar": ("Azahar", "3ds", "{rom}", ["azahar"], "org.azahar_emu.Azahar"),
    "pcsx2": ("PCSX2", "ps2", "-batch -fullscreen -- {rom}", ["pcsx2-qt", "pcsx2"], "net.pcsx2.PCSX2"),
    "dolphin": ("Dolphin", "gc", "-b -e {rom}", ["dolphin-emu"], "org.DolphinEmu.dolphin-emu"),
    "duckstation": ("DuckStation", "ps1", "-batch -fullscreen -- {rom}", ["duckstation-qt", "duckstation"], "org.duckstation.DuckStation"),
    "mgba": ("mGBA", "gba", "-f {rom}", ["mgba-qt", "mgba"], "io.mgba.mGBA"),
    "ppsspp": ("PPSSPP", "psp", "--fullscreen {rom}", ["PPSSPPSDL", "ppsspp"], "org.ppsspp.PPSSPP"),
    "cemu": ("Cemu", "wiiu", "-f -g {rom}", ["Cemu", "cemu"], "info.cemu.Cemu"),
    "melonds": ("melonDS", "ds", "-f {rom}", ["melonDS"], "net.kuribo64.melonDS"),
    "rpcs3": ("RPCS3", "ps3", "--no-gui {rom}", ["rpcs3"], "net.rpcs3.RPCS3"),
    # RetroArch needs a core per system: put it in the arguments (-L /path/to/core.so)
    "retroarch": ("RetroArch", "retro", "-f -L CORE {rom}", ["retroarch"], "org.libretro.RetroArch"),
}
EMU_FILE = os.path.expanduser("~/.config/Tide/emulators.json")


# emulators that run more than one system (the first is the one in EMULATORS)
MORE_SYSTEMS = {"lichii": ["switch2"], "dolphin": [], "retroarch": []}


def find_programs(names, flatpak):
    """Where an emulator is installed: on PATH, as a Flatpak, or an AppImage in the usual places."""
    import shutil
    out = [shutil.which(n) for n in names if shutil.which(n)]
    if flatpak and subprocess.run(["flatpak", "info", flatpak], capture_output=True).returncode == 0:
        out.append("flatpak run " + flatpak)
    # programs that desktop entries launch (an AppImage or unpacked build anywhere)
    for f in glob.glob(os.path.expanduser("~/.local/share/applications/*.desktop")) + glob.glob("/usr/share/applications/*.desktop"):
        m = re.search(r"^Exec=\"?([^\"\s]+)", read(f), re.M)
        if m and os.path.basename(m.group(1)).lower().split(".")[0] in {n.lower() for n in names} and os.path.isfile(m.group(1)):
            out.append(m.group(1))
    for d in ("~/Applications", "~/.local/bin", "~/Downloads", "~/AppImages", "/opt"):
        for n in names:
            out += glob.glob(os.path.expanduser(f"{d}/*{n}*.AppImage")) + glob.glob(os.path.expanduser(f"{d}/{n}*/*.AppImage"))
    return list(dict.fromkeys(out))


def suggest_folders(emu, platform):
    """Game folders the emulator already knows (its qt-config.ini), and ROM folders named for the platform."""
    out = []
    for ini in glob.glob(os.path.expanduser(f"~/.config/{emu}*/qt-config.ini")) + glob.glob(os.path.expanduser(f"~/.config/{emu}-emu/qt-config.ini")):
        out += re.findall(r"gamedirs\\\d+\\path=(/[^\n]+)", read(ini))
    names = {platform, PLATFORMS[platform][1].lower()}
    for root in ("~/roms", "~/ROMs", "~/Games", "/mnt/*/roms", "/mnt/*/ROMs", "/mnt/*/Games"):
        for d in glob.glob(os.path.expanduser(root) + "/*"):
            b = os.path.basename(d).lower()
            if os.path.isdir(d) and (b in names or re.sub(r"\d+$", "", b) in names):
                out.append(d)
    return [d for d in dict.fromkeys(out) if os.path.isdir(d)]


def emulators_info():
    return {"platforms": {k: {"name": v[0], "short": v[1], "exts": v[2]} for k, v in PLATFORMS.items()},
            "emulators": [{"id": k, "name": v[0], "platform": v[1], "platforms": [v[1]] + MORE_SYSTEMS.get(k, []), "args": v[2], "exts": PLATFORMS[v[1]][2],
                           "found": find_programs(v[3], v[4]), "folders": suggest_folders(k, v[1])} for k, v in EMULATORS.items()]}


def cover_for(path, folder):
    """A cover next to the game (same name, .png/.jpg) or in a covers folder (by file
    name or by cleaned title)."""
    stem = os.path.splitext(os.path.basename(path))[0]
    here = os.path.dirname(path)
    dirs = [here] + [os.path.join(b, n) for b in (here, folder) for n in ("covers", "Covers", "icons", "Icons")]
    for d in dirs:
        for name in (stem, clean_title(os.path.basename(path))):
            for ext in ("png", "jpg", "jpeg", "webp"):
                c = os.path.join(d, f"{name}.{ext}")
                if os.path.isfile(c):
                    return c
    # loosely named pictures in a covers / icons folder ("bananza.jpg" for DonkeyKongBananza):
    # the picture's name inside the title, or a shared word of 4+ letters
    squash = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
    title = clean_title(os.path.basename(path))
    words = {w for w in re.findall(r"[a-z0-9]{4,}", title.lower())} | {squash(title)}
    for d in dirs[1:]:
        for f in sorted(glob.glob(os.path.join(d, "*"))):
            if f.rsplit(".", 1)[-1].lower() not in ("png", "jpg", "jpeg", "webp"):
                continue
            name = os.path.splitext(os.path.basename(f))[0]
            if (len(squash(name)) >= 4 and squash(name) in squash(title)) or words & set(re.findall(r"[a-z0-9]{4,}", name.lower())):
                return f
    return ""


def clean_title(name):
    t = os.path.splitext(name)[0]
    t = re.sub(r"\[[^\]]*\]|\([^)]*\)", "", t)      # [0100…][v0], (USA), (Rev 1)…
    t = re.sub(r"_+", " ", t)
    if " " not in t.strip():
        t = re.sub(r"\.+", " ", t)                   # Super.Mario.Bros → Super Mario Bros
    if " " not in t.strip():
        t = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", t)   # DonkeyKongBananza → Donkey Kong Bananza
    t = re.sub(r"\s*\+\s*(update|dlc)\b.*$", "", t, flags=re.I)   # "… + Update 1.8.0"
    t = re.sub(r"\s+", " ", t).strip(" -")
    # catalog style "Legend of Zelda, The - Ocarina…" → "The Legend of Zelda - Ocarina…"
    t = re.sub(r"^(.+?), (The|A|An)\b", r"\2 \1", t)
    return t or name


def emulator_games():
    try:
        emus = json.load(open(EMU_FILE))
    except (OSError, ValueError):
        return []
    out = []
    for e in emus:
        for entry in e.get("folders", []):
            folder = entry.get("path", "") if isinstance(entry, dict) else entry
            plat = (entry.get("platform") if isinstance(entry, dict) else "") or e.get("platform", "")
            # the emulator's file types plus this folder's system's usual ones (a Switch 2
            # folder still finds .nup when the list was filled in for Switch)
            exts = {x.lower() for x in (e.get("exts") or [])} | set(PLATFORMS.get(plat, ("", "", []))[2])
            if not folder:
                continue
            for root, dirs, files in os.walk(folder):
                if root[len(folder):].count(os.sep) >= 3:
                    dirs[:] = []
                for f in files:
                    if f.rsplit(".", 1)[-1].lower() in exts:
                        path = os.path.join(root, f)
                        out.append({"id": "emu:" + e["id"] + ":" + path, "emulator": e["id"], "emuName": e.get("name", ""),
                                    "platform": plat, "title": clean_title(f), "path": path, "installed": True,
                                    "lastPlayed": 0, "playtime": 0, "running": False, "ready": True,
                                    "cover": cover_for(path, folder), "hero": "", "logo": "", "header": ""})
    return out


def app_types(appids):
    """Steam's own app type ("game", "application", "tool"…) for these appids, from the
    binary appcache/appinfo.vdf (format 28 or 29: entry headers, binary key-values,
    and from 29 on a string table at the end). Only the wanted entries are parsed."""
    import struct
    want, out = {int(a) for a in appids}, {}
    try:
        data = open(f"{STEAM}/appcache/appinfo.vdf", "rb").read()
    except OSError:
        return out
    magic, _ = struct.unpack_from("<II", data, 0)
    v29 = magic == 0x07564429
    if magic not in (0x07564428, 0x07564429):
        return out
    pos = 8
    strings = []
    if v29:
        (table,) = struct.unpack_from("<q", data, 8)
        pos = 16
        n, = struct.unpack_from("<I", data, table)
        q = table + 4
        for _ in range(n):
            e = data.index(b"\0", q)
            strings.append(data[q:e].decode("utf-8", "replace"))
            q = e + 1

    def key(p):
        if v29:
            (i,) = struct.unpack_from("<I", data, p)
            return strings[i] if i < len(strings) else "", p + 4
        e = data.index(b"\0", p)
        return data[p:e].decode("utf-8", "replace"), e + 1

    def kv(p):
        obj = {}
        while True:
            t = data[p]; p += 1
            if t == 8:
                return obj, p
            k, p = key(p)
            if t == 0:
                obj[k], p = kv(p)
            elif t == 1:
                e = data.index(b"\0", p); obj[k] = data[p:e].decode("utf-8", "replace"); p = e + 1
            elif t in (2, 3, 4, 6):
                p += 4
            elif t in (7, 10):
                p += 8
            else:
                return obj, p

    while pos + 8 <= len(data) and want - out.keys():
        appid, size = struct.unpack_from("<II", data, pos)
        if appid == 0:
            break
        nxt = pos + 8 + size
        if appid in want:
            try:
                info, _ = kv(pos + 8 + 60)
                out[str(appid)] = (info.get("appinfo", {}).get("common", {}).get("type") or "").lower()
            except (IndexError, struct.error, ValueError):
                pass
        pos = nxt
    return out


LUTRIS = os.path.expanduser("~/.local/share/lutris")
MANUAL_FILE = os.path.expanduser("~/.config/Tide/games.json")
STATE_FILE = os.path.expanduser("~/.local/state/tide/games.json")


def lutris_games():
    """Lutris's installed games, read-only from its pga.db; covers and banners from its
    coverart and banners folders. They launch with `lutris lutris:rungameid/<id>`."""
    import sqlite3
    try:
        if json.load(open(STATE_FILE)).get("lutris") is False:      # Settings → Games → Lutris off
            return []
    except (OSError, ValueError):
        pass
    db = f"{LUTRIS}/pga.db"
    if not os.path.isfile(db):
        return []
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        rows = con.execute("select id, name, slug, runner, lastplayed, playtime from games where installed = 1").fetchall()
        con.close()
    except sqlite3.Error:
        return []
    out = []
    for gid, name, slug, runner, last, hours in rows:
        img = lambda d: next((f for f in (f"{LUTRIS}/{d}/{slug}.jpg", f"{LUTRIS}/{d}/{slug}.png", os.path.expanduser(f"~/.cache/lutris/{d}/{slug}.jpg")) if os.path.isfile(f)), "")
        out.append({"id": f"lutris:{gid}", "platform": "lutris", "title": name, "installed": True, "runner": runner or "",
                    "command": ["lutris", f"lutris:rungameid/{gid}"], "lastPlayed": int(last or 0), "playtime": int(round((hours or 0) * 60)),
                    "running": False, "ready": True, "cover": img("coverart"), "hero": img("banners"), "logo": "", "header": ""})
    return out


def chosen_art(games):
    """Art and names picked in the launcher (scripts/artdb.py, ~/.local/state/tide/art.json)
    over the game's own."""
    try:
        with open(os.path.expanduser("~/.local/state/tide/art.json")) as f:
            picked = json.load(f)
    except (OSError, ValueError):
        return games
    for g in games:
        for kind, v in (picked.get(g.get("id", "")) or {}).items():
            if kind in ("cover", "hero") and os.path.isfile(v):
                g[kind] = v
            elif kind == "title" and v:
                g["title"] = v
    return games


def manual_games():
    """Games added by hand in Settings → Games: a program, AppImage or script, launched directly."""
    try:
        items = json.load(open(MANUAL_FILE))
    except (OSError, ValueError):
        return []
    out = []
    for g in items if isinstance(items, list) else []:
        prog = os.path.expanduser(g.get("program", ""))
        if not prog:
            continue
        out.append({"id": "pc:" + g.get("id", prog), "platform": "pc", "title": g.get("name") or os.path.basename(prog), "installed": True,
                    "command": [prog] + (g.get("args") or []), "path": prog, "lastPlayed": 0, "playtime": 0, "running": False, "ready": True,
                    "cover": os.path.expanduser(g.get("cover", "")), "hero": "", "logo": "", "header": ""})
    return out


TIDE_STEAM = os.path.expanduser("~/.config/Tide/bin/tide-steam")


def steam_owned():
    """Owned games that aren't installed, from Tide's Steam helper (vendor/ugos-steam,
    through the running Steam client; it keeps the last answer when Steam is closed).
    Returns (games, note): note says why there are none when the helper can't answer."""
    if not os.access(TIDE_STEAM, os.X_OK):
        return [], ""
    try:
        r = subprocess.run([TIDE_STEAM, "--state", os.path.expanduser("~/.local/state/tide/steam"), "library"],
                           capture_output=True, text=True, timeout=25)
        d = json.loads(r.stdout or "{}")
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return [], "Steam's full library isn't available right now, so only installed games show."
    if "error" in d:
        return [], "Steam's full library isn't available right now (" + d["error"].get("code", "error") + "), so only installed games show."
    out = []
    for g in d.get("games", []):
        if g.get("installed") or g.get("kind", "game") != "game":
            continue
        appid = str(g["appid"])
        local = art(appid, "")
        out.append({"id": "steam:" + appid, "appid": appid, "platform": "steam", "title": g.get("name", appid), "kind": "game",
                    "installed": False, "lastPlayed": int(g.get("last_played") or 0), "playtime": int(g.get("minutes_played") or 0),
                    "running": False, "ready": True, "cover": local["cover"] or g.get("cover", ""), "hero": local["hero"],
                    "logo": local["logo"], "header": local["header"]})
    return out, ("Showing the last library Steam gave (Steam isn't running)." if d.get("stale") else "")


def running():
    out = subprocess.run(["ps", "-eo", "args"], capture_output=True, text=True).stdout
    return sorted({m.group(1) for m in re.finditer(r"SteamLaunch AppId=(\d+)", out)})


def steam_running():
    return subprocess.run(["pgrep", "-x", "steam"], capture_output=True).returncode == 0


def games():
    if not STEAM:
        return []
    acct = account()
    act = activity(acct) if acct else {}
    now = set(running())
    out, seen = [], set()
    for lib in libraries():
        for f in glob.glob(f"{lib}/steamapps/appmanifest_*.acf"):
            st = vdf(read(f)).get("AppState", {})
            appid, name = st.get("appid", ""), st.get("name", "")
            if not appid or appid in seen or NOT_GAMES.search(name):
                continue
            seen.add(appid)
            a = act.get(appid, {})
            last = int(a.get("LastPlayed") or st.get("LastPlayed") or 0)
            out.append({"id": "steam:" + appid, "appid": appid, "platform": "steam", "title": name, "kind": "",
                        "installed": True, "lastPlayed": last, "playtime": int(a.get("Playtime") or 0),
                        "running": appid in now,
                        # still downloading or updating (StateFlags without "fully installed")
                        "ready": (int(st.get("StateFlags") or 4) & 4) != 0 and int(st.get("StateFlags") or 4) & 0x400 == 0,
                        **art(appid, acct)})
    # Steam's app type: Blender, Lossless Scaling and the like are "application"
    kinds = app_types([g["appid"] for g in out])
    for g in out:
        g["kind"] = kinds.get(g["appid"], "")
    return out


if __name__ == "__main__":
    if sys.argv[1:] == ["running"]:
        print(json.dumps(running()))
    elif sys.argv[1:2] == ["window"] and len(sys.argv) > 2:
        # has the game opened a window yet? "<address> <fullscreen>" or "no"
        #   window PID           the process or one it started (emulators)
        #   window steam APPID   Steam's launch of that game
        procs, cmds = {}, {}
        for d in glob.glob("/proc/[0-9]*/stat"):
            st = read(d)
            if st:
                pid = int(d.split("/")[2])
                procs[pid] = int(st[st.rfind(")") + 2:].split()[1])
        steam = sys.argv[2] == "steam" and len(sys.argv) > 3
        if steam:
            tag = "SteamLaunch\0AppId=" + sys.argv[3] + "\0"
            kids = {pid for pid in procs if tag in (read(f"/proc/{pid}/cmdline") or "")}
        else:
            kids = {int(sys.argv[2])}
        changed = True
        while changed:
            changed = False
            for pid, ppid in procs.items():
                if ppid in kids and pid not in kids:
                    kids.add(pid)
                    changed = True
        try:
            clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout)
        except ValueError:
            clients = []
        wins = [c for c in clients if c.get("pid") in kids or (steam and c.get("class") == "steam_app_" + sys.argv[3])]
        win = min(wins, key=lambda c: bool(c.get("floating")), default=None)     # the main window, not a dialog
        print(f"{win['address']} {win.get('fullscreen', 0)}" if win else "no")
    elif sys.argv[1:] == ["emulators"]:
        print(json.dumps(emulators_info()))
    else:
        owned, note = steam_owned()
        print(json.dumps({"games": chosen_art(games() + owned + emulator_games() + lutris_games() + manual_games()), "steamRunning": steam_running(), "steamNote": note,
                          "lutrisFound": os.path.isfile(f"{LUTRIS}/pga.db"),
                          "platforms": dict({k: {"name": v[0], "short": v[1]} for k, v in PLATFORMS.items()},
                                            lutris={"name": "Lutris", "short": "LUTRIS"}, pc={"name": "PC", "short": "PC"})}))
