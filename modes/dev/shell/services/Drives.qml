pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// The drives Tide shows, one list for everything: the System widget, the resource
// center and the fill alerts. theme.json "drives": [{ path, name }], edited in
// Settings → Widgets → System widget. When it's empty the mounted drives are
// detected once and saved as the list (so a fresh setup shows what's there); after
// that only the list counts. Every 5 minutes scripts/drives.py reads their usage; one
// that fills past its "notify at" level (theme.json "driveAlerts": { mount: percent,
// 0 = off }, 90 when not set) sends a notification once, and again only after it has
// dropped back below.
Singleton {
    id: root
    readonly property var chosen: Theme.opt("drives", [])
    // every chosen drive in order: {mount, device, fs, size, used, pct, label, path},
    // or {path, label, missing: true} when it isn't mounted right now
    property var list: []
    readonly property var mounted: list.filter(d => !d.missing)
    onChosenChanged: check()

    // which drives already warned, kept on disk so a shell restart doesn't warn again
    property var warned: ({})
    property bool warnedLoaded: false
    FileView {
        id: warnedFile
        path: Quickshell.env("HOME") + "/.local/state/tide/drives-warned.json"
        printErrors: false
        onLoaded: { try { root.warned = JSON.parse(text()); } catch (e) {} root.warnedLoaded = true; root.check(); }
        onLoadFailed: { root.warnedLoaded = true; root.check(); }
    }
    readonly property var alerts: Theme.opt("driveAlerts", ({}))
    function at(mount) { return alerts[mount] !== undefined ? alerts[mount] : 90; }
    function setAt(mount, pct) {
        const a = Object.assign({}, alerts);
        a[mount] = pct;
        Theme.set("driveAlerts", a);
        check();
    }
    function gb(b) { return b >= 1e12 ? (b / 1e12).toFixed(2) + " TB" : Math.round(b / 1e9) + " GB"; }

    // ---- editing the list ----
    function save(l) { Theme.set("drives", l); }
    function rename(i, name) { const l = chosen.slice(); l[i] = { path: l[i].path, name: name.trim() || l[i].name }; save(l); }
    function remove(i) { const l = chosen.slice(); l.splice(i, 1); save(l); }
    function move(i, by) {
        const j = i + by, l = chosen.slice();
        if (j < 0 || j >= l.length) return;
        [l[i], l[j]] = [l[j], l[i]];
        save(l);
    }
    // detect again and replace the list with what's mounted
    function resetToDetected() { if (chosen.length) save([]); else check(); }

    // add: resolve the path to its drive first; addMessage says what happened
    property string addMessage: ""
    property bool addOk: false
    function add(path) {
        path = path.trim();
        if (!path || resolver.running) return;
        resolver.command = ["python3", "-I", Quickshell.shellDir + "/scripts/drives.py", "--resolve", path];
        resolver.running = true;
    }
    Process {
        id: resolver
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { root.addOk = false; root.addMessage = "Couldn't read that path"; return; }
                if (d.error) { root.addOk = false; root.addMessage = d.error; return; }
                const same = root.mounted.find(x => x.device === d.device);
                if (same) { root.addOk = false; root.addMessage = "Same drive as " + same.label + " (" + d.device + " at " + same.mount + ")"; return; }
                root.addOk = true;
                root.addMessage = "Added " + d.device + " at " + d.mount;
                root.save(root.chosen.concat([{ path: d.mount, name: d.label }]));
            }
        }
    }

    // ---- reading usage ----
    function check() {
        if (!warnedLoaded) return;
        if (probe.running) { probe.pending = true; return; }
        probe.seeding = chosen.length === 0;
        probe.command = ["python3", "-I", Quickshell.shellDir + "/scripts/drives.py"]
            .concat(probe.seeding ? [] : ["--paths", JSON.stringify(chosen.map(d => d.path))]);
        probe.running = true;
    }
    Process {
        id: probe
        property bool seeding: false
        onRunningChanged: if (!running && pending) { pending = false; root.check(); }
        property bool pending: false
        stdout: StdioCollector {
            onStreamFinished: {
                let l;
                try { l = JSON.parse(text); } catch (e) { return; }
                if (probe.seeding) {
                    // first run (or Reset): the detected drives become the list
                    if (l.length) root.save(l.map(d => ({ path: d.mount, name: d.label })));
                    return;
                }
                const names = root.chosen;
                root.list = l.map((d, i) => Object.assign({}, d, { label: names[i] ? names[i].name : (d.label || d.path) }));
                const w = Object.assign({}, root.warned);
                for (const d of root.mounted) {
                    const limit = root.at(d.mount);
                    if (limit > 0 && d.pct >= limit && !w[d.mount]) {
                        w[d.mount] = true;
                        Quickshell.execDetached(["notify-send", "-a", "Storage", "-u", "critical",
                            d.label + " is " + d.pct + "% full",
                            root.gb(d.size - d.used) + " left on " + d.mount]);
                    } else if (limit === 0 || d.pct < limit - 2) {
                        delete w[d.mount];
                    }
                }
                if (JSON.stringify(w) !== JSON.stringify(root.warned)) {
                    root.warned = w;
                    warnedFile.setText(JSON.stringify(w));
                }
            }
        }
    }
    Timer { interval: 300000; running: true; repeat: true; onTriggered: root.check() }

    IpcHandler {
        target: "drives"
        function check(): void { root.check(); }
        function state(): string { return JSON.stringify({ alerts: root.alerts, warned: root.warned, list: root.list.map(d => d.label + " " + (d.mount || d.path) + " " + (d.missing ? "missing" : d.pct + "%")) }); }
        function add(path: string): void { root.add(path); }
        function message(): string { return root.addMessage; }
        function remove(i: int): void { root.remove(i); }
        function move(i: int, by: int): void { root.move(i, by); }
        function rename(i: int, name: string): void { root.rename(i, name); }
    }
}
