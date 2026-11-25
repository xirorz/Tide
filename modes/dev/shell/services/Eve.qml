pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import ".."

// Live mode in the island: everything it shows, as plain state. A connected assistant that
// takes calls (Settings → AI) drives it through services/EveData.qml; scripts can still set it
// over IPC (see EVE_WIRING.md). Without calls, starting it opens the AI panel instead.
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


    // ---- driven by the connected assistant (EveData) or by scripts over IPC ----
    // manual: started by you (launcher row, tide:eve). Started from outside (IPC)
    // while you have a tool open, she waits underneath and shows when you close it.
    function start(manual) {
        if (!Theme.aiEnabled) return;
        // You started it: a live call with the connected assistant, or, when it doesn't take calls, the AI panel.
        if (manual && !EveData.canCall) { EveData.open = true; return; }
        if (!Session.useTool("eve")) return;
        active = true;
        muted = false;
        setStage("listening");
        if (manual || !IslandState.isTool(IslandState.mode)) IslandState.open("eve", "");
        if (manual && EveData.startCall()) say("", false);
    }
    function end() {
        EveData.endCall();
        active = false;
        steps = [];
        term = [];
        caption = "";
        chatTitle = "";
        // active is already false, so the island rests on the clock again
        if (IslandState.mode === "eve") IslandState.close();
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
    function toggleMute() { muted = !muted; EveData.muteCall(muted); }
    // type instead: the call ends and the AI panel opens with its message box
    function typeInstead() { end(); EveData.open = true; }

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
        description: "Talk to the AI (live mode)"
        onPressed: if (Theme.aiEnabled) root.active ? root.end() : root.start(true)
    }

    // Settings → AI off: Eve leaves the island
    Connections { target: Theme; function onAiEnabledChanged() { if (!Theme.aiEnabled && root.active) root.end(); } }
}
