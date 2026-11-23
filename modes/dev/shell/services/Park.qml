pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Park mode: hold Super+Alt+P (1.5 s) to step away and leave things running. Every
// window goes to a hidden workspace (bin/tide-park), your apps go quiet, Hyprland's
// "tide-park" key map leaves only the combo working, and the screen becomes the kid
// space (park/ParkScreen.qml): the parked screen with a big Play button, his tiles, the
// games, and after an hour of play the sleepy "time's up" screen. Holding the combo
// again brings everything back where it was. Super+Ctrl+Alt+P unparks without the shell.
// His stars and levels live in ~/.local/state/tide/park-kid.json; voice lines come from
// Breeze TTS once and are kept (scripts/park-sound.py).
Singleton {
    id: root

    readonly property string tool: Quickshell.env("HOME") + "/.config/Tide/bin/tide-park"
    readonly property string sound: Quickshell.shellDir + "/scripts/park-sound.py"
    property bool parked: false
    property bool preview: false          // the screens without parking (IPC, for trying them)
    property bool busy: false
    property var apps: []                 // what's still running (the parked badge)
    property int windows: 0
    property real since: 0

    // ---- his side ----
    property string view: "parked"        // parked | home | game | timesup
    property string game: ""              // bubble | letters
    readonly property int playMinutes: 60
    property real playStart: 0            // when Play was first pressed this park
    property real now: Date.now()
    readonly property real playLeft: playStart ? Math.max(0, playMinutes * 60000 - (now - playStart)) : playMinutes * 60000
    property int stars: 0
    property var levels: ({})             // game -> level reached (1..3)

    function say(key) { Quickshell.execDetached(["python3", "-I", sound, "say", key]); }
    function fx(name) { Quickshell.execDetached(["python3", "-I", sound, "fx", name]); }

    function play() {
        if (!playStart) playStart = Date.now();
        if (playLeft <= 0) { view = "timesup"; return; }
        view = "home";
        say("hello");
    }
    function open(g) { game = g; view = "game"; say(g === "bubble" ? "pop" : "letters"); }
    function home() { game = ""; view = "home"; }
    function star(n) { stars += n || 1; saveKid(); }
    function levelUp(g, l) { const v = Object.assign({}, levels); v[g] = Math.max(v[g] || 1, l); levels = v; saveKid(); }

    FileView {
        id: kidFile
        path: Quickshell.env("HOME") + "/.local/state/tide/park-kid.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const d = JSON.parse(text()); root.stars = d.stars || 0; root.levels = d.levels || {}; } catch (e) {} }
    }
    function saveKid() { kidFile.setText(JSON.stringify({ stars: stars, levels: levels }, null, 2)); }

    // ---- park / unpark ----
    function toggle() {
        if (busy) return;
        busy = true;
        act.command = [tool, parked ? "unpark" : "park"];
        act.running = true;
    }
    Process {
        id: act
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                let d = {};
                try { d = JSON.parse(text); } catch (e) { return; }
                root.parked = !!d.parked;
                if (root.parked) {
                    root.view = "parked"; root.game = ""; root.playStart = 0; root.since = Date.now();
                    Quickshell.execDetached(["python3", "-I", root.sound, "prepare"]);   // any line still missing
                }
                statusProc.running = true;
            }
        }
    }
    Process {
        id: statusProc
        command: [root.tool, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    // the shell came back while parked (a reload): stay parked
                    if (d.parked && !root.parked) { root.parked = true; root.view = "parked"; }
                    root.apps = d.apps || []; root.windows = d.windows || 0; root.since = (d.since || 0) * 1000;
                } catch (e) {}
            }
        }
    }
    Component.onCompleted: statusProc.running = true

    // while parked: new app sound stays muted, the clock and his hour tick
    Timer {
        interval: 3000; repeat: true; running: root.parked
        onTriggered: { Quickshell.execDetached([root.tool, "mute"]); statusProc.running = true; }
    }
    Timer {
        interval: 1000; repeat: true; running: root.parked || root.preview
        onTriggered: {
            root.now = Date.now();
            if (root.playStart && root.playLeft <= 0 && root.view !== "timesup") {
                root.view = "timesup"; root.game = "";
                root.fx("chime"); root.say("timesup");
            }
        }
    }

    // ---- the combo: held 1.5 s (a tap does nothing, so a bump can't park or unpark) ----
    readonly property int holdMs: 1500
    property bool holding: false
    property real holdStart: 0
    property real holdProgress: 0
    GlobalShortcut {
        appid: "tide"
        name: "park"
        description: "Park mode (hold)"
        onPressed: { root.holding = true; root.holdStart = Date.now(); root.holdProgress = 0; }
        onReleased: { root.holding = false; root.holdProgress = 0; }
    }
    Timer {
        interval: 16; repeat: true; running: root.holding
        onTriggered: {
            root.holdProgress = Math.min(1, (Date.now() - root.holdStart) / root.holdMs);
            if (root.holdProgress >= 1) { root.holding = false; root.holdProgress = 0; root.toggle(); }
        }
    }

    IpcHandler {
        target: "park"
        function toggle(): void { root.toggle(); }
        function state(): string { return JSON.stringify({ parked: root.parked, view: root.view, game: root.game, stars: root.stars, levels: root.levels, apps: root.apps, playLeftMin: Math.round(root.playLeft / 60000) }); }
        // for trying the screens without waiting (tests)
        function setView(v: string): void { root.view = v; }
        function preview(on: bool): void { root.preview = on; if (on) root.view = "parked"; }
        function openGame(g: string): void { root.open(g); }
    }
}
