import QtQuick
import ".."

// The design's <kbd>: mono 11.5px on a faint chip with a hairline border.
Rectangle {
    property string text
    implicitWidth: t.implicitWidth + Theme.s(16)
    implicitHeight: t.implicitHeight + Theme.s(6)
    radius: Theme.s(7)
    color: Theme.white(0.1)
    border.width: 1
    border.color: Theme.white(0.14)
    Text { id: t; anchors.centerIn: parent; text: parent.text; color: Theme.text; font.family: Theme.mono; font.pointSize: Theme.sf(8.625) }
}
