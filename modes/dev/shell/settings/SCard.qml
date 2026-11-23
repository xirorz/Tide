import QtQuick
import QtQuick.Layouts
import ".."

// A settings card: tile background, radius 16, rows stacked (SRow), optional small
// grey title above it like the design's "Metrics" / "Default apps".
ColumnLayout {
    id: c
    property string title: ""
    default property alias rows: body.data
    Layout.fillWidth: true
    spacing: Theme.s(6)
    Text {
        visible: c.title !== ""
        Layout.leftMargin: Theme.s(4)
        Layout.bottomMargin: Theme.s(2)
        text: c.title
        color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight
        radius: Theme.s(16)
        color: Theme.tile
        ColumnLayout {
            id: body
            width: parent.width
            spacing: 0
        }
    }
}
