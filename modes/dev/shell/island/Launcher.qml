import QtQuick
import "../components/Icons.js" as Icons
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"
import "MathEval.js" as M

// Island launcher (620x640): search, inline math, apps, modes and quick tools.
// Typing an expression shows the result at the top; Enter copies it.
Item {
    id: lr
    // the live mode's row, named after the assistant (ai.json; "AI" without one)
    readonly property string talkTitle: "Talk to " + EveData.assistantName
    signal closeRequested()
    property string query: ""
    property int sel: 0
    // "Show all apps": every installed app, A to Z, instead of recent apps and quick
    // tools (search still works in it); back to the usual view on Escape or when closed
    property bool allApps: false

    readonly property string q: query.trim()
    readonly property var mathV: M.looksLikeMath(q) ? M.evalMath(q) : null
    readonly property bool hasMath: mathV !== null

    // ---------- data ----------
    function glyph(e) {
        const c = e.categories || [];
        const has = x => c.indexOf(x) >= 0;
        if (has("WebBrowser")) return Icons.browser;
        if (has("TerminalEmulator")) return Icons.term;
        if (has("Engineering") && has("3DGraphics")) return Icons.printer;
        if (has("3DGraphics")) return Icons.cube;
        if (has("Game")) return Icons.game;
        if (has("Recorder")) return Icons.obs;
        if (has("RasterGraphics") || has("2DGraphics") || has("Graphics")) return Icons.brush;
        if (has("Video") || has("Player")) return Icons.film;
        return Icons.app;
    }
    function subtitle(e) {
        const c = e.categories || [];
        const has = x => c.indexOf(x) >= 0;
        if (has("WebBrowser")) return "Browser";
        if (has("TerminalEmulator")) return "Terminal";
        if (has("Engineering") && has("3DGraphics")) return "3D printing";
        if (has("3DGraphics")) return "3D modeling";
        if (has("Game")) return "Games";
        if (has("Recorder")) return "Recording";
        if (has("RasterGraphics") || has("2DGraphics")) return "Drawing";
        if (has("FileManager")) return "File manager";
        return e.genericName || e.comment || "App";
    }
    function appRow(e) {
        return { title: e.name, sub: subtitle(e), icon: glyph(e), key: "", tool: false,
                 act: () => { RecentApps.add(e.id); e.execute(); lr.closeRequested(); } };
    }
    function toolRow(title, sub, icon, key, mode) {
        return { title: title, sub: sub, icon: icon, key: key, tool: true,
                 // Eve starts a conversation (and the preview loop until she's wired)
                 act: () => mode === "eve" ? Eve.start(true) : IslandState.open(mode, IslandState.screenName) };
    }

    // during a mode with "Only allow these apps", only those apps (and the Tide tools
    // it allows) are listed; themes and the game library wait until it ends
    readonly property bool limited: Session.active && !!Session.s.limit
    readonly property var entries: DesktopEntries.applications.values
        .filter(e => !e.noDisplay && Session.allowedEntry(e))
        .slice().sort((a, b) => a.name.localeCompare(b.name))

    readonly property var tools: [
        toolRow("Calculator", "Quick math in the island", Icons.calc, "Mod+C", "calculator"),
        toolRow("Clipboard history", "Everything you copied", Icons.clip, "Mod+V", "clipboard"),
        toolRow("Resource center", "GPU, CPU, memory, disk, network and processes", Icons.gauge, "Ctrl+Shift+Esc", "resources"),
        toolRow("Free up space", "Old packages, caches, Trash and logs", Icons.trash, "Mod+Del", "cleanup"),
        toolRow("Power menu", "Lock, suspend, log out, restart, shut down", Icons.power, "Mod+Esc", "power"),
        toolRow("Switch theme", Modes.list.map(m => m.name).join(", "), Icons.themes, "Mod+T", "themes"),
        toolRow(talkTitle, "Live mode: listening, thinking, working, speaking", Icons.eve, "Mod+Alt+E", "eve")
    ].filter(r => (Theme.aiEnabled || r.title !== talkTitle)
                && Session.toolAllowed(({ "Calculator": "calculator", "Clipboard history": "clipboard", [talkTitle]: "eve" })[r.title] || "-")
                && !(r.title === "Switch theme" && Session.locked))
    readonly property var modes: (Session.locked || limited ? [] : Modes.list).map(m => ({
        title: m.name, sub: m.active ? m.description + " · active" : m.description, icon: Icons.themes, key: "", tool: false,
        act: () => { lr.closeRequested(); Modes.apply(m.id); }
    })).concat(limited ? [] : [
        { title: "Gaming library", sub: "Steam, emulators and more", icon: Icons.game, key: "Mod+G", tool: false, act: () => { lr.closeRequested(); Games.open = true; Games.refresh(); } },
    ])

    readonly property var sections: {
        if (allApps) {
            const ql = q.toLowerCase();
            const all = entries.map(appRow).filter(r => !ql || r.title.toLowerCase().indexOf(ql) >= 0 || r.sub.toLowerCase().indexOf(ql) >= 0);
            return [{ title: (ql ? "Apps matching \"" + q + "\"" : "All apps") + " · " + all.length, items: all }];
        }
        if (!q) {
            const byId = {};
            for (const e of entries) byId[e.id] = e;
            let recent = RecentApps.ids.map(id => byId[id]).filter(e => e !== undefined);
            if (recent.length < 4) recent = recent.concat(entries.filter(e => recent.indexOf(e) < 0));
            const showAll = { title: "Show all apps", sub: entries.length + " installed, A to Z", icon: Icons.grid, key: "", tool: false,
                              act: () => { lr.allApps = true; lr.sel = 0; results.contentY = 0; } };
            return [{ title: "Recent apps", items: recent.slice(0, 4).map(appRow).concat([showAll]) },
                    { title: "Quick tools", items: tools }];
        }
        const ql = q.toLowerCase();
        const hit = r => r.title.toLowerCase().indexOf(ql) >= 0 || r.sub.toLowerCase().indexOf(ql) >= 0;
        const a = entries.map(appRow).filter(hit);
        const m = modes.filter(hit);
        const t = tools.filter(hit);
        const out = [];
        if (a.length) out.push({ title: "Apps", items: a.slice(0, 5) });
        if (m.length) out.push({ title: "Modes", items: m });
        if (t.length) out.push({ title: "Quick tools", items: t });
        return out;
    }
    // flat list for the view: headers and rows; rows carry their index for keyboard selection
    readonly property var flat: {
        const out = [];
        let n = 0;
        for (const s of sections) {
            out.push({ header: true, title: s.title });
            for (const it of s.items) out.push(Object.assign({ header: false, row: n++ }, it));
        }
        return out;
    }
    readonly property int rowCount: flat.filter(x => !x.header).length

    function activate() {
        if (hasMath) {
            Quickshell.execDetached(["wl-copy", M.plain(mathV)]);
            closeRequested();
            return;
        }
        const r = flat.find(x => !x.header && x.row === sel);
        if (r) r.act();
    }

    function reset() {
        allApps = false;
        input.text = "";
        sel = 0;
        input.forceActiveFocus();
    }

    // ---------- view ----------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.s(14)
        spacing: Theme.s(10)

        // settings button, then the search field
        RowLayout {
          Layout.fillWidth: true
          spacing: Theme.s(8)
          HoverButton {
            Layout.preferredWidth: Theme.s(46)
            Layout.preferredHeight: Theme.s(46)
            radius: Theme.s(14)
            hoverFill: false
            color: hovered ? Theme.white(0.12) : Theme.white(0.07)
            onClicked: { lr.closeRequested(); IslandState.openSettings(""); }
            Icon { anchors.centerIn: parent; path: Icons.sliders; size: Theme.s(18); color: Theme.text2 }
          }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.s(46)
            radius: Theme.s(14)
            color: Theme.white(0.07)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.s(14)
                anchors.rightMargin: Theme.s(14)
                spacing: Theme.s(10)

                Icon { path: Icons.search; size: Theme.s(18); color: Theme.muted }
                TextInput {
                    id: input
                    Layout.fillWidth: true
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: Theme.s(15)
                    clip: true
                    selectByMouse: true
                    selectionColor: Theme.white(0.2)
                    onTextChanged: { lr.query = text; lr.sel = 0; results.contentY = 0; }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) { if (lr.allApps) { lr.allApps = false; input.text = ""; lr.sel = 0; } else lr.closeRequested(); event.accepted = true; }
                        else if (event.key === Qt.Key_Down) { lr.sel = Math.min(lr.rowCount - 1, lr.sel + 1); event.accepted = true; }
                        else if (event.key === Qt.Key_Up) { lr.sel = Math.max(0, lr.sel - 1); event.accepted = true; }
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { lr.activate(); event.accepted = true; }
                    }
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Search apps, or type math like 48*12"
                        color: Theme.dim
                        font: input.font
                        visible: input.text === ""
                    }
                }
                HoverButton {
                    Layout.preferredWidth: Theme.s(28)
                    Layout.preferredHeight: Theme.s(28)
                    onClicked: lr.closeRequested()
                    Icon { anchors.centerIn: parent; path: Icons.close; color: Theme.muted }
                }
            }
        }
        }

        // inline math result
        Rectangle {
            visible: lr.hasMath
            Layout.fillWidth: true
            Layout.preferredHeight: mathRow.implicitHeight + Theme.s(28)
            radius: Theme.s(14)
            color: Theme.accentSoft
            border.width: 1
            border.color: Theme.accentLine

            RowLayout {
                id: mathRow
                anchors.fill: parent
                anchors.leftMargin: Theme.s(16)
                anchors.rightMargin: Theme.s(16)
                spacing: Theme.s(14)

                Icon { path: Icons.calcCard; size: Theme.s(20); color: Theme.accent }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.s(2)
                    Text {
                        text: "= " + (lr.hasMath ? M.fmt(lr.mathV) : "")
                        color: Theme.text
                        font.family: Theme.mono
                        font.pixelSize: Theme.s(22)
                        font.weight: Font.Medium
                    }
                    Text { text: "Enter copies the result"; color: Theme.muted; font.family: Theme.sans; font.pointSize: Theme.sf(11.5 * 0.75) }
                }
                HoverButton {
                    Layout.preferredHeight: Theme.s(30)
                    Layout.preferredWidth: openCalc.implicitWidth + Theme.s(24)
                    radius: Theme.s(9)
                    hoverFill: false
                    color: Theme.white(hovered ? 0.16 : 0.08)
                    onClicked: IslandState.openCalculator(lr.q)
                    Text { id: openCalc; anchors.centerIn: parent; text: "Open calculator"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                }
            }
        }

        // results (scrolls when there are more than fit: all apps)
        Flickable {
            id: results
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: resultsCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            WheelScroll {}
            // the keyboard's row stays in view
            function show(item) {
                const y = item.mapToItem(resultsCol, 0, 0).y;
                if (y < contentY) contentY = y;
                else if (y + item.height > contentY + height) contentY = y + item.height - height;
            }

            Column {
                id: resultsCol
                width: parent.width
                spacing: Theme.s(2)

                Repeater {
                    model: lr.flat
                    delegate: Item {
                        id: entry
                        required property var modelData
                        width: parent.width
                        height: modelData.header ? head.implicitHeight : Theme.s(44)
                        readonly property bool current: !modelData.header && modelData.row === lr.sel
                        onCurrentChanged: if (current) results.show(entry)

                        Text {
                            id: head
                            visible: entry.modelData.header
                            text: entry.modelData.header ? entry.modelData.title : ""
                            color: Theme.dim
                            font.family: Theme.sans
                            font.pixelSize: Theme.s(11)
                            leftPadding: Theme.s(10); rightPadding: Theme.s(10); topPadding: Theme.s(8); bottomPadding: Theme.s(4)
                        }

                        HoverButton {
                            visible: !entry.modelData.header
                            anchors.fill: parent
                            radius: Theme.s(11)
                            hoverFill: false
                            color: hovered || (!lr.hasMath && entry.modelData.row === lr.sel) ? Theme.white(0.08) : "transparent"
                            onClicked: { if (!entry.modelData.header) entry.modelData.act(); }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.s(10)
                                anchors.rightMargin: Theme.s(10)
                                spacing: Theme.s(12)

                                Rectangle {
                                    Layout.preferredWidth: Theme.s(30)
                                    Layout.preferredHeight: Theme.s(30)
                                    radius: Theme.s(9)
                                    color: entry.modelData.tool ? Theme.accentSoft : Theme.white(0.08)
                                    Icon {
                                        anchors.centerIn: parent
                                        path: entry.modelData.icon || ""
                                        color: entry.modelData.tool ? Theme.accent : Theme.soft
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: entry.modelData.title || ""
                                        color: Theme.text
                                        font.family: Theme.sans
                                        font.pixelSize: Theme.s(13)
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: entry.modelData.sub || ""
                                        color: Theme.muted
                                        font.family: Theme.sans
                                        font.pixelSize: Theme.s(11)
                                    }
                                }
                                Text {
                                    text: entry.modelData.key || ""
                                    color: Theme.dim
                                    font.family: Theme.mono
                                    font.pixelSize: Theme.s(11)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
