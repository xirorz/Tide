import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../services"

// Park mode's screen (services/Park.qml), over everything on every monitor. The main one
// holds the parked screen, his space, the games and "time's up"; the others show a calm
// sky. Sized from a 1440 × 900 design like the game launcher (k).
PanelWindow {
    id: ps
    required property var modelData
    screen: modelData
    readonly property bool main: modelData.name === (Theme.monitor || Quickshell.screens[0].name)
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: main ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "tide-park"
    color: "black"

    readonly property real k: Math.min(width / 1440, height / 900)
    function u(px) { return Math.round(px * k); }

    // the other screens: a quiet sky
    Rectangle {
        visible: !ps.main
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Park.view === "parked" ? "#141B2B" : Park.view === "timesup" ? "#2B2A6B" : "#8FD3FF" }
            GradientStop { position: 1; color: Park.view === "parked" ? "#0A0B10" : Park.view === "timesup" ? "#6A4FA8" : "#DDF4C8" }
        }
    }

    Item {
        visible: ps.main
        anchors.fill: parent
        focus: ps.main
        Loader {
            anchors.fill: parent
            sourceComponent: Park.view === "home" ? homeC : Park.view === "game" ? (Park.game === "letters" ? lettersC : bubbleC)
                : Park.view === "timesup" ? timesC : parkedC
            onLoaded: item.forceActiveFocus()
        }
        Component { id: parkedC; ParkedView { k: ps.k } }
        Component { id: homeC; KidHome { k: ps.k } }
        Component { id: bubbleC; BubblePop { k: ps.k } }
        Component { id: lettersC; LetterRain { k: ps.k } }
        Component { id: timesC; TimesUp { k: ps.k } }

        // the parent's hold, filling (no words: nothing for him to learn)
        Item {
            visible: Park.holding && Park.holdProgress > 0.15
            anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: ps.u(24)
            width: ps.u(44); height: ps.u(44)
            Canvas {
                anchors.fill: parent
                property real p: Park.holdProgress
                onPChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d"); c.reset();
                    c.lineWidth = width * 0.12; c.lineCap = "round";
                    c.strokeStyle = "rgba(255,255,255,0.25)";
                    c.beginPath(); c.arc(width / 2, height / 2, width * 0.4, 0, Math.PI * 2); c.stroke();
                    c.strokeStyle = "#FFFFFF";
                    c.beginPath(); c.arc(width / 2, height / 2, width * 0.4, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p); c.stroke();
                }
            }
        }
    }
}
