import QtQuick
import "../services"

// The round house button: back to his space.
Rectangle {
    id: hb
    property real k: 1
    property color tint: "#FF5C8A"
    function u(px) { return Math.round(px * k); }
    width: u(96); height: width; radius: width / 2
    color: "white"
    // pointing him home: grows and shrinks, and a ring spreads out from it
    property bool nudge: false
    SequentialAnimation on scale { running: hb.nudge; loops: Animation.Infinite
        NumberAnimation { from: 1; to: 1.25; duration: 450; easing.type: Easing.OutQuad }
        NumberAnimation { from: 1.25; to: 1; duration: 450; easing.type: Easing.InQuad } }
    onNudgeChanged: if (!nudge) scale = 1
    Rectangle {
        visible: hb.nudge
        anchors.centerIn: parent
        width: parent.width; height: width; radius: width / 2
        color: "transparent"; border.width: hb.u(6); border.color: hb.tint
        z: -2
        NumberAnimation on scale { running: hb.nudge; loops: Animation.Infinite; from: 1; to: 1.8; duration: 900 }
        NumberAnimation on opacity { running: hb.nudge; loops: Animation.Infinite; from: 0.8; to: 0; duration: 900 }
    }
    Rectangle { anchors.fill: parent; anchors.topMargin: hb.u(8); radius: width / 2; color: Qt.rgba(31 / 255, 35 / 255, 64 / 255, 0.12); z: -1 }
    Canvas {
        anchors.centerIn: parent; width: hb.u(50); height: width
        onPaint: {
            const c = getContext("2d"); c.reset(); c.scale(width / 24, height / 24);
            c.strokeStyle = hb.tint; c.lineWidth = 2.6; c.lineCap = "round"; c.lineJoin = "round"; c.beginPath();
            c.moveTo(3, 11.5); c.lineTo(12, 4); c.lineTo(21, 11.5);
            c.moveTo(5.5, 10); c.lineTo(5.5, 19.5); c.lineTo(18.5, 19.5); c.lineTo(18.5, 10);
            c.moveTo(10, 19.5); c.lineTo(10, 14.5); c.lineTo(14, 14.5); c.lineTo(14, 19.5); c.stroke();
        }
    }
}
