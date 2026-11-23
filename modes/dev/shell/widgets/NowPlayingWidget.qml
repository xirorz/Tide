import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Widgets
import ".."
import "../components"

// Now playing (design: 340 wide), in three sizes: small is a pill with the cover,
// title and play / pause; medium (the design) is the cover, title, artist, the music
// bars while playing, the wavy seek bar with times, and previous / play-pause / next;
// large puts a big cover on top.
Item {
    id: np
    property string size: "medium"
    readonly property bool small: size === "small"
    readonly property bool large: size === "large"
    implicitWidth: Theme.s(small ? 280 : 340)
    implicitHeight: col.implicitHeight + Theme.s(32)
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
    readonly property bool playing: player !== null && player.isPlaying
    Timer { interval: 1000; repeat: true; running: np.playing && !np.small; onTriggered: np.player.positionChanged() }
    function mmss(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }

    ColumnLayout {
        id: col
        x: Theme.s(16); y: Theme.s(16)
        width: np.implicitWidth - Theme.s(32)
        spacing: Theme.s(12)
        // large: the cover across the top
        ClippingRectangle {
            visible: np.large
            Layout.fillWidth: true
            implicitHeight: width; radius: Theme.s(16)
            color: "#18181B"
            Image { anchors.fill: parent; source: np.large && np.player && np.player.trackArtUrl ? np.player.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            Icon { visible: !np.player || !np.player.trackArtUrl; anchors.centerIn: parent; size: Theme.s(48); path: "M9 18 V6 L19 4 V16 M6.5 15.5 A2.5 2.5 0 1 0 6.51 15.5 M16.5 13.5 A2.5 2.5 0 1 0 16.51 13.5"; color: Theme.muted }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.s(12)
            ClippingRectangle {
                visible: !np.large
                implicitWidth: Theme.s(np.small ? 40 : 52); implicitHeight: implicitWidth; radius: Theme.s(np.small ? 10 : 12)
                color: "#18181B"
                Image { anchors.fill: parent; source: np.player && np.player.trackArtUrl ? np.player.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                Icon { visible: !np.player || !np.player.trackArtUrl; anchors.centerIn: parent; path: "M9 18 V6 L19 4 V16 M6.5 15.5 A2.5 2.5 0 1 0 6.51 15.5 M16.5 13.5 A2.5 2.5 0 1 0 16.51 13.5"; color: Theme.muted }
            }
            Column {
                Layout.fillWidth: true
                spacing: Theme.s(2)
                Text { width: parent.width; elide: Text.ElideRight; text: np.player ? (np.player.trackTitle || "Unknown track") : "Nothing playing"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(14); font.weight: Font.DemiBold }
                Text { width: parent.width; elide: Text.ElideRight; text: np.player ? [np.player.trackArtist, np.player.identity].filter(x => x).join(" · ") : "Play something to see it here"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            }
            EqBars { visible: np.playing && !np.small; running: np.playing && !np.small; Layout.alignment: Qt.AlignVCenter }
            // small: play / pause right here
            HoverButton {
                visible: np.small && np.player !== null
                implicitWidth: Theme.s(32); implicitHeight: Theme.s(32); radius: Theme.s(16)
                hoverFill: false
                color: Theme.text
                onClicked: if (np.player) np.player.togglePlaying()
                Icon { anchors.centerIn: parent; path: np.playing ? "M7 5 H10 V19 H7 Z M14 5 H17 V19 H14 Z" : "M8 5 V19 L19 12 Z"; filled: true; stroke: -1; color: Theme.ink }
            }
        }
        RowLayout {
            visible: np.player !== null && !np.small
            Layout.fillWidth: true
            spacing: Theme.s(10)
            Text { text: np.player ? np.mmss(np.player.position) : "0:00"; color: Theme.text2; font.family: Theme.mono; font.pointSize: Theme.sf(7.875) }
            SeekBar {
                Layout.fillWidth: true
                animating: np.playing
                progress: np.player && np.player.length > 0 ? np.player.position / np.player.length : 0
                onSeek: f => { if (np.player && np.player.canSeek) np.player.position = f * np.player.length; }
            }
            Text { text: np.player ? np.mmss(np.player.length) : "0:00"; color: Theme.text2; font.family: Theme.mono; font.pointSize: Theme.sf(7.875) }
        }
        Row {
            visible: np.player !== null && !np.small
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.s(22)
            HoverButton {
                width: Theme.s(32); height: Theme.s(32)
                onClicked: if (np.player) np.player.previous()
                Icon { anchors.centerIn: parent; path: "M18 6 V18 L9 12 Z M6 6 H8 V18 H6 Z"; filled: true; stroke: -1; color: Theme.text }
            }
            HoverButton {
                width: Theme.s(32); height: Theme.s(32); radius: Theme.s(16)
                hoverFill: false
                color: Theme.text
                onClicked: if (np.player) np.player.togglePlaying()
                Icon { anchors.centerIn: parent; path: np.playing ? "M7 5 H10 V19 H7 Z M14 5 H17 V19 H14 Z" : "M8 5 V19 L19 12 Z"; filled: true; stroke: -1; color: Theme.ink }
            }
            HoverButton {
                width: Theme.s(32); height: Theme.s(32)
                onClicked: if (np.player) np.player.next()
                Icon { anchors.centerIn: parent; path: "M6 6 V18 L15 12 Z M16 6 H18 V18 H16 Z"; filled: true; stroke: -1; color: Theme.text }
            }
        }
    }
}
