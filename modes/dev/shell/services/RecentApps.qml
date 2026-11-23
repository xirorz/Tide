pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Remembers launched apps for the launcher's "Recent apps".
Singleton {
    id: root
    readonly property string dir: Quickshell.env("HOME") + "/.local/state/tide"
    property var ids: []

    function add(id) {
        const next = [id].concat(ids.filter(x => x !== id)).slice(0, 12);
        ids = next;
        file.setText(JSON.stringify(next));
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", dir])

    FileView {
        id: file
        path: root.dir + "/recent.json"
        printErrors: false
        onLoaded: {
            try { root.ids = JSON.parse(text()); } catch (e) { root.ids = []; }
        }
    }
}
