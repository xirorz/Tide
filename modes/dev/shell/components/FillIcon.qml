import QtQuick
import ".."

// A device icon that fills from the bottom with its own charge, in the accent color.
Item {
    id: f
    property string path
    property real level: 0     // 0..1
    implicitWidth: Theme.s(16)
    implicitHeight: Theme.s(16)

    Icon { path: f.path; color: Theme.fg(0.28) }
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * Math.max(0, Math.min(1, f.level))
        clip: true
        Icon { anchors.bottom: parent.bottom; path: f.path; color: Theme.accent }
    }
}
