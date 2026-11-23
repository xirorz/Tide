import QtQuick
import ".."

// The design's 36x22 switch: accent track with a dark knob when on.
Rectangle {
    id: tg
    property bool on: false
    property bool interactive: true
    signal toggled()
    implicitWidth: Theme.s(36)
    implicitHeight: Theme.s(22)
    radius: Theme.s(11)
    color: on ? Theme.accent : Theme.white(0.18)
    opacity: interactive ? 1 : 0.5
    Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 0 : Theme.durHover } }
    Rectangle {
        y: Theme.s(2); x: tg.on ? Theme.s(16) : Theme.s(2)
        width: Theme.s(18); height: Theme.s(18); radius: Theme.s(9)
        color: tg.on ? Theme.ink : Theme.text
        Behavior on x { NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
    }
    MouseArea {
        anchors.fill: parent
        enabled: tg.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: tg.toggled()
    }
}
