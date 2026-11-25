import QtQuick
import ".."
import "../components"

// A small text button for the control center's questions (Confirm / Cancel); primary
// is filled with the accent.
HoverButton {
    property string label
    property bool primary: false
    width: sbLbl.implicitWidth + Theme.s(28)
    height: Theme.s(30)
    radius: Theme.s(9)
    hoverFill: !primary
    color: primary ? Theme.accent : Theme.white(0.07)
    Text { id: sbLbl; anchors.centerIn: parent; text: parent.label; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium; color: parent.primary ? Theme.ink : Theme.text2 }
}
