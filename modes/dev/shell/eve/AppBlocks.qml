import QtQuick
import QtQuick.Layouts
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// An app's content in the AI panel, drawn from the AI API's display blocks
// (~/.config/Tide/docs/AI-API.md, "Apps"). Each block is a rounded card; any block may
// carry a small `label` and `icon` on top. Blocks Tide doesn't know are skipped.
// Tabs hold their own blocks, so this file loads itself for them.
Column {
    id: root
    property var blocks: []
    spacing: Theme.s(12)

    readonly property var known: ["hero", "cards", "stat", "progress", "rows", "list", "checklist", "table", "metrics", "tiles", "calendar", "tabs", "text", "terminal"]
    function toneColor(t) { return t === "critical" ? Theme.critical : t === "warning" ? Theme.warning : t === "good" ? "#30D158" : t === "muted" ? Theme.muted : Theme.accent; }
    // a picture tile was clicked: the panel opens its viewer
    signal openImage(string url, string name)
    function iconPath(name) { return EveData.appIcons[name] || ""; }

    Repeater {
        model: root.blocks.filter(b => b && root.known.indexOf(b.type) >= 0)
        delegate: Loader {
            id: blk
            required property var modelData
            width: root.width
            sourceComponent: ({ hero: heroC, cards: cardsC, tabs: tabsC })[modelData.type] || cardC
        }
    }

    // ---------- a plain card: label on top, then the block's own content ----------
    Component {
        id: cardC
        Rectangle {
            id: card
            readonly property var b: parent ? parent.modelData : ({})
            width: parent ? parent.width : 0
            height: cardCol.implicitHeight + Theme.s(32)
            radius: Theme.s(16)
            color: Theme.tile
            border.width: card.b.tone === "warning" || card.b.tone === "critical" ? 1 : 0
            border.color: Qt.rgba(root.toneColor(card.b.tone).r, root.toneColor(card.b.tone).g, root.toneColor(card.b.tone).b, 0.45)
            Column {
                id: cardCol
                x: Theme.s(16); y: Theme.s(16)
                width: parent.width - Theme.s(32)
                spacing: Theme.s(10)
                Row {
                    visible: !!card.b.label
                    spacing: Theme.s(7)
                    Icon { visible: !!card.b.icon; anchors.verticalCenter: parent.verticalCenter; path: root.iconPath(card.b.icon); size: Theme.s(13); color: Theme.accent }
                    Text { text: card.b.label || ""; color: card.b.tone === "warning" || card.b.tone === "critical" ? root.toneColor(card.b.tone) : Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: card.b.tone ? Font.DemiBold : Font.Normal }
                }
                Loader {
                    width: parent.width
                    readonly property var b: card.b
                    sourceComponent: ({ stat: statC, progress: progressC, rows: rowsC, list: listC, checklist: checkC, table: tableC,
                                        metrics: metricsC, tiles: tilesC, calendar: calendarC, text: textC, terminal: terminalC })[card.b.type] || null
                }
            }
        }
    }

    // ---------- hero: the big summary card ----------
    Component {
        id: heroC
        Rectangle {
            readonly property var b: parent ? parent.modelData : ({})
            width: parent ? parent.width : 0
            height: heroCol.implicitHeight + Theme.s(40)
            radius: Theme.s(18)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) }
                GradientStop { position: 0.6; color: Theme.tile }
            }
            Column {
                id: heroCol
                x: Theme.s(18); y: Theme.s(20)
                width: parent.width - Theme.s(36)
                spacing: Theme.s(10)
                Text { visible: !!parent.parent.b.eyebrow; text: parent.parent.b.eyebrow || ""; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                Text { width: parent.width; wrapMode: Text.Wrap; text: parent.parent.b.title || ""; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(22); font.weight: Font.Bold }
                Text { width: parent.width; wrapMode: Text.Wrap; textFormat: Text.MarkdownText; text: parent.parent.b.text || ""; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(15); lineHeight: 1.25 }
                HoverButton {
                    visible: !!parent.parent.b.speak && EveData.can("voice.speech")
                    width: listenRow.implicitWidth + Theme.s(28); height: Theme.s(34); radius: Theme.s(17)
                    hoverFill: false
                    color: hovered ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
                    onClicked: EveData.speaking ? EveData.stopSpeaking() : EveData.speak(parent.parent.b.speak)
                    Row {
                        id: listenRow
                        anchors.centerIn: parent
                        spacing: Theme.s(8)
                        Icon { anchors.verticalCenter: parent.verticalCenter; path: EveData.speaking ? "M7 7 H17 V17 H7 Z" : "M8 5 L19 12 L8 19 Z"; filled: true; size: Theme.s(12); color: Theme.ink }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: EveData.speaking ? "Stop" : "Listen"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold }
                    }
                }
                Text { visible: !!parent.parent.b.footnote; width: parent.width; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignRight; text: parent.parent.b.footnote || ""; color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
            }
        }
    }

    // ---------- cards: small cards two across ----------
    Component {
        id: cardsC
        Grid {
            readonly property var b: parent ? parent.modelData : ({})
            width: parent ? parent.width : 0
            columns: 2
            columnSpacing: Theme.s(10); rowSpacing: Theme.s(10)
            Repeater {
                model: parent.b.items || []
                delegate: Rectangle {
                    required property var modelData
                    width: (root.width - Theme.s(10)) / 2
                    height: Math.max(Theme.s(96), sc.implicitHeight + Theme.s(28))
                    radius: Theme.s(16)
                    color: Theme.tile
                    Column {
                        id: sc
                        x: Theme.s(14); y: Theme.s(14)
                        width: parent.width - Theme.s(28)
                        spacing: Theme.s(6)
                        Row {
                            spacing: Theme.s(7)
                            Icon { visible: !!modelData.icon; anchors.verticalCenter: parent.verticalCenter; path: root.iconPath(modelData.icon); size: Theme.s(13); color: Theme.accent }
                            Text { text: modelData.label || ""; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                        }
                        Row {
                            visible: !!modelData.value
                            spacing: Theme.s(8)
                            Text { text: modelData.value || ""; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(28) }
                            Text { anchors.baseline: parent.children[0].baseline; text: modelData.unit || ""; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
                        }
                        Text { visible: !!modelData.title; width: parent.width; wrapMode: Text.Wrap; text: modelData.title || ""; color: modelData.tone ? root.toneColor(modelData.tone) : Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
                        Text { visible: !!modelData.sub; width: parent.width; wrapMode: Text.Wrap; text: modelData.sub || ""; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                    }
                }
            }
        }
    }

    // ---------- stat: one big figure ----------
    Component {
        id: statC
        Column {
            readonly property var b: parent && parent.b ? parent.b : ({})
            width: parent ? parent.width : 0
            spacing: Theme.s(6)
            Text { text: b.value || ""; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(28); font.weight: Font.DemiBold }
            Text { visible: !!b.sub; width: parent.width; wrapMode: Text.Wrap; text: b.sub || ""; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
            // Up to the goal the bar fills in the accent; past it, the goal moves left (a tick marks it)
            // and the extra pushes on in a second wallpaper color.
            Item {
                id: bar
                visible: !!b.bar && b.bar.max > 0
                readonly property real ratio: b.bar && b.bar.max > 0 ? b.bar.value / b.bar.max : 0
                readonly property real goalAt: ratio > 1 ? 1 / ratio : 1
                width: parent.width; height: Theme.s(10)
                Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.white(0.08) }
                Rectangle { height: parent.height; radius: height / 2; color: Theme.accent; width: parent.width * Math.min(1, bar.ratio) * bar.goalAt }
                Rectangle {
                    visible: bar.ratio > 1
                    x: parent.width * bar.goalAt - radius; height: parent.height; radius: height / 2
                    width: parent.width * (1 - bar.goalAt) + radius
                    color: Theme.netDown
                }
                Rectangle { visible: bar.ratio > 1; x: parent.width * bar.goalAt - 1; y: -Theme.s(3); width: 2; height: parent.height + Theme.s(6); radius: 1; color: Theme.text }
            }
            Text {
                visible: bar.visible
                text: bar.ratio > 1 ? Math.round((bar.ratio - 1) * 100) + "% past your goal" : Math.round(bar.ratio * 100) + "% of the way"
                color: bar.ratio > 1 ? Theme.netDown : Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12)
            }
        }
    }

    // ---------- progress: labelled bars ----------
    Component {
        id: progressC
        Column {
            readonly property var b: parent && parent.b ? parent.b : ({})
            width: parent ? parent.width : 0
            spacing: Theme.s(12)
            Repeater {
                model: b.items || []
                delegate: Column {
                    required property var modelData
                    width: parent.width
                    spacing: Theme.s(5)
                    RowLayout {
                        width: parent.width
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.label || ""; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
                        Text { text: modelData.text || ""; color: modelData.tone && modelData.tone !== "normal" ? root.toneColor(modelData.tone) : Theme.text2; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                    }
                    Rectangle {
                        width: parent.width; height: Theme.s(5); radius: Theme.s(3)
                        color: Theme.white(0.08)
                        Rectangle { height: parent.height; radius: parent.radius; color: root.toneColor(modelData.tone); width: modelData.max > 0 ? parent.width * Math.min(1, modelData.value / modelData.max) : 0 }
                    }
                    Text { visible: !!modelData.sub; text: modelData.sub || ""; color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                }
            }
        }
    }

    // ---------- rows: a mono time column beside text ----------
    Component {
        id: rowsC
        Column {
            readonly property var b: parent && parent.b ? parent.b : ({})
            width: parent ? parent.width : 0
            spacing: Theme.s(8)
            Repeater {
                model: b.items || []
                delegate: RowLayout {
                    required property var modelData
                    width: parent.width
                    spacing: Theme.s(14)
                    Text { Layout.preferredWidth: Theme.s(118); Layout.alignment: Qt.AlignTop; elide: Text.ElideRight; text: modelData.when || ""; color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                    Text {
                        Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData.text || ""
                        color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13)
                        MouseArea { anchors.fill: parent; enabled: !!modelData.chat; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: EveData.openChat(modelData.chat) }
                    }
                }
            }
        }
    }

    // ---------- list: rows with a right-hand value ----------
    Component {
        id: listC
        Column {
            readonly property var b: parent && parent.b ? parent.b : ({})
            width: parent ? parent.width : 0
            spacing: Theme.s(2)
            Text { visible: !!b.lead; width: parent.width; wrapMode: Text.Wrap; text: b.lead || ""; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(14); bottomPadding: Theme.s(6) }
            Repeater {
                model: b.items || []
                delegate: HoverButton {
                    id: li
                    required property var modelData
                    width: parent.width
                    height: liCol.implicitHeight + Theme.s(18)
                    radius: Theme.s(10)
                    hoverFill: !!modelData.chat
                    onClicked: if (modelData.chat) EveData.openChat(modelData.chat)
                    Column {
                        id: liCol
                        x: Theme.s(4); y: Theme.s(9)
                        width: parent.width - Theme.s(8)
                        spacing: Theme.s(3)
                        RowLayout {
                            width: parent.width
                            spacing: Theme.s(8)
                            Rectangle {
                                visible: !!li.modelData.live
                                width: Theme.s(7); height: Theme.s(7); radius: Theme.s(4); color: Theme.accent
                                SequentialAnimation on opacity { running: !!li.modelData.live && !Theme.reduceMotion; loops: Animation.Infinite; NumberAnimation { to: 0.3; duration: 700 } NumberAnimation { to: 1; duration: 700 } }
                            }
                            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: li.modelData.title || ""; color: li.modelData.tone ? root.toneColor(li.modelData.tone) : Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(14); font.weight: Font.Medium }
                            Rectangle {
                                visible: !!li.modelData.badge
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: badgeText.implicitWidth + Theme.s(14); implicitHeight: Theme.s(20); radius: Theme.s(10)
                                readonly property color tc: li.modelData.badge ? root.toneColor(li.modelData.badge.tone) : Theme.muted
                                color: Qt.rgba(tc.r, tc.g, tc.b, 0.15)
                                Text { id: badgeText; anchors.centerIn: parent; text: li.modelData.badge ? li.modelData.badge.text : ""; color: parent.tc; font.family: Theme.sans; font.pixelSize: Theme.s(11); font.weight: Font.Medium }
                            }
                            Text { Layout.alignment: Qt.AlignTop; text: li.modelData.trailing || ""; color: Theme.text2; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                        }
                        Text { visible: !!li.modelData.code; width: parent.width; elide: Text.ElideRight; text: "$ " + (li.modelData.code || ""); color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11) }
                        Text { visible: !!li.modelData.sub; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: li.modelData.sub || ""; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                        Text { visible: !!li.modelData.detail; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; text: li.modelData.detail || ""; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12); topPadding: Theme.s(2) }
                    }
                }
            }
        }
    }

    // ---------- checklist: tick boxes ----------
    Component {
        id: checkC
        Column {
            readonly property var b: parent && parent.b ? parent.b : ({})
            width: parent ? parent.width : 0
            spacing: Theme.s(4)
            Repeater {
                model: b.items || []
                delegate: HoverButton {
                    required property var modelData
                    width: parent.width; height: Theme.s(36); radius: Theme.s(10)
                    onClicked: EveData.checkAppItem(modelData.id, !modelData.done)
                    Row {
                        x: Theme.s(4); anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s(12)
                        Rectangle {
                            width: Theme.s(20); height: Theme.s(20); radius: Theme.s(10)
                            color: modelData.done ? Theme.accent : "transparent"
                            border.width: modelData.done ? 0 : 1.5; border.color: Theme.muted
                            Icon { visible: !!modelData.done; anchors.centerIn: parent; path: Icons.check; size: Theme.s(12); stroke: 2.4; color: Theme.ink }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.text || ""; color: modelData.done ? Theme.dim : Theme.text; font.strikeout: !!modelData.done; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
                    }
                }
            }
        }
    }

    // ---------- table ----------
    Component {
        id: tableC
        Column {
            readonly property var b: parent && parent.b ? parent.b : ({})
            width: parent ? parent.width : 0
            spacing: Theme.s(8)
            readonly property int cols: Math.max(1, (b.columns || []).length)
            RowLayout {
                width: parent.width
                Repeater {
                    model: b.columns || []
                    delegate: Text { required property var modelData; required property int index; Layout.fillWidth: true; Layout.preferredWidth: index === 0 ? 2 : 1; elide: Text.ElideRight; text: modelData; color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                }
            }
            Repeater {
                model: b.rows || []
                delegate: RowLayout {
                    required property var modelData
                    width: parent.width
                    Repeater {
                        model: parent.modelData
                        delegate: Text { required property var modelData; required property int index; Layout.fillWidth: true; Layout.preferredWidth: index === 0 ? 2 : 1; elide: Text.ElideRight; text: String(modelData); color: index === 0 ? Theme.text : Theme.text2; font.family: index === 0 ? Theme.sans : Theme.mono; font.pixelSize: Theme.s(12) }
                    }
                }
            }
        }
    }

    // ---------- metrics: a grid of figures ----------
    Component {
        id: metricsC
        Grid {
            readonly property var b: parent && parent.b ? parent.b : ({})
            width: parent ? parent.width : 0
            columns: 3
            columnSpacing: Theme.s(10); rowSpacing: Theme.s(10)
            Repeater {
                model: b.items || []
                delegate: Rectangle {
                    required property var modelData
                    width: (root.width - Theme.s(32) - Theme.s(20)) / 3
                    height: Theme.s(62)
                    radius: Theme.s(12)
                    color: Theme.white(0.04)
                    Column {
                        x: Theme.s(12); anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s(4)
                        Text { text: modelData.label || ""; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                        Text { text: modelData.value || ""; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
                    }
                }
            }
        }
    }

    // ---------- tiles: file cards ----------
    Component {
        id: tilesC
        Grid {
            readonly property var b: parent && parent.b ? parent.b : ({})
            width: parent ? parent.width : 0
            columns: 3
            columnSpacing: Theme.s(10); rowSpacing: Theme.s(10)
            Repeater {
                model: b.items || []
                delegate: HoverButton {
                    required property var modelData
                    readonly property real w: (root.width - Theme.s(32) - Theme.s(20)) / 3
                    width: w; height: w + Theme.s(44)
                    radius: Theme.s(12)
                    hoverFill: false
                    color: hovered ? Theme.white(0.08) : Theme.white(0.04)
                    onClicked: {
                        if (modelData.image) root.openImage(modelData.url || modelData.image, modelData.name || "");
                        else if (modelData.url) Qt.openUrlExternally(modelData.url);
                        else if (modelData.chat) EveData.openChat(modelData.chat);
                    }
                    Rectangle {
                        x: Theme.s(6); y: Theme.s(6)
                        width: parent.width - Theme.s(12); height: parent.w - Theme.s(12)
                        radius: Theme.s(8)
                        color: Theme.white(0.05)
                        clip: true
                        Image { anchors.fill: parent; visible: !!modelData.image; source: modelData.image || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 360 }
                        Text { visible: !modelData.image; anchors.centerIn: parent; text: ((modelData.name || "").split(".").pop() || "FILE").toUpperCase(); color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                    }
                    Column {
                        x: Theme.s(8); y: parent.w
                        width: parent.width - Theme.s(16)
                        spacing: Theme.s(2)
                        Text { width: parent.width; elide: Text.ElideMiddle; text: modelData.name || ""; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                        Text { width: parent.width; elide: Text.ElideRight; text: modelData.meta || ""; color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(10) }
                    }
                }
            }
        }
    }

    // ---------- calendar: a month grid, then the picked day's events ----------
    Component {
        id: calendarC
        Column {
            readonly property var b: parent && parent.b ? parent.b : ({})
            width: parent ? parent.width : 0
            id: cal
            spacing: Theme.s(12)
            readonly property var first: new Date((b.month || "2026-01") + "-01T00:00:00")
            readonly property int days: new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()
            readonly property int lead: (first.getDay() + 6) % 7          // weeks start on Monday
            property string picked: b.today || ""
            function iso(d) { return (b.month || "") + "-" + (d < 10 ? "0" : "") + d; }
            function eventsOn(dateText) { return (b.events || []).filter(e => e.date === dateText); }
            Grid {
                columns: 7
                width: parent.width
                Repeater {
                    model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                    delegate: Text { required property var modelData; width: cal.width / 7; horizontalAlignment: Text.AlignHCenter; text: modelData; color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(11); bottomPadding: Theme.s(6) }
                }
                Repeater {
                    model: cal.lead
                    delegate: Item { width: cal.width / 7; height: Theme.s(38) }
                }
                Repeater {
                    model: cal.days
                    delegate: HoverButton {
                        required property int index
                        readonly property string date: cal.iso(index + 1)
                        readonly property bool isToday: date === b.today
                        readonly property bool isPicked: date === cal.picked
                        width: cal.width / 7; height: Theme.s(38); radius: Theme.s(10)
                        hoverFill: false
                        color: isPicked ? Theme.accentSoft : hovered ? Theme.white(0.06) : "transparent"
                        onClicked: cal.picked = date
                        Text { anchors.horizontalCenter: parent.horizontalCenter; y: Theme.s(8); text: index + 1; color: isToday ? Theme.accent : Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: isToday ? Font.Bold : Font.Normal }
                        Rectangle { visible: cal.eventsOn(date).length > 0; anchors.horizontalCenter: parent.horizontalCenter; y: Theme.s(28); width: Theme.s(4); height: Theme.s(4); radius: Theme.s(2); color: Theme.accent }
                    }
                }
            }
            Rectangle { width: parent.width; height: 1; color: Theme.white(0.08) }
            Text {
                readonly property var d: new Date(cal.picked + "T00:00:00")
                text: cal.picked ? d.toLocaleDateString(Qt.locale(), "dddd, MMMM d") : ""
                color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12)
            }
            Repeater {
                model: cal.eventsOn(cal.picked)
                delegate: RowLayout {
                    required property var modelData
                    width: cal.width
                    spacing: Theme.s(14)
                    Text { Layout.preferredWidth: Theme.s(80); text: modelData.time || "All day"; color: Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                    Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData.text || ""; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
                }
            }
            Text { visible: cal.eventsOn(cal.picked).length === 0; text: "Nothing scheduled."; color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
        }
    }

    // ---------- terminal: the last lines of a terminal, mono ----------
    Component {
        id: terminalC
        Rectangle {
            readonly property var b: parent && parent.b ? parent.b : ({})
            width: parent ? parent.width : 0
            height: termCol.implicitHeight + Theme.s(20)
            radius: Theme.s(10)
            color: Qt.rgba(0, 0, 0, 0.35)
            Column {
                id: termCol
                x: Theme.s(12); y: Theme.s(10)
                width: parent.width - Theme.s(24)
                spacing: Theme.s(2)
                Repeater {
                    model: parent.parent.b.lines || []
                    delegate: Text { required property var modelData; width: termCol.width; elide: Text.ElideRight; text: typeof modelData === "string" ? modelData : (modelData.text || ""); color: String(modelData).startsWith("$") ? Theme.text : Theme.muted; font.family: Theme.mono; font.pixelSize: Theme.s(11) }
                }
            }
        }
    }

    // ---------- text ----------
    Component {
        id: textC
        Text {
            readonly property var b: parent && parent.b ? parent.b : ({})
            width: parent ? parent.width : 0
            wrapMode: Text.Wrap; textFormat: Text.MarkdownText; text: b.markdown || ""; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(14)
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }

    // ---------- tabs: a segmented row, then the tab's own blocks ----------
    Component {
        id: tabsC
        Column {
            id: tabsCol
            readonly property var b: parent ? parent.modelData : ({})
            property int current: 0
            width: parent ? parent.width : 0
            spacing: Theme.s(12)
            Rectangle {
                width: tabRow.implicitWidth + Theme.s(8); height: Theme.s(36); radius: Theme.s(12)
                color: Theme.white(0.06)
                Row {
                    id: tabRow
                    x: Theme.s(4); anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: tabsCol.b.tabs || []
                        delegate: HoverButton {
                            required property var modelData
                            required property int index
                            width: tl.implicitWidth + Theme.s(26); height: Theme.s(28); radius: Theme.s(9)
                            hoverFill: false
                            color: index === tabsCol.current ? Theme.white(0.12) : "transparent"
                            onClicked: tabsCol.current = index
                            Text { id: tl; anchors.centerIn: parent; text: modelData.name || ""; color: index === tabsCol.current ? Theme.text : Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium }
                        }
                    }
                }
            }
            Loader {
                id: tabBody
                width: parent.width
                source: "AppBlocks.qml"
                onLoaded: {
                    item.openImage.connect(root.openImage);
                    item.width = Qt.binding(() => tabBody.width);
                    item.blocks = Qt.binding(() => ((tabsCol.b.tabs || [])[tabsCol.current] || {}).blocks || []);
                }
            }
        }
    }
}
