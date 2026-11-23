import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Settings → Games: what the game launcher (Mod+G) finds by itself and what you add.
// Steam and Lutris are discovered; emulators found on this PC are offered (you add them,
// with the folders your games are in); any other game (a program, AppImage or script)
// can be added by hand. Tide only launches: settings stay in each app.
ColumnLayout {
    id: gs
    spacing: Theme.s(18)
    Component.onCompleted: { Games.refresh(); Games.loadKnown(); }

    Heading { text: "Games"; sub: "The game launcher (Mod + G) finds Steam and Lutris games by itself. Add your emulators and other games here." }

    // ---- what's discovered ----
    SCard {
        title: "Library"
        SRow {
            label: "Steam"
            sub: Games.steamNote || (Games.raw.some(g => g.platform === "steam") ? Games.raw.filter(g => g.platform === "steam" && g.installed !== false && (!g.kind || g.kind === "game")).length + " installed, " + Games.raw.filter(g => g.platform === "steam" && g.installed === false).length + " more you own (install them from the launcher)" : "Not found on this PC")
        }
        SRow {
            label: "Lutris games"
            sub: Games.lutrisFound ? Games.raw.filter(g => g.platform === "lutris").length + " installed games from your Lutris library" : "Lutris isn't set up on this PC"
            SToggle { on: Games.lutris; onToggled: Games.setLutris(!on) }
        }
        SRow {
            label: "Show non-game apps"
            sub: "Steam apps that aren't games (" + Games.appCount + " installed), like Blender"
            SToggle { on: Games.showApps; onToggled: Games.setShowApps(!on) }
        }
        // only with the AI features on (Settings → AI): it's about the local AI's memory
        SRow {
            visible: Theme.aiEnabled
            last: true
            label: "Pause local AI while playing"
            sub: "Frees the graphics memory the local AI uses while a game runs (not active yet)"
            SToggle { on: Games.pauseAi; onToggled: Games.setPauseAi(!on) }
        }
    }

    // ---- emulators: your cards, one "Add an emulator" row; the chooser and the form open on demand ----
    SCard {
        id: form
        title: "Emulators"
        property var draft: null
        property int index: -1
        property string error: ""
        property bool choosing: false             // "Add…" pressed: which emulator?
        onDraftChanged: if (draft) choosing = false
        function close() { draft = null; choosing = false; error = ""; }
        readonly property var found: (Games.known.emulators || []).filter(k => k.found.length && !Games.emulators.some(e => e.id === k.id))
        // a folder's system, from its name: "switch2" → Switch 2, "switch1" → Switch
        function guess(path, plats) {
            const b = path.split("/").pop().toLowerCase().replace(/[\s_-]+/g, "");
            return plats.find(p => p === b) || plats.find(p => p === b.replace(/\d+$/, "")) || plats[0];
        }
        function folderList(list, plats, fallback) { return (list || []).map(f => typeof f === "string" ? { path: f, platform: fallback || guess(f, plats) } : f); }
        function fromKnown(k) {
            const plats = k.platforms || [k.platform];
            draft = { id: k.id, name: k.name, platforms: plats, program: k.found[0] || "", args: k.args, folders: folderList(k.folders, plats), exts: k.exts.join(", ") };
            index = -1; error = "";
        }
        function edit(e, i) {
            const d = JSON.parse(JSON.stringify(e)), plats = d.platforms || [d.platform];
            d.platforms = plats; d.folders = folderList(d.folders, plats, d.platform); d.exts = (d.exts || []).join(", ");
            draft = d; index = i; error = "";
        }
        function blank(k) { if (k) { fromKnown(k); return; } draft = { id: "custom-" + Date.now(), name: "", platforms: ["switch"], program: "", args: "{rom}", folders: [], exts: "" }; index = -1; error = ""; }
        function togglePlatform(k) {
            const has = draft.platforms.indexOf(k) >= 0;
            if (has && draft.platforms.length === 1) return;         // at least one system
            const plats = has ? draft.platforms.filter(x => x !== k) : draft.platforms.concat([k]);
            const d = Object.assign({}, draft, { platforms: plats });
            d.folders = d.folders.map(f => plats.indexOf(f.platform) >= 0 ? f : { path: f.path, platform: guess(f.path, plats) });
            draft = d;
        }
        function setFolder(i, key, v) { const l = draft.folders.slice(); l[i] = Object.assign({}, l[i], { [key]: v }); set("folders", l); }
        function set(key, v) { if (!draft) return; const d = Object.assign({}, draft); d[key] = v; draft = d; }
        function save() {
            if (!draft.name.trim()) { error = "Give it a name"; return; }
            if (!draft.program.trim()) { error = "Pick the emulator's program"; return; }
            if (!draft.folders.length) { error = "Add the folder your games are in"; return; }
            const d = Object.assign({}, draft);
            d.platform = d.platforms[0];                       // the main one (older entries had only this)
            d.exts = String(d.exts || "").split(/[\s,]+/).map(x => x.replace(/^\./, "").toLowerCase()).filter(x => x);
            if (!d.exts.length) delete d.exts;
            const l = Games.emulators.slice();
            const at = index >= 0 ? index : l.findIndex(e => e.id === d.id);
            if (at >= 0) l[at] = d; else l.push(d);
            Games.saveEmulators(l);
            close();
        }

        // your emulators (hidden while one is being edited)
        Repeater {
            model: form.draft ? [] : Games.emulators
            delegate: SRow {
                required property var modelData
                required property int index
                label: modelData.name + " · " + (modelData.platforms || [modelData.platform]).map(k => (Games.platformInfo[k] || {}).name || k).join(", ")
                sub: Games.raw.filter(g => g.emulator === modelData.id).length + " games in " + modelData.folders.length + (modelData.folders.length === 1 ? " folder" : " folders")
                Row {
                    spacing: Theme.s(8)
                    SBtn { label: "Edit"; onClicked: form.edit(Games.emulators[index], index) }
                    SBtn { label: "Remove"; onClicked: Games.saveEmulators(Games.emulators.filter((e, i) => i !== index)) }
                }
            }
        }
        // closed: one row
        SRow {
            visible: form.draft === null && !form.choosing
            last: true
            label: "Add an emulator"
            sub: form.found.length ? form.found.length + (form.found.length === 1 ? " emulator" : " emulators") + " found on this PC" : "One Tide knows, or any other program"
            SBtn { label: "Add…"; primary: true; onClicked: form.choosing = true }
        }
        // the chooser: what's found on this PC (a line each), or pick any
        Repeater {
            model: form.draft === null && form.choosing ? form.found : []
            delegate: SRow {
                required property var modelData
                label: "Found: " + modelData.name + " · " + (modelData.platforms || [modelData.platform]).map(k => (Games.platformInfo[k] || {}).name || k).join(", ")
                sub: modelData.found[0]
                SBtn { label: "Add"; primary: true; onClicked: form.fromKnown(modelData) }
            }
        }
        SRow {
            visible: form.draft === null && form.choosing
            label: "Or pick one"
            sub: "Emulators Tide knows, or Other for anything else"
            SDropdown {
                mono: false
                options: (Games.known.emulators || []).map(k => ({ label: k.name + " · " + ((Games.platformInfo[k.platform] || {}).name || k.platform), value: k.id })).concat([{ label: "Other…", value: "other" }])
                value: ""
                onPicked: v => form.blank(v === "other" ? null : (Games.known.emulators || []).find(k => k.id === v))
            }
        }
        SRow {
            visible: form.draft === null && form.choosing
            last: true
            label: ""
            SBtn { label: "Cancel"; onClicked: form.close() }
        }
        // the form
        SRow {
            visible: form.draft !== null
            label: form.index >= 0 ? "Editing " + (form.draft ? form.draft.name : "") : "Setting up " + (form.draft && form.draft.name ? form.draft.name : "an emulator")
            sub: "Save to keep it; Cancel to leave things as they were"
        }
        SRow { visible: form.draft !== null; label: "Name"; SField { text: form.draft ? form.draft.name : ""; hint: "Lichii"; onEdited: v => form.set("name", v) } }
        SRow {
            visible: form.draft !== null
            label: "Systems"
            sub: "Everything it runs (Lichii: Switch and Switch 2)"
            Flow {
                width: Theme.s(380)
                spacing: Theme.s(6)
                Repeater {
                    model: Object.keys(Games.platformInfo).filter(k => ["steam", "lutris", "pc"].indexOf(k) < 0)
                    delegate: HoverButton {
                        required property var modelData
                        readonly property bool on: !!form.draft && (form.draft.platforms || []).indexOf(modelData) >= 0
                        width: pt.implicitWidth + Theme.s(22); height: Theme.s(30); radius: Theme.s(9)
                        hoverFill: false
                        color: on ? Theme.accent : Theme.white(hovered ? 0.12 : 0.07)
                        onClicked: form.togglePlatform(modelData)
                        Text { id: pt; anchors.centerIn: parent; text: Games.platformInfo[parent.modelData].name; color: parent.on ? Theme.ink : Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                    }
                }
            }
        }
        SRow {
            visible: form.draft !== null
            label: "Program"
            sub: form.draft && form.draft.program ? form.draft.program : "The emulator's program or AppImage (or a flatpak run … command)"
            Row {
                spacing: Theme.s(8)
                SField { text: form.draft ? form.draft.program : ""; hint: "/path/to/emulator"; onEdited: v => form.set("program", v) }
                SBtn { label: "Browse…"; onClicked: Games.pick(false, "The emulator's program", p => form.set("program", p)) }
            }
        }
        SRow { visible: form.draft !== null; label: "File types"; sub: "The game files it opens"; SField { text: form.draft ? form.draft.exts : ""; hint: "xci, nsp"; onEdited: v => form.set("exts", v) } }
        SRow { visible: form.draft !== null; label: "Launch arguments"; sub: "{rom} is the game's file"; SField { text: form.draft ? form.draft.args : ""; hint: "-f -g {rom}"; onEdited: v => form.set("args", v) } }
        SRow {
            visible: form.draft !== null
            label: "Game folders"
            sub: form.draft && form.draft.folders.length ? "Each folder is one system's games" : "Where you keep the games for it"
            Row {
                spacing: Theme.s(8)
                // type a path and press Enter, or Browse
                SField {
                    id: folderIn
                    hint: "/path/to/games, then Enter"
                    onDone: v => { const p = v.trim().replace(/\/$/, ""); if (p && !form.draft.folders.some(f => f.path === p)) form.set("folders", form.draft.folders.concat([{ path: p, platform: form.guess(p, form.draft.platforms) }])); folderIn.text = ""; }
                }
                SBtn { label: "Browse…"; onClicked: Games.pick(true, "A folder with games", p => { if (!form.draft.folders.some(f => f.path === p)) form.set("folders", form.draft.folders.concat([{ path: p, platform: form.guess(p, form.draft.platforms) }])); }) }
            }
        }
        Repeater {
            model: form.draft ? form.draft.folders : []
            delegate: Item {
                required property var modelData
                required property int index
                visible: form.draft !== null
                Layout.fillWidth: true
                implicitHeight: Theme.s(46)
                Text {
                    anchors.left: parent.left; anchors.leftMargin: Theme.s(28)
                    anchors.right: fRow.left; anchors.rightMargin: Theme.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideMiddle
                    text: parent.modelData.path
                    color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(12)
                }
                Row {
                    id: fRow
                    anchors.right: parent.right; anchors.rightMargin: Theme.s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.s(8)
                    // which system this folder's games are (only when it runs more than one)
                    SDropdown {
                        visible: form.draft && form.draft.platforms.length > 1
                        mono: false
                        options: form.draft ? form.draft.platforms.map(k => ({ label: Games.platformInfo[k].name, value: k })) : []
                        value: parent.parent.modelData.platform
                        onPicked: v => form.setFolder(parent.parent.index, "platform", v)
                    }
                    HoverButton {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.s(30); height: Theme.s(30); radius: Theme.s(9)
                        onClicked: form.set("folders", form.draft.folders.filter((f, i) => i !== parent.parent.index))
                        Text { anchors.centerIn: parent; text: "×"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(16) }
                    }
                }
                Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: Theme.s(16); anchors.rightMargin: Theme.s(16); height: 1; color: Theme.white(0.05) }
            }
        }
        SRow {
            visible: form.draft !== null
            last: true
            label: form.error
            Row {
                spacing: Theme.s(8)
                SBtn { label: "Cancel"; onClicked: form.close() }
                SBtn { label: "Save"; primary: true; onClicked: form.save() }
            }
        }
    }

    // ---- other games, by hand ----
    SCard {
        id: manual
        title: "Your games"
        property var draft: null
        property string error: ""
        function set(key, v) { if (!draft) return; const d = Object.assign({}, draft); d[key] = v; draft = d; }
        function save() {
            if (!draft.program.trim()) { error = "Pick the game's program"; return; }
            const d = Object.assign({}, draft);
            if (!d.name.trim()) d.name = d.program.split("/").pop().replace(/\.(AppImage|sh|x86_64)$/i, "");
            Games.saveManual(Games.manual.concat([d]));
            draft = null; error = "";
        }
        Repeater {
            model: Games.manual
            delegate: SRow {
                required property var modelData
                required property int index
                label: modelData.name
                sub: modelData.program
                SBtn { label: "Remove"; onClicked: Games.saveManual(Games.manual.filter((g, i) => i !== index)) }
            }
        }
        SRow {
            visible: manual.draft === null
            last: true
            label: "Add a game"
            sub: "A program, AppImage or script; it starts directly from the launcher"
            SBtn { label: "Add…"; primary: true; onClicked: { manual.draft = { id: String(Date.now()), name: "", program: "", cover: "" }; manual.error = ""; } }
        }
        SRow {
            visible: manual.draft !== null
            label: "Program"
            sub: manual.draft && manual.draft.program ? manual.draft.program : "The game's program, AppImage or script"
            SBtn { label: "Browse…"; onClicked: Games.pick(false, "The game", p => manual.set("program", p)) }
        }
        SRow { visible: manual.draft !== null; label: "Name"; SField { text: manual.draft ? manual.draft.name : ""; hint: "From the file name"; onEdited: v => manual.set("name", v) } }
        SRow {
            visible: manual.draft !== null
            label: "Cover (optional)"
            sub: manual.draft && manual.draft.cover ? manual.draft.cover : "A picture for the shelf"
            SBtn { label: "Browse…"; onClicked: Games.pick(false, "A cover picture", p => manual.set("cover", p)) }
        }
        SRow {
            visible: manual.draft !== null
            last: true
            label: manual.error
            Row {
                spacing: Theme.s(8)
                SBtn { label: "Cancel"; onClicked: manual.draft = null }
                SBtn { label: "Add game"; primary: true; onClicked: manual.save() }
            }
        }
    }
}
