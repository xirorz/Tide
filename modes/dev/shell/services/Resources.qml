pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The resource center's numbers (scripts/resources.py, once a second) and an hour of
// history for the 1 min / 5 min / 1 hr charts.
Singleton {
    id: root
    property var now: ({})
    property var procs: []
    // history, newest last, at most an hour (one sample a second)
    property var gpuHist: []
    property var cpuHist: []
    property var memHist: []
    property var diskHist: []
    property var netHist: []
    readonly property int maxSamples: 3600

    function push(list, v) {
        const l = list.length >= maxSamples ? list.slice(list.length - maxSamples + 1) : list.slice();
        l.push(v);
        return l;
    }
    // the last `seconds` of a history, averaged down to about `points` values
    function window(list, seconds, points) {
        const l = list.slice(Math.max(0, list.length - seconds));
        if (l.length <= points) return l;
        const step = l.length / points, out = [];
        for (let i = 0; i < points; i++) {
            const a = Math.floor(i * step), b = Math.max(a + 1, Math.floor((i + 1) * step));
            let s = 0;
            for (let j = a; j < b; j++) s += l[j];
            out.push(s / (b - a));
        }
        return out;
    }

    function gb(bytes) { return (bytes / 1073741824).toFixed(1); }
    function rate(bps) {
        if (bps >= 1048576) return (bps / 1048576).toFixed(bps >= 104857600 ? 0 : 1) + " MB/s";
        if (bps >= 1024) return Math.round(bps / 1024) + " KB/s";
        return Math.round(bps) + " B/s";
    }
    // ask a process to quit (SIGTERM)
    function end(pid) { endAll([pid]); }

    // ---- ending, with Force quit when something won't go ----
    // key -> pids still alive 3 s after End (the row then offers Force quit)
    property var stuck: ({})
    property var ending: ({})            // key -> true while waiting those 3 s
    function endAll(pids, key) {
        key = key || String(pids[0]);
        Quickshell.execDetached(["kill", "-TERM"].concat(pids.map(String)));
        const e = Object.assign({}, ending); e[key] = { pids: pids, at: Date.now() }; ending = e;
    }
    function forceQuit(key) {
        const pids = stuck[key] || [];
        if (pids.length) Quickshell.execDetached(["kill", "-KILL"].concat(pids.map(String)));
        const s = Object.assign({}, stuck); delete s[key]; stuck = s;
        searchSoon();
    }
    // 3 s after End: which of those are still running
    Timer {
        interval: 500; repeat: true
        running: Object.keys(root.ending).length > 0 && !aliveCheck.running
        onTriggered: {
            const due = Object.keys(root.ending).filter(k => Date.now() - root.ending[k].at >= 3000);
            if (!due.length) return;
            aliveCheck.keys = due;
            // only numbers reach the shell: each argument is "<index in due>:<pid>" (a
            // program's name can hold quotes, e.g. Wine's "Baldur's Gate 3.exe")
            const args = [];
            due.forEach((k, i) => root.ending[k].pids.map(Number).filter(Number.isInteger).forEach(pid => args.push(i + ":" + pid)));
            aliveCheck.command = ["sh", "-c", 'for a; do kill -0 "${a#*:}" 2>/dev/null && echo "$a"; done', "sh"].concat(args);
            aliveCheck.running = true;
        }
    }
    Process {
        id: aliveCheck
        property var keys: []
        stdout: StdioCollector {
            onStreamFinished: {
                const left = {};
                for (const line of text.trim().split("\n").filter(x => x)) {
                    const [i, pid] = line.split(":").map(Number);
                    const k = aliveCheck.keys[i];
                    if (k !== undefined) (left[k] = left[k] || []).push(pid);
                }
                const s = Object.assign({}, root.stuck), e = Object.assign({}, root.ending);
                for (const k of aliveCheck.keys) { if (left[k]) s[k] = left[k]; else delete s[k]; delete e[k]; }
                root.stuck = s; root.ending = e;
                root.searchSoon();
            }
        }
    }
    // a systemd user service
    function stopUnit(unit) {
        Quickshell.execDetached(["systemctl", "--user", "stop", unit]);
        searchSoon();
    }

    // ---- search (the resource center's box): every process, not just the busiest ----
    property string query: ""
    property var found: ({ procs: [], services: [] })
    onQueryChanged: { if (query.trim()) searchSoon(); else found = { procs: [], services: [] }; }
    function searchSoon() { if (query.trim()) debounce.restart(); }
    Timer { id: debounce; interval: 200; onTriggered: if (!searcher.running) searcher.running = true; else again = true; property bool again: false }
    // while a search is showing, it keeps up (every 2 s)
    Timer { interval: 2000; repeat: true; running: root.query.trim() !== ""; onTriggered: root.searchSoon() }
    Process {
        id: searcher
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/procsearch.py", root.query]
        stdout: StdioCollector {
            onStreamFinished: {
                try { if (root.query.trim()) root.found = JSON.parse(text); } catch (e) {}
                if (debounce.again) { debounce.again = false; debounce.restart(); }
            }
        }
    }

    Process {
        id: sampler
        running: true
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/resources.py"]
        // if it ever stops, start it again a second later
        onExited: restart.start()
        stdout: SplitParser {
            onRead: line => {
                let d;
                try { d = JSON.parse(line); } catch (e) { return; }
                root.procs = d.procs;
                delete d.procs;
                root.now = d;
                root.gpuHist = root.push(root.gpuHist, Math.max(0, d.gpu));
                root.cpuHist = root.push(root.cpuHist, d.cpu);
                root.memHist = root.push(root.memHist, d.ramUsed / 1073741824);
                root.diskHist = root.push(root.diskHist, (d.diskRead + d.diskWrite) / 1048576);
                root.netHist = root.push(root.netHist, d.rx / 1048576);
            }
        }
    }
    Timer { id: restart; interval: 1000; onTriggered: sampler.running = true }
    IpcHandler {
        target: "resources"
        function search(q: string): void { root.query = q; }
        function state(): string { return JSON.stringify({ query: root.query, found: (root.found.procs || []).map(p => p.name + "×" + p.count + (p.own ? "" : " (system)")), services: (root.found.services || []).map(s => s.unit + " " + s.active + (s.own ? "" : " (system)")), ending: Object.keys(root.ending), stuck: root.stuck }); }
    }
}
