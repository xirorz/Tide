import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// Settings → Widgets: on/off, which screen they live on (handy on a second screen),
// which widgets show, and the weather's place and units. Moving them is done on the
// desktop with "Edit widgets".
ColumnLayout {
    id: ws
    spacing: Theme.s(18)
    Heading { text: "Widgets"; sub: "Calm widgets on your desktop, under your windows. Use “Edit widgets” on the desktop to move, add or remove them." }

    SCard {
        SRow {
            label: "Desktop widgets"
            SToggle { on: Widgets.enabled; onToggled: Widgets.setEnabled(!on) }
        }
        SRow {
            label: "Show them on"
            sub: "A screen other than your main one keeps them out from under your windows"
            SDropdown {
                mono: false
                interactive: Widgets.enabled
                options: [{ label: "Main screen (" + Theme.monitor + ")", value: "" }].concat(Quickshell.screens.filter(s => s.name !== Theme.monitor).map(s => ({ label: s.name + (s.model ? " · " + s.model : ""), value: s.name })))
                value: Widgets.screen
                onPicked: v => Widgets.save({ screen: v })
            }
        }
        SRow {
            label: "Clock font"
            sub: "The big clock's own font"
            SDropdown {
                mono: false
                options: Fonts.clockFonts.map(f => ({ label: f.label, value: f.value, family: f.value }))
                value: Widgets.clockFont.value
                onPicked: v => Widgets.save({ clockFont: v })
            }
        }
        SRow {
            label: "Clock color"
            sub: "White, or the accent from your wallpaper"
            SSegment {
                options: [{ label: "White", value: "white" }, { label: "Wallpaper accent", value: "accent" }]
                value: Widgets.clockColor
                onPicked: v => Widgets.save({ clockColor: v })
            }
        }
        SRow {
            label: "Clock shadow"
            sub: "A soft shadow that keeps the clock readable on light wallpapers"
            SToggle { on: Widgets.clockShadow; onToggled: Widgets.save({ clockShadow: !on }) }
        }
        SRow {
            label: "Card style"
            sub: "Widgets keep their cards whatever the bar style; the clock has none"
            SSegment {
                options: [{ label: "Match the bar", value: "bar" }, { label: "Dark", value: "dark" }, { label: "Glass", value: "glass" }]
                value: Widgets.cardStyle
                onPicked: v => Widgets.save({ cardStyle: v })
            }
        }
        SRow {
            last: true
            label: "Layout"
            sub: "Put every widget back where the design has it, at its normal size"
            HoverButton {
                implicitWidth: rl.implicitWidth + Theme.s(28); implicitHeight: Theme.s(32); radius: Theme.s(9)
                enabled: Widgets.enabled
                opacity: enabled ? 1 : 0.4
                hoverFill: false
                color: Theme.white(hovered ? 0.14 : 0.08)
                onClicked: Widgets.resetLayout()
                Text { id: rl; anchors.centerIn: parent; text: "Reset layout"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            }
        }
    }

    SCard {
        title: "Widgets"
        Repeater {
            model: Widgets.catalog
            delegate: SRow {
                required property var modelData
                required property int index
                last: index === Widgets.catalog.length - 1
                label: modelData.label
                SToggle {
                    interactive: Widgets.enabled
                    on: Widgets.has(parent.parent.modelData.type)
                    onToggled: on ? Widgets.remove(parent.parent.modelData.type) : Widgets.add(parent.parent.modelData.type)
                }
            }
        }
    }

    SCard {
        title: "System widget"
        Repeater {
            model: [{ key: "cpu", label: "CPU" }, { key: "memory", label: "Memory" }, { key: "gpu", label: "GPU" },
                    { key: "network", label: "Network", sub: "Download and upload, with the last minute" }, { key: "drives", label: "Drives" }]
            delegate: SRow {
                required property var modelData
                required property int index
                label: modelData.label
                sub: modelData.sub || ""
                SToggle { on: Widgets.systemShows(modelData.key); onToggled: Widgets.setSystemShows(modelData.key, !on) }
            }
        }
        // the drives list, shared with the resource center and the fill alerts (services/Drives.qml)
        SRow {
            label: "Drives"
            sub: "Shown here, in the resource center and in the fill alerts. Type a mount path like / or /mnt/data, then Enter"
            Rectangle {
                implicitWidth: Theme.s(240); implicitHeight: Theme.s(34); radius: Theme.s(10)
                color: Qt.rgba(0, 0, 0, 0.3)
                border.width: 1; border.color: drivePath.activeFocus ? Theme.accentLine : Theme.white(0.1)
                TextInput {
                    id: drivePath
                    anchors.fill: parent; anchors.leftMargin: Theme.s(12); anchors.rightMargin: Theme.s(12)
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(12)
                    onAccepted: Drives.add(text)
                    onTextChanged: Drives.addMessage = ""
                    Connections { target: Drives; function onAddOkChanged() { if (Drives.addOk) drivePath.text = ""; } }
                    Text { visible: !drivePath.text; anchors.verticalCenter: parent.verticalCenter; text: "Add a drive: /mnt/…"; color: Theme.dim; font: drivePath.font }
                }
            }
        }
        Text {
            visible: Drives.addMessage !== ""
            Layout.fillWidth: true
            leftPadding: Theme.s(16); rightPadding: Theme.s(16); bottomPadding: Theme.s(10)
            wrapMode: Text.WordWrap
            text: Drives.addMessage
            color: Drives.addOk ? Theme.text2 : Theme.red
            font.family: Theme.sans; font.pixelSize: Theme.s(12)
        }
        Repeater {
            model: Drives.chosen
            delegate: Item {
                id: dr
                required property var modelData
                required property int index
                readonly property var info: Drives.list[index] || ({})
                Layout.fillWidth: true
                implicitHeight: Theme.s(52)
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.white(0.06) }
                Rectangle {
                    id: nameBox
                    x: Theme.s(16); anchors.verticalCenter: parent.verticalCenter
                    width: Theme.s(150); height: Theme.s(30); radius: Theme.s(8)
                    color: nameIn.activeFocus ? Qt.rgba(0, 0, 0, 0.3) : "transparent"
                    border.width: 1; border.color: nameIn.activeFocus ? Theme.accentLine : "transparent"
                    TextInput {
                        id: nameIn
                        anchors.fill: parent; anchors.leftMargin: Theme.s(8); anchors.rightMargin: Theme.s(8)
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        text: dr.modelData.name
                        color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13)
                        onEditingFinished: if (text !== dr.modelData.name) Drives.rename(dr.index, text)
                    }
                }
                Column {
                    anchors.left: nameBox.right; anchors.leftMargin: Theme.s(10)
                    anchors.right: btns.left; anchors.rightMargin: Theme.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.s(5)
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: dr.info.missing ? dr.modelData.path + " · not mounted"
                            : dr.info.size ? (dr.info.mount + " · " + Drives.gb(dr.info.used) + " of " + Drives.gb(dr.info.size) + " · " + dr.info.pct + "%") : dr.modelData.path
                        color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11)
                    }
                    Rectangle {
                        visible: !!dr.info.size
                        width: parent.width; height: Theme.s(4); radius: Theme.s(2)
                        color: Theme.white(0.18)
                        Rectangle { width: parent.width * (dr.info.pct || 0) / 100; height: parent.height; radius: parent.radius; color: dr.info.pct >= 90 ? Theme.red : Theme.accent }
                    }
                }
                Row {
                    id: btns
                    anchors.right: parent.right; anchors.rightMargin: Theme.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.s(4)
                    Repeater {
                        model: [{ t: "↑", by: -1 }, { t: "↓", by: 1 }, { t: "×", by: 0 }]
                        delegate: HoverButton {
                            required property var modelData
                            readonly property bool can: modelData.by === 0 || (dr.index + modelData.by >= 0 && dr.index + modelData.by < Drives.chosen.length)
                            width: Theme.s(28); height: Theme.s(28); radius: Theme.s(8)
                            enabled: can
                            opacity: can ? 1 : 0.3
                            onClicked: modelData.by === 0 ? Drives.remove(dr.index) : Drives.move(dr.index, modelData.by)
                            Text { anchors.centerIn: parent; text: parent.modelData.t; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(14) }
                        }
                    }
                }
            }
        }
        SRow {
            last: true
            label: "Reset to detected drives"
            sub: "Replace the list with every drive that's mounted now"
            HoverButton {
                implicitWidth: rd.implicitWidth + Theme.s(28); implicitHeight: Theme.s(32); radius: Theme.s(9)
                hoverFill: false
                color: Theme.white(hovered ? 0.14 : 0.08)
                onClicked: Drives.resetToDetected()
                Text { id: rd; anchors.centerIn: parent; text: "Reset"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            }
        }
    }

    // 3D printer (Bambu Lab, local network): services/Printer.qml
    SCard {
        title: "3D printer"
        Component.onCompleted: Printer.refreshCode()
        SRow {
            label: "Find printer"
            sub: Printer.finding ? "Listening for printers on your network…"
                : Printer.found.length ? "Pick one to fill in the details below"
                : "Bambu printers announce themselves on the network; if yours doesn't show up, type its details"
            HoverButton {
                implicitWidth: fp.implicitWidth + Theme.s(28); implicitHeight: Theme.s(32); radius: Theme.s(9)
                hoverFill: false
                opacity: Printer.finding ? 0.5 : 1
                color: Theme.white(hovered ? 0.14 : 0.08)
                onClicked: Printer.find()
                Text { id: fp; anchors.centerIn: parent; text: Printer.finding ? "Finding…" : "Find printer"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            }
        }
        Repeater {
            model: Printer.found
            delegate: HoverButton {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Theme.s(38); radius: 0
                onClicked: Printer.save({ host: modelData.host, serial: modelData.serial, model: Printer.niceModel(modelData.model) })
                Text { x: Theme.s(16); anchors.verticalCenter: parent.verticalCenter; text: (parent.modelData.name || Printer.niceModel(parent.modelData.model) || "Printer") + "  ·  " + parent.modelData.host + "  ·  " + parent.modelData.serial; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
            }
        }
        // Find heard nothing: why, and the firewall command that fixes it (with Allow)
        ColumnLayout {
            visible: !Printer.finding && Printer.findDone && Printer.found.length === 0
            Layout.fillWidth: true
            Layout.leftMargin: Theme.s(16); Layout.rightMargin: Theme.s(16); Layout.bottomMargin: Theme.s(14)
            spacing: Theme.s(10)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Printer.fw.fw === "ufw" || Printer.fw.fw === "firewalld"
                    ? "No printer answered. Your firewall (" + Printer.fw.fw + ") is on and likely blocks the printers' announcements (UDP port 2021). Allow them from your network" + (Printer.fw.subnet ? " (" + Printer.fw.subnet + ")" : "") + " with:"
                    : Printer.fw.fw === "none"
                    ? "No printer answered, and no firewall is blocking it. The printer may be asleep or on another network (a guest Wi-Fi or VLAN). Type its IP address and serial below instead."
                    : "No printer answered."
                color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12)
            }
            Rectangle {
                visible: !!Printer.fw.cmd
                Layout.fillWidth: true
                implicitHeight: cmdText.implicitHeight + Theme.s(20)
                radius: Theme.s(10)
                color: Qt.rgba(0, 0, 0, 0.35)
                border.width: 1; border.color: Theme.white(0.08)
                TextEdit {
                    id: cmdText
                    x: Theme.s(12); y: Theme.s(10)
                    width: parent.width - Theme.s(24)
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    text: Printer.fw.cmd ? "sudo " + Printer.fw.cmd.replace("&& firewall-cmd", "&& sudo firewall-cmd") : ""
                    color: Theme.text; selectionColor: Theme.white(0.25)
                    font.family: Theme.mono; font.pixelSize: Theme.s(12)
                }
            }
            Row {
                visible: !!Printer.fw.cmd
                spacing: Theme.s(8)
                HoverButton {
                    implicitWidth: al.implicitWidth + Theme.s(28); implicitHeight: Theme.s(32); radius: Theme.s(9)
                    hoverFill: false
                    color: hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
                    onClicked: Printer.allowFind()
                    Text { id: al; anchors.centerIn: parent; text: "Allow and find again"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold }
                }
                HoverButton {
                    id: copyBtn
                    property bool copied: false
                    implicitWidth: cp.implicitWidth + Theme.s(28); implicitHeight: Theme.s(32); radius: Theme.s(9)
                    hoverFill: false
                    color: Theme.white(hovered ? 0.14 : 0.08)
                    onClicked: { Quickshell.execDetached(["wl-copy", cmdText.text]); copied = true; copiedReset.restart(); }
                    Timer { id: copiedReset; interval: 1500; onTriggered: copyBtn.copied = false }
                    Text { id: cp; anchors.centerIn: parent; text: copyBtn.copied ? "Copied" : "Copy"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                }
            }
            Text {
                visible: !!Printer.fw.cmd
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Printer.allowError || "Allow asks for your system password (Tide never sees it), runs the command, then looks for the printer again."
                color: Printer.allowError ? Theme.red : Theme.muted
                font.family: Theme.sans; font.pixelSize: Theme.s(11)
            }
        }
        SRow { label: "Model"; sub: "For the card's title, like P1S or X1C"; SField { text: Printer.model; hint: "P1S"; onDone: v => { if (v.trim() !== Printer.model) Printer.save({ model: v.trim() }); } } }
        SRow { label: "IP address"; sub: "On the printer: Settings → Network"; SField { text: Printer.host; hint: "192.168.1.50"; onDone: v => { if (v.trim() !== Printer.host) Printer.save({ host: v.trim() }); } } }
        SRow { label: "Serial number"; sub: "On the printer: Settings → Device"; SField { text: Printer.serial; hint: "01P00A…"; onDone: v => { if (v.trim() !== Printer.serial) Printer.save({ serial: v.trim().toUpperCase() }); } } }
        SRow {
            label: "Access code"
            sub: Printer.hasCode ? "Saved on this computer only (not in theme.json). Type a new one to replace it" : "On the printer: Settings → Network (LAN only). Kept on this computer only"
            SField {
                id: codeField
                secret: true
                hint: Printer.hasCode ? "••••••••  saved" : "Type it, then Enter"
                onDone: v => { if (v.trim()) { Printer.saveCode(v); codeField.text = ""; } }
            }
        }
        SRow {
            label: "Test connection"
            sub: Printer.testing ? "Connecting…" : Printer.testResult || (Printer.configured ? "Checks the address, serial and access code" : "Fill in the address and serial first")
            HoverButton {
                implicitWidth: tc.implicitWidth + Theme.s(28); implicitHeight: Theme.s(32); radius: Theme.s(9)
                hoverFill: false
                enabled: Printer.configured && !Printer.testing
                opacity: enabled ? 1 : 0.4
                color: hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
                onClicked: Printer.test()
                Text { id: tc; anchors.centerIn: parent; text: "Test"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold }
            }
        }
        Text {
            visible: Printer.testResult !== "" && !Printer.testing
            Layout.fillWidth: true
            leftPadding: Theme.s(16); rightPadding: Theme.s(16); bottomPadding: Theme.s(10)
            text: (Printer.testOk ? "✓ " : "✕ ") + Printer.testResult
            color: Printer.testOk ? Theme.accent : Theme.red
            font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium
        }
        SRow {
            label: "Notify when a print ends"
            sub: "A notification when a print finishes or fails"
            SToggle { on: Printer.notify; onToggled: Printer.save({ notify: !on }) }
        }
        Text {
            Layout.fillWidth: true
            leftPadding: Theme.s(16); rightPadding: Theme.s(16); topPadding: Theme.s(4); bottomPadding: Theme.s(14)
            wrapMode: Text.WordWrap
            text: "ⓘ  " + Printer.lanNote
            color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12)
        }
    }

    SCard {
        title: "Weather"
        SRow {
            label: "Location"
            sub: Widgets.location ? Widgets.location.name : "Not set: the weather widget asks for one"
            Rectangle {
                implicitWidth: Theme.s(240); implicitHeight: Theme.s(34); radius: Theme.s(10)
                color: Qt.rgba(0, 0, 0, 0.3)
                border.width: 1; border.color: place.activeFocus ? Theme.accentLine : Theme.white(0.1)
                TextInput {
                    id: place
                    anchors.fill: parent; anchors.leftMargin: Theme.s(12); anchors.rightMargin: Theme.s(12)
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                    onAccepted: Widgets.findPlace(text)
                    Text { visible: !place.text; anchors.verticalCenter: parent.verticalCenter; text: "Type a city, then Enter"; color: Theme.dim; font: place.font }
                }
            }
        }
        Repeater {
            model: Widgets.places
            delegate: HoverButton {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Theme.s(38); radius: 0
                onClicked: { Widgets.setLocation(modelData); place.text = ""; }
                Text { x: Theme.s(16); anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
            }
        }
        SRow {
            last: true
            label: "Units"
            SSegment {
                options: [{ label: "°F", value: "F" }, { label: "°C", value: "C" }]
                value: Widgets.units
                onPicked: v => Widgets.save({ units: v })
            }
        }
    }
}
