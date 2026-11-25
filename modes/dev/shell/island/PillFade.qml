import QtQuick
import ".."

// What one of the island's pills shows (the clock, recording, dictation, a timed
// mode): goes out at once (150ms) when the island changes, and comes in only after the
// shape has moved (durHide + delayReveal, then 300ms), so two never show together.
// The timing is picked when the change happens; animations on the item's own opacity
// kept the previous state's timing and ghosted.
Item {
    id: f
    property Item target: parent
    property bool on: false
    visible: false
    Component.onCompleted: target.opacity = on ? 1 : 0
    onOnChanged: {
        fadeIn.stop(); fadeOut.stop();
        if (on) fadeIn.start(); else fadeOut.start();
    }
    SequentialAnimation {
        id: fadeIn
        PropertyAction { target: f.target; property: "opacity"; value: 0 }
        PauseAnimation { duration: Theme.reduceMotion ? 0 : Theme.durHide + Theme.delayReveal }
        NumberAnimation { target: f.target; property: "opacity"; to: 1; duration: Theme.reduceMotion ? 150 : Theme.durReveal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
    }
    NumberAnimation { id: fadeOut; target: f.target; property: "opacity"; to: 0; duration: Theme.reduceMotion ? 0 : Theme.durHide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
}
