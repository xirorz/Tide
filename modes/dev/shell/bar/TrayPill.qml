import QtQuick
import "../components/Icons.js" as Icons
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import ".."
import "../components"
import "../services"

// System tray plus the updates count (hidden when there are none).
Pill {
    id: root
    padH: Theme.s(8)
    spacing: Theme.s(2)
    visible: SystemTray.items.values.length > 0 || Updates.listed > 0 || Updates.phase !== "list"
    property bool panelOpen: false
    signal toggled()

    // an icon's menu: the bar shows it (bar/TrayMenu.qml)
    signal menuRequested(var menu, var item)

    Repeater {
        model: SystemTray.items
        delegate: HoverButton {
            id: btn
            required property var modelData
            Layout.preferredWidth: Theme.s(28)
            Layout.preferredHeight: Theme.s(28)
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

            // tray icons are tinted to the design's #C7C7CC so they match the stroke icons
            IconImage {
                id: img
                anchors.centerIn: parent
                implicitSize: Theme.s(16)
                source: btn.modelData.icon
                visible: false
            }
            MultiEffect {
                anchors.fill: img
                source: img
                colorization: 1.0
                colorizationColor: Theme.text2
                brightness: 1.0
            }

            // hover: the app's name (and what its tooltip says, when that's more) in a small
            // toast under the icon, like the device battery toast. Apps name themselves in
            // different places: a title ("qBittorrent"), only a tooltip ("Claude"), or an id
            // ("TelegramDesktop", "privateinternetaccess"); the most readable one wins.
            readonly property string tipText: (btn.modelData.tooltipTitle || "").split("\n")[0].trim()
            readonly property string appName: {
                const d = btn.modelData;
                const words = n => n.replace(/[_-]+/g, " ").replace(/([a-z]{2,})([A-Z])/g, "$1 $2")
                                     .replace(/\b(status icon|client|tray|indicator)\b/gi, "").replace(/\s+\d+$/, "").trim();
                const title = (d.title || "").trim();
                const tipHead = tipText.split(":")[0].trim();
                // a run-together lowercase title the tooltip spells out ("privateinternetaccess")
                if (title && tipHead && tipHead.replace(/\s+/g, "").toLowerCase() === title.toLowerCase()) return tipHead;
                if (title) return words(title);
                if (tipHead) return tipHead;
                return words(d.id || "");
            }
            // what the tooltip adds after the name (speeds, status), on the same line: not
            // when it only repeats the name ("Telegram Desktop (3)", "Shield TV launcher")
            readonly property string appMore: {
                const t = tipText.replace(/\u00a0/g, " ");
                if (!t) return "";
                const low = t.toLowerCase(), name = appName.toLowerCase();
                if (low.indexOf(name + ":") === 0) return t.slice(appName.length + 1).trim();
                if (low.indexOf(name) === 0) return "";
                return t;
            }
            Item {
                visible: btn.hovered && btn.appName !== ""
                width: toastCol.implicitWidth + Theme.s(20)
                height: toastCol.implicitHeight + Theme.s(12)
                x: (btn.width - width) / 2
                y: Theme.s(36)
                z: 10
                Surface { anchors.fill: parent; kind: "panel"; radius: Theme.s(10) }
                Text {
                    id: toastCol
                    anchors.centerIn: parent
                    textFormat: Text.StyledText
                    text: btn.appName.charAt(0).toUpperCase() + btn.appName.slice(1)
                          + (btn.appMore ? " <font color='" + Theme.muted + "'>· " + btn.appMore.replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</font>" : "")
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: Theme.s(12)
                }
            }

            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton && !btn.modelData.onlyMenu) btn.modelData.activate();
                else if (mouse.button === Qt.MiddleButton) btn.modelData.secondaryActivate();
                else if (btn.modelData.hasMenu) {
                    root.menuRequested(btn.modelData.menu, btn);
                }
            }
        }
    }

    // the updates count: opens the updates panel (its only way in). While updating it
    // shows a spinner and the percent, then a check mark until the panel is closed.
    HoverButton {
        // also with only held-back packages (no number), so they can be released
        visible: Updates.listed > 0 || Updates.phase !== "list"
        Layout.preferredHeight: Theme.s(28)
        Layout.preferredWidth: upRow.implicitWidth + Theme.s(18)
        radius: Theme.s(14)
        hoverFill: false
        color: root.panelOpen ? Theme.white(0.14) : hovered ? Theme.white(0.08) : "transparent"
        onClicked: root.toggled()
        Row {
            id: upRow
            anchors.centerIn: parent
            spacing: Theme.s(5)
            Rectangle {
                visible: Updates.phase === "busy"
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.s(12); height: Theme.s(12); radius: Theme.s(6)
                color: "transparent"
                border.width: 2
                border.color: Theme.white(0.25)
                // the spinning accent quarter (the design's border-top)
                Canvas {
                    id: arc
                    anchors.fill: parent
                    onPaint: {
                        const c = getContext("2d");
                        c.reset();
                        c.scale(width / 12, height / 12);
                        c.lineWidth = 2;
                        c.strokeStyle = Theme.accent;
                        c.beginPath();
                        c.arc(6, 6, 5, -Math.PI / 2, 0);
                        c.stroke();
                    }
                    Connections { target: Theme; function onAccentChanged() { arc.requestPaint(); } }
                    RotationAnimation on rotation {
                        running: Updates.phase === "busy" && !Theme.reduceMotion
                        from: 0; to: 360; duration: 900; loops: Animation.Infinite
                    }
                }
            }
            Icon { visible: Updates.phase !== "busy"; path: Updates.phase === "done" ? Icons.check : Icons.updates; anchors.verticalCenter: parent.verticalCenter }
            Text {
                visible: Updates.phase !== "done" && (Updates.phase === "busy" || Updates.count > 0)
                anchors.verticalCenter: parent.verticalCenter
                text: Updates.phase === "busy" ? Updates.pct + "%" : Updates.count
                color: Theme.text
                font.family: Theme.mono
                font.pixelSize: Theme.s(12)
            }
        }
    }
}
