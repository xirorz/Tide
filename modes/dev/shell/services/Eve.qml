pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import ".."

// Eve live mode: everything the island shows, as plain state. Nothing in here talks
// to Eve itself; whatever drives Eve sets this state over IPC (see EVE_WIRING.md)
// and hears the user's buttons through the hook commands in theme.json "eveHooks".
// Until something is wired, "eveDemo": true plays the design's preview loop.
Singleton {
    id: root

    property bool active: false
    // listening | thinking | working | speaking
    property string stage: "listening"
    property bool muted: false
    property string chatTitle: ""          // the chat a call is in, when the assistant says
    // the line under the header; while `typing` it is revealed letter by letter
    property string caption: ""
    property bool typing: false
    property real typeSpeed: 0.5          // letters per 45ms tick (the design's pace)
    property real shown: 0                // letters of `caption` revealed so far
    readonly property string visibleCaption: typing ? caption.slice(0, Math.floor(shown)) : caption
    // working: [{ text, icon, done, active }] and [{ t, c }] terminal lines
    property var steps: []
    property var term: []

    readonly property var hooks: Theme.opt("eveHooks", ({}))
    readonly property bool demo: Theme.opt("eveDemo", true)
    function hook(name) {
        const cmd = hooks[name];
        if (cmd) Quickshell.execDetached(["sh", "-c", cmd, "eve-hook", muted ? "muted" : "unmuted"]);
    }

    // ---- driven by Eve (IPC) or the demo ----
    // manual: started by you (launcher row, tide:eve). Started from outside (IPC)
    // while you have a tool open, she waits underneath and shows when you close it.
    function start(manual) {
        if (!Theme.aiEnabled || !Session.useTool("eve")) return;
        active = true;
        muted = false;
        setStage("listening");
        if (manual || !IslandState.isTool(IslandState.mode)) IslandState.open("eve", "");
        // A connected assistant that takes calls (Settings → AI) runs it; otherwise the hooks or the demo do.
        if (manual && EveData.startCall()) { say("", false); return; }
        hook("start");
        if (demo && !hooks.start) demoRun.start();
    }
    function end() {
        demoRun.stop();
        EveData.endCall();
        active = false;
        steps = [];
        term = [];
        caption = "";
        chatTitle = "";
        // active is already false, so the island rests on the clock again
        if (IslandState.mode === "eve") IslandState.close();
        hook("end");
    }
    function setStage(s) {
        stage = s;
        if (s !== "working") { steps = []; term = []; }
    }
    // show text; typed = reveal it at the design's pace (listening 0.5, speaking 0.75)
    function say(text, typed) {
        caption = text;
        shown = 0;
        typeSpeed = stage === "speaking" ? 0.75 : 0.5;
        typing = typed;
    }
    function addStep(text, icon) {
        const s = steps.map(x => Object.assign({}, x, { done: true, active: false }));
        s.push({ text: text, icon: icon || "terminal", done: false, active: true });
        steps = s;
    }
    function finishSteps() { steps = steps.map(x => Object.assign({}, x, { done: true, active: false })); }
    function addTerm(line, kind) {
        // kind: "cmd" (light), "out" (muted), "ok" (accent)
        term = term.concat([{ t: line, c: kind || "out" }]);
    }

    // ---- the user's buttons ----
    function toggleMute() { muted = !muted; if (EveData.calling) EveData.muteCall(muted); else hook("mute"); }
    // type instead: the call ends and the AI panel opens with its message box
    function typeInstead() { if (EveData.calling) { end(); EveData.open = true; } else hook("type"); }

    Timer {
        interval: 45; repeat: true
        running: root.typing && root.active
        onTriggered: {
            root.shown += root.typeSpeed;
            if (root.shown >= root.caption.length) root.typing = false;
        }
    }

    // qs -p <shell dir> ipc call eve <function> ...
    IpcHandler {
        target: "eve"
        function start(): void { root.start(); }
        function end(): void { root.end(); }
        function stage(s: string): void { root.setStage(s); }
        function say(text: string): void { root.say(text, false); }
        function sayTyped(text: string): void { root.say(text, true); }
        function step(text: string, icon: string): void { root.addStep(text, icon); }
        function stepsDone(): void { root.finishSteps(); }
        function term(line: string, kind: string): void { root.addTerm(line, kind); }
        function mute(on: bool): void { root.muted = on; }
        function status(): string { return JSON.stringify({ active: root.active, stage: root.stage, muted: root.muted }); }
    }
    GlobalShortcut {
        appid: "tide"
        name: "eve"
        description: "Talk to Eve (live mode)"
        onPressed: if (Theme.aiEnabled) root.active ? root.end() : root.start(true)
    }

    // Settings → AI off: Eve leaves the island
    Connections { target: Theme; function onAiEnabledChanged() { if (!Theme.aiEnabled && root.active) root.end(); } }

    // ---- the design's preview loop (eveDemo) ----
    SequentialAnimation {
        id: demoRun
        loops: Animation.Infinite
        ScriptAction { script: { root.setStage("listening"); root.say("Eve, is the barbershop site up? And find out why the printer stopped last night.", true); } }
        PauseAnimation { duration: 3600 }
        ScriptAction { script: { root.setStage("thinking"); root.say(root.caption, false); } }
        PauseAnimation { duration: 1800 }
        ScriptAction { script: { root.setStage("working"); root.say("Checking the site and the printer for you.", false); root.addStep("Opened her terminal", "terminal"); } }
        PauseAnimation { duration: 180 }
        ScriptAction { script: root.addTerm("$ docker ps --filter name=barbershop", "cmd") }
        PauseAnimation { duration: 630 }
        ScriptAction { script: root.addTerm("barbershop-web   Up 41 days (healthy)", "out") }
        PauseAnimation { duration: 315 }
        ScriptAction { script: root.addStep("Checked containers: barbershop-web is healthy", "containers") }
        PauseAnimation { duration: 225 }
        ScriptAction { script: root.addTerm("$ curl -sI [site address] | head -1", "cmd") }
        PauseAnimation { duration: 540 }
        ScriptAction { script: root.addTerm("HTTP/2 200", "ok") }
        PauseAnimation { duration: 585 }
        ScriptAction { script: root.addStep("Opened her browser: printer history", "browser") }
        PauseAnimation { duration: 315 }
        ScriptAction { script: root.addTerm("$ printer-log --since yesterday", "cmd") }
        PauseAnimation { duration: 810 }
        ScriptAction { script: root.addTerm("02:14 paused: filament runout (slot 2)", "ok") }
        PauseAnimation { duration: 225 }
        ScriptAction { script: root.addStep("Reading the print log", "log") }
        PauseAnimation { duration: 900 }
        ScriptAction { script: root.finishSteps() }
        PauseAnimation { duration: 1050 }
        ScriptAction { script: { root.setStage("speaking"); root.say("The site is up and healthy. The printer paused at 2:14 AM because slot 2 ran out of filament. Want a reminder to reload it?", true); } }
        PauseAnimation { duration: 4800 }
    }
}
