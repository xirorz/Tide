import QtQuick
import QtQuick.Layouts
import ".."
import "../services"

// Settings → System: drives to watch (fill alerts, services/Drives.qml), the update
// center and the clipboard switches.
ColumnLayout {
    spacing: Theme.s(18)
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
