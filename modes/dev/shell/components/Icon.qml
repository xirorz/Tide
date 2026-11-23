import QtQuick
import ".."
import QtQuick.Shapes

// A stroke icon on the design's 24x24 grid (stroke 1.6, round caps and joins).
Item {
    id: ic
    property string path: ""
    property color color: "#F5F5F7"
    property real size: Theme.s(16)
    property real stroke: 1.6
    property bool filled: false

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 24
        height: 24
        scale: ic.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: ic.color
            strokeWidth: ic.stroke
            fillColor: ic.filled ? ic.color : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: ic.path }
        }
    }
}
