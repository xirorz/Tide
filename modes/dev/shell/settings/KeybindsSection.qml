import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"

// Settings → Keybinds: every bind in the Hyprland config (scripts/keybinds.py),
// grouped, with a search over actions and keys. Click a shortcut to change it: pick the
// modifiers, press the key (Hyprland would catch a held Super combo before Settings
// sees it, so modifiers are toggles), Save. scripts/keybind-set.py checks for clashes,
// keeps a backup, verifies the config and reloads Hyprland.
ColumnLayout {
    id: kb
    spacing: Theme.s(16)
    property var binds: []
    property string q: ""
    property int editLine: -1
    property string error: ""
    Process {
        id: setter
        stdout: StdioCollector {
            onStreamFinished: {
                let r = { ok: false, error: "Something went wrong." };
                try { r = JSON.parse(text); } catch (e) {}
                if (r.ok) { kb.editLine = -1; kb.error = ""; } else kb.error = r.error;
                kb.reload();
            }
        }
    }
    function save(b, raw) {
        error = "";
        const norm = s => s.split("+").map(x => x.trim().toLowerCase()).join("+");
        const clash = binds.find(o => o.line !== b.line && norm(o.raw) === norm(raw));
        if (clash) {
            error = raw.replace("SUPER", "Mod").replace("CTRL", "Ctrl").replace("SHIFT", "Shift").replace("ALT", "Alt") + " is already used by " + clash.action;
            return;
        }
        setter.command = ["python3", "-I", Quickshell.shellDir + "/scripts/keybind-set.py", String(b.line), b.raw, raw];
        setter.running = true;
    }
    // Qt key → Hyprland key name
    function keyName(e) {
        const k = e.key;
        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k);
        if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(k);
        if (k >= Qt.Key_F1 && k <= Qt.Key_F24) return "F" + (k - Qt.Key_F1 + 1);
        const named = {};
        named[Qt.Key_Return] = "RETURN"; named[Qt.Key_Enter] = "RETURN"; named[Qt.Key_Escape] = "ESCAPE";
        named[Qt.Key_Space] = "SPACE"; named[Qt.Key_Tab] = "TAB"; named[Qt.Key_Backspace] = "BACKSPACE";
        named[Qt.Key_Delete] = "DELETE"; named[Qt.Key_Home] = "HOME"; named[Qt.Key_End] = "END";
        named[Qt.Key_PageUp] = "Page_Up"; named[Qt.Key_PageDown] = "Page_Down"; named[Qt.Key_Insert] = "INSERT";
        named[Qt.Key_Left] = "left"; named[Qt.Key_Right] = "right"; named[Qt.Key_Up] = "up"; named[Qt.Key_Down] = "down";
        named[Qt.Key_Print] = "Print";
        if (named[k]) return named[k];
        const punct = { "-": "minus", "=": "equal", "[": "bracketleft", "]": "bracketright", ";": "semicolon", "'": "apostrophe",
                        ",": "comma", ".": "period", "/": "slash", "\\": "backslash", "`": "grave" };
        return punct[e.text] || "";
    }
    function reload() { reader.running = true; }
    Process {
        id: reader
        running: true
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/keybinds.py"]
        stdout: StdioCollector { onStreamFinished: { try { kb.binds = JSON.parse(text); } catch (e) {} } }
    }
    readonly property var order: ["Island and tools", "Screens and modes", "Windows and workspaces", "Apps and scripts", "Media and hardware"]
    readonly property var groups: {
        const ql = q.toLowerCase();
        const hit = b => !ql || b.action.toLowerCase().indexOf(ql) >= 0 || b.keys.toLowerCase().indexOf(ql) >= 0;
        return order.map(g => ({ title: g, rows: binds.filter(b => b.group === g && hit(b)) })).filter(g => g.rows.length > 0);
    }

    RowLayout {
        Layout.fillWidth: true
        Heading { Layout.fillWidth: true; text: "Keybinds" }
        Rectangle {
            implicitWidth: Theme.s(280); implicitHeight: Theme.s(36); radius: Theme.s(11)
            color: Qt.rgba(0, 0, 0, 0.3)
            border.width: 1; border.color: Theme.white(0.08)
            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.s(12); anchors.rightMargin: Theme.s(12)
                spacing: Theme.s(8)
                Icon { anchors.verticalCenter: parent.verticalCenter; path: "M16 16 L20 20 M11 5 A6 6 0 1 0 11.01 5"; size: Theme.s(14); color: Theme.muted }
                TextInput {
                    id: search
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.s(30)
                    color: Theme.text
                    font.family: Theme.sans; font.pointSize: Theme.sf(9.375)
                    selectByMouse: true
                    onTextChanged: kb.q = text
                    Text { visible: !search.text; text: "Search actions or keys"; color: Theme.dim; font: search.font }
                }
            }
        }
    }

    Repeater {
        model: kb.groups
        delegate: SCard {
            id: grp
            required property var modelData
            title: modelData.title
            Repeater {
                model: grp.modelData.rows
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool editing: kb.editLine === modelData.line
                    Layout.fillWidth: true
                    implicitHeight: Theme.s(46) + (editing ? editor.implicitHeight + Theme.s(12) : 0)
                    Rectangle { anchors.fill: parent; color: hov.hovered || row.editing ? Theme.white(0.04) : "transparent"; radius: 0 }
                    HoverHandler { id: hov }
                    Text { anchors.left: parent.left; anchors.leftMargin: Theme.s(16); y: Theme.s(23) - height / 2; text: row.modelData.action; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
                    HoverButton {
                        anchors.right: parent.right; anchors.rightMargin: Theme.s(10)
                        y: Theme.s(7)
                        width: keys.implicitWidth + Theme.s(20); height: Theme.s(32); radius: Theme.s(9)
                        hoverFill: false
                        enabled: row.modelData.editable
                        color: row.editing ? Theme.accent : hovered ? Theme.white(0.14) : Theme.white(0.08)
                        onClicked: {
                            kb.error = "";
                            kb.editLine = row.editing ? -1 : row.modelData.line;
                            if (kb.editLine >= 0) editor.start(row.modelData.raw);
                        }
                        Text { id: keys; anchors.centerIn: parent; text: row.modelData.keys; color: row.editing ? Theme.ink : Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                    }
                    // the editor: modifier toggles, the key, save
                    Column {
                        id: editor
                        visible: row.editing
                        x: Theme.s(16); y: Theme.s(50)
                        width: row.width - Theme.s(26)
                        spacing: Theme.s(8)
                        property var mods: ({ SUPER: false, CTRL: false, SHIFT: false, ALT: false })
                        property string key: ""
                        function start(raw) {
                            const parts = raw.split("+").map(s => s.trim());
                            const m = { SUPER: false, CTRL: false, SHIFT: false, ALT: false };
                            let k = "";
                            for (const p of parts) { const u = p.toUpperCase(); if (u in m) m[u] = true; else k = p; }
                            mods = m; key = k;
                            capture.forceActiveFocus();
                        }
                        readonly property string raw: ["SUPER", "CTRL", "SHIFT", "ALT"].filter(x => mods[x]).concat(key ? [key] : []).join(" + ")
                        Row {
                            spacing: Theme.s(6)
                            Repeater {
                                model: [["SUPER", "Mod"], ["CTRL", "Ctrl"], ["SHIFT", "Shift"], ["ALT", "Alt"]]
                                delegate: HoverButton {
                                    id: mb
                                    required property var modelData
                                    readonly property bool on: !!editor.mods[modelData[0]]
                                    width: mt.implicitWidth + Theme.s(22); height: Theme.s(30); radius: Theme.s(8)
                                    hoverFill: false
                                    color: on ? Theme.accent : hovered ? Theme.white(0.14) : Theme.white(0.08)
                                    onClicked: { const m = Object.assign({}, editor.mods); m[mb.modelData[0]] = !mb.on; editor.mods = m; capture.forceActiveFocus(); }
                                    Text { id: mt; anchors.centerIn: parent; text: mb.modelData[1]; color: mb.on ? Theme.ink : Theme.text2; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                                }
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "+"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(13); leftPadding: Theme.s(4); rightPadding: Theme.s(4) }
                            Rectangle {
                                width: Math.max(Theme.s(130), kt.implicitWidth + Theme.s(24)); height: Theme.s(30); radius: Theme.s(8)
                                color: Qt.rgba(0, 0, 0, 0.3)
                                border.width: 1
                                border.color: capture.activeFocus ? Theme.accentLine : Theme.white(0.1)
                                Text { id: kt; anchors.centerIn: parent; text: editor.key || "Press a key"; color: editor.key ? Theme.text : Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                                MouseArea { anchors.fill: parent; onClicked: capture.forceActiveFocus() }
                                Item {
                                    id: capture
                                    Keys.onPressed: e => {
                                        const n = kb.keyName(e);
                                        if (n) { editor.key = n; e.accepted = true; }
                                        else if (e.key !== Qt.Key_Shift && e.key !== Qt.Key_Control && e.key !== Qt.Key_Alt && e.key !== Qt.Key_Meta && e.key !== Qt.Key_Super_L) e.accepted = true;
                                    }
                                }
                            }
                        }
                        Row {
                            spacing: Theme.s(8)
                            HoverButton {
                                width: st1.implicitWidth + Theme.s(26); height: Theme.s(30); radius: Theme.s(8)
                                hoverFill: false
                                enabled: editor.key !== "" && editor.raw !== row.modelData.raw
                                opacity: enabled ? 1 : 0.4
                                color: hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
                                onClicked: kb.save(row.modelData, editor.raw)
                                Text { id: st1; anchors.centerIn: parent; text: "Save"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold }
                            }
                            HoverButton {
                                width: st2.implicitWidth + Theme.s(26); height: Theme.s(30); radius: Theme.s(8)
                                hoverFill: false
                                color: Theme.white(hovered ? 0.14 : 0.08)
                                onClicked: { kb.editLine = -1; kb.error = ""; }
                                Text { id: st2; anchors.centerIn: parent; text: "Cancel"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: kb.error; color: Theme.critical; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                        }
                    }
                    Rectangle { visible: row.index < grp.modelData.rows.length - 1; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.white(0.05) }
                }
            }
        }
    }
}
