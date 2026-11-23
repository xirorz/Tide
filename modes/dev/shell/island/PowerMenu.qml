import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// The island's power menu (520x144): five round buttons that act right away
// (no confirm step, per the spec). Escape or a click outside closes it.
Item {
    id: pm
    signal closeRequested()
    function reset() { forceActiveFocus(); }
    focus: true
    Keys.onEscapePressed: pm.closeRequested()

    // lock goes through hyprlock like hypridle does; log out ends the session
    readonly property var items: [
        { label: "Lock", icon: Icons.pLock, cmd: "pidof hyprlock || hyprlock" },
        { label: "Suspend", icon: Icons.pSleep, cmd: "systemctl suspend" },
        // uwsm only when it runs the compositor (a login straight into Hyprland has no
        // uwsm session to stop): otherwise Hyprland exits itself
        { label: "Log out", icon: Icons.pLogout, cmd: "if systemctl --user list-units --state=active --plain --no-legend 'wayland-wm@*.service' | grep -q .; then uwsm stop; else hyprctl dispatch 'hl.dsp.exit()'; fi" },
        { label: "Restart", icon: Icons.pRestart, cmd: "systemctl reboot" },
        { label: "Shut down", icon: Icons.pShutdown, cmd: "systemctl poweroff", danger: true }
    ]
    function act(cmd) {
        pm.closeRequested();
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    GridLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.s(18)
        anchors.rightMargin: Theme.s(18)
        anchors.topMargin: Theme.s(16)
        anchors.bottomMargin: Theme.s(16)
        columns: 5
        columnSpacing: Theme.s(6)
        uniformCellWidths: true

        Repeater {
            model: pm.items
            delegate: Item {
                id: b
                required property var modelData
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: Theme.s(112)
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pm.act(b.modelData.cmd)
                }
                Column {
                    anchors.centerIn: parent
                    spacing: Theme.s(9)
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Theme.s(58); height: Theme.s(58); radius: Theme.s(29)
                        color: b.modelData.danger ? Qt.rgba(1, 69 / 255, 58 / 255, 0.18) : Theme.white(0.1)
                        Icon { anchors.centerIn: parent; path: b.modelData.icon; size: Theme.s(22); color: b.modelData.danger ? "#FF6961" : Theme.text }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: b.modelData.label
                        color: Theme.soft
                        font.family: Theme.sans
                        font.pixelSize: Theme.s(12)
                    }
                }
            }
        }
    }
}
