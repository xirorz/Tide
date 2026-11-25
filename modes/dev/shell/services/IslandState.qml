pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Which shape the island is in, and on which monitor.
Singleton {
    id: root
    property string mode: "idle"
    property string screenName: ""

    // states that are built so far; the rest of the design's states come next
    readonly property var built: ["idle", "launcher", "notification", "calculator", "clipboard", "capture", "power", "volume", "brightness", "eve", "wallpapers", "resources", "themes", "confirm", "cleanup"]

    // the control center is open (set by the bar); the island and it never show together
    property bool ccOpen: false
    // asks the bar to open the control center (the banner's View all)
    signal controlCenterRequested()
    // asks the bar to open or close it (the tide:controlcenter shortcut)
    signal controlCenterToggleRequested()
    signal controlCenterCloseRequested()

    // qs -p <shell dir> ipc call controlcenter toggle | open | close
    // (here, not in the bar, because the bar's window is rebuilt on a Dark/Glass switch)
    IpcHandler {
        target: "controlcenter"
        function toggle(): void { root.controlCenterToggleRequested(); }
        function open(): void { root.controlCenterRequested(); }
        function close(): void { root.controlCenterCloseRequested(); }
    }

    // ---- notification banner ----
    // what the banner shows: newest last, as plain copies (the notification itself
    // may be gone by the time the banner closes). `ref` is the live object for its action.
    property var banner: []
    property bool bannerHovered: false
    // a notification with buttons (other than its default click), like a scheduled
    // mode's "Start now / Skip today": the banner is taller and stays up longer
    readonly property bool bannerActions: {
        const c = banner.length ? banner[banner.length - 1] : null;
        return !!(c && c.ref && c.ref.actions && c.ref.actions.some(a => a.identifier !== "default"));
    }
    function showBanner(n) {
        // never on top of an open tool or the control center; it waits in the list
        if (ccOpen || (mode !== "idle" && mode !== "notification")) return;
        const item = { appName: n.appName, summary: n.summary, body: n.body,
                       appIcon: n.appIcon, image: n.image, desktopEntry: n.desktopEntry, ref: n };
        banner = (mode === "notification" ? banner : []).concat([item]);
        if (mode !== "notification") open("notification", "");
        bannerTimer.restart();
    }
    Timer {
        id: bannerTimer
        interval: root.bannerActions ? 20000 : 5000
        running: root.mode === "notification" && !root.bannerHovered
        onTriggered: if (root.mode === "notification") root.close()
    }
    Connections {
        target: Notifications
        function onReceived(n) { root.showBanner(n); }
    }

    // ---- volume pop-up ----
    // shown only by the volume/mute keys (the Tide Hyprland config runs the key's
    // wpctl command, then `qs ipc call island volume`); never on its own, and not
    // while a tool or the control center is open
    property bool volumeHovered: false
    function showVolume() {
        if (ccOpen || (mode !== "idle" && mode !== "volume" && mode !== "brightness")) return;
        if (mode !== "volume") open("volume", "");
        volumeTimer.restart();
    }
    Timer {
        id: volumeTimer
        interval: 3500
        running: root.mode === "volume" && !root.volumeHovered
        onTriggered: if (root.mode === "volume") root.close()
    }
    // the brightness keys: the same pop-up idea, for the screen's brightness
    function showBrightness() {
        if (ccOpen || (mode !== "idle" && mode !== "volume" && mode !== "brightness")) return;
        if (!Power.hasBacklight && !Power.preview) return;      // no laptop screen to dim
        Power.readBrightness();
        if (mode !== "brightness") open("brightness", "");
        brightnessTimer.restart();
    }
    Timer {
        id: brightnessTimer
        interval: 3500
        running: root.mode === "brightness" && !root.volumeHovered
        onTriggered: if (root.mode === "brightness") root.close()
    }

    // ---- calculator ----
    property string calcExpr: ""
    property string calcHist: ""
    function openCalculator(expr) {
        calcExpr = expr.replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-");
        calcHist = "";
        open("calculator", "");
    }

    // ---- priority ----
    // lowest:  passive (notification banner, volume pop-up): only on an empty island
    // middle:  Eve: keeps running underneath; whatever covers her, closing it brings
    //          her back as she is now
    // highest: tools you open (launcher, calculator, clipboard, capture, power,
    //          wallpapers): always open, over passive things and over Eve
    readonly property var passiveModes: ["notification", "volume", "brightness"]
    function isTool(m) { return m !== "idle" && m !== "eve" && passiveModes.indexOf(m) < 0; }
    // what the island rests on when nothing is open on top
    readonly property string restMode: Eve.active ? "eve" : "idle"

    // the island's tools a limited mode can block (Session.qml says why instead)
    readonly property var gated: ({ calculator: "calculator", clipboard: "clipboard", capture: "capture", wallpapers: "wallpapers", eve: "eve" })
    function open(m, screen) {
        if (built.indexOf(m) < 0) { close(); return; }
        if (gated[m] && !Session.useTool(gated[m])) return;
        screenName = screen || (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "");
        mode = m;
    }
    function close() { mode = restMode; }

    // Settings: a big panel over everything (not an island state)
    property bool settingsOpen: false
    property string settingsSection: "themes"
    function openSettings(section) {
        if (section) settingsSection = section;
        if (isTool(mode)) close();
        controlCenterCloseRequested();
        settingsOpen = true;
    }
    function closeSettings() { settingsOpen = false; }
    // a password window (pkexec) has to be seen: Settings and the game launcher step
    // aside while one is up. Counted, so two at once can't bring them back early.
    property int asideCount: 0
    readonly property bool steppedAside: asideCount > 0
    function stepAside() { asideCount++; }
    function stepBack() { asideCount = Math.max(0, asideCount - 1); }
    function toggle(m) {
        if (mode === m) close();
        else open(m, "");
    }

    IpcHandler {
        target: "island"
        function open(m: string): void { root.open(m, ""); }
        function toggle(m: string): void { root.toggle(m); }
        function close(): void { root.close(); }
        function state(): string { return root.mode; }
        function calculator(): void { root.toggle("calculator"); }
        function volume(): void { root.showVolume(); }
        function brightness(): void { root.showBrightness(); }
    }
    IpcHandler {
        target: "settings"
        function open(section: string): void { root.openSettings(section); }
        function close(): void { root.closeSettings(); }
        function toggle(): void { if (root.settingsOpen) root.closeSettings(); else root.openSettings(""); }
    }
    GlobalShortcut {
        appid: "tide"
        name: "launcher"
        description: "Open the island launcher"
        onPressed: root.toggle("launcher")
    }
    GlobalShortcut {
        appid: "tide"
        name: "controlcenter"
        description: "Open or close the control center"
        onPressed: root.controlCenterToggleRequested()
    }
    GlobalShortcut {
        appid: "tide"
        name: "clipboard"
        description: "Open the island clipboard history"
        onPressed: root.toggle("clipboard")
    }
    GlobalShortcut {
        appid: "tide"
        name: "capture"
        description: "Open the island capture tools"
        onPressed: root.toggle("capture")
    }
    GlobalShortcut {
        appid: "tide"
        name: "power"
        description: "Open the island power menu (while locked in a theme: hold 5 s for the emergency exit)"
        // locked in a theme: a tap still opens the menu, a 5 s hold is the emergency exit
        onPressed: Session.locked ? Session.beginHold() : root.toggle("power")
        onReleased: Session.endHold()
    }
    GlobalShortcut {
        appid: "tide"
        name: "resources"
        description: "Open the resource center"
        onPressed: root.toggle("resources")
    }
    GlobalShortcut {
        appid: "tide"
        name: "cleanup"
        description: "Free up space"
        onPressed: root.toggle("cleanup")
    }
    GlobalShortcut {
        appid: "tide"
        name: "themes"
        description: "Open the island theme picker (modes)"
        onPressed: root.toggle("themes")
    }
    GlobalShortcut {
        appid: "tide"
        name: "calculator"
        description: "Open the island calculator"
        onPressed: root.toggle("calculator")
    }
}
