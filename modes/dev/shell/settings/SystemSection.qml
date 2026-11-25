import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../services"

// Settings → System: drives to watch (fill alerts, services/Drives.qml), free up space
// (scripts/cleanup.py), the update center and the clipboard switches.
ColumnLayout {
    id: sys
    spacing: Theme.s(18)

    // ---- free up space: scripts/cleanup.py scans; "here" steps run after a second
    // click (Sure?), "terminal" ones open in your terminal, where pacman/flatpak ask ----
    readonly property string cleanTool: Quickshell.shellDir + "/scripts/cleanup.py"
    property var scan: null
    property bool scanning: false
    property string armed: ""              // the button waiting for its second click
    Timer { id: disarm; interval: 4000; onTriggered: sys.armed = "" }
    function startScan() { if (scanProc.running) return; scanning = true; scanProc.running = true; }
    Process {
        id: scanProc
        command: ["python3", "-I", sys.cleanTool, "scan"]
        stdout: StdioCollector { onStreamFinished: { try { sys.scan = JSON.parse(text); } catch (e) {} sys.scanning = false; } }
    }
    function gb(b) { return b >= 1073741824 ? (b / 1073741824).toFixed(1) + " GB" : Math.max(1, Math.round(b / 1048576)) + " MB"; }
    readonly property var items: scan ? scan.items.filter(i => i.bytes > 0 || i.count > 0) : []
    readonly property real total: items.reduce((a, i) => a + i.bytes, 0) + (scan ? scan.caches.reduce((a, c) => a + c.bytes, 0) : 0)
    function clean(id, how, cmd) {
        if (!id) return;
        if (how === "terminal") {
            IslandState.closeSettings();
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/Tide/bin/tide-term", "Free up space", "bash", "-c",
                cmd + "; echo; read -r -s -n 1 -p 'Done. Press any key to close this window.'"]);
            rescanSoon.restart();
            return;
        }
        if (armed !== id) { armed = id; disarm.restart(); return; }
        armed = "";
        cleaner.command = ["python3", "-I", cleanTool, "clean", id];
        cleaner.running = true;
    }
    Process { id: cleaner; onExited: sys.startScan() }
    Timer { id: rescanSoon; interval: 15000; onTriggered: sys.startScan() }

    Heading { text: "System" }

    SCard {
        title: "Drives to watch"
        Repeater {
            model: Drives.mounted
            delegate: Item {
                id: dr
                required property var modelData
                required property int index
                readonly property int limit: Drives.at(modelData.mount)
                readonly property bool over: limit > 0 && modelData.pct >= limit
                Layout.fillWidth: true
                implicitHeight: Theme.s(62)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.s(16); anchors.rightMargin: Theme.s(16)
                    spacing: Theme.s(16)
                    Column {
                        Layout.fillWidth: true
                        spacing: Theme.s(2)
                        Text { text: dr.modelData.label; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
                        Text { text: dr.modelData.mount + " · " + dr.modelData.device; color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11) }
                    }
                    Column {
                        Layout.preferredWidth: Theme.s(220)
                        spacing: Theme.s(5)
                        Rectangle {
                            width: parent.width; height: Theme.s(6); radius: Theme.s(3)
                            color: Theme.white(0.12)
                            Rectangle { width: parent.width * dr.modelData.pct / 100; height: Theme.s(6); radius: Theme.s(3); color: dr.over ? Theme.critical : dr.modelData.pct >= 80 ? Theme.warning : Theme.accent }
                        }
                        Text { text: Drives.gb(dr.modelData.used) + " of " + Drives.gb(dr.modelData.size) + " · " + dr.modelData.pct + "%"; color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11) }
                    }
                    Row {
                        spacing: Theme.s(8)
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Notify at"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                        SSegment {
                            options: [{ label: "Off", value: 0 }, { label: "80%", value: 80 }, { label: "90%", value: 90 }, { label: "95%", value: 95 }]
                            value: dr.limit
                            onPicked: v => Drives.setAt(dr.modelData.mount, v)
                        }
                    }
                }
                Rectangle { visible: dr.index < Drives.mounted.length - 1; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.white(0.05) }
            }
        }
    }

    SCard {
        title: "Free up space"
        SRow {
            last: !sys.scan
            label: sys.scan ? "About " + sys.gb(sys.total) + " can be freed" : "See what can be freed"
            sub: sys.scanning ? "Looking… (a few seconds)" : "Old packages, packages nothing needs, logs, Trash and app caches. Tide only removes things that are safe to remove; system ones ask first in your terminal."
            SBtn { label: sys.scanning ? "Scanning…" : sys.scan ? "Scan again" : "Scan"; primary: !sys.scan; onClicked: sys.startScan() }
        }
        Repeater {
            model: sys.items
            delegate: SRow {
                id: itemRow
                required property var modelData
                label: modelData.label + " · " + (modelData.bytes > 0 ? sys.gb(modelData.bytes) : modelData.count + (modelData.count === 1 ? " item" : " items"))
                sub: modelData.sub
                CleanBtn { armed: sys.armed; enabled: !cleaner.running; onClean: (w, h, c) => sys.clean(w, h, c); what: itemRow.modelData.id; how: itemRow.modelData.how; cmd: itemRow.modelData.cmd || "" }
            }
        }
        Text {
            visible: !!sys.scan && sys.scan.caches.length > 0
            Layout.leftMargin: Theme.s(16); Layout.topMargin: Theme.s(10)
            text: "App caches (~/.cache): apps rebuild them when needed; close an app before clearing its cache"
            color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11.5)
        }
        Repeater {
            model: sys.scan ? sys.scan.caches : []
            delegate: SRow {
                id: cacheRow
                required property var modelData
                label: modelData.name + " · " + sys.gb(modelData.bytes)
                CleanBtn { armed: sys.armed; enabled: !cleaner.running; onClean: (w, h, c) => sys.clean(w, h, c); what: "cache:" + cacheRow.modelData.name }
            }
        }
        Text {
            visible: !!sys.scan && sys.scan.big.length > 0
            Layout.leftMargin: Theme.s(16); Layout.topMargin: Theme.s(10)
            text: "Biggest folders in your home: to look through yourself (Tide doesn't delete these)"
            color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11.5)
        }
        Repeater {
            model: sys.scan ? sys.scan.big : []
            delegate: SRow {
                id: bigRow
                required property var modelData
                required property int index
                last: index === sys.scan.big.length - 1
                label: modelData.path.replace(Quickshell.env("HOME"), "~") + " · " + sys.gb(modelData.bytes)
                SBtn { label: "Open"; onClicked: { IslandState.closeSettings(); Quickshell.execDetached([Quickshell.env("HOME") + "/.config/Tide/bin/tide-open", "files", bigRow.modelData.path]); } }
            }
        }
    }

    SCard {
        title: "Updates"
        SRow {
            label: "AUR helper"
            sub: Updates.helperInfo.found.length ? "Found here: " + Updates.helperInfo.found.join(", ") : "No yay or paru found"
            SDropdown {
                options: [{ label: "Automatic (" + (Updates.helperInfo.auto || "none") + ")", value: "auto" }]
                    .concat(Updates.helperInfo.found.map(h => ({ label: h, value: h })))
                value: Updates.aurHelper
                onPicked: v => Theme.set("updatesAurHelper", v)
            }
        }
        SRow { label: "Include AUR packages"; SToggle { on: Updates.includeAur; onToggled: Theme.set("updatesAur", !on) } }
        SRow { label: "Review AUR build scripts before updating"; sub: "Asks for each AUR package and shows its build script if you want; off goes straight to the AUR helper"; SToggle { on: Updates.reviewAur; onToggled: Theme.set("updatesReviewAur", !on) } }
        SRow { label: "Include Flatpak apps"; SToggle { on: Updates.includeFlatpak; onToggled: Theme.set("updatesFlatpak", !on) } }
        SRow { label: "Take a snapshot before updating"; sub: "snap-pac takes it; off skips the snapshot for that update"; SToggle { on: Updates.snapshot; onToggled: Theme.set("updatesSnapshot", !on) } }
        SRow { label: "CachyOS news"; sub: "Warn about CachyOS blog posts next to Arch news"; SToggle { on: Updates.cachyNews; onToggled: Theme.set("updatesCachyNews", !on) } }
        SRow {
            last: true
            label: "Check for updates every"
            SSegment {
                options: [{ label: "15 min", value: 15 }, { label: "30 min", value: 30 }, { label: "1 hour", value: 60 }, { label: "3 hours", value: 180 }]
                value: Theme.updatesEveryMinutes
                onPicked: v => Theme.set("updatesEveryMinutes", v)
            }
        }
    }

    SCard {
        title: "Clipboard"
        SRow { label: "Clean up old clips"; sub: "Runs after every copy"; SToggle { on: Theme.opt("clipboardCleanup", false); onToggled: Theme.set("clipboardCleanup", !on) } }
        SRow {
            label: "Keep the newest"
            SSegment {
                options: [{ label: "25", value: 25 }, { label: "50", value: 50 }, { label: "100", value: 100 }, { label: "200", value: 200 }]
                value: Theme.opt("clipboardMax", 50)
                onPicked: v => Theme.set("clipboardMax", v)
            }
        }
        SRow {
            last: true
            label: "Forget clips older than"
            SSegment {
                options: [{ label: "1 day", value: 1 }, { label: "7 days", value: 7 }, { label: "30 days", value: 30 }]
                value: Theme.opt("clipboardDays", 7)
                onPicked: v => Theme.set("clipboardDays", v)
            }
        }
    }
}
