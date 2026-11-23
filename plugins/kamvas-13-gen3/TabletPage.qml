import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

// Kamvas 13 Gen 3 · Tide Settings page (loaded by Settings → Tablet while this tablet
// is plugged in). Draws the tablet from engine/assets/tablets/definitions.py, shows
// each profile's mappings, and edits express keys and pen buttons in this plugin's
// own profiles.json (engine/tide_bridge.py). Tide hands in `theme`, `plugin` and `host`.
ColumnLayout {
    id: kp
    property var theme
    property var plugin
    property var host
    readonly property string sans: theme ? theme.sans : "Inter"
    // Tide's interface size (Appearance → Interface size)
    function s(px) { return theme ? theme.s(px) : px; }
    function sf(pt) { return theme ? theme.sf(pt) : pt; }
    spacing: kp.s(16)

    property var info: null
    property string profile: "krita"
    property string sel: "3"            // a slot id ("3"–"7", "11"–"13") or a dial ("d0", "d8")
    readonly property var prof: info ? (info.profiles.find(p => p.id === profile) || info.profiles[0]) : null
    readonly property string bridge: plugin ? plugin.dir + "/engine/tide_bridge.py" : ""

    function reload() { if (bridge) { dumper.command = ["python3", "-I", bridge, "dump"]; dumper.running = true; } }
    onBridgeChanged: reload()
    Process {
        id: dumper
        stdout: StdioCollector { onStreamFinished: { try { kp.info = JSON.parse(text); } catch (e) {} } }
    }
    Process { id: writer; onExited: kp.reload() }
    // the tablet app (or anything else) changing profiles.json shows up here too
    FileView {
        path: kp.plugin ? kp.plugin.dir + "/profiles.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: kp.reload()
    }
    function setKey(slot, keys, dbl) {
        writer.command = ["python3", "-I", bridge, "set-key", profile, String(slot), keys, dbl || ""];
        writer.running = true;
    }

    // ---------- helpers ----------
    function control(id) {
        if (!info) return null;
        if (id.startsWith("d")) return info.layout.controls.find(c => c.type === "dial" && c.id === id.slice(1));
        const c = info.layout.controls.find(c => c.type === "button" && String(c.id) === id);
        return c || info.layout.pen.find(p => String(p.id) === id);
    }
    function actionText(id) {
        if (!prof) return "";
        if (id.startsWith("d")) {
            const m = prof.dials[id.slice(1)];
            return m && m.length ? m.map(x => x.label).join(" · ") : "Not set";
        }
        const k = prof.keys[id];
        if (!k) return "Not set";
        return k.keys + (k.double ? "  ·  double: " + k.double : "");
    }
    function tc(c) { return theme ? theme[c] : "#F5F5F7"; }

    // ---------- header: profiles ----------
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: "Click any control to see what it does"
            color: kp.tc("muted"); font.family: kp.theme ? kp.theme.sans : "Inter"; font.pixelSize: kp.s(13)
        }
        Rectangle {
            implicitWidth: profRow.implicitWidth + kp.s(6); implicitHeight: kp.s(36); radius: kp.s(11)
            color: Qt.rgba(0, 0, 0, 0.3)
            Row {
                id: profRow
                x: kp.s(3); y: kp.s(3)
                spacing: kp.s(2)
                Repeater {
                    model: kp.info ? kp.info.profiles : []
                    delegate: Rectangle {
                        id: pb
                        required property var modelData
                        readonly property bool on: kp.profile === modelData.id
                        width: pl.implicitWidth + kp.s(28); height: kp.s(30); radius: kp.s(8)
                        color: on ? kp.tc("text") : pma.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                        Text { id: pl; anchors.centerIn: parent; text: pb.modelData.name; color: pb.on ? kp.tc("ink") : kp.tc("text2"); font.family: kp.theme ? kp.theme.sans : "Inter"; font.pixelSize: kp.s(12) }
                        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: kp.profile = pb.modelData.id }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: kp.s(18)

        // ---------- the drawing: tablet body (860×500 in definitions.py) and pen ----------
        Item {
            id: art
            Layout.preferredWidth: kp.s(520)
            Layout.preferredHeight: kp.s(380)
            Layout.alignment: Qt.AlignTop
            readonly property real bw: kp.s(520)
            readonly property real bh: kp.s(520) * 500 / 860
            Rectangle {
                width: art.bw; height: art.bh; radius: kp.s(22)
                gradient: Gradient { GradientStop { position: 0; color: "#2A2A2E" } GradientStop { position: 1; color: "#18181B" } }
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.08)
            }
            // the screen
            Rectangle {
                x: art.bw * 128 / 860; y: art.bh * 22 / 500
                width: art.bw * 716 / 860; height: art.bh * 456 / 500
                radius: kp.s(8)
                gradient: Gradient { GradientStop { position: 0; color: "#101014" } GradientStop { position: 1; color: "#08080A" } }
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.06)
                Text { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: kp.s(8); text: "13.3 in · 1920 × 1080"; color: kp.tc("dim"); font.family: kp.sans; font.pixelSize: kp.s(11) }
            }
            // the key strip
            Rectangle {
                visible: !!kp.info
                x: kp.info ? kp.info.layout.strip.x * art.bw : 0; y: kp.info ? kp.info.layout.strip.y * art.bh : 0
                width: kp.info ? kp.info.layout.strip.w * art.bw : 0; height: kp.info ? kp.info.layout.strip.h * art.bh : 0
                radius: width / 2
                color: Qt.rgba(0, 0, 0, 0.25)
            }
            Repeater {
                model: kp.info ? kp.info.layout.controls : []
                delegate: Rectangle {
                    id: ctl
                    required property var modelData
                    readonly property string key: modelData.type === "dial" ? "d" + modelData.id : String(modelData.id)
                    readonly property bool picked: kp.sel === key
                    readonly property real size: modelData.type === "dial" ? modelData.r * 2 * art.bw : 0
                    width: modelData.type === "dial" ? size : kp.s(30)
                    height: modelData.type === "dial" ? size : kp.s(22)
                    x: modelData.cx * art.bw - width / 2
                    y: modelData.cy * art.bh - height / 2
                    radius: height / 2
                    color: picked ? kp.tc("accent") : cma.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12)
                    border.width: modelData.type === "dial" ? 3 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.18)
                    Rectangle { visible: ctl.modelData.type === "dial"; anchors.centerIn: parent; width: parent.width * 0.42; height: width; radius: width / 2; color: Qt.rgba(0, 0, 0, 0.35) }
                    MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: kp.sel = ctl.key }
                }
            }
            // pen: body, tip and its three buttons
            Rectangle {
                x: kp.s(40); y: art.bh + kp.s(26); width: kp.s(400); height: kp.s(22); radius: kp.s(11)
                gradient: Gradient { GradientStop { position: 0; color: "#2E2E33" } GradientStop { position: 1; color: "#1A1A1D" } }
            }
            Shape {
                x: kp.s(440); y: art.bh + kp.s(26)
                ShapePath { fillColor: "#3A3A3F"; strokeWidth: -1; startX: 0; startY: 4; PathLine { x: kp.s(24); y: kp.s(11) } PathLine { x: 0; y: kp.s(18) } PathLine { x: 0; y: kp.s(4) } }
            }
            Repeater {
                model: kp.info ? kp.info.layout.pen : []
                delegate: Rectangle {
                    id: pen
                    required property var modelData
                    required property int index
                    readonly property bool picked: kp.sel === String(modelData.id)
                    x: kp.s(376) - index * kp.s(34); y: art.bh + kp.s(29)
                    width: kp.s(26); height: kp.s(16); radius: kp.s(8)
                    color: picked ? kp.tc("accent") : penMa.containsMouse ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.16)
                    MouseArea { id: penMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: kp.sel = String(pen.modelData.id) }
                }
            }
        }

        // ---------- the selected control, and every control in this profile ----------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: kp.s(12)

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: selCol.implicitHeight + kp.s(32)
                radius: kp.s(16)
                color: kp.theme ? kp.theme.tile : "#18181B"
                border.width: 1
                border.color: kp.theme ? kp.theme.accentLine : "transparent"
                ColumnLayout {
                    id: selCol
                    x: kp.s(16); y: kp.s(16)
                    width: parent.width - kp.s(32)
                    spacing: kp.s(8)
                    Text { text: kp.control(kp.sel) ? kp.control(kp.sel).label : ""; color: kp.tc("muted"); font.family: kp.sans; font.pixelSize: kp.s(12) }
                    Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: kp.actionText(kp.sel); color: kp.tc("text"); font.family: kp.sans; font.pixelSize: kp.s(18); font.weight: Font.Bold }
                    Text {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: kp.sel.startsWith("d")
                            ? "Press the dial to switch between these; turn it to use one. Dial modes are edited in the tablet app."
                            : "Type the keys to send, like ctrl+z or shift+a. Double: what a double tap then hold sends. Empty clears it."
                        color: kp.tc("text2"); font.family: kp.sans; font.pixelSize: kp.s(12)
                    }
                    // edit an express key or pen button
                    ColumnLayout {
                        visible: !kp.sel.startsWith("d")
                        Layout.fillWidth: true
                        spacing: kp.s(8)
                        KeyField { id: keysIn; Layout.fillWidth: true; hint: "Keys"; text: kp.prof && kp.prof.keys[kp.sel] ? kp.prof.keys[kp.sel].keys : "" }
                        KeyField { id: dblIn; Layout.fillWidth: true; hint: "Double tap (optional)"; text: kp.prof && kp.prof.keys[kp.sel] ? kp.prof.keys[kp.sel].double : "" }
                        Rectangle {
                            Layout.alignment: Qt.AlignRight
                            implicitWidth: saveT.implicitWidth + kp.s(28); implicitHeight: kp.s(32); radius: kp.s(9)
                            color: saveMa.containsMouse ? Qt.lighter(kp.tc("accent"), 1.12) : kp.tc("accent")
                            Text { id: saveT; anchors.centerIn: parent; text: "Save"; color: kp.tc("ink"); font.family: kp.sans; font.pixelSize: kp.s(12); font.weight: Font.DemiBold }
                            MouseArea { id: saveMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: kp.setKey(kp.sel, keysIn.text, dblIn.text) }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: listCol.implicitHeight
                radius: kp.s(16)
                color: kp.theme ? kp.theme.tile : "#18181B"
                clip: true
                Column {
                    id: listCol
                    width: parent.width
                    Repeater {
                        model: kp.info ? kp.info.layout.controls.map(c => c.type === "dial" ? { key: "d" + c.id, label: c.label } : { key: String(c.id), label: c.label })
                                          .concat(kp.info.layout.pen.map(p => ({ key: String(p.id), label: "Pen · " + p.label }))) : []
                        delegate: Rectangle {
                            id: li
                            required property var modelData
                            width: listCol.width; height: kp.s(34)
                            color: kp.sel === modelData.key ? Qt.rgba(1, 1, 1, 0.08) : lma.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"
                            Text { x: kp.s(14); anchors.verticalCenter: parent.verticalCenter; text: li.modelData.label; color: kp.tc("muted"); font.family: kp.sans; font.pixelSize: kp.s(12) }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: kp.s(14); anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * 0.55; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                                text: kp.actionText(li.modelData.key); color: kp.tc("text"); font.family: kp.sans; font.pixelSize: kp.s(12)
                            }
                            MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: kp.sel = li.modelData.key }
                        }
                    }
                }
            }
        }
    }

    // ---------- the full app ----------
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: kp.s(64)
        radius: kp.s(16)
        color: kp.theme ? kp.theme.tile : "#18181B"
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: kp.s(16); anchors.rightMargin: kp.s(16)
            Column {
                Layout.fillWidth: true
                spacing: kp.s(2)
                Text { text: "Pressure, buttons and dials"; color: kp.tc("text"); font.family: kp.sans; font.pixelSize: kp.s(13) }
                Text { text: "Capture new keys and edit dial modes in the tablet app (Tide's own copy)"; color: kp.tc("muted"); font.family: kp.sans; font.pixelSize: kp.s(12) }
            }
            Rectangle {
                implicitWidth: openT.implicitWidth + kp.s(28); implicitHeight: kp.s(32); radius: kp.s(9)
                color: openMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.1)
                Text { id: openT; anchors.centerIn: parent; text: "Open tablet app  ↗"; color: kp.tc("text"); font.family: kp.sans; font.pixelSize: kp.s(12) }
                MouseArea { id: openMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (kp.host) kp.host.openApp() }
            }
        }
    }

    component KeyField: Rectangle {
        id: kf
        property alias text: input.text
        property string hint
        implicitHeight: kp.s(36)
        radius: kp.s(10)
        color: Qt.rgba(0, 0, 0, 0.3)
        border.width: 1
        border.color: input.activeFocus ? (kp.theme ? kp.theme.accentLine : "white") : Qt.rgba(1, 1, 1, 0.1)
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: kp.s(12); anchors.rightMargin: kp.s(12)
            verticalAlignment: TextInput.AlignVCenter
            color: kp.tc("text"); font.family: kp.theme ? kp.theme.mono : "monospace"; font.pixelSize: kp.s(12)
            selectByMouse: true
            clip: true
            Text { visible: !input.text; anchors.verticalCenter: parent.verticalCenter; text: kf.hint; color: kp.tc("dim"); font.family: kp.sans; font.pixelSize: kp.s(12) }
        }
    }
}
