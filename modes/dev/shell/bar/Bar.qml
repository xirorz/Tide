import QtQuick
import "../components/Icons.js" as Icons
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."
import "../components"
import "../services"

// The Dev mode top bar: floating 38px pills, 12px from the sides and 10px from the top.
// Left: workspace dots + window title. Right: network/resources, tray + updates,
// the AI button and the control cluster. The center pill is the island (island/Island.qml).
Item {
    id: bar
    required property var screen
    property alias leftGroup: leftRow
    property alias rightGroup: rightRow
    property alias controlCenter: controlCenter
    property bool ccOpen: false
    property bool upOpen: false
    property bool trayOpen: false         // a tray icon's menu (TrayMenu)
    // anything dropped down from the bar (the whole layer takes input while it's open)
    readonly property bool panelOpen: ccOpen || upOpen || trayOpen
    function closePanels() { ccOpen = false; upOpen = false; trayOpen = false; }
    onTrayOpenChanged: if (!trayOpen && trayMenu.visible) trayMenu.visible = false
    // the window is rebuilt on a Dark/Glass switch; keep the control center open
    Component.onCompleted: ccOpen = IslandState.ccOpen

    // only one thing open at a time: the island closes the control center and back
    // the control center replaces an open tool; Eve and the clock stay
    onCcOpenChanged: {
        IslandState.ccOpen = ccOpen;
        if (ccOpen) { upOpen = false; trayOpen = false; IslandState.closeSettings(); }
        if (ccOpen && IslandState.isTool(IslandState.mode)) IslandState.close();
    }
    onUpOpenChanged: {
        if (upOpen) { ccOpen = false; trayOpen = false; IslandState.closeSettings(); }
        if (upOpen && IslandState.isTool(IslandState.mode)) IslandState.close();
    }
    Connections {
        target: IslandState
        function onModeChanged() { if (IslandState.isTool(IslandState.mode)) bar.closePanels(); }
        function onControlCenterRequested() { bar.ccOpen = true; }
        function onControlCenterToggleRequested() { bar.ccOpen = !bar.ccOpen; }
        function onControlCenterCloseRequested() { bar.ccOpen = false; }
    }

    readonly property var active: ToplevelManager.activeToplevel
    readonly property bool aiOpen: EveData.open

    RowLayout {
        id: leftRow
        x: Theme.s(12)
        y: Theme.s(10)
        height: Theme.s(38)
        spacing: Theme.s(8)

        Workspaces { screen: bar.screen }

        Pill {
            visible: bar.active !== null && bar.active.title !== ""
            padH: Theme.s(15)
            Text {
                Layout.maximumWidth: Theme.s(420)
                elide: Text.ElideRight
                text: bar.active ? (bar.active.appId ? bar.active.appId + " — " + bar.active.title : bar.active.title) : ""
                color: Theme.text2
                font.family: Theme.sans
                font.pixelSize: Theme.s(12)
            }
        }
    }

    RowLayout {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: Theme.s(12)
        y: Theme.s(10)
        height: Theme.s(38)
        spacing: Theme.s(8)

        SystemPill {}
        TrayPill {
            id: trayPill
            panelOpen: bar.upOpen
            onToggled: bar.upOpen = !bar.upOpen
            onMenuRequested: (menu, item) => {
                if (bar.trayOpen && trayMenu.anchorItem === item) { bar.trayOpen = false; return; }
                bar.ccOpen = false; bar.upOpen = false;
                trayMenu.open(menu, item);
                bar.trayOpen = true;
            }
        }

        // AI corner button: toggles the Eve panel; outlined while it is open; gone when
        // Settings → AI is off
        Item {
            visible: Theme.aiEnabled
            Layout.preferredWidth: Theme.s(38)
            Layout.preferredHeight: Theme.s(38)
            Surface { anchors.fill: parent; kind: "bar"; radius: Theme.s(19) }
            Rectangle {
                anchors.fill: parent
                radius: Theme.s(19)
                color: "transparent"
                border.width: 1
                border.color: Theme.white(0.45)
                visible: bar.aiOpen
            }
            Icon { anchors.centerIn: parent; path: Icons.sparkle; size: Theme.s(17) }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: EveData.toggle()
            }
        }

        ControlCluster {
            open: bar.ccOpen
            onToggled: bar.ccOpen = !bar.ccOpen
        }
    }

    // right edge under the tray pill, where the updates count is
    UpdatesPanel {
        x: rightRow.x + trayPill.x + trayPill.width - width
        y: Theme.s(58)
        open: bar.upOpen
        maxHeight: Math.min(Theme.s(828), bar.height - Theme.s(58) - Theme.s(12))
        onCloseRequested: bar.upOpen = false
    }

    TrayMenu {
        id: trayMenu
        onCloseRequested: bar.trayOpen = false
    }

    ControlCenter {
        id: controlCenter
        anchors.right: parent.right
        anchors.rightMargin: Theme.s(12)
        y: Theme.s(58)
        open: bar.ccOpen
        maxHeight: bar.height - Theme.s(58) - Theme.s(12)
        onCloseRequested: bar.ccOpen = false
    }
}
