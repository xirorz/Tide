import QtQuick
import Quickshell
import ".."
import "../services"

// The Eve panel as a real floating window (title "Eve"), so Hyprland treats it like
// every other app: Mod + drag moves it, Mod + right-drag resizes it. Created fresh on
// each open at the saved size (theme.json "eveSize", the design's 572 × 828 at first)
// on the right (window rule "tide-eve" in hyprland.lua); the size you leave it at is
// kept for next time.
LazyLoader {
    active: EveData.open && Theme.aiEnabled
    FloatingWindow {
        id: w
        title: "AI"
        color: "transparent"
        visible: true
        // kept in design units, so it grows with Appearance → Interface size
        readonly property var saved: Theme.opt("eveSize", [572, 828])
        implicitWidth: Theme.s(saved[0])
        implicitHeight: Theme.s(saved[1])

        EvePanel { anchors.fill: parent }

        // closed from Hyprland (Mod+Q): the AI button follows
        onVisibleChanged: if (!visible) EveData.open = false

        function keep() {
            const dw = Math.round(w.width / Theme.uiScale), dh = Math.round(w.height / Theme.uiScale);
            if (dw > 300 && dh > 300 && (Math.abs(dw - w.saved[0]) > 1 || Math.abs(dh - w.saved[1]) > 1))
                Theme.set("eveSize", [dw, dh]);
        }
        onWidthChanged: saver.restart()
        onHeightChanged: saver.restart()
        Timer { id: saver; interval: 800; onTriggered: w.keep() }
        Component.onDestruction: keep()
    }
}
