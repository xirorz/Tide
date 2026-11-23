import QtQuick
import ".."

// Click-and-drag slider: 4px track, filled part, 16px thumb (the design's range input).
Item {
    id: sl
    property real value: 0
    property color fill: Theme.text
    signal moved(real v)
    implicitHeight: Theme.s(16)
    readonly property real v: Math.max(0, Math.min(1, value))
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: Theme.s(4); radius: Theme.s(2)
        color: Theme.white(0.18)
    }
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: sl.v * parent.width; height: Theme.s(4); radius: Theme.s(2)
        color: sl.fill
    }
    Rectangle {
        x: sl.v * (parent.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.s(16); height: Theme.s(16); radius: Theme.s(8)
        color: sl.fill
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function set(mx) { sl.moved(Math.max(0, Math.min(1, mx / width))); }
        onPressed: m => set(m.x)
        onPositionChanged: m => { if (pressed) set(m.x); }
    }
}
