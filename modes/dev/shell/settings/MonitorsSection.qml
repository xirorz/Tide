import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"

// Settings → Monitors. A draft of every screen (from hyprctl): drag them to match
// the desk (they snap edge to edge), pick resolution, refresh rate, scale and
// rotation from each screen's real modes, and the main screen (bar and island).
// Apply pushes it to Hyprland live and asks to keep it; without Keep it goes back
// to how it was after 15 seconds. Keep saves ~/.config/hypr/monitors.conf.
ColumnLayout {
    id: mo
    spacing: Theme.s(16)

    property var live: []        // what Hyprland runs now
    property var draft: []       // what the page shows
    property string sel: ""
    property string mainName: Theme.monitor
    property bool confirming: false
    property int countdown: 15

    readonly property var selMon: draft.find(m => m.name === sel) || draft[0] || null
    readonly property bool changed: JSON.stringify(strip(draft)) !== JSON.stringify(strip(live)) || mainName !== Theme.monitor

    function strip(l) { return l.map(m => ({ n: m.name, w: m.w, h: m.h, hz: m.hz, x: m.x, y: m.y, s: m.scale, t: m.transform, v: m.vrr, b: m.bitdepth, c: m.cm, sb: m.sdrbrightness, ss: m.sdrsaturation })); }

    // what monitors.conf says beyond the mode (Hyprland reports whether VRR is active
    // right now, not the setting, so the setting is read from the file)
    property var saved: ({})
    FileView {
        id: confFile
        path: Quickshell.env("HOME") + "/.config/hypr/monitors.conf"
        printErrors: false
        onLoaded: {
            const s = {};
            for (const line of text().split("\n")) {
                const k = line.match(/^\s*monitor\s*=\s*([^,]+),[^,]+,[^,]+,[\d.]+(.*)$/);
                if (!k) continue;
                const extra = {};
                const parts = k[2].split(",").map(x => x.trim()).filter(x => x !== "");
                for (let i = 0; i + 1 < parts.length; i += 2) extra[parts[i]] = parts[i + 1];
                s[k[1].trim()] = extra;
            }
            mo.saved = s;
            mo.reload();
        }
    }
    function clone(l) { return l.map(m => Object.assign({}, m)); }
    function hzText(r) { return Number(r).toFixed(2); }

    // ---------- reading ----------
    function reload() { reader.running = true; }
    Component.onCompleted: reload()
    Process {
        id: reader
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw;
                try { raw = JSON.parse(text); } catch (e) { return; }
                const l = raw.filter(m => !m.disabled).map(m => {
                    const modes = {};
                    for (const s of m.availableModes) {
                        const k = s.match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
                        if (!k) continue;
                        const res = k[1] + "x" + k[2];
                        (modes[res] = modes[res] || []);
                        const hz = Number(k[3]).toFixed(2);
                        if (modes[res].indexOf(hz) < 0) modes[res].push(hz);
                    }
                    for (const r in modes) modes[r].sort((a, b) => b - a);
                    const sv = mo.saved[m.name] || {};
                    return {
                        name: m.name, desc: m.description || m.model || "",
                        w: m.width, h: m.height, hz: mo.hzText(m.refreshRate),
                        x: m.x, y: m.y, scale: m.scale, transform: m.transform,
                        vrr: sv.vrr !== undefined ? Number(sv.vrr) : 0,
                        bitdepth: sv.bitdepth !== undefined ? Number(sv.bitdepth) : (String(m.currentFormat).indexOf("2101010") >= 0 ? 10 : 8),
                        cm: sv.cm || m.colorManagementPreset || "srgb",
                        sdrbrightness: Number(m.sdrBrightness || 1), sdrsaturation: Number(m.sdrSaturation || 1),
                        modes: modes
                    };
                });
                mo.live = l;
                if (!mo.confirming) mo.draft = mo.clone(l);
                if (!mo.sel && l.length) mo.sel = (l.find(m => m.name === Theme.monitor) || l[0]).name;
            }
        }
    }

    function setField(name, patch) {
        const d = clone(draft);
        const m = d.find(x => x.name === name);
        Object.assign(m, patch);
        // the highest refresh rate when the resolution changes and the old one isn't offered
        if (patch.w !== undefined) {
            const rates = m.modes[m.w + "x" + m.h] || [];
            if (rates.indexOf(m.hz) < 0) m.hz = rates[0];
        }
        const overlaps = d.some(o => o.name !== name && m.x < o.x + lw(o) && m.x + lw(m) > o.x && m.y < o.y + lh(o) && m.y + lh(m) > o.y);
        draft = overlaps ? arrange(d, name) : d;
    }

    // size on the desk (logical pixels: scale and rotation applied)
    function lw(m) { return Math.round((m.transform % 2 ? m.h : m.w) / m.scale); }
    function lh(m) { return Math.round((m.transform % 2 ? m.w : m.h) / m.scale); }

    // snap the moved screen to the nearest edge of another one, keep the rest apart,
    // then move everything so the top-left screen sits at 0,0
    function arrange(d, moved) {
        const m = d.find(x => x.name === moved);
        const others = d.filter(x => x.name !== moved);
        if (m && others.length) {
            let best = null;
            for (const o of others) {
                const cands = [
                    [o.x + lw(o), o.y], [o.x - lw(m), o.y], [o.x, o.y + lh(o)], [o.x, o.y - lh(m)],
                    [o.x + lw(o), o.y + (lh(o) - lh(m)) / 2], [o.x - lw(m), o.y + (lh(o) - lh(m)) / 2],
                    [o.x + lw(o), o.y + lh(o) - lh(m)], [o.x - lw(m), o.y + lh(o) - lh(m)],
                    [o.x + (lw(o) - lw(m)) / 2, o.y + lh(o)], [o.x + (lw(o) - lw(m)) / 2, o.y - lh(m)]
                ];
                for (const c of cands) {
                    const dist = Math.hypot(c[0] - m.x, c[1] - m.y);
                    const overlaps = others.some(p => c[0] < p.x + lw(p) && c[0] + lw(m) > p.x && c[1] < p.y + lh(p) && c[1] + lh(m) > p.y);
                    if (!overlaps && (!best || dist < best.d)) best = { x: c[0], y: c[1], d: dist };
                }
            }
            if (best) { m.x = Math.round(best.x); m.y = Math.round(best.y); }
        }
        const minX = Math.min(...d.map(x => x.x)), minY = Math.min(...d.map(x => x.y));
        for (const x of d) { x.x -= minX; x.y -= minY; }
        return d;
    }

    // ---------- applying ----------
    function luaFor(m) {
        return "hl.monitor({ output = \"" + m.name + "\", mode = \"" + m.w + "x" + m.h + "@" + m.hz + "\", position = \"" + m.x + "x" + m.y +
               "\", scale = " + m.scale + ", transform = " + m.transform + ", vrr = " + m.vrr + ", bitdepth = " + m.bitdepth +
               ", cm = \"" + m.cm + "\", sdrbrightness = " + m.sdrbrightness + ", sdrsaturation = " + m.sdrsaturation + " })";
    }
    function push(list) {
        for (const m of list) Quickshell.execDetached(["hyprctl", "eval", luaFor(m)]);
    }
    property var before: []
    function apply() {
        before = clone(live);
        push(draft);
        confirming = true;
        countdown = 15;
        tick.restart();
        settle.restart();
    }
    function keep() {
        confirming = false;
        tick.stop();
        saver.command = ["python3", "-I", Quickshell.shellDir + "/scripts/monitors-save.py",
            JSON.stringify(draft.map(m => ({ name: m.name, mode: m.w + "x" + m.h + "@" + m.hz, x: m.x, y: m.y, scale: m.scale, transform: m.transform,
                vrr: m.vrr, bitdepth: m.bitdepth, cm: m.cm, sdrbrightness: m.sdrbrightness, sdrsaturation: m.sdrsaturation })))];
        saver.running = true;
        // last: moving the bar to another screen rebuilds this window
        if (mainName !== Theme.monitor) Theme.set("monitor", mainName);
    }
    function undo() {
        confirming = false;
        tick.stop();
        push(before);
        mainName = Theme.monitor;
        draft = clone(before);
        settle.restart();
    }
    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: { mo.countdown -= 1; if (mo.countdown <= 0) mo.undo(); }
    }
    // read back what Hyprland actually did (it may round the scale)
    Timer { id: settle; interval: 1500; onTriggered: mo.reload() }
    Process { id: saver; onExited: confFile.reload() }

    // ---------- layout ----------
    Heading { text: "Monitors"; sub: "Drag the screens to match your desk. Where they touch is where your mouse crosses over." }

    Rectangle {
        id: desk
        Layout.fillWidth: true
        implicitHeight: Theme.s(260)
        radius: Theme.s(18)
        color: Qt.rgba(0, 0, 0, 0.3)
        border.width: 1; border.color: Theme.white(0.07)
        clip: true
        // dotted grid
        Canvas {
            anchors.fill: parent
            onPaint: {
                const c = getContext("2d");
                c.fillStyle = "rgba(255,255,255,0.07)";
                for (let x = 10; x < width; x += 20) for (let y = 10; y < height; y += 20) c.fillRect(x, y, 1, 1);
            }
        }
        // fit every screen with some room around
        readonly property real minX: mo.draft.length ? Math.min(...mo.draft.map(m => m.x)) : 0
        readonly property real minY: mo.draft.length ? Math.min(...mo.draft.map(m => m.y)) : 0
        readonly property real spanW: mo.draft.length ? Math.max(...mo.draft.map(m => m.x + mo.lw(m))) - minX : 1
        readonly property real spanH: mo.draft.length ? Math.max(...mo.draft.map(m => m.y + mo.lh(m))) - minY : 1
        readonly property real k: Math.min((width - 120) / spanW, (height - 80) / spanH)
        readonly property real ox: (width - spanW * k) / 2
        readonly property real oy: (height - spanH * k) / 2

        Repeater {
            model: mo.draft
            delegate: Rectangle {
                id: scr
                required property var modelData
                readonly property bool picked: mo.sel === modelData.name
                property bool dragging: false
                x: dragging ? x : desk.ox + (modelData.x - desk.minX) * desk.k
                y: dragging ? y : desk.oy + (modelData.y - desk.minY) * desk.k
                width: mo.lw(modelData) * desk.k
                height: mo.lh(modelData) * desk.k
                radius: Theme.s(10)
                color: picked ? Theme.white(0.14) : Theme.white(0.08)
                border.width: picked ? 2 : 1
                border.color: picked ? Theme.accent : Theme.white(0.22)
                Behavior on x { enabled: !scr.dragging && !Theme.reduceMotion; NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
                Behavior on y { enabled: !scr.dragging && !Theme.reduceMotion; NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
                Column {
                    anchors.centerIn: parent
                    spacing: Theme.s(3)
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: scr.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: scr.modelData.w + " × " + scr.modelData.h + " · " + Math.round(scr.modelData.hz) + " Hz"; color: Theme.text2; font.family: Theme.mono; font.pointSize: Theme.sf(7.875) }
                    Text { visible: scr.modelData.name === mo.mainName; anchors.horizontalCenter: parent.horizontalCenter; text: "Main"; color: Theme.accent; font.family: Theme.sans; font.pointSize: Theme.sf(7.875); font.weight: Font.DemiBold }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !mo.confirming
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    drag.target: scr
                    drag.threshold: 4
                    onPressed: mo.sel = scr.modelData.name
                    drag.onActiveChanged: {
                        if (drag.active) { scr.dragging = true; return; }
                        // dropped: back to desk pixels, then snap
                        const nx = Math.round((scr.x - desk.ox) / desk.k + desk.minX);
                        const ny = Math.round((scr.y - desk.oy) / desk.k + desk.minY);
                        scr.dragging = false;
                        const d = mo.clone(mo.draft);
                        const m = d.find(v => v.name === scr.modelData.name);
                        m.x = nx; m.y = ny;
                        mo.draft = mo.arrange(d, m.name);
                    }
                }
            }
        }
    }

    // ---------- the selected screen ----------
    SCard {
        visible: mo.selMon !== null
        SRow {
            label: mo.selMon ? mo.selMon.name : ""
            sub: mo.selMon ? mo.selMon.desc : ""
            Text { text: mo.selMon ? mo.lw(mo.selMon) + " × " + mo.lh(mo.selMon) + " on the desk" : ""; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
        }
        SRow {
            label: "Resolution"
            SDropdown {
                interactive: !mo.confirming
                options: mo.selMon ? Object.keys(mo.selMon.modes).sort((a, b) => b.split("x")[0] * b.split("x")[1] - a.split("x")[0] * a.split("x")[1])
                    .map((r, i) => ({ label: r.replace("x", " × "), value: r, note: i === 0 ? "native" : "" })) : []
                value: mo.selMon ? mo.selMon.w + "x" + mo.selMon.h : ""
                onPicked: v => mo.setField(mo.selMon.name, { w: Number(v.split("x")[0]), h: Number(v.split("x")[1]) })
            }
        }
        SRow {
            label: "Refresh rate"
            SDropdown {
                interactive: !mo.confirming
                options: mo.selMon ? (mo.selMon.modes[mo.selMon.w + "x" + mo.selMon.h] || []).map((r, i) => ({ label: (Number(r) % 1 ? Number(r).toFixed(2) : Math.round(r)) + " Hz", value: r, note: i === 0 ? "highest" : "" })) : []
                value: mo.selMon ? mo.selMon.hz : ""
                onPicked: v => mo.setField(mo.selMon.name, { hz: v })
            }
        }
        ChipRow {
            label: "Scale"
            options: [1, 1.25, 1.5, 1.75, 2].map(s => ({ label: s + "×", value: s }))
            value: mo.selMon ? mo.selMon.scale : 1
            onPicked: v => mo.setField(mo.selMon.name, { scale: v })
        }
        ChipRow {
            label: "Rotation"
            options: [{ label: "Normal", value: 0 }, { label: "90°", value: 1 }, { label: "180°", value: 2 }, { label: "270°", value: 3 }]
            value: mo.selMon ? mo.selMon.transform : 0
            onPicked: v => mo.setField(mo.selMon.name, { transform: v })
        }
        SRow {
            last: true
            label: "Main screen (bar and island live here)"
            SToggle { on: mo.selMon !== null && mo.selMon.name === mo.mainName; onToggled: if (!on) mo.mainName = mo.selMon.name }
        }
    }

    // ---------- display options (same Apply / Keep) ----------
    SCard {
        visible: mo.selMon !== null
        title: "Display"
        SRow {
            label: "Variable refresh rate (VRR)"
            sub: "Fullscreen only turns it on for games and video in fullscreen"
            SSegment {
                options: [{ label: "Off", value: 0 }, { label: "On", value: 1 }, { label: "Fullscreen only", value: 2 }]
                value: mo.selMon ? mo.selMon.vrr : 0
                onPicked: v => { if (!mo.confirming) mo.setField(mo.selMon.name, { vrr: v }); }
            }
        }
        SRow {
            label: "10-bit output"
            sub: "Smoother gradients when the screen and cable support it"
            SToggle { interactive: !mo.confirming; on: mo.selMon !== null && mo.selMon.bitdepth === 10; onToggled: mo.setField(mo.selMon.name, { bitdepth: on ? 8 : 10 }) }
        }
        SRow {
            label: "Wide color gamut"
            sub: "Use the screen's full color range instead of sRGB"
            SToggle { interactive: !mo.confirming; on: mo.selMon !== null && mo.selMon.cm === "wide"; onToggled: mo.setField(mo.selMon.name, { cm: on ? "srgb" : "wide" }) }
        }
        SRow {
            label: "SDR brightness"
            sub: "For normal content while HDR is on"
            Row {
                spacing: Theme.s(12)
                Text { anchors.verticalCenter: parent.verticalCenter; width: Theme.s(36); horizontalAlignment: Text.AlignRight; text: sdrB.shown.toFixed(2); color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                SSlider { id: sdrB; from: 0.5; to: 2; step: 0.05; value: mo.selMon ? mo.selMon.sdrbrightness : 1; onReleased: v => { if (!mo.confirming) mo.setField(mo.selMon.name, { sdrbrightness: Math.round(v * 100) / 100 }); } }
            }
        }
        SRow {
            last: true
            label: "SDR saturation"
            sub: "For normal content while HDR is on"
            Row {
                spacing: Theme.s(12)
                Text { anchors.verticalCenter: parent.verticalCenter; width: Theme.s(36); horizontalAlignment: Text.AlignRight; text: sdrS.shown.toFixed(2); color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                SSlider { id: sdrS; from: 0.5; to: 1.5; step: 0.05; value: mo.selMon ? mo.selMon.sdrsaturation : 1; onReleased: v => { if (!mo.confirming) mo.setField(mo.selMon.name, { sdrsaturation: Math.round(v * 100) / 100 }); } }
            }
        }
    }

    // ---------- apply / keep ----------
    // pinned to the bottom of the Settings window (Settings.qml hosts `footer`), so
    // "Keep these settings?" is always in view
    property Item footer: footerRow
    RowLayout {
        id: footerRow
        visible: false
        spacing: Theme.s(8)
        Text {
            Layout.fillWidth: true
            visible: mo.confirming
            text: "Keep these settings? Going back in " + mo.countdown + " s"
            color: Theme.warning; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.Medium
        }
        Item { Layout.fillWidth: true; visible: !mo.confirming }
        Btn {
            label: mo.confirming ? "Go back" : "Revert"
            enabled: mo.confirming || mo.changed
            onClicked: { if (mo.confirming) mo.undo(); else { mo.draft = mo.clone(mo.live); mo.mainName = Theme.monitor; } }
        }
        Btn {
            label: mo.confirming ? "Keep" : "Apply"
            primary: true
            enabled: mo.confirming || mo.changed
            onClicked: mo.confirming ? mo.keep() : mo.apply()
        }
    }

    // a labelled row of chips (resolutions, rates, scales): wraps when there are many
    component ChipRow: Item {
        id: cr
        property string label
        property var options: []
        property var value
        signal picked(var value)
        Layout.fillWidth: true
        implicitHeight: Math.max(Theme.s(28), flow.implicitHeight) + Theme.s(24)
        Text { x: Theme.s(16); y: Theme.s(12) + Theme.s(6); text: cr.label; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
        Flow {
            id: flow
            x: Theme.s(180); y: Theme.s(12)
            width: cr.width - Theme.s(180) - Theme.s(16)
            spacing: Theme.s(6)
            Repeater {
                model: cr.options
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool on: String(cr.value) === String(modelData.value)
                    width: ct.implicitWidth + Theme.s(22); height: Theme.s(28); radius: Theme.s(8)
                    color: on ? Theme.accent : chipMa.containsMouse ? Theme.white(0.12) : Theme.white(0.07)
                    Text { id: ct; anchors.centerIn: parent; text: chip.modelData.label; color: chip.on ? Theme.ink : Theme.text2; font.family: Theme.mono; font.pixelSize: Theme.s(12); font.weight: chip.on ? Font.DemiBold : Font.Normal }
                    MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; enabled: !mo.confirming; cursorShape: Qt.PointingHandCursor; onClicked: cr.picked(chip.modelData.value) }
                }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.white(0.06) }
    }
    component Btn: HoverButton {
        property string label
        property bool primary: false
        implicitWidth: bt.implicitWidth + Theme.s(34); implicitHeight: Theme.s(38); radius: Theme.s(11)
        hoverFill: false
        opacity: enabled ? 1 : 0.4
        color: primary ? (hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent) : Theme.white(hovered ? 0.12 : 0.08)
        Text { id: bt; anchors.centerIn: parent; text: parent.label; color: parent.primary ? Theme.ink : Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: parent.primary ? Font.DemiBold : Font.Normal }
    }
}
