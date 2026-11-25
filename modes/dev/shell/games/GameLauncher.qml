import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import ".."
import "../components"
import "../services"

// The game launcher (the design's "Game launcher" artboard), full screen on the main
// monitor while Games.open: the selected game's art behind everything, the library
// sidebar (search, Library and Platforms with counts), the selected game (platform,
// title, when you last played and for how long, Play / Resume, favourite, the "Pause
// local AI while playing" switch), and the shelf of covers. Keys: arrows move, Enter
// plays, typing searches, Esc clears the search, then closes.
PanelWindow {
    id: gl
    screen: Quickshell.screens.find(s => s.name === Theme.monitor) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "tide-games"
    color: "#050507"
    visible: !Games.picking && !IslandState.steppedAside

    // The design is a 1440 × 900 full-screen view: every size scales with the screen
    // (2.4× on a 4K monitor), so the launcher reads the same on any display.
    readonly property real k: Math.min(width / 1440, height / 900)
    function u(px) { return Math.round(px * k); }

    // ---- what's shown ----
    property string cat: "all"            // all | recent | fav | steam
    property string query: ""
    property int sel: 0
    // platforms: names and badges from games.py; icons from the design (a pad for the rest)
    readonly property var icons: ({ steam: "M12 3a9 9 0 100 18 9 9 0 000-18zM9 14l3 1.5M15 9a2 2 0 100 4 2 2 0 000-4z",
        switch: "M8 4h3v16H8a3 3 0 01-3-3V7a3 3 0 013-3zM13 4h3a3 3 0 013 3v10a3 3 0 01-3 3h-3zM8 8h0M16 15h0",
        gc: "M12 3l8 4.5v9L12 21l-8-4.5v-9z", ps2: "M4 7h16v10H4zM8 11h3M15 11h1", gba: "M5 8h14v8H5zM8 11v2M7 12h2M16 12h0" })
    function plat(k) {
        const p = Games.platformInfo[k] || { name: k, short: k.toUpperCase() };
        return { name: p.name, short: p.short, icon: icons[k] || "M6 10h4M8 8v4M15 11h.01M18 9h.01M7 6h10a4 4 0 014 4v4a4 4 0 01-4 4H7a4 4 0 01-4-4v-4a4 4 0 014-4z" };
    }
    // a game without art: the design's glow from colors picked by its title
    function glow(s) { let h = 0; for (const c of s) h = (h * 31 + c.charCodeAt(0)) >>> 0; return Qt.hsla((h % 360) / 360, 0.55, 0.55, 1); }
    readonly property var all: Games.games.slice().sort((a, b) => (b.installed !== false) - (a.installed !== false) || b.lastPlayed - a.lastPlayed || a.title.localeCompare(b.title))
    readonly property var shown: {
        let l = all;
        if (cat === "recent") l = l.filter(g => g.lastPlayed > 0).slice(0, 8);
        else if (cat === "installed") l = l.filter(g => g.installed !== false);
        else if (cat === "fav") l = l.filter(g => Games.isFav(g.id));
        else if (cat !== "all") l = l.filter(g => g.platform === cat);
        const q = query.trim().toLowerCase();
        return q ? l.filter(g => g.title.toLowerCase().indexOf(q) >= 0) : l;
    }
    readonly property var g: shown[Math.min(sel, shown.length - 1)] || null
    onShownChanged: if (sel >= shown.length) sel = Math.max(0, shown.length - 1)
    readonly property var titles: Object.assign({ all: "All games", installed: "Installed", recent: "Recently played", fav: "Favorites" },
        ...Object.keys(Games.platformInfo).map(k => ({ [k]: Games.platformInfo[k].name })))

    function ago(t) {
        if (!t) return "Never played";
        const days = Math.floor((Date.now() / 1000 - t) / 86400);
        const when = days <= 0 ? "today" : days === 1 ? "yesterday" : days < 7 ? days + " days ago" : days < 14 ? "last week"
            : days < 30 ? Math.floor(days / 7) + " weeks ago" : days < 60 ? "last month" : days < 365 ? Math.floor(days / 30) + " months ago"
            : days < 730 ? "1 year ago" : Math.floor(days / 365) + " years ago";
        return "Played " + when;
    }
    function meta(x) {
        if (!x) return "";
        if (Games.isRunning(x)) return "Running now";
        if (Games.downloading(x)) {
            const d = Games.installing[x.appid];
            return (d.state === "Downloading" ? "Downloading " : d.state + " ") + Math.round(d.percent) + "%" + (d.total ? " · " + Games.gb(d.done) + " of " + Games.gb(d.total) : "");
        }
        if (x.installed === false) return "Not installed" + (x.playtime ? " · " + ago(x.lastPlayed).toLowerCase() + " · " + Math.round(x.playtime / 60) + " h" : "");
        const h = x.playtime / 60;
        const time = !x.playtime ? "" : x.playtime < 60 ? x.playtime + " min" : (h >= 10 ? Math.round(h) : h.toFixed(1)) + " h";
        return ago(x.lastPlayed) + (time ? " · " + time : "");
    }
    readonly property var gameLauncher: gl       // handed to the emulator set-up
    function close() { Games.open = false; }
    property bool details: false             // the selected game's details (Uninstall)
    property bool confirmUninstall: false
    property string panel: ""             // "", "emulators", "edit": the emulator set-up (mouse and keyboard)
    function back() {
        if (Games.installAsk) Games.cancelAsk();
        else if (details) { details = false; confirmUninstall = false; }
        else if (Games.launching) Games.cancelLaunch();
        else if (panel) panel = panel === "edit" ? "emulators" : "";
        else if (query) query = "";
        else close();
    }
    // the controller can be in the sidebar (categories) or on the shelf
    property string zone: "shelf"
    // X: jump to the next first letter; the letter shows big for a moment
    property string jumpLetter: ""
    Timer { id: letterHide; interval: 900; onTriggered: gl.jumpLetter = "" }
    function jump() {
        if (!shown.length) return;
        const first = x => (x.title.match(/[A-Za-z0-9]/) || ["#"])[0].toUpperCase();
        const cur = g ? first(g) : "";
        let i = shown.findIndex((x, k) => k > sel && first(x) !== cur);
        if (i < 0) i = 0;
        sel = i; jumpLetter = first(shown[i]); letterHide.restart();
    }
    readonly property var cats: ["all", "installed", "recent", "fav"].concat(Object.keys(Games.platformInfo).filter(k => all.some(x => x.platform === k)))
    function move(word) {
        const cols = 6;
        if (zone === "side") {
            const i = cats.indexOf(cat);
            if (word === "up" || word === "down") { cat = cats[Math.max(0, Math.min(cats.length - 1, i + (word === "down" ? 1 : -1)))]; sel = 0; }
            else if (word === "right") zone = "shelf";
            return;
        }
        if (word === "right") sel = Math.min(shown.length - 1, sel + 1);
        else if (word === "left") { if (sel % cols === 0) zone = "side"; else sel = Math.max(0, sel - 1); }
        else if (word === "down") sel = Math.min(shown.length - 1, sel + cols);
        else if (word === "up") sel = Math.max(0, sel - cols);
    }
    Connections {
        target: Games
        function onPadPressed(word) {
            if (gl.panel) { if (word === "back") gl.back(); return; }   // set-up is mouse and keyboard
            if (["up", "down", "left", "right"].indexOf(word) >= 0) gl.move(word);
            else if (word === "ok" && gl.zone === "side") gl.zone = "shelf";
            else if (word === "ok" || word === "play") Games.launch(gl.g);
            else if (word === "back") { if (gl.zone === "side") gl.zone = "shelf"; else gl.back(); }
            else if (word === "fav" && gl.g) Games.toggleFav(gl.g.id);
            else if (word === "search") gl.jump();
            else if (word === "prev" || word === "next") {
                const i = gl.cats.indexOf(gl.cat), n = gl.cats.length;
                gl.cat = gl.cats[(i + (word === "next" ? 1 : n - 1)) % n]; gl.sel = 0;
            }
        }
    }

    // ---- keys ----
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Component.onCompleted: forceActiveFocus()
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) gl.back();
            else if (gl.panel) return;           // the set-up's own fields take the keys
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) Games.launch(gl.g);
            else if (e.key === Qt.Key_Right) gl.move("right");
            else if (e.key === Qt.Key_Left) gl.move("left");
            else if (e.key === Qt.Key_Down) gl.move("down");
            else if (e.key === Qt.Key_Up) gl.move("up");
            else if (e.key === Qt.Key_Backspace) gl.query = gl.query.slice(0, -1);
            else if (e.text && e.text.trim() && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) gl.query += e.text;
            else return;
            e.accepted = true;
        }
    }

    // ---- the selected game's art, behind everything ----
    Item {
        anchors.fill: parent
        opacity: 0
        NumberAnimation on opacity { to: 1; duration: Theme.reduceMotion ? 0 : Theme.durDrop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }

        // no art (emulator games): the design's glow in the game's own colors
        Rectangle {
            id: heroGlow
            anchors.fill: parent
            visible: heroArt.status !== Image.Ready
            readonly property color c: gl.g ? gl.glow(gl.g.title) : Theme.accent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(heroGlow.c.r * 0.55, heroGlow.c.g * 0.55, heroGlow.c.b * 0.55, 1) }
                GradientStop { position: 0.6; color: Qt.rgba(heroGlow.c.r * 0.15, heroGlow.c.g * 0.15, heroGlow.c.b * 0.15, 1) }
                GradientStop { position: 1; color: "#050507" }
            }
        }
        Image {
            id: heroArt
            anchors.fill: parent
            source: gl.g && gl.g.hero ? "file://" + gl.g.hero : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.durWallpaper } }
        }
        // the design's two fades: from the left (under the sidebar and text) and from the bottom (under the shelf)
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(5 / 255, 5 / 255, 7 / 255, 0.85) }
                GradientStop { position: 0.45; color: Qt.rgba(5 / 255, 5 / 255, 7 / 255, 0.35) }
                GradientStop { position: 1; color: Qt.rgba(5 / 255, 5 / 255, 7 / 255, 0.15) }
            }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.3; color: Qt.rgba(5 / 255, 5 / 255, 7 / 255, 0) }
                GradientStop { position: 0.55; color: Qt.rgba(5 / 255, 5 / 255, 7 / 255, 0.65) }
                GradientStop { position: 1; color: Qt.rgba(5 / 255, 5 / 255, 7 / 255, 0.95) }
            }
        }

        // ============ SIDEBAR ============
        Rectangle {
            id: side
            x: gl.u(16); y: gl.u(16)
            width: gl.u(248); height: parent.height - gl.u(32)
            radius: gl.u(24)
            color: Theme.surface === "glass" ? Qt.rgba(24 / 255, 24 / 255, 27 / 255, 0.72) : Theme.panelFill
            border.width: 1; border.color: Theme.white(Theme.surface === "glass" ? 0.14 : 0.07)
            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: gl.u(18); anchors.bottomMargin: gl.u(18)
                anchors.leftMargin: gl.u(12); anchors.rightMargin: gl.u(12)
                spacing: gl.u(4)
                Row {
                    Layout.leftMargin: gl.u(8); Layout.bottomMargin: gl.u(14)
                    spacing: gl.u(10)
                    Icon { anchors.verticalCenter: parent.verticalCenter; path: "M6 10h4M8 8v4M15 11h.01M18 9h.01M7 6h10a4 4 0 014 4v4a4 4 0 01-4 4H7a4 4 0 01-4-4v-4a4 4 0 014-4z"; size: gl.u(18); color: Theme.text }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Games"; color: Theme.text; font.family: Theme.sans; font.pixelSize: gl.u(16); font.weight: Font.Bold }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.leftMargin: gl.u(2); Layout.rightMargin: gl.u(2); Layout.bottomMargin: gl.u(10)
                    implicitHeight: gl.u(36); radius: gl.u(11)
                    color: Qt.rgba(0, 0, 0, 0.3); border.width: 1; border.color: gl.query ? Theme.accentLine : Theme.white(0.08)
                    Row {
                        anchors.left: parent.left; anchors.leftMargin: gl.u(12); anchors.verticalCenter: parent.verticalCenter
                        spacing: gl.u(8)
                        Icon { anchors.verticalCenter: parent.verticalCenter; path: "M11 4 A7 7 0 1 0 11.01 4 M16 16 L20 20"; size: gl.u(14); color: Theme.muted }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: gl.query || "Search games"; color: gl.query ? Theme.text : Theme.dim; font.family: Theme.sans; font.pixelSize: gl.u(12.5) }
                    }
                }
                Repeater {
                    model: [
                        { title: "Library", items: [
                            { key: "all", label: "All games", icon: "M5 5h6v6H5zM13 5h6v6h-6zM5 13h6v6H5zM13 13h6v6h-6z", count: gl.all.length },
                            { key: "installed", label: "Installed", icon: "M12 4v11M7 10l5 5 5-5M5 20h14", count: gl.all.filter(x => x.installed !== false).length },
                            { key: "recent", label: "Recently played", icon: "M12 4a8 8 0 100 16 8 8 0 000-16zM12 8v4l3 2", count: "" },
                            { key: "fav", label: "Favorites", icon: "M12 20s-7-4.4-7-10a4 4 0 017-2.6A4 4 0 0119 10c0 5.6-7 10-7 10z", count: gl.all.filter(x => Games.isFav(x.id)).length }] },
                        { title: "Platforms", items: Object.keys(Games.platformInfo).filter(k => gl.all.some(x => x.platform === k)).map(k => (
                            { key: k, label: gl.plat(k).name, icon: gl.plat(k).icon, count: gl.all.filter(x => x.platform === k).length })) }
                    ]
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: gl.u(4)
                        Text { Layout.leftMargin: gl.u(12); Layout.topMargin: gl.u(12); Layout.bottomMargin: gl.u(4); text: parent.modelData.title; color: "#7C7C82"; font.family: Theme.sans; font.pixelSize: gl.u(11) }
                        Repeater {
                            model: parent.modelData.items
                            delegate: HoverButton {
                                required property var modelData
                                readonly property bool on: gl.cat === modelData.key
                                Layout.fillWidth: true
                                implicitHeight: gl.u(38); radius: gl.u(11)
                                hoverFill: !on
                                color: on ? Theme.white(0.12) : hovered ? Theme.white(0.06) : "transparent"
                                border.width: on && gl.zone === "side" ? gl.u(2) : 0
                                border.color: Theme.accent
                                onClicked: { gl.cat = modelData.key; gl.sel = 0; }
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: gl.u(12); anchors.rightMargin: gl.u(12)
                                    spacing: gl.u(10)
                                    Icon { path: parent.parent.modelData.icon; size: gl.u(16); color: parent.parent.on ? Theme.text : Theme.soft }
                                    Text { Layout.fillWidth: true; text: parent.parent.modelData.label; color: parent.parent.on ? Theme.text : Theme.soft; font.family: Theme.sans; font.pixelSize: gl.u(13); font.weight: parent.parent.on ? Font.Medium : Font.Normal }
                                    Text { text: parent.parent.modelData.count; color: Theme.text; opacity: 0.7; font.family: Theme.mono; font.pixelSize: gl.u(11) }
                                }
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                // Steam apps that aren't games (Blender, Lossless Scaling…), hidden by default
                HoverButton {
                    visible: Games.appCount > 0
                    Layout.fillWidth: true
                    implicitHeight: gl.u(38); radius: gl.u(11)
                    onClicked: Games.setShowApps(!Games.showApps)
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: gl.u(12); anchors.rightMargin: gl.u(12)
                        spacing: gl.u(10)
                        Text { Layout.fillWidth: true; text: "Show non-game apps"; color: Theme.soft; font.family: Theme.sans; font.pixelSize: gl.u(12.5) }
                        Text { text: Games.appCount; color: Theme.text; opacity: 0.6; font.family: Theme.mono; font.pixelSize: gl.u(11) }
                        Rectangle {
                            implicitWidth: gl.u(30); implicitHeight: gl.u(18); radius: gl.u(9)
                            color: Games.showApps ? Theme.accent : Theme.white(0.18)
                            Rectangle { y: gl.u(2); x: Games.showApps ? parent.width - width - gl.u(2) : gl.u(2); width: gl.u(14); height: gl.u(14); radius: gl.u(7); color: Games.showApps ? Theme.ink : Theme.text }
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.white(0.08) }
                // emulators: both open the set-up
                Repeater {
                    model: [["Add a game or emulator", "M12 5v14M5 12h14"], ["Emulator settings", "M12 15a3 3 0 100-6 3 3 0 000 6zM19.4 15a1.7 1.7 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.7 1.7 0 00-1.8-.3 1.7 1.7 0 00-1 1.5V21a2 2 0 11-4 0v-.1a1.7 1.7 0 00-1.1-1.5 1.7 1.7 0 00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.7 1.7 0 00.3-1.8 1.7 1.7 0 00-1.5-1H3a2 2 0 110-4h.1A1.7 1.7 0 004.6 9a1.7 1.7 0 00-.3-1.8l-.1-.1a2 2 0 112.8-2.8l.1.1a1.7 1.7 0 001.8.3H9a1.7 1.7 0 001-1.5V3a2 2 0 114 0v.1a1.7 1.7 0 001 1.5 1.7 1.7 0 001.8-.3l.1-.1a2 2 0 112.8 2.8l-.1.1a1.7 1.7 0 00-.3 1.8V9a1.7 1.7 0 001.5 1H21a2 2 0 110 4h-.1a1.7 1.7 0 00-1.5 1z"]]
                    delegate: HoverButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: gl.u(38); radius: gl.u(11)
                        // Add: the set-up. Emulator settings: the selected game's emulator, opened
                        // normally (its settings live there); the set-up when there's none
                        onClicked: {
                            const e = gl.g && gl.g.emulator ? Games.emulatorOf(gl.g) : null;
                            if (modelData[0] === "Emulator settings" && e) Games.openEmulator(e);
                            else { gl.close(); IslandState.openSettings("games"); }    // Settings → Games: one place to add
                        }
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: gl.u(12); anchors.verticalCenter: parent.verticalCenter
                            spacing: gl.u(10)
                            Icon { anchors.verticalCenter: parent.verticalCenter; path: parent.parent.modelData[1]; size: gl.u(16); color: Theme.soft }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData[0]; color: Theme.soft; font.family: Theme.sans; font.pixelSize: gl.u(13) }
                        }
                    }
                }
            }
        }

        // close
        HoverButton {
            anchors.right: parent.right; anchors.rightMargin: gl.u(24)
            y: gl.u(22)
            width: gl.u(38); height: gl.u(38); radius: gl.u(19)
            hoverFill: false
            color: Qt.rgba(24 / 255, 24 / 255, 27 / 255, hovered ? 0.85 : 0.6)
            border.width: 1; border.color: Theme.white(0.14)
            onClicked: gl.close()
            Icon { anchors.centerIn: parent; path: "M6 6 L18 18 M18 6 L6 18"; size: gl.u(16); color: Theme.text }
        }

        // ============ HERO ============
        ColumnLayout {
            id: hero
            visible: gl.g !== null
            x: gl.u(304); y: gl.u(120)
            width: parent.width - x - gl.u(48)
            spacing: gl.u(14)
            Row {
                spacing: gl.u(8)
                Rectangle {
                    width: pRow.implicitWidth + gl.u(22); height: gl.u(26); radius: gl.u(13)
                    color: Theme.white(0.14)
                    Row {
                        id: pRow
                        anchors.centerIn: parent
                        spacing: gl.u(7)
                        Icon { anchors.verticalCenter: parent.verticalCenter; path: gl.g ? gl.plat(gl.g.platform).icon : ""; size: gl.u(14); color: Theme.text }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: gl.g ? gl.plat(gl.g.platform).name + (gl.g.emuName ? " · " + gl.g.emuName : "") : ""; color: Theme.text; font.family: Theme.sans; font.pixelSize: gl.u(12); font.weight: Font.Medium }
                    }
                }
                Rectangle {
                    visible: Games.isRunning(gl.g)
                    width: rRow.implicitWidth + gl.u(22); height: gl.u(26); radius: gl.u(13)
                    color: Theme.accent
                    Row {
                        id: rRow
                        anchors.centerIn: parent
                        spacing: gl.u(7)
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: gl.u(6); height: gl.u(6); radius: gl.u(3); color: Theme.ink }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Running"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: gl.u(12); font.weight: Font.DemiBold }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: gl.g ? gl.g.title : ""
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 1.02
                color: Theme.text; font.family: Theme.sans; font.pixelSize: gl.u(64); font.weight: Font.Bold; font.letterSpacing: -0.03 * gl.u(64)
                style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.25)
            }
            Text { text: gl.meta(gl.g); color: Theme.soft; font.family: Theme.sans; font.pixelSize: gl.u(14) }
            Rectangle {
                visible: Games.downloading(gl.g)
                Layout.preferredWidth: gl.u(420); implicitHeight: gl.u(6); radius: gl.u(3)
                color: Theme.white(0.15)
                Rectangle { width: parent.width * (Games.downloading(gl.g) ? Games.installing[gl.g.appid].percent / 100 : 0); height: parent.height; radius: parent.radius; color: Theme.accent; Behavior on width { NumberAnimation { duration: 400 } } }
            }
            Row {
                Layout.topMargin: gl.u(8)
                spacing: gl.u(10)
                HoverButton {
                    readonly property bool dl: Games.downloading(gl.g)
                    width: playRow.implicitWidth + gl.u(60); height: gl.u(52); radius: gl.u(26)
                    hoverFill: false
                    color: dl ? Theme.white(hovered ? 0.2 : 0.14) : hovered ? Qt.lighter(Theme.accent, 1.08) : Theme.accent
                    onClicked: dl ? Games.cancelInstall(gl.g) : Games.launch(gl.g)
                    Row {
                        id: playRow
                        anchors.centerIn: parent
                        spacing: gl.u(10)
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property bool inst: gl.g && gl.g.installed === false
                            path: Games.downloading(gl.g) ? "M6 6 L18 18 M18 6 L6 18" : inst ? "M12 4v11M7 10l5 5 5-5M5 20h14" : "M8 5 V19 L19 12 Z"
                            filled: !inst && !Games.downloading(gl.g); stroke: filled ? -1 : 2.2; size: gl.u(18)
                            color: Games.downloading(gl.g) ? Theme.text : Theme.ink
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Games.downloading(gl.g) ? "Cancel" : gl.g && gl.g.installed === false ? "Install" : Games.isRunning(gl.g) ? "Resume" : "Play"
                            color: Games.downloading(gl.g) ? Theme.text : Theme.ink; font.family: Theme.sans; font.pixelSize: gl.u(16); font.weight: Font.Bold
                        }
                    }
                }
                HoverButton {
                    readonly property bool fav: gl.g ? Games.isFav(gl.g.id) : false
                    width: gl.u(52); height: gl.u(52); radius: gl.u(26)
                    hoverFill: false
                    color: Qt.rgba(24 / 255, 24 / 255, 27 / 255, hovered ? 0.8 : 0.5)
                    border.width: 1; border.color: Theme.white(0.14)
                    onClicked: if (gl.g) Games.toggleFav(gl.g.id)
                    Icon { anchors.centerIn: parent; path: "M12 20s-7-4.4-7-10a4 4 0 017-2.6A4 4 0 0119 10c0 5.6-7 10-7 10z"; filled: parent.fav; size: gl.u(20); color: parent.fav ? Theme.accent : Theme.text }
                }
                HoverButton {
                    width: gl.u(52); height: gl.u(52); radius: gl.u(26)
                    hoverFill: false
                    color: Qt.rgba(24 / 255, 24 / 255, 27 / 255, hovered ? 0.8 : 0.5)
                    border.width: 1; border.color: Theme.white(0.14)
                    onClicked: gl.details = true
                    Icon { anchors.centerIn: parent; path: "M12 4a8 8 0 100 16 8 8 0 000-16zM12 11v5M12 8h.01"; size: gl.u(20); color: Theme.text }
                }
                // "Pause local AI while playing": a stub for now (EVE_WIRING.md); only with the AI features on
                HoverButton {
                    visible: Theme.aiEnabled
                    anchors.verticalCenter: parent.verticalCenter
                    width: aiRow.implicitWidth + gl.u(28); height: gl.u(40); radius: gl.u(20)
                    hoverFill: false
                    color: Qt.rgba(24 / 255, 24 / 255, 27 / 255, hovered ? 0.8 : 0.5)
                    border.width: 1; border.color: Theme.white(0.14)
                    onClicked: Games.setPauseAi(!Games.pauseAi)
                    Row {
                        id: aiRow
                        anchors.centerIn: parent
                        spacing: gl.u(10)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: gl.u(32); height: gl.u(20); radius: gl.u(10)
                            color: Games.pauseAi ? Theme.accent : Theme.white(0.18)
                            Rectangle {
                                y: gl.u(2); x: Games.pauseAi ? parent.width - width - gl.u(2) : gl.u(2)
                                width: gl.u(16); height: gl.u(16); radius: gl.u(8)
                                color: Games.pauseAi ? Theme.ink : Theme.text
                                Behavior on x { NumberAnimation { duration: Theme.durHover } }
                            }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Pause local AI while playing"; color: "#E5E5EA"; font.family: Theme.sans; font.pixelSize: gl.u(12.5) }
                    }
                }
            }
        }

        // ============ SHELF ============
        ColumnLayout {
            x: gl.u(304)
            y: Math.max(gl.u(470), hero.y + hero.implicitHeight + gl.u(40))
            width: parent.width - x - gl.u(32)
            height: parent.height - y - gl.u(16)
            spacing: gl.u(12)
            Row {
                spacing: gl.u(10)
                Text { text: gl.titles[gl.cat] || ""; color: Theme.text; font.family: Theme.sans; font.pixelSize: gl.u(16); font.weight: Font.DemiBold }
                Text { anchors.baseline: parent.children[0].baseline; text: gl.shown.length + (gl.shown.length === 1 ? " game" : " games") + (gl.query ? " · \"" + gl.query + "\"" : ""); color: Theme.muted; font.family: Theme.mono; font.pixelSize: gl.u(12) }
            }
            Text { visible: Games.steamNote !== ""; text: Games.steamNote; color: Theme.muted; font.family: Theme.sans; font.pixelSize: gl.u(12) }
            Text {
                visible: !Games.loading && gl.shown.length === 0
                text: gl.query ? "No games match \"" + gl.query + "\"" : gl.cat === "fav" ? "No favourites yet: the heart on a game adds it here" : "No games found. Installed Steam games show up here."
                color: Theme.soft; font.family: Theme.sans; font.pixelSize: gl.u(13)
            }
            GridView {
                id: shelf
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                topMargin: gl.u(8); leftMargin: gl.u(4)
                cellWidth: (width - gl.u(20)) / 6
                cellHeight: (cellWidth - gl.u(16)) * 4 / 3 + gl.u(44)
                model: gl.shown
                currentIndex: gl.sel
                boundsBehavior: Flickable.StopAtBounds
                WheelScroll {}
                delegate: Item {
                    id: cover
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === gl.sel
                    width: shelf.cellWidth; height: shelf.cellHeight
                    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { if (gl.sel === cover.index) Games.launch(cover.modelData); else gl.sel = cover.index; } }
                    Column {
                        x: 0; width: parent.width - gl.u(16)
                        y: hov.hovered || cover.selected ? -gl.u(4) : 0
                        Behavior on y { NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
                        spacing: gl.u(8)
                        Rectangle {
                            width: parent.width; height: width * 4 / 3; radius: gl.u(14)
                            color: "#18181B"
                            border.width: cover.selected ? gl.u(2.5) : 1
                            border.color: cover.selected ? (gl.zone === "side" ? Theme.white(0.5) : Theme.accent) : Theme.white(0.1)
                            ClippingRectangle {
                                anchors.fill: parent; anchors.margins: parent.border.width
                                radius: parent.radius - parent.border.width
                                color: "transparent"
                                Image {
                                    id: coverArt
                                    anchors.fill: parent
                                    // not installed: grey and dim (the design's owned-not-installed look)
                                    opacity: cover.modelData.installed === false && !Games.downloading(cover.modelData) ? 0.55 : 1
                                    layer.enabled: cover.modelData.installed === false
                                    layer.effect: MultiEffect { saturation: -1 }
                                    source: !cover.modelData.cover ? "" : cover.modelData.cover.startsWith("/") ? "file://" + cover.modelData.cover : cover.modelData.cover
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 400
                                }
                                // no art: the title on a card in the game's colors
                                Rectangle {
                                    id: noArt
                                    anchors.fill: parent
                                    visible: coverArt.status !== Image.Ready
                                    readonly property color c: gl.glow(cover.modelData.title)
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: Qt.rgba(noArt.c.r * 0.7, noArt.c.g * 0.7, noArt.c.b * 0.7, 1) }
                                        GradientStop { position: 1; color: "#08080A" }
                                    }
                                }
                                Text {
                                    visible: coverArt.status !== Image.Ready
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: gl.u(10)
                                    wrapMode: Text.WordWrap
                                    text: cover.modelData.title
                                    color: Theme.text; font.family: Theme.sans; font.pixelSize: gl.u(15); font.weight: Font.Bold
                                }
                                Rectangle {
                                    x: gl.u(8); y: gl.u(8)
                                    width: shortT.implicitWidth + gl.u(14); height: gl.u(20); radius: gl.u(10)
                                    color: Qt.rgba(0, 0, 0, 0.5)
                                    Text { id: shortT; anchors.centerIn: parent; text: gl.plat(cover.modelData.platform).short; color: Theme.text; font.family: Theme.sans; font.pixelSize: gl.u(10); font.weight: Font.DemiBold }
                                }
                                // downloading: progress along the bottom
                                Rectangle {
                                    visible: Games.downloading(cover.modelData)
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                    anchors.margins: gl.u(8)
                                    height: gl.u(5); radius: gl.u(3)
                                    color: Qt.rgba(0, 0, 0, 0.5)
                                    Rectangle { width: parent.width * (Games.downloading(cover.modelData) ? Games.installing[cover.modelData.appid].percent / 100 : 0); height: parent.height; radius: parent.radius; color: Theme.accent }
                                }
                                Rectangle {
                                    visible: cover.modelData.installed === false && !Games.downloading(cover.modelData)
                                    anchors.right: parent.right; anchors.rightMargin: gl.u(8); y: gl.u(8)
                                    width: instT.implicitWidth + gl.u(14); height: gl.u(20); radius: gl.u(10)
                                    color: Qt.rgba(0, 0, 0, 0.55)
                                    Text { id: instT; anchors.centerIn: parent; text: "Install"; color: Theme.text; font.family: Theme.sans; font.pixelSize: gl.u(10); font.weight: Font.DemiBold }
                                }
                                Rectangle {
                                    visible: Games.isRunning(cover.modelData)
                                    anchors.right: parent.right; anchors.rightMargin: gl.u(8); y: gl.u(8)
                                    width: resT.implicitWidth + gl.u(14); height: gl.u(20); radius: gl.u(10)
                                    color: Theme.accent
                                    Text { id: resT; anchors.centerIn: parent; text: "Resume"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: gl.u(10); font.weight: Font.Bold }
                                }
                            }
                        }
                        Text { width: parent.width; elide: Text.ElideRight; leftPadding: gl.u(2); text: cover.modelData.title; color: Theme.muted; font.family: Theme.sans; font.pixelSize: gl.u(11.5) }
                    }
                }
            }
        }

        // ============ LAUNCHING ============
        Rectangle {
            anchors.fill: parent
            visible: Games.launching !== null
            color: Qt.rgba(0, 0, 0, 0.55)
            MouseArea { anchors.fill: parent }
            Rectangle {
                id: launchCard
                anchors.centerIn: parent
                // as wide as the title needs (up to a limit; longer ones wrap to two lines)
                TextMetrics { id: launchTitleM; text: Games.launching ? Games.launching.title : ""; font.family: Theme.sans; font.pixelSize: gl.u(17); font.weight: Font.Bold }
                width: Math.min(gl.u(720), Math.max(gl.u(420), launchTitleM.advanceWidth + gl.u(52 + 56 + 14 + 8)))
                height: lc.implicitHeight + gl.u(52); radius: gl.u(26)
                color: Qt.rgba(24 / 255, 24 / 255, 27 / 255, 0.9)
                border.width: 1; border.color: Theme.white(0.14)
                ColumnLayout {
                    id: lc
                    x: gl.u(26); y: gl.u(26)
                    width: parent.width - gl.u(52)
                    spacing: gl.u(16)
                    Row {
                        spacing: gl.u(14)
                        ClippingRectangle {
                            width: gl.u(56); height: gl.u(74); radius: gl.u(10)
                            color: "#18181B"
                            Image { anchors.fill: parent; source: Games.launching && Games.launching.cover ? "file://" + Games.launching.cover : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 120 }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: gl.u(3)
                            Text { width: launchCard.width - gl.u(52 + 56 + 14); wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; text: Games.launching ? Games.launching.title : ""; color: Theme.text; font.family: Theme.sans; font.pixelSize: gl.u(17); font.weight: Font.Bold }
                            Text { text: Games.launching ? gl.plat(Games.launching.platform).name + (Games.launching.emuName ? " · " + Games.launching.emuName : "") : ""; color: Theme.soft; font.family: Theme.sans; font.pixelSize: gl.u(12) }
                        }
                    }
                    Repeater {
                        model: !Games.launching ? [] : Games.launching.platform === "steam"
                            ? ["Starting Steam in the background", "Checking for updates", "Launching " + Games.launching.title]
                            : Games.launching.platform === "lutris" ? ["Starting Lutris", "Getting the game ready", "Launching " + Games.launching.title]
                            : Games.launching.platform === "pc" ? ["Starting " + Games.launching.title, "Waiting for its window", "Ready"]
                            : ["Starting " + (Games.launching.emuName || "the emulator"), "Loading your save and controller profile", "Launching " + Games.launching.title]
                        delegate: Row {
                            required property var modelData
                            required property int index
                            readonly property bool done: index < Games.step
                            readonly property bool active: index === Games.step
                            spacing: gl.u(10)
                            Item {
                                width: gl.u(16); height: gl.u(16)
                                anchors.verticalCenter: parent.verticalCenter
                                Icon { visible: parent.parent.done; anchors.centerIn: parent; path: "M5 12 L10 17 L19 7"; size: gl.u(14); stroke: 2.4; color: Theme.accent }
                                Rectangle {
                                    visible: parent.parent.active
                                    anchors.centerIn: parent
                                    width: gl.u(14); height: gl.u(14); radius: gl.u(7)
                                    color: "transparent"
                                    border.width: gl.u(2); border.color: Theme.white(0.2)
                                    Rectangle { width: gl.u(5); height: gl.u(5); radius: gl.u(3); color: Theme.accent; x: (parent.width - width) / 2; y: -gl.u(1.5) }
                                    RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: parent.visible }
                                }
                                Rectangle { visible: !parent.parent.done && !parent.parent.active; anchors.centerIn: parent; width: gl.u(8); height: gl.u(8); radius: gl.u(4); color: Theme.white(0.2) }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, launchCard.width - gl.u(52 + 26))
                                elide: Text.ElideRight
                                text: parent.modelData
                                color: parent.done ? Theme.soft : parent.active ? Theme.text : Theme.muted
                                font.family: Theme.sans; font.pixelSize: gl.u(13)
                            }
                        }
                    }
                    Text { visible: Games.launchError !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: Games.launchError + " Esc to stop waiting."; color: Theme.soft; font.family: Theme.sans; font.pixelSize: gl.u(12) }
                }
            }
        }

        // ============ INSTALL (asks first: size and free space; licence agreements) ============
        Rectangle {
            anchors.fill: parent
            visible: Games.installAsk !== null
            color: Qt.rgba(0, 0, 0, 0.55)
            MouseArea { anchors.fill: parent; onClicked: Games.cancelAsk() }
            Rectangle {
                anchors.centerIn: parent
                width: gl.u(460); height: ic.implicitHeight + gl.u(52); radius: gl.u(26)
                color: Qt.rgba(24 / 255, 24 / 255, 27 / 255, 0.95)
                border.width: 1; border.color: Theme.white(0.14)
                MouseArea { anchors.fill: parent }
                readonly property var a: Games.installAsk || ({ game: {}, bytes: -1, free: -1, licences: [] })
                ColumnLayout {
                    id: ic
                    x: gl.u(26); y: gl.u(26)
                    width: parent.width - gl.u(52)
                    spacing: gl.u(14)
                    Row {
                        spacing: gl.u(14)
                        ClippingRectangle {
                            width: gl.u(56); height: gl.u(74); radius: gl.u(10)
                            color: "#18181B"
                            Image { anchors.fill: parent; source: parent.parent.parent.parent.a.game.cover ? (parent.parent.parent.parent.a.game.cover.startsWith("/") ? "file://" : "") + parent.parent.parent.parent.a.game.cover : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 120 }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: gl.u(3)
                            Text { width: gl.u(320); elide: Text.ElideRight; text: "Install " + (Games.installAsk ? Games.installAsk.game.title : "") + "?"; color: Theme.text; font.family: Theme.sans; font.pixelSize: gl.u(17); font.weight: Font.Bold }
                            Text {
                                text: !Games.installAsk ? "" : Games.installAsk.bytes < 0 ? "Asking Steam for the size…" : Games.gb(Games.installAsk.bytes) + (Games.installAsk.free >= 0 ? " · " + Games.gb(Games.installAsk.free) + " free" : "")
                                color: Theme.soft; font.family: Theme.sans; font.pixelSize: gl.u(12)
                            }
                        }
                    }
                    Text {
                        visible: !!Games.installAsk && Games.installAsk.licences.length > 0
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: "This game asks you to accept " + (Games.installAsk ? Games.installAsk.licences.length : 0) + " licence agreement(s) first:\n" + (Games.installAsk ? Games.installAsk.licences.map(l => l.url).join("\n") : "")
                        color: Theme.soft; font.family: Theme.sans; font.pixelSize: gl.u(12)
                    }
                    Text { visible: Games.installError !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: Games.installError; color: Theme.red; font.family: Theme.sans; font.pixelSize: gl.u(12) }
                    Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "It downloads in the background through Steam; no Steam window opens."; color: Theme.muted; font.family: Theme.sans; font.pixelSize: gl.u(11.5) }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        CardBtn { k: gl.k; label: "Cancel"; onClicked: Games.cancelAsk() }
                        CardBtn { k: gl.k;
                            readonly property bool lic: !!Games.installAsk && Games.installAsk.licences.length > 0
                            label: lic ? "Accept and install" : "Install"; primary: true
                            enabled: !!Games.installAsk && (Games.installAsk.bytes >= 0 || lic)
                            opacity: enabled ? 1 : 0.5
                            onClicked: Games.confirmInstall(lic)
                        }
                    }
                }
            }
        }

        // ============ DETAILS (hours, last played; Uninstall for Steam games) ============
        Rectangle {
            anchors.fill: parent
            visible: gl.details && gl.g !== null
            color: Qt.rgba(0, 0, 0, 0.55)
            MouseArea { anchors.fill: parent; onClicked: { gl.details = false; gl.confirmUninstall = false; } }
            Rectangle {
                anchors.centerIn: parent
                width: gl.u(460); height: dc.implicitHeight + gl.u(52); radius: gl.u(26)
                color: Qt.rgba(24 / 255, 24 / 255, 27 / 255, 0.95)
                border.width: 1; border.color: Theme.white(0.14)
                MouseArea { anchors.fill: parent }
                ColumnLayout {
                    id: dc
                    x: gl.u(26); y: gl.u(26)
                    width: parent.width - gl.u(52)
                    spacing: gl.u(10)
                    Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: gl.g ? gl.g.title : ""; color: Theme.text; font.family: Theme.sans; font.pixelSize: gl.u(18); font.weight: Font.Bold }
                    Text { text: gl.g ? gl.plat(gl.g.platform).name + (gl.g.emuName ? " · " + gl.g.emuName : "") + (gl.g.installed === false ? " · not installed" : "") : ""; color: Theme.soft; font.family: Theme.sans; font.pixelSize: gl.u(12.5) }
                    Text { text: gl.g ? gl.ago(gl.g.lastPlayed) + (gl.g.playtime ? " · " + Math.round(gl.g.playtime / 60) + " h played" : "") : ""; color: Theme.muted; font.family: Theme.sans; font.pixelSize: gl.u(12.5) }
                    Text { visible: !!gl.g && !!gl.g.path; Layout.fillWidth: true; elide: Text.ElideMiddle; text: gl.g && gl.g.path ? gl.g.path : ""; color: Theme.muted; font.family: Theme.mono; font.pixelSize: gl.u(11) }
                    RowLayout {
                        Layout.topMargin: gl.u(8)
                        Layout.fillWidth: true
                        // Steam only, and it asks once more: the game's files are deleted
                        CardBtn { k: gl.k;
                            visible: !!gl.g && gl.g.platform === "steam" && gl.g.installed !== false
                            label: gl.confirmUninstall ? "Uninstall " + (gl.g ? gl.g.title : "") + "?" : "Uninstall"
                            danger: gl.confirmUninstall
                            onClicked: { if (gl.confirmUninstall) { Games.uninstall(gl.g); gl.details = false; gl.confirmUninstall = false; } else gl.confirmUninstall = true; }
                        }
                        Item { Layout.fillWidth: true }
                        CardBtn { k: gl.k; label: "Close"; onClicked: { gl.details = false; gl.confirmUninstall = false; } }
                    }
                }
            }
        }

        // the letter X jumped to
        Rectangle {
            visible: gl.jumpLetter !== ""
            anchors.centerIn: parent
            width: gl.u(120); height: gl.u(120); radius: gl.u(30)
            color: Qt.rgba(24 / 255, 24 / 255, 27 / 255, 0.85)
            border.width: 1; border.color: Theme.white(0.14)
            Text { anchors.centerIn: parent; text: gl.jumpLetter; color: Theme.text; font.family: Theme.sans; font.pixelSize: gl.u(64); font.weight: Font.Bold }
        }

        // ============ KEY HINTS: the pad's buttons when one is connected, the keyboard's otherwise ============
        Row {
            visible: Games.pad === "" && !gl.panel
            anchors.right: parent.right; anchors.rightMargin: gl.u(32)
            anchors.bottom: parent.bottom; anchors.bottomMargin: gl.u(20)
            spacing: gl.u(18)
            Repeater {
                model: [["Enter", "Play"], ["Esc", "Back"], ["Arrows", "Move"], ["Type", "Search"]]
                delegate: Row {
                    required property var modelData
                    spacing: gl.u(7)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: kk.implicitWidth + gl.u(14); height: gl.u(22); radius: gl.u(6)
                        color: Theme.white(0.12)
                        Text { id: kk; anchors.centerIn: parent; text: parent.parent.modelData[0]; color: Theme.text; font.family: Theme.mono; font.pixelSize: gl.u(11) }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[1]; color: Theme.soft; font.family: Theme.sans; font.pixelSize: gl.u(12) }
                }
            }
        }
        Row {
            visible: Games.pad !== "" && !gl.panel
            anchors.right: parent.right; anchors.rightMargin: gl.u(32)
            anchors.bottom: parent.bottom; anchors.bottomMargin: gl.u(20)
            spacing: gl.u(18)
            Repeater {
                model: [["A", "Play"], ["B", "Back"], ["Y", "Favorite"], ["X", "Jump to letter"], ["LB RB", "Categories"]]
                delegate: Row {
                    required property var modelData
                    spacing: gl.u(7)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(gl.u(22), kt.implicitWidth + gl.u(12)); height: gl.u(22); radius: gl.u(11)
                        color: Theme.white(0.14)
                        Text { id: kt; anchors.centerIn: parent; text: parent.parent.modelData[0]; color: Theme.text; font.family: Theme.sans; font.pixelSize: gl.u(11); font.weight: Font.Bold }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[1]; color: Theme.soft; font.family: Theme.sans; font.pixelSize: gl.u(12) }
                }
            }
        }
    }
}
