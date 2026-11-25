pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

// Idle and lock (Settings → Apps and Hyprland, and the control center's Stay awake).
// hypridle does the timing (~/.config/hypr/hypridle.conf, written by
// scripts/hypridle.py) and runs as its systemd user unit; this keeps it running (a
// Hyprland crash takes it down), dims the screens itself when hypridle says so (the
// monitors have no backlight to dim), and says what's holding idle off.
// Keep-awake rules: hypridle ignores apps' systemd and Wayland keep-awake requests and
// asks Tide before each step (scripts/idle-step.sh → step()). A step waits while Stay
// awake is on, a game or fullscreen video is showing (theme.json "idleKeepGames",
// default on), or an app that isn't on the ignore list ("idleIgnore": [{name, cls}])
// is asking (scripts/idle-blockers.py); it runs once that's over if you're still away.
// Stay awake is kept across Tide restarts (~/.local/state/tide/stay-awake).
Singleton {
    id: root
    readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/tide/stay-awake"
    property bool awake: false
    property bool awakeLoaded: false
    onAwakeChanged: if (awakeLoaded) awakeFile.setText(awake ? "1\n" : "0\n")
    FileView {
        id: awakeFile
        path: root.stateFile
        printErrors: false
        onLoaded: { root.awake = text().trim() === "1"; root.awakeLoaded = true; }
        onLoadFailed: root.awakeLoaded = true
    }

    // ---- the keep-awake rules ----
    readonly property var ignoreList: Theme.opt("idleIgnore", [])
    readonly property bool keepGames: Theme.opt("idleKeepGames", true)
    function setIgnore(l) { Theme.set("idleIgnore", l); }
    function tokens(n, c) {
        const out = [];
        for (const v of [n, c]) if (v) { out.push(v.toLowerCase()); out.push(v.toLowerCase().split(".").pop()); }
        const e = c ? DesktopEntries.heuristicLookup(c) : null;
        if (e) out.push(e.name.toLowerCase());
        return out;
    }
    function ignored(b) {
        const mine = tokens(b.name, b.cls);
        return ignoreList.some(i => tokens(i.name, i.cls).some(x => mine.indexOf(x) >= 0));
    }
    function nameOf(b) {
        if (b.rule === "game") return "a game";
        if (b.rule === "video") return "fullscreen video";
        const e = b.kind === "window" ? DesktopEntries.heuristicLookup(b.cls) : null;
        return e ? e.name : b.name;
    }
    property var raw: []                     // from idle-blockers.py
    readonly property var active: raw.filter(b => b.rule ? keepGames : !ignored(b))
    readonly property var ignoredNow: raw.filter(b => !b.rule && ignored(b))
    function uniq(l) { return l.map(nameOf).filter((n, i, a) => a.indexOf(n) === i); }

    // ---- steps from hypridle ----
    property var pending: []                 // steps waiting for a keep-awake to end
    property bool dryRun: false              // tests: lock / screens off / suspend only log
    readonly property string dryLog: Quickshell.env("HOME") + "/.local/state/tide/idle-dryrun.log"
    function step(s) {
        if (s === "resume") { pending = []; dimmed = false; return; }
        if (pending.indexOf(s) < 0) pending = pending.concat([s]);
        checkBlockers();
    }
    function apply() {
        if (!pending.length) return;
        if (awake || active.length) return;            // still held off; checked again soon
        if (!idleMon.isIdle && !dryRun) { pending = []; return; }  // you came back meanwhile (tests skip this)
        for (const s of ["dim", "lock", "dpms", "suspend"]) {
            if (pending.indexOf(s) < 0) continue;
            if (s === "dim") { dimmed = true; continue; }
            const cmd = s === "lock" ? ["loginctl", "lock-session"] : s === "dpms" ? ["hyprctl", "dispatch", "hl.dsp.dpms({ action = \"off\" })"] : ["systemctl", "suspend"];
            if (dryRun) Quickshell.execDetached(["sh", "-c", "echo \"$(date +%T) " + (s === "lock" ? "LOCK" : s) + " would run here\" >> " + dryLog]);
            else Quickshell.execDetached(cmd);
        }
        pending = [];
    }
    Timer { interval: 15000; repeat: true; running: root.pending.length > 0; onTriggered: root.checkBlockers() }

    // minutes, 0 = never: dim, lock, screens off, suspend
    property var timings: ({ dim: 0, lock: 0, dpms: 0, suspend: 0 })
    property bool running: false
    // true once hypridle.conf has been read: until then the timings above are only
    // placeholders, and Power must not save them as the plugged-in times
    property bool loaded: false
    function read() { reader.running = true; }
    Process {
        id: reader
        running: true
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/hypridle.py", "read"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const d = JSON.parse(text); if (d.timings) { root.timings = d.timings; root.loaded = true; } root.running = d.running; } catch (e) {}
            }
        }
    }
    function set(key, minutes) {
        const t = Object.assign({}, timings);
        t[key] = minutes;
        timings = t;
        writer.command = ["python3", "-I", Quickshell.shellDir + "/scripts/hypridle.py", "write", JSON.stringify(t)];
        writer.running = true;
    }
    Process { id: writer; onExited: root.read() }
    // all four at once (Power: the battery's times, and back)
    function setAll(t) {
        timings = Object.assign({}, t);
        writer.command = ["python3", "-I", Quickshell.shellDir + "/scripts/hypridle.py", "write", JSON.stringify(timings)];
        writer.running = true;
    }
    function start() { starter.running = true; }
    Process { id: starter; command: ["systemctl", "--user", "start", "hypridle.service"]; onExited: again.restart() }
    Timer { id: again; interval: 1500; onTriggered: root.read() }

    // keep hypridle running: a minute after it's found missing, start it again
    Timer {
        interval: 60000; repeat: true; running: true
        onTriggered: { root.read(); if (!root.running) root.start(); }
    }

    // ---- dim: hypridle calls `ipc call idle dim / undim` ----
    property bool dimmed: false
    Variants {
        model: root.dimmed ? Quickshell.screens : []
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "tide-dim"
            color: "transparent"
            mask: Region {}
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0
                NumberAnimation on opacity { to: 0.6; duration: Theme.reduceMotion ? 0 : 1500; easing.type: Easing.InOutQuad }
            }
        }
    }

    // ---- who's asking to stay awake (scripts/idle-blockers.py) ----
    property var blockers: uniq(active)      // Settings: "Idle blocked by …"
    function checkBlockers() { if (!blockCheck.running) blockCheck.running = true; }
    Process {
        id: blockCheck
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/idle-blockers.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.raw = JSON.parse(text); } catch (e) {}
                root.apply();
            }
        }
    }
    // how long you've been away (for "next: dim in 1:40"); counts only while nothing blocks
    property int idleSince: 0
    property int now: 0
    IdleMonitor {
        id: idleMon
        enabled: true
        timeout: 5
        respectInhibitors: false
        onIsIdleChanged: root.idleSince = isIdle ? Math.floor(Date.now() / 1000) - 5 : 0
    }
    // only while Settings shows the status
    property bool watching: false
    Timer {
        interval: 1000; repeat: true; running: root.watching
        triggeredOnStart: true
        onTriggered: { root.now = Math.floor(Date.now() / 1000); if (root.now % 5 === 0 || root.blockers === undefined) root.checkBlockers(); }
    }
    onWatchingChanged: if (watching) { read(); checkBlockers(); }

    IpcHandler {
        target: "idle"
        function dim(): void { root.dimmed = true; }
        function undim(): void { root.dimmed = false; }
        // hypridle (scripts/idle-step.sh): "ok" means Tide takes it from here
        function step(s: string): string { root.step(s); return "ok"; }
        function setDryRun(on: bool): void { root.dryRun = on; }
        function state(): string { return JSON.stringify({ running: root.running, awake: root.awake, dimmed: root.dimmed, blockers: root.blockers, ignoring: root.uniq(root.ignoredNow), pending: root.pending, idle: idleMon.isIdle, dryRun: root.dryRun, timings: root.timings }); }
        function check(): void { root.read(); root.checkBlockers(); }
    }
}
