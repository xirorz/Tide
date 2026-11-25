pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// The Bluetooth pairing agent (scripts/bt-agent.py), running while there's an adapter.
// Devices that pair with a code ask through it; the control center's Bluetooth list
// shows the question (bar/ControlCenter.qml) and opens itself when a device asks.
//   ask: null, or { id, kind: confirm|pin|passkey|display|authorize, device, code }
Singleton {
    id: root
    property var ask: null
    signal asked()
    function answer(ok, value) {
        if (!ask) return;
        if (ask.id) agent.write(JSON.stringify({ id: ask.id, ok: ok, value: value || "" }) + "\n");
        ask = null;
    }
    Process {
        id: agent
        running: !!Bluetooth.defaultAdapter
        stdinEnabled: true
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/bt-agent.py"]
        stdout: SplitParser {
            onRead: line => {
                let d;
                try { d = JSON.parse(line); } catch (e) { return; }
                if (d.kind === "cancel") { root.ask = null; return; }
                root.ask = d;
                root.asked();
            }
        }
        onExited: { root.ask = null; if (Bluetooth.defaultAdapter) again.start(); }
    }
    // "type this code on the device" has no answer: it goes when pairing ends or after a minute
    Timer { running: !!root.ask && root.ask.kind === "display"; interval: 60000; onTriggered: root.ask = null }
    // try the question without a device: qs ipc call btagent sample confirm|pin|display|authorize
    // (id 0: nothing is sent to BlueZ)
    IpcHandler {
        target: "btagent"
        function sample(kind: string): void { root.ask = { id: 0, kind: kind, device: "Keyboard K380", code: kind === "pin" ? "" : "482913" }; root.asked(); }
    }
    Timer { id: again; interval: 5000; onTriggered: agent.running = !!Bluetooth.defaultAdapter }
}
