import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// Free up space (Mod+Delete, or the launcher): what can be removed safely and how much
// it frees (scripts/cleanup.py scans when the panel opens). Steps that need the
// password or a package manager's own question open in your terminal (Clean…), where
// pacman / flatpak list what goes and ask first; the others take a second click
// (Sure?). The biggest folders in your home are listed to open and look through,
// never deleted.
Item {
    id: cp
    signal closeRequested()
    focus: true
    Keys.onEscapePressed: cp.closeRequested()

    readonly property string tool: Quickshell.shellDir + "/scripts/cleanup.py"
    property var scan: null
    property bool scanning: false
    property string armed: ""               // the button waiting for its second click
    Timer { id: disarm; interval: 4000; onTriggered: cp.armed = "" }

    function reset() { forceActiveFocus(); armed = ""; startScan(); }
    function startScan() { if (scanProc.running) return; scanning = true; scanProc.running = true; }
    Process {
        id: scanProc
        command: ["python3", "-I", cp.tool, "scan"]
        stdout: StdioCollector { onStreamFinished: { try { cp.scan = JSON.parse(text); } catch (e) {} cp.scanning = false; } }
    }
    function gb(b) { return b >= 1073741824 ? (b / 1073741824).toFixed(1) + " GB" : Math.max(1, Math.round(b / 1048576)) + " MB"; }
    readonly property var items: scan ? scan.items.filter(i => i.bytes > 0 || i.count > 0) : []
    readonly property real total: items.reduce((a, i) => a + i.bytes, 0) + (scan ? scan.caches.reduce((a, c) => a + c.bytes, 0) : 0)

    function clean(id, how, cmd) {
        if (!id) return;
        if (how === "terminal") {
            cp.closeRequested();
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/Tide/bin/tide-term", "Free up space", "bash", "-c",
                cmd + "; echo; read -r -s -n 1 -p 'Done. Press any key to close this window.'"]);
            return;
        }
        if (armed !== id) { armed = id; disarm.restart(); return; }
        armed = "";
        cleaner.command = ["python3", "-I", tool, "clean", id];
        cleaner.running = true;
    }
    Process { id: cleaner; onExited: cp.startScan() }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.s(20)
        spacing: Theme.s(12)

        // header: what it found, scan again, close
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.s(10)
            Icon { path: Icons.trash; size: Theme.s(18); color: Theme.accent }
            Column {
                Layout.fillWidth: true
                spacing: Theme.s(2)
                Text { text: "Free up space"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(16); font.weight: Font.DemiBold }
                Text {
                    text: cp.scanning && !cp.scan ? "Looking… (a few seconds)" : cp.scan ? "About " + cp.gb(cp.total) + " can be freed" + (cp.scanning ? " · checking again…" : "") : ""
                    color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                }
            }
            HoverButton {
                implicitWidth: againT.implicitWidth + Theme.s(24); implicitHeight: Theme.s(30); radius: Theme.s(9)
                color: Theme.white(0.07)
                enabled: !cp.scanning
                opacity: enabled ? 1 : 0.5
                onClicked: cp.startScan()
                Text { id: againT; anchors.centerIn: parent; text: "Scan again"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            }
            HoverButton {
                implicitWidth: Theme.s(30); implicitHeight: Theme.s(30)
                onClicked: cp.closeRequested()
                Icon { anchors.centerIn: parent; path: Icons.close; color: Theme.muted }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: list.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            WheelScroll {}
            Column {
                id: list
                width: parent.width
                spacing: Theme.s(4)

                Repeater {
                    model: cp.items
                    delegate: CleanRow {
                        required property var modelData
                        title: modelData.label + " · " + (modelData.bytes > 0 ? cp.gb(modelData.bytes) : modelData.count + (modelData.count === 1 ? " item" : " items"))
                        sub: modelData.sub
                        what: modelData.id; how: modelData.how; cmd: modelData.cmd || ""
                    }
                }
                Text {
                    visible: !!cp.scan && cp.scan.caches.length > 0
                    topPadding: Theme.s(10); leftPadding: Theme.s(4)
                    text: "App caches · apps rebuild them; close an app before clearing its cache"
                    color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11.5)
                }
                Repeater {
                    model: cp.scan ? cp.scan.caches : []
                    delegate: CleanRow {
                        required property var modelData
                        title: modelData.name + " · " + cp.gb(modelData.bytes)
                        what: "cache:" + modelData.name
                    }
                }
                Text {
                    visible: !!cp.scan && cp.scan.big.length > 0
                    topPadding: Theme.s(10); leftPadding: Theme.s(4)
                    text: "Biggest folders in your home · to look through yourself (never deleted here)"
                    color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11.5)
                }
                Repeater {
                    model: cp.scan ? cp.scan.big : []
                    delegate: CleanRow {
                        required property var modelData
                        title: modelData.path.replace(Quickshell.env("HOME"), "~") + " · " + cp.gb(modelData.bytes)
                        what: "open:" + modelData.path
                        how: "open"
                    }
                }
            }
        }
    }

    // one row: name · size, what it is, and its button
    component CleanRow: Rectangle {
        id: row
        property string title
        property string sub: ""
        property string what
        property string how: "here"
        property string cmd: ""
        width: list.width
        height: rowCol.implicitHeight + Theme.s(18)
        radius: Math.min(Theme.s(16), Theme.s(12) * Theme.radiusScale)
        color: Theme.white(0.04)
        Column {
            id: rowCol
            anchors.left: parent.left; anchors.leftMargin: Theme.s(14)
            anchors.right: btn.left; anchors.rightMargin: Theme.s(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s(2)
            Text { width: parent.width; elide: Text.ElideMiddle; text: row.title; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.Medium }
            Text { visible: row.sub !== ""; width: parent.width; wrapMode: Text.WordWrap; text: row.sub; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
        }
        HoverButton {
            id: btn
            readonly property bool sure: cp.armed === row.what
            anchors.right: parent.right; anchors.rightMargin: Theme.s(10)
            anchors.verticalCenter: parent.verticalCenter
            width: btnT.implicitWidth + Theme.s(26); height: Theme.s(30); radius: Theme.s(9)
            hoverFill: !sure
            color: sure ? Theme.accent : Theme.white(0.08)
            enabled: !cleaner.running
            onClicked: {
                if (row.how === "open") {
                    cp.closeRequested();
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.config/Tide/bin/tide-open", "files", row.what.slice(5)]);
                } else cp.clean(row.what, row.how, row.cmd);
            }
            Text {
                id: btnT
                anchors.centerIn: parent
                text: row.how === "open" ? "Open" : btn.sure ? "Sure?" : row.how === "terminal" ? "Clean…" : "Clean"
                color: btn.sure ? Theme.ink : Theme.text
                font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: btn.sure ? Font.DemiBold : Font.Normal
            }
        }
    }
}
