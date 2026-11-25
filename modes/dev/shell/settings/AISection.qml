import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../components/Icons.js" as Icons
import "../services"

// Settings → AI: one switch for every AI piece in Tide, then the assistant it's connected
// to: whether it answers, what it can do (Tide shows only that), where Tide uses it, and how
// the connection is made (~/.config/Tide/ai.json → scripts/assistant-bridge.py → the
// assistant's AI API, docs/AI-API.md). Nothing here is tied to one assistant: it shows what
// the connected one says about itself.
ColumnLayout {
    id: ai
    spacing: Theme.s(18)

    readonly property string home: Quickshell.env("HOME")
    readonly property bool on: Theme.aiEnabled
    readonly property bool set: EveData.configured
    readonly property color dot: !set ? Theme.dim : EveData.connected ? "#30D158" : EveData.reachable ? Theme.warning : Theme.critical
    readonly property string statusText: !on ? "Off" : !set ? "Not set up" : EveData.connected ? "Connected" : EveData.reachable ? "Not ready" : "Can't be reached"

    // what each capability means, in words; Tide hides whatever the assistant lacks
    readonly property var features: [
        { key: "chat", name: "Chat", what: "Messages in the AI panel, with replies streamed as they're written" },
        { key: "history", name: "Chat history", what: "Your chats and projects in the panel's sidebar; pin, rename, delete" },
        { key: "cancel", name: "Stop a reply", what: "The stop button while it answers" },
        { key: "thinking", name: "Thinking", what: "The light bulb in the message box (off unless you turn it on)" },
        { key: "attachments", name: "Attachments", what: "Files and pictures from the + button" },
        { key: "approvals", name: "Approvals", what: "It asks before acting on your computer or servers" },
        { key: "mode", name: "Access mode", what: "Approve for me / Full access under the message box" },
        { key: "power", name: "Power", what: "The power button in the panel's header (loads or unloads its model)" },
        { key: "voice.dictation", name: "Live dictation", what: "The mic in the message box: your words appear as you speak" },
        { key: "voice.speech", name: "Read aloud", what: "The play button under replies, and Listen on the daily briefing" },
        { key: "voice.call", name: "Live calls", what: "Talk to it in the island (Super+Alt+E, or Talk to … in the launcher)" },
        { key: "live", name: "Live activity", what: "What it's doing step by step, in the island during calls" },
        { key: "apps", name: "Apps", what: "The Apps in the panel's sidebar" },
        { key: "appearance", name: "Your look", what: "Its own windows (like its browser) wear your wallpaper's accent" }
    ]
    function when(ms) {
        if (!ms) return "never";
        const s = (Date.now() - ms) / 1000;
        return s < 60 ? "just now" : s < 3600 ? Math.round(s / 60) + " min ago" : Math.round(s / 3600) + " h ago";
    }
    // refresh "checked … ago" while the page is open
    Timer { interval: 15000; running: ai.visible; repeat: true; onTriggered: ai.checkedText = ai.when(EveData.checkedAt) }
    property string checkedText: when(EveData.checkedAt)
    Connections { target: EveData; function onCheckedAtChanged() { ai.checkedText = ai.when(EveData.checkedAt); } }

    Heading { text: "AI"; sub: "Turn this off if you don't use an assistant: everything AI disappears from Tide, and nothing else changes." }
    SCard {
        SRow {
            last: true
            label: "AI features"
            sub: "The AI button in the bar, the AI panel, live calls in the island (Super+Alt+E) and Talk to … in the launcher"
            SToggle { on: Theme.aiEnabled; onToggled: Theme.set("aiEnabled", !on) }
        }
    }

    // ---------- the assistant ----------
    Text { visible: ai.on; text: "Connected assistant"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold; Layout.topMargin: Theme.s(4) }
    SCard {
        visible: ai.on
        SRow {
            label: ai.set ? (EveData.backendName || "Connected") : "No assistant set up"
            sub: !ai.set ? "The panel shows demo content until one is connected. Add one below by pasting its address."
                : EveData.connected ? "Answering and ready · checked " + ai.checkedText
                : EveData.reachable ? "Answering, not ready yet" + (EveData.detail ? ": " + EveData.detail : "")
                : "Not answering" + (EveData.detail ? ": " + EveData.detail : "")
            Row {
                spacing: Theme.s(10)
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.s(7)
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Theme.s(8); height: Theme.s(8); radius: Theme.s(4); color: ai.dot }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: ai.statusText; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                }
                SBtn { label: "Check again"; onClicked: EveData.reconnect() }
            }
        }
        SRow {
            visible: ai.set
            label: "Address"
            sub: (EveData.backendProtocol === "openai" ? "OpenAI-compatible server" : "Tide AI API") + " · the connection Tide talks through"
            Text { text: EveData.backendUrl; color: Theme.text2; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
        }
        SRow {
            visible: ai.set
            last: true
            label: "Used for"
            sub: "The AI panel (chats, apps, the mic), live calls in the island, and Talk to " + EveData.assistantName + " in the launcher"
            Text { text: EveData.capabilities.length + " of " + ai.features.length + " features"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
        }
    }

    // ---------- your assistants: add one by pasting its address ----------
    Text { visible: ai.on; text: "Assistants"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold; Layout.topMargin: Theme.s(4) }
    SCard {
        visible: ai.on
        Repeater {
            model: EveData.backends
            delegate: SRow {
                required property var modelData
                readonly property bool using: modelData.id === EveData.usingBackend
                label: modelData.name + (using ? "  ·  in use" : "")
                sub: (modelData.type === "openai" ? "OpenAI-compatible (chat only)" : "Tide AI API") + " · " + modelData.url + (modelData.token ? " · key saved" : "")
                Row {
                    spacing: Theme.s(8)
                    SBtn { visible: !using; label: "Use"; onClicked: EveData.useBackend(modelData.id) }
                    SBtn { label: "Remove"; onClicked: ai.removing = modelData.id === ai.removing ? "" : modelData.id }
                    SBtn { visible: ai.removing === modelData.id; primary: true; label: "Remove " + modelData.name; onClicked: { EveData.removeBackend(modelData.id); ai.removing = ""; } }
                }
            }
        }
        // the easy path: local AI apps already running on this computer, one click to connect
        SRow {
            label: EveData.discovered.length ? "Found on this computer" : "Add an AI"
            sub: EveData.discovered.length ? "AI apps running here right now. Connect one and chat with it in the AI panel."
                : "Start LM Studio, Ollama or another local AI app and it shows up here; or paste its address below."
            SBtn { label: "Look again"; onClicked: EveData.discover() }
        }
        Repeater {
            model: EveData.discovered
            delegate: SRow {
                required property var modelData
                padV: Theme.s(10)
                label: modelData.name
                sub: modelData.url + (modelData.protocol === "openai" ? " · chat" : " · Tide AI API")
                SBtn { primary: true; label: "Connect"; onClicked: EveData.addBackend(modelData.url, modelData.name, "") }
            }
        }
        SRow {
            last: true
            label: "Or paste an address"
            sub: "Where your AI app answers, like LM Studio's http://localhost:1234. Tide works out how to talk to it. A key is only needed for a server that asks for one, like a cloud service or a server on another machine."
            Text { visible: false; text: "" }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.s(16); Layout.rightMargin: Theme.s(16); Layout.bottomMargin: Theme.s(14)
            spacing: Theme.s(8)
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s(8)
                SField { id: newUrl; Layout.fillWidth: true; hint: "Address, e.g. http://localhost:1234" }
                SField { id: newName; Layout.preferredWidth: Theme.s(150); hint: "Name (optional)" }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s(8)
                SField { id: newKey; Layout.fillWidth: true; secret: true; hint: "API key, only if the server asks for one" }
                SBtn {
                    primary: true
                    label: EveData.probing ? "Connecting…" : "Connect"
                    onClicked: if (newUrl.text.trim() && !EveData.probing) EveData.addBackend(newUrl.text.trim(), newName.text.trim(), newKey.text.trim())
                }
            }
            Text {
                visible: !!EveData.probeResult
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: !EveData.probeResult ? "" : EveData.probeResult.ok
                    ? "Connected to " + (EveData.probeResult.name || "it") + " (" + (EveData.probeResult.protocol === "openai" ? "OpenAI-compatible, chat only" : "Tide AI API") + ") and now in use."
                    : EveData.probeResult.detail
                color: EveData.probeResult && EveData.probeResult.ok ? "#30D158" : Theme.warning
                font.family: Theme.sans; font.pixelSize: Theme.s(12)
            }
        }
    }
    SCard {
        visible: ai.on
        SRow {
            last: true
            label: "Your own custom AI?"
            sub: copied ? "Copied. Paste it to your coding agent and ask it to connect your assistant to Tide."
                : "If you built your own AI, give this guide to your coding agent: it explains how to connect any AI to Tide, with chat and as many extras as yours can do."
            property bool copied: false
            Row {
                spacing: Theme.s(8)
                SBtn { label: "Show file"; onClicked: Qt.openUrlExternally("file://" + ai.home + "/.config/Tide/docs") }
                SBtn {
                    primary: true
                    label: "Copy the guide"
                    onClicked: { Quickshell.execDetached(["sh", "-c", 'wl-copy < "$1"', "copy", ai.home + "/.config/Tide/docs/AI-API.md"]); parent.parent.parent.copied = true; }
                }
            }
        }
    }
    property string removing: ""          // the assistant whose Remove was pressed once (press again to confirm)
    Connections { target: EveData; function onProbeResultChanged() { if (EveData.probeResult && EveData.probeResult.saved) { newUrl.text = ""; newName.text = ""; newKey.text = ""; } } }
    Component.onCompleted: { EveData.listBackends(); EveData.discover(); }

    // ---------- what it can do ----------
    Text { visible: ai.on && ai.set; text: "What it can do"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold; Layout.topMargin: Theme.s(4) }
    Text {
        visible: ai.on && ai.set
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: "What " + (EveData.backendName || "it") + " says it supports. Tide shows only these; anything it doesn't support is left out of the panel and the island."
        color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12)
    }
    SCard {
        visible: ai.on && ai.set
        Repeater {
            model: ai.features
            delegate: SRow {
                required property var modelData
                required property int index
                readonly property bool has: EveData.can(modelData.key)
                last: index === ai.features.length - 1
                padV: Theme.s(10)
                label: modelData.name + (modelData.key === "apps" && has && EveData.apps.length ? " · " + EveData.apps.map(a => a.name).join(", ") : "")
                sub: modelData.what
                Row {
                    spacing: Theme.s(6)
                    Icon { anchors.verticalCenter: parent.verticalCenter; visible: has; path: Icons.check; size: Theme.s(14); stroke: 2.4; color: Theme.accent }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: has ? "On" : "Not offered"; color: has ? Theme.text2 : Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                }
            }
        }
    }

    // ---------- how it connects ----------
    Text { visible: ai.on; text: "How it connects"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold; Layout.topMargin: Theme.s(4) }
    SCard {
        visible: ai.on
        SRow {
            last: true
            label: "The bridge"
            sub: "scripts/assistant-bridge.py runs in the background while AI is on and does the talking: messages, voice, calls and apps."
            Text { text: EveData.reachable ? "Running" : "Waiting"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
        }
    }
}
