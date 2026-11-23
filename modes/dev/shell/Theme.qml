pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Design tokens from the Dev mode canvas. Values in theme.json override the defaults,
// and the accent follows the wallpaper through pywal (~/.cache/wal/colors.json).
Singleton {
    id: root

    property var cfg: ({})
    property var wal: ({})
    property var roles: ({})

    function opt(key, fallback) {
        return root.cfg[key] !== undefined ? root.cfg[key] : fallback;
    }
    function walColor(name, fallback) {
        const c = root.wal.colors;
        if (c && c[name]) return c[name];
        return root.roles[name] ? root.roles[name] : fallback;
    }

    // surface: "glass", "dark" or "tinted" (never light); the island follows it. Tinted is
    // dark and solid, in the wallpaper's own dark surface colours (matugen, colors.css)
    readonly property string surface: opt("surface", "glass")
    readonly property bool tinted: surface === "tinted"
    function tone(role, fallback) { return tinted && roles[role] ? roles[role] : fallback; }
    // solid fills (dark and tinted); they fade when the wallpaper changes
    property color barFill: tone("surface-low", "#0D0D0F")
    property color panelFill: tone("surface", "#0D0D0F")
    property color islandFill: tone("surface-lowest", "#000000")
    property color tileFill: tone("surface-container", "#18181B")
    Behavior on barFill { ColorAnimation { duration: 600 } }
    Behavior on panelFill { ColorAnimation { duration: 600 } }
    Behavior on islandFill { ColorAnimation { duration: 600 } }
    Behavior on tileFill { ColorAnimation { duration: 600 } }
    // drop shadows under surfaces: off (flat) by default; the island can differ
    readonly property bool shadows: opt("shadows", false)
    readonly property bool islandShadow: opt("islandShadow", shadows)
    // the one monitor the shell runs on (Hyprland name)
    readonly property string monitor: opt("monitor", "")

    // type
    // Settings → Appearance → Interface size: Small (1, the design) / Medium / Large.
    // Every size in the shell goes through s() (pointSize through sf()); at Small they
    // return the value untouched, so today's look stays pixel for pixel.
    readonly property real uiScale: opt("uiScale", 1)
    function s(px) { return uiScale === 1 ? px : Math.round(px * uiScale); }
    function sf(pt) { return pt * uiScale; }
    readonly property string sans: opt("font", "Inter")
    readonly property string mono: opt("monoFont", "JetBrains Mono")

    // text
    readonly property color text: "#F5F5F7"
    readonly property color text2: "#C7C7CC"
    readonly property color muted: "#9A9AA0"
    readonly property color dim: "#7C7C82"
    readonly property color soft: "#E5E5EA"
    readonly property color ink: "#0A0A0B"
    readonly property color red: "#FF453A"

    // accent from the wallpaper
    // "accentFromWallpaper": false keeps the fixed accentFallback (the picker's
    // "Accent across the shell" switch)
    readonly property color accentTarget: opt("accentFromWallpaper", true)
        ? walColor(opt("walAccent", "color4"), opt("accentFallback", "#F2A23C"))
        : opt("accentFallback", "#F2A23C")
    // a new palette crossfades every accent at once (500ms, linear)
    property color accent: accentTarget
    Behavior on accent { ColorAnimation { duration: root.reduceMotion ? 0 : root.durAccent; easing.type: Easing.Linear } }
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.14)
    readonly property color accentLine: Qt.rgba(accent.r, accent.g, accent.b, 0.4)
    readonly property var eq: {
        const names = opt("walEq", ["color2", "color4", "color1", "color7"]);
        const fb = opt("eqFallback", ["#3C8CE0", "#F2A23C", "#F25C5C", "#E6ECF5"]);
        return [0, 1, 2, 3].map(i => walColor(names[i], fb[i]));
    }

    // network arrows: one wallpaper color each ("netDown" / "netUp" in theme.json)
    readonly property color netDown: walColor(opt("netDown", "cyan"), "#3C8CE0")
    readonly property color netUp: walColor(opt("netUp", "magenta"), "#F2A23C")

    // ---- motion and typography sheet ("Tide motion and typography") ----
    // surfaces and status colors
    readonly property color islandBg: islandFill
    readonly property color panelBg: panelFill
    readonly property color critical: "#FF453A"
    readonly property color warning: "#FFB340"
    // three curves; everything that moves uses one of them
    readonly property var spring: [0.2, 0.9, 0.25, 1.15, 1, 1]     // island morphs, anything that grows
    readonly property var standard: [0.2, 0.8, 0.2, 1, 1, 1]       // panels, reveals, hovers
    // the island opening: the spring with less overshoot (the sheet's felt too strong there)
    readonly property var islandSpring: [0.2, 0.9, 0.3, 1.05, 1, 1]
    // timings (ms), divided by Settings → Appearance → Animation speed (1 = the sheet)
    readonly property real motionSpeed: Math.max(0.25, opt("motionSpeed", 1))
    readonly property int durMorph: Math.round(420 / motionSpeed)        // island: width, height, radius together
    readonly property int durReveal: Math.round(300 / motionSpeed)       // content fades in + rises 6px ...
    readonly property int delayReveal: Math.round(120 / motionSpeed)     // ... after the shape has started to settle
    readonly property int durHide: Math.round(150 / motionSpeed)         // content fades out before the shape shrinks
    readonly property int durDrop: Math.round(260 / motionSpeed)         // panels: fade + 8px drop + 98% -> 100%
    readonly property int durHover: Math.round(180 / motionSpeed)        // hovers and selection
    readonly property int durWallpaper: Math.round(600 / motionSpeed)    // wallpaper change
    readonly property int durAccent: Math.round(500 / motionSpeed)       // accent crossfade
    // Reduced motion (Appearance): morphs and drops become 150ms fades, no hover
    // lifts, loops hold still; the recording dot keeps pulsing (it's a warning)
    // (an animation speed of 0 means the same)
    readonly property bool reduceMotion: opt("reduceMotion", false) || opt("motionSpeed", 1) === 0
    // corner roundness (Appearance, 0–24; 18 = the design): scales the bar, panels and
    // the island; Hyprland's window corners follow (14 at 18)
    readonly property real roundness: opt("roundness", 18)
    readonly property real radiusScale: roundness / 18
    // Settings → AI: off hides every AI piece (bar button, launcher row, Eve in the
    // island and its shortcut, the Eve panel)
    readonly property bool aiEnabled: opt("aiEnabled", true)
    // Appearance → Bar style: "pills" (the design) or "text" (bare text and icons)
    readonly property string barStyle: opt("barStyle", "pills")
    // type scale: [size px, weight, letter spacing px]
    readonly property var type: ({
        h1: [s(22), Font.Bold, sf(-0.22)],
        h2: [s(16), Font.Bold, 0],
        title: [s(15), Font.DemiBold, 0],
        body: [s(13), Font.Normal, 0],
        bodyStrong: [s(13), Font.DemiBold, 0],
        small: [s(12), Font.Normal, 0],
        caption: [s(11.5), Font.Normal, 0],
        mono: [s(12), Font.Normal, 0],
        monoStat: [s(30), Font.Medium, sf(-0.6)]
    })
    // large type tracks tighter: -0.02em from 22px up
    function tracking(px) { return px >= 22 ? -0.02 * px : 0; }

    function white(a) { return Qt.rgba(1, 1, 1, a); }
    function fg(a) { return Qt.rgba(245 / 255, 245 / 255, 247 / 255, a); }

    readonly property int workspaceCount: opt("workspaceCount", 5)
    readonly property string audioApp: opt("audioApp", "pavucontrol")
    readonly property string aiToggleUrl: opt("aiToggleUrl", "http://127.0.0.1:5200/toggle")
    readonly property string aiWindowClass: opt("aiWindowClass", "ai-copilot-panel")
    readonly property string recordStopCommand: opt("recordStopCommand", "pkill -INT -x wf-recorder")
    readonly property int updatesEveryMinutes: opt("updatesEveryMinutes", 30)
    // control center output buttons: part of each PipeWire sink's name
    readonly property string speakersSink: opt("speakersSink", "Scarlett")
    readonly property string headphonesSink: opt("headphonesSink", "CORSAIR VOID")
    readonly property color tile: surface === "glass" ? white(0.08) : tileFill   // the sheet's tile

    // the control center's Dark/Glass/Tinted switch writes "surface" back to theme.json
    function setSurface(v) { set("surface", v); }
    // write one setting back to theme.json (and apply it now; the file watcher
    // doesn't report our own write)
    function set(key, value) {
        const c = Object.assign({}, root.cfg);
        c[key] = value;
        root.cfg = c;
        cfgFile.setText(JSON.stringify(c, null, 2) + "\n");
    }

    // CSS "ease" and the island's springy curve
    readonly property var easeCss: standard
    readonly property var easeInOutCss: [0.42, 0, 0.58, 1, 1, 1]
    readonly property var springCss: spring

    FileView {
        id: cfgFile
        path: Quickshell.shellDir + "/../theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.cfg = JSON.parse(text()); } catch (e) { console.warn("theme.json:", e); }
        }
    }
    FileView {
        path: Quickshell.env("HOME") + "/.cache/wal/colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.wal = JSON.parse(text()); } catch (e) { root.wal = {}; }
        }
    }
    // matugen roles (primary, secondary, tertiary, ...) from the wallpaper, in Tide's own
    // file (~/.config/Tide/colors, written by scripts/wallpaper-apply.sh)
    FileView {
        path: Quickshell.env("HOME") + "/.config/Tide/colors/colors.css"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const out = {};
            const re = /--([\w-]+):\s*(#[0-9a-fA-F]{6})/g;
            let m;
            while ((m = re.exec(text())) !== null) out[m[1]] = m[2];
            root.roles = out;
        }
    }
}
