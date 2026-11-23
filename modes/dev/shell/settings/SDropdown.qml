import QtQuick
import QtQuick.Controls
import "../components/Icons.js" as Icons
import ".."
import "../components"

// A drop-down: the current choice with a chevron; clicking opens a list under it
// (over everything, scrolls past 8 rows) with a check on the current one.
// options: [{ label, value, note?, family? (shown in that font) }]
Item {
    id: dd
    property var options: []
    property var value
    property bool mono: true
    property bool interactive: true
    signal picked(var value)
    implicitWidth: Theme.s(220)
    implicitHeight: Theme.s(34)

    readonly property var current: options.find(o => String(o.value) === String(value))

    HoverButton {
        id: btn
        anchors.fill: parent
        radius: Theme.s(10)
        hoverFill: false
        enabled: dd.interactive
        opacity: enabled ? 1 : 0.5
        color: pop.opened ? Theme.white(0.14) : hovered ? Theme.white(0.12) : Theme.white(0.08)
        border.width: pop.opened ? 1 : 0
        border.color: Theme.accentLine
        onClicked: pop.opened ? pop.close() : pop.open()
        Text {
            anchors.left: parent.left; anchors.leftMargin: Theme.s(12)
            anchors.right: chev.left; anchors.rightMargin: Theme.s(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: dd.current ? dd.current.label : ""
            color: Theme.text
            font.family: dd.current && dd.current.family ? dd.current.family : dd.mono ? Theme.mono : Theme.sans; font.pixelSize: dd.current && dd.current.family ? Theme.s(13) : Theme.s(12)
        }
        Icon {
            id: chev
            anchors.right: parent.right; anchors.rightMargin: Theme.s(10)
            anchors.verticalCenter: parent.verticalCenter
            path: pop.opened ? Icons.chevronUp : Icons.chevronDown; size: Theme.s(14); color: Theme.muted
        }
    }

    Popup {
        id: pop
        y: dd.height + Theme.s(6)
        width: dd.width
        height: Math.min(Theme.s(8), dd.options.length) * 32 + Theme.s(12)
        padding: Theme.s(6)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: Theme.s(12)
            color: Theme.panelBg
            border.width: 1
            border.color: Theme.white(0.12)
        }
        contentItem: ListView {
            id: list
            clip: true
            model: dd.options
            boundsBehavior: Flickable.StopAtBounds
            Component.onCompleted: positionViewAtIndex(Math.max(0, dd.options.indexOf(dd.current)), ListView.Center)
            delegate: HoverButton {
                id: item
                required property var modelData
                readonly property bool on: String(modelData.value) === String(dd.value)
                width: list.width
                height: Theme.s(32)
                radius: Theme.s(8)
                hoverFill: false
                color: hovered ? Theme.white(0.08) : "transparent"
                onClicked: { pop.close(); dd.picked(item.modelData.value); }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: Theme.s(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: item.modelData.label
                    color: item.on ? Theme.accent : Theme.text
                    // a font choice is shown in its own font
                    font.family: item.modelData.family || (dd.mono ? Theme.mono : Theme.sans); font.pixelSize: item.modelData.family ? Theme.s(14) : Theme.s(12)
                    font.weight: item.on ? Font.DemiBold : Font.Normal
                }
                Text {
                    visible: !!item.modelData.note
                    anchors.right: tick.left; anchors.rightMargin: Theme.s(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: item.modelData.note || ""
                    color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(11)
                }
                Icon {
                    id: tick
                    visible: item.on
                    anchors.right: parent.right; anchors.rightMargin: Theme.s(10)
                    anchors.verticalCenter: parent.verticalCenter
                    path: Icons.check; size: Theme.s(13); stroke: 2; color: Theme.accent
                }
            }
        }
    }
}
