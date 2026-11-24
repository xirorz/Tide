import QtQuick
import QtQuick.Layouts
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// One sound device in the control center's list; the one in use has a check.
HoverButton {
    id: dr
    property var node: null
    property bool on: false
    Layout.fillWidth: true
    implicitHeight: Theme.s(34)
    radius: Theme.s(9)
    Text {
        x: Theme.s(12); anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Theme.s(44); elide: Text.ElideRight
        text: Audio.label(dr.node); color: dr.on ? Theme.text : Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12)
    }
    Icon { visible: dr.on; anchors.right: parent.right; anchors.rightMargin: Theme.s(10); anchors.verticalCenter: parent.verticalCenter; path: Icons.check; size: Theme.s(14); color: Theme.accent }
}
