pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import ".."

// Power on a laptop: the battery (level, charging, time left), the power mode
// (power-profiles-daemon: Power saver / Balanced / Performance), the screen's
// brightness (brightnessctl) and low-battery warnings. On a desktop nothing shows.
Singleton {
    id: root

    // ---- battery ----
    readonly property var dev: UPower.displayDevice
    property bool preview: false           // the laptop parts on a desktop (IPC, for trying them)
    readonly property bool hasBattery: preview || (!!dev && dev.ready && dev.isLaptopBattery)
    readonly property real level: dev && dev.ready && dev.isLaptopBattery ? dev.percentage : (preview ? 0.64 : 0)
    readonly property bool charging: !!dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: !!dev && dev.state === UPowerDeviceState.FullyCharged
    function hm(sec) {
        const m = Math.round(sec / 60);
        return m >= 60 ? Math.floor(m / 60) + " h " + (m % 60) + " min" : m + " min";
    }
    readonly property string status: {
        if (!hasBattery) return "";
        if (full) return "Full";
        if (charging) return dev.timeToFull > 0 ? "Charging · full in " + hm(dev.timeToFull) : "Charging";
        return dev && dev.timeToEmpty > 0 ? hm(dev.timeToEmpty) + " left" : (preview ? "3 h 10 min left" : "On battery");
    }

    // ---- power mode ----
    property bool hasProfiles: false
    Process { running: true; command: ["sh", "-c", "busctl --system status net.hadess.PowerProfiles >/dev/null 2>&1 || busctl --system status org.freedesktop.UPower.PowerProfiles >/dev/null 2>&1"]; onExited: code => root.hasProfiles = code === 0 }
    readonly property string profile: PowerProfiles.profile === PowerProfile.PowerSaver ? "saver" : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile
    function setProfile(p) {
        PowerProfiles.profile = p === "saver" ? PowerProfile.PowerSaver : p === "performance" ? PowerProfile.Performance : PowerProfile.Balanced;
    }

    // ---- screen brightness (the laptop's own panel) ----
    property bool hasBacklight: false
    property real brightness: 0            // 0..1
    function readBrightness() { if (!bl.running) bl.running = true; }
    Process {
        id: bl
        running: true
        command: ["brightnessctl", "-m", "-c", "backlight", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                // name,class,current,percent%,max
                const f = text.trim().split("\n")[0].split(",");
                root.hasBacklight = f.length >= 5 && f[1] === "backlight";
                if (root.hasBacklight) root.brightness = parseInt(f[3]) / 100;
            }
        }
    }
    function setBrightness(v) {
        brightness = Math.max(0.02, Math.min(1, v));
        Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "set", Math.round(brightness * 100) + "%"]);
    }
    // keys and other apps change it too
    Timer { interval: 5000; repeat: true; running: root.hasBacklight; onTriggered: root.readBrightness() }

    // ---- low battery: a warning at the level in Settings → Power, and again at 5% ----
    readonly property int warnAt: Theme.opt("batteryWarn", 20)
    property int warned: 101               // the lowest level warned about this discharge
    onLevelChanged: {
        if (!hasBattery || preview) return;
        const pct = Math.round(level * 100);
        if (charging || full) { warned = 101; return; }
        if (warnAt > 0 && pct <= warnAt && warned > warnAt) {
            warned = warnAt;
            Quickshell.execDetached(["notify-send", "-a", "Tide", "-i", "battery-low", "Battery low", pct + "% left. Plug in soon."]);
        } else if (pct <= 5 && warned > 5) {
            warned = 5;
            Quickshell.execDetached(["notify-send", "-a", "Tide", "-u", "critical", "-i", "battery-caution", "Battery almost empty", pct + "% left. Plug in now."]);
        }
    }
    onChargingChanged: if (charging) warned = 101

    IpcHandler {
        target: "power"
        function state(): string { return JSON.stringify({ battery: root.hasBattery, level: Math.round(root.level * 100), status: root.status, profiles: root.hasProfiles, profile: root.profile, backlight: root.hasBacklight, brightness: Math.round(root.brightness * 100) }); }
        function preview(on: bool): void { root.preview = on; }
    }
}
