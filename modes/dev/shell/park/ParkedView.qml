import QtQuick
import ".."
import "../services"

// The parked screen (design artboard 1): big clock, what's still running, your apps
// muted, and a big Play button that pulses to call him over.
Item {
    id: pv
    property real k: 1
    function u(px) { return Math.round(px * k); }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#2A3B5C" }
            GradientStop { position: 0.5; color: "#141B2B" }
            GradientStop { position: 1; color: "#0A0B10" }
        }
    }

    // badge: parked, and how many apps are still running
    Rectangle {
        x: pv.u(32); y: pv.u(28)
        height: pv.u(36); width: badge.implicitWidth + pv.u(28); radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.08); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
        Row {
            id: badge
            anchors.centerIn: parent
            spacing: pv.u(10)
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: pv.u(8); height: width; radius: width / 2; color: Theme.accent }
            Text { text: "Parked"; color: "#F5F5F7"; font.family: Theme.sans; font.pixelSize: pv.u(13); font.weight: Font.Medium }
            Text { text: "· " + Park.apps.length + (Park.apps.length === 1 ? " app" : " apps") + " still running"; color: "#C7C7CC"; font.family: Theme.sans; font.pixelSize: pv.u(13) }
        }
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: pv.u(32); y: pv.u(36)
        text: "Your apps are muted"; color: "#C7C7CC"; font.family: Theme.sans; font.pixelSize: pv.u(13)
    }

    // the clock
    Column {
        x: pv.u(96); y: pv.u(210)
        spacing: pv.u(6)
        Text {
            text: Qt.formatTime(new Date(Park.now), "h:mm")
            color: "#F5F5F7"; font.family: Theme.sans; font.pixelSize: pv.u(168); font.weight: Font.Light; font.letterSpacing: -pv.u(6)
        }
        Text {
            leftPadding: pv.u(8)
            text: Qt.formatDate(new Date(Park.now), "dddd, MMMM d")
            color: "#C7C7CC"; font.family: Theme.sans; font.pixelSize: pv.u(22)
        }
    }

    // while you're away: the apps still running
    Rectangle {
        visible: Park.apps.length > 0
        x: pv.u(96); anchors.bottom: parent.bottom; anchors.bottomMargin: pv.u(96)
        width: pv.u(460); height: away.implicitHeight + pv.u(44); radius: pv.u(22)
        color: Qt.rgba(13 / 255, 13 / 255, 15 / 255, 0.62); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
        Column {
            id: away
            x: pv.u(24); y: pv.u(22); width: parent.width - pv.u(48)
            spacing: pv.u(14)
            Text { text: "WHILE YOU'RE AWAY"; color: "#C7C7CC"; font.family: Theme.sans; font.pixelSize: pv.u(13); font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
            Repeater {
                model: Park.apps.slice(0, 5)
                delegate: Row {
                    required property string modelData
                    spacing: pv.u(12)
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: pv.u(10); height: width; radius: width / 2; color: Theme.accent }
                    Text { width: away.width - pv.u(120); elide: Text.ElideRight; text: { const n = modelData.split(".").pop().replace(/[-_]+/g, " "); return n.charAt(0).toUpperCase() + n.slice(1); } color: "#F5F5F7"; font.family: Theme.sans; font.pixelSize: pv.u(15) }
                    Text { text: "running"; color: "#9A9AA0"; font.family: Theme.sans; font.pixelSize: pv.u(13) }
                }
            }
        }
    }

    // Play: big, warm, pulsing
    Item {
        id: playBox
        width: pv.u(300); height: pv.u(300)
        anchors.right: parent.right; anchors.rightMargin: pv.u(150); y: pv.u(250)
        Rectangle {
            id: glow
            anchors.centerIn: parent
            width: parent.width; height: width; radius: width / 2
            color: "#F2702C"; opacity: 0
            SequentialAnimation on scale { loops: Animation.Infinite; running: true; NumberAnimation { from: 1; to: 1.35; duration: 1400; easing.type: Easing.OutCubic } PauseAnimation { duration: 300 } }
            SequentialAnimation on opacity { loops: Animation.Infinite; running: true; NumberAnimation { from: 0.45; to: 0; duration: 1400; easing.type: Easing.OutCubic } PauseAnimation { duration: 300 } }
        }
        Rectangle {
            id: playBtn
            anchors.centerIn: parent
            width: parent.width; height: width; radius: width / 2
            border.width: pv.u(10); border.color: Qt.rgba(1, 1, 1, 0.9)
            gradient: Gradient {
                GradientStop { position: 0; color: "#FFD36B" }
                GradientStop { position: 0.55; color: "#FF9F2E" }
                GradientStop { position: 1; color: "#F2702C" }
            }
            SequentialAnimation on scale { loops: Animation.Infinite; running: !playMouse.pressed
                NumberAnimation { from: 1; to: 1.06; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.06; to: 1; duration: 700; easing.type: Easing.InOutSine }
                PauseAnimation { duration: 300 } }
            Canvas {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: pv.u(10)
                width: pv.u(130); height: width
                onPaint: {
                    const c = getContext("2d"); c.reset();
                    c.fillStyle = "#FFFFFF"; c.beginPath();
                    c.moveTo(width * 0.28, height * 0.18); c.lineTo(width * 0.85, height * 0.5); c.lineTo(width * 0.28, height * 0.82);
                    c.closePath(); c.fill();
                }
            }
            MouseArea { id: playMouse; anchors.fill: parent; anchors.margins: -pv.u(20); cursorShape: Qt.PointingHandCursor; onClicked: Park.play() }
        }
    }
    Text {
        anchors.horizontalCenter: playBox.horizontalCenter
        anchors.top: playBox.bottom; anchors.topMargin: pv.u(22)
        text: "Play"; color: "#F5F5F7"; font.family: "Fredoka"; font.variableAxes: ({ "wght": 640 }); font.pixelSize: pv.u(44); font.weight: Font.DemiBold
    }
    // the way back, in small print (left on purpose: he's learning to read)
    Text {
        anchors.right: parent.right; anchors.rightMargin: pv.u(32)
        anchors.bottom: parent.bottom; anchors.bottomMargin: pv.u(28)
        text: "Hold Super + Alt + P to come back"
        color: "#9A9AA0"; font.family: Theme.sans; font.pixelSize: pv.u(12)
    }
    // a key press also plays (Enter / Space): he may reach for the keyboard
    Keys.onPressed: e => { if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) Park.play(); }
}
