import QtQuick
import ".."
import "../components"
import "../services"

// One widget on the desktop: its card (none for the clock), and in edit mode an
// outline, drag to move, the corner handle to resize (or step through sizes), and −
// to remove it (all saved).
Item {
    id: f
    property string type
    property real s: 1                 // "scale" widgets: a multiple of the design's size
    property string size: ""           // "sizes" widgets: which layout (small / medium / large)
    readonly property var spec: Widgets.spec(type)
    readonly property var sizes: spec.sizes || []
    readonly property var range: spec.scale || null
    readonly property var box: spec.box || null      // [minW, minH, maxW, maxH], design pixels
    property real boxW: 0
    property real boxH: 0
    readonly property real k: range ? Math.max(range[0], Math.min(range[1], s)) : 1
    readonly property bool resizable: sizes.length > 1 || range !== null || box !== null
    readonly property bool card: type !== "clock"
    onSizeChanged: if (loader.item && !Theme.reduceMotion) reveal.restart()
    readonly property real baseW: loader.item ? loader.item.implicitWidth : 0
    readonly property real baseH: loader.item ? loader.item.implicitHeight : 0
    width: baseW * k
    height: baseH * k

    // the widget at its design size, scaled as a whole so it keeps its look at any size
    Item {
        width: f.baseW; height: f.baseH
        // stepping between sizes: the card morphs (Tide's spring, island timing) and the
        // new layout fades in; drags of scale / box widgets follow the hand directly
        Behavior on width { enabled: f.sizes.length > 0 && !Theme.reduceMotion; NumberAnimation { duration: Theme.durMorph; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        Behavior on height { enabled: f.sizes.length > 0 && !Theme.reduceMotion; NumberAnimation { duration: Theme.durMorph; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        scale: f.k
        transformOrigin: Item.TopLeft
        Surface { visible: f.card; anchors.fill: parent; kind: "card"; glass: Widgets.cardGlass; radius: Theme.s(22) }
        Loader {
            id: loader
            anchors.fill: parent
            NumberAnimation on opacity { id: reveal; running: false; from: 0; to: 1; duration: Theme.durReveal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
            // sized widgets read their layout from "size"
            onLoaded: {
                if (f.sizes.length && item.size !== undefined) item.size = Qt.binding(() => f.size);
                if (f.box) { item.boxW = Qt.binding(() => f.boxW); item.boxH = Qt.binding(() => f.boxH); }
            }
        source: ({ clock: "ClockWidget.qml", weather: "WeatherWidget.qml", nowplaying: "NowPlayingWidget.qml",
                   notes: "NotesWidget.qml", calendar: "CalendarWidget.qml", status: "StatusWidget.qml", system: "SystemWidget.qml", printer: "PrinterWidget.qml" })[f.type] || ""
        }
    }

    // edit mode
    Rectangle {
        visible: Widgets.editing
        anchors.fill: parent
        anchors.margins: -Theme.s(6)
        radius: Theme.s(26)
        color: "transparent"
        border.width: 1.5
        border.color: Theme.white(0.5)
    }
    MouseArea {
        anchors.fill: parent
        enabled: Widgets.editing
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        drag.target: f
        drag.threshold: 2
        onReleased: Widgets.move(f.type, f.x, f.y)
    }
    // resize: drag the corner. Sized widgets step through their layouts (one step per
    // 70px of drag, a label says which); scale widgets grow or shrink within their range.
    Rectangle {
        id: handle
        visible: Widgets.editing && f.resizable
        x: f.width - Theme.s(14); y: f.height - Theme.s(14)
        width: Theme.s(22); height: Theme.s(22); radius: Theme.s(11)
        color: Theme.text
        Icon { anchors.centerIn: parent; path: "M9 15 L15 9 M13 15 L15 13"; size: Theme.s(14); stroke: 2.2; color: Theme.ink }
        MouseArea {
            id: rz
            anchors.fill: parent
            anchors.margins: -Theme.s(6)
            cursorShape: Qt.SizeFDiagCursor
            property real startS: 1
            property int startI: 0
            property real startW: 0
            property real startH: 0
            property point start
            onPressed: m => {
                startS = f.k;
                startI = Math.max(0, f.sizes.indexOf(f.size));
                startW = f.boxW; startH = f.boxH;
                start = mapToItem(f.parent, m.x, m.y);
            }
            onPositionChanged: m => {
                const p = mapToItem(f.parent, m.x, m.y);
                if (f.box) {
                    f.boxW = Math.max(f.box[0], Math.min(f.box[2], startW + (p.x - start.x) / Theme.uiScale));
                    f.boxH = Math.max(f.box[1], Math.min(f.box[3], startH + (p.y - start.y) / Theme.uiScale));
                } else if (f.sizes.length) {
                    const step = Math.round(((p.x - start.x) + (p.y - start.y)) / 2 / Theme.s(70));
                    f.size = f.sizes[Math.max(0, Math.min(f.sizes.length - 1, startI + step))];
                } else {
                    const w = f.baseW * startS + (p.x - start.x);
                    f.s = Math.max(f.range[0], Math.min(f.range[1], w / f.baseW));
                }
            }
            onReleased: f.box ? Widgets.setBox(f.type, f.boxW, f.boxH) : f.sizes.length ? Widgets.setSize(f.type, f.size) : Widgets.resize(f.type, f.s)
        }
        // while dragging a sized widget: which layout it's on
        Rectangle {
            visible: rz.pressed && f.sizes.length > 0
            anchors.right: parent.left; anchors.rightMargin: Theme.s(8)
            anchors.verticalCenter: parent.verticalCenter
            width: szl.implicitWidth + Theme.s(18); height: Theme.s(24); radius: Theme.s(12)
            color: Theme.text
            Text { id: szl; anchors.centerIn: parent; text: f.size.charAt(0).toUpperCase() + f.size.slice(1); color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(11); font.weight: Font.DemiBold }
        }
    }
    HoverButton {
        visible: Widgets.editing
        x: -Theme.s(8); y: -Theme.s(8)
        width: Theme.s(24); height: Theme.s(24); radius: Theme.s(12)
        hoverFill: false
        color: Theme.text
        onClicked: Widgets.remove(f.type)
        Rectangle { anchors.centerIn: parent; width: Theme.s(12); height: Theme.s(2.4); radius: 1; color: Theme.ink }
    }
}
