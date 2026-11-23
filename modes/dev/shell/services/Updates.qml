pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Pending updates (scripts/updates.py: pacman, AUR, Flatpak, Arch news) and the
// update itself, which runs in a floating kitty (scripts/update-run.sh). The panel
// follows the terminal's log: phase, percent, the package being installed, and
// when pacman is waiting for an answer. A shell restart picks a running update up
// again from the same log.
Singleton {
    id: root

    property var groups: ({ system: [], apps: [], aur: [], flatpak: [] })
    property var news: ({ ok: false, posts: [] })
    property real checkedAt: 0
    property bool checking: false

    // the panel's switches, kept in theme.json
    readonly property bool includeAur: Theme.opt("updatesAur", true)
    readonly property bool includeFlatpak: Theme.opt("updatesFlatpak", true)
    readonly property bool snapshot: Theme.opt("updatesSnapshot", true)
    readonly property bool reviewAur: Theme.opt("updatesReviewAur", true)
    // the AUR helper (scripts/aur-helper.sh): Settings → System, "auto" finds it
    readonly property string aurHelper: Theme.opt("updatesAurHelper", "auto")
    property var helperInfo: ({ use: "", auto: "", found: [] })
    function loadHelper() { if (!helperProc.running) helperProc.running = true; }
    Process {
        id: helperProc
        command: ["bash", Quickshell.shellDir + "/scripts/aur-helper.sh", "--json", root.aurHelper]
        stdout: StdioCollector { onStreamFinished: { try { root.helperInfo = JSON.parse(text); } catch (e) {} } }
    }
    onAurHelperChanged: loadHelper()
    Component.onCompleted: loadHelper()
    // CachyOS news next to Arch's (Settings can turn it off)
    readonly property bool cachyNews: Theme.opt("updatesCachyNews", true)

    function included(key) {
        return (key !== "aur" || includeAur) && (key !== "flatpak" || includeFlatpak);
    }
    readonly property int count: ["system", "apps", "aur", "flatpak"].reduce((s, k) => s + (included(k) ? groups[k].length : 0), 0)
    readonly property real totalMb: ["system", "apps", "aur", "flatpak"].reduce((s, k) => s + (included(k) ? groups[k].reduce((a, r) => a + r.mb, 0) : 0), 0)

    function mb(n) {
        if (n <= 0) return "";
        if (n >= 1000) return (n / 1000).toFixed(2) + " GB";
        return (n >= 10 ? Math.round(n) : n.toFixed(1)) + " MB";
    }
    function ago(t) {
        if (!t) return "";
        const s = Math.max(0, Date.now() / 1000 - t);
        if (s < 60) return "just now";
        if (s < 3600) return Math.floor(s / 60) + " min ago";
        return Math.floor(s / 3600) + " h ago";
    }

    function check() {
        if (phase === "busy" || checker.running) return;
        root.checking = true;
        checker.running = true;
    }
    Process {
        id: checker
        command: ["env", "TIDE_AUR_HELPER=" + root.aurHelper, "python3", "-I", Quickshell.shellDir + "/scripts/updates.py", "--news", root.cachyNews ? "arch,cachyos" : "arch"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.checking = false;
                let d;
                try { d = JSON.parse(text); } catch (e) { return; }
                root.groups = { system: d.system, apps: d.apps, aur: d.aur, flatpak: d.flatpak };
                if (d.news.ok) root.news = d.news;
                root.checkedAt = d.checked;
            }
        }
        onExited: root.checking = false
    }
    Timer {
        interval: Theme.updatesEveryMinutes * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.check()
    }
    // first check shortly after login
    Timer { interval: 30000; running: true; onTriggered: root.check() }

    // ---------- the update ----------
    property string phase: "list"          // list | busy | done
    property bool dryRun: false            // rehearse with sample output (IPC: updates dryRun true)
    property int planned: 0                // packages when it started
    property var plannedNames: []
    property bool needsRestart: false      // kernel, drivers or firmware were updated
    property string step: ""               // pacman | aur | flatpak
    property string stage: ""              // the design's phase line
    property int pct: 0
    property string current: ""
    property int doneN: 0
    property int installN: 0               // pacman's (k/N) total
    property bool waiting: false           // a question is open in the terminal
    property var pacnew: []
    property var codes: ({})
    property int seconds: 0
    // the log is only read once this run's id shows up (an old log may still be there)
    property string runId: ""
    property bool seenRun: false
    readonly property bool failed: Object.keys(codes).some(k => codes[k] !== 0)
    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/tide-updates"

    signal started()
    function start() {
        if (phase === "busy" || count === 0) return;
        const names = [];
        let restart = false;
        for (const k of ["system", "apps", "aur", "flatpak"]) {
            if (!included(k)) continue;
            for (const r of groups[k]) names.push(r.name);
            if (k === "system" && groups[k].length > 0) restart = true;
        }
        plannedNames = names;
        planned = names.length;
        needsRestart = restart;
        resetRun();
        runId = String(Date.now());
        seenRun = false;
        phase = "busy";
        Quickshell.execDetached(["env", "TIDE_ACCENT=" + Theme.accentTarget, "TIDE_AUR_HELPER=" + aurHelper, "kitty", "--config", Quickshell.shellDir + "/scripts/update-kitty.conf",
            "--class", "tide-updates", "--title", "Updates",
            "bash", Quickshell.shellDir + "/scripts/update-run.sh", dryRun ? "dry" : "real",
            includeAur ? "1" : "0", includeFlatpak ? "1" : "0", snapshot ? "1" : "0", runId, reviewAur ? "1" : "0"]);
        follow.restart();
        started();
    }
    function resetRun() {
        step = ""; stage = "Checking for conflicts"; pct = 0; current = "Preparing…";
        doneN = 0; installN = 0; waiting = false; pacnew = []; codes = ({}); seconds = 0;
    }
    // back to the list after "Close" on the done view
    function finish() {
        phase = "list";
        check();
    }
    function restartNow() { Quickshell.execDetached(["systemctl", "reboot"]); }
    function reviewPacnew() {
        Quickshell.execDetached(["kitty", "--config", Quickshell.shellDir + "/scripts/update-kitty.conf", "--class", "tide-updates", "--title", "pacdiff", "sudo", "DIFFPROG=nvim -d", "pacdiff"]);
    }
    function openNews() {
        const p = news.posts[0];
        Quickshell.execDetached(["xdg-open", p && p.link ? p.link : "https://archlinux.org/news/"]);
    }

    // reads the log from the top every time it starts (also after a shell restart)
    Timer {
        id: follow
        interval: 700
        onTriggered: { tail.running = false; tail.running = true; }
    }
    Process {
        id: tail
        command: ["tail", "-n", "+1", "-F", root.dir + "/log"]
        stdout: SplitParser { onRead: line => root.feed(line) }
    }
    function feed(raw) {
        // pacman redraws progress with \r; colour codes are dropped
        const parts = raw.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "").split("\r");
        for (let i = 0; i < parts.length; i++) {
            const l = parts[i];
            if (l.trim() === "" && i < parts.length - 1) continue;
            line(l, i === parts.length - 1);
        }
    }
    function line(l, last) {
        if (l.startsWith("Script started") || l.startsWith("Script done")) return;
        const m = l.match(/^::tide:: (\w+) ?(.*)$/);
        if (runId !== "" && !seenRun) {
            if (m && m[1] === "run" && m[2] === runId) seenRun = true;
            return;
        }
        if (m) {
            const a = m[2].split(" ");
            if (m[1] === "step") {
                step = a[0];
                if (step === "aur") { stage = "Updating AUR packages"; pct = Math.max(pct, 85); current = "Building with " + (helperInfo.use || "the AUR helper"); }
                if (step === "flatpak") { stage = "Updating Flatpak apps"; pct = Math.max(pct, 93); current = "flatpak update"; }
            } else if (m[1] === "rc") {
                const c = Object.assign({}, codes);
                c[a[0]] = parseInt(a[1]);
                codes = c;
            } else if (m[1] === "end") {
                seconds = parseInt(a[0]) || 0;
                waiting = false;
                pct = 100;
                tail.running = false;
                phase = "done";
                if (!failed) doneN = planned;
            }
            return;
        }
        if (phase !== "busy") phase = "busy";
        let k;
        if (/^:: Synchronizing/.test(l)) { stage = "Checking for conflicts"; pct = Math.max(pct, 3); }
        else if (/^:: Starting full system upgrade/.test(l)) pct = Math.max(pct, 8);
        else if (/^:: Retrieving packages/.test(l)) { stage = "Downloading"; pct = Math.max(pct, 15); current = "Downloading " + root.mb(root.totalMb); }
        else if (/checking keys|checking package integrity/.test(l)) { stage = "Installing"; pct = Math.max(pct, 35); }
        else if ((k = l.match(/^\((\s*\d+)\/(\d+)\) (upgrading|installing|reinstalling|downgrading) (\S+)/))) {
            const n = parseInt(k[1]), of = parseInt(k[2]);
            stage = "Installing";
            installN = of;
            doneN = Math.min(planned, n);
            current = "Updated " + n + " of " + of + " · " + k[4];
            pct = Math.max(pct, 40 + Math.round(35 * n / of));
        }
        else if (/^:: Running post-transaction hooks/.test(l)) { stage = "Running post-install steps"; pct = Math.max(pct, 78); current = "Post-install hooks"; }
        else if ((k = l.match(/installed as (\S+\.pacnew)/))) pacnew = pacnew.concat([k[1]]);
        else if (step === "flatpak" && (k = l.match(/^\s*(\d+)\.\s+\S+\s+(\S+)/))) current = "Flatpak · " + k[2];
    }

    // pacman, sudo or the AUR helper waiting for an answer: the log's unfinished last line
    // ends in a question (SplitParser only sees finished lines, so poll the tail)
    Timer {
        interval: 1000
        repeat: true
        running: root.phase === "busy"
        onTriggered: if (!promptProc.running) promptProc.running = true
    }
    Process {
        id: promptProc
        command: ["tail", "-c", "400", root.dir + "/log"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lastLine = text.slice(text.lastIndexOf("\n") + 1).split("\r").pop().replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "");
                root.waiting = root.phase === "busy" && /(\[[YyNn](\/[YyNnAa])+\]|password[^:]*:|\[default=[^\]]*\]:?|Enter a [^:]*:|==>.*)\s*$/.test(lastLine);
            }
        }
    }

    // a shell restart mid-update: carry on following the same log
    FileView {
        id: pidFile
        path: root.dir + "/pid"
        printErrors: false
        onLoaded: {
            if (text().trim() !== "" && root.phase === "list") {
                root.resetRun();
                root.runId = "";
                root.planned = root.count;
                root.phase = "busy";
                follow.restart();
            }
        }
    }

    IpcHandler {
        target: "updates"
        function dryRun(on: bool): void { root.dryRun = on; }
        function check(): void { root.check(); }
        function state(): string { return root.phase + " " + root.pct + "% " + root.stage + " · " + root.current + (root.waiting ? " · waiting" : "") + " · count " + root.count; }
    }
}
