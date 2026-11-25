import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../services"

// Settings → Appearance. Everything applies at once and is saved in theme.json;
// window corners and blur are also pushed to Hyprland live (hypr.lua reads them back
// on the next reload).
ColumnLayout {
    id: ap
    spacing: Theme.s(16)
    // everything in the shell follows at once; Hyprland re-reads its config so the Eve
    // window's place under the (now taller) bar follows too
    function setScale(v) {
        Theme.set("uiScale", v);
        reloadLater.restart();
    }
    Timer { id: reloadLater; interval: 400; onTriggered: Quickshell.execDetached(["sh", "-c", "Hyprland --verify-config -c ~/.config/hypr/hyprland.lua | grep -q 'config ok' && hyprctl reload"]) }
    function hypr(key, value) {
        Quickshell.execDetached(["hyprctl", "eval", "hl.config({[\"" + key + "\"] = " + value + "})"]);
    }

    // GTK/Qt dark: the desktop portal's color-scheme
    property bool appsDark: true
    Process {
        id: schemeGet
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        stdout: StdioCollector { onStreamFinished: ap.appsDark = text.indexOf("prefer-dark") >= 0 }
    }
    function setAppsDark(on) {
        appsDark = on;
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", on ? "prefer-dark" : "default"]);
    }

    Heading { text: "Appearance" }

    SCard {
        SRow {
            label: "Surface"
            sub: "Tinted is dark and solid, in your wallpaper's own colours"
            SSegment {
                options: [{ label: "Dark", value: "dark" }, { label: "Glass", value: "glass" }, { label: "Tinted", value: "tinted" }]
                value: Theme.surface === "glass" || Theme.surface === "tinted" ? Theme.surface : "dark"
                onPicked: v => Theme.setSurface(v)
            }
        }
        SRow {
            label: "Accent from wallpaper"
            sub: "pywal picks the accent every time the wallpaper changes"
            Row {
                spacing: Theme.s(10)
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Theme.s(22); height: Theme.s(22); radius: Theme.s(11); color: Theme.accent }
                SToggle { anchors.verticalCenter: parent.verticalCenter; on: Theme.opt("accentFromWallpaper", true); onToggled: Theme.set("accentFromWallpaper", !on) }
            }
        }
        SRow {
            label: "Bar style"
            sub: "Pills, or bare text and icons along the top edge"
            SSegment {
                options: [{ label: "Pills", value: "pills" }, { label: "Text and icons", value: "text" }]
                value: Theme.barStyle
                onPicked: v => Theme.set("barStyle", v)
            }
        }
        SRow {
            label: "Corner roundness"
            sub: "The bar, panels, the island and window corners"
            Row {
                spacing: Theme.s(12)
                Text { anchors.verticalCenter: parent.verticalCenter; width: Theme.s(28); horizontalAlignment: Text.AlignRight; text: Math.round(round.shown); color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                SSlider {
                    id: round
                    from: 0; to: 24; step: 1
                    value: Theme.roundness
                    onMoved: v => Theme.set("roundness", v)
                    onReleased: v => ap.hypr("decoration.rounding", Math.round(14 * v / 18))
                }
            }
        }
        SRow {
            label: "Glass blur"
            sub: "How frosted glass surfaces and windows look"
            Row {
                spacing: Theme.s(12)
                Text { anchors.verticalCenter: parent.verticalCenter; width: Theme.s(28); horizontalAlignment: Text.AlignRight; text: Math.round(blur.shown); color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                SSlider {
                    id: blur
                    from: 0; to: 60; step: 2
                    value: Theme.opt("glassBlur", 36)
                    onReleased: v => { Theme.set("glassBlur", v); ap.hypr("decoration.blur.size", Math.round(v / 4)); }
                }
            }
        }
        SRow {
            label: "Animation speed"
            sub: "1× is the motion sheet; 0 turns animations off"
            Row {
                spacing: Theme.s(12)
                Text { anchors.verticalCenter: parent.verticalCenter; width: Theme.s(28); horizontalAlignment: Text.AlignRight; text: speed.shown === 0 ? "Off" : speed.shown.toFixed(1) + "×"; color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                SSlider {
                    id: speed
                    from: 0; to: 2; step: 0.1
                    value: Theme.opt("motionSpeed", 1)
                    onReleased: v => Theme.set("motionSpeed", Math.round(v * 10) / 10)
                }
            }
        }
        SRow {
            last: true
            label: "Reduce motion"
            sub: "Morphs and drops become short fades, loops hold still"
            SToggle { on: Theme.opt("reduceMotion", false); onToggled: Theme.set("reduceMotion", !on) }
        }
    }

    SCard {
        SRow {
            label: "Interface font"
            sub: "Used everywhere in Tide (numbers stay in " + Theme.mono + ")"
            SDropdown {
                mono: false
                options: Fonts.interfaceFonts.map(f => ({ label: f, value: f, family: f }))
                value: Theme.sans
                onPicked: v => Theme.set("font", v)
            }
        }
        SRow {
            label: "Interface size"
            sub: Theme.uiScaleSetting === "auto" ? "Auto fits it to your screen (" + Math.round(Theme.autoScale * 100) + "% here)" : "Auto fits it to your screen"
            SSegment {
                options: [{ label: "Auto", value: "auto" }, { label: "80%", value: 0.8 }, { label: "90%", value: 0.9 }, { label: "100%", value: 1 }, { label: "115%", value: 1.15 }, { label: "130%", value: 1.3 }]
                value: Theme.uiScaleSetting
                onPicked: v => ap.setScale(v)
            }
        }
        SRow {
            last: true
            label: "Apply the dark theme to all apps (GTK and Qt)"
            SToggle { on: ap.appsDark; onToggled: ap.setAppsDark(!on) }
        }
    }

    // what a terminal shows when it opens (bin/tide-greet); picking one also adds
    // tide-greet's one startup line to your shell if it isn't there yet
    readonly property string greetTool: Quickshell.env("HOME") + "/.config/Tide/bin/tide-greet"
    property bool hasPokemon: false
    Process { id: pokeCheck; running: true; command: ["sh", "-c", "command -v pokemon-colorscripts"]; onExited: code => ap.hasPokemon = code === 0 }
    function setGreeting(v) {
        Theme.set("terminalGreeting", v);
        Quickshell.execDetached([greetTool, "install"]);
    }
    SCard {
        title: "Terminal"
        SRow {
            label: "Greeting"
            sub: "What a terminal shows when it opens. Tide's wave takes your wallpaper's colours."
            SSegment {
                options: [{ label: "Tide", value: "tide" }, { label: "Pokémon", value: "pokemon" }, { label: "Distro", value: "distro" }, { label: "Minimal", value: "minimal" }, { label: "Off", value: "off" }]
                value: Theme.opt("terminalGreeting", "tide")
                onPicked: v => ap.setGreeting(v)
            }
        }
        SRow {
            visible: Theme.opt("terminalGreeting", "tide") === "pokemon" && !ap.hasPokemon
            label: "pokemon-colorscripts isn't installed"
            sub: "Until it is, terminals show Tide's wave. It installs with your AUR helper."
            SBtn {
                label: "Install…"; primary: true
                onClicked: IslandState.closeSettings() || Quickshell.execDetached([Quickshell.env("HOME") + "/.config/Tide/bin/tide-term", "Install Pokémon greeting", "bash", "-c",
                    "h=$(bash '" + Quickshell.shellDir + "/scripts/aur-helper.sh'); if [ -z \"$h\" ]; then echo 'No AUR helper (yay or paru) found.'; else $h -S --needed pokemon-colorscripts-git; fi; read -r -s -n 1 -p 'Press any key to close this window.'"])
            }
        }
        SRow {
            last: true
            label: "Preview"
            sub: "Opens a terminal with the greeting"
            SBtn {
                label: "Show"
                onClicked: IslandState.closeSettings() || Quickshell.execDetached([Quickshell.env("HOME") + "/.config/Tide/bin/tide-term", "Terminal greeting", "bash", "-c",
                    "'" + ap.greetTool + "'; read -r -s -n 1 -p 'Press any key to close this window.'"])
            }
        }
    }

    // where your wallpapers are (the picker, Super+W, shows this folder)
    SCard {
        title: "Wallpapers"
        Component.onCompleted: Wallpapers.refresh()
        SRow {
            last: true
            label: "Wallpaper folder"
            sub: Wallpapers.dir.replace(Quickshell.env("HOME"), "~") + " · " + Wallpapers.files.length + " wallpapers"
            SBtn {
                label: "Choose…"
                onClicked: Games.pick(true, "Your wallpaper folder", p => { Theme.set("wallpaperDir", p); Qt.callLater(Wallpapers.refresh); })
            }
        }
    }
}
