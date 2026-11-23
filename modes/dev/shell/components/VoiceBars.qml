import QtQuick
import ".."
import "../services"

// 5 thick accent bars (like the old whisper overlay): live = follow the mic,
// otherwise bounce in a wave while transcribing
Row {
    id: vb
    property bool live: true
    property real phase: 0
    spacing: Theme.s(5)
    height: Theme.s(30)
    NumberAnimation on phase {
        from: 0; to: Math.PI * 2; duration: 900; loops: Animation.Infinite
        running: !vb.live && vb.visible && !Theme.reduceMotion
    }
    Repeater {
        model: [0.4, 0.75, 1, 0.75, 0.4]
        delegate: Rectangle {
            required property var modelData
            required property int index
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.s(4); radius: Theme.s(2)
            color: Theme.accent
            height: vb.live ? Theme.s(4) + Theme.s(24) * Math.min(1, (Voice.levels[index] || 0) * 1.6) * modelData
                            : Theme.s(4) + (Math.sin(vb.phase + index) * 0.5 + 0.5) * Theme.s(22)
            Behavior on height { enabled: vb.live; NumberAnimation { duration: 80 } }
        }
    }
}
