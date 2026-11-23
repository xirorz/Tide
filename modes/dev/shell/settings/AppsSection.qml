import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../services"

// Settings → Apps and Hyprland. Default apps: terminal and file manager open through
// ~/.config/Tide/bin/tide-open (Super+Enter, Super+E), so they change without a
// Hyprland reload; the browser is the system default (xdg-settings); the audio app is
// what right-clicking the speaker opens. Idle and lock: hypridle timings
// (services/Idle.qml) and Stay awake.
ColumnLayout {
    id: ap
    spacing: Theme.s(18)

    // what's installed
    property var have: []
    Process {
        running: true
        command: ["sh", "-c", "for a in kitty alacritty foot wezterm ghostty konsole gnome-terminal nemo nautilus thunar dolphin pcmanfm pavucontrol pwvucontrol easyeffects helvum qpwgraph; do command -v $a >/dev/null && echo $a; done"]
        stdout: StdioCollector { onStreamFinished: ap.have = text.trim().split("\n").filter(x => x) }
    }
    function pick(list) { return list.filter(a => have.indexOf(a) >= 0).map(a => ({ label: a.charAt(0).toUpperCase() + a.slice(1), value: a })); }

    // browsers: desktop entries in the WebBrowser category
    readonly property var browsers: DesktopEntries.applications.values
        .filter(e => !e.noDisplay && e.categories.indexOf("WebBrowser") >= 0)
        .map(e => ({ label: e.name, value: e.id + ".desktop" }))
    property string browser: ""
    Process {
        id: browserGet
        running: true
        command: ["xdg-settings", "get", "default-web-browser"]
        stdout: StdioCollector { onStreamFinished: ap.browser = text.trim() }
    }
    function setBrowser(v) {
        browser = v;
        Quickshell.execDetached(["xdg-settings", "set", "default-web-browser", v]);
    }

    // the keep-awake ignore list's picker: apps asking now first, then a search
    property string ignoreQuery: ""
    readonly property var ignoreSuggestions: {
        const have = Idle.ignoreList.map(i => i.name.toLowerCase());
        const asking = Idle.active.filter(b => !b.rule).map(b => ({ name: Idle.nameOf(b), cls: b.kind === "window" ? b.cls : "", asking: true }))
            .filter((a, i, l) => l.findIndex(x => x.name === a.name) === i);
        // the systemd request (e.g. "Claude") and the window (com.anthropic.Claude) are one app
        for (const a of asking) { const w = Idle.active.find(b => b.kind === "window" && Idle.nameOf(b) === a.name); if (w) a.cls = w.cls; }
        const q = ignoreQuery.trim().toLowerCase();
        const found = q.length < 2 ? [] : DesktopEntries.applications.values.filter(e => !e.noDisplay && e.name.toLowerCase().indexOf(q) >= 0).slice(0, 5)
            .map(e => ({ name: e.name, cls: e.startupClass || e.id.replace(/\.desktop$/, ""), asking: false }));
        return asking.concat(found).filter(a => have.indexOf(a.name.toLowerCase()) < 0);
    }
    readonly property var minutes: [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60].map(m => ({ label: m === 0 ? "Never" : m < 60 ? m + " min" : "1 hour", value: m }))

    Heading { text: "Apps and Hyprland" }

    SCard {
        title: "Default apps"
        SRow {
            label: "Terminal"
            sub: "Super + Enter"
            SSegment {
                options: ap.pick(["kitty", "alacritty", "foot", "wezterm", "ghostty", "konsole", "gnome-terminal"])
                value: Theme.opt("terminal", "alacritty")
                onPicked: v => Theme.set("terminal", v)
            }
        }
        SRow {
            label: "Browser"
            sub: "Opens links from every app"
            SDropdown {
                mono: false
                options: ap.browsers.length ? ap.browsers : [{ label: ap.browser, value: ap.browser }]
                value: ap.browser
                onPicked: v => ap.setBrowser(v)
            }
        }
        SRow {
            label: "File manager"
            sub: "Super + E"
            SSegment {
                options: ap.pick(["nemo", "nautilus", "thunar", "dolphin", "pcmanfm"])
                value: Theme.opt("fileManager", "nemo")
                onPicked: v => Theme.set("fileManager", v)
            }
        }
        SRow {
            last: true
            label: "Audio settings"
            sub: "Right-click on the speaker"
            SSegment {
                options: ap.pick(["pavucontrol", "pwvucontrol", "easyeffects", "helvum", "qpwgraph"])
                value: Theme.audioApp
                onPicked: v => Theme.set("audioApp", v)
            }
        }
    }

    SCard {
        title: "Idle and lock (hypridle)"
        SRow {
            label: "Idle service"
            // "Idle: running · next: dim in 1:40", "Idle blocked by Claude", or not running
            sub: {
                if (!Idle.running) return "hypridle isn't running, so none of these happen right now (Tide starts it again within a minute)";
                if (Idle.awake) return "Idle: running · paused by Stay awake";
                const ign = Idle.uniq(Idle.ignoredNow);
                const ignoring = ign.length ? " (ignoring " + ign.join(", ") + ")" : "";
                if (Idle.blockers.length) return "Idle blocked by " + Idle.blockers.join(", ") + ignoring;
                const t = Idle.timings, away = Idle.idleSince ? Idle.now - Idle.idleSince : 0;
                const steps = [["dim", t.dim], ["lock", t.lock], ["turn screens off", t.dpms], ["suspend", t.suspend]].filter(s => s[1] > 0 && s[1] * 60 > away);
                if (!steps.length) return "Idle: running" + ignoring;
                const left = steps[0][1] * 60 - away;
                return "Idle: running · next: " + steps[0][0] + " in " + Math.floor(left / 60) + ":" + String(left % 60).padStart(2, "0") + ignoring;
            }
            Component.onCompleted: { Idle.watching = true; Idle.checkBlockers(); }
            Component.onDestruction: Idle.watching = false
            HoverButton {
                visible: !Idle.running
                implicitWidth: startT.implicitWidth + Theme.s(28); implicitHeight: Theme.s(32); radius: Theme.s(9)
                hoverFill: false
                color: hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
                onClicked: Idle.start()
                Text { id: startT; anchors.centerIn: parent; text: "Start"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold }
            }
        }
        SRow { label: "Dim the screen after"; SDropdown { mono: false; options: ap.minutes; value: Idle.timings.dim; onPicked: v => Idle.set("dim", v) } }
        SRow { label: "Lock after"; SDropdown { mono: false; options: ap.minutes; value: Idle.timings.lock; onPicked: v => Idle.set("lock", v) } }
        SRow { label: "Turn screens off after"; SDropdown { mono: false; options: ap.minutes; value: Idle.timings.dpms; onPicked: v => Idle.set("dpms", v) } }
        SRow { label: "Suspend after"; SDropdown { mono: false; options: ap.minutes; value: Idle.timings.suspend; onPicked: v => Idle.set("suspend", v) } }
        // keep-awake rules (services/Idle.qml)
        SRow {
            label: "Games and full-screen video always keep the screen on"
            sub: "Steam, Lutris, Heroic and gamescope games on screen, and video in full screen"
            SToggle { on: Idle.keepGames; onToggled: Theme.set("idleKeepGames", !on) }
        }
        SRow {
            label: "Ignore keep-awake from these apps"
            sub: Idle.ignoreList.length ? "These can't stop your screen from dimming and locking" : "None yet: apps that ask to keep your PC awake show up below"
            SField {
                implicitWidth: Theme.s(220)
                hint: "Add an app…"
                text: ap.ignoreQuery
                onEdited: v => ap.ignoreQuery = v
            }
        }
        // the list, each with ×
        Repeater {
            model: Idle.ignoreList
            delegate: Item {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: Theme.s(40)
                Text { x: Theme.s(28); anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
                HoverButton {
                    anchors.right: parent.right; anchors.rightMargin: Theme.s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.s(28); height: Theme.s(28); radius: Theme.s(8)
                    onClicked: Idle.setIgnore(Idle.ignoreList.filter((x, i) => i !== parent.index))
                    Text { anchors.centerIn: parent; text: "×"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(15) }
                }
            }
        }
        // suggestions: who's asking right now, then search results
        Repeater {
            model: ap.ignoreSuggestions
            delegate: HoverButton {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Theme.s(40); radius: 0
                hoverFill: true
                onClicked: { Idle.setIgnore(Idle.ignoreList.concat([{ name: modelData.name, cls: modelData.cls }])); ap.ignoreQuery = ""; }
                Text {
                    x: Theme.s(28); anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.asking ? parent.modelData.name + " is keeping your PC awake" : parent.modelData.name
                    color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(13)
                }
                Text { anchors.right: parent.right; anchors.rightMargin: Theme.s(20); anchors.verticalCenter: parent.verticalCenter; text: "Ignore"; color: Theme.accent; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold }
            }
        }
        SRow {
            last: true
            label: "Stay awake"
            sub: "Same as the toggle in the control center; pauses all of the above"
            SToggle { on: Idle.awake; onToggled: Idle.awake = !Idle.awake }
        }
    }
}
