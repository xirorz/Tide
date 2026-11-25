import QtQuick
import ".."

// A device icon that fills from the bottom with its own charge, in the accent color,
// with a small bolt in its corner while it charges.
Item {
    id: f
    property string path
    property real level: 0     // 0..1
    property bool charging: false
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
    Canvas {
        visible: f.charging
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -Theme.s(3)
        anchors.bottomMargin: -Theme.s(1)
        width: Theme.s(8); height: Theme.s(10)
        onPaint: {
            const c = getContext("2d"); c.reset(); c.scale(width / 10, height / 12);
            c.fillStyle = "#FFFFFF"; c.strokeStyle = "#000000"; c.lineWidth = 1.2; c.lineJoin = "round";
            c.beginPath(); c.moveTo(6, 0); c.lineTo(1.5, 7); c.lineTo(4.5, 7); c.lineTo(3.5, 12); c.lineTo(8.5, 5); c.lineTo(5.5, 5); c.closePath();
            c.fill(); c.stroke();
        }
    }
}
