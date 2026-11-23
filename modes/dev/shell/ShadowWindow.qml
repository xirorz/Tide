import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"
import "services"

// Glass mode only: the surfaces' drop shadows in their own layer, under the shell.
// Hyprland blurs the "tide-shell" layer wherever it is more than 40% opaque; a shadow
// stacked on the screen dim crosses that and showed as a blurred ring. This layer has
// no blur rule, so shadows here never blur.
PanelWindow {
    id: sw
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.namespace: "tide-shadows"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Repeater {
        model: Shadows.items
        delegate: SurfaceShadow {
            id: d
            required property var modelData
            readonly property var src: modelData
            visible: src.visible && src.QsWindow.window && src.QsWindow.window.screen === sw.screen
            w: src.width
            h: src.height
            radius: src.radius
            spec: src.spec
            // follow the surface (the island morphs, panels open and close)
            FrameAnimation {
                running: d.visible
                onTriggered: {
                    const p = d.src.mapToItem(null, 0, 0);
                    d.x = p.x;
                    d.y = p.y;
                }
            }
        }
    }
}
