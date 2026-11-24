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
            sub: "Small is the design; Medium and Large make everything bigger"
            SSegment {
                options: [{ label: "Small", value: 1 }, { label: "Medium", value: 1.15 }, { label: "Large", value: 1.3 }]
                value: Theme.uiScale
                onPicked: v => ap.setScale(v)
            }
        }
        SRow {
            last: true
            label: "Apply the dark theme to all apps (GTK and Qt)"
            SToggle { on: ap.appsDark; onToggled: ap.setAppsDark(!on) }
        }
    }

    // where your wallpapers are (the picker, Super+W, shows this folder)
    SCard {
        title: "Wallpapers"
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
