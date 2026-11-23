import QtQuick
import QtQuick.Layouts
import ".."

// A section that isn't built yet: its title and what it will hold.
ColumnLayout {
    property string title
    property string plan
    spacing: Theme.s(16)
    Heading { text: parent.title }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: planText.implicitHeight + Theme.s(32)
        radius: Theme.s(16)
        color: Theme.tile
        Text {
            id: planText
            x: Theme.s(16); y: Theme.s(16)
            width: parent.width - Theme.s(32)
            wrapMode: Text.WordWrap
            lineHeight: Theme.s(19); lineHeightMode: Text.FixedHeight
            text: parent.parent.plan
            color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(13)
        }
    }
}
