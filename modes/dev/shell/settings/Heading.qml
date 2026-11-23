import QtQuick
import QtQuick.Layouts
import ".."

// A section title (the sheet's h1, 22/700) with an optional grey line under it.
ColumnLayout {
    property string text
    property string sub: ""
    spacing: Theme.s(4)
    Text { Layout.fillWidth: true; text: parent.text; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.type.h1[0]; font.weight: Theme.type.h1[1]; font.letterSpacing: Theme.type.h1[2] }
    Text {
        visible: parent.sub !== ""
        Layout.fillWidth: true
        Layout.maximumWidth: Theme.s(560)
        wrapMode: Text.WordWrap
        lineHeight: Theme.s(19); lineHeightMode: Text.FixedHeight
        text: parent.sub; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(13)
    }
}
