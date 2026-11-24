import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// The control center: drops down from the right corner when the control cluster is
// clicked. 384px wide, at most 830px tall (then it scrolls, no scrollbar), radius 24,
// padding 14, sections 10px apart. Escape or a click outside closes it.
Item {
    id: cc
    property bool open: false
    signal closeRequested()

    width: Theme.s(384)
    height: Math.min(col.implicitHeight + Theme.s(28), maxHeight)
    // the panel may grow down to 12px above the screen's bottom edge
    property real maxHeight: Theme.s(10000)
    // panel drop (motion sheet): 260ms, fade + 8px drop + 98% -> 100%, from the
    // top-right where the control cluster is; reduced motion: a 150ms fade
    visible: opacity > 0
    opacity: 0
    transformOrigin: Item.TopRight
    transform: Translate { id: dropShift; y: 0 }
    ParallelAnimation {
        id: dropIn
        NumberAnimation { target: cc; property: "opacity"; from: 0; to: 1; duration: Theme.reduceMotion ? 150 : Theme.durDrop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
        NumberAnimation { target: dropShift; property: "y"; from: Theme.reduceMotion ? 0 : -8; to: 0; duration: Theme.durDrop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
        NumberAnimation { target: cc; property: "scale"; from: Theme.reduceMotion ? 1 : 0.98; to: 1; duration: Theme.durDrop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
    }
    NumberAnimation { id: dropOut; target: cc; property: "opacity"; to: 0; duration: Theme.durHide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
    focus: open
    Keys.onEscapePressed: cc.closeRequested()

    onOpenChanged: {
        if (open) { dropOut.stop(); dropIn.restart(); } else { dropIn.stop(); dropOut.restart(); }
        if (open) {
            expand = "";
            netProc.running = true;
            wifiProc.running = true;
            forceActiveFocus();
        }
        Notifications.markSeen();
    }

    property string expand: ""          // "" | "net" | "bt" | "out" | "in"
    property bool rgbOk: false
    Process { running: true; command: ["sh", "-c", "test -x \"$HOME/.local/bin/matugen-openrgb-sync\""]; onExited: code => cc.rgbOk = code === 0 }

    // ---------- helpers ----------
    readonly property string onBg: Theme.accent
    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }
    // capture: close first, then the shared Capture service runs it
    function capture(fn) { cc.closeRequested(); fn(); }

    // ---------- network (nmcli) ----------
    property string ethDevice: ""
    property string ethState: ""        // connected | disconnected | unavailable
    property string wifiDevice: ""
    property string ssid: ""
    property var wifiRows: []

    function nmSplit(line) {
        // nmcli -t escapes ':' inside values as '\:'
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue; }
            if (c === ":") { out.push(cur); cur = ""; continue; }
            cur += c;
        }
        out.push(cur);
        return out;
    }
    Process {
        id: netProc
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"]
        stdout: StdioCollector {
            onStreamFinished: {
                let eth = "", ethSt = "", wdev = "", wssid = "";
                for (const l of text.split("\n")) {
                    const f = cc.nmSplit(l);
                    if (f[1] === "ethernet" && (eth === "" || f[2] === "connected")) { eth = f[0]; ethSt = f[2]; }
                    if (f[1] === "wifi") { wdev = f[0]; if (f[2] === "connected") wssid = f[3]; }
                }
                cc.ethDevice = eth; cc.ethState = ethSt; cc.wifiDevice = wdev; cc.ssid = wssid;
            }
        }
    }
    Process {
        id: wifiProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SECURITY", "device", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}, rows = [];
                for (const l of text.split("\n")) {
                    const f = cc.nmSplit(l);
                    if (!f[1] || seen[f[1]]) continue;
                    seen[f[1]] = true;
                    rows.push({ name: f[1], inUse: f[0] === "*", secure: (f[2] || "") !== "" && f[2] !== "--" });
                }
                rows.sort((a, b) => b.inUse - a.inUse);
                cc.wifiRows = rows.slice(0, 8);
            }
        }
    }
    Timer { interval: 5000; repeat: true; running: cc.open; onTriggered: netProc.running = true }
    Process {
        id: connectProc
        property string label: ""
        onExited: (code, status) => {
            netProc.running = true;
            Net.refresh();
            if (code !== 0) cc.run("notify-send -a Network \"Couldn't connect\" \"" + label + " needs a password or is out of range.\"");
        }
    }
    function connectTo(args, label) {
        connectProc.label = label;
        connectProc.command = ["nmcli"].concat(args);
        connectProc.running = true;
    }

    readonly property string netName: Net.kind === "wifi" ? "Wi-Fi" : Net.kind === "ethernet" ? "Ethernet" : "Offline"
    readonly property string netSub: Net.kind === "ethernet" ? "Connected" : Net.kind === "wifi" ? "Connected · " + cc.ssid : "Not connected"
    readonly property string ethSub: ethState === "connected" ? "Connected · Wired" : ethState === "unavailable" ? "Unplugged" : "Cable plugged in"

    // ---------- bluetooth ----------
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: adapter ? adapter.enabled : false
    readonly property var btDevices: adapter ? adapter.devices.values.filter(d => d.paired) : []
    readonly property int btConnected: btDevices.filter(d => d.connected).length
    readonly property string btSub: btOn ? "On · " + btConnected + (btConnected === 1 ? " device" : " devices") : "Off"
    // looking for new devices while the Bluetooth list is open (stops when it closes)
    readonly property bool btSearch: open && expand === "bt" && btOn
    onBtSearchChanged: if (adapter && adapter.discovering !== btSearch) adapter.discovering = btSearch
    // nearby devices that aren't paired yet (named ones: unnamed ones are mostly beacons)
    readonly property var btNearby: adapter ? adapter.devices.values.filter(d => !d.paired && d.deviceName) : []
    // pair, trust (so it reconnects by itself later), then connect
    property var btAsked: ({})          // addresses paired from here
    function btPair(d) {
        if (d.pairing) { d.cancelPair(); return; }
        btAsked[d.address] = true;
        d.pair();
    }
    Instantiator {
        model: cc.adapter ? cc.adapter.devices : null
        delegate: Connections {
            required property var modelData
            target: modelData
            function onPairedChanged() {
                if (!modelData.paired || !cc.btAsked[modelData.address]) return;
                delete cc.btAsked[modelData.address];
                modelData.trusted = true;
                modelData.connect();
            }
        }
    }
    function btIcon(d) {
        const i = d.icon || "";
        if (i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0) return Icons.headset;
        if (i.indexOf("mouse") >= 0) return Icons.mouse;
        if (i.indexOf("gaming") >= 0 || i.indexOf("joystick") >= 0) return Icons.controller;
        if (i.indexOf("phone") >= 0) return Icons.phone;
        if (i.indexOf("microphone") >= 0) return Icons.mic;
        return Icons.bluetooth;
    }

    // ---------- stay awake: services/Idle.qml (shared with Settings) ----------

    // ---------- sound ----------
    // (sinks and volume live in services/Audio.qml, shared with the volume pop-up)

    // ---------- lighting ----------
    // "rgbBrightness" (10-100). Each apply takes ~2s (OpenRGB, headset, panels), so a
    // drag applies the newest value as soon as the previous apply finishes.
    property int rgbBrightness: Theme.opt("rgbBrightness", 10)
    property bool rgbPending: false
    function setRgb(v) {
        rgbBrightness = Math.max(10, Math.min(100, v));
        rgbDebounce.restart();
    }
    Timer {
        id: rgbDebounce
        interval: 150
        onTriggered: {
            if (rgbProc.running) { cc.rgbPending = true; return; }
            Theme.set("rgbBrightness", cc.rgbBrightness);
            rgbProc.command = ["bash", Quickshell.shellDir + "/scripts/rgb-apply.sh", String(cc.rgbBrightness)];
            rgbProc.running = true;
        }
    }
    Process {
        id: rgbProc
        onExited: if (cc.rgbPending) { cc.rgbPending = false; rgbDebounce.restart(); }
    }

    // ---------- media ----------
    readonly property var player: {
        const ps = Mpris.players.values;
        return ps.find(p => p.isPlaying) || ps[0] || null;
    }
    readonly property bool playing: player !== null && player.isPlaying
    Timer {
        interval: 1000; repeat: true
        running: cc.open && cc.playing
        onTriggered: cc.player.positionChanged()
    }
    function mmss(s) {
        s = Math.max(0, Math.floor(s));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    // ---------- the panel ----------
    Surface { anchors.fill: parent; kind: "panel"; radius: Theme.s(24) }

    // swallow clicks on the panel so they don't reach the outside-click catcher
    MouseArea { anchors.fill: parent }

    // taller than the screen (a laptop): it stops above the bottom edge and scrolls
    Flickable {
        id: scroller
        anchors.fill: parent
        contentHeight: col.implicitHeight + Theme.s(28)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
    ColumnLayout {
        id: col
        x: Theme.s(14); y: Theme.s(14)
        width: cc.width - Theme.s(28)
        spacing: Theme.s(10)

        // ===== header =====
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.s(4)
            Layout.rightMargin: Theme.s(2)
            T { text: "Control center"; px: Theme.type.h2[0]; weight: Theme.type.h2[1]; color: Theme.text; Layout.fillWidth: true }
            HoverButton {
                implicitWidth: Theme.s(30); implicitHeight: Theme.s(30)
                onClicked: IslandState.openSettings("")
                Icon { anchors.centerIn: parent; path: Icons.sliders; color: Theme.text2 }
            }
        }

        // ===== quick tiles =====
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Theme.s(8)
            rowSpacing: Theme.s(8)
            uniformCellWidths: true

            QuickTile {
                title: cc.netName
                sub: cc.netSub
                icon: Net.kind === "wifi" ? Icons.wifiArcs : Icons.ethernet
                on: Net.kind !== "none"
                chevron: cc.expand === "net" ? Icons.chevronUp : Icons.chevronDown
                expanded: cc.expand === "net"
                onClicked: cc.expand = cc.expand === "net" ? "" : "net"
            }
            QuickTile {
                title: "Bluetooth"
                sub: cc.btSub
                icon: Icons.bluetooth
                on: cc.btOn
                chevron: cc.expand === "bt" ? Icons.chevronUp : Icons.chevronDown
                expanded: cc.expand === "bt"
                onClicked: cc.expand = cc.expand === "bt" ? "" : "bt"
            }
            QuickTile {
                title: "Stay awake"
                sub: Idle.awake ? "Screen stays on" : "Off"
                icon: Icons.cup
                on: Idle.awake
                onClicked: Idle.awake = !Idle.awake
            }
        }

        // ===== network list =====
        Card {
            visible: cc.expand === "net"
            padding: Theme.s(8)
            spacing: Theme.s(2)

            ListRow {
                rowHeight: Theme.s(46)
                icon: Icons.ethernet
                title: "Ethernet"
                sub: cc.ethSub
                trailing: cc.ethState === "connected" ? Icons.check : ""
                trailingStroke: 2.2
                trailingColor: Theme.text
                onClicked: if (cc.ethDevice) cc.connectTo(["device", "connect", cc.ethDevice], "Ethernet")
            }
            SectionLabel { text: "Wi-Fi networks" }
            Repeater {
                model: cc.wifiRows
                delegate: ListRow {
                    required property var modelData
                    readonly property bool connected: modelData.inUse
                    rowHeight: Theme.s(42)
                    icon: Icons.wifiArcs
                    iconColor: connected ? Theme.text : Theme.muted
                    title: modelData.name
                    sub: connected ? "Connected" : modelData.secure ? "Secured" : "Open"
                    trailing: connected ? Icons.check : modelData.secure ? Icons.lock : Icons.chevronRight
                    onClicked: if (!connected) cc.connectTo(["device", "wifi", "connect", modelData.name], modelData.name)
                }
            }
            T {
                visible: cc.wifiRows.length === 0
                Layout.leftMargin: Theme.s(8)
                Layout.bottomMargin: Theme.s(4)
                text: cc.wifiDevice ? "No networks found" : "No Wi-Fi adapter"
                px: Theme.s(11); color: Theme.muted
            }
        }

        // ===== bluetooth list =====
        Card {
            visible: cc.expand === "bt"
            padding: Theme.s(8)
            spacing: Theme.s(2)

            HoverButton {
                Layout.fillWidth: true
                implicitHeight: Theme.s(40)
                radius: Theme.s(11)
                onClicked: if (cc.adapter) cc.adapter.enabled = !cc.adapter.enabled
                T { x: Theme.s(8); anchors.verticalCenter: parent.verticalCenter; text: "Bluetooth"; px: Theme.s(12.5); weight: Font.Medium }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.s(8)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.s(36); height: Theme.s(22); radius: Theme.s(11)
                    color: cc.btOn ? Theme.text : Theme.white(0.18)
                    Rectangle {
                        y: Theme.s(2)
                        x: cc.btOn ? Theme.s(16) : Theme.s(2)
                        width: Theme.s(18); height: Theme.s(18); radius: Theme.s(9)
                        color: cc.btOn ? Theme.ink : Theme.text
                    }
                }
            }
            SectionLabel { visible: cc.btOn && cc.btDevices.length > 0; text: "Devices" }
            Repeater {
                model: cc.btOn ? cc.btDevices : []
                delegate: ListRow {
                    required property var modelData
                    rowHeight: Theme.s(44)
                    icon: cc.btIcon(modelData)
                    iconColor: modelData.connected ? Theme.text : Theme.muted
                    title: modelData.name || modelData.deviceName
                    sub: modelData.connected
                         ? "Connected" + (modelData.batteryAvailable ? " · " + Math.round(modelData.battery * 100) + "%" : "")
                         : "Paired"
                    action: modelData.connected ? "Disconnect" : "Connect"
                    onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                }
            }
            SectionLabel { visible: cc.btOn; text: cc.adapter && cc.adapter.discovering ? "Nearby · searching…" : "Nearby" }
            Repeater {
                model: cc.btOn ? cc.btNearby : []
                delegate: ListRow {
                    required property var modelData
                    rowHeight: Theme.s(44)
                    icon: cc.btIcon(modelData)
                    iconColor: Theme.muted
                    title: modelData.deviceName
                    sub: modelData.pairing ? "Pairing…" : "Not paired"
                    action: modelData.pairing ? "Cancel" : "Pair"
                    onClicked: cc.btPair(modelData)
                }
            }
            T {
                visible: cc.btOn && cc.btNearby.length === 0
                Layout.leftMargin: Theme.s(8)
                Layout.bottomMargin: Theme.s(4)
                text: "Put the device in pairing mode to see it here"
                px: Theme.s(11); color: Theme.muted
            }
        }

        // ===== appearance =====
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.s(52)
            radius: Theme.s(16)
            color: Theme.tile
            T { x: Theme.s(14); anchors.verticalCenter: parent.verticalCenter; text: "Appearance"; px: Theme.s(14); weight: Font.DemiBold }
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: Theme.s(8)
                anchors.verticalCenter: parent.verticalCenter
                width: seg.implicitWidth + Theme.s(6)
                height: Theme.s(36)
                radius: Theme.s(12)
                color: Qt.rgba(0, 0, 0, 0.3)
                Row {
                    id: seg
                    x: Theme.s(3); y: Theme.s(3)
                    spacing: Theme.s(2)
                    Segment { label: "Dark"; on: Theme.surface !== "glass" && Theme.surface !== "tinted"; onClicked: Theme.setSurface("dark") }
                    Segment { label: "Glass"; on: Theme.surface === "glass"; onClicked: Theme.setSurface("glass") }
                    Segment { label: "Tinted"; on: Theme.surface === "tinted"; onClicked: Theme.setSurface("tinted") }
                }
            }
        }

        // ===== battery (laptops): level and time, power mode, screen brightness =====
        Card {
            visible: Power.hasBattery
            padding: Theme.s(12)
            hPadding: Theme.s(14)
            spacing: Theme.s(8)

            RowLayout {
                Layout.fillWidth: true
                T { text: "Battery"; px: Theme.s(14); weight: Font.DemiBold; Layout.fillWidth: true }
                T { text: Math.round(Power.level * 100) + "% · " + Power.status; px: Theme.s(12); color: Theme.muted }
            }
            // power mode (power-profiles-daemon)
            Rectangle {
                visible: Power.hasProfiles
                Layout.fillWidth: true
                implicitHeight: Theme.s(36)
                radius: Theme.s(12)
                color: Qt.rgba(0, 0, 0, 0.3)
                Row {
                    x: Theme.s(3); y: Theme.s(3)
                    spacing: Theme.s(2)
                    readonly property real w: (parent.width - Theme.s(6) - Theme.s(4)) / (Power.hasPerformance ? 3 : 2)
                    Segment { width: parent.w; label: "Power saver"; on: Power.profile === "saver"; onClicked: Power.setProfile("saver") }
                    Segment { width: parent.w; label: "Balanced"; on: Power.profile === "balanced"; onClicked: Power.setProfile("balanced") }
                    Segment { visible: Power.hasPerformance; width: parent.w; label: "Performance"; on: Power.profile === "performance"; onClicked: Power.setProfile("performance") }
                }
            }
            // the screen's brightness
            RowLayout {
                visible: Power.hasBacklight
                Layout.fillWidth: true
                spacing: Theme.s(10)
                Icon { path: Icons.sun; color: Theme.muted }
                VolumeSlider {
                    Layout.fillWidth: true
                    value: Power.brightness
                    onMoved: v => Power.setBrightness(v)
                }
                T {
                    Layout.preferredWidth: Theme.s(22)
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(Power.brightness * 100)
                    px: Theme.s(11); mono: true; color: Theme.muted
                }
            }
        }

        // ===== lighting: RGB brightness (the color comes from the wallpaper); only on a
        // PC with the OpenRGB sync Tide drives (~/.local/bin/matugen-openrgb-sync) =====
        Card {
            visible: cc.rgbOk
            padding: Theme.s(12)
            hPadding: Theme.s(14)
            spacing: Theme.s(8)

            RowLayout {
                Layout.fillWidth: true
                T { text: "Lighting"; px: Theme.s(14); weight: Font.DemiBold; Layout.fillWidth: true }
                T { text: "RGB"; px: Theme.s(12); color: Theme.muted }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s(10)
                Icon { path: Icons.sun; color: Theme.muted }
                VolumeSlider {
                    Layout.fillWidth: true
                    value: (cc.rgbBrightness - 10) / 90
                    onMoved: v => cc.setRgb(10 + Math.round(v * 90))
                }
                T {
                    Layout.preferredWidth: Theme.s(22)
                    horizontalAlignment: Text.AlignRight
                    text: cc.rgbBrightness
                    px: Theme.s(11); mono: true; color: Theme.muted
                }
            }
        }

        // ===== sound =====
        Card {
            padding: Theme.s(12)
            hPadding: Theme.s(14)
            spacing: Theme.s(8)

            RowLayout {
                Layout.fillWidth: true
                T { text: "Sound"; px: Theme.s(14); weight: Font.DemiBold; Layout.fillWidth: true }
                T { visible: Audio.quickPair; text: "Output"; px: Theme.s(12); color: Theme.muted }
            }
            // two named outputs (theme.json speakersSink / headphonesSink): one button each
            GridLayout {
                visible: Audio.quickPair
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.s(6)
                uniformCellWidths: true
                OutputButton { label: "Studio speakers"; icon: Icons.speakers; node: Audio.speakers }
                OutputButton { label: "Headphones"; icon: Icons.headset; node: Audio.headphones }
            }
            // otherwise: the output in use (click to pick another) and its volume
            DeviceButton {
                visible: !Audio.quickPair; label: "Output"; device: Audio.label(Audio.sink); open: cc.expand === "out"; onClicked: cc.expand = cc.expand === "out" ? "" : "out" }
            Repeater {
                model: cc.expand === "out" ? Audio.sinks : []
                delegate: DeviceRow { required property var modelData; node: modelData; on: modelData === Audio.sink; onClicked: { Audio.use(modelData); cc.expand = ""; } }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s(10)
                Icon { path: Icons.speaker; color: Theme.muted }
                VolumeSlider {
                    Layout.fillWidth: true
                    value: Audio.volume
                    onMoved: v => Audio.setVolume(v)
                }
                T {
                    Layout.preferredWidth: Theme.s(22)
                    horizontalAlignment: Text.AlignRight
                    text: Audio.sink ? Math.round(Audio.volume * 100) : "–"
                    px: Theme.s(11); mono: true; color: Theme.muted
                }
            }
            // input: the microphone and its level (with the pickers)
            DeviceButton {
                visible: !Audio.quickPair; label: "Input"; device: Audio.label(Audio.source); open: cc.expand === "in"; onClicked: cc.expand = cc.expand === "in" ? "" : "in" }
            Repeater {
                model: cc.expand === "in" ? Audio.sources : []
                delegate: DeviceRow { required property var modelData; node: modelData; on: modelData === Audio.source; onClicked: { Audio.useSource(modelData); cc.expand = ""; } }
            }
            RowLayout {
                visible: !Audio.quickPair
                Layout.fillWidth: true
                spacing: Theme.s(10)
                Icon { path: Icons.mic; color: Theme.muted }
                VolumeSlider {
                    Layout.fillWidth: true
                    value: Audio.inVolume
                    onMoved: v => Audio.setInVolume(v)
                }
                T {
                    Layout.preferredWidth: Theme.s(22)
                    horizontalAlignment: Text.AlignRight
                    text: Audio.source ? Math.round(Audio.inVolume * 100) : "–"
                    px: Theme.s(11); mono: true; color: Theme.muted
                }
            }
        }

        // ===== capture =====
        Card {
            padding: Theme.s(12)
            spacing: Theme.s(8)

            RowLayout {
                Layout.fillWidth: true
                T { text: "Screenshot"; px: Theme.s(14); weight: Font.DemiBold; Layout.fillWidth: true }
                // the quick way in, for next time
                T { text: "Mod+S"; px: Theme.s(11); mono: true; color: Theme.dim; Layout.rightMargin: Theme.s(4) }
                FolderButton { onClicked: Capture.openScreenshots() }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 3; columnSpacing: Theme.s(6); uniformCellWidths: true
                CaptureButton { label: "Region"; icon: Icons.shotRegion; onClicked: cc.capture(() => Capture.screenshot("region")) }
                CaptureButton { label: "Window"; icon: Icons.shotWindow; onClicked: cc.capture(() => Capture.screenshot("window")) }
                CaptureButton { label: "Screen"; icon: Icons.shotScreen; onClicked: cc.capture(() => Capture.screenshot("screen")) }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.s(4)
                Row {
                    Layout.fillWidth: true
                    spacing: Theme.s(7)
                    Rectangle { width: Theme.s(7); height: Theme.s(7); radius: Theme.s(4); color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
                    T { text: "Record"; px: Theme.s(14); weight: Font.DemiBold }
                }
                FolderButton { onClicked: Capture.openRecordings() }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 3; columnSpacing: Theme.s(6); uniformCellWidths: true
                CaptureButton { label: "Region"; icon: Icons.corners; dot: Qt.point(12, 12); dotR: 2.5; onClicked: cc.capture(() => Capture.record("region")) }
                CaptureButton { label: "Window"; icon: Icons.shotWindow; dot: Qt.point(12, 14); dotR: 2; onClicked: cc.capture(() => Capture.record("window")) }
                CaptureButton { label: "Screen"; icon: Icons.shotScreen; dot: Qt.point(12, 10); dotR: 2; onClicked: cc.capture(() => Capture.record("screen")) }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.white(0.07) }
            GridLayout {
                Layout.fillWidth: true
                columns: 3; columnSpacing: Theme.s(6); uniformCellWidths: true
                ToolButton { label: "OCR"; icon: Icons.ocr; onClicked: cc.capture(() => Capture.ocr()) }
                ToolButton { label: "Color"; icon: Icons.picker; onClicked: cc.capture(() => Capture.colorPicker()) }
                ToolButton { label: "Timer"; icon: Icons.timer; onClicked: Capture.timer() }
            }
        }

        // ===== now playing =====
        Card {
            visible: cc.playing
            padding: Theme.s(12)
            spacing: Theme.s(10)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s(12)
                ClippingRectangle {
                    implicitWidth: Theme.s(46); implicitHeight: Theme.s(46)
                    radius: Theme.s(10)
                    color: "transparent"
                    // linear-gradient(135deg, #3A3A3F, #18181B)
                    Shape {
                        anchors.fill: parent
                        ShapePath {
                            strokeWidth: -1
                            fillGradient: LinearGradient {
                                x1: 0; y1: 0; x2: Theme.s(46); y2: Theme.s(46)
                                GradientStop { position: 0; color: "#3A3A3F" }
                                GradientStop { position: 1; color: "#18181B" }
                            }
                            PathRectangle { x: 0; y: 0; width: Theme.s(46); height: Theme.s(46) }
                        }
                    }
                    Icon { anchors.centerIn: parent; path: Icons.music; color: Theme.muted; visible: art.status !== Image.Ready }
                    Image {
                        id: art
                        anchors.fill: parent
                        source: cc.player ? cc.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize: Qt.size(92, 92)
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.s(2)
                    T { Layout.fillWidth: true; elide: Text.ElideRight; text: cc.player ? cc.player.trackTitle : ""; px: Theme.s(13); weight: Font.DemiBold }
                    T { Layout.fillWidth: true; elide: Text.ElideRight; text: cc.player ? cc.player.trackArtist : ""; px: Theme.s(12); color: Theme.muted }
                }
                EqBars { running: cc.open && cc.playing; Layout.alignment: Qt.AlignVCenter }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s(8)
                T { text: cc.player ? cc.mmss(cc.player.position) : "0:00"; px: Theme.s(11); mono: true; color: Theme.muted }
                SeekBar {
                    Layout.fillWidth: true
                    animating: cc.open && cc.playing
                    progress: cc.player && cc.player.length > 0 ? cc.player.position / cc.player.length : 0
                    onSeek: f => { if (cc.player && cc.player.canSeek) cc.player.position = f * cc.player.length; }
                }
                T { text: cc.player ? cc.mmss(cc.player.length) : "0:00"; px: Theme.s(11); mono: true; color: Theme.muted }
            }

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.s(18)
                HoverButton {
                    width: Theme.s(34); height: Theme.s(34)
                    onClicked: if (cc.player) cc.player.previous()
                    Icon { anchors.centerIn: parent; path: Icons.prev; filled: true; stroke: -1 }
                }
                HoverButton {
                    width: Theme.s(34); height: Theme.s(34); radius: Theme.s(17)
                    hoverFill: false
                    color: Theme.text
                    onClicked: if (cc.player) cc.player.togglePlaying()
                    Icon { anchors.centerIn: parent; path: cc.playing ? Icons.pause : Icons.play; filled: true; stroke: -1; color: Theme.ink }
                }
                HoverButton {
                    width: Theme.s(34); height: Theme.s(34)
                    onClicked: if (cc.player) cc.player.next()
                    Icon { anchors.centerIn: parent; path: Icons.next; filled: true; stroke: -1 }
                }
            }
        }
        // ===== notifications: the only part that scrolls, 3 cards tall =====
        ColumnLayout {
            id: notifSection
            Layout.fillWidth: true
            spacing: Theme.s(6)

            RowLayout {
                id: notifHeader
                Layout.fillWidth: true
                Layout.leftMargin: Theme.s(4)
                Layout.rightMargin: Theme.s(4)
                Layout.topMargin: Theme.s(4)
                T { text: "Notifications"; px: Theme.type.h2[0]; weight: Theme.type.h2[1]; Layout.fillWidth: true }
                HoverButton {
                    implicitWidth: clearLbl.implicitWidth + Theme.s(12)
                    implicitHeight: Theme.s(24)
                    onClicked: Notifications.clearAll()
                    T { id: clearLbl; anchors.centerIn: parent; text: "Clear all"; px: Theme.s(12); color: Theme.muted }
                }
            }
            Flickable {
                id: notifView
                visible: notifRep.count > 0
                Layout.fillWidth: true
                // three full cards (fewer if there are fewer), less if the panel would
                // run past the bottom of the screen
                readonly property real threeCards: {
                    notifCol.implicitHeight;
                    const n = Math.min(3, notifRep.count);
                    let h = 0;
                    for (let i = 0; i < n; i++) {
                        const it = notifRep.itemAt(i);
                        if (it) h += it.implicitHeight;
                    }
                    return h + Math.max(0, n - 1) * 6;
                }
                // everything above the list: the fixed sections, the header and the gaps
                readonly property real room: {
                    let used = 28 + notifHeader.implicitHeight + 4 + 6;
                    for (const c of col.children) {
                        if (c === notifSection || !c.visible) continue;
                        used += c.implicitHeight + col.spacing;
                    }
                    return cc.maxHeight - used;
                }
                Layout.preferredHeight: Math.max(0, Math.min(threeCards, room))
                contentHeight: notifCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                WheelScroll {}

                ColumnLayout {
                    id: notifCol
                    width: notifView.width
                    spacing: Theme.s(6)
                    Repeater {
                        id: notifRep
                        model: Notifications.list
                        delegate: NotificationCard {
                            required property var modelData
                            n: modelData
                        }
                    }
                }
            }
        }
    }
    }


    // ================= pieces =================

    // text at the design's sizes (some are fractional, so they go through pointSize)
    component T: Text {
        property real px: Theme.s(13)
        property int weight: Font.Normal
        property bool mono: false
        color: Theme.text
        font.family: mono ? Theme.mono : Theme.sans
        font.pointSize: px * 0.75
        font.weight: weight
    }

    // a section block: tile background, radius 16
    component Card: Rectangle {
        id: card
        property real padding: Theme.s(12)
        property real hPadding: padding
        property alias spacing: inner.spacing
        default property alias content: inner.data
        Layout.fillWidth: true
        implicitHeight: inner.implicitHeight + padding * 2
        radius: Theme.s(16)
        color: Theme.tile
        ColumnLayout {
            id: inner
            x: card.hPadding
            y: card.padding
            width: card.width - card.hPadding * 2
        }
    }

    component SectionLabel: Item {
        property alias text: lbl.text
        Layout.fillWidth: true
        Layout.topMargin: Theme.s(2)
        implicitHeight: lbl.implicitHeight + Theme.s(12)
        Rectangle { width: parent.width; height: 1; color: Theme.white(0.07) }
        T { id: lbl; x: Theme.s(8); y: Theme.s(8); px: Theme.s(11); color: Theme.muted }
    }

    component QuickTile: HoverButton {
        id: qt
        property string title
        property string sub
        property string icon
        property string chevron: ""
        property bool on: false
        property bool expanded: false
        Layout.fillWidth: true
        implicitHeight: tileCol.implicitHeight + Theme.s(24)
        radius: Theme.s(16)
        hoverFill: false
        color: Theme.tile
        Rectangle {
            anchors.fill: parent
            radius: Theme.s(16)
            color: "transparent"
            border.width: 1
            border.color: Theme.white(0.45)
            visible: qt.expanded
        }
        ColumnLayout {
            id: tileCol
            x: Theme.s(12); y: Theme.s(12)
            width: qt.width - Theme.s(24)
            spacing: Theme.s(10)
            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    implicitWidth: Theme.s(32); implicitHeight: Theme.s(32); radius: Theme.s(16)
                    color: qt.on ? cc.onBg : Theme.white(0.1)
                    Icon { anchors.centerIn: parent; path: qt.icon; color: qt.on ? Theme.ink : Theme.muted }
                }
                Item { Layout.fillWidth: true }
                Icon { visible: qt.chevron !== ""; path: qt.chevron; size: Theme.s(14); color: Theme.muted }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                T { text: qt.title; px: Theme.s(14); weight: Font.DemiBold }
                T { Layout.fillWidth: true; text: qt.sub; px: Theme.s(11); color: Theme.muted; elide: Text.ElideRight }
            }
        }
    }

    component ListRow: HoverButton {
        id: lr
        property real rowHeight: Theme.s(44)
        property string icon
        property color iconColor: Theme.text
        property string title
        property string sub
        property string trailing: ""
        property real trailingStroke: 1.6
        property color trailingColor: Theme.muted
        property string action: ""
        Layout.fillWidth: true
        implicitHeight: rowHeight
        radius: Theme.s(11)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.s(8)
            anchors.rightMargin: Theme.s(8)
            spacing: Theme.s(10)
            Icon { path: lr.icon; color: lr.iconColor }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                T { Layout.fillWidth: true; elide: Text.ElideRight; text: lr.title; px: Theme.s(12.5); weight: Font.Medium }
                T { text: lr.sub; px: Theme.s(11); color: Theme.muted }
            }
            Icon { visible: lr.trailing !== ""; path: lr.trailing; size: Theme.s(14); stroke: lr.trailingStroke; color: lr.trailingColor }
            Rectangle {
                visible: lr.action !== ""
                implicitWidth: actLbl.implicitWidth + Theme.s(16)
                implicitHeight: actLbl.implicitHeight + Theme.s(8)
                radius: Theme.s(8)
                color: Theme.white(0.07)
                T { id: actLbl; anchors.centerIn: parent; text: lr.action; px: Theme.s(11); color: Theme.text2 }
            }
        }
    }

    component Segment: HoverButton {
        property string label
        property bool on: false
        width: segLbl.implicitWidth + Theme.s(32)
        height: Theme.s(30)
        radius: Theme.s(9)
        hoverFill: false
        color: on ? cc.onBg : "transparent"
        T { id: segLbl; anchors.centerIn: parent; text: parent.label; px: Theme.s(12); weight: Font.Medium; color: parent.on ? Theme.ink : Theme.text2 }
    }

    component OutputButton: HoverButton {
        id: ob
        property string label
        property string icon
        property var node: null
        readonly property bool on: node !== null && Pipewire.defaultAudioSink === node
        Layout.fillWidth: true
        implicitHeight: Theme.s(40)
        radius: Theme.s(11)
        hoverFill: false
        color: on ? cc.onBg : Qt.rgba(0, 0, 0, 0.25)
        opacity: node ? 1 : 0.5
        onClicked: Audio.use(node)
        Row {
            x: Theme.s(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s(8)
            Icon { path: ob.icon; color: ob.on ? Theme.ink : Theme.text2 }
            T { anchors.verticalCenter: parent.verticalCenter; text: ob.label; px: Theme.s(12); weight: Font.Medium; color: ob.on ? Theme.ink : Theme.text2 }
        }
    }

    component FolderButton: HoverButton {
        implicitWidth: Theme.s(26); implicitHeight: Theme.s(26)
        Icon { anchors.centerIn: parent; path: Icons.folder; size: Theme.s(14); color: Theme.muted }
    }

    component CaptureButton: HoverButton {
        id: cb
        property string label
        property string icon
        property point dot: Qt.point(-1, -1)
        property real dotR: 0
        Layout.fillWidth: true
        implicitHeight: Theme.s(54)
        radius: Theme.s(11)
        hoverFill: false
        color: Qt.rgba(0, 0, 0, 0.25)
        Column {
            anchors.centerIn: parent
            spacing: Theme.s(5)
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.s(16); height: Theme.s(16)
                Icon { path: cb.icon; color: Theme.soft }
                Icon { visible: cb.dotR > 0; path: Icons.circle(cb.dot.x, cb.dot.y, cb.dotR); filled: true; stroke: -1; color: Theme.soft }
            }
            T { anchors.horizontalCenter: parent.horizontalCenter; text: cb.label; px: Theme.s(11); color: Theme.soft }
        }
    }

    component ToolButton: HoverButton {
        id: tb
        property string label
        property string icon
        Layout.fillWidth: true
        implicitHeight: Theme.s(32)
        Row {
            anchors.centerIn: parent
            spacing: Theme.s(6)
            Icon { path: tb.icon; size: Theme.s(14); color: Theme.text2; anchors.verticalCenter: parent.verticalCenter }
            T { text: tb.label; px: Theme.s(11.5); color: Theme.text2; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // the wavy played part (accent, moving), a 4px handle, then the flat rest
    component NotificationCard: HoverButton {
        id: nc
        property var n
        readonly property string iconSource: {
            if (!n) return "";
            if (n.image) return n.image;
            if (n.appIcon) return n.appIcon.indexOf("/") === 0 || n.appIcon.indexOf("file:") === 0 ? n.appIcon : Quickshell.iconPath(n.appIcon, true);
            const e = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null;
            return e && e.icon ? Quickshell.iconPath(e.icon, true) : "";
        }
        readonly property string bodyText: {
            if (!n) return "";
            const b = (n.body || "").replace(/<[^>]*>/g, "");
            const lines = [];
            if (n.appName && n.summary) lines.push(n.summary);
            if (b) lines.push(b);
            return lines.join("\n");
        }
        Layout.fillWidth: true
        implicitHeight: ncRow.implicitHeight + Theme.s(20)
        radius: Theme.s(14)
        hoverFill: false
        color: Theme.tile
        onClicked: Notifications.activate(n)
        RowLayout {
            id: ncRow
            x: Theme.s(12); y: Theme.s(10)
            width: nc.width - Theme.s(24)
            spacing: Theme.s(10)
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: Theme.s(28); implicitHeight: Theme.s(28); radius: Theme.s(8)
                color: Theme.white(0.08)
                IconImage {
                    anchors.centerIn: parent
                    visible: nc.iconSource !== ""
                    source: nc.iconSource
                    implicitSize: Theme.s(16)
                }
                Icon { anchors.centerIn: parent; visible: nc.iconSource === ""; path: Icons.bell; size: Theme.s(14) }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.s(2)
                RowLayout {
                    Layout.fillWidth: true
                    T { Layout.fillWidth: true; elide: Text.ElideRight; text: nc.n ? (nc.n.appName || nc.n.summary) : ""; px: Theme.s(12); weight: Font.DemiBold }
                    T { text: nc.n ? Notifications.ago(nc.n) : ""; px: Theme.s(12); color: Theme.muted }
                }
                T {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: nc.bodyText
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    px: Theme.s(12); color: Theme.text2
                }
            }
        }
    }
}
