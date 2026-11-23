import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import ".."
import "../components"
import "../services"

// "Save current setup as new theme" (the design's 4 steps): Name it (and what to keep
// from the current setup), Apps ("Only allow these apps"; they also open when the
// theme starts), Time and limits (how long, repeat days and time, "Lock me in until
// time is up"), Review. Saving hands it to bin/tide-mode save, which captures the
// setup itself.
Rectangle {
    id: wz
    signal closed()
    property int step: 1
    property string name: ""
    property var caps: ({ widgets: true, wallpaper: true, bar: true, surface: true, windows: false, monitors: false, cursor: false, gtk: false, icons: false, qt: false })
    property bool limit: false
    property var apps: []                 // [{ name, class, command, icon }]
    property int duration: 0              // minutes, 0 = no limit
    property var days: []                 // 0 = Sunday
    property string time: "19:00"
    property bool lockout: false
    // Tide's own tools while the apps are limited
    readonly property var toolList: [["calculator", "Calculator"], ["clipboard", "Clipboard"], ["capture", "Capture"], ["dictation", "Dictation"],
                                     ["eve", "Eve (live and panel)"], ["wallpapers", "Wallpaper picker"], ["widgets", "Widgets edit"]]
    readonly property var toolDefaults: ({ calculator: true, clipboard: true, capture: true, dictation: true, eve: false, wallpapers: false, widgets: false })
    property var tools: Object.assign({}, toolDefaults)
    property bool saving: false
    // Edit: the theme being changed ("" for a new one); load() fills the steps from it
    property string editId: ""
    function reset() {
        editId = ""; step = 1; name = ""; error = ""; query = "";
        caps = { widgets: true, wallpaper: true, bar: true, surface: true, windows: false, monitors: false, cursor: false, gtk: false, icons: false, qt: false };
        limit = false; apps = []; duration = 0; days = []; time = "19:00"; lockout = false; tools = Object.assign({}, toolDefaults);
        nameField.text = ""; appSearch.text = ""; timeField.text = "";
    }
    function load(m) {
        reset();
        editId = m.id; name = m.name || "";
        caps = Object.assign({ widgets: false, wallpaper: false, bar: false, surface: false, windows: false, monitors: false, cursor: false, gtk: false, icons: false, qt: false }, m.captures || {});
        limit = !!m.limit; apps = (m.apps || []).map(a => ({ name: a.name || a.class, class: a.class, id: a.id || "", exe: a.exe || "", command: a.command, icon: "" }));
        duration = m.duration || 0; days = m.days || []; time = m.time || "19:00"; lockout = !!m.lockout;
        tools = Object.assign({}, toolDefaults, m.tools || {});
        nameField.text = name;
    }
    property string error: ""

    readonly property var capLabels: [["widgets", "Widget layout"], ["wallpaper", "Wallpaper and accent"], ["bar", "Bar layout"],
                                      ["windows", "Open apps and window layout"], ["surface", "Dark or glass"], ["monitors", "Monitor arrangement"],
                                      ["cursor", "Mouse cursor"], ["gtk", "GTK app theme"], ["icons", "Icon theme"], ["qt", "Qt app style"]]
    readonly property var durations: [[15, "15 min"], [30, "30 min"], [60, "1 hour"], [120, "2 hours"], [0, "No limit"]]
    readonly property var dayNames: [["S", "Sun"], ["M", "Mon"], ["T", "Tue"], ["W", "Wed"], ["T", "Thu"], ["F", "Fri"], ["S", "Sat"]]
    readonly property var titles: ["", "Name it", "Apps", "Time and limits", "Review"]

    function toggled(map, k) { const o = Object.assign({}, map); o[k] = !o[k]; return o; }
    function hasApp(cls) { return apps.some(a => a.class === cls); }
    function entryApp(e) {
        if (!e) return null;
        // without desktop-entry placeholders (%u, Flatpak's @@ file forwarding)
        const cmd = (e.command || []).filter(a => !/^(%[a-zA-Z]|@@u?|--file-forwarding)$/.test(a)).map(a => /[\s"']/.test(a) ? "'" + a.replace(/'/g, "'\\''") + "'" : a).join(" ");
        return { name: e.name, class: e.startupClass || e.id.replace(/\.desktop$/, ""), id: e.id.replace(/\.desktop$/, ""),
                 exe: ((e.command || [])[0] || ""), command: cmd, icon: e.icon };
    }
    function toggleApp(a) { apps = hasApp(a.class) ? apps.filter(x => x.class !== a.class) : apps.concat([a]); }
    // "7:00 PM", "19:00", "7pm" -> "19:00"
    function parseTime(t) {
        const m = t.trim().toLowerCase().match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/);
        if (!m) return "";
        let h = parseInt(m[1]), mi = parseInt(m[2] || "0");
        if (m[3] === "pm" && h < 12) h += 12;
        if (m[3] === "am" && h === 12) h = 0;
        return h < 24 && mi < 60 ? String(h).padStart(2, "0") + ":" + String(mi).padStart(2, "0") : "";
    }
    function niceTime(hm) { const [h, m] = hm.split(":").map(Number); return (h % 12 || 12) + ":" + String(m).padStart(2, "0") + (h < 12 ? " AM" : " PM"); }
    readonly property string dayText: {
        const d = days.slice().sort();
        if (!d.length) return "";
        if (d.length === 7) return "every day";
        if (d.join() === "1,2,3,4,5") return "weekdays";
        if (d.join() === "0,6") return "weekends";
        return d.map(i => dayNames[i][1]).join(", ");
    }
    readonly property string summary: (limit ? "Only " + (apps.map(a => a.name).join(", ") || "no apps") : "All apps allowed") + ". "
        + (duration ? durations.find(x => x[0] === duration)[1] : "No timer")
        + (days.length ? ", " + dayText + " at " + niceTime(time) : "") + "."
        + (lockout && duration ? " Locked in until time is up." : "")

    // apps to offer: what's open now, then what you add by searching
    readonly property var openApps: {
        const out = [], seen = {};
        for (const t of Hyprland.toplevels.values) {
            const cls = t.lastIpcObject && t.lastIpcObject.class ? t.lastIpcObject.class : "";
            if (!cls || seen[cls] || cls === "org.quickshell") continue;
            seen[cls] = true;
            const a = entryApp(DesktopEntries.heuristicLookup(cls));
            out.push(a ? Object.assign(a, { class: cls }) : { name: cls, class: cls, command: cls.toLowerCase(), icon: "" });
        }
        return out;
    }
    property string query: ""
    readonly property var found: query.trim().length < 2 ? [] : DesktopEntries.applications.values
        .filter(e => !e.noDisplay && e.name.toLowerCase().indexOf(query.trim().toLowerCase()) >= 0)
        .slice(0, 6).map(e => entryApp(e))
    readonly property var chips: openApps.concat(apps.filter(a => !openApps.some(o => o.class === a.class)))

    // suggestions from the theme's name: its words map to app categories (freedesktop
    // Categories) in ~/.config/Tide/app-suggestions.json (editable), matched against
    // each installed app's Categories and Keywords
    property var topics: ({})
    FileView {
        path: Quickshell.env("HOME") + "/.config/Tide/app-suggestions.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { wz.topics = JSON.parse(text()); } catch (e) { wz.topics = {}; } }
    }
    readonly property var suggested: {
        const words = name.toLowerCase().split(/[^a-z0-9]+/).filter(w => w.length > 1);
        if (!words.length) return [];
        const cats = [].concat(...words.map(w => Array.isArray(topics[w]) ? topics[w] : []));
        const scored = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue;
            // viewers only when the name asks for them (reading, study)
            if ((e.categories || []).indexOf("Viewer") >= 0 && cats.indexOf("Viewer") < 0) continue;
            let s = 0;
            for (const c of e.categories || []) if (cats.indexOf(c) >= 0) s += 3 - Math.min(2, cats.indexOf(c) % 4);
            const text = (e.keywords || []).concat([e.name, e.genericName]).join(" ").toLowerCase();
            for (const w of words) if (w.length > 2 && text.indexOf(w) >= 0) s += 2;
            if (s > 0) scored.push([s, e]);
        }
        return scored.sort((a, b) => b[0] - a[0] || a[1].name.localeCompare(b[1].name)).slice(0, 8)
            .map(x => entryApp(x[1])).filter(a => !chips.some(c => c.class === a.class || c.name === a.name));
    }

    function next() {
        if (step === 1 && !name.trim()) { error = "Give it a name"; return; }
        // the typed time counts even without Enter
        if (step === 3 && timeField.text.trim()) {
            const typed = parseTime(timeField.text);
            if (!typed) { error = "That time doesn't look right (try 7:00 PM)"; return; }
            time = typed;
        }
        error = "";
        if (step < 4) { step++; return; }
        saving = true;
        saver.running = true;
    }
    Process {
        id: saver
        stdinEnabled: true
        command: [Quickshell.env("HOME") + "/.config/Tide/bin/tide-mode", "save"]
        onStarted: {
            write(JSON.stringify({
                id: wz.editId, name: wz.name.trim(), description: wz.summary, captures: wz.caps,
                art: [Theme.accent.toString(), Qt.darker(Theme.accent, 3.2).toString()],
                limit: wz.limit, apps: wz.apps, tools: wz.tools, duration: wz.duration,
                days: wz.days, time: wz.days.length ? wz.time : "", lockout: wz.lockout && wz.duration > 0
            }) + "\n");
            stdinEnabled = false;
        }
        onExited: code => {
            wz.saving = false;
            if (code === 0) { Modes.refresh(); wz.closed(); }
            else wz.error = code === 2 ? "It's locked in until time is up" : "Couldn't save the theme";
        }
    }

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + Theme.s(48)
    radius: Theme.s(22)
    color: Theme.tile
    border.width: 1; border.color: Theme.white(0.08)

    // a chip that turns on and off
    component WChip: HoverButton {
        id: ch
        property string label
        property bool on: false
        implicitWidth: chipRow.implicitWidth + Theme.s(26); implicitHeight: Theme.s(34); radius: Theme.s(10)
        hoverFill: false
        color: on ? Theme.accentSoft : Theme.white(hovered ? 0.1 : 0.07)
        border.width: on ? 1 : 0; border.color: Theme.accentLine
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Theme.s(8)
            Icon { visible: ch.on; anchors.verticalCenter: parent.verticalCenter; path: "M5 12 L10 17 L19 7"; size: Theme.s(14); stroke: 2.2; color: Theme.accent }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ch.label; color: ch.on ? Theme.text : Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12.5) }
        }
    }
    component WSwitch: HoverButton {
        id: sw
        property string label
        property string sub: ""
        property bool on: false
        Layout.fillWidth: true
        implicitHeight: Math.max(Theme.s(56), swText.implicitHeight + Theme.s(20)); radius: Theme.s(12)
        hoverFill: false
        color: Theme.white(hovered ? 0.07 : 0.05)
        Column {
            id: swText
            anchors.left: parent.left; anchors.leftMargin: Theme.s(14)
            anchors.right: tog.left; anchors.rightMargin: Theme.s(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s(2)
            Text { width: parent.width; wrapMode: Text.WordWrap; text: sw.label; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
            Text { visible: sw.sub !== ""; width: parent.width; wrapMode: Text.WordWrap; text: sw.sub; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
        }
        SToggle { id: tog; anchors.right: parent.right; anchors.rightMargin: Theme.s(14); anchors.verticalCenter: parent.verticalCenter; on: sw.on; onToggled: sw.clicked(null) }
    }

    ColumnLayout {
        id: col
        x: Theme.s(24); y: Theme.s(24)
        width: parent.width - Theme.s(48)
        spacing: Theme.s(18)

        // header: step, title, cancel; four progress bars
        RowLayout {
            Layout.fillWidth: true
            Column {
                Layout.fillWidth: true
                spacing: Theme.s(3)
                Text { text: (wz.editId ? "Editing · " : "") + "Step " + wz.step + " of 4"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                Text { text: wz.titles[wz.step]; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(18); font.weight: Font.Bold }
            }
            HoverButton {
                implicitWidth: Theme.s(32); implicitHeight: Theme.s(32); radius: Theme.s(16)
                onClicked: wz.closed()
                Icon { anchors.centerIn: parent; path: "M6 6 L18 18 M18 6 L6 18"; color: Theme.text2 }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.s(6)
            Repeater {
                model: 4
                delegate: Rectangle { required property int index; Layout.fillWidth: true; implicitHeight: Theme.s(4); radius: Theme.s(2); color: index < wz.step ? Theme.accent : Theme.white(0.12) }
            }
        }

        // 1: name it, and what to keep
        ColumnLayout {
            visible: wz.step === 1
            Layout.fillWidth: true
            spacing: Theme.s(10)
            Text { text: "Name"; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            SField {
                id: nameField
                Layout.fillWidth: true
                implicitHeight: Theme.s(40)
                hint: "Drawing practice"
                onEdited: v => wz.name = v
            }
            Text { Layout.topMargin: Theme.s(6); text: wz.editId ? "Kept from when you saved it (newly ticked parts come from your current setup)" : "Saved from your current setup"; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                uniformCellWidths: true
                columnSpacing: Theme.s(6); rowSpacing: Theme.s(6)
                Repeater {
                    model: wz.capLabels
                    delegate: WChip {
                        required property var modelData
                        Layout.fillWidth: true
                        label: modelData[1]
                        on: !!wz.caps[modelData[0]]
                        onClicked: wz.caps = wz.toggled(wz.caps, modelData[0])
                    }
                }
            }
        }

        // 2: apps
        ColumnLayout {
            visible: wz.step === 2
            Layout.fillWidth: true
            spacing: Theme.s(12)
            WSwitch { label: "Only allow these apps while this theme is on"; sub: "Other apps are set aside (not closed) until the theme ends"; on: wz.limit; onClicked: wz.limit = !wz.limit }
            // apps that fit the name ("Drawing" → Krita, GIMP…)
            Text { visible: wz.suggested.length > 0; text: "Suggested for " + wz.name.trim(); color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            Flow {
                visible: wz.suggested.length > 0
                Layout.fillWidth: true
                spacing: Theme.s(6)
                Repeater {
                    model: wz.suggested
                    delegate: WChip {
                        required property var modelData
                        label: "+ " + modelData.name
                        on: wz.hasApp(modelData.class)
                        onClicked: wz.toggleApp(modelData)
                    }
                }
            }
            Text { visible: wz.suggested.length > 0; text: "Open now"; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.s(6)
                Repeater {
                    model: wz.chips
                    delegate: WChip {
                        required property var modelData
                        label: modelData.name
                        on: wz.hasApp(modelData.class)
                        onClicked: wz.toggleApp(modelData)
                    }
                }
            }
            SField {
                id: appSearch
                Layout.fillWidth: true
                hint: "Add another app: type its name"
                onEdited: v => wz.query = v
            }
            Flow {
                visible: wz.found.length > 0
                Layout.fillWidth: true
                spacing: Theme.s(6)
                Repeater {
                    model: wz.found
                    delegate: WChip {
                        required property var modelData
                        label: "+ " + modelData.name
                        on: wz.hasApp(modelData.class)
                        onClicked: { wz.toggleApp(modelData); appSearch.text = ""; }
                    }
                }
            }
            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Selected apps also open automatically when the theme starts."; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            // Tide's own tools (only matters when the apps are limited)
            Text { visible: wz.limit; Layout.topMargin: Theme.s(6); text: "Tide tools allowed during this mode"; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            Flow {
                visible: wz.limit
                Layout.fillWidth: true
                spacing: Theme.s(6)
                Repeater {
                    model: wz.toolList
                    delegate: WChip {
                        required property var modelData
                        label: modelData[1]
                        on: !!wz.tools[modelData[0]]
                        onClicked: wz.tools = wz.toggled(wz.tools, modelData[0])
                    }
                }
            }
        }

        // 3: time and limits
        ColumnLayout {
            visible: wz.step === 3
            Layout.fillWidth: true
            spacing: Theme.s(14)
            Text { text: "How long"; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            SSegment {
                options: wz.durations.map(d => ({ label: d[1], value: d[0] }))
                value: wz.duration
                onPicked: v => { wz.duration = v; if (!v) wz.lockout = false; }
            }
            Text { text: "Repeat on"; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            RowLayout {
                spacing: Theme.s(6)
                Repeater {
                    model: 7
                    delegate: HoverButton {
                        required property int index
                        readonly property bool on: wz.days.indexOf(index) >= 0
                        implicitWidth: Theme.s(34); implicitHeight: Theme.s(34); radius: Theme.s(17)
                        hoverFill: false
                        color: on ? Theme.accent : Theme.white(hovered ? 0.1 : 0.07)
                        onClicked: wz.days = on ? wz.days.filter(d => d !== index) : wz.days.concat([index])
                        Text { anchors.centerIn: parent; text: wz.dayNames[index][0]; color: parent.on ? Theme.ink : Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium }
                    }
                }
                Text { Layout.leftMargin: Theme.s(8); text: "at"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                SField {
                    id: timeField
                    implicitWidth: Theme.s(110)
                    hint: wz.niceTime(wz.time)
                    onDone: v => { const t = wz.parseTime(v); if (t) wz.time = t; }
                }
            }
            WSwitch {
                label: "Lock me in until time is up"
                sub: wz.duration ? "Emergency exit: hold Mod + Esc for 5 seconds" : "Pick how long first"
                on: wz.lockout && wz.duration > 0
                opacity: wz.duration ? 1 : 0.5
                onClicked: if (wz.duration) wz.lockout = !wz.lockout
            }
        }

        // 4: review
        ColumnLayout {
            visible: wz.step === 4
            Layout.fillWidth: true
            spacing: Theme.s(12)
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s(14)
                Rectangle {
                    implicitWidth: Theme.s(120); implicitHeight: Theme.s(76); radius: Theme.s(11)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.accent }
                        GradientStop { position: 1; color: Qt.darker(Theme.accent, 3.2) }
                    }
                }
                Column {
                    Layout.fillWidth: true
                    spacing: Theme.s(4)
                    Text { text: wz.name.trim() || "New theme"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
                    Text { width: parent.width; wrapMode: Text.WordWrap; text: wz.summary; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: "Keeps: " + wz.capLabels.filter(c => wz.caps[c[0]]).map(c => c[1].toLowerCase()).join(", ")
                        color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Shortcut"; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                Kbd {
                    readonly property int at: wz.editId ? Modes.list.findIndex(m => m.id === wz.editId) : Modes.list.length
                    text: at < 9 ? "Mod + Ctrl + " + (at + 1) : "Mod + T"
                }
            }
        }

        Text { visible: wz.error !== ""; text: wz.error; color: Theme.red; font.family: Theme.sans; font.pixelSize: Theme.s(12) }

        // back / next
        RowLayout {
            Layout.fillWidth: true
            HoverButton {
                visible: wz.step > 1
                implicitWidth: bk.implicitWidth + Theme.s(32); implicitHeight: Theme.s(40); radius: Theme.s(12)
                hoverFill: false
                color: Theme.white(hovered ? 0.14 : 0.08)
                onClicked: { wz.error = ""; wz.step--; }
                Text { id: bk; anchors.centerIn: parent; text: "Back"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
            }
            Item { Layout.fillWidth: true }
            HoverButton {
                implicitWidth: nx.implicitWidth + Theme.s(36); implicitHeight: Theme.s(40); radius: Theme.s(12)
                hoverFill: false
                enabled: !wz.saving
                color: hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
                onClicked: wz.next()
                Text { id: nx; anchors.centerIn: parent; text: wz.saving ? "Saving…" : wz.step === 4 ? "Save theme" : "Next"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold }
            }
        }
    }
}
