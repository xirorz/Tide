import QtQuick
import Quickshell.Services.UPower
import ".."

// The laptop's battery in the bar: an outline that fills with the charge (red under
// 15%), a bolt while it charges, and the percentage. Not there on a PC without one.
Row {
    id: lb
    readonly property var dev: UPower.displayDevice
    readonly property bool present: !!dev && dev.ready && dev.isLaptopBattery
    readonly property real level: present ? dev.percentage : 0
    readonly property bool charging: present && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: present && dev.state === UPowerDeviceState.FullyCharged
    visible: present
    spacing: Theme.s(5)

    Item {
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.s(22); height: Theme.s(12)
        Rectangle {
            width: parent.width - Theme.s(2); height: parent.height
            radius: Theme.s(3)
            color: "transparent"
            border.width: Theme.s(1.5) > 1 ? Theme.s(1.5) : 1.5
            border.color: Theme.text2
            Rectangle {
                x: Theme.s(2); y: Theme.s(2)
                height: parent.height - Theme.s(4)
                width: Math.max(Theme.s(2), (parent.width - Theme.s(4)) * lb.level)
                radius: Theme.s(1.5)
                color: lb.charging || lb.full ? Theme.accent : lb.level < 0.15 ? Theme.red : Theme.text2
            }
        }
        Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: Theme.s(2); height: Theme.s(5); radius: 1; color: Theme.text2 }
        // charging: a small bolt over the cell
        Canvas {
            visible: lb.charging
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -Theme.s(1)
            width: Theme.s(10); height: Theme.s(12)
            onPaint: {
                const c = getContext("2d"); c.reset(); c.scale(width / 10, height / 12);
                c.fillStyle = "#FFFFFF"; c.strokeStyle = "#000000"; c.lineWidth = 0.8; c.lineJoin = "round";
                c.beginPath(); c.moveTo(6, 0); c.lineTo(1.5, 7); c.lineTo(4.5, 7); c.lineTo(3.5, 12); c.lineTo(8.5, 5); c.lineTo(5.5, 5); c.closePath();
                c.fill(); c.stroke();
            }
        }
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(lb.level * 100) + "%"
        color: Theme.text
        font.family: Theme.mono
        font.pixelSize: Theme.s(12)
    }
}
