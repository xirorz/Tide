import QtQuick
import "../components/Icons.js" as Icons
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import ".."
import "../components"
import "../services"

// Right corner: music wave while playing, device batteries (each icon fills with
// its own charge), sound, notifications, Ethernet or Wi-Fi.
// Clicking opens the control center (built next). Right-click the speaker opens the audio app.
Item {
    id: root
    property bool open: false
    signal toggled()

    implicitHeight: Theme.s(38)
    implicitWidth: row.implicitWidth + Theme.s(28)

    readonly property bool playing: Mpris.players.values.some(p => p.isPlaying)

    // wireless batteries straight from the kernel (services/Peripherals.qml); UPower
    // only noticed a newly connected headset about a minute later
    readonly property var devices: Peripherals.devices.filter(d => root.iconFor(d) !== "")
    function iconFor(d) {
        return ({ headset: Icons.headset, mouse: Icons.mouse, controller: Icons.controller, phone: Icons.phone })[d.kind] || "";
    }
    function nameFor(d) {
        return ({ headset: "Headset", mouse: "Mouse", controller: "Controller", phone: "Phone" })[d.kind] || d.model;
    }
    function level(d) { return d.percent / 100; }

    Surface { anchors.fill: parent; kind: "bar"; radius: Theme.s(19) }
    Rectangle {
        anchors.fill: parent
        radius: Theme.s(19)
        color: "transparent"
        border.width: 1
        border.color: Theme.white(0.45)
        visible: root.open
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }

    RowLayout {
        id: row
        x: Theme.s(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.s(12)

        // music bars, colors from the wallpaper palette
        EqBars {
            visible: root.playing
            running: root.playing
            Layout.preferredHeight: Theme.s(12)
        }
        Divider { visible: root.playing }

        Repeater {
            model: root.devices
            delegate: FillIcon {
                id: dev
                required property var modelData
                path: root.iconFor(modelData)
                level: root.level(modelData)

                // hover only; clicks still reach the cluster underneath
                HoverHandler { id: devHover }

                // battery toast, 32px under the icon like the resource hover card
                Item {
                    visible: devHover.hovered
                    width: toastRow.implicitWidth + Theme.s(20)
                    height: toastRow.implicitHeight + Theme.s(12)
                    x: (dev.width - width) / 2
                    y: Theme.s(32)
                    z: 10

                    Surface { anchors.fill: parent; kind: "panel"; radius: Theme.s(10) }

                    Row {
                        id: toastRow
                        x: Theme.s(10); y: Theme.s(6)
                        Text {
                            text: root.nameFor(dev.modelData) + " · "
                            color: Theme.text
                            font.family: Theme.sans
                            font.pixelSize: Theme.s(12)
                        }
                        Text {
                            text: Math.round(root.level(dev.modelData) * 100) + "%"
                            color: Theme.text
                            font.family: Theme.mono
                            font.pixelSize: Theme.s(12)
                        }
                    }
                }
            }
        }
        Divider { visible: root.devices.length > 0 }

        Icon {
            path: Icons.volume
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["sh", "-c", Theme.audioApp])
            }
        }

        Item {
            implicitWidth: Theme.s(16)
            implicitHeight: Theme.s(16)
            Icon { path: Icons.bell }
            // unread dot: notifications that arrived since the control center was last opened
            Rectangle {
                visible: Notifications.unseen > 0
                // "bellDotSize" in theme.json (10px), with a 2px ring in the pill's color
                readonly property int size: Theme.opt("bellDotSize", Theme.s(10))
                x: Theme.s(16) - size + Theme.s(3); y: -Theme.s(3)
                width: size; height: size; radius: size / 2
                color: Theme.accent
                border.width: 2
                border.color: Theme.surface === "glass" ? "#1C1C1E" : Theme.barFill
            }
        }

        Icon {
            visible: Net.kind !== "none"
            path: Net.kind === "wifi" ? Icons.wifi : Icons.ethernet
        }
    }

    component Divider: Rectangle {
        Layout.preferredWidth: 1
        Layout.preferredHeight: Theme.s(14)
        color: Theme.white(0.14)
    }
}
