pragma Singleton
import QtQuick
import Quickshell
import ".."

// Screenshot, record, OCR, color picker, timer and the two folders, shared by the
// control center and the island's capture state. Whoever calls these closes itself
// first; the capture starts 200ms later so the shell isn't in the shot.
Singleton {
    id: root
    readonly property string captureScripts: Quickshell.shellDir + "/scripts/capture/"
    readonly property string tideScripts: Quickshell.shellDir + "/scripts/"

    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }
    function later(cmd) { pending.cmd = cmd; pending.restart(); }
    Timer {
        id: pending
        property string cmd: ""
        interval: 200
        onTriggered: root.run(cmd)
    }

    // scripts/capture/ (Tide's copies of the screenshot, OCR, picker and timer scripts; run through bash)
    // screenshot.sh: s = region, w = window, p = screen
    function screenshot(kind) { later("bash " + captureScripts + "screenshot.sh " + ({ region: "s", window: "w", screen: "p" })[kind]); }
    // a recording runs until stopped; pressing record while one runs stops it
    function record(kind) {
        if (Recording.active) { Recording.stop(); return; }
        const extra = kind === "screen" ? " " + (Theme.monitor || "screen") : "";
        later("\"" + tideScripts + "record.sh\" " + kind + extra);
    }
    function ocr() { later("bash " + captureScripts + "ocr.sh"); }
    function colorPicker() { later("bash " + captureScripts + "hyprpicker.sh -hex"); }
    function timer() { run("bash " + captureScripts + "pomodoro.sh"); }
    function openScreenshots() { run("xdg-open \"${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots\""); }
    function openRecordings() { run("xdg-open \"${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings\""); }
}
