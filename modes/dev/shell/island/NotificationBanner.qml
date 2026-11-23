import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// The island's notification state (500x92): the newest notification, and while more
// came in during the same banner a stacked card behind the icon, a count badge, a
// "+N more" line and View all. New ones replace the content in place, never queue.
Item {
    id: nb
    readonly property var items: IslandState.banner
    readonly property var cur: items.length > 0 ? items[items.length - 1] : null
    readonly property bool multi: items.length > 1

    readonly property string iconSource: {
        if (!cur) return "";
        if (cur.image) return cur.image;
        if (cur.appIcon) return cur.appIcon.indexOf("/") === 0 || cur.appIcon.indexOf("file:") === 0 ? cur.appIcon : Quickshell.iconPath(cur.appIcon, true);
        const e = cur.desktopEntry ? DesktopEntries.byId(cur.desktopEntry) : null;
        return e && e.icon ? Quickshell.iconPath(e.icon, true) : "";
    }
    // buttons the notification offers besides its default click
    readonly property var acts: cur && cur.ref && cur.ref.actions ? cur.ref.actions.filter(a => a.identifier !== "default") : []
    function title(it) { return it.appName || it.summary || "Notification"; }
    function bodyOf(it) {
        const b = (it.body || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim();
        if (it.appName && it.summary) return b ? it.summary + " · " + b : it.summary;
        return b;
    }
    // "+2 more · Local agent, 3D printer": the earlier ones, newest first
    readonly property string more: {
        if (!multi) return "";
        const earlier = items.slice(0, -1).reverse().map(title);
        return "+" + earlier.length + " more · " + earlier.join(", ");
    }

    // the timeout pauses while the cursor is anywhere on the banner. MouseArea hover
    // (unlike HoverHandler) resets when the banner hides, so it can't get stuck on.
    Binding {
        target: IslandState
        property: "bannerHovered"
        value: nb.visible && (bannerArea.containsMouse || viewAllBtn.hovered || dismissBtn.hovered || actRow.hovered)
    }
    // the whole banner runs the notification's default action
    MouseArea {
        id: bannerArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const n = nb.cur ? nb.cur.ref : null;
            IslandState.close();
            if (n) Notifications.activate(n);
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.s(14)
        anchors.rightMargin: Theme.s(14)
        spacing: Theme.s(14)

        // icon, with the stacked card and count badge while several came in
        Item {
            implicitWidth: Theme.s(52)
            implicitHeight: Theme.s(52)
            Rectangle {
                visible: nb.multi
                x: Theme.s(6); y: -Theme.s(4)
                width: Theme.s(40); height: Theme.s(52); radius: Theme.s(14)
                color: Theme.white(0.1)
            }
            Rectangle {
                anchors.fill: parent
                radius: Theme.s(16)
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                IconImage {
                    anchors.centerIn: parent
                    visible: nb.iconSource !== ""
                    source: nb.iconSource
                    implicitSize: Theme.s(24)
                }
                Icon { anchors.centerIn: parent; visible: nb.iconSource === ""; path: Icons.bell; size: Theme.s(24); color: Theme.accent }
            }
            Rectangle {
                visible: nb.multi
                x: Theme.s(52) + Theme.s(6) - width
                y: -Theme.s(6)
                width: Math.max(Theme.s(20), countLbl.implicitWidth + Theme.s(10))
                height: Theme.s(20)
                radius: Theme.s(10)
                color: Theme.accent
                border.width: 2
                border.color: "#000000"
                Text {
                    id: countLbl
                    anchors.centerIn: parent
                    text: nb.items.length
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: Theme.s(11)
                    font.weight: Font.Medium
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.s(3)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: nb.cur ? nb.title(nb.cur) : ""
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: Theme.s(12)
                    font.weight: Font.DemiBold
                }
                Text { text: "now"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: nb.cur ? nb.bodyOf(nb.cur) : ""
                color: Theme.soft
                font.family: Theme.sans
                font.pixelSize: Theme.s(13)
            }
            Row {
                id: actRow
                property bool hovered: false
                visible: nb.acts.length > 0
                Layout.topMargin: Theme.s(6)
                spacing: Theme.s(8)
                Repeater {
                    model: nb.acts
                    delegate: HoverButton {
                        required property var modelData
                        required property int index
                        implicitWidth: actLbl.implicitWidth + Theme.s(24); implicitHeight: Theme.s(30); radius: Theme.s(9)
                        hoverFill: false
                        color: index === 0 ? (hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent) : Theme.white(hovered ? 0.16 : 0.1)
                        onHoveredChanged: actRow.hovered = hovered
                        onClicked: {
                            const n = nb.cur ? nb.cur.ref : null;
                            modelData.invoke();
                            IslandState.close();
                            if (n) n.dismiss();
                        }
                        Text { id: actLbl; anchors.centerIn: parent; text: modelData.text; color: index === 0 ? Theme.ink : Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium }
                    }
                }
            }
            Text {
                visible: nb.multi
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: nb.more
                color: Theme.muted
                font.family: Theme.sans
                font.pixelSize: Theme.s(11)
            }
        }

        HoverButton {
            id: viewAllBtn
            visible: nb.multi
            implicitWidth: viewAll.implicitWidth + Theme.s(24)
            implicitHeight: Theme.s(32)
            hoverFill: false
            color: Theme.accent
            onClicked: { IslandState.close(); IslandState.controlCenterRequested(); }
            Text { id: viewAll; anchors.centerIn: parent; text: "View all"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium }
        }
        HoverButton {
            id: dismissBtn
            implicitWidth: Theme.s(32)
            implicitHeight: Theme.s(32)
            hoverFill: false
            color: Theme.white(0.1)
            onClicked: IslandState.close()
            Icon { anchors.centerIn: parent; path: Icons.close; size: Theme.s(14) }
        }
    }
}
