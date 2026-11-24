import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// The island's wallpaper picker (760x420, SUPER+W): search, which display, Images
// or Videos, the transition, and a scrolling grid of thumbnails. Click selects,
// double-click or Enter applies, and the island stays open (the grid stays put)
// so you can try another. RGB sync and accent from the wallpaper are always on.
Item {
    id: wpp
    signal closeRequested()

    property string query: ""
    property bool videos: false
    property string monitor: "All"          // All or a Hyprland monitor name
    property string transition: Theme.opt("wallpaperTransition", "grow")
    property int index: 0
    property bool monitorMenu: false

    readonly property var shown: {
        const q = query.trim().toLowerCase();
        let list = Wallpapers.files.filter(f => f.video === videos);
        if (q) list = list.filter(f => f.title.toLowerCase().indexOf(q) >= 0 || f.name.toLowerCase().indexOf(q) >= 0);
        return list;
    }
    readonly property var sel: shown.length > 0 ? shown[Math.max(0, Math.min(index, shown.length - 1))] : null
    function monitorLabel(m) { return m === "All" ? "All displays" : m === Theme.monitor ? "Main" : "Side"; }

    function reset() {
        Wallpapers.refresh();
        query = "";
        search.text = "";
        monitorMenu = false;
        jumpPending = true;
        jumpToApplied();
        forceActiveFocus();
    }
    // select the wallpaper on screen when the picker opens (not after applying one,
    // so the grid stays where you are); runs after the list has been rebuilt
    property bool jumpPending: false
    function jumpToApplied() { if (jumpPending) Qt.callLater(doJump); }
    function doJump() {
        const a = Wallpapers.files.find(f => f.path === Wallpapers.applied);
        if (a) videos = a.video;
        const q = query.trim().toLowerCase();
        const list = Wallpapers.files.filter(f => f.video === videos && (!q || f.title.toLowerCase().indexOf(q) >= 0 || f.name.toLowerCase().indexOf(q) >= 0));
        const i = list.findIndex(f => f.path === Wallpapers.applied);
        if (i < 0) return;      // not known yet; the next update tries again
        jumpPending = false;
        index = i;
        grid.positionViewAtIndex(index, GridView.Center);
    }
    Connections {
        target: Wallpapers
        function onFilesChanged() { wpp.jumpToApplied(); }
        function onAppliedChanged() { if (IslandState.mode === "wallpapers") wpp.jumpToApplied(); }
    }
    function apply() {
        if (sel) Wallpapers.apply(sel, monitor === "All" ? "all" : monitor, transition, true);
    }

    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { if (monitorMenu) monitorMenu = false; else wpp.closeRequested(); }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) wpp.apply();
        else if (event.key === Qt.Key_Right) index = Math.min(shown.length - 1, index + 1);
        else if (event.key === Qt.Key_Left) index = Math.max(0, index - 1);
        else if (event.key === Qt.Key_Down) index = Math.min(shown.length - 1, index + grid.columns);
        else if (event.key === Qt.Key_Up) index = Math.max(0, index - grid.columns);
        else if (event.text && event.text.trim() && !(event.modifiers & Qt.ControlModifier)) { search.forceActiveFocus(); search.text += event.text; }
        else return;
        event.accepted = true;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.s(14)
        spacing: Theme.s(10)

        // ---- controls ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.s(8)

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.s(34)
                radius: Theme.s(11)
                color: Theme.white(0.07)
                Icon { x: Theme.s(11); anchors.verticalCenter: parent.verticalCenter; path: Icons.search; size: Theme.s(14); color: Theme.muted }
                TextInput {
                    id: search
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.s(32)
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.s(10)
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: Theme.s(12)
                    clip: true
                    onTextChanged: { wpp.query = text; wpp.index = 0; }
                    Keys.onEscapePressed: { if (text) text = ""; else wpp.closeRequested(); }
                    Keys.onReturnPressed: wpp.apply()
                    Keys.onDownPressed: wpp.forceActiveFocus()
                    Text {
                        visible: !search.text
                        text: "Search " + Wallpapers.files.length + " wallpapers"
                        color: Theme.muted; font: search.font
                    }
                }
            }

            // display: a small dropdown (only with more than one screen; one screen gets it)
            HoverButton {
                id: monBtn
                visible: Hyprland.monitors.values.length > 1
                implicitWidth: monRow.implicitWidth + Theme.s(22)
                implicitHeight: Theme.s(34)
                radius: Theme.s(11)
                hoverFill: false
                color: wpp.monitorMenu ? Theme.white(0.12) : Theme.white(0.07)
                onClicked: wpp.monitorMenu = !wpp.monitorMenu
                Row {
                    id: monRow
                    anchors.centerIn: parent
                    spacing: Theme.s(6)
                    Icon { anchors.verticalCenter: parent.verticalCenter; path: Icons.shotScreen; size: Theme.s(14); color: Theme.text2 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: wpp.monitorLabel(wpp.monitor); color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium }
                    Icon { anchors.verticalCenter: parent.verticalCenter; path: wpp.monitorMenu ? Icons.chevronUp : Icons.chevronDown; size: Theme.s(12); color: Theme.muted }
                }
            }

            Segmented {
                options: ["Images", "Videos"]
                current: wpp.videos ? "Videos" : "Images"
                onPicked: o => { wpp.videos = o === "Videos"; wpp.index = 0; }
            }
            Segmented {
                options: ["Grow", "Fade", "Wipe"]
                current: wpp.transition.charAt(0).toUpperCase() + wpp.transition.slice(1)
                onPicked: o => { wpp.transition = o.toLowerCase(); Theme.set("wallpaperTransition", wpp.transition); }
            }
        }

        // ---- thumbnails ----
        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            readonly property int columns: 5
            cellWidth: Math.floor(width / columns)
            cellHeight: Math.round((cellWidth - Theme.s(8)) * 9 / 16) + Theme.s(8) + Theme.s(20)
            model: wpp.shown
            currentIndex: wpp.index
            boundsBehavior: Flickable.StopAtBounds
            WheelScroll {}
            // keyboard moves keep the selection in view; Contain never scrolls a visible tile
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

            delegate: Item {
                id: tile
                required property var modelData
                required property int index
                readonly property bool selected: index === wpp.index
                readonly property bool applied: modelData.path === Wallpapers.applied
                width: grid.cellWidth
                height: grid.cellHeight
                HoverHandler { id: hov }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    // with the display menu open, a click only closes it
                    onClicked: {
                        if (wpp.monitorMenu) { wpp.monitorMenu = false; return; }
                        wpp.index = tile.index;
                        wpp.forceActiveFocus();
                    }
                    onDoubleClicked: { wpp.index = tile.index; wpp.apply(); }
                }
                Column {
                    x: Theme.s(4)
                    // hover lifts the tile 5px (motion sheet: 180ms, none with reduced motion)
                    y: Theme.s(4) - (hov.hovered && !Theme.reduceMotion ? Theme.s(5) : 0)
                    Behavior on y { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
                    width: parent.width - Theme.s(8)
                    spacing: Theme.s(4)
                    ClippingRectangle {
                        width: parent.width
                        height: Math.round(width * 9 / 16)
                        radius: Theme.s(10)
                        color: Theme.white(0.06)
                        // selection is always a 2px accent ring
                        border.width: tile.selected ? 2 : 1
                        border.color: tile.selected ? Theme.accent : Theme.white(0.1)
                        Behavior on border.color { ColorAnimation { duration: Theme.durHover } }
                        contentUnderBorder: true
                        Image {
                            anchors.fill: parent
                            source: tile.modelData.thumb
                            sourceSize.width: 320
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Rectangle {
                            visible: tile.applied
                            x: parent.width - Theme.s(24); y: Theme.s(6)
                            width: Theme.s(18); height: Theme.s(18); radius: Theme.s(9)
                            color: Theme.text
                            Icon { anchors.centerIn: parent; path: Icons.check; size: Theme.s(11); stroke: 2.4; color: Theme.ink }
                        }
                    }
                    Text {
                        width: parent.width
                        leftPadding: Theme.s(2)
                        elide: Text.ElideRight
                        text: tile.modelData.title
                        color: tile.selected || hov.hovered ? Theme.text : Theme.muted
                        font.family: Theme.sans
                        font.pixelSize: Theme.s(11)
                        font.weight: tile.selected ? Font.DemiBold : Font.Normal
                    }
                }
            }

            Text {
                visible: wpp.shown.length === 0
                anchors.centerIn: parent
                text: wpp.videos ? "No video wallpapers" : "No wallpapers match"
                color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12)
            }
        }
    }

    // the display dropdown, over the grid
    Rectangle {
        visible: wpp.monitorMenu
        // under the button (its row sits 14px inside the panel)
        x: Theme.s(14) + monBtn.x
        y: Theme.s(14) + monBtn.y + monBtn.height + Theme.s(6)
        width: Math.max(monBtn.width, Theme.s(150))
        height: menuCol.implicitHeight + Theme.s(8)
        radius: Theme.s(12)
        color: "#18181B"
        border.width: 1
        border.color: Theme.white(0.1)
        z: 20
        // keep clicks on the menu from reaching the tiles underneath
        MouseArea { anchors.fill: parent }
        Column {
            id: menuCol
            x: Theme.s(4); y: Theme.s(4)
            width: parent.width - Theme.s(8)
            Repeater {
                model: ["All"].concat(Hyprland.monitors.values.map(m => m.name))
                delegate: HoverButton {
                    required property var modelData
                    width: menuCol.width
                    height: Theme.s(32)
                    radius: Theme.s(8)
                    onClicked: { wpp.monitor = modelData; wpp.monitorMenu = false; wpp.forceActiveFocus(); }
                    Text {
                        x: Theme.s(10); anchors.verticalCenter: parent.verticalCenter
                        text: wpp.monitorLabel(modelData) + (modelData === "All" ? "" : "  ·  " + modelData)
                        color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                    }
                    Icon {
                        visible: wpp.monitor === modelData
                        anchors.right: parent.right; anchors.rightMargin: Theme.s(10); anchors.verticalCenter: parent.verticalCenter
                        path: Icons.check; size: Theme.s(12); stroke: 2.2; color: Theme.accent
                    }
                }
            }
        }
    }

    // compact segmented choice
    component Segmented: Rectangle {
        id: seg
        property var options: []
        property string current: ""
        signal picked(string o)
        implicitWidth: segRow.implicitWidth + Theme.s(6)
        implicitHeight: Theme.s(34)
        radius: Theme.s(11)
        color: Theme.white(0.07)
        Row {
            id: segRow
            x: Theme.s(3); y: Theme.s(3)
            spacing: Theme.s(2)
            Repeater {
                model: seg.options
                delegate: HoverButton {
                    required property var modelData
                    readonly property bool on: seg.current === modelData
                    width: segText.implicitWidth + Theme.s(22)
                    height: Theme.s(28)
                    radius: Theme.s(8)
                    hoverFill: false
                    color: on ? Theme.text : "transparent"
                    onClicked: seg.picked(modelData)
                    Text { id: segText; anchors.centerIn: parent; text: modelData; color: parent.on ? Theme.ink : Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium }
                }
            }
        }
    }
}
