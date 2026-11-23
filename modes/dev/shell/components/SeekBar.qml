import QtQuick
import QtQuick.Shapes
import ".."

// The design's wavy seek bar: the played part is a moving accent squiggle (while
// `animating`), then a short accent handle, then a thin track. Click to seek.
Item {
    id: sb
    property real progress: 0
    property bool animating: false
    signal seek(real f)
    implicitHeight: Theme.s(16)
    readonly property real p: Math.max(0, Math.min(1, progress))
    Item {
        id: played
        width: Math.min(sb.p * sb.width, sb.width - Theme.s(14))
        height: Theme.s(16)
        clip: true
        // the wave is drawn at the design's size and scaled with the interface size
        Shape {
            width: 420; height: 16
            scale: Theme.uiScale
            transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer
            NumberAnimation on x { from: -16 * Theme.uiScale; to: 0; duration: 1100; loops: Animation.Infinite; running: sb.animating && !Theme.reduceMotion }
            ShapePath {
                strokeColor: Theme.accent
                strokeWidth: 2.5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathSvg { path: "M0 8 q4 -7 8 0" + " t8 0".repeat(52) }
            }
        }
    }
    Rectangle {
        x: played.width + Theme.s(5)
        width: Theme.s(4); height: Theme.s(16); radius: Theme.s(2)
        color: Theme.accent
    }
    Rectangle {
        x: played.width + Theme.s(14)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, sb.width - x); height: Theme.s(3); radius: Theme.s(2)
        color: Theme.white(0.18)
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: m => sb.seek(Math.max(0, Math.min(1, m.x / width)))
    }
}
