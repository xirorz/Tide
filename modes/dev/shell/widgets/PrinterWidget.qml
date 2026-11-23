import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// 3D printer (the design's "Bambu Lab" card, LabWidgets): status pill, the job and its
// progress, time left and when it's done, nozzle, bed and the AMS spools. The design's
// live camera is left out for now. Light, Pause / Resume and Stop (with the design's
// "Stop print? It can't resume") work in LAN mode only; if the printer refuses or
// doesn't answer, they grey out and the card says why. Data: services/Printer.qml.
// Small keeps the name, status, progress and time left (no temperatures or controls).
Item {
    id: pw
    property string size: "medium"
    readonly property bool small: size === "small"
    implicitWidth: Theme.s(small ? 280 : 440)
    implicitHeight: col.implicitHeight + Theme.s(36)

    readonly property var j: Printer.job
    // a failed or stopped job stays "FAILED" on the printer until the next print; with
    // nothing printing that reads as Idle, with a note about the last print
    readonly property string st: Printer.status === "error" ? "idle" : Printer.status
    readonly property bool lastFailed: Printer.status === "error"
    function code(e) { const h = (e >>> 0).toString(16).toUpperCase().padStart(8, "0"); return h.slice(0, 4) + "-" + h.slice(4); }
    readonly property bool active: st === "printing" || st === "paused"
    readonly property bool ctl: Printer.online && Printer.controlsOk
    property bool confirming: false
    Timer { id: unconfirm; interval: 4000; onTriggered: pw.confirming = false }

    function timeLeft(m) { return m < 0 ? "" : m >= 60 ? Math.floor(m / 60) + " h " + (m % 60) + " min" : m + " min"; }
    function doneAt(m) { return Qt.formatTime(new Date(Date.now() + m * 60000), "h:mm AP"); }
    readonly property var activeTray: (j.trays || []).find(t => t.active)

    readonly property var pill: ({
        printing: [j.preparing ? "Preparing" : "Printing", Theme.accent],
        paused: ["Paused", Theme.accent],
        finished: ["Finished", Theme.accent],
        error: ["Error", Theme.red],
        idle: ["Idle", Theme.text2],
        offline: ["Offline", Theme.muted],
        setup: ["Not set up", Theme.muted]
    })[st] || ["", Theme.muted]

    component Btn: HoverButton {
        id: btn
        property string label
        property string icon
        property bool fill: false
        property color tint: Theme.text
        Layout.fillWidth: label !== ""
        implicitWidth: label ? row.implicitWidth + Theme.s(24) : Theme.s(40)
        implicitHeight: Theme.s(40)
        radius: Theme.s(12)
        hoverFill: false
        enabled: pw.ctl && !Printer.busy
        opacity: enabled ? 1 : 0.4
        color: hovered && enabled ? Theme.white(0.18) : Theme.white(0.12)
        Row {
            id: row
            anchors.centerIn: parent
            spacing: Theme.s(8)
            Icon { visible: btn.icon !== ""; anchors.verticalCenter: parent.verticalCenter; path: btn.icon; size: Theme.s(16); color: btn.tint }
            Text { visible: btn.label !== ""; anchors.verticalCenter: parent.verticalCenter; text: btn.label; color: btn.tint; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.Medium }
        }
        onHoveredChanged: tip.show(hovered)
    }

    ColumnLayout {
        id: col
        x: Theme.s(18); y: Theme.s(18)
        width: pw.implicitWidth - Theme.s(36)
        spacing: Theme.s(14)

        // header: name and status
        RowLayout {
            Layout.fillWidth: true
            Row {
                Layout.fillWidth: true
                spacing: Theme.s(10)
                Icon { anchors.verticalCenter: parent.verticalCenter; path: "M5 20h14M7 20V9h10v11M9 9V5h6v4M10 13h4"; size: Theme.s(18); color: Theme.text }
                Text { anchors.verticalCenter: parent.verticalCenter; text: Printer.modelName ? (pw.small ? Printer.modelName : "Bambu Lab " + Printer.modelName) : "Bambu Lab"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
            }
            Rectangle {
                implicitHeight: Theme.s(28); implicitWidth: pillRow.implicitWidth + Theme.s(24); radius: Theme.s(14)
                color: Qt.rgba(pw.pill[1].r, pw.pill[1].g, pw.pill[1].b, 0.16)
                Row {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: Theme.s(8)
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Theme.s(7); height: Theme.s(7); radius: Theme.s(4); color: pw.pill[1] }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: pw.pill[0]; color: pw.pill[1]; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium }
                }
            }
        }

        // not set up, or can't reach it
        Text {
            visible: pw.st === "setup" || pw.st === "offline"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: pw.st === "setup" ? "Set up the printer in Settings → Widgets → 3D printer."
                : (Printer.error || "Can't reach printer") + (Printer.seen ? " · last seen " + Qt.formatDateTime(new Date(Printer.seen * 1000), "h:mm AP") : "")
            color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(13)
        }

        // the job and its progress
        ColumnLayout {
            visible: Printer.online
            Layout.fillWidth: true
            spacing: Theme.s(8)
            RowLayout {
                Layout.fillWidth: true
                Column {
                    Layout.fillWidth: true
                    spacing: Theme.s(2)
                    Text { width: parent.width; elide: Text.ElideRight; text: pw.j.file || (pw.st === "idle" ? "Nothing printing" : ""); color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(14); font.weight: Font.DemiBold }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: pw.active ? ((pw.j.layers > 0 ? "Layer " + pw.j.layer + " of " + pw.j.layers : "") + (pw.activeTray && pw.activeTray.type ? " · " + pw.activeTray.type : ""))
                            : pw.st === "finished" ? "Finished" : pw.lastFailed ? "Last print stopped with an error" + (pw.j.error ? " (" + pw.code(pw.j.error) + ")" : "") : "Ready"
                        color: pw.lastFailed ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.85) : Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                    }
                }
                Text { visible: pw.st !== "idle"; text: (pw.j.percent || 0) + "%"; color: Theme.accent; font.family: Theme.mono; font.pixelSize: Theme.s(30); font.weight: Font.Medium }
            }
            Rectangle {
                visible: pw.st !== "idle"
                Layout.fillWidth: true
                implicitHeight: Theme.s(8); radius: Theme.s(4)
                color: Theme.white(0.12)
                Rectangle { width: parent.width * Math.min(1, (pw.j.percent || 0) / 100); height: parent.height; radius: parent.radius; color: Theme.accent }
            }
            RowLayout {
                visible: pw.active || pw.st === "finished"
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: pw.active ? (pw.st === "paused" ? "Paused · " : "") + pw.timeLeft(pw.j.minutesLeft) + " left" : pw.st === "finished" ? "Ready to remove" : ""
                    color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                }
                Text {
                    visible: !pw.small
                    text: pw.st === "printing" && pw.j.minutesLeft >= 0 ? "Done around " + pw.doneAt(pw.j.minutesLeft) : pw.st === "finished" && pw.j.bed > 0 ? "Bed cooling · " + pw.j.bed + "°" : ""
                    color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                }
            }
        }

        // temperatures and spools, under a hairline
        Rectangle { visible: Printer.online && !pw.small; Layout.fillWidth: true; implicitHeight: 1; color: Theme.white(0.08) }
        RowLayout {
            visible: Printer.online && !pw.small
            Layout.fillWidth: true
            spacing: Theme.s(18)
            Column {
                spacing: Theme.s(2)
                Text { text: "Nozzle"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                Text { text: pw.j.nozzle + "°" + (pw.j.nozzleTarget > 0 ? " / " + pw.j.nozzleTarget + "°" : ""); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
            }
            Column {
                spacing: Theme.s(2)
                Text { text: "Bed"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                Text { text: pw.j.bed + "°" + (pw.j.bedTarget > 0 ? " / " + pw.j.bedTarget + "°" : ""); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
            }
            Item { Layout.fillWidth: true }
            Column {
                visible: (pw.j.trays || []).length > 0
                spacing: Theme.s(4)
                Text { anchors.right: parent.right; text: "Filament"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                Row {
                    spacing: Theme.s(6)
                    Repeater {
                        model: pw.j.trays || []
                        delegate: Rectangle {
                            required property var modelData
                            width: Theme.s(20); height: Theme.s(20); radius: Theme.s(10)
                            color: modelData.color
                            border.width: modelData.active ? Theme.s(1.5) : 1
                            border.color: modelData.active ? Theme.text : Theme.white(0.25)
                        }
                    }
                }
            }
        }

        // controls (LAN mode)
        RowLayout {
            visible: Printer.online && !pw.small
            Layout.fillWidth: true
            spacing: Theme.s(8)
            Btn {
                visible: pw.active && !pw.confirming
                label: pw.st === "paused" ? "Resume" : "Pause"
                icon: pw.st === "paused" ? "M8 5 L19 12 L8 19 Z" : "M8 5 V19 M16 5 V19"
                onClicked: Printer.send(pw.st === "paused" ? "resume" : "pause")
            }
            Btn {
                visible: pw.active && !pw.confirming
                label: "Stop"
                icon: "M7 7 H17 V17 H7 Z"
                onClicked: { pw.confirming = true; unconfirm.restart(); }
            }
            Btn {
                visible: pw.confirming
                label: "Stop print? It can't resume"
                tint: "#FFFFFF"
                color: hovered && enabled ? Qt.lighter(Theme.red, 1.1) : Theme.red
                onClicked: { pw.confirming = false; Printer.send("stop"); }
            }
            Item { visible: !pw.active; Layout.fillWidth: true }
            Btn {
                icon: "M9 18h6M10 21h4M12 3a6 6 0 00-4 10.5c.7.7 1 1.5 1 2.5h6c0-1 .3-1.8 1-2.5A6 6 0 0012 3z"
                tint: pw.j.light === "on" ? Theme.accent : Theme.text
                onClicked: Printer.send(pw.j.light === "on" ? "light-off" : "light-on")
            }
        }
        // why the controls are off, or the LAN note on hover
        Text {
            id: tip
            function show(on) { hover = on; }
            property bool hover: false
            visible: Printer.online && !pw.small && (!Printer.controlsOk || hover)
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: (Printer.controlsOk || !Printer.reason ? "" : Printer.reason.startsWith("No answer") ? Printer.reason + ". " : "The printer refused it (" + Printer.reason + "). ") + Printer.lanNote
            color: Printer.controlsOk ? Theme.muted : Theme.text2
            font.family: Theme.sans; font.pixelSize: Theme.s(11)
        }
    }
}
