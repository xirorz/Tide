pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Voice dictation in the island (obs-voice / whisper-paste). scripts/voice.sh wraps
// the user's scripts unchanged and reports each moment here over IPC:
//   qs -p <shell dir> ipc call voice start | stop | transcribing | done | cancel | error
// state: idle | recording | transcribing | done | error
Singleton {
    id: root
    property string state: "idle"
    property string tool: ""          // obs-voice | whisper-paste (who is recording)
    property int seconds: 0
    readonly property string time: Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
    // live mic level while recording: 5 values 0..1, one per bar
    // (scripts/miclevel.py, its own tiny capture)
    property var levels: [0, 0, 0, 0, 0]
    readonly property real level: Math.max.apply(null, levels)

    // what the finished state says: whisper-paste copies the transcript,
    // obs-voice writes a note
    readonly property string doneText: tool === "obs-voice" ? "Saved to notes" : "Copied to clipboard"

    function start(t) { tool = t || tool; seconds = 0; state = "recording"; }
    function transcribing() { state = "transcribing"; }
    function done() { state = "done"; settle.restart(); }
    function error() { state = "error"; settle.restart(); }
    function cancel() { state = "idle"; }
    // the pill's stop button: like pressing the key again, but it can only stop
    function stop() {
        if (state !== "recording") return;
        Quickshell.execDetached(["bash", Quickshell.shellDir + "/scripts/voice.sh", tool || "whisper-paste", "stop"]);
    }

    Timer { interval: 1000; repeat: true; running: root.state === "recording"; onTriggered: root.seconds++ }
    // "Copied to clipboard" (or the error) shows for 2s, then back to the clock
    Timer { id: settle; interval: 2000; onTriggered: if (root.state === "done" || root.state === "error") root.state = "idle" }

    Process {
        running: root.state === "recording"
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/miclevel.py"]
        stdout: SplitParser { onRead: line => root.levels = line.split(",").map(x => parseFloat(x) || 0) }
        onRunningChanged: if (!running) root.levels = [0, 0, 0, 0, 0]
    }

    IpcHandler {
        target: "voice"
        function start(tool: string): void { root.start(tool); }
        function stop(): void { root.transcribing(); }
        function transcribing(): void { root.transcribing(); }
        // stopping a recording, and whose it is ("Saved to notes" or "Copied to clipboard")
        function stopping(tool: string): void { root.tool = tool; root.transcribing(); }
        function done(): void { root.done(); }
        function cancel(): void { root.cancel(); }
        function error(): void { root.error(); }
        function status(): string { return JSON.stringify({ state: root.state, tool: root.tool, seconds: root.seconds, level: root.level }); }
    }
}
