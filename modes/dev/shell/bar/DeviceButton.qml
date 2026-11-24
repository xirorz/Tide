import QtQuick
import QtQuick.Layouts
import "../components/Icons.js" as Icons
import ".."
import "../components"

// "Output   Laptop speakers ⌄": the sound device in use; click to choose another
// (the control center lists them under it).
HoverButton {
    id: db
    property string label
    property string device
    property bool open: false
    Layout.fillWidth: true
    implicitHeight: Theme.s(36)
    radius: Theme.s(10)
    hoverFill: false
    color: open ? Theme.white(0.1) : Qt.rgba(0, 0, 0, 0.25)
    Text { x: Theme.s(10); anchors.verticalCenter: parent.verticalCenter; text: db.label; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
    Text {
        anchors.left: parent.left; anchors.leftMargin: Theme.s(64)
        anchors.right: chev.left; anchors.rightMargin: Theme.s(6)
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: db.device; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium
    }
    Icon { id: chev; anchors.right: parent.right; anchors.rightMargin: Theme.s(10); anchors.verticalCenter: parent.verticalCenter; path: db.open ? Icons.chevronUp : Icons.chevronDown; size: Theme.s(14); color: Theme.muted }
}
