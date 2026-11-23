pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wired or wireless, from NetworkManager.
Singleton {
    id: root
    property string kind: "ethernet"     // ethernet | wifi | none

    function refresh() { nm.running = true; }

    Process {
        id: nm
        command: ["nmcli", "-t", "-f", "TYPE,STATE", "device"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                if (lines.some(l => l.startsWith("ethernet:connected"))) root.kind = "ethernet";
                else if (lines.some(l => l.startsWith("wifi:connected"))) root.kind = "wifi";
                else root.kind = "none";
            }
        }
    }
    Timer { interval: 5000; running: true; repeat: true; onTriggered: nm.running = true }
}
