pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// AI PANEL DATA LAYER: the only place the AI panel (eve/EvePanel.qml) gets its data.
// (The file keeps its old name so nothing that imports it breaks; nothing in it is tied to one assistant.)
//
// It talks to whatever assistant is set up in ~/.config/Tide/ai.json through
// scripts/assistant-bridge.py, which speaks the Tide AI API (~/.config/Tide/docs/AI-API.md)
// or, later, any OpenAI-compatible server. The bridge says what the backend can do
// (`capabilities`) and the panel shows only that. With no backend set up, the panel keeps
// the design's demo content, and with AI turned off in Settings → AI the bridge never runs.
Singleton {
    id: root

    // ---------- backend status (from the bridge) ----------
    property string assistantName: "Assistant"
    property bool configured: false     // ai.json names a backend
    property bool reachable: false      // the backend answers
    property bool ready: false          // and says it is ready (e.g. its model is loaded)
    property string detail: ""          // why not, in the backend's words
    property var capabilities: []
    readonly property bool connected: reachable && ready
    readonly property bool live: configured && reachable   // real data instead of the demo
    readonly property string integration: !configured ? "none" : assistantName
    function can(c) { return capabilities.indexOf(c) >= 0; }
    // the panel's status line under the greeting
    readonly property string statusLine: !configured ? "Demo · not connected yet (Settings → AI)"
        : !reachable ? assistantName + " can't be reached" + (detail ? ": " + detail : "")
        : !on ? assistantName + " is off. Turn her on with the power button."
        : !ready ? assistantName + " is starting" + (detail ? " (" + detail + ")" : "")
        : assistantName + " is on and ready"

    // ---------- panel state (UI only) ----------
    property bool open: false
    property bool on: true            // the header's power button (the backend's `power`, when it has one)
    property string current: ""       // open chat id, "" = home
    property bool working: false      // the assistant is answering
    property bool think: false
    property bool listening: false      // the mic (live transcription)
    property var attachments: []        // [{ name, path, kind: pdf|sheet|image|file }]
    property string approval: "approve"   // approve | full
    property string error: ""           // last failed request, shown nowhere yet (kept for debugging)

    // ---------- content: the backend's, or the design's demo while none is set up ----------
    property var chats: demoChats
    property var projects: demoProjects
    property var apps: demoApps
    property var homeCards: demoCards
    property var suggestions: ["What’s using my VRAM?", "Summarize my mail", "Plan tomorrow"]

    readonly property var chat: chats.find(c => c.id === current) || null

    // ---------- apps: shown in the panel from the backend's display blocks ----------
    property string app: ""             // the open app's id, "" = none
    property var appPage: null          // { title, subtitle, blocks } as the backend sent it
    readonly property string appTitle: appPage && appPage.title ? appPage.title : ((apps.find(a => a.id === app) || {}).name || "")
    property string appView: ""          // an app's chosen view (a month in Finance), "" = the app's default
    function openApp(id, view) {
        if (!id || !(live && can("apps"))) return;
        if (id !== app) appPage = null;
        current = ""; app = id; appView = view || "";
        _send({ op: "app", id: id, view: appView });
    }
    function closeApp() { app = ""; appPage = null; }
    function checkAppItem(item, done) { if (app) _send({ op: "check", app: app, item: item, done: done }); }
    // an app refreshes as often as its page asks (`refresh`, seconds; Live: every 2 s while she works), else every 30 s
    Timer { interval: Math.max(1, (root.appPage && root.appPage.refresh) || 30) * 1000; repeat: true; running: root.open && root.app !== ""; onTriggered: root._send({ op: "app", id: root.app, view: root.appView }) }

    // ---------- talk to the assistant: a hands-free call (`voice.call`), drawn in the island (services/Eve.qml) ----------
    readonly property bool canCall: live && can("voice.call")
    property bool calling: false
    property string _heard: ""           // your words since the assistant last spoke
    property string callChat: ""         // the chat the call is in
    function startCall() { if (!canCall) return false; calling = true; _heard = ""; _send({ op: "call", action: "start" }); return true; }
    function endCall() { if (calling) { calling = false; _send({ op: "call", action: "end" }); } }
    function muteCall(on) { if (calling) _send({ op: "call", action: "mute", on: on }); }
    Timer { id: ackDone; interval: 1200; onTriggered: if (root.calling && Eve.stage === "speaking") { Eve.setStage("thinking"); Eve.say(root._heard, false); } }
    // while she works in a call: each tool step's title under Working, and in the island's terminal the search,
    // page or command it ran (and her terminal's output), so the terminal looks like hers
    function _live(m) {
        if (!calling || !m.busy || !m.steps || !m.steps.length) return;
        if (Eve.stage !== "working") Eve.setStage("working");
        const icons = { web: "browser", browser: "browser", terminal: "terminal", containers: "containers" };
        Eve.steps = m.steps.slice(-5).map((st, i, list) => ({
            text: st.title, icon: icons[st.kind] || "log",
            done: st.status !== "running", active: st.status === "running" && i === list.length - 1
        }));
        // her terminal window is only for her terminal: its commands, then its output
        const lines = [];
        for (const st of m.steps) {
            if (st.kind !== "terminal" || !st.detail) continue;
            lines.push({ t: "$ " + st.detail, c: "cmd" });
            if (st.status === "error") lines.push({ t: "failed", c: "out" });
        }
        if (lines.length) for (const t of m.terminal || []) lines.push({ t: t, c: "out" });
        Eve.term = lines.slice(-10);
        // anything else is one status line: what she is doing, and with what
        const now = m.steps[m.steps.length - 1];
        if (!lines.length && now) {
            const what = now.kind === "web" && now.title === "Reading a page" ? now.detail.replace(/^https?:\/\/(www\.)?/, "").split("/")[0] : now.detail;
            Eve.say(now.title + (what && what.length < 70 ? ": " + what : ""), false);
        }
    }

    // the assistant's step lines ("Web • search", "Terminal • run") in plain words for the island
    function _stepWords(t) {
        if (/^web\b.*\b(search|at once)/i.test(t)) return "Searching the web";
        if (/^web\b.*\bread/i.test(t)) return "Reading a page";
        if (/^browser/i.test(t)) return "Using her browser";
        if (/^terminal/i.test(t)) return "Running a command";
        if (/^news/i.test(t)) return "Reading the news";
        return t.replace(/\s*•\s*/g, ": ");
    }
    function _call(m) {
        switch (m.type) {
        case "stage":
            // "speaking" waits for her words (the caption), so an acknowledgement doesn't flip the island
            if (m.stage === "listening") Eve.setStage("listening");
            else if (m.stage === "working" && Eve.stage !== "working") Eve.setStage("working");
            break;
        case "talking":
            if (Eve.stage === "speaking" || Eve.stage === "listening") Eve.setStage("listening");
            break;
        case "caption":
            if (m.who === "user") {
                if (Eve.stage === "speaking") { Eve.setStage("listening"); _heard = ""; }
                _heard = (_heard ? _heard + " " : "") + m.text;
                // the island shows your latest words; the whole call is saved as a chat
                Eve.say(_heard.length > 160 ? "…" + _heard.slice(-160).replace(/^\S*\s/, "") : _heard, false);
            } else if (m.progress) {
                Eve.say(m.text, false);
            } else if (/^\W*(mhm+|mm+|hmm+|uh[- ]huh|okay|ok|yeah|right|sure|got it)\W*$/i.test(m.text)) {
                // her small acknowledgement while you talk: she says it, then she's thinking again
                Eve.setStage("speaking");
                Eve.say(m.text, false);
                ackDone.restart();
            } else {
                _heard = "";
                Eve.setStage("speaking");
                Eve.say(m.text, true);
            }
            break;
        case "step":
            if (can("live")) break;   // the live steps below say more
            Eve.addStep(_stepWords(m.text), /^web\b/i.test(m.text) ? "browser" : /brows/i.test(m.text) ? "browser" : /contain|docker|stack|portainer/i.test(m.text) ? "containers" : /log/i.test(m.text) ? "log" : "terminal");
            break;
        case "approval":
            Eve.say("Waiting for your OK. Open the AI panel to approve or deny it.", false);
            break;
        case "chat":
            Eve.chatTitle = m.title || "";
            callChat = m.id || "";
            break;
        case "stop":
            Eve.setStage("listening");
            break;
        case "error":
            console.warn("AI bridge: call:", m.error);
            Eve.say(m.error, false);
            break;
        case "ended":
            if (calling) { calling = false; if (Eve.active) Eve.end(); }
            break;
        }
    }

    // ---------- the desktop's look, for the assistant's own windows (`appearance`: her browser wears your accent) ----------
    function _hex(c) { const h = x => ("0" + Math.round(x * 255).toString(16)).slice(-2); return "#" + h(c.r) + h(c.g) + h(c.b); }
    function _sendLook() {
        if (!live || !can("appearance")) return;
        _send({ op: "appearance", look: { accent: _hex(Theme.accent), accent2: _hex(Theme.netDown), background: _hex(Theme.panelBg),
                surface: "#18181b", text: _hex(Theme.text), muted: _hex(Theme.muted), font: Theme.sans, mono: Theme.mono } });
    }
    Connections { target: Theme; function onAccentChanged() { lookTimer.restart(); } }
    Timer { id: lookTimer; interval: 1500; onTriggered: root._sendLook() }   // the accent crossfades: send where it lands

    // ---------- read aloud (the backend's `voice.speech`) ----------
    property bool speaking: false
    property string speakingText: ""     // what is being read, so its button shows Stop
    function speak(text) { if (text && live && can("voice.speech")) { speaking = true; speakingText = text; _send({ op: "speak", text: text }); } }
    function stopSpeaking() { speaking = false; _send({ op: "speak", stop: true }); }

    // ---------- the bridge ----------
    property bool _settingOn: false
    property bool _settingMode: false
    readonly property bool _wanted: Theme.aiEnabled
    Process {
        id: bridge
        running: root._wanted
        stdinEnabled: true
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/assistant-bridge.py"]
        stdout: SplitParser { onRead: line => root._receive(line) }
        onRunningChanged: if (!running) { root.reachable = false; root.working = false; if (root._wanted) restartBridge.restart(); }
    }
    Timer { id: restartBridge; interval: 5000; onTriggered: if (root._wanted && !bridge.running) bridge.running = true }

    function _send(req) {
        if (!bridge.running) return false;
        bridge.write(JSON.stringify(req) + "\n");
        return true;
    }
    function reconnect() { _send({ op: "connect" }); }

    function _receive(line) {
        let m;
        try { m = JSON.parse(line); } catch (e) { return; }
        switch (m.ev) {
        case "manifest":
            assistantName = m.name || "Assistant";
            capabilities = m.capabilities || [];
            configured = true;
            apps = (m.apps || []).map(a => ({ id: a.id, name: a.name, icon: appIcons[a.icon] || appIcons.grid }));
            loadChats();
            if (can("power")) _send({ op: "power" });
            _sendLook();
            if (can("mode")) _send({ op: "mode" });
            break;
        case "status":
            const was = live;
            configured = m.configured;
            reachable = m.connected;
            ready = m.ready;
            detail = m.detail || "";
            if (!configured) _showDemo();
            else if (!was && live && chats === demoChats) loadChats();
            break;
        case "chats":
            _setChats(m.chats || []);
            break;
        case "messages":
            chats = chats.map(c => c.id !== m.chat ? c : Object.assign({}, c, { messages: (m.messages || []).map(_message), loaded: true }));
            break;
        case "reply":
            _reply(m);
            break;
        case "call":
            _call(m);
            break;
        case "live":
            _live(m);
            break;
        case "speech":
            speaking = !!m.speaking;
            if (m.error) console.warn("AI bridge: speech:", m.error);
            break;
        case "app":
            if (m.id === app) appPage = m.page || null;
            break;
        case "dictation":
            if (m.error) { error = m.error; console.warn("AI bridge: dictation:", m.error); }
            if (m.cancelled) { transcribing = false; transcript = ""; break; }
            if (m.final) { listening = false; transcribing = false; }
            transcript = m.text || "";
            dictated(transcript, !!m.final);
            break;
        case "power":
            _settingOn = true; on = !!m.on; _settingOn = false;
            break;
        case "mode":
            _settingMode = true; approval = m.mode === "full" ? "full" : "approve"; _settingMode = false;
            break;
        case "error":
            error = m.error || "";
            console.warn("AI bridge:", m.op, m.error);
            break;
        }
    }

    function _showDemo() {
        chats = demoChats; projects = demoProjects; apps = demoApps; homeCards = demoCards;
        assistantName = "Assistant"; capabilities = [];
    }

    // backend chats → the panel's shape, keeping messages already loaded
    function _setChats(list) {
        const old = {};
        for (const c of chats) old[c.id] = c;
        const next = list.map(c => ({
            id: c.id, title: c.title || (old[c.id] && old[c.id].title) || "New chat", pinned: !!c.pinned, updated: c.updatedAt || 0,
            project: c.project || null,
            messages: old[c.id] && old[c.id].loaded ? old[c.id].messages : [], loaded: !!(old[c.id] && old[c.id].loaded)
        }));
        // a chat started here that the backend hasn't listed yet stays
        for (const c of chats) if (c.local && !next.find(n => n.id === c.id)) next.unshift(c);
        chats = next;
        const groups = {};
        for (const c of next) if (c.project) {
            groups[c.project.id] = groups[c.project.id] || { name: c.project.name, chats: [] };
            groups[c.project.id].chats.push(c.title);
        }
        projects = Object.keys(groups).map(k => groups[k]);
        const last = next.slice().sort((a, b) => b.updated - a.updated)[0];
        homeCards = last ? [{ label: "Continue", title: last.title, sub: _ago(last.updated), icon: "M5 5 H19 V15 H9 L5 19 Z", chat: last.id }] : [];
    }

    function _seconds(ms) { return ms >= 60000 ? Math.round(ms / 60000) + " min" : (ms / 1000).toFixed(1) + " s"; }
    function _tele(t) {
        if (!t) return "";
        const parts = [];
        if (t.tokensPerSecond) parts.push(Math.round(t.tokensPerSecond) + " tok/s");
        if (t.ttftMs) parts.push("TTFT " + (t.ttftMs / 1000).toFixed(2) + " s");
        if (t.tokensPerSecond) parts.push(Math.round(1000 / t.tokensPerSecond) + " ms/tok");
        return parts.join(" · ");
    }
    function _ago(ms) {
        if (!ms) return "";
        const s = (Date.now() - ms) / 1000;
        return s < 90 ? "Just now" : s < 5400 ? "Last message " + Math.round(s / 60) + " min ago"
            : s < 129600 ? "Last message " + Math.round(s / 3600) + " h ago" : "Last message " + Math.round(s / 86400) + " days ago";
    }
    function _message(m) {
        const mine = m.role === "user";
        return {
            who: mine ? "user" : "eve", text: m.text || "", files: m.files || [], images: m.images || [],
            worked: m.cancelled ? "stopped" : (!mine && m.telemetry && m.telemetry.totalMs ? _seconds(m.telemetry.totalMs) : ""),
            tele: mine ? "" : _tele(m.telemetry)
        };
    }

    // one reply's events, into the last message of its chat
    function _reply(m) {
        const edit = fn => {
            chats = chats.map(c => {
                if (c.id !== m.chat) return c;
                const msgs = c.messages.slice();
                const last = Object.assign({}, msgs[msgs.length - 1]);
                fn(last);
                msgs[msgs.length - 1] = last;
                return Object.assign({}, c, { messages: msgs });
            });
        };
        switch (m.type) {
        case "started":
            working = true;
            chats = chats.map(c => c.id !== m.chat ? c : Object.assign({}, c, { messages: c.messages.concat([{ who: "eve", text: "", worked: "", tele: "", footer: false }]) }));
            break;
        case "delta":
            edit(l => l.text = (l.text || "") + (m.text || ""));
            break;
        case "done":
            edit(l => { l.text = m.text || l.text; l.worked = m.telemetry && m.telemetry.totalMs ? _seconds(m.telemetry.totalMs) : ""; l.tele = _tele(m.telemetry); });
            _revealFooter(m.chat);
            break;
        case "cancelled":
            edit(l => l.worked = "stopped");
            _revealFooter(m.chat);
            break;
        case "error":
            edit(l => l.error = m.error || "Something went wrong");
            break;
        case "closed":
            working = false;
            loadChats();      // a new chat gets its name from the first exchange
            break;
        }
    }

    // a finished reply's footer (read aloud, copy, telemetry) comes in a second after it ends
    property string _revealChat: ""
    function _revealFooter(chat) { _revealChat = chat; revealTimer.restart(); }
    Timer {
        id: revealTimer
        interval: 1000
        onTriggered: root.chats = root.chats.map(c => c.id !== root._revealChat ? c
            : Object.assign({}, c, { messages: c.messages.map(x => x.footer === false ? Object.assign({}, x, { footer: true }) : x) }))
    }

    // ---------- what the panel calls ----------
    function loadChats() { if (live && can("history")) _send({ op: "chats" }); }
    function loadApps() {}
    function sendMessage(text) {
        text = text.trim();
        if (!text) return;
        let id = current;
        if (!id) {
            id = (live ? "tide-" : "local-") + Date.now().toString(16) + Math.floor(Math.random() * 0xffffff).toString(16);
            chats = [{ id: id, title: text.length > 48 ? text.slice(0, 46) + "…" : text, pinned: false, updated: Date.now(), messages: [], loaded: true, local: true }].concat(chats);
            current = id;
        }
        const files = attachments.slice();
        chats = chats.map(c => c.id !== id ? c : Object.assign({}, c, { messages: c.messages.concat([{ who: "user", text: text, files: files.map(a => a.name) }]) }));
        attachments = [];
        if (listening) cancelMic(); else listening = false;
        transcribing = false;
        if (!live) return;    // demo: the message only shows in the open chat
        _send({ op: "send", chat: id, text: text, think: think && can("thinking"),
                attachments: can("attachments") ? files.map(a => ({ name: a.name, path: a.path })) : [] });
    }
    function stop() {
        if (live && current && can("cancel")) _send({ op: "cancel", chat: current });
        else working = false;
    }
    // live transcription: the words fill the message box as you speak (the backend's
    // `voice.dictation`); stopping the mic settles them, and sending stops it first
    property string transcript: ""        // the dictation's text so far
    property bool transcribing: false     // stopped, final text on its way
    signal dictated(string text, bool final)
    function toggleMic() {
        if (!(live && can("voice.dictation"))) { listening = !listening; return; }
        if (listening) { listening = false; transcribing = true; _send({ op: "dictate", on: false }); }
        else { transcript = ""; listening = true; _send({ op: "dictate", on: true }); }
    }
    function cancelMic() { if (listening) { listening = false; _send({ op: "dictate", on: false, cancel: true }); } }
    function addAttachment(path) {
        path = path.trim();
        if (!path) return;
        const name = path.split("/").pop();
        const ext = (name.split(".").pop() || "").toLowerCase();
        const kind = ext === "pdf" ? "pdf" : ["csv", "xls", "xlsx", "ods"].indexOf(ext) >= 0 ? "sheet"
            : ["png", "jpg", "jpeg", "webp", "gif"].indexOf(ext) >= 0 ? "image" : "file";
        attachments = attachments.concat([{ name: name, path: path, kind: kind }]);
    }
    function removeAttachment(i) { attachments = attachments.filter((a, j) => j !== i); }

    // ---------- chat housekeeping ----------
    function newChat() { current = ""; closeApp(); }
    function openChat(id) {
        closeApp();
        current = id;
        if (live && can("history") && !id.startsWith("local-")) _send({ op: "messages", chat: id });
    }
    function pin(id) {
        const c = chats.find(x => x.id === id);
        chats = chats.map(c => c.id !== id ? c : Object.assign({}, c, { pinned: !c.pinned }));
        if (live && c) _send({ op: "pin", chat: id, pinned: !c.pinned });
    }
    function rename(id, title) {
        chats = chats.map(c => c.id !== id ? c : Object.assign({}, c, { title: title }));
        if (live) _send({ op: "rename", chat: id, title: title });
    }
    function remove(id) {
        chats = chats.filter(c => c.id !== id);
        if (current === id) current = "";
        if (live) _send({ op: "delete", chat: id });
    }

    // the header's power button and the Approve for me / Full access switch
    onOnChanged: if (!_settingOn && live && can("power")) _send({ op: "power", on: on })
    onApprovalChanged: if (!_settingMode && live && can("mode")) _send({ op: "mode", mode: approval === "full" ? "full" : "ask" })
    onOpenChanged: if (open && live) { loadChats(); if (current) openChat(current); }

    function toggle() { if (Theme.aiEnabled && (open || Session.useTool("eve"))) open = !open; }
    IpcHandler {
        target: "evepanel"
        function toggle(): void { root.toggle(); }
    }
    Connections { target: Theme; function onAiEnabledChanged() { if (!Theme.aiEnabled) root.open = false; } }

    // the AI API's app icon names (docs/AI-API.md), drawn like the rest of the panel's icons
    readonly property var appIcons: ({
        clock: "M12 4 A8 8 0 1 0 12.01 4 M12 8 V12 L15 14",
        mic: "M9 6 A3 3 0 0 1 15 6 V11 A3 3 0 0 1 9 11 Z M6 11 A6 6 0 0 0 18 11 M12 17 V21",
        book: "M5 4 H9 V20 H5 Z M11 4 H15 V20 H11 Z M17 5 L20 5.8 L16.4 20.2 L13.4 19.4",
        download: "M12 4 V15 M7 10 L12 15 L17 10 M5 20 H19",
        chart: "M4 20 V10 M10 20 V4 M16 20 V13 M22 20 H2",
        calendar: "M5 6 H19 V20 H5 Z M5 10 H19 M9 3 V7 M15 3 V7",
        server: "M4 4 H20 V11 H4 Z M4 13 H20 V20 H4 Z M8 7.5 L8.1 7.5 M8 16.5 L8.1 16.5",
        mail: "M4 6 H20 V18 H4 Z M4 7 L12 13 L20 7",
        grid: "M4 4 H11 V11 H4 Z M13 4 H20 V8 H13 Z M13 10 H20 V20 H13 Z M4 13 H11 V20 H4 Z",
        folder: "M3 7 A2 2 0 0 1 5 5 H9 L11 7 H19 A2 2 0 0 1 21 9 V17 A2 2 0 0 1 19 19 H5 A2 2 0 0 1 3 17 Z",
        star: "M12 4 L14.4 9 L19.8 9.6 L15.8 13.3 L16.9 18.6 L12 15.9 L7.1 18.6 L8.2 13.3 L4.2 9.6 L9.6 9 Z",
        heart: "M12 19 C5 14 4 10.5 4 8.5 A4 4 0 0 1 12 7 A4 4 0 0 1 20 8.5 C20 10.5 19 14 12 19 Z"
    })

    // ---------- the design's demo content (only while no backend is set up) ----------
    readonly property var demoChats: [
        { id: "print", title: "Why the print paused", pinned: true, messages: [
            { who: "user", text: "Why did the print fail last night?" },
            { who: "eve", text: "It didn’t fail, it paused. At 2:14 AM slot 2 ran out of orange PLA, about 54% of the way through.\n\nThe printer held its position, so the part is still on the bed and can pick up where it stopped.", worked: "8.4 s", tele: "41 tok/s · TTFT 0.42 s · 24 ms/tok" },
            { who: "user", text: "Can I resume it tomorrow morning?" },
            { who: "eve", text: "Yes, as long as the bed isn’t moved. I’ve kept the nozzle cool overnight and set a reminder so you reload slot 2 and resume first thing.", tool: "Reminder set · tomorrow 9:00 AM", worked: "3.1 s", tele: "46 tok/s · TTFT 0.37 s · 22 ms/tok" }
        ] },
        { id: "vram", title: "VRAM budget for the 32B model", pinned: true, messages: [] },
        { id: "ssl", title: "Barbershop site SSL renewal", pinned: false, messages: [] },
        { id: "kid", title: "Kid space game ideas", pinned: false, messages: [] },
        { id: "mon", title: "Monitor arrangement for the 32 inch", pinned: false, messages: [] },
        { id: "wave", title: "Quickshell wave seek bar", pinned: false, messages: [] }
    ]
    readonly property var demoProjects: [
        { name: "Hyprland mode system", chats: ["Island states for the coding agent", "Wallpaper picker grid", "Eve panel redesign"] },
        { name: "Gaming OS", chats: ["Installer flow", "Emulator plugin store"] },
        { name: "Tablet driver", chats: ["Run it as a service"] }
    ]
    readonly property var demoApps: [
        { name: "Daily briefing", icon: "M12 4 A8 8 0 1 0 12.01 4 M12 8 V12 L15 14" },
        { name: "Live", icon: "M9 6 A3 3 0 0 1 15 6 V11 A3 3 0 0 1 9 11 Z M6 11 A6 6 0 0 0 18 11 M12 17 V21" },
        { name: "Library", icon: "M5 4 H9 V20 H5 Z M11 4 H15 V20 H11 Z M17 5 L20 5.8 L16.4 20.2 L13.4 19.4" },
        { name: "Downloads", icon: "M12 4 V15 M7 10 L12 15 L17 10 M5 20 H19" },
        { name: "Finance", icon: "M4 20 V10 M10 20 V4 M16 20 V13 M22 20 H2" },
        { name: "Calendar", icon: "M5 6 H19 V20 H5 Z M5 10 H19 M9 3 V7 M15 3 V7" },
        { name: "Home lab", icon: "M4 4 H20 V11 H4 Z M4 13 H20 V20 H4 Z M8 7.5 L8.1 7.5 M8 16.5 L8.1 16.5" },
        { name: "Mail", icon: "M4 6 H20 V18 H4 Z M4 7 L12 13 L20 7" },
        { name: "Dashboard", icon: "M4 4 H11 V11 H4 Z M13 4 H20 V8 H13 Z M13 10 H20 V20 H13 Z M4 13 H11 V20 H4 Z" }
    ]
    readonly property var demoCards: [
        { label: "Daily briefing", title: "Tonight: 3 reminders, a paused print, 12 updates", sub: "Tap for the full rundown", icon: "M12 4 A8 8 0 1 0 12.01 4 M12 8 V12 L15 14", chat: "" },
        { label: "Home lab", title: "All 9 containers healthy", sub: "Barbershop site up · 182 ms", icon: "M4 4 H20 V11 H4 Z M4 13 H20 V20 H4 Z", draft: "How is the home lab doing?" },
        { label: "Continue", title: "Why the print paused", sub: "Last message 12 min ago", icon: "M5 5 H19 V15 H9 L5 19 Z", chat: "print" },
        { label: "Calendar", title: "Monitor delivery window", sub: "Monday · 10:00 AM", icon: "M5 6 H19 V20 H5 Z M5 10 H19 M9 3 V7 M15 3 V7", draft: "What’s on my calendar this week?" }
    ]
}
