pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wireless device batteries for the control cluster (scripts/peripherals.py reads the
// kernel every 2 seconds, so a device shows up right after it connects).
// Each: { id, kind: headset|mouse|controller|keyboard|phone, model, percent, charging }
Singleton {
    id: root
    property var devices: []
    Process {
        id: reader
        running: true
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/peripherals.py"]
        stdout: SplitParser {
            onRead: line => { try { root.devices = JSON.parse(line); } catch (e) {} }
        }
        onExited: restart.start()
    }
    Timer { id: restart; interval: 2000; onTriggered: reader.running = true }
}
