import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// Settings: a 1240x1180 panel in the middle of the main screen (radius 26). Sidebar
// (236px) with the sections, content on the right, scrolling. Opened from the
// control center's gear or the launcher; Escape, the X or a click outside closes it.
Item {
    id: st
    readonly property bool open: IslandState.settingsOpen
    width: Math.min(Theme.s(1240), parent ? parent.width - Theme.s(48) : Theme.s(1240))
    // tall enough that Monitors (the longest section) fits without scrolling
    height: Math.min(Theme.s(1180), parent ? parent.height - Theme.s(120) : Theme.s(1180))

    // panel drop (motion sheet), from the center
    visible: opacity > 0
    opacity: 0
    transform: Translate { id: shift; y: 0 }
    ParallelAnimation {
        id: inAnim
        NumberAnimation { target: st; property: "opacity"; from: 0; to: 1; duration: Theme.reduceMotion ? 150 : Theme.durDrop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
        NumberAnimation { target: shift; property: "y"; from: Theme.reduceMotion ? 0 : -8; to: 0; duration: Theme.durDrop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
        NumberAnimation { target: st; property: "scale"; from: Theme.reduceMotion ? 1 : 0.98; to: 1; duration: Theme.durDrop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
    }
    NumberAnimation { id: outAnim; target: st; property: "opacity"; to: 0; duration: Theme.durHide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
    onOpenChanged: {
        if (open) { outAnim.stop(); inAnim.restart(); forceActiveFocus(); flick.contentY = 0; tabletCheck.running = true; }
        else { inAnim.stop(); outAnim.restart(); }
    }
    Component.onCompleted: if (open) { opacity = 1; forceActiveFocus(); }
    focus: open
    // an island tool takes over
    Connections {
        target: IslandState
        function onModeChanged() { if (IslandState.isTool(IslandState.mode)) IslandState.closeSettings(); }
    }
    Keys.onEscapePressed: IslandState.closeSettings()

    // Tablet only shows when Hyprland sees a drawing tablet (checked each time
    // Settings opens, so plugging one in makes the section appear)
    property var tablets: []
    Process {
        id: tabletCheck
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { st.tablets = JSON.parse(text).tablets || []; } catch (e) { st.tablets = []; }
                if (st.tablets.length === 0 && IslandState.settingsSection === "tablet") IslandState.settingsSection = "themes";
            }
        }
    }
    readonly property var nav: allNav.filter(n => (n.key !== "tablet" || tablets.length > 0) && (n.key !== "power" || Power.hasBattery))
    readonly property var allNav: [
        { key: "themes", label: "Themes", icon: "M4 6 H20 V18 H4 Z M4 10 H20 M8 14 H11" },
        { key: "appearance", label: "Appearance", icon: "M12 3 A9 9 0 1 0 12 21 C13 21 13.5 20.2 13.5 19.4 C13.5 18.5 12.9 18.2 12.9 17.4 C12.9 16.5 13.6 16 14.5 16 H17 A4 4 0 0 0 21 12 C21 7 17 3 12 3 Z M7.5 11 L7.6 11 M10 7.5 L10.1 7.5 M14.5 7.5 L14.6 7.5" },
        { key: "keybinds", label: "Keybinds", icon: "M3 7 H21 V17 H3 Z M7 11 L7.1 11 M10 11 L10.1 11 M13 11 L13.1 11 M16 11 L16.1 11 M8 14 H16" },
        { key: "monitors", label: "Monitors", icon: "M3 4 H21 V16 H3 Z M9 20 H15 M12 16 V20" },
        { key: "tablet", label: "Tablet", icon: "M3 5 H21 V19 H3 Z M7 5 V19 M5 8 L5.1 8 M5 16 L5.1 16 M14 15 L17 9" },
        { key: "widgets", label: "Widgets", icon: "M4 4 H11 V11 H4 Z M13 4 H20 V11 H13 Z M4 13 H11 V20 H4 Z M13 13 H20 V20 H13 Z" },
        { key: "login", label: "Login screen", icon: "M5 11 H19 V20 H5 Z M8 11 V8 A4 4 0 0 1 16 8 V11 M12 15 V16.5" },
        { key: "notifications", label: "Notifications", icon: "M6 16 V11 A6 6 0 0 1 18 11 V16 L19.5 18 H4.5 Z M10 20 H14" },
        { key: "games", label: "Games", icon: "M6 10h4M8 8v4M15 11h.01M18 9h.01M7 6h10a4 4 0 014 4v4a4 4 0 01-4 4H7a4 4 0 01-4-4v-4a4 4 0 014-4z" },
        { key: "ai", label: "AI", icon: "M12 3 L13.8 7.7 L18.5 9.5 L13.8 11.3 L12 16 L10.2 11.3 L5.5 9.5 L10.2 7.7 Z M18 15 L18.8 17.2 L21 18 L18.8 18.8 L18 21 L17.2 18.8 L15 18 L17.2 17.2 Z" },
        { key: "power", label: "Power", icon: "M7 7 H17 V18 H7 Z M10 4 H14 V7 M12 10 L10.5 13 H13.5 L12 16" },
        { key: "system", label: "System", icon: "M4 20 V10 M10 20 V4 M16 20 V13 M22 20 H2" },
        { key: "apps", label: "Apps and Hyprland", icon: "M5 5 H11 V11 H5 Z M13 5 H19 V11 H13 Z M5 13 H11 V19 H5 Z M13 13 H19 V19 H13 Z" }
    ]

    Surface { anchors.fill: parent; kind: "panel"; radius: Theme.s(26) }
    // clicks on the panel stay here (outside it closes)
    MouseArea { anchors.fill: parent }

    // ---------- sidebar ----------
    Item {
        id: side
        width: Theme.s(236)
        height: parent.height
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.white(0.07) }
        Column {
            x: Theme.s(12); y: Theme.s(20)
            width: parent.width - Theme.s(24)
            spacing: Theme.s(3)
            Row {
                leftPadding: Theme.s(10)
                bottomPadding: Theme.s(16)
                spacing: Theme.s(10)
                Icon { anchors.verticalCenter: parent.verticalCenter; path: Icons.sliders; size: Theme.s(18); color: Theme.accent }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Settings"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.type.h2[0]; font.weight: Theme.type.h2[1] }
            }
            Repeater {
                model: st.nav
                delegate: HoverButton {
                    id: nb
                    required property var modelData
                    readonly property bool on: IslandState.settingsSection === modelData.key
                    width: parent.width
                    height: Theme.s(40)
                    radius: Theme.s(11)
                    hoverFill: false
                    color: on ? Theme.white(0.1) : hovered ? Theme.white(0.06) : "transparent"
                    onClicked: { IslandState.settingsSection = nb.modelData.key; flick.contentY = 0; }
                    Row {
                        anchors.left: parent.left; anchors.leftMargin: Theme.s(12)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s(11)
                        Icon { anchors.verticalCenter: parent.verticalCenter; path: nb.modelData.icon; color: nb.on ? Theme.text : Theme.text2 }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: nb.modelData.label
                            color: nb.on ? Theme.text : Theme.text2
                            font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: nb.on ? Font.Medium : Font.Normal
                        }
                    }
                }
            }
        }
    }

    // ---------- content ----------
    Flickable {
        id: flick
        anchors.left: side.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 1
        anchors.bottomMargin: footerBar.visible ? footerBar.height : 1
        clip: true
        contentHeight: content.implicitHeight + Theme.s(58)
        boundsBehavior: Flickable.StopAtBounds
        WheelScroll {}
        Loader {
            id: content
            x: Theme.s(32); y: Theme.s(26)
            width: Math.min(flick.width - Theme.s(64), ["themes", "tablet"].indexOf(IslandState.settingsSection) >= 0 ? Theme.s(10000) : Theme.s(820))
            sourceComponent: ({
                themes: themesC, appearance: appearanceC, keybinds: keybindsC, monitors: monitorsC,
                tablet: tabletC, system: systemC, apps: appsC, ai: aiC, widgets: widgetsC, games: gamesC, notifications: notificationsC, power: powerC, login: loginC
            })[IslandState.settingsSection] || themesC
        }
    }

    // a section's footer (Monitors: Apply / Keep), always visible at the bottom
    Item {
        id: footerBar
        readonly property Item host: content.item && content.item.footer ? content.item.footer : null
        visible: host !== null
        anchors.left: side.right; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: Theme.s(64)
        Rectangle { width: parent.width; height: 1; color: Theme.white(0.07) }
        onHostChanged: if (host) { host.parent = footerBar; host.visible = true; host.anchors.fill = undefined; host.x = 32; host.width = Qt.binding(() => Math.min(footerBar.width - 64, 820)); host.anchors.verticalCenter = footerBar.verticalCenter; }
    }

    HoverButton {
        anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: Theme.s(16)
        implicitWidth: Theme.s(32); implicitHeight: Theme.s(32); radius: Theme.s(16)
        onClicked: IslandState.closeSettings()
        Icon { anchors.centerIn: parent; path: Icons.close; size: Theme.s(14); color: Theme.muted }
    }

    Component { id: themesC; ThemesSection {} }
    Component { id: appearanceC; AppearanceSection {} }
    Component { id: keybindsC; KeybindsSection {} }
    Component { id: systemC; SystemSection {} }
    Component { id: monitorsC; MonitorsSection {} }
    Component { id: tabletC; TabletSection {} }
    Component { id: appsC; AppsSection {} }
    Component { id: aiC; AISection {} }
    Component { id: widgetsC; WidgetsSection {} }
    Component { id: gamesC; GamesSection {} }
    Component { id: notificationsC; NotificationsSection {} }
    Component { id: powerC; PowerSection {} }
    Component { id: loginC; LoginScreenSection {} }
}
