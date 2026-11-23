import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Weather (design: 340 wide), in three sizes: small is the place, temperature, sky and
// today's high and low; medium (the design) adds the next hours; large adds the next
// five days. Open-Meteo, once a location is set in Settings → Widgets.
Item {
    id: wd
    property string size: "medium"
    readonly property bool small: size === "small"
    readonly property bool large: size === "large"
    implicitWidth: Theme.s(small ? 220 : 340)
    implicitHeight: col.implicitHeight + Theme.s(36)
    readonly property var w: Widgets.location ? Widgets.weather : null
    ColumnLayout {
        id: col
        x: Theme.s(20); y: Theme.s(18)
        width: wd.implicitWidth - Theme.s(40)
        spacing: Theme.s(14)
        Text {
            visible: !Widgets.location || (!w && Widgets.weatherError)
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: !Widgets.location ? "Set your location in Settings → Widgets to see the weather." : Widgets.weatherError
            color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(13)
        }
        RowLayout {
            visible: !!w
            Layout.fillWidth: true
            Column {
                Layout.fillWidth: true
                spacing: Theme.s(2)
                Text { width: parent.width; elide: Text.ElideRight; text: Widgets.location ? Widgets.location.name : ""; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                Text { text: w ? w.temp + "°" : ""; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(wd.small ? 40 : 48); font.weight: Font.Light }
            }
            Column {
                Layout.alignment: Qt.AlignTop
                topPadding: Theme.s(4)
                spacing: Theme.s(6)
                Icon { anchors.right: parent.right; size: Theme.s(28); color: Theme.text; path: w ? Widgets.weatherIcon(w.code, w.day) : "" }
                Text { anchors.right: parent.right; text: w ? Widgets.weatherText(w.code) : ""; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                Text { anchors.right: parent.right; text: w ? "H " + w.high + "° · L " + w.low + "°" : ""; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
            }
        }
        // the next hours (medium and large)
        Rectangle { visible: !!w && !wd.small; Layout.fillWidth: true; implicitHeight: 1; color: Theme.white(0.1) }
        RowLayout {
            visible: !!w && !wd.small
            Layout.fillWidth: true
            Repeater {
                model: w ? w.hours : []
                delegate: Column {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.s(6)
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.modelData.t; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.modelData.d; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.Medium }
                }
            }
        }
        // the next five days (large)
        Rectangle { visible: !!w && wd.large; Layout.fillWidth: true; implicitHeight: 1; color: Theme.white(0.1) }
        ColumnLayout {
            visible: !!w && wd.large
            Layout.fillWidth: true
            spacing: Theme.s(10)
            Repeater {
                model: w && w.days ? w.days : []
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.s(12)
                    Text { Layout.preferredWidth: Theme.s(44); text: modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
                    Icon { size: Theme.s(18); color: Theme.soft; path: Widgets.weatherIcon(modelData.code, true) }
                    Text { Layout.fillWidth: true; text: Widgets.weatherText(modelData.code); color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12); elide: Text.ElideRight }
                    Text { text: modelData.low + "°"; color: Theme.text2; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                    Text { Layout.preferredWidth: Theme.s(34); horizontalAlignment: Text.AlignRight; text: modelData.high + "°"; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                }
            }
        }
    }
}
