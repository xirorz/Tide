import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../services"

// Settings → Login screen: the screen after a restart or log out (SDDM), with
// SilentSDDM by uiriansan. Pick an image or a video for it; bin/tide-login-screen puts it
// in place (one password prompt) without touching the theme's own files. The idle lock
// screen (hyprlock) stays as it is.
ColumnLayout {
    id: ls
    spacing: Theme.s(18)
    readonly property string tool: Quickshell.env("HOME") + "/.config/Tide/bin/tide-login-screen"
    property var st: ({})
    property string message: ""
    property bool busy: false
    property bool showAll: false
    // videos first (the point of this login screen), ten until "Show all"
    // the wallpaper that's on the login screen now: Tide copies it as tide/tide-<name> (the
    // helper's safe_name), so it's found by that name
    function safeName(path) {
        const n = path.split("/").pop(), dot = n.lastIndexOf(".");
        const stem = (dot > 0 ? n.slice(0, dot) : n).replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60) || "background";
        return "tide-" + stem + (dot > 0 ? n.slice(dot).toLowerCase() : "");
    }
    readonly property string appliedPath: { const b = st.background || ""; const f = Wallpapers.files.find(x => "tide/" + safeName(x.path) === b); return f ? f.path : ""; }
    // the applied one first, then videos, then images
    readonly property var walls: {
        const a = Wallpapers.files.filter(f => f.path === appliedPath);
        const rest = Wallpapers.files.filter(f => f.path !== appliedPath);
        return a.concat(rest.filter(f => f.video), rest.filter(f => !f.video));
    }
    Component.onCompleted: { statusProc.running = true; optsProc.running = true; Wallpapers.refresh(); }
    // the layout options: what the theme has now, and what you've changed but not applied
    property var opts: ({})
    property var pending: ({})
    function opt(k) { return pending[k] !== undefined ? pending[k] : (opts[k] || ""); }
    function change(k, v) { const p = Object.assign({}, pending); if (opts[k] === v) delete p[k]; else p[k] = v; pending = p; }
    function applyOptions() {
        if (busy || !changes) return;
        busy = true;
        // only the very first time needs your password: then Settings steps aside for it
        if (!st.ready) { message = "Asking for your password…"; Games.picking = true; } else message = "Applying…";
        setProc.command = [tool, "set-options"].concat(Object.keys(pending).map(k => k + "=" + pending[k]))
            .concat(pendingBg ? ["background=" + pendingBg] : []);
        setProc.running = true;
    }
    Process {
        id: optsProc
        command: [ls.tool, "options"]
        stdout: StdioCollector { onStreamFinished: { try { ls.opts = JSON.parse(text); } catch (e) {} } }
    }

    // a background you clicked: applied with the rest (Apply)
    property string pendingBg: ""
    function set(path) { pendingBg = path === st.path ? "" : path; message = ""; }
    readonly property int changes: Object.keys(pending).length + (pendingBg ? 1 : 0)
    function use() {
        if (busy) return;
        busy = true; message = "Asking for your password…";
        Games.picking = true;            // the password window needs the screen (Settings hides)
        setProc.command = [tool, "use"];
        setProc.running = true;
    }
    Process {
        id: statusProc
        command: [ls.tool, "status"]
        stdout: StdioCollector { onStreamFinished: { try { ls.st = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: setProc
        stdout: StdioCollector {
            onStreamFinished: {
                Games.picking = false;
                ls.busy = false;
                let d = {};
                try { d = JSON.parse(text); } catch (e) { d = { error: "Couldn't change it" }; }
                ls.message = d.error || "Done. Preview it, or you'll see it at your next log out or restart.";
                // applied: start from what's there now (on an error your changes stay to try again)
                if (!d.error) { ls.pending = {}; ls.pendingBg = ""; }
                statusProc.running = true;
                optsProc.running = true;
            }
        }
    }

    Heading { text: "Login screen"; sub: "What you see after a restart or when you log out. The lock screen when you're idle stays as it is." }

    // not there yet: install it, or make it the login screen
    SCard {
        visible: ls.st.installed === false || (!!ls.st.installed && !ls.st.active)
        title: "Theme"
        SRow {
            visible: ls.st.installed === false
            last: true
            label: "SilentSDDM isn't installed"
            sub: "The login screen theme Tide uses. It installs from the AUR with your AUR helper."
            SBtn {
                label: "Install…"; primary: true
                onClicked: Quickshell.execDetached(["kitty", "--class", "tide-updates", "--title", "Install SilentSDDM", "bash", "-c",
                    "h=$(bash '" + Quickshell.shellDir + "/scripts/aur-helper.sh'); if [ -z \"$h\" ]; then echo 'No AUR helper (yay or paru) found.'; else $h -S sddm-silent-theme; fi; read -r -s -n 1 -p 'Press any key to close this window.'"])
            }
        }
        SRow {
            visible: !!ls.st.installed && !ls.st.active
            last: true
            label: "Use SilentSDDM as the login screen"
            sub: "Right now it's " + (ls.st.current || "SDDM's default")
            SBtn { label: "Use it"; primary: true; onClicked: ls.use() }
        }
    }

    SCard {
        visible: !!ls.st.installed
        title: "Background"
        SRow {
            label: ls.pendingBg ? ls.pendingBg.split("/").pop() : (ls.st.background ? ls.st.background.split("/").pop().replace(/^tide-/, "") : "None")
            sub: ls.pendingBg ? "Picked: press Apply below to use it" : (ls.st.video ? "Video" : "Image") + (ls.st.tide ? " · picked in Tide" : " · the theme's own") + " · Preview shows it for 30 s"
            Row {
                spacing: Theme.s(8)
                SBtn { label: "Preview"; enabled: !!ls.st.greeter; onClicked: { IslandState.closeSettings(); Quickshell.execDetached([ls.tool, "preview"]); } }
                SBtn { label: "Choose file…"; primary: true; enabled: !ls.busy; onClicked: Games.pick(false, "An image or video for the login screen", p => ls.set(p)) }
            }
        }
        // your wallpapers: click one, then Apply
        Item {
            Layout.fillWidth: true
            implicitHeight: wallFlow.implicitHeight + Theme.s(28)
            Text {
                anchors.right: parent.right; anchors.rightMargin: Theme.s(16); y: Theme.s(4)
                visible: ls.walls.length > 10
                text: ls.showAll ? "Show fewer" : "Show all " + ls.walls.length
                color: Theme.accent; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                MouseArea { anchors.fill: parent; anchors.margins: -Theme.s(6); cursorShape: Qt.PointingHandCursor; onClicked: ls.showAll = !ls.showAll }
            }
            Text { x: Theme.s(16); y: Theme.s(4); text: "From your wallpapers"; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            Flow {
                id: wallFlow
                x: Theme.s(16); y: Theme.s(24)
                width: parent.width - Theme.s(32)
                spacing: Theme.s(8)
                Repeater {
                    model: ls.showAll ? ls.walls : ls.walls.slice(0, 10)
                    delegate: Rectangle {
                        required property var modelData
                        width: Theme.s(132); height: Theme.s(74); radius: Theme.s(10)
                        color: Theme.white(0.06)
                        clip: true
                        readonly property bool chosen: ls.pendingBg === modelData.path
                        readonly property bool applied: !ls.pendingBg && ls.appliedPath === modelData.path
                        border.width: chosen || applied ? 3 : hov.containsMouse ? 2 : 0
                        border.color: chosen || applied ? Theme.accent : Theme.white(0.5)
                        Image { anchors.fill: parent; anchors.margins: parent.border.width; source: modelData.thumb; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 264 }
                        // "On now" / "Picked" over the one in use or the one you clicked
                        Rectangle {
                            visible: parent.applied || parent.chosen
                            anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.s(6)
                            width: st2.implicitWidth + Theme.s(12); height: Theme.s(18); radius: Theme.s(9)
                            color: Theme.accent
                            Text { id: st2; anchors.centerIn: parent; text: parent.parent.applied ? "On now" : "Picked"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(10); font.weight: Font.DemiBold }
                        }
                        Rectangle {
                            visible: modelData.video
                            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.s(6)
                            width: vt.implicitWidth + Theme.s(10); height: Theme.s(18); radius: Theme.s(9)
                            color: Qt.rgba(0, 0, 0, 0.6)
                            Text { id: vt; anchors.centerIn: parent; text: "Video"; color: "white"; font.family: Theme.sans; font.pixelSize: Theme.s(10) }
                        }
                        MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !ls.busy; onClicked: ls.set(modelData.path) }
                    }
                }
            }
        }
    }

    // Tide's own fonts (Settings → Appearance and the clock widget's), copied for the login screen
    SCard {
        visible: !!ls.st.installed && ls.st.active !== false
        title: "Fonts"
        SRow {
            label: "Text"
            sub: "Name, password box, buttons and the date"
            SDropdown {
                mono: false
                options: [{ label: "Theme's own (Red Hat Display)", value: "RedHatDisplay" }].concat(Fonts.interfaceFonts.map(f => ({ label: f, value: f, family: f })))
                value: ls.opt("font")
                onPicked: v => ls.change("font", v)
            }
        }
        SRow {
            last: true
            label: "Clock"
            SDropdown {
                mono: false
                options: [{ label: "Theme's own (Red Hat Display)", value: "RedHatDisplay" }].concat(Fonts.clockFonts.map(f => ({ label: f.label, value: f.value, family: f.value })))
                value: ls.opt("clock-font")
                onPicked: v => ls.change("clock-font", v)
            }
        }
    }

    SCard {
        visible: !!ls.st.installed && ls.st.active !== false
        title: "Layout"
        SRow {
            label: "Password box"
            SSegment {
                options: [{ label: "Left", value: "left" }, { label: "Center", value: "center" }, { label: "Right", value: "right" }]
                value: ls.opt("LoginScreen.LoginArea/position")
                // the clock screen lines up with it: clock and its message on the same side
                onPicked: v => {
                    ls.change("LoginScreen.LoginArea/position", v);
                    ls.change("LockScreen.Clock/position", v === "center" ? "center" : "center-" + v);
                    ls.change("LockScreen.Message/position", "bottom-" + (v === "center" ? "center" : v));
                    ls.change("LockScreen.Clock/align", v);
                    ls.change("LockScreen.Message/align", v);
                }
            }
        }
        SRow {
            label: "Clock screen first"
            sub: "A clock over your background, on the same side as the password box; any key or click brings up the box"
            SToggle { on: ls.opt("LockScreen/display") !== "false"; onToggled: ls.change("LockScreen/display", on ? "false" : "true") }
        }
        SRow {
            visible: ls.opt("LockScreen/display") !== "false"
            label: "Clock"
            SSegment {
                options: [{ label: "24-hour", value: "hh:mm" }, { label: "12-hour", value: "h:mm AP" }]
                value: ls.opt("LockScreen.Clock/format")
                onPicked: v => ls.change("LockScreen.Clock/format", v)
            }
        }
        SRow {
            visible: ls.opt("LockScreen/display") !== "false"
            label: "Blur on the clock screen"
            SSegment {
                options: [{ label: "None", value: "0" }, { label: "Soft", value: "16" }, { label: "Strong", value: "32" }]
                value: ls.opt("LockScreen/blur")
                onPicked: v => ls.change("LockScreen/blur", v)
            }
        }
        SRow {
            label: "Blur behind the password box"
            SSegment {
                options: [{ label: "None", value: "0" }, { label: "Soft", value: "16" }, { label: "Strong", value: "32" }]
                value: ls.opt("LoginScreen/blur")
                onPicked: v => ls.change("LoginScreen/blur", v)
            }
        }
        SRow {
            label: "Darken the background"
            sub: "Makes the text easier to read over a bright video"
            SSegment {
                readonly property string cur: String(parseFloat(ls.opt("LoginScreen/brightness") || "0"))
                options: [{ label: "Off", value: "0" }, { label: "A little", value: "-0.2" }, { label: "More", value: "-0.4" }]
                value: cur
                onPicked: v => { ls.change("LoginScreen/brightness", v === "0" ? "0.0" : v); ls.change("LockScreen/brightness", v === "0" ? "0.0" : v); }
            }
        }
        SRow {
            last: true
            label: ls.changes ? "Changes to apply" : "Up to date"
            sub: ls.message || (ls.st.ready ? "Background and layout apply together" : "The first change asks for your password once; after that, no password")
            Row {
                spacing: Theme.s(8)
                SBtn { label: "Undo"; visible: ls.changes > 0; onClicked: { ls.pending = {}; ls.pendingBg = ""; } }
                SBtn { label: "Apply"; primary: true; enabled: ls.changes > 0 && !ls.busy; onClicked: ls.applyOptions() }
            }
        }
    }

    SCard {
        title: "Credit"
        SRow {
            last: true
            label: "SilentSDDM by uiriansan"
            sub: "The login screen theme · GPL-2.0 · github.com/uiriansan/SilentSDDM"
            SBtn { label: "Open"; onClicked: Quickshell.execDetached(["xdg-open", "https://github.com/uiriansan/SilentSDDM"]) }
        }
    }
}
