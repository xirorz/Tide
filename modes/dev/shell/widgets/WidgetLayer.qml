import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// The desktop widgets: a layer under your windows (above the wallpaper) on the screen
// picked in Settings → Widgets. Each widget sits where you dragged it (edit mode);
// "Edit widgets" at the bottom shows the remove buttons and a gallery to add more.
PanelWindow {
    id: wl
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    // glass widgets get the same Hyprland blur as the bar ("tide-shell" layer rule)
    WlrLayershell.namespace: Widgets.cardGlass ? "tide-shell" : "tide-widgets"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // where each widget goes before you move it (the design's layout, 1440 × 900)
    function defaultPos(type) {
        const s = Theme.s, right = width - s(56) - s(360);
        return ({ clock: [s(56), s(96)], weather: [s(56), s(290)], nowplaying: [s(56), s(488)], notes: [s(56), s(678)],
                  calendar: [right, s(96)], status: [right, s(596)], system: [right - s(384), s(96)], printer: [right - s(464), s(96)] })[type] || [s(56), s(96)];
    }

    Repeater {
        model: Widgets.items
        delegate: WidgetFrame {
            required property var modelData
            type: modelData.type
            s: modelData.s || 1
            size: Widgets.sizeOf(modelData)
            // a box widget saved before boxes: its old scale becomes its size
            boxW: modelData.w || 340 * (modelData.s || 1)
            boxH: modelData.h || 150 * (modelData.s || 1)
            x: modelData.x >= 0 ? Math.min(modelData.x, wl.width - width) : wl.defaultPos(modelData.type)[0]
            y: modelData.y >= 0 ? Math.min(modelData.y, wl.height - height) : wl.defaultPos(modelData.type)[1]
        }
    }

    // ---------- edit mode: the gallery and the toggle ----------
    Item {
        visible: Widgets.editing && gallery.count > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.s(84)
        width: galleryRow.implicitWidth + Theme.s(24); height: Theme.s(108)
        Surface { anchors.fill: parent; kind: "panel"; glass: Widgets.cardGlass; radius: Theme.s(22) }
        Row {
            id: galleryRow
            x: Theme.s(12); y: Theme.s(12)
            spacing: Theme.s(10)
            Repeater {
                id: gallery
                model: Widgets.catalog.filter(c => !Widgets.has(c.type))
                delegate: HoverButton {
                    required property var modelData
                    width: Theme.s(104); height: Theme.s(84); radius: Theme.s(14)
                    hoverFill: false
                    color: hovered ? Theme.white(0.14) : Theme.white(0.08)
                    onClicked: Widgets.add(modelData.type)
                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.s(8)
                        Icon { anchors.horizontalCenter: parent.horizontalCenter; path: parent.parent.modelData.icon; size: Theme.s(20); color: Theme.soft }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.modelData.label; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                    }
                }
            }
        }
    }
    HoverButton {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.s(28)
        width: editRow.implicitWidth + Theme.s(32); height: Theme.s(36); radius: Theme.s(18)
        hoverFill: false
        color: Widgets.editing ? Theme.text : hovered ? Theme.white(0.18) : Theme.white(0.1)
        onClicked: if (Widgets.editing || Session.useTool("widgets")) Widgets.editing = !Widgets.editing
        Row {
            id: editRow
            anchors.centerIn: parent
            spacing: Theme.s(8)
            Icon { anchors.verticalCenter: parent.verticalCenter; path: "M4 4 H11 V11 H4 Z M13 4 H20 V11 H13 Z M4 13 H11 V20 H4 Z M16.5 13 V20 M13 16.5 H20"; size: Theme.s(14); color: Widgets.editing ? Theme.ink : Theme.text }
            Text { anchors.verticalCenter: parent.verticalCenter; text: Widgets.editing ? "Done" : "Edit widgets"; color: Widgets.editing ? Theme.ink : Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium }
        }
    }
}
