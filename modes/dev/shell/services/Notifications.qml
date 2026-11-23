pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Tide is the notification daemon. Every notification is kept (tracked) until it is
// clicked or cleared in the control center. `unseen` counts the ones that arrived
// since the control center was last opened; the bell dot shows while it is above 0.
// Rules (Settings → Notifications, ~/.config/Tide/notifications.json): apps you mute
// are dropped; every app that has sent one is listed there to mute.
Singleton {
    id: root

    property int unseen: 0
    // a new notification came in (the island shows it as a banner)
    signal received(var n)
    // arrival time per notification id, for "now" / "2m" / "1h"
    property var arrived: ({})
    // ticks once a minute so the relative times refresh
    property date now: new Date()

    // newest first
    readonly property var list: server.trackedNotifications.values.slice().reverse()

    function markSeen() { unseen = 0; }
    function clearAll() {
        for (const n of server.trackedNotifications.values.slice()) n.dismiss();
        unseen = 0;
    }
    function activate(n) {
        for (const a of n.actions) {
            if (a.identifier === "default") { a.invoke(); break; }
        }
        n.dismiss();
    }
    function ago(n) {
        const t = arrived[n.id];
        if (!t) return "now";
        const m = Math.floor((now - t) / 60000);
        if (m < 1) return "now";
        if (m < 60) return m + "m";
        const h = Math.floor(m / 60);
        if (h < 24) return h + "h";
        return Math.floor(h / 24) + "d";
    }

    // ---- rules ----
    property var muted: []                   // app names, lower case
    property var apps: []                    // every app that has sent one (as it names itself)
    property bool steamTideNotices: true     // hide Steam's pop-ups for what Tide already tells you
    function isMuted(name) { return muted.indexOf(String(name).toLowerCase()) >= 0; }
    function setMuted(name, on) {
        const k = String(name).toLowerCase();
        muted = on ? muted.filter(x => x !== k).concat([k]) : muted.filter(x => x !== k);
        saveRules();
    }
    function setSteamTideNotices(on) { steamTideNotices = on; saveRules(); }
    function saveRules() { rf.setText(JSON.stringify({ muted: muted, apps: apps, steamTideNotices: steamTideNotices }, null, 2) + "\n"); }
    FileView {
        id: rf
        path: Quickshell.env("HOME") + "/.config/Tide/notifications.json"
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.muted = d.muted || []; root.apps = d.apps || []; root.steamTideNotices = d.steamTideNotices !== false;
            } catch (e) {}
        }
    }

    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.now = new Date() }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            const name = n.appName || n.desktopEntry || "";
            if (name && !root.apps.some(a => a.toLowerCase() === name.toLowerCase())) { root.apps = root.apps.concat([name]); root.saveRules(); }
            if (name && root.isMuted(name)) { n.dismiss(); return; }
            n.tracked = true;
            const a = Object.assign({}, root.arrived);
            a[n.id] = new Date();
            root.arrived = a;
            root.now = new Date();
            // kept across a shell reload: already seen, no new banner
            if (n.lastGeneration) return;
            root.unseen++;
            root.received(n);
        }
    }

    IpcHandler {
        target: "notifications"
        function rules(): string { return JSON.stringify({ muted: root.muted, apps: root.apps, steamTideNotices: root.steamTideNotices }); }
        function list(): string { return JSON.stringify(root.list.map(n => ({ app: n.appName, summary: n.summary, body: n.body, desktop: n.desktopEntry }))); }
    }
}
