import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../services"

// Settings → Tablet (only listed while Hyprland sees a drawing tablet). A plugin for
// the connected tablet (~/.config/Tide/plugins/*) shows its page here; the pen itself
// always stays on the tablet's own screen (input:tablet:output in the Hyprland config). Plugin pages get `theme` (Theme), `plugin` (its
// manifest, with `dir`) and `host` (openApp()) when they load.
ColumnLayout {
    id: tb
    spacing: Theme.s(16)
    readonly property var plugin: Tablets.active

    Heading {
        Layout.fillWidth: true
        text: "Tablet"
        sub: (tb.plugin ? tb.plugin.name : (Tablets.tablets[0] || "Drawing tablet")) + " · connected"
    }

    // the connected tablet's plugin page
    Loader {
        id: page
        Layout.fillWidth: true
        active: tb.plugin !== null && !!tb.plugin.page
        source: active ? "file://" + tb.plugin.dir + "/" + tb.plugin.page : ""
        onLoaded: {
            item.theme = Theme;
            item.plugin = Qt.binding(() => tb.plugin);
            item.host = tb.host;
        }
    }
    QtObject {
        id: host
        function openApp() { if (tb.plugin) Tablets.openApp(tb.plugin); }
    }
    property alias host: host
}
