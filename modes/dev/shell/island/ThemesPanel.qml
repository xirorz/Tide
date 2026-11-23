import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Widgets
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// The island's theme picker (Mod+T, 640x200): a row of up to four cards, one per mode
// from the mode manager. The active one is tinted with a check; clicking a card (or
// Enter on the selected one) applies it and the island shrinks back.
Item {
    id: th
    signal closeRequested()
    property int sel: 0
    function reset() {
        Modes.refresh();
        sel = Math.max(0, Modes.list.findIndex(m => m.active));
        forceActiveFocus();
    }
    function apply(i) {
        const m = Modes.list[i];
        if (!m) return;
        th.closeRequested();
        Modes.apply(m.id);
    }
    focus: true
    Keys.onEscapePressed: th.closeRequested()
    Keys.onLeftPressed: sel = Math.max(0, sel - 1)
    Keys.onRightPressed: sel = Math.min(Modes.list.length - 1, sel + 1)
    Keys.onReturnPressed: apply(sel)
    Keys.onEnterPressed: apply(sel)

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.s(18)
        anchors.rightMargin: Theme.s(18)
        anchors.topMargin: Theme.s(16)
        anchors.bottomMargin: Theme.s(16)
        spacing: Theme.s(12)

        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: "Themes"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.type.h2[0]; font.weight: Theme.type.h2[1] }
            Text { text: "Applies layout, widgets, wallpaper, bar and app limits"; color: Theme.muted; font.family: Theme.sans; font.pointSize: Theme.sf(8.625) }
        }

        // four columns, like the design; cards fill from the left
        Row {
            id: cards
            Layout.fillWidth: true
            spacing: Theme.s(10)
            readonly property real cardW: (width - 3 * spacing) / 4
            Repeater {
                model: Modes.list.slice(0, 4)
                delegate: HoverButton {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property bool on: modelData.active
                    readonly property color glow: modelData.art[0] || "#9A9AA0"
                    width: cards.cardW
                    height: cardCol.implicitHeight + Theme.s(16)
                    radius: Theme.s(16)
                    hoverFill: false
                    color: on ? Theme.accentSoft : Theme.white(hovered || th.sel === index ? 0.09 : 0.05)
                    // active: accent ring; keyboard selection: a faint white ring
                    border.width: on ? 1.5 : th.sel === index ? 1 : 0
                    border.color: on ? Theme.accent : Theme.white(0.35)
                    onClicked: th.apply(index)
                    Column {
                        id: cardCol
                        x: Theme.s(8); y: Theme.s(8)
                        width: parent.width - Theme.s(16)
                        spacing: Theme.s(8)
                        // preview: the mode's two colors, a glow over a dark fade, a tiny bar
                        ClippingRectangle {
                            width: parent.width; height: Theme.s(78); radius: Theme.s(10)
                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    orientation: Gradient.Vertical
                                    GradientStop { position: 0; color: card.modelData.art[1] || "#141416" }
                                    GradientStop { position: 1; color: "#050507" }
                                }
                            }
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeWidth: -1
                                    fillGradient: RadialGradient {
                                        centerX: cardCol.width * 0.25; centerY: Theme.s(78) * 0.3
                                        // the design's radial-gradient(70% 90% at 25% 30%, a 0%, transparent 65%)
                                        centerRadius: cardCol.width * 0.75
                                        focalX: centerX; focalY: centerY
                                        GradientStop { position: 0; color: card.glow }
                                        GradientStop { position: 0.65; color: Qt.rgba(card.glow.r, card.glow.g, card.glow.b, 0) }
                                    }
                                    PathRectangle { width: cardCol.width; height: Theme.s(78) }
                                }
                            }
                            Rectangle { x: Theme.s(6); y: Theme.s(5); width: parent.width - Theme.s(12); height: Theme.s(6); radius: Theme.s(3); color: Qt.rgba(0, 0, 0, 0.45) }
                            Rectangle {
                                visible: card.on
                                anchors.right: parent.right; anchors.bottom: parent.bottom
                                anchors.margins: Theme.s(6)
                                width: Theme.s(20); height: Theme.s(20); radius: Theme.s(10)
                                color: Theme.accent
                                Icon { anchors.centerIn: parent; path: Icons.check; size: Theme.s(12); stroke: 2.6; color: Theme.ink }
                            }
                        }
                        Column {
                            x: Theme.s(2)
                            width: parent.width - Theme.s(4)
                            spacing: Theme.s(2)
                            Text { text: card.modelData.name; color: Theme.text; font.family: Theme.sans; font.pointSize: Theme.sf(9.375); font.weight: Font.DemiBold }
                            Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.description; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                        }
                    }
                }
            }
        }
    }
}
