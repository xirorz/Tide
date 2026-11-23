import QtQuick
import ".."
import "../components"

// A button on the game launcher's cards (install, details): plain, primary (accent)
// or danger (red). k: the launcher's screen scale.
HoverButton {
    id: cb
    property string label
    property bool primary: false
    property bool danger: false
    property real k: 1
    implicitWidth: cbt.implicitWidth + Math.round(30 * k); implicitHeight: Math.round(38 * k); radius: Math.round(12 * k)
    hoverFill: false
    color: danger ? Theme.red : primary ? (hovered ? Qt.lighter(Theme.accent, 1.1) : Theme.accent) : Theme.white(hovered ? 0.14 : 0.08)
    Text { id: cbt; anchors.centerIn: parent; text: cb.label; color: cb.danger ? "#FFFFFF" : cb.primary ? Theme.ink : Theme.text; font.family: Theme.sans; font.pixelSize: Math.round(13 * cb.k); font.weight: cb.primary || cb.danger ? Font.DemiBold : Font.Normal }
}
