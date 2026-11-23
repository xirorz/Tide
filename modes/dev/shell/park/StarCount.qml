import QtQuick
import "../services"

// His stars: a gold star and the number, in a white pill. Bounces when one is added.
Rectangle {
    id: sc
    property real k: 1
    function u(px) { return Math.round(px * k); }
    height: u(72); width: row.implicitWidth + u(34); radius: height / 2
    color: "white"
    Rectangle { anchors.fill: parent; anchors.topMargin: sc.u(8); radius: height / 2; color: Qt.rgba(31 / 255, 35 / 255, 64 / 255, 0.12); z: -1 }
    Row {
        id: row
        x: sc.u(10); anchors.verticalCenter: parent.verticalCenter
        spacing: sc.u(14)
        Rectangle {
            width: sc.u(52); height: width; radius: width / 2; color: "#FFCE3D"
            Canvas {
                anchors.centerIn: parent; width: sc.u(34); height: width
                onPaint: {
                    const c = getContext("2d"); c.reset(); c.scale(width / 24, height / 24);
                    c.fillStyle = "#FFFFFF"; c.strokeStyle = "#E0A800"; c.lineWidth = 1.2; c.lineJoin = "round"; c.beginPath();
                    const p = [[12, 2.5], [14.9, 8.6], [21.5, 9.4], [16.6, 14], [17.9, 20.6], [12, 17.3], [6.1, 20.6], [7.4, 14], [2.5, 9.4], [9.1, 8.6]];
                    c.moveTo(p[0][0], p[0][1]); for (let i = 1; i < p.length; i++) c.lineTo(p[i][0], p[i][1]); c.closePath(); c.fill(); c.stroke();
                }
            }
        }
        Text {
            id: num
            anchors.verticalCenter: parent.verticalCenter
            text: Park.stars
            color: "#1F2340"; font.family: "Fredoka"; font.variableAxes: ({ "wght": 640 }); font.pixelSize: sc.u(40); font.weight: Font.Bold
            onTextChanged: bounce.restart()
            SequentialAnimation on scale { id: bounce; running: false
                NumberAnimation { to: 1.35; duration: 120; easing.type: Easing.OutQuad }
                NumberAnimation { to: 1; duration: 220; easing.type: Easing.OutBack } }
        }
    }
}
