import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Starting a mode that locks you in by hand (Mod+Ctrl+n, the picker, Settings → Apply)
// asks first: "Start Drawing? You'll be locked in for 15 min". Enter starts, Esc
// cancels, and it cancels by itself after 10 seconds (Session.qml). Scheduled starts
// don't ask (they have their own heads-up).
Item {
    id: cs
    signal closeRequested()
    function reset() { forceActiveFocus(); }
    focus: true
    Keys.onReturnPressed: Session.confirmStart()
    Keys.onEnterPressed: Session.confirmStart()
    Keys.onEscapePressed: Session.cancelStart()
    readonly property var c: Session.pending || ({})

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.s(22); anchors.rightMargin: Theme.s(22)
        spacing: Theme.s(16)
        Rectangle {
            implicitWidth: Theme.s(48); implicitHeight: Theme.s(48); radius: Theme.s(16)
            color: Theme.accentSoft
            Icon { anchors.centerIn: parent; path: "M7 11 V8 A5 5 0 0 1 17 8 V11 M5 11 H19 V20 H5 Z"; size: Theme.s(22); color: Theme.accent }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.s(3)
            Text { text: "Start " + (cs.c.name || "") + "?"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: "You'll be locked in for " + Session.left(60 * (cs.c.duration || 0)) + " · emergency exit: hold Mod + Esc"
                color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12)
            }
            Row {
                Layout.topMargin: Theme.s(8)
                spacing: Theme.s(8)
                HoverButton {
                    implicitWidth: st.implicitWidth + Theme.s(30); implicitHeight: Theme.s(32); radius: Theme.s(10)
                    hoverFill: false
                    color: hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
                    onClicked: Session.confirmStart()
                    Text { id: st; anchors.centerIn: parent; text: "Start"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold }
                }
                HoverButton {
                    implicitWidth: cn.implicitWidth + Theme.s(30); implicitHeight: Theme.s(32); radius: Theme.s(10)
                    hoverFill: false
                    color: Theme.white(hovered ? 0.16 : 0.1)
                    onClicked: Session.cancelStart()
                    Text { id: cn; anchors.centerIn: parent; text: "Cancel"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
                }
            }
        }
        // the 10 seconds before it cancels itself
        Text { Layout.alignment: Qt.AlignTop; text: Session.pendingLeft + "s"; color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11) }
    }
}
