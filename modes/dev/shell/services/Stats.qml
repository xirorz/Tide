pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property int cpu: 0
    property real ramUsed: 0
    property real ramTotal: 1
    property int gpu: -1
    property real vramUsed: -1
    property real vramTotal: -1
    property int temp: -1
    property real rx: 0
    property real tx: 0

    // "lit when data moves": above 2 KB/s counts as activity
    readonly property bool downloading: rx > 2048
    readonly property bool uploading: tx > 2048

    function gb(bytes) { return (bytes / 1073741824).toFixed(1); }
    function gbTotal(bytes) { return Math.round(bytes / 1073741824); }

    Process {
        command: ["bash", Quickshell.shellDir + "/scripts/stats.sh"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    root.cpu = d.cpu; root.ramUsed = d.ramUsed; root.ramTotal = d.ramTotal;
                    root.gpu = d.gpu; root.vramUsed = d.vramUsed; root.vramTotal = d.vramTotal;
                    root.temp = d.temp; root.rx = d.rx; root.tx = d.tx;
                } catch (e) {}
            }
        }
    }
}
