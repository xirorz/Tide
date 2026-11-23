pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Drawing tablets and tablet plugins (~/.config/Tide/plugins/*/plugin.json), checked
// every 3 seconds by scripts/tablets.py. A plugin's background daemon runs only while
// its tablet is plugged in, and steps aside while the plugin's own app is open (both
// would grab the tablet).
Singleton {
    id: root
    property var tablets: []           // names Hyprland reports
    property string screen: ""         // the monitor that is a tablet's own screen
    property var plugins: []
    readonly property bool any: tablets.length > 0
    // the plugin whose tablet is connected (the Tablet page shows its page)
    readonly property var active: plugins.find(p => p.connected) || null
    property var opening: ({})         // plugin id → true while its app is starting

    function check() { if (!probe.running) probe.running = true; }
    Process {
        id: probe
        running: true
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/tablets.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { return; }
                // only on change: a new plugins list rebuilds the daemon processes
                if (JSON.stringify(d.tablets) !== JSON.stringify(root.tablets)) root.tablets = d.tablets;
                if (d.screen !== root.screen) root.screen = d.screen;
                if (JSON.stringify(d.plugins) !== JSON.stringify(root.plugins)) root.plugins = d.plugins;
            }
        }
    }
    Timer { interval: 3000; running: true; repeat: true; onTriggered: root.check() }

    // stop the daemon, then open the plugin's own app
    function openApp(p) {
        const o = Object.assign({}, opening);
        o[p.id] = true;
        opening = o;
        appLaunch.plugin = p;
        appLaunch.restart();
    }
    Timer {
        id: appLaunch
        property var plugin: null
        interval: 1500
        onTriggered: {
            const p = plugin;
            Quickshell.execDetached({ command: p.app.map(a => a.indexOf("/") > 0 && !a.startsWith("/") ? p.dir + "/" + a : a), workingDirectory: p.dir });
            clearOpening.restart();
        }
    }
    // by then the app shows up as running and keeps the daemon off by itself
    Timer { id: clearOpening; interval: 6000; onTriggered: root.opening = ({}) }

    Instantiator {
        model: root.plugins.filter(p => p.daemon && p.daemon.length)
        delegate: Process {
            id: daemonProc
            required property var modelData
            readonly property bool wanted: modelData.connected && !modelData.appRunning && !root.opening[modelData.id]
            running: wanted
            workingDirectory: modelData.dir
            command: modelData.daemon.map(a => a.indexOf("/") > 0 && !a.startsWith("/") ? modelData.dir + "/" + a : a)
            // if it ever stops on its own, start it again a few seconds later
            onExited: if (wanted) again.restart()
            property Timer again: Timer { interval: 3000; onTriggered: if (daemonProc.wanted) daemonProc.running = true }
        }
    }
}
