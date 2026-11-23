import QtQuick
import ".."
import "../components"

// A small settings button: plain, or primary (accent).
HoverButton {
    id: b
    property string label
    property bool primary: false
    implicitWidth: t.implicitWidth + Theme.s(28); implicitHeight: Theme.s(32); radius: Theme.s(9)
    hoverFill: false
    color: primary ? (hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent) : Theme.white(hovered ? 0.14 : 0.08)
    Text { id: t; anchors.centerIn: parent; text: b.label; color: b.primary ? Theme.ink : Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: b.primary ? Font.DemiBold : Font.Normal }
}
