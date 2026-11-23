import QtQuick

// One of his big picture tiles: a colour, a drawing, dots for the levels he's reached.
// Not ready (a game still to build): dimmed and it doesn't open.
Item {
    id: t
    property real k: 1
    function u(px) { return Math.round(px * k); }
    property color base: "#FF7FA8"
    property color shade: "#D95A84"
    property string art: "bubble"           // bubble | letters | paint | star | animal | more
    property int level: 0
    property bool ready: true
    signal picked()
    width: u(362); height: u(314)
    opacity: ready || art === "more" ? 1 : 0.45

    Rectangle {
        y: t.u(14); width: parent.width; height: t.u(300); radius: t.u(40)
        color: t.shade
        visible: t.art !== "more"
    }
    Rectangle {
        id: face
        width: parent.width; height: t.u(300); radius: t.u(40)
        y: mouse.pressed && t.ready ? t.u(10) : (mouse.containsMouse && t.ready ? -t.u(4) : 0)
        Behavior on y { NumberAnimation { duration: 120 } }
        color: t.art === "more" ? Qt.rgba(1, 1, 1, 0.45) : t.base
        border.width: t.art === "more" ? t.u(6) : 0
        border.color: Qt.rgba(31 / 255, 35 / 255, 64 / 255, 0.22)

        Canvas {
            id: pic
            anchors.centerIn: parent
            anchors.verticalCenterOffset: t.art === "more" || t.art === "paint" ? 0 : -t.u(18)
            width: t.u(150); height: width
            onPaint: {
                const c = getContext("2d"); c.reset();
                const s = width / 100;
                c.scale(s, s);
                const circle = (x, y, r, col) => { c.fillStyle = col; c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.fill(); };
                if (t.art === "bubble") {
                    circle(42, 46, 28, "rgba(255,255,255,0.85)"); circle(74, 30, 14, "rgba(255,255,255,0.7)");
                    circle(70, 74, 10, "rgba(255,255,255,0.6)"); circle(34, 36, 7, "#FFFFFF");
                } else if (t.art === "letters") {
                    const box = (x, y, ch) => {
                        c.fillStyle = "#C9D7FF"; c.beginPath(); c.roundedRect(x, y + 4, 28, 28, 6, 6); c.fill();
                        c.fillStyle = "#FFFFFF"; c.beginPath(); c.roundedRect(x, y, 28, 28, 6, 6); c.fill();
                        c.fillStyle = "#3E6AD8"; c.font = "bold 21px Fredoka"; c.textAlign = "center"; c.textBaseline = "middle"; c.fillText(ch, x + 14, y + 15);
                    };
                    box(4, 30, "A"); box(36, 46, "b"); box(68, 30, "c");
                } else if (t.art === "paint") {
                    c.fillStyle = "#FFFFFF"; c.beginPath(); c.moveTo(50, 14);
                    c.bezierCurveTo(28, 14, 14, 29, 14, 47); c.bezierCurveTo(14, 60, 23, 66, 31, 66);
                    c.bezierCurveTo(37, 66, 38, 60, 44, 60); c.bezierCurveTo(51, 60, 48, 72, 57, 72);
                    c.bezierCurveTo(73, 72, 86, 60, 86, 45); c.bezierCurveTo(86, 28, 70, 14, 50, 14); c.fill();
                    circle(34, 40, 7, "#FF5C7A"); circle(52, 30, 7, "#5B8CFF"); circle(70, 40, 7, "#46C46E"); circle(72, 58, 7, "#B57CF2");
                } else if (t.art === "star") {
                    c.fillStyle = "#FFE066"; c.strokeStyle = "#FFFFFF"; c.lineWidth = 4; c.lineJoin = "round"; c.beginPath();
                    const p = [[50, 12], [60, 33], [83, 36], [66, 52], [70, 75], [50, 64], [30, 75], [34, 52], [17, 36], [40, 33]];
                    c.moveTo(p[0][0], p[0][1]); for (let i = 1; i < p.length; i++) c.lineTo(p[i][0], p[i][1]); c.closePath(); c.fill(); c.stroke();
                } else if (t.art === "animal") {
                    circle(50, 56, 28, "#FFFFFF"); circle(28, 30, 12, "#FFFFFF"); circle(72, 30, 12, "#FFFFFF");
                    circle(40, 52, 4, "#1F2340"); circle(60, 52, 4, "#1F2340"); circle(50, 66, 5, "#1F2340");
                } else {
                    c.strokeStyle = "rgba(31,35,64,0.35)"; c.lineWidth = 7; c.lineCap = "round";
                    c.beginPath(); c.moveTo(50, 22); c.lineTo(50, 78); c.moveTo(22, 50); c.lineTo(78, 50); c.stroke();
                }
            }
        }
        // levels reached
        Row {
            visible: t.ready && t.level > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: t.u(40)
            spacing: t.u(6)
            Repeater {
                model: 3
                delegate: Rectangle { required property int index; width: t.u(16); height: width; radius: width / 2; color: index < t.level ? "white" : Qt.rgba(1, 1, 1, 0.45) }
            }
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: face
        hoverEnabled: true
        enabled: t.ready
        cursorShape: t.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: t.picked()
    }
}
