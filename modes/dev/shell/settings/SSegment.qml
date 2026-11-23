import QtQuick
import ".."

// Segmented choice on a dark well: the picked one is white with dark text (or the
// accent with `accentOn`). options: [{ label, value, enabled? }]
Rectangle {
    id: seg
    property var options: []
    property var value
    property bool accentOn: false
    signal picked(var value)
    implicitWidth: row.implicitWidth + Theme.s(6)
    implicitHeight: Theme.s(36)
    radius: Theme.s(11)
    color: Qt.rgba(0, 0, 0, 0.3)
    Row {
        id: row
        x: Theme.s(3); y: Theme.s(3)
        spacing: Theme.s(2)
        Repeater {
            model: seg.options
            delegate: Rectangle {
                id: opt
                required property var modelData
                readonly property bool on: seg.value === modelData.value
                readonly property bool usable: modelData.enabled !== false
                width: lbl.implicitWidth + Theme.s(32)
                height: Theme.s(30)
                radius: Theme.s(8)
                color: on ? (seg.accentOn ? Theme.accent : Theme.text) : ma.containsMouse && usable ? Theme.white(0.06) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 0 : Theme.durHover } }
                Text {
                    id: lbl
                    anchors.centerIn: parent
                    text: opt.modelData.label
                    color: opt.on ? Theme.ink : opt.usable ? Theme.text2 : Theme.dim
                    font.family: Theme.sans; font.pointSize: Theme.sf(9.375)
                    font.weight: opt.on && seg.accentOn ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: opt.usable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(opt.modelData.value)
                }
            }
        }
    }
}
