import QtQuick
import QtQuick.Shapes
import ".."

// Resource ring: 15px, r6 on a 16 grid, 2px stroke, accent arc from 12 o'clock.
Item {
    id: r
    property real value: 0      // 0..1
    implicitWidth: Theme.s(15)
    implicitHeight: Theme.s(15)

    Shape {
        width: Theme.s(16); height: Theme.s(16)
        scale: 15 / 16
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.fg(0.2)
            strokeWidth: 2
            PathAngleArc { centerX: Theme.s(8); centerY: Theme.s(8); radiusX: Theme.s(6); radiusY: Theme.s(6); startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: r.value > 0 ? Theme.accent : "transparent"
            strokeWidth: 2
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: Theme.s(8); centerY: Theme.s(8); radiusX: Theme.s(6); radiusY: Theme.s(6); startAngle: -90; sweepAngle: 360 * Math.max(0, Math.min(1, r.value)) }
        }
    }
}
