import QtQuick
import ".."
import "../services"

// His space (design artboard 2): sky and hills, big picture tiles, no words. The stars
// he's earned top left; the ring top right is his hour running down. Tiles that aren't
// built yet are dimmed and don't open.
Item {
    id: kh
    property real k: 1
    function u(px) { return Math.round(px * k); }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#8FD3FF" }
            GradientStop { position: 0.55; color: "#BDE7FF" }
            GradientStop { position: 1; color: "#DDF4C8" }
        }
    }
    Hills { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: kh.u(200) }

    StarCount { x: kh.u(40); y: kh.u(28); k: kh.k }

    // his hour: a ring that empties
    Rectangle {
        anchors.right: parent.right; anchors.rightMargin: kh.u(40); y: kh.u(28)
        width: kh.u(80); height: width; radius: width / 2
        color: "white"
        Rectangle { anchors.fill: parent; anchors.topMargin: kh.u(8); radius: width / 2; color: Qt.rgba(31 / 255, 35 / 255, 64 / 255, 0.12); z: -1 }
        Canvas {
            anchors.centerIn: parent
            width: kh.u(56); height: width
            property real frac: Park.playLeft / (Park.playMinutes * 60000)
            onFracChanged: requestPaint()
            onPaint: {
                const c = getContext("2d"); c.reset();
                c.lineWidth = width * 0.18; c.lineCap = "round";
                c.strokeStyle = "#E6ECF5"; c.beginPath(); c.arc(width / 2, height / 2, width * 0.4, 0, Math.PI * 2); c.stroke();
                c.strokeStyle = frac > 0.15 ? "#46C46E" : "#FFB938";
                c.beginPath(); c.arc(width / 2, height / 2, width * 0.4, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac); c.stroke();
            }
        }
    }

    Grid {
        anchors.horizontalCenter: parent.horizontalCenter
        y: kh.u(150)
        columns: 3
        spacing: kh.u(36)
        Tile { k: kh.k; base: "#FF7FA8"; shade: "#D95A84"; art: "bubble"; level: Park.levels.bubble || 1; onPicked: Park.open("bubble") }
        Tile { k: kh.k; base: "#5B8CFF"; shade: "#3E6AD8"; art: "letters"; level: Park.levels.letters || 1; onPicked: Park.open("letters") }
        Tile { k: kh.k; base: "#FFB938"; shade: "#D99418"; art: "paint"; ready: false }
        Tile { k: kh.k; base: "#B57CF2"; shade: "#8F57D0"; art: "star"; ready: false }
        Tile { k: kh.k; base: "#46C46E"; shade: "#2FA055"; art: "animal"; ready: false }
        Tile { k: kh.k; base: "transparent"; shade: "transparent"; art: "more"; ready: false }
    }
}
