import QtQuick
import ".."

// A 220px range slider in the accent (like the design's accent-colored input range).
// `value` follows the setting; dragging reports moved(v) live and released(v) at the end.
Item {
    id: sl
    property real from: 0
    property real to: 1
    property real step: 1
    property real value: 0
    signal moved(real v)
    signal released(real v)
    implicitWidth: Theme.s(220)
    implicitHeight: Theme.s(22)
    readonly property real shown: ma.pressed ? dragV : value
    property real dragV: 0
    readonly property real frac: (shown - from) / (to - from)

    function at(x) {
        const f = Math.max(0, Math.min(1, (x - 8) / (width - 16)));
        const v = from + f * (to - from);
        return Math.round(v / step) * step;
    }
    Rectangle {
        x: Theme.s(8); width: parent.width - Theme.s(16)
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.s(4); radius: Theme.s(2)
        color: Theme.white(0.15)
        Rectangle { width: parent.width * sl.frac; height: parent.height; radius: Theme.s(2); color: Theme.accent }
    }
    Rectangle {
        x: Theme.s(8) + (sl.width - Theme.s(16)) * sl.frac - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.s(16); height: Theme.s(16); radius: Theme.s(8)
        color: Theme.text
        border.width: 3
        border.color: Theme.accent
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => { sl.dragV = sl.at(mouse.x); sl.moved(sl.dragV); }
        onPositionChanged: mouse => { if (pressed) { const v = sl.at(mouse.x); if (v !== sl.dragV) { sl.dragV = v; sl.moved(v); } } }
        onReleased: sl.released(sl.dragV)
    }
}
