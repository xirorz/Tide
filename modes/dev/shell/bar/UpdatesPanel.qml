import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// The updates panel: drops down under the updates count in the bar (the only way
// to open it). 470px wide, radius 24, padding 16, 12px gaps. Three views:
// the list (news, groups, switches, Update button), updating (progress while the
// floating terminal runs pacman) and done (result, restart, .pacnew files).
Item {
    id: up
    property bool open: false
    property real maxHeight: Theme.s(828)
    signal closeRequested()

    width: Theme.s(470)
    height: Math.min(maxHeight, col.implicitHeight + Theme.s(32))

    // panel drop (motion sheet), the same as the control center
    visible: opacity > 0
    opacity: 0
    transformOrigin: Item.TopRight
    transform: Translate { id: dropShift; y: 0 }
    ParallelAnimation {
        id: dropIn
        NumberAnimation { target: up; property: "opacity"; from: 0; to: 1; duration: Theme.reduceMotion ? 150 : Theme.durDrop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
        NumberAnimation { target: dropShift; property: "y"; from: Theme.reduceMotion ? 0 : -8; to: 0; duration: Theme.durDrop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
        NumberAnimation { target: up; property: "scale"; from: Theme.reduceMotion ? 1 : 0.98; to: 1; duration: Theme.durDrop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
    }
    NumberAnimation { id: dropOut; target: up; property: "opacity"; to: 0; duration: Theme.durHide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
    focus: open
    Keys.onEscapePressed: up.closeRequested()
    onOpenChanged: {
        if (open) { dropOut.stop(); dropIn.restart(); forceActiveFocus(); } else { dropIn.stop(); dropOut.restart(); }
        // a list older than 10 minutes is checked again on open
        if (open && Updates.phase === "list" && Date.now() / 1000 - Updates.checkedAt > 600) Updates.check();
    }

    // the terminal needs the keyboard: the panel steps aside (the bar's percent brings it back)
    Connections { target: Updates; function onStarted() { up.closeRequested(); } }

    // which groups are expanded (System starts open)
    property var groupsOpen: ({ system: true, apps: false, aur: false, flatpak: false })
    // "checked 12 min ago" ticks while the panel is open
    property real now: Date.now()
    Timer { interval: 30000; repeat: true; running: up.open; onTriggered: up.now = Date.now() }

    readonly property string phase: Updates.phase
    readonly property bool hasNews: Updates.news.posts.length > 0
    readonly property var groupDefs: [
        { key: "system", title: "System", restart: true },
        { key: "apps", title: "Apps and libraries", restart: false },
        { key: "aur", title: "AUR", restart: false },
        { key: "flatpak", title: "Flatpak", restart: false }
    ]

    Surface { anchors.fill: parent; kind: "panel"; radius: Theme.s(24) }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.s(16)
        spacing: Theme.s(12)

        // ---------- header ----------
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.s(8)
            Column {
                Layout.fillWidth: true
                spacing: Theme.s(3)
                Text {
                    text: up.phase === "busy" ? "Updating"
                        : up.phase === "done" ? (Updates.failed ? "Update stopped" : "Up to date")
                        : Updates.count === 0 ? (Updates.checking ? "Checking…" : Updates.listed > 0 ? "Up to date · " + Updates.listed + " held back" : "Up to date")
                        : Updates.count + (Updates.count === 1 ? " update ready" : " updates ready")
                    color: Theme.text
                    font.family: Theme.sans; font.pixelSize: Theme.type.h2[0]; font.weight: Theme.type.h2[1]
                }
                Text {
                    text: {
                        up.now;
                        if (up.phase === "busy") return Updates.waiting ? "Waiting for you in the terminal" : "Running in the terminal";
                        if (up.phase === "done") return "Checked just now";
                        const size = Updates.mb(Updates.totalMb);
                        const when = Updates.checking ? "checking now" : "checked " + Updates.ago(Updates.checkedAt);
                        return Updates.count > 0 && size !== "" ? size + " to download · " + when : (Updates.checkedAt ? when.charAt(0).toUpperCase() + when.slice(1) : "Not checked yet");
                    }
                    color: up.phase === "busy" && Updates.waiting ? Theme.warning : Theme.muted
                    font.family: Theme.sans; font.pixelSize: Theme.s(12)
                }
            }
            HoverButton {
                visible: up.phase === "list"
                Layout.alignment: Qt.AlignTop
                implicitWidth: Theme.s(32); implicitHeight: Theme.s(32); radius: Theme.s(16)
                hoverFill: false
                color: hovered ? Theme.white(0.12) : Theme.white(0.08)
                onClicked: Updates.check()
                Icon {
                    id: recheckIcon
                    anchors.centerIn: parent
                    path: Icons.pRestart; size: Theme.s(14); color: Theme.text
                    RotationAnimation on rotation {
                        running: Updates.checking && !Theme.reduceMotion
                        from: 0; to: 360; duration: 900; loops: Animation.Infinite
                        onRunningChanged: if (!running) recheckIcon.rotation = 0
                    }
                }
            }
        }

        // ---------- list ----------
        ColumnLayout {
            visible: up.phase === "list"
            Layout.fillWidth: true
            spacing: Theme.s(12)

            // Arch news since the last full upgrade
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: newsRow.implicitHeight + Theme.s(20)
                radius: Theme.s(13)
                color: up.hasNews ? Qt.rgba(1, 179 / 255, 64 / 255, 0.14) : Theme.tile
                RowLayout {
                    id: newsRow
                    anchors.fill: parent
                    anchors.leftMargin: Theme.s(12); anchors.rightMargin: Theme.s(12)
                    spacing: Theme.s(10)
                    Icon { path: up.hasNews ? Icons.warn : Icons.check; size: Theme.s(15); color: up.hasNews ? "#FFD08A" : Theme.text2 }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        lineHeight: Theme.s(17); lineHeightMode: Text.FixedHeight
                        readonly property string feeds: Updates.cachyNews ? "Arch or CachyOS" : "Arch"
                        text: {
                            const p = Updates.news.posts;
                            if (p.length === 0) return Updates.news.ok ? "No " + feeds + " news since your last update." : "Couldn't reach " + feeds + " news.";
                            const who = p.every(x => x.source === "cachyos") ? "CachyOS" : p.every(x => x.source !== "cachyos") ? "Arch" : feeds.replace(" or ", " and ");
                            return (p.length === 1 ? "1 " + who + " news post" : p.length + " " + who + " news posts") + " since your last update may need manual steps. Read it before updating.";
                        }
                        color: up.hasNews ? "#FFD08A" : Theme.text2
                        font.family: Theme.sans; font.pixelSize: Theme.s(12)
                    }
                    HoverButton {
                        visible: up.hasNews
                        implicitWidth: readText.implicitWidth + Theme.s(20); implicitHeight: Theme.s(26); radius: Theme.s(8)
                        hoverFill: false
                        color: Qt.rgba(0, 0, 0, hovered ? 0.35 : 0.25)
                        onClicked: { Updates.openNews(); up.closeRequested(); }
                        Text { id: readText; anchors.centerIn: parent; text: "Read"; color: "#FFD08A"; font.family: Theme.sans; font.pointSize: Theme.sf(8.625) }
                    }
                }
            }

            // the groups; the list scrolls past 470px
            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(Theme.s(470), groupsCol.implicitHeight)
                visible: Updates.listed > 0
                contentHeight: groupsCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                WheelScroll {}
                Column {
                    id: groupsCol
                    width: flick.width
                    spacing: Theme.s(10)
                    Repeater {
                        model: up.groupDefs.filter(g => Updates.included(g.key) && Updates.groups[g.key].length > 0)
                        delegate: ClippingRectangle {
                            id: grp
                            required property var modelData
                            readonly property var rows: Updates.groups[modelData.key]
                            readonly property bool expanded: !!up.groupsOpen[modelData.key]
                            width: groupsCol.width
                            height: grpCol.implicitHeight
                            radius: Theme.s(14)
                            color: Theme.tile
                            Column {
                                id: grpCol
                                width: parent.width
                                HoverButton {
                                    width: parent.width; height: Theme.s(40); radius: 0
                                    onClicked: {
                                        const o = Object.assign({}, up.groupsOpen);
                                        o[grp.modelData.key] = !grp.expanded;
                                        up.groupsOpen = o;
                                    }
                                    Row {
                                        anchors.left: parent.left; anchors.leftMargin: Theme.s(12)
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.s(8)
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: grp.modelData.title; color: Theme.text; font.family: Theme.sans; font.pointSize: Theme.sf(9.375); font.weight: Font.DemiBold }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: grp.rows.length; color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11) }
                                        Rectangle {
                                            visible: grp.modelData.restart
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: badge.implicitWidth + Theme.s(14); height: badge.implicitHeight + Theme.s(4); radius: Theme.s(7)
                                            color: Theme.accentSoft
                                            Text { id: badge; anchors.centerIn: parent; text: "restart after"; color: Theme.accent; font.family: Theme.sans; font.pointSize: Theme.sf(7.875); font.weight: Font.Medium }
                                        }
                                    }
                                    Row {
                                        anchors.right: parent.right; anchors.rightMargin: Theme.s(12)
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.s(8)
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: Updates.mb(grp.rows.reduce((a, r) => a + r.mb, 0)); color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11) }
                                        Icon { anchors.verticalCenter: parent.verticalCenter; path: grp.expanded ? Icons.chevronUp : Icons.chevronDown; size: Theme.s(13); color: Theme.muted }
                                    }
                                }
                                Repeater {
                                    model: grp.expanded ? grp.rows : []
                                    delegate: Item {
                                        id: row
                                        required property var modelData
                                        readonly property bool held: Updates.isHeld(modelData)
                                        width: grpCol.width; height: Theme.s(34)
                                        opacity: held ? 0.55 : 1
                                        // hover: Hold (skip it until you release it) / Release
                                        HoverHandler { id: rowHover }
                                        Rectangle { width: parent.width; height: 1; color: Theme.white(0.05) }
                                        // name + repo | from → to | size (64px)
                                        Text {
                                            anchors.left: parent.left; anchors.leftMargin: Theme.s(12)
                                            anchors.right: ver.left; anchors.rightMargin: Theme.s(10)
                                            anchors.verticalCenter: parent.verticalCenter
                                            elide: Text.ElideRight
                                            textFormat: Text.StyledText
                                            text: row.modelData.name + (row.modelData.repo ? " <font color='#7C7C82' size='1'>" + row.modelData.repo + "</font>" : "")
                                            color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                                        }
                                        Text {
                                            id: ver
                                            anchors.right: size.left; anchors.rightMargin: Theme.s(10)
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Math.min(implicitWidth, Theme.s(230))
                                            elide: Text.ElideMiddle
                                            textFormat: Text.StyledText
                                            text: (row.modelData.from || "installed") + " <font color='" + Theme.accent + "'>→</font> <font color='#E5E5EA'>" + (row.modelData.to || "latest") + "</font>"
                                            color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11)
                                        }
                                        Text {
                                            id: size
                                            anchors.right: parent.right; anchors.rightMargin: Theme.s(12)
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Theme.s(64)
                                            horizontalAlignment: Text.AlignRight
                                            visible: !rowHover.hovered && !row.held
                                            text: Updates.mb(row.modelData.mb)
                                            color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11)
                                        }
                                        HoverButton {
                                            visible: rowHover.hovered || row.held
                                            enabled: Updates.phase !== "busy"
                                            anchors.right: parent.right; anchors.rightMargin: Theme.s(8)
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Theme.s(68); height: Theme.s(24); radius: Theme.s(8)
                                            color: row.held ? Theme.accentSoft : Theme.white(0.07)
                                            onClicked: Updates.setHeld(row.modelData, !row.held)
                                            Text {
                                                anchors.centerIn: parent
                                                text: row.held ? (rowHover.hovered ? "Release" : "Held") : "Hold"
                                                color: row.held ? Theme.accent : Theme.text2
                                                font.family: Theme.sans; font.pixelSize: Theme.s(11); font.weight: Font.Medium
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // switches
            Column {
                Layout.fillWidth: true
                Layout.topMargin: Theme.s(4)
                Layout.bottomMargin: Theme.s(4)
                spacing: Theme.s(2)
                Switch { label: "Include AUR packages (" + (Updates.helperInfo.use || "AUR") + ")"; on: Updates.includeAur; onToggled: Theme.set("updatesAur", !on) }
                Switch { label: "Include Flatpak apps"; on: Updates.includeFlatpak; onToggled: Theme.set("updatesFlatpak", !on) }
                Switch { label: "Take a snapshot before updating"; on: Updates.snapshot; onToggled: Theme.set("updatesSnapshot", !on) }
            }

            HoverButton {
                Layout.fillWidth: true
                implicitHeight: Theme.s(44); radius: Theme.s(14)
                enabled: Updates.count > 0
                opacity: enabled ? 1 : 0.5
                hoverFill: false
                color: hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
                onClicked: Updates.start()
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.s(8)
                    Icon { anchors.verticalCenter: parent.verticalCenter; path: Icons.updates; stroke: 2; color: Theme.ink }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Updates.count === 0 ? "Nothing to update" : "Update " + Updates.count + (Updates.count === 1 ? " package" : " packages")
                        color: Theme.ink; font.family: Theme.sans; font.pointSize: Theme.sf(10.125); font.weight: Font.Bold
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: -Theme.s(4)
                horizontalAlignment: Text.AlignHCenter
                text: "Runs in a floating terminal so pacman can ask its questions"
                color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(11)
            }
        }

        // ---------- updating ----------
        ColumnLayout {
            visible: up.phase === "busy"
            Layout.fillWidth: true
            spacing: Theme.s(12)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: busyCol.implicitHeight + Theme.s(28)
                radius: Theme.s(14)
                color: Theme.tile
                ColumnLayout {
                    id: busyCol
                    anchors.fill: parent
                    anchors.margins: Theme.s(14)
                    spacing: Theme.s(10)
                    RowLayout {
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; text: Updates.stage; color: Theme.text; font.family: Theme.sans; font.pointSize: Theme.sf(9.375); font.weight: Font.DemiBold }
                        Text { text: Updates.pct + "%"; color: Theme.muted; font.family: Theme.mono; font.pointSize: Theme.sf(9.375) }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.s(6); radius: Theme.s(3)
                        color: Theme.white(0.12)
                        Rectangle {
                            height: parent.height; radius: Theme.s(3)
                            width: parent.width * Updates.pct / 100
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: Theme.reduceMotion ? 0 : 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Updates.waiting ? "pacman is asking something. Answer it in the terminal." : Updates.current
                        color: Updates.waiting ? Theme.warning : Theme.text2
                        font.family: Theme.sans; font.pixelSize: Theme.s(12)
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                lineHeight: Theme.s(18); lineHeightMode: Text.FixedHeight
                text: "You can keep working. If pacman asks something, the terminal waits for you and this panel says so."
                color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12)
            }
        }

        // ---------- done ----------
        ColumnLayout {
            visible: up.phase === "done"
            Layout.fillWidth: true
            spacing: Theme.s(12)

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.s(64)
                radius: Theme.s(14)
                color: Updates.failed ? Qt.rgba(1, 69 / 255, 58 / 255, 0.14) : Theme.accentSoft
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.s(14)
                    spacing: Theme.s(12)
                    Rectangle {
                        implicitWidth: Theme.s(36); implicitHeight: Theme.s(36); radius: Theme.s(18)
                        color: Updates.failed ? Theme.critical : Theme.accent
                        Icon { anchors.centerIn: parent; path: Updates.failed ? Icons.close : Icons.check; stroke: 2.4; color: Theme.ink }
                    }
                    Column {
                        Layout.fillWidth: true
                        spacing: Theme.s(2)
                        Text {
                            text: Updates.failed ? "Some updates didn't finish" : Updates.doneN + (Updates.doneN === 1 ? " package updated" : " packages updated")
                            color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold
                        }
                        Text {
                            text: Updates.failed ? "The terminal shows what went wrong." : "Finished in " + (Updates.seconds >= 60 ? Math.floor(Updates.seconds / 60) + " min " : "") + Updates.seconds % 60 + " s"
                            color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                        }
                    }
                }
            }

            Rectangle {
                visible: Updates.needsRestart && !Updates.failed
                Layout.fillWidth: true
                implicitHeight: restartCol.implicitHeight + Theme.s(28)
                radius: Theme.s(14)
                color: Theme.tile
                ColumnLayout {
                    id: restartCol
                    anchors.fill: parent
                    anchors.margins: Theme.s(14)
                    spacing: Theme.s(8)
                    Text { text: "Restart to finish"; color: Theme.text; font.family: Theme.sans; font.pointSize: Theme.sf(9.375); font.weight: Font.DemiBold }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        lineHeight: Theme.s(18); lineHeightMode: Text.FixedHeight
                        text: "The kernel or graphics driver was updated. They take effect after a restart."
                        color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                    }
                    HoverButton {
                        implicitWidth: rsRow.implicitWidth + Theme.s(28); implicitHeight: Theme.s(34); radius: Theme.s(10)
                        hoverFill: false
                        color: hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
                        onClicked: Updates.restartNow()
                        Row {
                            id: rsRow
                            anchors.centerIn: parent
                            spacing: Theme.s(7)
                            Icon { anchors.verticalCenter: parent.verticalCenter; path: Icons.pRestart; size: Theme.s(14); color: Theme.ink }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Restart now"; color: Theme.ink; font.family: Theme.sans; font.pointSize: Theme.sf(9.375); font.weight: Font.DemiBold }
                        }
                    }
                }
            }

            Rectangle {
                visible: Updates.pacnew.length > 0
                Layout.fillWidth: true
                implicitHeight: Theme.s(60)
                radius: Theme.s(14)
                color: Theme.tile
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.s(14); anchors.rightMargin: Theme.s(14)
                    spacing: Theme.s(12)
                    Icon { path: Icons.pacnew; color: Theme.warning }
                    Column {
                        Layout.fillWidth: true
                        spacing: Theme.s(2)
                        Text {
                            text: Updates.pacnew.length === 1 ? "1 config file has a new version" : Updates.pacnew.length + " config files have new versions"
                            color: Theme.text; font.family: Theme.sans; font.pointSize: Theme.sf(9.375); font.weight: Font.Medium
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideMiddle
                            text: Updates.pacnew.join("  ")
                            color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11)
                        }
                    }
                    HoverButton {
                        implicitWidth: Theme.s(70); implicitHeight: Theme.s(30); radius: Theme.s(9)
                        hoverFill: false
                        color: Theme.white(hovered ? 0.14 : 0.1)
                        onClicked: { Updates.reviewPacnew(); up.closeRequested(); }
                        Text { anchors.centerIn: parent; text: "Review"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                    }
                }
            }

            HoverButton {
                Layout.fillWidth: true
                implicitHeight: Theme.s(38); radius: Theme.s(12)
                hoverFill: false
                color: Theme.white(hovered ? 0.12 : 0.08)
                onClicked: { Updates.finish(); up.closeRequested(); }
                Text { anchors.centerIn: parent; text: "Close"; color: Theme.text; font.family: Theme.sans; font.pointSize: Theme.sf(9.375) }
            }
        }
    }

    // a 32px row: label, then a 32x20 switch
    component Switch: HoverButton {
        id: sw
        property string label
        property bool on
        signal toggled()
        width: parent.width
        height: Theme.s(32)
        hoverFill: false
        onClicked: sw.toggled()
        Text { anchors.left: parent.left; anchors.leftMargin: Theme.s(4); anchors.verticalCenter: parent.verticalCenter; text: sw.label; color: Theme.soft; font.family: Theme.sans; font.pointSize: Theme.sf(9.375) }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: Theme.s(4)
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.s(32); height: Theme.s(20); radius: Theme.s(10)
            color: sw.on ? Theme.accent : Theme.white(0.18)
            Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 0 : Theme.durHover } }
            Rectangle {
                y: Theme.s(2); x: sw.on ? Theme.s(14) : Theme.s(2)
                width: Theme.s(16); height: Theme.s(16); radius: Theme.s(8)
                color: sw.on ? Theme.ink : Theme.text
                Behavior on x { NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
            }
        }
    }
}
