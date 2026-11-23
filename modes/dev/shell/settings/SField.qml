import QtQuick
import ".."

// A text box for settings: saves when you press Enter or leave it (done), with a grey
// hint while empty; secret hides what's typed.
Rectangle {
    id: fld
    property alias text: inp.text
    property string hint
    property bool secret: false
    signal done(string value)
    signal edited(string value)       // every change, as you type
    implicitWidth: Theme.s(240); implicitHeight: Theme.s(34); radius: Theme.s(10)
    color: Qt.rgba(0, 0, 0, 0.3)
    border.width: 1; border.color: inp.activeFocus ? Theme.accentLine : Theme.white(0.1)
    TextInput {
        id: inp
        anchors.fill: parent; anchors.leftMargin: Theme.s(12); anchors.rightMargin: Theme.s(12)
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        echoMode: fld.secret ? TextInput.Password : TextInput.Normal
        color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(12)
        onEditingFinished: fld.done(text)
        onTextChanged: fld.edited(text)
        Text { visible: !inp.text; anchors.verticalCenter: parent.verticalCenter; text: fld.hint; color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
    }
}
