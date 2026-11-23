pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The modes (the island calls them themes) from the mode manager, ~/.config/Tide/bin/tide-mode:
// one folder per mode in ~/.config/Tide/modes with a mode.json. Applying one runs
// tide-mode, which swaps the Hyprland config and the shell (switching away from Dev
// and its saved themes stops this shell).
Singleton {
    id: root
    readonly property string tool: Quickshell.env("HOME") + "/.config/Tide/bin/tide-mode"
    property var list: []
    readonly property string active: (list.find(m => m.active) || { id: "dev" }).id

    function refresh() { if (!lister.running) lister.running = true; }
    // what went wrong last (a locked-in session, a config that doesn't load)
    property string error: ""
    function apply(id) {
        if (id === active || runner.running) return;
        error = "";
        runner.command = [tool, id];
        runner.running = true;
    }
    function remove(id) {
        if (runner.running) return;
        error = "";
        runner.command = [tool, "delete", id];
        runner.running = true;
    }
    Process {
        id: runner
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = text.trim().replace(/^tide-mode: /, "") }
        // refused while locked in (from the island picker too): say so
        onExited: code => {
            root.refresh();
            if (code === 2) Quickshell.execDetached(["notify-send", "-a", "Tide", "Locked in", root.error || "This theme is locked in until time is up"]);
        }
    }

    Process {
        id: lister
        running: true
        command: [root.tool, "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.list = JSON.parse(text); } catch (e) {}
            }
        }
    }
    // themes saved or edited outside Settings (a terminal) show up within 5 minutes, so
    // their schedules run
    Timer { interval: 300000; repeat: true; running: true; onTriggered: root.refresh() }
    IpcHandler {
        target: "modes"
        function refresh(): void { root.refresh(); }
        function list(): string { return JSON.stringify(root.list.map(m => m.id)); }
    }
    // the active mode can change from a terminal too
    FileView {
        path: Quickshell.env("HOME") + "/.config/Tide/mode"
        watchChanges: true
        printErrors: false
        onFileChanged: root.refresh()
    }
}
