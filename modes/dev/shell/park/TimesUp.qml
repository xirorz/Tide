import QtQuick
import ".."
import "../services"

// Time's up (design artboard 4): a sleepy moon over a night sky, and today's stars.
// Nothing he clicks does anything; you hold Super+Alt+P to come back.
Item {
    id: tu
    property real k: 1
    function u(px) { return Math.round(px * k); }
    focus: true
    Keys.onPressed: e => e.accepted = true

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#2B2A6B" }
            GradientStop { position: 0.6; color: "#4B3C8F" }
            GradientStop { position: 1; color: "#6A4FA8" }
        }
    }
    Repeater {
        model: [[180, 120, 8], [420, 210, 6], [1080, 150, 10], [1260, 320, 6], [300, 560, 7], [1180, 640, 8], [720, 90, 5]]
        delegate: Rectangle {
            required property var modelData
            x: tu.u(modelData[0]); y: tu.u(modelData[1]); width: tu.u(modelData[2]); height: width; radius: width / 2; color: "white"
            SequentialAnimation on opacity { loops: Animation.Infinite
                NumberAnimation { from: 0.8; to: 0.3; duration: 1600 + modelData[0] % 900; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.3; to: 0.8; duration: 1600 + modelData[0] % 900; easing.type: Easing.InOutSine } }
        }
    }
    Column {
        anchors.horizontalCenter: parent.horizontalCenter; y: tu.u(170)
        spacing: tu.u(40)
        Canvas {
            anchors.horizontalCenter: parent.horizontalCenter
            width: tu.u(300); height: width
            SequentialAnimation on y { loops: Animation.Infinite
                NumberAnimation { from: 0; to: tu.u(10); duration: 2400; easing.type: Easing.InOutSine }
                NumberAnimation { from: tu.u(10); to: 0; duration: 2400; easing.type: Easing.InOutSine } }
            onPaint: {
                const c = getContext("2d"); c.reset(); c.scale(width / 100, height / 100);
                c.fillStyle = "#FFE07A"; c.beginPath(); c.arc(50, 50, 40, 0, Math.PI * 2); c.fill();
                c.globalCompositeOperation = "destination-out"; c.beginPath(); c.arc(72, 36, 34, 0, Math.PI * 2); c.fill();
                c.globalCompositeOperation = "source-over";
                c.strokeStyle = "#B8902A"; c.lineWidth = 2.6; c.lineCap = "round";
                c.beginPath(); c.moveTo(24, 50); c.quadraticCurveTo(28, 54, 32, 50); c.stroke();
                c.beginPath(); c.moveTo(30, 66); c.quadraticCurveTo(35, 70, 40, 66); c.stroke();
                c.fillStyle = "white"; c.font = "bold 12px Fredoka"; c.fillText("z", 70, 64); c.font = "bold 9px Fredoka"; c.fillText("z", 80, 54);
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            height: tu.u(72); width: sr.implicitWidth + tu.u(52); radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.12)
            Row {
                id: sr
                anchors.centerIn: parent; spacing: tu.u(16)
                Text { anchors.verticalCenter: parent.verticalCenter; text: "★"; color: "#FFCE3D"; font.pixelSize: tu.u(44) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: Park.stars; color: "white"; font.family: "Fredoka"; font.variableAxes: ({ "wght": 640 }); font.pixelSize: tu.u(44); font.weight: Font.Bold }
            }
        }
    }
    MouseArea { anchors.fill: parent }
}
