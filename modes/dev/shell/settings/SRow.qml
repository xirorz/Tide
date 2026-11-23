import QtQuick
import QtQuick.Layouts
import ".."

// One row of a settings card: label (and an optional grey line under it) on the
// left, the control (this item's children) on the right; a hairline under it unless last.
Item {
    id: r
    property string label
    property string sub: ""
    property bool last: false
    property real padV: Theme.s(14)
    default property alias control: slot.data
    Layout.fillWidth: true
    implicitHeight: Math.max(texts.implicitHeight, slot.childrenRect.height) + padV * 2
    Column {
        id: texts
        anchors.left: parent.left; anchors.leftMargin: Theme.s(16)
        anchors.right: slot.left; anchors.rightMargin: Theme.s(16)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.s(2)
        Text { width: parent.width; wrapMode: Text.WordWrap; text: r.label; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
        Text { visible: r.sub !== ""; width: parent.width; wrapMode: Text.WordWrap; text: r.sub; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
    }
    Item {
        id: slot
        anchors.right: parent.right; anchors.rightMargin: Theme.s(16)
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
    Rectangle { visible: !r.last; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.white(0.06) }
}
