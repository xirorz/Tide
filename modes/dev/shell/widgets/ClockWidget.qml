import QtQuick
import QtQuick.Effects
import Quickshell
import ".."
import "../services"

// The design's big clock, no card: 120px light time, the date under it. Settings →
// Widgets can add a soft shadow (for light wallpapers) and color it with the accent.
Item {
    SystemClock { id: clk; precision: SystemClock.Minutes }
    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight
    Column {
    id: col
    layer.enabled: Widgets.clockShadow
    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowBlur: 0.5; blurMax: 16; shadowScale: 1.02; shadowVerticalOffset: 0; shadowHorizontalOffset: 0; autoPaddingEnabled: true }
    spacing: Theme.s(4)
    Text {
        id: time
        text: (clk.date.getHours() % 12 || 12) + ":" + String(clk.date.getMinutes()).padStart(2, "0")
        color: Widgets.clockColor === "accent" ? Theme.accent : Theme.text; font.family: Widgets.clockFont.value; font.pixelSize: Theme.s(120); font.weight: Widgets.clockFont.weight
        font.letterSpacing: -0.04 * 120
        style: Widgets.clockShadow ? Text.Normal : Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.25)
    }
    Text {
        id: date
        leftPadding: Theme.s(6)
        text: Qt.formatDate(clk.date, "dddd, MMMM d")
        color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(18); font.weight: Font.Medium
        style: Widgets.clockShadow ? Text.Normal : Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.25)
    }
}
}
