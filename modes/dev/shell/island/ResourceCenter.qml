import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// The resource center (1180x772, from the resource rings): GPU with VRAM by process,
// CPU, memory, disk and network with history (1 min / 5 min / 1 hr), and the
// processes, sortable by VRAM, CPU or RAM, each with End on hover (asks first; Force
// quit if it won't go). The search box finds every process (and user service) by name,
// command line or user; same-name processes are one row.
Item {
    id: rc
    signal closeRequested()

    property string range: "5 min"
    // sort by a column; clicking the same column again reverses it
    property string sortKey: "vram"          // name | cpu | ram | vram
    property bool sortDesc: true
    // ↓ / ↑ after the sorted column's title (for names: A→Z is ↓)
    function arrow(k) { return sortKey === k ? (sortDesc === (k !== "name") ? "  ↓" : "  ↑") : ""; }
    function sortBy(k) {
        if (sortKey === k) sortDesc = !sortDesc;
        else { sortKey = k; sortDesc = k !== "name"; }   // numbers high→low, names A→Z first
    }
    readonly property string sort: sortKey.toUpperCase()
    readonly property int seconds: range === "1 min" ? 60 : range === "1 hr" ? 3600 : 300
    readonly property var d: Resources.now
    readonly property color tile: Theme.tile

    // the design's multi-color set, from the wallpaper
    readonly property var multi: [Theme.accent, Theme.eq[0], Theme.eq[2], Theme.eq[3]]

    function reset() { search.text = ""; Resources.query = ""; confirmKey = ""; search.forceActiveFocus(); }
    focus: true
    // Esc clears a search first, then closes
    Keys.onEscapePressed: { if (search.text) search.text = ""; else rc.closeRequested(); }

    // search (every process and user service, Resources.found) and the inline confirm
    readonly property bool searching: Resources.query.trim() !== ""
    property string confirmKey: ""        // the row asking "End <name>?"
    function keyOf(p) { return p.pids ? p.name + "@" + p.user : String(p.pid); }
    readonly property var searchRows: {
        const k = sortKey, dir = sortDesc ? -1 : 1;
        const vr = {};
        for (const p of Resources.procs) vr[p.pid] = p;
        return (Resources.found.procs || []).map(g => Object.assign({}, g, {
            pid: g.pids[0], vram: g.pids.reduce((s, x) => s + (vr[x] ? vr[x].vram : 0), 0),
            vramBy: g.pids.length === 1 && vr[g.pids[0]] ? vr[g.pids[0]].vramBy : {}
        })).sort((a, b) => {
            const c = k === "name" ? a.name.localeCompare(b.name, undefined, { sensitivity: "base" }) : a[k] - b[k];
            return c !== 0 ? dir * c : b.cpu - a.cpu;
        });
    }

    // the main GPU (most VRAM) and its VRAM by process; any other GPUs get a line each
    readonly property var gpus: d.gpus || []
    readonly property string mainPci: gpus.length > 0 ? gpus[0].pci : ""
    function onMain(p) { return (p.vramBy && p.vramBy[mainPci]) || 0; }
    // with more than one GPU, each process's VRAM says which card it's on
    readonly property bool multiGpu: gpus.length > 1
    function shortGpu(name) {
        const m = /(RTX|GTX|RX|Arc|Quadro|Radeon Pro)\s?[A-Z]?\d{3,4}\s?(XTX|XT|GRE|Ti|SUPER)?/i.exec(name || "");
        return m ? m[0].trim() : (name || "GPU");
    }
    function gpuTag(p) {
        if (!multiGpu || !p.vramBy) return "";
        const on = Object.keys(p.vramBy).filter(k => p.vramBy[k] >= 52428800);   // 50 MB+
        if (on.length === 0) return "";
        if (on.length > 1) return "both";
        const g = gpus.find(x => x.pci === on[0]);
        return g ? shortGpu(g.name) : "";
    }
    readonly property var vramProcs: Resources.procs.filter(p => onMain(p) > 0).sort((a, b) => onMain(b) - onMain(a))
    readonly property var sortedProcs: {
        const k = sortKey, dir = sortDesc ? -1 : 1;
        return Resources.procs.slice().sort((a, b) => {
            const c = k === "name" ? a.name.localeCompare(b.name, undefined, { sensitivity: "base" }) : a[k] - b[k];
            return c !== 0 ? dir * c : b.cpu - a.cpu;
        });
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.s(22)
        anchors.rightMargin: Theme.s(22)
        anchors.topMargin: Theme.s(20)
        anchors.bottomMargin: Theme.s(22)
        spacing: Theme.s(16)

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            Row {
                Layout.fillWidth: true
                spacing: Theme.s(12)
                Text { text: "Resource center"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.type.h1[0]; font.weight: Theme.type.h1[1]; font.letterSpacing: Theme.type.h1[2] }
                Row {
                    anchors.baseline: parent.children[0].baseline
                    spacing: Theme.s(6)
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Theme.s(6); height: Theme.s(6); radius: Theme.s(3); color: Theme.accent }
                    Text { text: "Live · " + (rc.d.uptime || ""); color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                }
            }
            Segmented { options: ["1 min", "5 min", "1 hr"]; current: rc.range; onPicked: o => rc.range = o }
            HoverButton {
                implicitWidth: Theme.s(32); implicitHeight: Theme.s(32); radius: Theme.s(16)
                onClicked: rc.closeRequested()
                Icon { anchors.centerIn: parent; path: Icons.close; color: Theme.text2 }
            }
        }

        // ---- GPU + 2x2 (fixed height; the processes take the rest) ----
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Theme.s(252)
            columns: 2
            columnSpacing: Theme.s(14)
            uniformCellWidths: true

            // GPU / VRAM
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: gpuCol.implicitHeight + Theme.s(36)
                radius: Theme.s(20)
                color: rc.tile
                ColumnLayout {
                    id: gpuCol
                    anchors.fill: parent
                    anchors.leftMargin: Theme.s(20)
                    anchors.rightMargin: Theme.s(20)
                    anchors.topMargin: Theme.s(18)
                    anchors.bottomMargin: Theme.s(18)
                    spacing: Theme.s(14)
                    RowLayout {
                        Layout.fillWidth: true
                        Row {
                            Layout.fillWidth: true
                            spacing: Theme.s(8)
                            Icon { anchors.verticalCenter: parent.verticalCenter; path: Icons.rect(3, 6, 18, 12, 2) + Icons.circle(9, 12, 2.5) + Icons.circle(16, 12, 2.5); size: Theme.s(14); color: Theme.text2 }
                            Text { text: "GPU"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(14); font.weight: Font.DemiBold }
                            Text { text: rc.d.gpuName || ""; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                        }
                        Text {
                            text: (rc.d.gpuTemp >= 0 ? rc.d.gpuTemp + "°C" : "") + (rc.d.gpuPower >= 0 ? " · " + rc.d.gpuPower + " W" : "")
                            color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.s(2)
                            Text { text: "VRAM"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                            Row {
                                spacing: Theme.s(8)
                                Text {
                                    text: rc.d.vramUsed > 0 ? Resources.gb(rc.d.vramUsed) : "–"
                                    color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(40); font.weight: Font.Medium
                                    font.letterSpacing: -0.8
                                }
                                Text {
                                    anchors.baseline: parent.children[0].baseline
                                    text: rc.d.vramTotal > 0 ? "/ " + Math.round(rc.d.vramTotal / 1073741824) + " GB" : ""
                                    color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(16)
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.alignment: Qt.AlignBottom
                            spacing: Theme.s(2)
                            Text { Layout.alignment: Qt.AlignRight; text: "Usage"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                            Text { Layout.alignment: Qt.AlignRight; text: (rc.d.gpu >= 0 ? rc.d.gpu : 0) + "%"; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(24); font.weight: Font.Medium; font.letterSpacing: Theme.tracking(24) }
                        }
                    }
                    // VRAM by process: the top three, then the rest of what's used
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s(8)
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.s(12)
                            radius: Theme.s(6)
                            color: Theme.white(0.1)
                            clip: true
                            Row {
                                height: parent.height
                                spacing: Theme.s(2)
                                Repeater {
                                    model: rc.vramProcs.slice(0, 3)
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        height: Theme.s(12)
                                        width: rc.d.vramTotal > 0 ? (parent.parent.width) * rc.onMain(modelData) / rc.d.vramTotal : 0
                                        color: rc.multi[index]
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.s(16)
                            Repeater {
                                model: rc.vramProcs.slice(0, 3)
                                delegate: Row {
                                    required property var modelData
                                    required property int index
                                    spacing: Theme.s(6)
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Theme.s(8); height: Theme.s(8); radius: Theme.s(2); color: rc.multi[index] }
                                    T { text: modelData.name; color: Theme.text2; px: Theme.s(11.5) }
                                    T { text: Resources.gb(rc.onMain(modelData)); color: Theme.muted; px: Theme.s(11.5); mono: true }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            T { text: rc.d.vramTotal > 0 ? Resources.gb(rc.d.vramTotal - rc.d.vramUsed) + " GB free" : ""; color: Theme.muted; px: Theme.s(11.5) }
                        }
                    }
                    // any other GPUs, one line each
                    Repeater {
                        model: rc.gpus.slice(1)
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.s(10)
                            T { text: modelData.name; color: Theme.text2; px: Theme.s(11.5) }
                            Item { Layout.fillWidth: true }
                            T {
                                text: Resources.gb(modelData.vramUsed) + " / " + Math.round(modelData.vramTotal / 1073741824) + " GB · " + modelData.busy + "%"
                                      + (modelData.temp >= 0 ? " · " + modelData.temp + "°C" : "") + (modelData.power >= 0 ? " · " + modelData.power + " W" : "")
                                color: Theme.muted; px: Theme.s(11.5); mono: true
                            }
                        }
                    }
                    Spark {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: Theme.s(30)
                        values: Resources.window(Resources.gpuHist, rc.seconds, 120)
                        max: 100
                        color: Theme.accent
                        lineWidth: 1.8
                    }
                }
            }

            // CPU, memory, disk, network
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 2
                columnSpacing: Theme.s(14)
                rowSpacing: Theme.s(14)
                uniformCellWidths: true
                uniformCellHeights: true
                MiniCard {
                    label: "CPU"; meta: rc.d.cpuTemp >= 0 ? rc.d.cpuTemp + "°C" : ""
                    value: Math.round(rc.d.cpu || 0) + "%"; sub: (rc.d.cpuFreq || 0).toFixed(1) + " GHz"
                    values: Resources.window(Resources.cpuHist, rc.seconds, 60); max: 100; lineColor: rc.multi[1]
                }
                MiniCard {
                    label: "Memory"; meta: "swap " + (rc.d.swapUsed > 0 ? Resources.gb(rc.d.swapUsed) + " GB" : "0")
                    value: Resources.gb(rc.d.ramUsed || 0) + " GB"
                    sub: "of " + Math.round((rc.d.ramTotal || 0) / 1073741824) + " GB · " + Math.round(100 * (rc.d.ramUsed || 0) / (rc.d.ramTotal || 1)) + "%"
                    values: Resources.window(Resources.memHist, rc.seconds, 60); max: (rc.d.ramTotal || 1) / 1073741824; lineColor: rc.multi[2]
                }
                MiniCard {
                    label: "Disk"; meta: rc.d.disk || ""
                    value: Resources.rate(rc.d.diskRead || 0); sub: "read · write " + Resources.rate(rc.d.diskWrite || 0)
                    values: Resources.window(Resources.diskHist, rc.seconds, 60); max: 0; lineColor: rc.multi[3]
                    drives: Drives.mounted
                }
                MiniCard {
                    label: "Network"; meta: rc.d.net || ""
                    value: Resources.rate(rc.d.rx || 0); sub: "down · up " + Resources.rate(rc.d.tx || 0)
                    values: Resources.window(Resources.netHist, rc.seconds, 60); max: 0; lineColor: Theme.accent
                }
            }
        }

        // ---- processes ----
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.s(20)
            color: rc.tile
            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.s(16)
                anchors.rightMargin: Theme.s(16)
                anchors.topMargin: Theme.s(14)
                anchors.bottomMargin: Theme.s(10)
                spacing: Theme.s(8)
                RowLayout {
                    Layout.fillWidth: true
                    Row {
                        Layout.fillWidth: true
                        Text { text: "Processes"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.type.h2[0]; font.weight: Theme.type.h2[1] }
                        Text {
                            anchors.baseline: parent.children[0].baseline
                            text: rc.searching ? " · " + rc.searchRows.length + " matching" : " · " + (rc.d.procCount || 0) + " running"
                            color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                        }
                    }
                    // search: name, command line or user; Esc clears
                    Rectangle {
                        implicitWidth: Theme.s(300); implicitHeight: Theme.s(34); radius: Theme.s(10)
                        color: Qt.rgba(0, 0, 0, 0.3)
                        border.width: 1; border.color: search.activeFocus ? Theme.accentLine : Theme.white(0.08)
                        Icon { id: sIcon; x: Theme.s(10); anchors.verticalCenter: parent.verticalCenter; path: "M11 4 A7 7 0 1 0 11.01 4 M16 16 L20 20"; size: Theme.s(14); color: Theme.muted }
                        TextInput {
                            id: search
                            anchors.left: sIcon.right; anchors.leftMargin: Theme.s(8)
                            anchors.right: parent.right; anchors.rightMargin: Theme.s(10)
                            anchors.verticalCenter: parent.verticalCenter
                            clip: true
                            color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12.5)
                            selectionColor: Theme.white(0.2)
                            onTextChanged: { Resources.query = text; rc.confirmKey = ""; }
                            Keys.onEscapePressed: { if (text) text = ""; else rc.closeRequested(); }
                            Text { visible: !search.text; anchors.verticalCenter: parent.verticalCenter; text: "Search processes and services"; color: Theme.dim; font: search.font }
                        }
                    }
                    Segmented { options: ["VRAM", "CPU", "RAM"]; current: rc.sort; padH: Theme.s(14); onPicked: o => { rc.sortKey = o.toLowerCase(); rc.sortDesc = true; } }
                }
                // column titles
                Item {
                    Layout.fillWidth: true
                    implicitHeight: Theme.s(26)
                    ProcColumns {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.s(10)
                        anchors.rightMargin: Theme.s(10)
                        nameText: "Name"; cpuText: "CPU"; ramText: "RAM"; vramText: "VRAM"
                        header: true
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.white(0.07) }
                }
                // the rows are rebuilt every second, so which one is under the cursor
                // is tracked here (by pid), not by each row's own hover
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ListView {
                        id: procList
                        anchors.fill: parent
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: rc.searching ? rc.searchRows : rc.sortedProcs
                        property int hoverPid: -1
                        property point mouse: Qt.point(-1, -1)
                        function updateHover() {
                            if (mouse.y < 0) { hoverPid = -1; return; }
                            const i = indexAt(mouse.x, mouse.y + contentY);
                            const m = rc.searching ? rc.searchRows : rc.sortedProcs;
                            hoverPid = i >= 0 && i < m.length ? m[i].pid : -1;
                        }
                        onModelChanged: updateHover()
                        onContentYChanged: updateHover()
                        WheelScroll {}
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            readonly property bool hovered: procList.hoverPid === modelData.pid
                            width: procList.width
                            height: Theme.s(38)
                            radius: Theme.s(10)
                            color: hovered ? Theme.white(0.05) : "transparent"
                            ProcColumns {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.s(10)
                                anchors.rightMargin: Theme.s(10)
                                proc: row.modelData
                                nameText: row.modelData.name + (row.modelData.count > 1 ? "  ×" + row.modelData.count : "")
                                noteText: row.modelData.note || ""
                                cpuText: row.modelData.cpu.toFixed(1) + "%"
                                ramText: Resources.gb(row.modelData.ram) + " GB"
                                vramText: row.modelData.vram > 0 ? Resources.gb(row.modelData.vram) + " GB" : "—"
                                gpuTag: rc.gpuTag(row.modelData)
                                showEnd: (row.hovered || Resources.stuck[rc.keyOf(row.modelData)] !== undefined || Resources.ending[rc.keyOf(row.modelData)] !== undefined) && rc.confirmKey !== rc.keyOf(row.modelData)
                                rowKey: rc.keyOf(row.modelData)
                            }
                            // the inline confirm: "End firefox (11)?" End / Cancel; or Force quit
                            Rectangle {
                                visible: rc.confirmKey === rc.keyOf(row.modelData)
                                anchors.right: parent.right; anchors.rightMargin: Theme.s(8)
                                anchors.verticalCenter: parent.verticalCenter
                                width: cfRow.implicitWidth + Theme.s(16); height: Theme.s(30); radius: Theme.s(9)
                                color: Theme.tile
                                readonly property bool force: Resources.stuck[rc.keyOf(row.modelData)] !== undefined
                                Row {
                                    id: cfRow
                                    anchors.centerIn: parent
                                    spacing: Theme.s(8)
                                    T { anchors.verticalCenter: parent.verticalCenter; text: (parent.parent.force ? "Force quit " : "End ") + row.modelData.name + (row.modelData.count > 1 ? " (" + row.modelData.count + ")" : "") + "?"; px: Theme.s(12) }
                                    HoverButton {
                                        width: cfYes.implicitWidth + Theme.s(18); height: Theme.s(24); radius: Theme.s(7)
                                        hoverFill: false
                                        color: hovered ? Qt.lighter(Theme.red, 1.1) : Theme.red
                                        onClicked: {
                                            const k = rc.keyOf(row.modelData);
                                            if (Resources.stuck[k] !== undefined) Resources.forceQuit(k);
                                            else Resources.endAll(row.modelData.pids || [row.modelData.pid], k);
                                            rc.confirmKey = "";
                                        }
                                        Text { id: cfYes; anchors.centerIn: parent; text: parent.parent.parent.force ? "Force quit" : "End"; color: "#FFFFFF"; font.family: Theme.sans; font.pixelSize: Theme.s(11); font.weight: Font.DemiBold }
                                    }
                                    HoverButton {
                                        width: cfNo.implicitWidth + Theme.s(18); height: Theme.s(24); radius: Theme.s(7)
                                        hoverFill: false
                                        color: Theme.white(hovered ? 0.14 : 0.08)
                                        onClicked: rc.confirmKey = ""
                                        Text { id: cfNo; anchors.centerIn: parent; text: "Cancel"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                                    }
                                }
                            }
                        }
                    }
                    // hover only (clicks still reach the rows' End buttons)
                    HoverHandler {
                        id: listHover
                        onPointChanged: { procList.mouse = hovered ? point.position : Qt.point(-1, -1); procList.updateHover(); }
                        onHoveredChanged: { if (!hovered) { procList.mouse = Qt.point(-1, -1); procList.updateHover(); } }
                    }
                }
                // services that match the search (systemd --user), with Stop
                ColumnLayout {
                    visible: rc.searching && (Resources.found.services || []).length > 0
                    Layout.fillWidth: true
                    spacing: Theme.s(2)
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.white(0.07) }
                    T { Layout.topMargin: Theme.s(6); text: "Services"; px: Theme.s(11); color: Theme.muted }
                    Repeater {
                        model: (Resources.found.services || []).slice(0, 4)
                        delegate: Rectangle {
                            id: sv
                            required property var modelData
                            readonly property string key: "unit:" + modelData.unit
                            Layout.fillWidth: true
                            implicitHeight: Theme.s(36); radius: Theme.s(10)
                            color: svHover.hovered ? Theme.white(0.05) : "transparent"
                            HoverHandler { id: svHover }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.s(10); anchors.rightMargin: Theme.s(10)
                                spacing: Theme.s(10)
                                Rectangle { implicitWidth: Theme.s(7); implicitHeight: Theme.s(7); radius: Theme.s(4); color: sv.modelData.active === "active" ? Theme.accent : Theme.white(0.25) }
                                T { text: sv.modelData.unit.replace(/\.service$/, ""); px: Theme.s(12.5) }
                                T { Layout.fillWidth: true; elide: Text.ElideRight; text: sv.modelData.desc; px: Theme.s(11); color: Theme.muted }
                                T { text: sv.modelData.sub; px: Theme.s(11); color: Theme.muted; mono: true }
                                Item {
                                    implicitWidth: Theme.s(150); implicitHeight: Theme.s(26)
                                    Row {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.s(6)
                                        T { visible: rc.confirmKey === sv.key; anchors.verticalCenter: parent.verticalCenter; text: "Stop?"; px: Theme.s(12) }
                                        HoverButton {
                                            visible: sv.modelData.own && (svHover.hovered || rc.confirmKey === sv.key)
                                            width: stText.implicitWidth + Theme.s(20); height: Theme.s(26); radius: Theme.s(8)
                                            hoverFill: false
                                            color: rc.confirmKey === sv.key ? Theme.red : Theme.white(0.08)
                                            onClicked: { if (rc.confirmKey === sv.key) { Resources.stopUnit(sv.modelData.unit); rc.confirmKey = ""; } else rc.confirmKey = sv.key; }
                                            Text { id: stText; anchors.centerIn: parent; text: "Stop"; color: rc.confirmKey === sv.key ? "#FFFFFF" : Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                                        }
                                        HoverButton {
                                            visible: rc.confirmKey === sv.key
                                            width: snText.implicitWidth + Theme.s(18); height: Theme.s(26); radius: Theme.s(8)
                                            hoverFill: false
                                            color: Theme.white(hovered ? 0.14 : 0.08)
                                            onClicked: rc.confirmKey = ""
                                            Text { id: snText; anchors.centerIn: parent; text: "Cancel"; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                                        }
                                        T { visible: !sv.modelData.own && svHover.hovered && sv.modelData.active === "active"; anchors.verticalCenter: parent.verticalCenter; text: "System service"; px: Theme.s(11); color: Theme.muted }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- pieces ----------
    component T: Text {
        property real px: Theme.s(12)
        property bool mono: false
        font.family: mono ? Theme.mono : Theme.sans
        font.pointSize: px * 0.75
        color: Theme.text
    }

    component Segmented: Rectangle {
        id: seg
        property var options: []
        property string current: ""
        property real padH: Theme.s(12)
        signal picked(string o)
        implicitWidth: segRow.implicitWidth + Theme.s(6)
        implicitHeight: Theme.s(34)
        radius: Theme.s(11)
        color: Qt.rgba(0, 0, 0, 0.3)
        Row {
            id: segRow
            x: Theme.s(3); y: Theme.s(3)
            spacing: Theme.s(2)
            Repeater {
                model: seg.options
                delegate: HoverButton {
                    required property var modelData
                    readonly property bool on: seg.current === modelData
                    width: segText.implicitWidth + seg.padH * 2
                    height: Theme.s(28)
                    radius: Theme.s(8)
                    hoverFill: false
                    color: on ? Theme.accent : "transparent"
                    onClicked: seg.picked(modelData)
                    Text { id: segText; anchors.centerIn: parent; text: modelData; color: parent.on ? Theme.ink : Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium }
                }
            }
        }
    }

    // a history line with a soft fill under it (max 0 = scale to the window's peak)
    component Spark: Canvas {
        id: sp
        property var values: []
        property real max: 100
        property color color: Theme.accent
        property real lineWidth: 1.6
        onValuesChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const v = values;
            if (!v || v.length < 2) return;
            const top = max > 0 ? max : Math.max(1, Math.max.apply(null, v) * 1.15);
            const w = width, h = height, step = w / (v.length - 1);
            const y = x => h - 2 - (Math.min(x, top) / top) * (h - 6);
            ctx.beginPath();
            ctx.moveTo(0, y(v[0]));
            for (let i = 1; i < v.length; i++) ctx.lineTo(i * step, y(v[i]));
            ctx.lineJoin = "round";
            ctx.lineWidth = lineWidth;
            ctx.strokeStyle = color;
            ctx.stroke();
            ctx.lineTo(w, h);
            ctx.lineTo(0, h);
            ctx.closePath();
            ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.14);
            ctx.fill();
        }
    }

    component MiniCard: Rectangle {
        id: mc
        property string label
        property string meta
        property string value
        property string sub
        property var values: []
        property real max: 100
        property color lineColor: Theme.accent
        // the Disk card: each drive's fill on the right (Drives.mounted, the shared list)
        property var drives: []
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitHeight: Theme.s(119)
        radius: Theme.s(18)
        color: rc.tile
        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.s(16)
            anchors.rightMargin: Theme.s(16)
            anchors.topMargin: Theme.s(14)
            anchors.bottomMargin: Theme.s(14)
            spacing: Theme.s(8)
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: mc.label; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(14); font.weight: Font.DemiBold }
                Text { text: mc.meta; color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11) }
            }
            Text {
                // beside the drive list the number shrinks to fit rather than run under it
                Layout.preferredWidth: mc.drives.length ? mc.width * 0.48 - Theme.s(24) : -1
                fontSizeMode: mc.drives.length ? Text.HorizontalFit : Text.FixedSize
                minimumPixelSize: Theme.s(14)
                text: mc.value; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(22); font.weight: Font.Medium; font.letterSpacing: Theme.tracking(22)
            }
            Text { Layout.topMargin: -Theme.s(4); text: mc.sub; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
            Spark {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Theme.s(24)
                values: mc.values
                max: mc.max
                color: mc.lineColor
            }
        }
        Column {
            visible: mc.drives.length > 0
            anchors.right: parent.right; anchors.rightMargin: Theme.s(16)
            y: Theme.s(42)
            width: parent.width * 0.52 - Theme.s(16)
            spacing: Theme.s(7)
            Repeater {
                model: mc.drives.slice(0, 3)
                delegate: Row {
                    required property var modelData
                    width: parent.width
                    spacing: Theme.s(6)
                    Text { width: Theme.s(48); elide: Text.ElideRight; text: modelData.label; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(11); anchors.verticalCenter: parent.verticalCenter }
                    Rectangle {
                        width: parent.width - Theme.s(48) - Theme.s(30) - Theme.s(12); height: Theme.s(4); radius: Theme.s(2)
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.white(0.14)
                        Rectangle { width: parent.width * modelData.pct / 100; height: parent.height; radius: parent.radius; color: modelData.pct >= 90 ? Theme.red : mc.lineColor }
                    }
                    Text { width: Theme.s(30); horizontalAlignment: Text.AlignRight; text: modelData.pct + "%"; color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11); anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }
    }

    // name | CPU 110 | RAM 110 | VRAM 130 | End 90
    component ProcColumns: RowLayout {
        id: pc
        property var proc: null
        property bool header: false
        property string nameText
        property string noteText
        property string cpuText
        property string ramText
        property string vramText
        property string gpuTag: ""
        property bool showEnd: false
        property string rowKey: ""
        readonly property bool stuck: Resources.stuck[rowKey] !== undefined
        readonly property bool waiting: Resources.ending[rowKey] !== undefined
        spacing: 0
        readonly property string sortKey: rc.sort
        function style(col) { return !header && sortKey === col; }

        Row {
            Layout.fillWidth: true
            spacing: Theme.s(10)
            clip: true
            Rectangle {
                visible: !pc.header
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.s(22); height: Theme.s(22); radius: Theme.s(6)
                color: Theme.white(0.08)
                Text {
                    anchors.centerIn: parent
                    text: pc.nameText.replace(/[^A-Za-z0-9]/g, "").slice(0, 2).toUpperCase()
                    color: Theme.text2; font.family: Theme.sans; font.pointSize: Theme.sf(10.5 * 0.75); font.weight: Font.DemiBold
                }
            }
            T {
                anchors.verticalCenter: parent.verticalCenter
                text: pc.nameText + (pc.header ? rc.arrow("name") : "")
                px: pc.header ? Theme.s(11) : Theme.s(12.5)
                color: pc.header ? (rc.sortKey === "name" ? Theme.accent : Theme.muted) : Theme.text
                MouseArea { enabled: pc.header; anchors.fill: parent; anchors.margins: -Theme.s(6); cursorShape: Qt.PointingHandCursor; onClicked: rc.sortBy("name") }
            }
            T { anchors.verticalCenter: parent.verticalCenter; visible: !pc.header && pc.noteText !== ""; text: pc.noteText; px: Theme.s(11); color: Theme.muted }
        }
        ProcCol { w: Theme.s(110); key: "cpu"; text: pc.cpuText + (pc.header ? rc.arrow("cpu") : ""); on: pc.style("CPU"); header: pc.header }
        ProcCol { w: Theme.s(110); key: "ram"; text: pc.ramText + (pc.header ? rc.arrow("ram") : ""); on: pc.style("RAM"); header: pc.header }
        Row {
            Layout.preferredWidth: rc.multiGpu ? Theme.s(200) : Theme.s(130)
            layoutDirection: Qt.RightToLeft
            spacing: Theme.s(8)
            ProcCol { key: "vram"; w: 0; text: pc.vramText + (pc.header ? rc.arrow("vram") : ""); on: pc.style("VRAM"); header: pc.header; anchors.verticalCenter: parent.verticalCenter }
            T {
                visible: !pc.header && pc.gpuTag !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: pc.gpuTag
                px: Theme.s(11)
                color: Theme.muted
            }
        }
        Item {
            Layout.preferredWidth: Theme.s(90)
            implicitHeight: Theme.s(26)
            // End (asks first), "Ending…" for 3 s, then Force quit if it's still there;
            // Tide, the session and system processes say so instead
            HoverButton {
                visible: pc.showEnd && pc.proc && pc.proc.own
                enabled: !pc.waiting
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: endText.implicitWidth + Theme.s(20); height: Theme.s(26); radius: Theme.s(8)
                hoverFill: false
                color: pc.stuck ? Theme.red : Theme.white(0.08)
                onClicked: rc.confirmKey = pc.rowKey
                Text { id: endText; anchors.centerIn: parent; text: pc.waiting ? "Ending…" : pc.stuck ? "Force quit" : "End"; color: pc.stuck ? "#FFFFFF" : Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
            }
            T {
                visible: pc.showEnd && pc.proc && !pc.proc.own && !pc.header
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "System process"; px: Theme.s(11); color: Theme.muted
            }
        }
    }

    // a right-aligned number column (the sorted one in the accent)
    component ProcCol: Text {
        property real w: Theme.s(110)
        property bool on: false
        property bool header: false
        property string key: ""
        Layout.preferredWidth: w > 0 ? w : implicitWidth
        horizontalAlignment: Text.AlignRight
        color: header ? (rc.sortKey === key ? Theme.accent : Theme.muted) : on ? Theme.accent : Theme.text2
        // the column titles sort (again = reverse)
        MouseArea { enabled: parent.header; anchors.fill: parent; anchors.margins: -Theme.s(6); cursorShape: Qt.PointingHandCursor; onClicked: rc.sortBy(parent.key) }
        font.family: header ? Theme.sans : Theme.mono
        font.pixelSize: header ? Theme.s(11) : Theme.s(12)
        font.weight: on ? Font.Medium : Font.Normal
    }
}
