pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// The 3D printer widget's data (Bambu Lab, local network): scripts/bambu.py watches
// the printer over MQTT while the widget is on the desktop and set up. theme.json
// "widgets"."printer": { host, serial, model, notify }. The access code lives only in
// ~/.local/state/tide/secrets.json (chmod 600), written by the script from stdin;
// it never passes through here or theme.json.
// Controls (light, pause / resume, stop) work in LAN mode only: a command the printer
// rejects or doesn't answer turns them off (controlsOk) and the widget says why.
Singleton {
    id: root
    readonly property var cfg: Widgets.cfg.printer || ({})
    readonly property string host: cfg.host || ""
    readonly property string serial: cfg.serial || ""
    readonly property string model: cfg.model || ""
    // printers announce an internal code (C12 is a P1S); show the name people know
    function niceModel(m) { return ({ "BL-P001": "X1C", "BL-P002": "X1", "C11": "P1P", "C12": "P1S", "C13": "X1E", "N1": "A1 mini", "N2S": "A1", "O1D": "H2D" })[m] || m; }
    readonly property string modelName: niceModel(model)
    readonly property bool notify: cfg.notify !== false
    readonly property bool configured: host !== "" && serial !== ""
    function save(patch) { Widgets.save({ printer: Object.assign({}, cfg, patch) }); }

    readonly property string lanNote: "Controls only work when the printer is in LAN mode (Developer/LAN-only); otherwise the widget stays view-only."

    // ---- live status ----
    property bool online: false
    property int seen: 0                 // last report, seconds since the epoch
    property string error: ""
    property var job: ({})               // see summary() in bambu.py
    readonly property string status: !configured ? "setup" : online ? (job.status || "idle") : "offline"
    property bool controlsOk: true
    property string busy: ""             // the command waiting for an answer
    property string reason: ""

    Process {
        id: watcher
        running: Widgets.enabled && Widgets.has("printer") && root.configured
        stdinEnabled: true
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/bambu.py", "watch", root.host, root.serial]
        onRunningChanged: if (!running) { root.online = false; root.busy = ""; }
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.ack) {
                    root.busy = "";
                    if (!m.ack.ok) { root.controlsOk = false; root.reason = m.ack.reason || ""; }
                    return;
                }
                const before = root.job.status;
                root.online = m.state === "online";
                root.error = m.error || "";
                if (m.seen) root.seen = m.seen;
                if (root.online) root.job = m.job;
                // a print that ends while we watch: one notification
                const now = root.job.status;
                if (root.notify && root.online && (before === "printing" || before === "paused") && (now === "finished" || now === "error")) {
                    const name = root.job.file || "The print";
                    Quickshell.execDetached(["notify-send", "-a", "3D printer", "-u", now === "error" ? "critical" : "normal",
                        now === "finished" ? name + " is done" : name + " failed",
                        now === "finished" ? "Ready to remove from the bed" : "Check the printer"]);
                }
            }
        }
    }
    function send(cmd) {
        if (!watcher.running || !online || !controlsOk || busy) return;
        busy = cmd;
        watcher.write(JSON.stringify({ cmd: cmd }) + "\n");
    }
    // after a refusal, Settings → Test connection (or a new code) tries the controls again
    function allowControls() { controlsOk = true; reason = ""; }

    IpcHandler {
        target: "printer"
        function send(cmd: string): void { root.send(cmd); }
        function allow(): void { root.allowControls(); }
        // for testing the Settings card: act as if Find heard nothing
        function findFailed(): void { root.found = []; root.finding = false; root.findDone = true; fwCheck.running = true; }
        function state(): string { return JSON.stringify({ status: root.status, online: root.online, controlsOk: root.controlsOk, busy: root.busy, reason: root.reason, error: root.error }); }
    }

    // ---- Settings: find, access code, test ----
    property var found: []
    property bool finding: false
    property bool findDone: false        // a search has finished (to say when nothing answered)
    function find() { if (!finder.running) { found = []; finding = true; findDone = false; finder.running = true; } }
    Process {
        id: finder
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/bambu.py", "find", "8"]
        stdout: StdioCollector { onStreamFinished: { try { root.found = JSON.parse(text); } catch (e) { root.found = []; } root.finding = false; root.findDone = true; if (!root.found.length) fwCheck.running = true; } }
    }
    // nothing answered: which firewall is on, the local subnet, and the command that
    // would let the announcements in ({fw: ufw|firewalld|none, subnet, cmd})
    property var fw: ({})
    Process {
        id: fwCheck
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/bambu.py", "firewall"]
        stdout: StdioCollector { onStreamFinished: { try { root.fw = JSON.parse(text); } catch (e) { root.fw = {}; } } }
    }
    // Allow: run that command through pkexec (the system asks for the password; Tide
    // never sees it), then look again
    property string allowError: ""
    function allowFind() {
        if (!fw.cmd || allower.running) return;
        allowError = "";
        Games.picking = true;             // the password window must be in front of Settings
        allower.running = true;
    }
    Process {
        id: allower
        command: ["pkexec", "sh", "-c", root.fw.cmd || "true"]
        onExited: code => {
            Games.picking = false;        // Settings comes back (it stepped aside for the password)
            if (code === 0) root.find();
            else root.allowError = code === 126 || code === 127 ? "Cancelled, or not allowed to change the firewall" : "The firewall command failed (exit " + code + ")";
        }
    }

    property bool hasCode: false
    Process {
        id: codeCheck
        running: true
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/bambu.py", "has-code"]
        stdout: StdioCollector { onStreamFinished: root.hasCode = text.trim() === "true" }
    }
    function refreshCode() { if (!codeCheck.running) codeCheck.running = true; }
    function saveCode(code) {
        if (!code.trim() || codeSetter.running) return;
        codeSetter.pendingCode = code.trim();
        codeSetter.running = true;
    }
    Process {
        id: codeSetter
        property string pendingCode: ""
        stdinEnabled: true
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/bambu.py", "set-code"]
        onStarted: { write(pendingCode + "\n"); pendingCode = ""; }
        // the watcher reads the new code on its next try (within a few seconds)
        onExited: { codeCheck.running = true; root.allowControls(); }
    }

    property string testResult: ""
    property bool testOk: false
    property bool testing: false
    function test() {
        if (tester.running || !configured) return;
        testing = true; testResult = "";
        tester.running = true;
    }
    Process {
        id: tester
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/bambu.py", "test", root.host, root.serial]
        stdout: StdioCollector {
            onStreamFinished: {
                root.testing = false;
                let r;
                try { r = JSON.parse(text); } catch (e) { root.testOk = false; root.testResult = "The test didn't run"; return; }
                root.testOk = r.ok;
                root.testResult = r.ok ? "Connected: the printer is " + r.state : r.error;
                if (r.ok) root.allowControls();
            }
        }
    }
}
