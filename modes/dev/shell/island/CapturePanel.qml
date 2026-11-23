import QtQuick
import QtQuick.Layouts
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// The island's capture state (560x214): screenshot and record rows (region, window,
// screen, folder), then OCR, color picker and timer. The island closes first, then
// the shared Capture service (also used by the control center) runs the tool.
Item {
    id: cap
    signal closeRequested()
    function reset() { forceActiveFocus(); }
    focus: true
    Keys.onEscapePressed: cap.closeRequested()

    function go(fn) { cap.closeRequested(); fn(); }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.s(16)
        anchors.rightMargin: Theme.s(16)
        anchors.topMargin: Theme.s(14)
        anchors.bottomMargin: Theme.s(14)
        spacing: Theme.s(10)

        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: "Capture"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.type.h2[0]; font.weight: Theme.type.h2[1] }
            HoverButton {
                implicitWidth: Theme.s(28); implicitHeight: Theme.s(28)
                onClicked: cap.closeRequested()
                Icon { anchors.centerIn: parent; path: Icons.close; size: Theme.s(14); color: Theme.muted }
            }
        }

        // 92px label | three buttons | 36px folder
        GridLayout {
            Layout.fillWidth: true
            columns: 5
            columnSpacing: Theme.s(8)
            rowSpacing: Theme.s(8)

            Text { Layout.preferredWidth: Theme.s(92); text: "Screenshot"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            Tool { label: "Region"; icon: Icons.shotRegion; onClicked: cap.go(() => Capture.screenshot("region")) }
            Tool { label: "Window"; icon: Icons.shotWindow; onClicked: cap.go(() => Capture.screenshot("window")) }
            Tool { label: "Screen"; icon: Icons.shotScreen; onClicked: cap.go(() => Capture.screenshot("screen")) }
            Folder { onClicked: Capture.openScreenshots() }

            Row {
                Layout.preferredWidth: Theme.s(92)
                spacing: Theme.s(6)
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Theme.s(7); height: Theme.s(7); radius: Theme.s(4); color: Theme.red }
                Text { text: "Record"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            }
            Tool { label: "Region"; icon: Icons.corners; dot: Qt.point(12, 12); dotR: 2.5; onClicked: cap.go(() => Capture.record("region")) }
            Tool { label: "Window"; icon: Icons.shotWindow; dot: Qt.point(12, 14); dotR: 2; onClicked: cap.go(() => Capture.record("window")) }
            Tool { label: "Screen"; icon: Icons.shotScreen; dot: Qt.point(12, 10); dotR: 2; onClicked: cap.go(() => Capture.record("screen")) }
            Folder { onClicked: Capture.openRecordings() }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.white(0.08) }

        Row {
            spacing: Theme.s(8)
            Small { label: "OCR"; icon: Icons.ocr; onClicked: cap.go(() => Capture.ocr()) }
            Small { label: "Color picker"; icon: Icons.picker; onClicked: cap.go(() => Capture.colorPicker()) }
            Small { label: "Timer"; icon: Icons.timer; onClicked: { cap.closeRequested(); Capture.timer(); } }
        }
    }

    // 44px tile: icon + label side by side
    component Tool: HoverButton {
        id: t
        property string label
        property string icon
        property point dot: Qt.point(-1, -1)
        property real dotR: 0
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: Theme.s(44)
        radius: Theme.s(12)
        hoverFill: false
        color: Theme.white(0.08)
        Row {
            anchors.centerIn: parent
            spacing: Theme.s(7)
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.s(16); height: Theme.s(16)
                Icon { path: t.icon }
                Icon { visible: t.dotR > 0; path: Icons.circle(t.dot.x, t.dot.y, t.dotR); filled: true; stroke: -1 }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: t.label; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
        }
    }
    component Folder: HoverButton {
        Layout.preferredWidth: Theme.s(36)
        implicitHeight: Theme.s(44)
        Icon { anchors.centerIn: parent; path: Icons.folder; color: Theme.muted }
    }
    component Small: HoverButton {
        id: sm
        property string label
        property string icon
        width: smRow.implicitWidth + Theme.s(24)
        height: Theme.s(32)
        Row {
            id: smRow
            anchors.centerIn: parent
            spacing: Theme.s(6)
            Icon { anchors.verticalCenter: parent.verticalCenter; path: sm.icon; size: Theme.s(14); color: Theme.text2 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: sm.label; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
        }
    }
}
