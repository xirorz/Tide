import QtQuick
import ".."

// The design's .btn: transparent, rgba(255,255,255,0.08) on hover, radius 10.
Rectangle {
    id: b
    property bool hoverFill: true
    property alias hovered: ma.containsMouse
    property alias acceptedButtons: ma.acceptedButtons
    signal clicked(var mouse)

    radius: Theme.s(10)
    // the corners follow Appearance → Corner roundness like the panels around them (a
    // round or pill-shaped button stays round). Off where the radius is set some other
    // way (the island's pills use the island's own corners).
    property bool followRoundness: true
    Component.onCompleted: {
        if (!followRoundness) return;
        const design = radius / Theme.s(1);
        radius = Qt.binding(() => {
            const half = Math.min(width, height) / 2;
            const r = design * Theme.s(1);
            return r >= half - 0.5 ? half : Math.min(half, r * Theme.radiusScale);
        });
    }
    color: hoverFill && ma.containsMouse ? Theme.white(0.08) : "transparent"
    // hovers and selections ease over 180ms (motion sheet); buttons never lift
    Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 0 : Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => b.clicked(mouse)
    }
}
