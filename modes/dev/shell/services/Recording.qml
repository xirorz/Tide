pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// While a recording runs the island shows a red dot and the elapsed time.
// Your recorder (or the capture tool, later) calls:
//   qs -p <shell dir> ipc call recording start
//   qs -p <shell dir> ipc call recording stopped    (recorder ended by itself)
// Clicking the island runs recordStopCommand from theme.json.
Singleton {
    id: root
    property bool active: false
    property int seconds: 0
    readonly property string time: String(Math.floor(seconds / 60)).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0")

    function start() { seconds = 0; active = true; }
    function stop() {
        if (!active) return;
        active = false;
        Quickshell.execDetached(["sh", "-c", Theme.recordStopCommand]);
    }

    Timer { interval: 1000; repeat: true; running: root.active; onTriggered: root.seconds++ }

    IpcHandler {
        target: "recording"
        function start(): void { root.start(); }
        function stop(): void { root.stop(); }
        function stopped(): void { root.active = false; }
    }
}
