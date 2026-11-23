import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Io
import Quickshell.Widgets
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// Settings → Themes: every mode from the mode manager as a card with Apply (Mod+Ctrl+n
// for the first nine, Mod+T for the picker), and "Save current setup as new theme"
// (ThemeWizard.qml). Saved themes can be deleted; while a theme is locked in, nothing
// switches until time is up (services/Session.qml).
ColumnLayout {
    id: ts
    spacing: Theme.s(18)
    property bool wizard: false
    property string confirmDelete: ""
    function niceTime(hm) { const [h, m] = hm.split(":").map(Number); return (h % 12 || 12) + ":" + String(m).padStart(2, "0") + (h < 12 ? " AM" : " PM"); }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.s(20)
        Heading {
            Layout.fillWidth: true
            text: "Themes"
            sub: "A theme saves how your desktop looks and works right now. Add app limits and a timer to make it a focus session."
        }
        HoverButton {
            Layout.alignment: Qt.AlignBottom
            implicitWidth: saveRow.implicitWidth + Theme.s(36); implicitHeight: Theme.s(42); radius: Theme.s(13)
            hoverFill: false
            visible: !ts.wizard
            enabled: !Session.locked
            opacity: enabled ? 1 : 0.45
            color: hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
            onClicked: { wiz.reset(); ts.wizard = true; }
            Row {
                id: saveRow
                anchors.centerIn: parent
                spacing: Theme.s(8)
                Icon { anchors.verticalCenter: parent.verticalCenter; path: "M12 5 V19 M5 12 H19"; color: Theme.ink }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Save current setup as new theme"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold }
            }
        }
    }

    // Edit: read the theme's mode.json, then open the wizard on it
    Process {
        id: getter
        stdout: StdioCollector { onStreamFinished: { try { wiz.load(JSON.parse(text)); ts.wizard = true; } catch (e) {} } }
    }
    ThemeWizard {
        id: wiz
        visible: ts.wizard
        onClosed: ts.wizard = false
    }

    // a locked-in session: say so, and how to get out early
    Rectangle {
        visible: Session.active && !ts.wizard
        Layout.fillWidth: true
        implicitHeight: lockRow.implicitHeight + Theme.s(28)
        radius: Theme.s(16)
        color: Theme.accentSoft
        border.width: 1; border.color: Theme.accentLine
        Column {
            id: lockRow
            x: Theme.s(16); y: Theme.s(14)
            width: parent.width - Theme.s(32)
            spacing: Theme.s(2)
            Text { text: Session.name + (Session.secondsLeft >= 0 ? " · " + Session.left(Session.secondsLeft) + " left" : "") + (Session.locked ? " · locked in" : ""); color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: Session.locked ? "Themes can't be switched until time is up. Emergency exit: hold Mod + Esc for 5 seconds."
                    : (Session.s.limit ? "Apps that aren't allowed are set aside until it ends. " : "") + "Applying another theme ends it."
                color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12)
            }
        }
    }

    GridLayout {
        visible: !ts.wizard
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Theme.s(14)
        rowSpacing: Theme.s(14)
        uniformCellWidths: true
        Repeater {
            model: Modes.list
            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index
                // a saved theme says what it does: limits, timer, schedule
                readonly property string desc: {
                    const m = modelData;
                    if (!m.custom) return m.description;
                    const days = (m.days || []).slice().sort().join();
                    const when = !m.time ? "" : (days === "1,2,3,4,5" ? "weekdays" : days === "0,1,2,3,4,5,6" ? "every day" : (m.days || []).map(d => ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][d]).join(", ")) + " at " + ts.niceTime(m.time);
                    return [m.limit ? "Only " + (m.apps.join(", ") || "no apps") : "",
                            m.duration ? (m.duration >= 60 ? m.duration / 60 + " h" : m.duration + " min") : "",
                            when, m.lockout ? "locked in" : ""].filter(x => x).join(" · ") || "No limits";
                }
                readonly property color glow: modelData.art[0] || "#9A9AA0"
                Layout.fillWidth: true
                implicitHeight: Theme.s(110)
                radius: Theme.s(18)
                color: Theme.tile
                border.width: modelData.active ? 1.5 : 0
                border.color: Theme.accent
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.s(14)
                    spacing: Theme.s(14)
                    ClippingRectangle {
                        implicitWidth: Theme.s(132); implicitHeight: Theme.s(82); radius: Theme.s(11)
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0; color: card.modelData.art[1] || "#141416" }
                                GradientStop { position: 1; color: "#050507" }
                            }
                        }
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeWidth: -1
                                fillGradient: RadialGradient {
                                    centerX: Theme.s(33); centerY: Theme.s(25); centerRadius: Theme.s(100)
                                    focalX: Theme.s(33); focalY: Theme.s(25)
                                    GradientStop { position: 0; color: card.glow }
                                    GradientStop { position: 0.65; color: Qt.rgba(card.glow.r, card.glow.g, card.glow.b, 0) }
                                }
                                PathRectangle { width: Theme.s(132); height: Theme.s(82) }
                            }
                        }
                        Rectangle { x: Theme.s(6); y: Theme.s(5); width: parent.width - Theme.s(12); height: Theme.s(7); radius: Theme.s(4); color: Qt.rgba(0, 0, 0, 0.45) }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Theme.s(4)
                        Row {
                            spacing: Theme.s(8)
                            Text { anchors.verticalCenter: parent.verticalCenter; text: card.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(14); font.weight: Font.DemiBold }
                            Rectangle {
                                visible: card.modelData.active
                                anchors.verticalCenter: parent.verticalCenter
                                width: act.implicitWidth + Theme.s(14); height: act.implicitHeight + Theme.s(4); radius: Theme.s(8)
                                color: Theme.accent
                                Text { id: act; anchors.centerIn: parent; text: "Active"; color: Theme.ink; font.family: Theme.sans; font.pointSize: Theme.sf(7.875); font.weight: Font.DemiBold }
                            }
                        }
                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; text: card.desc; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s(8)
                        HoverButton {
                            implicitWidth: btnText.implicitWidth + Theme.s(24); implicitHeight: Theme.s(30); radius: Theme.s(9)
                            hoverFill: false
                            enabled: !card.modelData.active && !Session.locked
                            opacity: Session.locked && !card.modelData.active ? 0.45 : 1
                            color: card.modelData.active ? Theme.white(0.06) : hovered && enabled ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
                            onClicked: Modes.apply(card.modelData.id)
                            Text {
                                id: btnText
                                anchors.centerIn: parent
                                text: card.modelData.active ? "In use" : "Apply"
                                color: card.modelData.active ? Theme.muted : Theme.ink
                                font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium
                            }
                        }
                        Kbd { visible: card.index < 9; text: "Mod + Ctrl + " + (card.index + 1) }
                        Item { Layout.fillWidth: true }
                        // edit a saved theme (not while it's locked in)
                        HoverButton {
                            visible: card.modelData.custom
                            enabled: !Session.locked
                            opacity: enabled ? 1 : 0.4
                            implicitWidth: Theme.s(30); implicitHeight: Theme.s(30); radius: Theme.s(9)
                            hoverFill: false
                            color: Theme.white(hovered ? 0.12 : 0.06)
                            onClicked: { getter.command = [Modes.tool, "get", card.modelData.id]; getter.running = true; }
                            Icon { anchors.centerIn: parent; path: "M4 20 H8 L19 9 L15 5 L4 16 Z M13 7 L17 11"; size: Theme.s(15); color: Theme.text2 }
                        }
                        // delete a saved theme (asks once more first)
                        HoverButton {
                            visible: card.modelData.custom
                            enabled: !(Session.locked && Session.s.theme === card.modelData.id)
                            opacity: enabled ? 1 : 0.4
                            implicitWidth: ts.confirmDelete === card.modelData.id ? delText.implicitWidth + Theme.s(20) : Theme.s(30)
                            implicitHeight: Theme.s(30); radius: Theme.s(9)
                            hoverFill: false
                            color: ts.confirmDelete === card.modelData.id ? Theme.red : Theme.white(hovered ? 0.12 : 0.06)
                            onClicked: {
                                if (ts.confirmDelete === card.modelData.id) { Modes.remove(card.modelData.id); ts.confirmDelete = ""; }
                                else { ts.confirmDelete = card.modelData.id; delReset.restart(); }
                            }
                            Timer { id: delReset; interval: 4000; onTriggered: ts.confirmDelete = "" }
                            Icon { visible: ts.confirmDelete !== card.modelData.id; anchors.centerIn: parent; path: "M5 7 H19 M10 7 V5 H14 V7 M7 7 L8 19 H16 L17 7"; size: Theme.s(15); color: Theme.text2 }
                            Text { id: delText; visible: ts.confirmDelete === card.modelData.id; anchors.centerIn: parent; text: "Delete?"; color: "#FFFFFF"; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold }
                        }
                        }
                    }
                }
            }
        }
    }

    Text { visible: Modes.error !== "" && !ts.wizard; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: Modes.error; color: Theme.red; font.family: Theme.sans; font.pixelSize: Theme.s(12) }

    Rectangle {
        visible: !ts.wizard
        Layout.fillWidth: true
        implicitHeight: Theme.s(64)
        radius: Theme.s(16)
        color: Theme.tile
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.s(16); anchors.rightMargin: Theme.s(16)
            Column {
                Layout.fillWidth: true
                spacing: Theme.s(2)
                Text { text: "Quick theme picker"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold }
                Text { text: "Switch themes from the island without opening settings"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            }
            Kbd { text: "Mod + T" }
        }
    }
}
