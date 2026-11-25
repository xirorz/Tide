pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The game launcher (Mod+G, games/GameLauncher.qml). The library comes from
// scripts/games.py: Steam's local files (installed games, playtime, art) and the
// emulators set up in the launcher (~/.config/Tide/emulators.json: program, launch
// arguments with {rom}, game folders). Favourites, emulator play time and the "Pause
// local AI while playing" switch live in ~/.local/state/tide/games.json.
// Steam games launch through `steam -silent steam://rungameid/<id>`; emulator games
// start detached (a Tide restart never closes a game) and are followed by their
// process id. A controller (scripts/gamepad.py, only while the launcher is open)
// drives it the same way the keyboard does.
Singleton {
    id: root
    property bool open: false
    function toggle() { open = !open; if (open) refresh(); }
    onOpenChanged: if (!open) { picking = false; }

    property var raw: []
    property string steamNote: ""          // the Steam helper couldn't answer: only installed games show
    property bool steamRunning: false
    property bool loading: false
    property var platformInfo: ({ steam: { name: "Steam", short: "STEAM" } })
    // emulator games get their last played and play time from Tide's own record
    // Steam apps that aren't games (Blender, Lossless Scaling…) stay out unless shown
    property bool showApps: false
    readonly property int appCount: raw.filter(g => g.kind && g.kind !== "game").length
    readonly property var games: raw.filter(g => showApps || !g.kind || g.kind === "game").map(g => g.platform === "steam" || g.platform === "lutris" || !played[g.id] ? g
        : Object.assign({}, g, { lastPlayed: played[g.id].last || 0, playtime: Math.round(played[g.id].minutes || 0) }))
    function refresh() { if (!lister.running) { loading = true; lister.running = true; } }
    Process {
        id: lister
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/games.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.raw = d.games; root.steamRunning = d.steamRunning; root.steamNote = d.steamNote || ""; root.lutrisFound = !!d.lutrisFound;
                    root.platformInfo = Object.assign({ steam: { name: "Steam", short: "STEAM" } }, d.platforms || {});
                } catch (e) {}
                root.loading = false;
            }
        }
    }

    // ---- what Tide remembers ----
    property var favs: []
    property bool pauseAi: true
    property var played: ({})                // emulator games: id -> { last, minutes }
    property var emuRun: null                // { id, pid, start } while an emulator game runs
    readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/tide/games.json"
    FileView {
        id: sf
        path: root.stateFile
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.favs = d.favs || []; root.pauseAi = d.pauseAi !== false; root.played = d.played || {}; root.emuRun = d.emuRun || null;
                root.showApps = d.showApps === true;
                root.artAdult = d.artAdult === true;
                root.lutris = d.lutris !== false;
            } catch (e) {}
        }
    }
    function saveState() { sf.setText(JSON.stringify({ favs: favs, pauseAi: pauseAi, played: played, emuRun: emuRun, showApps: showApps, lutris: lutris, artAdult: artAdult }, null, 2)); }
    // Lutris's games (read from its own library); Settings → Games can turn them off
    property bool lutris: true
    property bool lutrisFound: false
    function setLutris(on) { lutris = on; saveState(); refreshSoon.restart(); }
    // games added by hand (Settings → Games): ~/.config/Tide/games.json
    readonly property string manualFile: Quickshell.env("HOME") + "/.config/Tide/games.json"
    property var manual: []
    FileView {
        id: mf
        path: root.manualFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.manual = JSON.parse(text()) || []; } catch (e) { root.manual = []; } }
    }
    function saveManual(list) { manual = list; mf.setText(JSON.stringify(list, null, 2) + "\n"); refreshSoon.restart(); }
    function setShowApps(on) { showApps = on; saveState(); }
    function isFav(id) { return favs.indexOf(id) >= 0; }
    function toggleFav(id) { favs = isFav(id) ? favs.filter(x => x !== id) : favs.concat([id]); saveState(); }
    // Stub: "Pause local AI while playing" is only remembered for now (see EVE_WIRING.md,
    // "Game launcher → Pause local AI"); nothing is paused yet.
    function setPauseAi(on) { pauseAi = on; saveState(); }

    // ---- emulators (the launcher's "Add a game or emulator" / "Emulator settings") ----
    readonly property string emuFile: Quickshell.env("HOME") + "/.config/Tide/emulators.json"
    property var emulators: []
    FileView {
        id: ef
        path: root.emuFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.emulators = JSON.parse(text()) || []; } catch (e) { root.emulators = []; } }
    }
    function saveEmulators(list) { emulators = list; ef.setText(JSON.stringify(list, null, 2) + "\n"); refreshSoon.restart(); }
    Timer { id: refreshSoon; interval: 300; onTriggered: root.refresh() }
    // the known ones (games.py emulators): platform, arguments, copies found, folders it suggests
    property var known: ({ platforms: {}, emulators: [] })
    function loadKnown() { if (!knownProc.running) knownProc.running = true; }
    Process {
        id: knownProc
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/games.py", "emulators"]
        stdout: StdioCollector { onStreamFinished: { try { root.known = JSON.parse(text); } catch (e) {} } }
    }

    // a file or folder picker (zenity); the launcher steps aside while it's open
    property bool picking: false
    property var pickDone: null
    function pick(folder, title, done) {
        if (picker.running) return;
        pickDone = done; picking = true;
        picker.command = ["zenity", "--file-selection", "--title=" + title].concat(folder ? ["--directory"] : []);
        picker.running = true;
    }
    Process {
        id: picker
        stdout: StdioCollector {
            onStreamFinished: {
                root.picking = false;
                const p = text.trim();
                if (p && root.pickDone) root.pickDone(p);
                root.pickDone = null;
            }
        }
    }

    // ---- running games ----
    property var runningIds: []              // Steam appids
    function isRunning(g) { return !!g && (g.platform === "steam" ? runningIds.indexOf(g.appid) >= 0 : !!emuRun && emuRun.id === g.id); }
    Process {
        id: runCheck
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/games.py", "running"]
        stdout: StdioCollector { onStreamFinished: { try { root.runningIds = JSON.parse(text); } catch (e) {} root.stepCheck(); } }
    }
    // an emulator game: still going? (its pid)
    Process {
        id: emuAlive
        onExited: code => {
            if (code === 0 || !root.emuRun) return;
            // it ended: add the time
            const r = root.emuRun, p = Object.assign({}, root.played);
            p[r.id] = { last: Math.floor(r.start / 1000), minutes: ((p[r.id] || {}).minutes || 0) + (Date.now() - r.start) / 60000 };
            root.played = p; root.emuRun = null; root.saveState();
        }
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: root.open || root.launching !== null || root.emuRun !== null
        onTriggered: {
            if (!runCheck.running) runCheck.running = true;
            if (root.emuRun && !emuAlive.running) { emuAlive.command = ["kill", "-0", String(root.emuRun.pid)]; emuAlive.running = true; }
        }
    }

    // ---- launching ----
    property var launching: null
    property int step: -1                    // 0 starting (Steam / the emulator), 1 getting ready, 2 launching
    property real stepAt: 0
    property bool gameUp: false              // the game's window is showing
    property string launchError: ""
    function emulatorOf(g) { return emulators.find(e => e.id === g.emulator) || null; }
    function launch(g) {
        if (!g) return;
        if (g.installed === false) { if (!downloading(g)) askInstall(g); return; }
        if (isRunning(g)) { resume(g); return; }
        launching = g; launchError = ""; stepAt = Date.now(); gameUp = false;
        if (g.platform === "steam") {
            step = steamRunning ? 1 : 0;
            Quickshell.execDetached(["steam", "-silent", "steam://rungameid/" + g.appid]);
            return;
        }
        const q = s => "'" + s.replace(/'/g, "'\\''") + "'";
        if (g.command) {
            step = 0;
            emuStart.command = ["sh", "-c", "setsid sh -c " + q("exec " + g.command.map(q).join(" ")) + " >/dev/null 2>&1 & echo $!"];
            emuStart.running = true;
            return;
        }
        const e = emulatorOf(g);
        if (!e || !e.program) { launchError = "Set up " + (g.emuName || "the emulator") + " first (Emulator settings)."; step = 0; return; }
        step = 0;
        // {rom} becomes the game's path, quoted; the program can be a command ("flatpak run …")
        const args = (e.args || "{rom}").replace(/\{rom\}/g, q(g.path));
        const prog = e.program.startsWith("flatpak run ") ? e.program : q(e.program.replace(/^~/, Quickshell.env("HOME")));
        emuStart.command = ["sh", "-c", "setsid sh -c " + q("exec " + prog + " " + args) + " >/dev/null 2>&1 & echo $!"];
        emuStart.running = true;
    }
    Process {
        id: emuStart
        stdout: StdioCollector {
            onStreamFinished: {
                const pid = parseInt(text.trim());
                if (!pid || !root.launching) return;
                root.emuRun = { id: root.launching.id, pid: pid, start: Date.now() };
                root.saveState();
            }
        }
    }
    Process {
        id: windowCheck
        // "<address> <fullscreen>" once the game has a window
        stdout: StdioCollector {
            onStreamFinished: {
                const w = text.trim().split(" ");
                if (w[0] === "no" || !w[0] || !root.launching || root.gameUp) return;
                root.gameUp = true; root.step = 2; root.stepAt = Date.now();
            }
        }
    }
    function stepCheck() {
        if (!launching || launchError) return;
        if (launching.platform === "steam") {
            if (step === 0) stepperSteam.running = true;
            else if (runningIds.indexOf(launching.appid) >= 0 && step < 2) { step = 2; stepAt = Date.now(); }
            // the game's process is up; stay until its window shows (Proton games take a while)
            if (step === 2 && !gameUp && Date.now() - stepAt > 60000) gameUp = true;   // no window we can see: don't hold the screen
            if (step === 2 && !gameUp && !windowCheck.running) { windowCheck.command = ["python3", "-I", Quickshell.shellDir + "/scripts/games.py", "window", "steam", launching.appid]; windowCheck.running = true; }
        } else if (launching.platform === "lutris") {
            // Lutris starts the game from its own process: follow the steps on time
            if (step < 2 && Date.now() - stepAt > 1500) { step++; stepAt = Date.now(); }
        } else {
            if (step === 0 && Date.now() - stepAt > 1200) { step = 1; stepAt = Date.now(); }
            if (step === 1 && emuRun && !windowCheck.running) { windowCheck.command = ["python3", "-I", Quickshell.shellDir + "/scripts/games.py", "window", String(emuRun.pid)]; windowCheck.running = true; }
            if (step >= 0 && !emuRun && Date.now() - stepAt > 6000) launchError = launching.title + " didn't start. Check the emulator's program in Emulator settings.";
        }
        if (step === 2 && (gameUp || launching.platform === "lutris") && Date.now() - stepAt > (gameUp ? 500 : 1500)) { launching = null; step = -1; open = false; }   // the game is up
        if (launching && Date.now() - stepAt > 120000) launchError = (launching.platform === "steam" ? "Steam" : "The emulator") + " is taking a while.";
    }
    Process {
        id: stepperSteam
        command: ["pgrep", "-x", "steam"]
        onExited: code => { if (code === 0 && root.step === 0) { root.steamRunning = true; root.step = 1; root.stepAt = Date.now(); } }
    }
    // "Emulator settings": the emulator's own app, opened normally (no game)
    function openEmulator(e) {
        if (!e || !e.program) return;
        open = false;
        Quickshell.execDetached(e.program.startsWith("flatpak run ") ? ["sh", "-c", e.program] : [e.program.replace(/^~/, Quickshell.env("HOME"))]);
    }
    function cancelLaunch() { launching = null; step = -1; launchError = ""; }
    function resume(g) {
        open = false;
        const target = g.platform === "steam" ? "class:^steam_app_" + g.appid + "$" : "pid:" + (emuRun ? emuRun.pid : 0);
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"" + target + "\" })"]);
    }

    // ---- art from SteamGridDB (scripts/artdb.py): right-click a game → Choose art ----
    readonly property string artTool: Quickshell.shellDir + "/scripts/artdb.py"
    property bool artKey: false
    Process { id: artKeyCheck; running: true; command: ["python3", "-I", root.artTool, "has-key"]; stdout: StdioCollector { onStreamFinished: root.artKey = text.trim() === "true" } }
    // the key goes to artdb.py on standard input (never in a command line)
    function saveArtKey(k) { artKeyProc.pending = k; artKeyProc.running = true; }
    Process {
        id: artKeyProc
        property string pending: ""
        command: ["python3", "-I", root.artTool, "set-key"]
        stdinEnabled: true
        onStarted: { write(pending + "\n"); pending = ""; }
        onExited: artKeyCheck.running = true
    }
    property var artGame: null              // the game whose art is being chosen
    property string artKind: "cover"        // cover | hero
    property var artChoices: []
    property string artMatch: ""            // the game SteamGridDB found for the name
    // adult art (SteamGridDB's NSFW): off unless turned on in Settings → Games
    property bool artAdult: false
    function setArtAdult(on) { artAdult = on; saveState(); }
    property bool artBusy: false
    property string artError: ""
    // what SteamGridDB is searched for: the game's name, or what you typed in the picker
    // (the game keeps its own name; a typed search skips the Steam id match)
    property string artSearch: ""
    function chooseArt(g, kind, search) {
        if (g !== artGame) artSearch = "";
        if (search !== undefined) artSearch = search.trim() === g.title ? "" : search.trim();
        artGame = g; artKind = kind || "cover"; artChoices = []; artMatch = ""; artError = ""; artBusy = true;
        artFind.command = ["python3", "-I", artTool, "find", artKind, artSearch || g.title,
            g.platform === "steam" && !artSearch ? String(g.appid || "") : "", artAdult ? "1" : "0"];
        artFind.running = true;
    }
    Process {
        id: artFind
        stdout: StdioCollector {
            onStreamFinished: {
                root.artBusy = false;
                let d; try { d = JSON.parse(text); } catch (e) { root.artError = "SteamGridDB didn't answer"; return; }
                if (d.error) { root.artError = d.error; return; }
                root.artChoices = d.items || [];
                root.artMatch = d.match || "";
                if (!root.artChoices.length) root.artError = "No " + (root.artKind === "cover" ? "covers" : "banners") + " for this game yet";
            }
        }
    }
    function pickArt(url) {
        if (!artGame || artSet.running) return;
        artBusy = true;
        artSet.command = ["python3", "-I", artTool, "set", artGame.id, artKind, url];
        artSet.running = true;
    }
    function resetArt() {
        if (!artGame || artSet.running) return;
        artSet.command = ["python3", "-I", artTool, "reset", artGame.id];
        artSet.running = true;
    }
    Process {
        id: artSet
        stdout: StdioCollector {
            onStreamFinished: {
                root.artBusy = false;
                let d; try { d = JSON.parse(text); } catch (e) { d = { error: "Couldn't save it" }; }
                if (d.error) { root.artError = d.error; return; }
                root.artGame = null;
                root.refresh();
            }
        }
    }

    // ---- Steam installs (bin/tide-steam: Steam's own install, no Steam window) ----
    readonly property string steamTool: Quickshell.env("HOME") + "/.config/Tide/bin/tide-steam"
    readonly property var steamArgs: [steamTool, "--state", Quickshell.env("HOME") + "/.local/state/tide/steam"]
    // Install asks first: Steam's size for it and the free space (a dry run), then the real one
    property var installAsk: null           // { game, bytes, free, licences: [] }
    property string installError: ""
    function askInstall(g) {
        if (!g || installProc.running) return;
        installAsk = { game: g, bytes: -1, free: -1, licences: [] }; installError = "";
        installProc.dry = true;
        installProc.command = steamArgs.concat(["install", g.appid, "--dry-run"]);
        installProc.running = true;
    }
    function confirmInstall(acceptLicences) {
        if (!installAsk || installProc.running) return;
        installProc.dry = false;
        installProc.command = steamArgs.concat(["install", installAsk.game.appid]).concat(acceptLicences ? ["--accept-licences"] : []);
        installProc.running = true;
    }
    function cancelAsk() { installRetry.stop(); installAsk = null; installError = ""; }
    // Steam starting: the same question again (the size first, or the install itself)
    Timer { id: installRetry; interval: 3000; onTriggered: if (root.installAsk && !installProc.running) installProc.running = true }
    Process {
        id: installProc
        property bool dry: true
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { root.installError = "Steam didn't answer"; return; }
                if (d.error) {
                    // Steam isn't running (or is still starting): start it, quietly, and ask
                    // again every 3 s for up to two minutes, then carry on by itself
                    if (["not-running", "not-ready", "timeout", "connection-failed"].indexOf(d.error.code) >= 0 && root.installAsk
                            && (root.installAsk.startedSteam || 0) < 40) {
                        if (!root.installAsk.startedSteam) Quickshell.execDetached(["steam", "-silent"]);
                        root.installAsk = Object.assign({}, root.installAsk, { startedSteam: (root.installAsk.startedSteam || 0) + 1 });
                        root.installError = "";
                        installRetry.restart();
                        return;
                    }
                    root.installError = d.error.code === "licence-required" ? "" : d.error.message;
                    if (d.error.code === "licence-required" && root.installAsk)
                        root.installAsk = Object.assign({}, root.installAsk, { licences: d.error.licences || [] });
                    return;
                }
                if (installProc.dry) { root.installAsk = Object.assign({}, root.installAsk, { bytes: d.bytes_needed, free: d.bytes_free, startedSteam: 0 }); return; }
                // started: follow it in the download queue
                const g = root.installAsk.game;
                root.installing = Object.assign({}, root.installing, { [g.appid]: { title: g.title, percent: 0, done: 0, total: d.bytes_needed || 0, state: "Starting" } });
                root.steamQuiet();
                root.installAsk = null;
            }
        }
    }
    // appid -> { title, percent, done, total, state } while it downloads
    property var installing: ({})
    function downloading(g) { return !!g && g.appid && installing[g.appid] !== undefined; }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: Object.keys(root.installing).length > 0
        onTriggered: if (!dl.running) dl.running = true
    }
    Process {
        id: dl
        command: root.steamArgs.concat(["downloads"])
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { return; }
                if (d.error) return;
                const now = Object.assign({}, root.installing);
                root.steamQuiet();
                for (const id of Object.keys(now)) {
                    const it = (d.items || []).find(x => String(x.appid) === id);
                    if (!it || it.completed) {
                        // gone from the queue: done (or cancelled from Steam)
                        Quickshell.execDetached(["notify-send", "-a", "Tide", now[id].title + " is installed", "Ready to play in the game launcher"]);
                        delete now[id];
                        root.refreshSoonInstalled.restart();
                        continue;
                    }
                    const active = String(d.appid) === id;
                    now[id] = Object.assign({}, now[id], { percent: active ? d.percent : now[id].percent, done: it.bytes_done, total: it.bytes_total, state: active ? d.state : (it.paused ? "Paused" : "Queued") });
                }
                root.installing = now;
            }
        }
    }
    // Steam's own pop-ups ("notificationtoasts_N_desktop" windows, not notifications) for
    // what Tide is doing and already tells you: while Tide installs or removes a game and
    // a minute after, they're moved out of sight (Settings → Notifications). Steam uses the
    // same window for friend messages, so outside that time they show; muting Steam there
    // hides them all.
    property real steamQuietUntil: 0
    function steamQuiet() { steamQuietUntil = Date.now() + 60000; }
    function hideSteamToast(address, title) {
        if (!/^notificationtoasts_/.test(title)) return;
        const tide = Notifications.steamTideNotices && (Object.keys(installing).length > 0 || Date.now() < steamQuietUntil);
        if (!tide && !Notifications.isMuted("Steam")) return;
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ workspace = \"special:tide-hidden\", window = \"address:0x" + address + "\", follow = false })"]);
    }
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (e.name === "openwindow") { const p = e.data.split(","); if (p[2] === "steam") root.hideSteamToast(p[0], p.slice(3).join(",")); }
            else if (e.name === "windowtitlev2") { const p = e.data.split(","); root.hideSteamToast(p[0], p.slice(1).join(",")); }
        }
    }
    property Timer refreshSoonInstalled: Timer { interval: 1500; onTriggered: root.refresh() }
    // Cancel while downloading, and Uninstall (both remove the game; the launcher asks first)
    function cancelInstall(g) {
        if (!g) return;
        Quickshell.execDetached(steamArgs.concat(["uninstall", g.appid]));
        steamQuiet();
        const now = Object.assign({}, installing); delete now[g.appid]; installing = now;
        refreshSoonInstalled.restart();
    }
    function uninstall(g) {
        if (!g || g.platform !== "steam") return;
        Quickshell.execDetached(steamArgs.concat(["uninstall", g.appid]));
        steamQuiet();
        Quickshell.execDetached(["notify-send", "-a", "Tide", "Removing " + g.title, "It stays in your library to install again"]);
        uninstallLater.restart();
    }
    property Timer uninstallLater: Timer { interval: 4000; onTriggered: root.refresh() }
    function gb(b) { return b >= 1e9 ? (b / 1e9).toFixed(1) + " GB" : Math.max(1, Math.round(b / 1e6)) + " MB"; }

    // ---- a controller, while the launcher is open ----
    property string pad: ""                  // its name, "" when none
    signal padPressed(string word)
    Process {
        running: root.open
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/gamepad.py"]
        onRunningChanged: if (!running) root.pad = ""
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("present ")) root.pad = line.slice(8);
                else if (line === "none") root.pad = "";
                else root.padPressed(line);
            }
        }
    }

    // the Guide / Home / PS button opens the launcher from anywhere (held 1 s over a
    // fullscreen game, so the game keeps a quick press)
    Process {
        running: true
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/gamepad.py", "guide"]
        stdout: SplitParser { onRead: line => { if (line === "guide") root.toggle(); } }
    }

    GlobalShortcut {
        appid: "tide"
        name: "games"
        description: "Open the game launcher"
        onPressed: root.toggle()
    }
    IpcHandler {
        target: "games"
        function toggle(): void { root.toggle(); }
        function state(): string { return JSON.stringify({ open: root.open, games: root.games.map(g => g.title + " [" + g.platform + "]"), running: root.runningIds, emuRun: root.emuRun, launching: root.launching ? root.launching.title : "", step: root.step, error: root.launchError, pad: root.pad, emulators: root.emulators.map(e => e.name) }); }
        function pad(word: string): void { root.padPressed(word); }
        function owned(): string { return JSON.stringify({ total: root.raw.length, notInstalled: root.raw.filter(g => g.installed === false).length, note: root.steamNote }); }
    }
}
