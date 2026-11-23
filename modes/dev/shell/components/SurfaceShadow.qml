import QtQuick
import QtQuick.Effects

// A surface's drop shadow, cut out under the surface like CSS box-shadow. Its origin
// is the surface's top-left corner. Drawn inside the surface in dark mode, and in the
// separate unblurred shadow layer in glass mode (see ShadowWindow.qml).
Item {
    id: sh
    property real w: 0
    property real h: 0
    property real radius: 0
    property var spec: ({ sy: 0, sb: 0, sa: 0 })
    readonly property real pad: spec.sb * 1.5 + spec.sy

    Item {
        id: shadowSrc
        visible: false
        x: -sh.pad; y: -sh.pad
        width: sh.w + sh.pad * 2; height: sh.h + sh.pad * 2
        layer.enabled: true
        RectangularShadow {
            x: sh.pad; y: sh.pad
            width: sh.w; height: sh.h
            radius: sh.radius
            offset: Qt.vector2d(0, sh.spec.sy)
            blur: sh.spec.sb
            color: Qt.rgba(0, 0, 0, sh.spec.sa)
        }
    }
    Item {
        id: shadowMask
        visible: false
        x: -sh.pad; y: -sh.pad
        width: shadowSrc.width; height: shadowSrc.height
        layer.enabled: true
        Rectangle {
            x: sh.pad; y: sh.pad
            width: sh.w; height: sh.h
            radius: sh.radius
            color: "white"
            antialiasing: true
        }
    }
    MultiEffect {
        x: -sh.pad; y: -sh.pad
        width: shadowSrc.width; height: shadowSrc.height
        source: shadowSrc
        maskEnabled: true
        maskInverted: true
        maskSource: shadowMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
