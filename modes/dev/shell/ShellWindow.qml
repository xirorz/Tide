import QtQuick
import Quickshell
import Quickshell.Wayland
import "bar"
import "island"
import "settings"
import "services"

// One full-screen, see-through layer per monitor holding the bar pills, the island
// and the dim behind it. Input only reaches the pills and the island, unless a tool
// is open (then clicking anywhere else closes it).
PanelWindow {
    id: win
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // only glass is blurred: in dark mode the layer has a name the blur rule ignores
    WlrLayershell.namespace: Theme.surface === "glass" ? "tide-shell" : "tide-shell-dark"
    WlrLayershell.layer: WlrLayer.Top
    // Settings steps aside while a file picker (Games.pick) is open, so it can take input
    readonly property bool settingsShown: IslandState.settingsOpen && !Games.picking && !IslandState.steppedAside
    WlrLayershell.keyboardFocus: island.grabs || bar.panelOpen || settingsShown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // while the island or a bar panel is open the whole layer takes input,
    // so a click anywhere else closes it
    mask: island.grabs || bar.panelOpen || settingsShown ? null : inputRegion
    Region {
        id: inputRegion
        item: bar.leftGroup
        Region { item: bar.rightGroup }
        Region { item: island.body }
    }

    // dim: rgba(0,0,0,0.35) while a tool is open, 0.3s ease
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, island.dims || settingsShown ? 0.35 : 0)
        Behavior on color { ColorAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }
        MouseArea {
            anchors.fill: parent
            enabled: island.grabs || bar.panelOpen || settingsShown
            onClicked: {
                // the calculator only closes with Escape or its X
                if (IslandState.mode !== "calculator") IslandState.close();
                bar.closePanels();
                IslandState.closeSettings();
            }
        }
    }

    Bar {
        id: bar
        anchors.fill: parent
        screen: win.screen
    }

    // Settings: built in the background once the bar is up (Boot), or at once if it's
    // opened first
    Loader {
        anchors.fill: parent
        asynchronous: !IslandState.settingsOpen && !Boot.finishNow
        active: IslandState.settingsOpen || Boot.settled || status === Loader.Ready
        onLoaded: if (!IslandState.settingsOpen) Boot.ready("settings")
        // Settings sizes itself from the screen, so it sits in a full-screen holder
        sourceComponent: Item {
            Settings {
                anchors.centerIn: parent
                visible: !Games.picking && !IslandState.steppedAside
            }
        }
    }

    // the bar's first frame: tells Boot to start building the rest
    FrameAnimation {
        running: !Boot.barShown
        onTriggered: Boot.shown()
    }

    Island {
        id: island
        anchors.fill: parent
        screen: win.screen
    }
}
