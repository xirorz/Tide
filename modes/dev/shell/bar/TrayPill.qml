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
    visible: SystemTray.items.values.length > 0 || Updates.count > 0 || Updates.phase !== "list"
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
        visible: Updates.count > 0 || Updates.phase !== "list"
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
                visible: Updates.phase !== "done"
                anchors.verticalCenter: parent.verticalCenter
                text: Updates.phase === "busy" ? Updates.pct + "%" : Updates.count
                color: Theme.text
                font.family: Theme.mono
                font.pixelSize: Theme.s(12)
            }
        }
    }
}
