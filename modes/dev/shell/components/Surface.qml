import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import ".."
import "../services"

// The background of a pill, panel or the island, exactly as the canvas draws it:
// fill, 1px border, a 1px inset highlight along the top (glass only) and an outer
// drop shadow that is cut out under the surface, like CSS box-shadow.
// The frosted blur itself comes from Hyprland (layer rule on "tide-shell", glass only).
Item {
    id: s
    property string kind: "bar"          // bar | card | panel | island
    property real radius: height / 2
    // the island scales its own radius; bars and panels follow Appearance → roundness here
    readonly property real rr: kind === "island" ? radius : Math.min(height / 2, radius * Theme.radiusScale)
    property bool glass: Theme.surface === "glass"

    readonly property var spec: {
        // Appearance → Bar style → Text and icons: bar pills draw nothing behind them
        if (kind === "bar" && Theme.barStyle === "text")
            return { fill: "transparent", border: 0, hl: 0, sy: 0, sb: 0, sa: 0 };
        // widget cards look like bar pills but always keep their background
        if (kind === "bar" || kind === "card")
            return glass ? { fill: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.42), border: 0.16, hl: 0.22, sy: 8, sb: 24, sa: 0.28 }
                         : { fill: Theme.barFill, border: 0.06, hl: 0, sy: 0, sb: 0, sa: 0 };
        if (kind === "panel")
            return glass ? { fill: Qt.rgba(30 / 255, 30 / 255, 33 / 255, 0.5), border: 0.16, hl: 0.2, sy: 30, sb: 80, sa: 0.5 }
                         : { fill: Theme.panelFill, border: 0.07, hl: 0, sy: 30, sb: 80, sa: 0.6 };
        // island: solid black in dark (the wallpaper's darkest tone in tinted), glass in glass
        return glass ? { fill: Qt.rgba(22 / 255, 22 / 255, 24 / 255, 0.62), border: 0.16, hl: 0.2, sy: 30, sb: 80, sa: 0.5 }
                     : { fill: Theme.islandFill, border: 0.08, hl: 0, sy: 30, sb: 80, sa: 0.55 };
    }

    // ---- outer shadow, masked out under the surface ----
    // Off by default ("shadows" in theme.json; the island follows "islandShadow").
    // When off, nothing is created: no layers, no MultiEffect. In dark mode the shadow
    // is drawn right here; in glass mode it goes to the unblurred shadow layer
    // (ShadowWindow.qml) so Hyprland's blur never catches it.
    readonly property bool shadowOn: (kind === "island" ? Theme.islandShadow : Theme.shadows) && spec.sa > 0
    readonly property bool shadowInLayer: shadowOn && glass
    onShadowInLayerChanged: shadowInLayer ? Shadows.add(s) : Shadows.remove(s)
    Component.onCompleted: if (shadowInLayer) Shadows.add(s)
    Component.onDestruction: Shadows.remove(s)
    Loader {
        active: s.shadowOn && !s.glass
        sourceComponent: SurfaceShadow { w: s.width; h: s.height; radius: s.rr; spec: s.spec }
    }

    // ---- fill + border ----
    Rectangle {
        anchors.fill: parent
        radius: s.rr
        color: s.spec.fill
        border.width: 1
        border.color: Theme.white(s.spec.border)
        antialiasing: true
    }

    // ---- inset 0 1px 0 highlight ----
    Item {
        visible: s.spec.hl > 0
        width: s.width
        height: Math.max(2, s.rr)
        clip: true
        Shape {
            width: s.width
            height: s.height
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: Theme.white(s.spec.hl)
                fillRule: ShapePath.OddEvenFill
                PathRectangle { x: 1; y: 1; width: s.width - 2; height: s.height - 2; radius: Math.max(0, s.rr - 1) }
                PathRectangle { x: 1; y: 2; width: s.width - 2; height: s.height - 2; radius: Math.max(0, s.rr - 1) }
            }
        }
    }
}
