import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// "While you're away" (design: 360 wide): what your agents and tests are doing. The
// rows come from Widgets.status (a stub to fill in, like EveData.qml).
Item {
    implicitWidth: Theme.s(360)
    implicitHeight: col.implicitHeight + Theme.s(32)
    ColumnLayout {
        id: col
        x: Theme.s(18); y: Theme.s(16)
        width: Theme.s(324)
        spacing: Theme.s(12)
        Text { text: "While you're away"; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold }
        Text { visible: Widgets.status.length === 0; text: "Nothing running right now."; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
        Repeater {
            model: Widgets.status
            delegate: ColumnLayout {
                id: row
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: Theme.s(7)
                Rectangle { visible: row.index > 0; Layout.fillWidth: true; implicitHeight: 1; color: Theme.white(0.1) }
                RowLayout {
                    Layout.fillWidth: true
                    Row {
                        Layout.fillWidth: true
                        spacing: Theme.s(8)
                        Icon { anchors.verticalCenter: parent.verticalCenter; path: row.modelData.icon || "M4 17 L10 12 L4 7 M12 19 H20"; size: Theme.s(14); color: Theme.text }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: row.modelData.label; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                    }
                    Text { text: row.modelData.value || ""; color: Theme.text2; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                }
                Rectangle {
                    visible: row.modelData.progress >= 0
                    Layout.fillWidth: true
                    implicitHeight: Theme.s(4); radius: Theme.s(2)
                    color: Theme.white(0.18)
                    Rectangle { width: parent.width * Math.max(0, row.modelData.progress || 0); height: Theme.s(4); radius: Theme.s(2); color: Theme.accent }
                }
            }
        }
    }
}
