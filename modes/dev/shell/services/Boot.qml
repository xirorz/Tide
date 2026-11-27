pragma Singleton
import QtQuick
import Quickshell

// Startup order: the bar is built and drawn first. Everything you only see when you open
// it (the island's tools, the control center, the updates panel, Settings) is built in
// the background right after the bar is on screen ("settled"), or at once if you open
// it before then. Times go to ~/.local/state/tide/boot.log; bin/tide-boot-report reads it.
Singleton {
    id: root
    readonly property real t0: Date.now()
    property bool barShown: false
    property bool settled: false

    property var pending: []
    function mark(what) {
        pending = pending.concat([what + " " + (Date.now() / 1000).toFixed(3)]);
        console.info("tide-boot:", what, "+" + (Date.now() - t0) + "ms");
        flush.restart();
    }
    Timer {
        id: flush
        interval: 300
        onTriggered: {
            const lines = root.pending.join("\n");
            root.pending = [];
            Quickshell.execDetached(["sh", "-c", 'f="$HOME/.local/state/tide/boot.log"; mkdir -p "${f%/*}"; printf "%s\\n" "$1" >> "$f"; tail -n 300 "$f" > "$f.tmp" && mv "$f.tmp" "$f"', "sh", lines]);
        }
    }

    // the bar's first frame (ShellWindow)
    function shown() {
        if (barShown) return;
        barShown = true;
        mark("bar-drawn");
        settle.start();
    }
    // a moment for the compositor to put the bar up, then the rest
    Timer { id: settle; interval: 250; onTriggered: { root.settled = true; root.mark("background-start"); } }
    // a few seconds later, anything still building in the background is finished at
    // once (in case background building stalls)
    property bool finishNow: false
    Timer { running: root.settled; interval: 4000; onTriggered: root.finishNow = true }
    // never hold the rest back if the frame signal doesn't come
    Timer { interval: 3000; running: true; onTriggered: if (!root.settled) { root.settled = true; root.mark("background-start-fallback"); } }

    // each part built in the background reports here; the last one marks the end
    property int built: 0
    function ready(name) {
        built++;
        doneTimer.restart();
    }
    Timer { id: doneTimer; interval: 600; onTriggered: root.mark("background-done " + root.built + "-parts") }

    Component.onCompleted: mark("--- shell-start")
}
