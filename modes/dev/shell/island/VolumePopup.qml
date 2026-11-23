import QtQuick
import QtQuick.Layouts
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// The island's volume pop-up (380x48): output switch (headphones / studio speakers),
// the level and the output's name. Shown by the volume/mute keys; hides after
// 3.5s (paused while hovered). Never takes the keyboard or dims the screen.
Item {
    id: vp

    Binding {
        target: IslandState
        property: "volumeHovered"
        value: vp.visible && (area.containsMouse || outBtn.hovered)
    }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.s(14)
        anchors.rightMargin: Theme.s(16)
        spacing: Theme.s(12)

        HoverButton {
            id: outBtn
            implicitWidth: Theme.s(30); implicitHeight: Theme.s(30); radius: Theme.s(15)
            onClicked: Audio.toggleOutput()
            Icon { anchors.centerIn: parent; size: Theme.s(18); color: Theme.accent; path: Audio.headphonesActive ? Icons.headset : Icons.speakers }
        }
        VolumeSlider {
            Layout.fillWidth: true
            fill: Audio.muted ? Theme.muted : Theme.accent
            value: Audio.volume
            onMoved: v => Audio.setVolume(v)
        }
        Text {
            Layout.preferredWidth: Theme.s(26)
            horizontalAlignment: Text.AlignRight
            text: Math.round(Audio.volume * 100)
            color: Theme.text
            font.family: Theme.mono
            font.pixelSize: Theme.s(12)
        }
        Text {
            text: Audio.headphonesActive ? "Headphones" : Audio.sink === Audio.speakers ? "Studio speakers" : (Audio.sink ? (Audio.sink.description || Audio.sink.name) : "")
            color: Theme.muted
            font.family: Theme.sans
            font.pointSize: Theme.sf(11.5 * 0.75)
            elide: Text.ElideRight
            Layout.maximumWidth: Theme.s(110)
        }
    }
}
