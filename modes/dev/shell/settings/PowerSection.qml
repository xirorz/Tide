import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Settings → Power (laptops only): the power mode, the screen's brightness and when
// Tide warns about a low battery. The control center's Battery card has the first two.
ColumnLayout {
    id: ps
    spacing: Theme.s(18)
    readonly property var minutes: [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60].map(m => ({ label: m === 0 ? "Never" : m < 60 ? m + " min" : "1 hour", value: m }))

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
            visible: Power.hasProfiles
            label: "Power saver on battery"
            sub: "Unplugged: Power saver. Plugged back in: your power mode again"
            SToggle { on: Power.saverOnBattery; onToggled: Theme.set("powerSaverOnBattery", !on) }
        }
        SRow {
            visible: Power.hasProfiles
            label: "Power saver when the battery gets low"
            sub: "At the warning level below"
            SToggle { on: Power.saverAtWarning; onToggled: Theme.set("powerSaverAtWarning", !on) }
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

    // idle on battery: sooner than plugged in (Apps and Hyprland → Idle has those)
    SCard {
        title: "On battery"
        SRow {
            label: "Shorter idle times on battery"
            sub: "Unplugged, these are used; plugged back in, your usual ones come back"
            SToggle { on: Power.batteryIdle; onToggled: Theme.set("idleOnBattery", !on) }
        }
        SRow { visible: Power.batteryIdle; label: "Dim the screen after"; SDropdown { mono: false; options: ps.minutes; value: Power.batteryTimings.dim; onPicked: v => Power.setBatteryTiming("dim", v) } }
        SRow { visible: Power.batteryIdle; label: "Lock after"; SDropdown { mono: false; options: ps.minutes; value: Power.batteryTimings.lock; onPicked: v => Power.setBatteryTiming("lock", v) } }
        SRow { visible: Power.batteryIdle; label: "Turn the screen off after"; SDropdown { mono: false; options: ps.minutes; value: Power.batteryTimings.dpms; onPicked: v => Power.setBatteryTiming("dpms", v) } }
        SRow { visible: Power.batteryIdle; last: true; label: "Sleep after"; SDropdown { mono: false; options: ps.minutes; value: Power.batteryTimings.suspend; onPicked: v => Power.setBatteryTiming("suspend", v) } }
    }

    // only where the battery supports it
    SCard {
        visible: Power.chargeLimitSupported
        title: "Battery health"
        SRow {
            last: true
            label: "Stop charging at"
            sub: "Keeping it below full helps the battery last longer" + (Power.chargeLimitWritable ? "" : " (asks for your password the first time)")
            SSegment {
                // a limit set elsewhere (the firmware's 85%) shows as its own choice, so one is lit
                options: {
                    const o = [{ label: "Full", value: 100 }, { label: "90%", value: 90 }, { label: "80%", value: 80 }, { label: "60%", value: 60 }];
                    if (o.every(x => x.value !== Power.chargeLimit)) o.push({ label: Power.chargeLimit + "%", value: Power.chargeLimit });
                    return o.sort((a, b) => b.value - a.value);
                }
                value: Power.chargeLimit
                onPicked: v => Power.setChargeLimit(v)
            }
        }
    }
}
