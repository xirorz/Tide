pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import ".."

// A running theme session (bin/tide-mode writes ~/.local/state/tide/session.json when a
// theme with a timer, app limit or lockout starts): counts down and ends it, sets aside
// windows of apps that aren't allowed (a hidden workspace; they come back when it
// ends; the island says so), starts scheduled themes (with a heads-up 5 minutes
// before: Start now / Skip today), and the emergency exit: while locked in, holding
// Mod+Esc for 5 seconds ends the session (the island shows a filling ring); a quick
// tap still opens the power menu. The island's timer pill reads secondsLeft.
Singleton {
    id: root
    readonly property string tool: Quickshell.env("HOME") + "/.config/Tide/bin/tide-mode"
    readonly property string file: Quickshell.env("HOME") + "/.local/state/tide/session.json"
    property var s: ({})
    readonly property bool active: !!s.theme
    readonly property int endsAt: s.endsAt || 0
    property real now: Date.now() / 1000
    readonly property int secondsLeft: endsAt ? Math.max(0, Math.round(endsAt - now)) : -1
    readonly property bool locked: active && !!s.lockout && secondsLeft > 0
    readonly property string name: s.name || ""
    // the pill: 18:42, or 1 h 05 past an hour
    function timeText(sec) {
        if (sec < 0) return "";
        if (sec >= 3600) return Math.floor(sec / 3600) + " h " + String(Math.floor(sec % 3600 / 60)).padStart(2, "0");
        return Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0");
    }
    // Tide tools allowed in this mode (when its apps are limited); the island's own
    // modes, the Eve panel, dictation and widget editing ask here first
    readonly property var toolNames: ({ calculator: "The calculator", clipboard: "Clipboard history", capture: "Capture", dictation: "Dictation",
                                        eve: "Eve", wallpapers: "The wallpaper picker", widgets: "Editing widgets" })
    function toolAllowed(t) { return !active || !s.limit || !s.tools || s.tools[t] !== false; }
    // false (and the island says why) when the tool is blocked
    function useTool(t) {
        if (toolAllowed(t)) return true;
        notice(toolNames[t] || t);
        return false;
    }
    function notice(what) {
        Quickshell.execDetached(["notify-send", "-a", "Tide", what + " isn't allowed in " + name + (secondsLeft > 0 ? " · " + left(secondsLeft) + " left" : ""),
                                 "It's back when " + name + " ends"]);
    }
    // an allowed app's window: its class (or the last part of it, or a word of its
    // title) matches one of the names tide-mode listed for the allowed apps
    function allowedWindow(cls, title) {
        const tokens = s.allowed || [], c = cls.toLowerCase(), last = c.split(".").pop(), ti = (title || "").toLowerCase();
        return tokens.indexOf(c) >= 0 || tokens.indexOf(last) >= 0 || tokens.some(t => t.length > 3 && ti.indexOf(t) >= 0);
    }
    function allowedEntry(e) {
        if (!active || !s.limit) return true;
        const id = e.id.replace(/\.desktop$/, "").toLowerCase();
        const exe = ((e.command || [])[0] || "").split("/").pop().toLowerCase();
        return [id, id.split(".").pop(), (e.startupClass || "").toLowerCase(), e.name.toLowerCase(), exe].some(n => n && (s.allowed || []).indexOf(n) >= 0);
    }
    function left(sec) {
        const m = Math.ceil(sec / 60);
        return m >= 60 ? Math.floor(m / 60) + " h " + (m % 60 ? (m % 60) + " min" : "") : m + " min";
    }

    // at start: tide-mode drops a session left from before a reboot or new login (a
    // plain shell restart keeps it), then the file is read
    Process {
        running: true
        command: [root.tool, "session"]
        onExited: sf.reload()
    }
    FileView {
        id: sf
        path: root.file
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.s = JSON.parse(text()) || {}; } catch (e) { root.s = {}; } root.warned = false; root.ending = false; }
        onLoadFailed: root.s = {}
    }

    // ---- the countdown ----
    property bool warned: false
    property bool ending: false
    Timer {
        interval: 1000; repeat: true
        running: root.active && root.endsAt > 0
        onTriggered: {
            root.now = Date.now() / 1000;
            if (!root.warned && root.secondsLeft <= 300 && root.secondsLeft > 0 && root.endsAt - root.s.started > 600) {
                root.warned = true;
                Quickshell.execDetached(["notify-send", "-a", "Tide", root.name + ": 5 minutes left", "Then it switches back to what you had before"]);
            }
            if (root.secondsLeft === 0 && !root.ending) {
                root.ending = true;
                Quickshell.execDetached(["notify-send", "-a", "Tide", "Done · " + root.left(root.endsAt - root.s.started) + " of " + root.name, "Back to what you had before"]);
                Quickshell.execDetached([root.tool, "end", "--timeup"]);
            }
        }
    }

    // ---- app limit: new windows of other apps are set aside ----
    Connections {
        target: Hyprland
        enabled: root.active && !!root.s.limit
        function onRawEvent(event) {
            if (event.name !== "openwindow") return;
            const f = event.data.split(",");
            const addr = "0x" + f[0], ws = f[1], cls = f[2] || "", title = f.slice(3).join(",");
            if (!cls || cls === "org.quickshell" || root.allowedWindow(cls, title) || ws.startsWith("special:")) return;
            Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ workspace = \"special:tidehidden\", window = \"address:" + addr + "\", follow = false })"]);
            const s = Object.assign({}, root.s);
            s.hidden = (s.hidden || []).concat([{ address: addr, workspace: ws, class: cls }]);
            root.s = s;
            sf.setText(JSON.stringify(s, null, 2));
            const e = DesktopEntries.heuristicLookup(cls);
            Quickshell.execDetached(["notify-send", "-a", "Tide", (e ? e.name : cls) + " isn't allowed in " + root.name + (root.secondsLeft > 0 ? " · " + root.left(root.secondsLeft) + " left" : ""),
                                     "It's set aside, not closed, and comes back when " + root.name + " ends"]);
        }
    }

    // ---- schedules: themes with days and a time start themselves ----
    // Only at the minute itself: a start that passed while the PC was off is skipped.
    // Five minutes before, a heads-up offers Start now / Skip today.
    property string lastStart: ""
    property var skipped: ({})          // "yyyy-MM-dd id" -> true (Skip today)
    property var warnedStart: ({})
    function scheduledAt(m, d) { return m.custom && m.time && m.time === Qt.formatTime(d, "HH:mm") && (m.days || []).indexOf(d.getDay()) >= 0; }
    Timer {
        interval: 20000; repeat: true; running: true
        onTriggered: {
            const d = new Date(), day = Qt.formatDate(d, "yyyy-MM-dd"), soon = new Date(d.getTime() + 5 * 60000);
            for (const m of Modes.list) {
                const k = day + " " + m.id;
                if (root.scheduledAt(m, soon) && !root.warnedStart[Qt.formatDate(soon, "yyyy-MM-dd") + " " + m.id] && !m.active && !heads.running) {
                    const w = Object.assign({}, root.warnedStart); w[Qt.formatDate(soon, "yyyy-MM-dd") + " " + m.id] = true; root.warnedStart = w;
                    heads.mode = m;
                    heads.command = ["notify-send", "-a", "Tide", "-A", "start=Start now", "-A", "skip=Skip today", "--wait",
                                     m.name + " starts in 5 minutes", m.lockout ? "It locks you in until time is up" : "On your schedule"];
                    heads.running = true;
                }
                if (root.locked || !root.scheduledAt(m, d) || m.active || root.skipped[k] || root.lastStart === k + Qt.formatTime(d, "HH:mm")) continue;
                root.lastStart = k + Qt.formatTime(d, "HH:mm");
                Quickshell.execDetached(["notify-send", "-a", "Tide", "Starting " + m.name, "It's on your schedule"]);
                Quickshell.execDetached([root.tool, m.id, "--scheduled"]);
                break;
            }
        }
    }
    Process {
        id: heads
        property var mode: null
        stdout: StdioCollector {
            onStreamFinished: {
                const a = text.trim(), m = heads.mode;
                if (!m) return;
                const start = new Date(Date.now() + 5 * 60000), k = Qt.formatDate(start, "yyyy-MM-dd") + " " + m.id;
                if (a === "skip") { const s = Object.assign({}, root.skipped); s[k] = true; root.skipped = s; }
                if (a === "start" && !root.locked) {
                    root.lastStart = k + m.time;
                    const s = Object.assign({}, root.skipped); s[k] = true; root.skipped = s;   // it's running; don't start again at the time
                    Quickshell.execDetached([root.tool, m.id, "--scheduled"]);
                }
            }
        }
    }

    // ---- starting a lock-in by hand asks first (tide-mode calls askStart) ----
    property var pending: null           // { id, name, duration }
    property int pendingLeft: 0
    function askStart(id) {
        Modes.refresh();
        const m = Modes.list.find(x => x.id === id);
        pending = { id: id, name: m ? m.name : id, duration: m ? m.duration : 0 };
        pendingLeft = 10;
        IslandState.open("confirm", Theme.monitor);   // always on the main screen, wherever the mouse is
    }
    function confirmStart() {
        if (!pending) return;
        const id = pending.id;
        pending = null;
        IslandState.close();
        Quickshell.execDetached([tool, id, "--confirmed"]);
    }
    function cancelStart() { pending = null; if (IslandState.mode === "confirm") IslandState.close(); }
    // the island closed some other way (a click outside): that's a no
    Connections {
        target: IslandState
        function onModeChanged() { if (IslandState.mode !== "confirm" && root.pending) root.pending = null; }
    }
    Timer {
        interval: 1000; repeat: true
        running: root.pending !== null
        onTriggered: if (--root.pendingLeft <= 0) root.cancelStart()
    }

    // ---- emergency exit: hold Mod+Esc for 5 seconds ----
    property bool holding: false
    property real holdStart: 0
    property real holdProgress: 0       // 0..1, the island's ring
    // a press shorter than this is a tap: the power menu, as always
    readonly property int tapMs: 400
    property bool holdVisible: false
    function beginHold() { if (!locked) return; holding = true; holdStart = Date.now(); holdProgress = 0; holdVisible = false; }
    function endHold() {
        if (holding && Date.now() - holdStart < tapMs) IslandState.toggle("power");
        holding = false; holdProgress = 0; holdVisible = false;
    }
    Timer {
        interval: 16; repeat: true
        running: root.holding
        onTriggered: {
            root.holdVisible = Date.now() - root.holdStart >= root.tapMs;
            root.holdProgress = Math.min(1, (Date.now() - root.holdStart) / 5000);
            if (root.holdProgress >= 1) {
                root.holding = false;
                root.holdVisible = false;
                Quickshell.execDetached(["notify-send", "-a", "Tide", "Emergency exit", root.name + " ended early"]);
                Quickshell.execDetached([root.tool, "end", "--emergency"]);
            }
        }
    }

    IpcHandler {
        target: "session"
        function state(): string { return JSON.stringify({ active: root.active, name: root.name, secondsLeft: root.secondsLeft, locked: root.locked, limit: !!root.s.limit, hidden: (root.s.hidden || []).length, holding: root.holding, skipped: Object.keys(root.skipped) }); }
        function beginHold(): void { root.beginHold(); }
        function endHold(): void { root.endHold(); }
        function toolAllowed(t: string): bool { return root.toolAllowed(t); }
        // the same, but says so in the island when it's blocked (scripts use this)
        function useTool(t: string): bool { return root.useTool(t); }
        // tide-mode: a lock-in started by hand asks in the island first
        function askStart(id: string): void { root.askStart(id); }
    }
}
