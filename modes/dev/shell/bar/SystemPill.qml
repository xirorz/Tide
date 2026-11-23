import QtQuick
import "../components/Icons.js" as Icons
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// Network activity arrows and resource rings (CPU, RAM, GPU).
// Numbers only appear on hover, VRAM first.
Pill {
    id: root
    padH: Theme.s(14)
    spacing: Theme.s(12)

    // network: down lit while downloading, up lit while uploading
    Row {
        spacing: -Theme.s(6)
        // each direction has its own wallpaper color while traffic flows
        Icon { path: Icons.down; color: Stats.downloading ? Theme.netDown : Theme.fg(0.3) }
        Icon { path: Icons.up; color: Stats.uploading ? Theme.netUp : Theme.fg(0.3) }
    }

    Item {
        id: res
        implicitWidth: rings.implicitWidth
        implicitHeight: Theme.s(15)

        Row {
            id: rings
            spacing: Theme.s(5)
            Ring { value: Stats.cpu / 100 }
            Ring { value: Stats.ramUsed / Stats.ramTotal }
            Ring { value: Stats.gpu < 0 ? 0 : Stats.gpu / 100 }
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: IslandState.open("resources", "") }

        // hover card: 200px panel, 32px under the rings
        Item {
            id: tip
            visible: hover.hovered
            width: Theme.s(200)
            height: tipCol.implicitHeight + Theme.s(24)
            x: (res.width - width) / 2
            y: Theme.s(32)
            z: 10

            Surface { anchors.fill: parent; kind: "panel"; radius: Theme.s(14) }

            Column {
                id: tipCol
                x: Theme.s(14); y: Theme.s(12)
                width: parent.width - Theme.s(28)
                spacing: Theme.s(7)

                // VRAM first, with its bar, then a divider (padding-bottom 8 + 1px border)
                Item {
                    width: parent.width
                    height: vram.implicitHeight + Theme.s(9)
                    visible: Stats.vramTotal > 0
                    Column {
                        id: vram
                        width: parent.width
                        spacing: Theme.s(6)
                        TipRow { label: "VRAM"; value: Stats.gb(Stats.vramUsed) + " / " + Stats.gbTotal(Stats.vramTotal) + " GB"; strong: true }
                        Rectangle {
                            width: parent.width; height: Theme.s(4); radius: Theme.s(2)
                            color: Theme.white(0.15)
                            Rectangle { width: parent.width * Math.min(1, Stats.vramUsed / Stats.vramTotal); height: Theme.s(4); radius: Theme.s(2); color: Theme.accent }
                        }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.white(0.08) }
                }
                TipRow { label: "CPU"; value: Stats.cpu + "%" }
                TipRow { label: "RAM"; value: Stats.gb(Stats.ramUsed) + " / " + Stats.gbTotal(Stats.ramTotal) + " GB" }
                TipRow { label: "GPU"; value: Stats.gpu < 0 ? "–" : Stats.gpu + "%" }
                TipRow { label: "Temp"; value: Stats.temp < 0 ? "–" : Stats.temp + "°C" }
                Column {
                    width: parent.width
                    spacing: 0
                    Rectangle { width: parent.width; height: 1; color: Theme.white(0.08) }
                    Text {
                        topPadding: Theme.s(4)
                        text: "Click for resource center"
                        color: Theme.muted
                        font.family: Theme.sans
                        font.pixelSize: Theme.s(11)
                    }
                }
            }
        }
    }

    component TipRow: Item {
        property string label
        property string value
        property bool strong: false
        width: parent ? parent.width : 0
        implicitHeight: Math.max(l.implicitHeight, v.implicitHeight)
        Text { id: l; text: parent.label; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
        Text {
            id: v
            anchors.right: parent.right
            anchors.baseline: l.baseline
            text: parent.value
            color: Theme.text
            font.family: Theme.mono
            font.pixelSize: Theme.s(12)
            font.weight: parent.strong ? Font.Medium : Font.Normal
        }
    }
}
