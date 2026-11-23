pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Clipboard history from cliphist (the same store Ax-Shell used). New clips come
// in through scripts/clip-store.sh, which the Tide Hyprland config starts at login. Entries are
// { id, kind: text | link | color | image, text, meta }, newest first.
Singleton {
    id: root
    property var entries: []
    // where image entries are decoded for thumbnails
    readonly property string thumbDir: Quickshell.env("XDG_RUNTIME_DIR") + "/tide-clipboard"

    function refresh() { listProc.running = true; }
    readonly property string metaTool: Quickshell.shellDir + "/scripts/clipmeta.py"
    function copy(id) { Quickshell.execDetached(["sh", "-c", "cliphist decode " + id + " | wl-copy"]); }
    function remove(id) {
        entries = entries.filter(e => e.id !== id);
        Quickshell.execDetached(["python3", "-I", metaTool, "delete", id]);
    }
    function clearAll() {
        entries = [];
        Quickshell.execDetached(["python3", "-I", metaTool, "clear"]);
    }

    // where and when each clip came from (scripts/clip-store.sh records it)
    property var meta: ({})
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/tide/clipmeta.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.meta = JSON.parse(text()); } catch (e) { root.meta = {}; } }
        onLoadFailed: root.meta = {}
    }
    // cleanup cycle at startup (a no-op unless "clipboardCleanup" is true)
    Component.onCompleted: Quickshell.execDetached(["python3", "-I", metaTool, "cleanup"])

    function appName(cls) {
        if (!cls) return "";
        const e = DesktopEntries.heuristicLookup(cls);
        return e && e.name ? e.name : cls;
    }
    function ago(t) {
        const m = Math.floor((Date.now() / 1000 - t) / 60);
        if (m < 1) return "just now";
        if (m < 60) return m + " min ago";
        const h = Math.floor(m / 60);
        if (h < 24) return h + " hr ago";
        const d = Math.floor(h / 24);
        return d + (d === 1 ? " day ago" : " days ago");
    }
    // the design's meta line: "Text · kitty · 1 min ago"; older clips without a
    // record keep the size line
    function metaLine(e) {
        const r = meta[e.id];
        if (!r) return e.meta;
        const kind = { text: "Text", link: "Link", color: "Color", image: "Image" }[e.kind];
        return [kind, appName(r.app), ago(r.time)].filter(x => x).join(" · ");
    }

    function classify(id, preview) {
        const img = /^\[\[ binary data (.+?) (\w+) (\d+)x(\d+) \]\]$/.exec(preview);
        if (img) return { id: id, kind: "image", text: "Image " + img[3] + " × " + img[4], meta: "Image · " + img[2].toUpperCase() + " · " + img[1] };
        const t = preview.trim();
        if (/^(#[0-9a-fA-F]{3}|#[0-9a-fA-F]{6}|#[0-9a-fA-F]{8}|rgba?\([^)]*\)|hsla?\([^)]*\))$/.test(t))
            return { id: id, kind: "color", text: t, meta: "Color" };
        if (/^(https?|ftp):\/\/\S+$/.test(t)) return { id: id, kind: "link", text: t, meta: "Link · " + (/^\w+:\/\/([^/:]+)/.exec(t) || ["", ""])[1] };
        return { id: id, kind: "text", text: t.replace(/\s+/g, " "), meta: "Text · " + t.length + (t.length === 1 ? " character" : " characters") };
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    out.push(root.classify(line.slice(0, tab), line.slice(tab + 1)));
                }
                root.entries = out;
            }
        }
    }
}
