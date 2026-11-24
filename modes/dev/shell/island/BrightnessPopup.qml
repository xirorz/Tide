import QtQuick
import QtQuick.Layouts
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// The island's brightness pop-up (like the volume one): the screen's brightness, with
// a slider you can drag. Shown by the brightness keys; hides after 3.5s (paused while
// hovered). Never takes the keyboard or dims the screen.
Item {
    id: bp

    Binding {
        target: IslandState
        property: "volumeHovered"
        value: bp.visible && area.containsMouse
    }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.s(16)
        anchors.rightMargin: Theme.s(16)
        spacing: Theme.s(12)

        Icon { size: Theme.s(18); color: Theme.accent; path: Icons.sun }
        VolumeSlider {
            Layout.fillWidth: true
            fill: Theme.accent
            value: Power.brightness
            onMoved: v => Power.setBrightness(v)
        }
        Text {
            Layout.preferredWidth: Theme.s(30)
            horizontalAlignment: Text.AlignRight
            text: Math.round(Power.brightness * 100) + "%"
            color: Theme.text
            font.family: Theme.mono
            font.pixelSize: Theme.s(12)
        }
    }
}
