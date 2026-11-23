import QtQuick
import Quickshell
import Quickshell.Widgets
import "../components/Icons.js" as Icons
import ".."
import "../components"

// A tray icon's menu drawn by Tide (the app's own menu looks out of place): a panel
// under the icon with the entries, separators, check marks and radio dots. A submenu
// opens in place with a back row. It's one of the bar's panels (bar.trayOpen), so a
// click outside or Escape closes it like the others.
Item {
    id: tm
    property var anchorItem: null
    signal closeRequested()
    property var stack: []                  // the menus opened so far: the last is shown
    readonly property var current: stack.length ? stack[stack.length - 1] : null
    visible: false
    width: Theme.s(260)
    height: list.implicitHeight + Theme.s(12)

    function open(menu, item) {
        if (!menu) return;
        anchorItem = item;
        const p = item.mapToItem(parent, 0, item.height + Theme.s(6));
        // right edge kept on screen: the tray sits at the right end of the bar
        x = Math.max(Theme.s(8), Math.min(p.x + item.width / 2 - width / 2, parent.width - width - Theme.s(8)));
        y = p.y;
        stack = [menu];
        visible = true;
        keys.forceActiveFocus();
    }
    function close() { visible = false; stack = []; closeRequested(); }
    function enter(entry) { stack = stack.concat([entry]); }
    function back() { if (stack.length > 1) stack = stack.slice(0, -1); }

    // one opener per level: a submenu lives only while its parent menu is open, so the
    // levels above stay open while a submenu is shown
    Instantiator {
        id: openers
        model: tm.stack.length
        delegate: QsMenuOpener { required property int index; menu: tm.stack[index] }
    }
    readonly property var shown: openers.count > 0 ? openers.objectAt(openers.count - 1) : null

    Surface {
        anchors.fill: parent
        kind: "panel"
        radius: Theme.s(14)
    }
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: tm.stack.length > 1 ? tm.back() : tm.close()
    }
    Column {
        id: list
        x: Theme.s(6); y: Theme.s(6)
        width: parent.width - Theme.s(12)

        // in a submenu: back
        HoverButton {
            visible: tm.stack.length > 1
            width: parent.width; height: Theme.s(34); radius: Theme.s(9)
            onClicked: tm.back()
            Row {
                anchors.verticalCenter: parent.verticalCenter; x: Theme.s(10)
                spacing: Theme.s(8)
                Icon { anchors.verticalCenter: parent.verticalCenter; path: "M15 6 L9 12 L15 18"; size: Theme.s(14); color: Theme.muted }
                Text { anchors.verticalCenter: parent.verticalCenter; text: tm.current && tm.current.text ? tm.current.text.replace(/_/g, "") : "Back"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
            }
        }
        Rectangle { visible: tm.stack.length > 1; width: parent.width; height: Theme.s(9); color: "transparent"
            Rectangle { anchors.centerIn: parent; width: parent.width - Theme.s(16); height: 1; color: Theme.white(0.08) } }

        Repeater {
            model: tm.shown ? tm.shown.children : []
            delegate: Item {
                id: row
                required property var modelData
                width: list.width
                height: modelData.isSeparator ? Theme.s(9) : Theme.s(34)

                Rectangle {
                    visible: row.modelData.isSeparator
                    anchors.centerIn: parent
                    width: parent.width - Theme.s(16); height: 1
                    color: Theme.white(0.08)
                }
                HoverButton {
                    visible: !row.modelData.isSeparator
                    anchors.fill: parent
                    radius: Theme.s(9)
                    enabled: row.modelData.enabled
                    opacity: enabled ? 1 : 0.4
                    onClicked: {
                        if (row.modelData.hasChildren) { tm.enter(row.modelData); return; }
                        row.modelData.triggered();
                        tm.close();
                    }
                    // check box / radio, or the entry's icon
                    Item {
                        id: lead
                        x: Theme.s(10); anchors.verticalCenter: parent.verticalCenter
                        width: Theme.s(16); height: width
                        visible: row.modelData.buttonType !== QsMenuButtonType.None || row.modelData.icon !== ""
                        Rectangle {
                            visible: row.modelData.buttonType === QsMenuButtonType.CheckBox
                            anchors.fill: parent; radius: Theme.s(4)
                            color: row.modelData.checkState === Qt.Checked ? Theme.accent : "transparent"
                            border.width: row.modelData.checkState === Qt.Checked ? 0 : 1.5
                            border.color: Theme.white(0.35)
                            Icon { visible: row.modelData.checkState === Qt.Checked; anchors.centerIn: parent; path: Icons.check; size: Theme.s(12); stroke: 2.6; color: Theme.ink }
                        }
                        Rectangle {
                            visible: row.modelData.buttonType === QsMenuButtonType.RadioButton
                            anchors.fill: parent; radius: width / 2
                            color: "transparent"; border.width: 1.5
                            border.color: row.modelData.checkState === Qt.Checked ? Theme.accent : Theme.white(0.35)
                            Rectangle { visible: row.modelData.checkState === Qt.Checked; anchors.centerIn: parent; width: parent.width * 0.5; height: width; radius: width / 2; color: Theme.accent }
                        }
                        IconImage {
                            visible: row.modelData.buttonType === QsMenuButtonType.None && row.modelData.icon !== ""
                            anchors.fill: parent
                            source: row.modelData.icon
                        }
                    }
                    Text {
                        x: lead.visible ? Theme.s(36) : Theme.s(12)
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - Theme.s(28)
                        elide: Text.ElideRight
                        // "_" marks the keyboard letter in these menus: not shown
                        text: (row.modelData.text || "").replace(/_(.)/g, "$1")
                        color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13)
                    }
                    Icon {
                        visible: row.modelData.hasChildren
                        anchors.right: parent.right; anchors.rightMargin: Theme.s(10); anchors.verticalCenter: parent.verticalCenter
                        path: "M9 6 L15 12 L9 18"; size: Theme.s(14); color: Theme.muted
                    }
                }
            }
        }
    }
}
