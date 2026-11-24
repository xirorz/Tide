import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Settings → Power (laptops only): the power mode, the screen's brightness and when
// Tide warns about a low battery. The control center's Battery card has the first two.
ColumnLayout {
    spacing: Theme.s(18)

    Heading { text: "Power"; sub: Math.round(Power.level * 100) + "% · " + Power.status }

    SCard {
        title: "Battery"
        SRow {
            visible: Power.hasProfiles
            label: "Power mode"
            sub: "Power saver stretches the battery; Performance is the fastest"
            SSegment {
                options: [{ label: "Power saver", value: "saver" }, { label: "Balanced", value: "balanced" }]
                    .concat(Power.hasPerformance ? [{ label: "Performance", value: "performance" }] : [])
                value: Power.profile
                onPicked: v => Power.setProfile(v)
            }
        }
        SRow {
            visible: !Power.hasProfiles
            label: "Power mode"
            sub: "Needs power-profiles-daemon (the installer sets it up on laptops)"
        }
        SRow {
            last: true
            label: "Low battery warning"
            sub: "A notification at this level, and again at 5%"
            SSegment {
                options: [{ label: "Off", value: 0 }, { label: "10%", value: 10 }, { label: "15%", value: 15 }, { label: "20%", value: 20 }, { label: "30%", value: 30 }]
                value: Power.warnAt
                onPicked: v => Theme.set("batteryWarn", v)
            }
        }
    }

    SCard {
        visible: Power.hasBacklight
        title: "Screen"
        SRow {
            last: true
            label: "Brightness"
            SSlider {
                implicitWidth: Theme.s(240)
                from: 2; to: 100; step: 1
                value: Math.round(Power.brightness * 100)
                onMoved: v => Power.setBrightness(v / 100)
            }
        }
    }
}
