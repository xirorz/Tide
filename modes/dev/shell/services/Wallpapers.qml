pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import ".."

// The wallpaper library for the island's picker (SUPER+W): files in "wallpaperDir"
// (~/wallpapers), their thumbnails (scripts/wallthumbs.sh), palettes (matugen,
// dry run) and sizes, the recent list, and applying one (scripts/wallpaper-apply.sh).
Singleton {
    id: root
    readonly property string dir: Theme.opt("wallpaperDir", Quickshell.env("HOME") + "/wallpapers")
    readonly property string shownDir: dir.replace(Quickshell.env("HOME"), "~")
    readonly property string thumbDir: Quickshell.env("HOME") + "/.cache/tide/wallthumbs"
    property var files: []            // [{ name, path, title, video, thumb }]
    property var recent: []           // paths, newest first
    property string applied: ""       // path of the wallpaper on screen now
    property var palettes: ({})       // path -> { swatches: [8], accent }
    property var metas: ({})          // path -> "3840 × 2160 · JPG"

    function toggle() { IslandState.toggle("wallpapers"); }

    function isVideo(n) { return /\.(mp4|webm|mkv|mov)$/i.test(n); }
    function title(n) {
        const base = n.replace(/\.[^.]+$/, "").replace(/[-_]+/g, " ").trim();
        return base.charAt(0).toUpperCase() + base.slice(1);
    }
    function thumbFor(name) { return "file://" + thumbDir + "/" + Qt.md5(name) + ".png"; }

    // login: video wallpapers start again (awww brings back the still ones by itself)
    Component.onCompleted: Quickshell.execDetached(["bash", Quickshell.shellDir + "/scripts/wallpaper-restore.sh"])
    function refresh() {
        listProc.running = true;
        thumbsProc.running = true;
        appliedProc.running = true;
        recentFile.reload();
    }
    Process {
        id: listProc
        command: ["sh", "-c", "ls -1 -- \"$1\"", "ls", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const n of text.split("\n")) {
                    if (!/\.(png|jpe?g|webp|bmp|gif|mp4|webm|mkv|mov)$/i.test(n)) continue;
                    out.push({ name: n, path: root.dir + "/" + n, title: root.title(n), video: root.isVideo(n), thumb: root.thumbFor(n) });
                }
                root.files = out;
            }
        }
    }
    // makes any missing thumbnails (new files)
    Process { id: thumbsProc; command: ["bash", Quickshell.shellDir + "/scripts/wallthumbs.sh", root.dir] }
    Process {
        id: appliedProc
        command: ["sh", "-c", "readlink -f \"$HOME/.current.wall\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                // a video wallpaper's link points at its thumbnail
                const v = root.files.find(f => f.video && t.endsWith(Qt.md5(f.name) + ".png"));
                root.applied = v ? v.path : t;
            }
        }
    }
    FileView {
        id: recentFile
        path: Quickshell.env("HOME") + "/.local/state/tide/wallpapers-recent"
        printErrors: false
        onLoaded: root.recent = text().split("\n").filter(x => x)
    }

    // palette and size, fetched once per wallpaper when it's selected
    function inspect(f) {
        if (!f) return;
        if (!palettes[f.path]) {
            const p = paletteProc.createObject(root, { target: f });
            p.running = true;
        }
        if (!metas[f.path]) {
            const m = metaProc.createObject(root, { target: f });
            m.running = true;
        }
    }
    Component {
        id: paletteProc
        Process {
            property var target
            // the thumbnail is plenty for colors and fast
            command: ["sh", "-c", "\"$0\" image \"$1\" --dry-run -j hex", Quickshell.shellDir + "/scripts/matugen.sh", target.thumb.replace("file://", "")]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const c = JSON.parse(text).colors;
                        const pick = k => (c[k] && (c[k].dark || c[k].default)) || "#000000";
                        const sw = ["background", "surface_container_high", "outline_variant", "outline",
                                    "tertiary", "secondary", "primary", "on_surface"].map(pick);
                        const p = Object.assign({}, root.palettes);
                        p[target.path] = { swatches: sw, accent: pick("primary") };
                        root.palettes = p;
                    } catch (e) {}
                    destroy();
                }
            }
        }
    }
    Component {
        id: metaProc
        Process {
            property var target
            command: target.video
                ? ["sh", "-c", "ffprobe -v error -select_streams v:0 -show_entries stream=width,height:format=duration -of csv=p=0:s=x \"$1\"", "ffprobe", target.path]
                : ["sh", "-c", "ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x \"$1\"", "ffprobe", target.path]
            stdout: StdioCollector {
                onStreamFinished: {
                    const ext = target.name.split(".").pop().toUpperCase().replace("JPEG", "JPG");
                    let s = ext;
                    const t = text.trim().split(/\s+|x|\n/).filter(x => x);
                    if (target.video && t.length >= 3) {
                        const d = Math.round(parseFloat(t[2]));
                        s = t[0] + " × " + t[1] + " · " + ext + " · " + Math.floor(d / 60) + ":" + String(d % 60).padStart(2, "0") + " loop";
                    } else if (t.length >= 2) {
                        s = t[0] + " × " + t[1] + " · " + ext;
                    }
                    const m = Object.assign({}, root.metas);
                    m[target.path] = s;
                    root.metas = m;
                    destroy();
                }
            }
        }
    }

    // apply: outputs "all" or "DP-1,HDMI-A-1"; transition grow | fade | wipe
    function apply(f, outputs, transition, rgb) {
        applied = f.path;
        const r = [f.path].concat(recent.filter(x => x !== f.path)).slice(0, 24);
        recent = r;
        Quickshell.execDetached(["bash", Quickshell.shellDir + "/scripts/wallpaper-apply.sh", f.path, outputs, transition, rgb ? "1" : "0"]);
    }

    IpcHandler {
        target: "wallpapers"
        function toggle(): void { root.toggle(); }
        function open(): void { IslandState.open("wallpapers", ""); }
        function close(): void { if (IslandState.mode === "wallpapers") IslandState.close(); }
    }
    GlobalShortcut {
        appid: "tide"
        name: "wallpapers"
        description: "Open the wallpaper picker"
        onPressed: root.toggle()
    }
}
