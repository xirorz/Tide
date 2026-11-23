import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import ".."
import "../components"

// Workspace dots: 7px dots, the active one 22px wide in the accent.
// Occupied 0.45 white, empty 0.2 white.
Pill {
    id: root
    required property var screen
    padH: Theme.s(15)
    spacing: Theme.s(7)

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property int activeId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 1
    readonly property int count: {
        let m = Theme.workspaceCount;
        for (const w of Hyprland.workspaces.values)
            if (w.id > m && w.id < 100) m = w.id;
        return m;
    }

    Repeater {
        model: root.count
        delegate: Rectangle {
            id: dot
            required property int index
            readonly property int wsId: index + 1
            readonly property var ws: Hyprland.workspaces.values.find(w => w.id === wsId)
            readonly property bool occupied: ws !== undefined && ws.toplevels.values.length > 0
            readonly property bool active: wsId === root.activeId

            Layout.preferredWidth: active ? Theme.s(22) : Theme.s(7)
            Layout.preferredHeight: Theme.s(7)
            radius: Theme.s(4)
            color: active ? Theme.accent : Theme.fg(occupied ? 0.45 : 0.2)

            MouseArea {
                anchors.fill: parent
                anchors.margins: -Theme.s(4)
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + dot.wsId)
            }
        }
    }
}
