import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"
import Quickshell
import Quickshell.Io

// The Eve panel (design: "Eve panel · home, chat, sidebar, input"): 572px wide on the
// right, under the bar. Header fades into the content; home (orb, greeting, cards,
// suggestions) or the chat; the input area fades up from the bottom; the sidebar
// slides over from the left. UI only: everything it shows comes from
// services/EveData.qml (demo content until an integration fills it in).
Item {
    id: ep
    readonly property bool shown: EveData.open && Theme.aiEnabled
    visible: opacity > 0
    opacity: 0
    transform: Translate { id: shift; x: 0 }
    states: State { name: "in"; when: ep.shown; PropertyChanges { target: ep; opacity: 1 } PropertyChanges { target: shift; x: 0 } }
    transitions: [
        Transition { to: "in"; NumberAnimation { target: ep; property: "opacity"; from: 0; duration: Theme.reduceMotion ? 150 : Theme.durDrop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
                               NumberAnimation { target: shift; property: "x"; from: Theme.reduceMotion ? 0 : 12; duration: Theme.durDrop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } },
        Transition { from: "in"; NumberAnimation { target: ep; property: "opacity"; to: 0; duration: Theme.durHide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
    ]
    onShownChanged: if (shown) input.forceActiveFocus()

    property bool side: false
    property bool attach: false
    property bool menu: false
    property var expanded: ({})          // "chat:index" → true for my long messages shown whole
    property var confirmDelete: null     // { id, title } while the delete confirmation is open
    property var viewing: null           // { url, name } while a picture is open full size
    function askDelete(id) {
        const c = EveData.chats.find(x => x.id === id);
        if (!c) return;
        ep.menu = false;
        ep.confirmDelete = { id: c.id, title: c.title };
    }
    property string query: ""
    readonly property bool isChat: EveData.current !== ""
    readonly property bool isApp: EveData.app !== ""
    readonly property color solid: Theme.surface === "glass" ? Qt.rgba(22 / 255, 22 / 255, 25 / 255, 1) : Theme.panelBg
    readonly property bool ready: EveData.on
    readonly property string statusText: EveData.statusLine

    Surface { anchors.fill: parent; kind: "panel"; radius: Theme.s(24) }
    MouseArea { anchors.fill: parent; onClicked: { ep.menu = false; input.forceActiveFocus(); } }

    // ================= content =================
    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: 1; anchors.bottomMargin: 1
        clip: true
        contentHeight: content.implicitHeight + Theme.s(72) + footer.height + Theme.s(20)
        boundsBehavior: Flickable.StopAtBounds
        WheelScroll {}
        // follow new text while the reply streams in
        onContentHeightChanged: if (ep.isChat) contentY = Math.max(0, contentHeight - height)
        Connections { target: EveData; function onAppChanged() { flick.contentY = 0; } }

        Column {
            id: content
            x: Theme.s(22); y: Theme.s(72)
            width: ep.width - Theme.s(44)
            spacing: Theme.s(22)

            // ---------- home ----------
            Column {
                visible: !ep.isChat && !ep.isApp
                width: parent.width
                spacing: Theme.s(22)
                topPadding: Theme.s(34)
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.s(92); height: Theme.s(92)
                    Repeater {
                        model: 2
                        delegate: Rectangle {
                            required property int index
                            anchors.fill: parent
                            radius: Theme.s(46)
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.accent
                            opacity: 0
                            SequentialAnimation on scale {
                                running: EveData.on && ep.shown && !Theme.reduceMotion
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 1500 }
                                ParallelAnimation {
                                    NumberAnimation { from: 0.9; to: 1.8; duration: 3000; easing.type: Easing.OutQuad }
                                }
                            }
                            SequentialAnimation on opacity {
                                running: EveData.on && ep.shown && !Theme.reduceMotion
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 1500 }
                                NumberAnimation { from: 0.5; to: 0; duration: 3000; easing.type: Easing.OutQuad }
                            }
                        }
                    }
                    // the core: the wallpaper's colors turning around (conic), a soft highlight
                    // and a glow, breathing while on; grey when off
                    Item {
                        id: core
                        anchors.fill: parent
                        Shape {
                            visible: EveData.on
                            x: -Theme.s(40); y: -Theme.s(40); width: Theme.s(172); height: Theme.s(172)
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeWidth: -1
                                fillGradient: RadialGradient {
                                    centerX: Theme.s(86); centerY: Theme.s(86); centerRadius: Theme.s(86); focalX: Theme.s(86); focalY: Theme.s(86)
                                    GradientStop { position: 0.45; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4) }
                                    GradientStop { position: 1; color: "transparent" }
                                }
                                PathAngleArc { centerX: Theme.s(86); centerY: Theme.s(86); radiusX: Theme.s(86); radiusY: Theme.s(86); startAngle: 0; sweepAngle: 360 }
                            }
                        }
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeWidth: -1
                                fillGradient: EveData.on ? conic : off
                                PathAngleArc { centerX: Theme.s(46); centerY: Theme.s(46); radiusX: Theme.s(46); radiusY: Theme.s(46); startAngle: 0; sweepAngle: 360 }
                            }
                            ConicalGradient {
                                id: conic
                                centerX: Theme.s(46); centerY: Theme.s(46); angle: 0
                                GradientStop { position: 0; color: Theme.eq[0] }
                                GradientStop { position: 0.33; color: Theme.eq[1] }
                                GradientStop { position: 0.66; color: Theme.eq[2] }
                                GradientStop { position: 1; color: Theme.eq[0] }
                            }
                            RadialGradient {
                                id: off
                                centerX: Theme.s(46); centerY: Theme.s(46); centerRadius: Theme.s(46); focalX: Theme.s(46); focalY: Theme.s(46)
                                GradientStop { position: 0; color: "#4A4A50" }
                                GradientStop { position: 1; color: "#3A3A3F" }
                            }
                        }
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeWidth: -1
                                fillGradient: RadialGradient {
                                    centerX: Theme.s(31); centerY: Theme.s(26); centerRadius: Theme.s(30); focalX: Theme.s(31); focalY: Theme.s(26)
                                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, EveData.on ? 0.85 : 0.35) }
                                    GradientStop { position: 1; color: "transparent" }
                                }
                                PathAngleArc { centerX: Theme.s(46); centerY: Theme.s(46); radiusX: Theme.s(46); radiusY: Theme.s(46); startAngle: 0; sweepAngle: 360 }
                            }
                        }
                        SequentialAnimation on scale {
                            running: EveData.on && ep.shown && !Theme.reduceMotion
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.94; to: 1.05; duration: 1500; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 1.05; to: 0.94; duration: 1500; easing.type: Easing.InOutQuad }
                        }
                    }
                }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.s(6)
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property int hour: new Date().getHours()
                        text: hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
                        color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(24); font.weight: Font.Bold; font.letterSpacing: Theme.tracking(24)
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.s(7)
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Theme.s(7); height: Theme.s(7); radius: Theme.s(4); color: EveData.on && EveData.connected ? Theme.accent : Theme.dim }
                        Text { text: ep.statusText; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
                    }
                }
                // cards
                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: Theme.s(10); rowSpacing: Theme.s(10)
                    Repeater {
                        model: EveData.homeCards
                        delegate: HoverButton {
                            id: card
                            required property var modelData
                            width: (content.width - Theme.s(10)) / 2
                            height: Math.max(Theme.s(104), cardCol.implicitHeight + Theme.s(28))
                            radius: Theme.s(16)
                            hoverFill: false
                            color: hovered ? Theme.white(0.1) : Theme.tile
                            onClicked: {
                                if (card.modelData.chat) EveData.openChat(card.modelData.chat);
                                else if (card.modelData.draft) { input.text = card.modelData.draft; input.forceActiveFocus(); }
                            }
                            Column {
                                id: cardCol
                                x: Theme.s(14); y: Theme.s(14)
                                width: parent.width - Theme.s(28)
                                spacing: Theme.s(8)
                                Row {
                                    spacing: Theme.s(8)
                                    Rectangle {
                                        width: Theme.s(26); height: Theme.s(26); radius: Theme.s(8)
                                        color: Theme.accentSoft
                                        Icon { anchors.centerIn: parent; path: card.modelData.icon; size: Theme.s(14); color: Theme.accent }
                                    }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: card.modelData.label; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                                }
                                Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.title; color: Theme.text; font.family: Theme.sans; font.pointSize: Theme.sf(10.125); font.weight: Font.DemiBold }
                                Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.sub; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                            }
                        }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: Theme.s(8)
                    Repeater {
                        model: EveData.suggestions
                        delegate: HoverButton {
                            required property var modelData
                            width: sg.implicitWidth + Theme.s(28); height: Theme.s(32); radius: Theme.s(16)
                            border.width: 1; border.color: Theme.white(0.14)
                            onClicked: { input.text = modelData; input.forceActiveFocus(); }
                            Text { id: sg; anchors.centerIn: parent; text: parent.modelData; color: Theme.text2; font.family: Theme.sans; font.pointSize: Theme.sf(9.375) }
                        }
                    }
                }
            }

            // ---------- an app (display blocks from the backend) ----------
            Text {
                visible: ep.isApp && !!EveData.appPage && !!EveData.appPage.subtitle
                text: EveData.appPage && EveData.appPage.subtitle ? EveData.appPage.subtitle : ""
                color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(13)
            }
            // an app with views (Finance's months): step through them, newest on the right
            RowLayout {
                id: views
                readonly property var list: ep.isApp && EveData.appPage && EveData.appPage.views ? EveData.appPage.views : []
                readonly property int at: list.findIndex(v => v.id === EveData.appPage.view)
                visible: list.length > 1
                width: parent.width
                HoverButton {
                    implicitWidth: Theme.s(34); implicitHeight: Theme.s(34); radius: Theme.s(10)
                    opacity: views.at > 0 ? 1 : 0.3
                    onClicked: if (views.at > 0) EveData.openApp(EveData.app, views.list[views.at - 1].id)
                    Icon { anchors.centerIn: parent; path: "M15 5 L8 12 L15 19"; size: Theme.s(16); color: Theme.text }
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: views.at >= 0 ? views.list[views.at].name : ""
                    color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold
                }
                HoverButton {
                    implicitWidth: Theme.s(34); implicitHeight: Theme.s(34); radius: Theme.s(10)
                    opacity: views.at >= 0 && views.at < views.list.length - 1 ? 1 : 0.3
                    onClicked: if (views.at >= 0 && views.at < views.list.length - 1) EveData.openApp(EveData.app, views.list[views.at + 1].id)
                    Icon { anchors.centerIn: parent; path: "M9 5 L16 12 L9 19"; size: Theme.s(16); color: Theme.text }
                }
            }
            AppBlocks {
                visible: ep.isApp
                width: parent.width
                blocks: ep.isApp && EveData.appPage ? EveData.appPage.blocks || [] : []
                onOpenImage: (url, name) => { ep.viewing = { url: url, name: name }; }
            }
            Text {
                visible: ep.isApp && !EveData.appPage
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Theme.s(40)
                text: "Loading…"
                color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(13)
            }

            // ---------- chat ----------
            Repeater {
                model: ep.isChat && EveData.chat ? EveData.chat.messages : []
                delegate: Item {
                    id: msg
                    required property var modelData
                    required property int index
                    readonly property bool mine: modelData.who === "user"
                    // a long message of mine shows 5 lines until it is expanded (kept per chat while the panel is open)
                    readonly property string key: EveData.current + ":" + index
                    readonly property bool expanded: !!ep.expanded[key]
                    width: content.width
                    height: mine ? bubble.height : eveCol.implicitHeight
                    Rectangle {
                        id: bubble
                        visible: msg.mine
                        anchors.right: parent.right
                        width: Math.min(Theme.s(380), Math.max(userText.implicitWidth, moreToggle.visible ? moreToggle.implicitWidth : 0) + Theme.s(30))
                        height: userText.height + Theme.s(22) + (moreToggle.visible ? moreToggle.height + Theme.s(4) : 0)
                        radius: Theme.s(18)
                        color: Theme.text
                        // the design's 18 18 5 18 corners: square off the bottom right
                        Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; width: Theme.s(14); height: Theme.s(14); radius: Theme.s(5); color: Theme.text }
                        Text {
                            id: userText
                            x: Theme.s(15); y: Theme.s(11)
                            width: Math.min(Theme.s(350), implicitWidth)
                            wrapMode: Text.Wrap
                            maximumLineCount: msg.expanded ? 100000 : 5
                            elide: Text.ElideRight
                            text: msg.modelData.text
                            color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(15)
                            lineHeight: Theme.s(22); lineHeightMode: Text.FixedHeight
                        }
                        Text {
                            id: moreToggle
                            visible: userText.truncated || msg.expanded
                            x: Theme.s(15); y: userText.y + userText.height + Theme.s(4)
                            text: msg.expanded ? "Show less" : "Show more"
                            color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.6)
                            font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -Theme.s(6)
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { const e = Object.assign({}, ep.expanded); e[msg.key] = !msg.expanded; ep.expanded = e; }
                            }
                        }
                    }
                    Column {
                        id: eveCol
                        visible: !msg.mine
                        width: Math.min(Theme.s(500), parent.width)
                        spacing: Theme.s(10)
                        // the reply's header: how long it took
                        Text {
                            visible: !!msg.modelData.worked
                            text: msg.modelData.worked === "stopped" ? "Stopped" : "Worked for " + (msg.modelData.worked || "")
                            color: Theme.muted; font.family: Theme.sans; font.pointSize: Theme.sf(8.625)
                        }
                        TextEdit {
                            width: parent.width
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.MarkdownText
                            text: msg.modelData.text || ""
                            color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(15)
                            selectionColor: Theme.white(0.2)
                        }
                        Rectangle {
                            visible: !!msg.modelData.tool
                            width: toolRow.implicitWidth + Theme.s(24); height: Theme.s(38); radius: Theme.s(11)
                            color: Theme.tile
                            Row {
                                id: toolRow
                                anchors.centerIn: parent
                                spacing: Theme.s(10)
                                Icon { anchors.verticalCenter: parent.verticalCenter; path: "M5 6 H19 V20 H5 Z M5 10 H19 M9 3 V7 M15 3 V7"; size: Theme.s(14); color: Theme.accent }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: msg.modelData.tool || ""; color: Theme.text; font.family: Theme.sans; font.pointSize: Theme.sf(9.375) }
                                Icon { anchors.verticalCenter: parent.verticalCenter; path: Icons.check; size: Theme.s(14); stroke: 2.4; color: Theme.accent }
                            }
                        }
                        Text {
                            visible: !!msg.modelData.error
                            text: "⚠ " + (msg.modelData.error || "")
                            color: Theme.warning; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                        }
                        // the reply's footer: shows a second after the reply is done (EveData sets `footer`)
                        RowLayout {
                            visible: !msg.modelData.error && msg.modelData.footer !== false
                            width: parent.width
                            HoverButton {
                                // read aloud (the backend's voice); pressed again while she reads, it stops
                                visible: EveData.can("voice.speech")
                                readonly property bool reading: EveData.speaking && EveData.speakingText === msg.modelData.text
                                implicitWidth: Theme.s(28); implicitHeight: Theme.s(28); radius: Theme.s(8)
                                onClicked: reading ? EveData.stopSpeaking() : EveData.speak(msg.modelData.text)
                                Icon { anchors.centerIn: parent; path: parent.reading ? "M7 7 H17 V17 H7 Z" : "M8 5 L19 12 L8 19 Z"; filled: parent.reading; size: Theme.s(14); color: parent.reading ? Theme.accent : Theme.muted }
                            }
                            HoverButton {
                                implicitWidth: Theme.s(28); implicitHeight: Theme.s(28); radius: Theme.s(8)
                                onClicked: Quickshell.execDetached(["wl-copy", msg.modelData.text])
                                Icon { anchors.centerIn: parent; path: "M8 8 H20 V20 H8 Z M16 8 V5 A1 1 0 0 0 15 4 H5 A1 1 0 0 0 4 5 V15 A1 1 0 0 0 5 16 H8"; size: Theme.s(14); color: Theme.muted }
                            }
                            Item { Layout.fillWidth: true }
                            Text { text: msg.modelData.tele || ""; color: Theme.dim; font.family: Theme.mono; font.pointSize: Theme.sf(7.875) }
                        }
                    }
                }
            }
            Text {
                visible: ep.isChat && EveData.chat !== null && EveData.chat.messages.length === 0
                width: content.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Theme.s(40)
                text: !EveData.live ? "Demo chat. Its messages show up here once an assistant is connected." : EveData.chat && EveData.chat.loaded ? "No messages yet." : "Loading…"
                color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(13)
            }
            Row {
                visible: ep.isChat && EveData.working
                spacing: Theme.s(8)
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.s(8); height: Theme.s(8); radius: Theme.s(4); color: Theme.accent
                    SequentialAnimation on opacity { running: EveData.working && !Theme.reduceMotion; loops: Animation.Infinite; NumberAnimation { to: 0.35; duration: 600 } NumberAnimation { to: 1; duration: 600 } }
                }
                Text { text: "Working…"; color: Theme.muted; font.family: Theme.sans; font.pointSize: Theme.sf(9.375) }
            }
        }
    }

    // ================= header (fades into the content) =================
    Item {
        id: header
        width: parent.width
        height: Theme.s(78)
        Rectangle {
            anchors.fill: parent
            radius: Theme.s(24)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(ep.solid.r, ep.solid.g, ep.solid.b, 1) }
                GradientStop { position: 0.55; color: Qt.rgba(ep.solid.r, ep.solid.g, ep.solid.b, 0.92) }
                GradientStop { position: 1; color: Qt.rgba(ep.solid.r, ep.solid.g, ep.solid.b, 0) }
            }
        }
        HoverButton {
            x: Theme.s(14); y: Theme.s(14)
            width: Theme.s(36); height: Theme.s(36); radius: Theme.s(11)
            onClicked: ep.side = true
            Icon { anchors.centerIn: parent; path: "M5 4 H19 A2 2 0 0 1 21 6 V18 A2 2 0 0 1 19 20 H5 A2 2 0 0 1 3 18 V6 A2 2 0 0 1 5 4 Z M9 4 V20"; size: Theme.s(18); color: Theme.text }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.s(22)
            width: parent.width - Theme.s(240)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            visible: !renaming.visible
            text: ep.isApp ? EveData.appTitle : EveData.chat ? EveData.chat.title : EveData.assistantName
            color: Theme.text; font.family: Theme.sans; font.pointSize: Theme.sf(10.125); font.weight: Font.DemiBold
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: Theme.s(14)
            y: Theme.s(14)
            spacing: Theme.s(4)
            HoverButton {
                width: Theme.s(36); height: Theme.s(36); radius: Theme.s(18)
                hoverFill: false
                color: EveData.on ? Theme.accentSoft : Theme.white(0.06)
                border.width: EveData.on ? 1.5 : 0
                border.color: Theme.accent
                onClicked: EveData.on = !EveData.on
                Icon { anchors.centerIn: parent; path: Icons.power; size: Theme.s(17); color: EveData.on ? Theme.accent : Theme.muted }
            }
            HoverButton {
                width: Theme.s(36); height: Theme.s(36); radius: Theme.s(11)
                onClicked: { EveData.newChat(); input.forceActiveFocus(); }
                Icon { anchors.centerIn: parent; path: "M4 20 H8 L19 9 L15 5 L4 16 Z M13.5 6.5 L17.5 10.5"; size: Theme.s(17); color: Theme.text }
            }
            HoverButton {
                visible: ep.isChat
                width: Theme.s(36); height: Theme.s(36); radius: Theme.s(11)
                onClicked: ep.menu = !ep.menu
                Icon { anchors.centerIn: parent; path: "M12 4.3 L12 4.4 M12 12 L12 12.1 M12 19.6 L12 19.7"; size: Theme.s(17); stroke: 2.4; color: Theme.text }
            }
            HoverButton {
                width: Theme.s(36); height: Theme.s(36); radius: Theme.s(11)
                onClicked: EveData.open = false
                Icon { anchors.centerIn: parent; path: Icons.close; size: Theme.s(15); color: Theme.muted }
            }
        }
    }

    // a click anywhere outside the open menu or the rename field closes it (a rename is kept)
    MouseArea {
        anchors.fill: parent
        visible: (ep.menu && ep.isChat) || renaming.visible
        z: 5
        onClicked: { if (renaming.visible) ep.finishRename(true); ep.menu = false; }
    }

    // chat menu: pin, rename, delete
    Rectangle {
        visible: ep.menu && ep.isChat
        x: parent.width - width - Theme.s(14); y: Theme.s(56)
        width: Theme.s(190); height: menuCol.implicitHeight + Theme.s(12)
        radius: Theme.s(14)
        color: "#1C1C1F"
        border.width: 1; border.color: Theme.white(0.1)
        z: 6
        Column {
            id: menuCol
            x: Theme.s(6); y: Theme.s(6)
            width: parent.width - Theme.s(12)
            MenuItem { label: EveData.chat && EveData.chat.pinned ? "Unpin chat" : "Pin chat"; icon: "M9 4 H15 L14 9 L17 12 H7 L10 9 Z M12 12 V20"; onClicked: { EveData.pin(EveData.current); ep.menu = false; } }
            MenuItem { label: "Rename chat"; icon: "M4 20 H8 L19 9 L15 5 L4 16 Z"; onClicked: { ep.menu = false; ep.startRename(); } }
            MenuItem { label: "Delete chat"; icon: "M5 7 H19 M10 7 V5 H14 V7 M7 7 L8 19 H16 L17 7"; danger: true; onClicked: ep.askDelete(EveData.current) }
        }
    }
    // rename in place of the chat's title: Enter or the check saves, Escape or the x cancels
    function startRename() {
        if (!EveData.chat) return;
        renamer.text = EveData.chat.title;
        renaming.visible = true;
        renamer.forceActiveFocus();
        renamer.selectAll();
    }
    function finishRename(save) {
        if (!renaming.visible) return;
        if (save && renamer.text.trim() && EveData.chat && renamer.text.trim() !== EveData.chat.title) EveData.rename(EveData.current, renamer.text.trim());
        renaming.visible = false;
        input.forceActiveFocus();
    }
    Rectangle {
        id: renaming
        visible: false
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.s(15)
        width: parent.width - Theme.s(220); height: Theme.s(34); radius: Theme.s(10)
        color: Theme.tile
        border.width: 1; border.color: Theme.accentLine
        z: 7
        TextInput {
            id: renamer
            anchors.left: parent.left; anchors.right: renameButtons.left
            anchors.leftMargin: Theme.s(12); anchors.rightMargin: Theme.s(6)
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold
            selectionColor: Theme.white(0.2)
            onAccepted: ep.finishRename(true)
            Keys.onEscapePressed: ep.finishRename(false)
        }
        Row {
            id: renameButtons
            anchors.right: parent.right; anchors.rightMargin: Theme.s(3)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s(2)
            HoverButton {
                width: Theme.s(28); height: Theme.s(28); radius: Theme.s(8)
                onClicked: ep.finishRename(true)
                Icon { anchors.centerIn: parent; path: Icons.check; size: Theme.s(14); stroke: 2.4; color: Theme.accent }
            }
            HoverButton {
                width: Theme.s(28); height: Theme.s(28); radius: Theme.s(8)
                onClicked: ep.finishRename(false)
                Icon { anchors.centerIn: parent; path: Icons.close; size: Theme.s(12); color: Theme.muted }
            }
        }
    }

    // ================= input area =================
    Item {
        id: footer
        // apps only show information: no message box while one is open
        visible: !ep.isApp
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: footerCol.implicitHeight + Theme.s(44)
        Rectangle {
            anchors.fill: parent
            radius: Theme.s(24)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(ep.solid.r, ep.solid.g, ep.solid.b, 0) }
                GradientStop { position: 0.22; color: Qt.rgba(ep.solid.r, ep.solid.g, ep.solid.b, 0.95) }
                GradientStop { position: 1; color: Qt.rgba(ep.solid.r, ep.solid.g, ep.solid.b, 1) }
            }
        }
        Column {
            id: footerCol
            x: Theme.s(14); y: Theme.s(30)
            width: parent.width - Theme.s(28)
            spacing: Theme.s(8)
            // the assistant waits for your OK: one card per request, newest last
            Repeater {
                model: EveData.approvals
                delegate: Rectangle {
                    id: apc
                    required property var modelData
                    readonly property bool high: modelData.risk === "high"
                    width: footerCol.width
                    height: apCol.implicitHeight + Theme.s(28)
                    radius: Theme.s(16)
                    color: Theme.surface === "glass" ? Qt.rgba(0.1, 0.1, 0.11, 0.96) : "#1C1C1F"
                    border.width: 1
                    border.color: high ? Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.5) : Theme.accentLine
                    Column {
                        id: apCol
                        x: Theme.s(14); y: Theme.s(14)
                        width: parent.width - Theme.s(28)
                        spacing: Theme.s(8)
                        Row {
                            spacing: Theme.s(8)
                            Icon { anchors.verticalCenter: parent.verticalCenter; path: "M12 3 L21 19 H3 Z M12 10 V14 M12 16.5 V16.6"; size: Theme.s(15); color: apc.high ? Theme.warning : Theme.accent }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: EveData.assistantName + " needs your OK"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: apc.modelData.title || ""; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                        }
                        Rectangle {
                            visible: !!apc.modelData.command
                            width: parent.width; height: cmdText.implicitHeight + Theme.s(16); radius: Theme.s(9)
                            color: Qt.rgba(0, 0, 0, 0.35)
                            Text { id: cmdText; x: Theme.s(10); y: Theme.s(8); width: parent.width - Theme.s(20); wrapMode: Text.WrapAnywhere; maximumLineCount: 6; elide: Text.ElideRight
                                   text: apc.modelData.command || ""; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
                        }
                        Text { visible: !!apc.modelData.reason; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight
                               text: apc.modelData.reason || ""; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                        Row {
                            spacing: Theme.s(8)
                            HoverButton {
                                width: okT.implicitWidth + Theme.s(26); height: Theme.s(32); radius: Theme.s(10); hoverFill: false
                                color: hovered ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
                                onClicked: EveData.decide(apc.modelData.id, "approve", "once")
                                Text { id: okT; anchors.centerIn: parent; text: "Approve"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold }
                            }
                            HoverButton {
                                visible: (apc.modelData.scopes || []).indexOf("task") >= 0
                                width: taskT.implicitWidth + Theme.s(26); height: Theme.s(32); radius: Theme.s(10); hoverFill: false
                                color: hovered ? Theme.white(0.16) : Theme.white(0.1)
                                onClicked: EveData.decide(apc.modelData.id, "approve", "task")
                                Text { id: taskT; anchors.centerIn: parent; text: "Approve for this task"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                            }
                            HoverButton {
                                width: noT.implicitWidth + Theme.s(26); height: Theme.s(32); radius: Theme.s(10); hoverFill: false
                                color: hovered ? Theme.white(0.16) : Theme.white(0.1)
                                onClicked: EveData.decide(apc.modelData.id, "deny", "once")
                                Text { id: noT; anchors.centerIn: parent; text: "Deny"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                            }
                        }
                    }
                }
            }
            // attachment chips
            Flow {
                visible: EveData.attachments.length > 0
                width: parent.width
                spacing: Theme.s(8)
                Repeater {
                    model: EveData.attachments
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        width: chipRow.implicitWidth + Theme.s(12); height: Theme.s(34); radius: Theme.s(10)
                        color: Theme.tile
                        Row {
                            id: chipRow
                            x: Theme.s(5); anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.s(8)
                            Rectangle {
                                width: Theme.s(24); height: Theme.s(24); radius: Theme.s(6); color: Theme.white(0.08)
                                Icon {
                                    anchors.centerIn: parent; size: Theme.s(13); color: Theme.muted
                                    path: chip.modelData.kind === "image" ? "M4 5 H20 V19 H4 Z M4 15 L9 10 L14 15 M13 13 L16 10 L20 14" : chip.modelData.kind === "sheet" ? "M5 4 H19 V20 H5 Z M5 9 H19 M5 14 H19 M10 4 V20" : "M6 3 H14 L19 8 V21 H6 Z M14 3 V8 H19"
                                }
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: chip.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                            HoverButton {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.s(20); height: Theme.s(20); radius: Theme.s(6)
                                onClicked: EveData.removeAttachment(chip.index)
                                Icon { anchors.centerIn: parent; path: Icons.close; size: Theme.s(12); color: Theme.muted }
                            }
                        }
                    }
                }
            }
            // live transcription: pulsing red dot and the voice bars
            Row {
                visible: EveData.listening
                leftPadding: Theme.s(4)
                spacing: Theme.s(8)
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.s(7); height: Theme.s(7); radius: Theme.s(4); color: Theme.critical
                    SequentialAnimation on opacity { running: EveData.listening && !Theme.reduceMotion; loops: Animation.Infinite; NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutQuad } NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutQuad } }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Live transcription"; color: Theme.text2; font.family: Theme.sans; font.pointSize: Theme.sf(8.625) }
                // the design's 10 bars: each 0.8s ease-in-out between 30% and 100%, offset in fives
                Row {
                    id: micBars
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: Theme.s(4)
                    spacing: Theme.s(2)
                    property real t: 0
                    NumberAnimation on t { from: 0; to: 1; duration: 800; loops: Animation.Infinite; running: EveData.listening && !Theme.reduceMotion }
                    Repeater {
                        model: 10
                        delegate: Rectangle {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.s(2.5); height: Theme.s(12); radius: Theme.s(2)
                            color: Theme.accent
                            transform: Scale {
                                origin.y: 6
                                yScale: {
                                    let p = (micBars.t + (index % 5) * 0.14 / 0.8) % 1;
                                    let x = p < 0.5 ? p * 2 : (1 - p) * 2;
                                    x = x * x * (3 - 2 * x);
                                    return 0.3 + 0.7 * x;
                                }
                            }
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width
                height: Math.min(Theme.s(145), Math.max(Theme.s(38), input.contentHeight + Theme.s(12))) + Theme.s(16)
                radius: Theme.s(16)
                color: Qt.rgba(0, 0, 0, 0.35)
                border.width: 1
                border.color: EveData.listening ? Theme.accent : input.activeFocus ? Theme.accentLine : Theme.white(0.1)
                Flickable {
                    id: inFlick
                    x: Theme.s(14); y: Theme.s(8)
                    width: parent.width - Theme.s(14) - Theme.s(8) - sendRow.width - Theme.s(4)
                    height: parent.height - Theme.s(16)
                    contentHeight: input.contentHeight + Theme.s(12)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    TextEdit {
                        id: input
                        width: inFlick.width
                        y: Theme.s(6)
                        wrapMode: TextEdit.Wrap
                        color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13)
                        selectByMouse: true
                        selectionColor: Theme.white(0.2)
                        readOnly: !ep.ready
                        onCursorRectangleChanged: if (cursorRectangle.y + cursorRectangle.height > inFlick.contentY + inFlick.height) inFlick.contentY = cursorRectangle.y + cursorRectangle.height - inFlick.height + 12
                        // dictation: the words go in after what was typed before the mic started
                        property string beforeMic: ""
                        Connections {
                            target: EveData
                            function onListeningChanged() { if (EveData.listening) input.beforeMic = input.text.replace(/\s+$/, ""); }
                            function onDictated(text, final) {
                                input.text = input.beforeMic + (input.beforeMic && text ? " " : "") + text;
                                input.cursorPosition = input.text.length;
                                if (final) {
                                    input.forceActiveFocus();
                                    if (ep.sendAfterMic) { ep.sendAfterMic = false; ep.sendNow(); }
                                }
                            }
                        }
                        Keys.onPressed: e => {
                            if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) { ep.sendNow(); e.accepted = true; }
                            else if (e.key === Qt.Key_Escape) { if (ep.attach) ep.attach = false; else if (ep.side) ep.side = false; else EveData.open = false; e.accepted = true; }
                        }
                        Text {
                            visible: !input.text
                            text: !EveData.on ? EveData.assistantName + " is off" : "Message " + EveData.assistantName
                            color: Theme.dim; font: input.font
                        }
                    }
                }
                // thinking · mic · attach · send (the design's order)
                Row {
                    id: sendRow
                    anchors.right: parent.right; anchors.rightMargin: Theme.s(8)
                    anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.s(8)
                    spacing: Theme.s(4)
                    HoverButton {
                        width: Theme.s(34); height: Theme.s(34); radius: Theme.s(10)
                        hoverFill: false
                        color: EveData.think ? Theme.accentSoft : hovered ? Theme.white(0.08) : "transparent"
                        onClicked: EveData.think = !EveData.think
                        Icon { anchors.centerIn: parent; path: "M9 18 H15 M10 21 H14 M12 3 A6 6 0 0 0 8 13.5 C8.7 14.2 9 15 9 16 H15 C15 15 15.3 14.2 16 13.5 A6 6 0 0 0 12 3 Z"; color: EveData.think ? Theme.accent : Theme.text2 }
                    }
                    HoverButton {
                        width: Theme.s(34); height: Theme.s(34)
                        followRoundness: false
                        radius: EveData.listening ? Theme.s(17) : Math.min(Theme.s(17), Theme.s(10) * Theme.radiusScale)
                        hoverFill: false
                        color: EveData.listening ? Theme.critical : hovered ? Theme.white(0.08) : "transparent"
                        onClicked: EveData.toggleMic()
                        Icon { anchors.centerIn: parent; path: "M9 6 A3 3 0 0 1 15 6 V11 A3 3 0 0 1 9 11 Z M6 11 A6 6 0 0 0 18 11 M12 17 V21"; color: EveData.listening ? "#FFFFFF" : Theme.text2 }
                    }
                    HoverButton {
                        width: Theme.s(34); height: Theme.s(34); radius: Theme.s(10)
                        hoverFill: false
                        color: ep.attach ? Theme.white(0.12) : hovered ? Theme.white(0.08) : "transparent"
                        onClicked: ep.attach = !ep.attach
                        Icon { anchors.centerIn: parent; path: "M12 5 V19 M5 12 H19"; color: ep.attach ? Theme.text : Theme.text2 }
                    }
                    HoverButton {
                        width: Theme.s(34); height: Theme.s(34); radius: Theme.s(11)
                        hoverFill: false
                        readonly property bool can: EveData.working || (input.text.trim() !== "" && ep.ready)
                        color: EveData.working ? Theme.white(0.14) : can ? Theme.accent : Theme.white(0.08)
                        onClicked: EveData.working ? EveData.stop() : ep.sendNow()
                        Icon { anchors.centerIn: parent; path: EveData.working ? "M7 7 H17 V17 H7 Z" : "M5 12 H19 M13 6 L19 12 L13 18"; filled: EveData.working; color: EveData.working ? Theme.text : parent.can ? Theme.ink : Theme.dim }
                    }
                }
            }
            RowLayout {
                width: parent.width
                Rectangle {
                    implicitWidth: apRow.implicitWidth + Theme.s(6); implicitHeight: Theme.s(32); radius: Theme.s(10)
                    color: Qt.rgba(0, 0, 0, 0.3)
                    Row {
                        id: apRow
                        x: Theme.s(3); y: Theme.s(3)
                        spacing: Theme.s(2)
                        Repeater {
                            model: [["approve", "Approve for me", "M12 3 L19 6 V12 C19 16 16 19 12 21 C8 19 5 16 5 12 V6 Z M9 12 L11 14 L15 10"], ["full", "Full access", "M12 3 L19 6 V12 C19 16 16 19 12 21 C8 19 5 16 5 12 V6 Z"]]
                            delegate: HoverButton {
                                id: ap
                                required property var modelData
                                readonly property bool on: EveData.approval === modelData[0]
                                width: apT.implicitWidth + Theme.s(36); height: Theme.s(26); radius: Theme.s(7)
                                hoverFill: false
                                color: on ? Theme.text : hovered ? Theme.white(0.06) : "transparent"
                                onClicked: EveData.approval = ap.modelData[0]
                                Row {
                                    anchors.centerIn: parent
                                    spacing: Theme.s(6)
                                    Icon { anchors.verticalCenter: parent.verticalCenter; path: ap.modelData[2]; size: Theme.s(12); color: ap.on ? Theme.ink : Theme.text2 }
                                    Text { id: apT; anchors.verticalCenter: parent.verticalCenter; text: ap.modelData[1]; color: ap.on ? Theme.ink : Theme.text2; font.family: Theme.sans; font.pointSize: Theme.sf(8.625) }
                                }
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Text { text: EveData.approval === "full" ? EveData.assistantName + " acts without asking" : EveData.assistantName + " asks before acting"; color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
            }
        }
    }
    // sending while the mic is on stops it first and sends once the final text is in, so the last words are kept
    property bool sendAfterMic: false
    function sendNow() {
        if (EveData.listening || EveData.transcribing) {
            ep.sendAfterMic = true;
            if (EveData.listening) EveData.toggleMic();
            return;
        }
        if (!input.text.trim() || !ready || EveData.working) return;
        EveData.sendMessage(input.text);
        input.text = "";
    }

    // ================= attach popover =================
    Rectangle {
        visible: ep.attach
        anchors.right: parent.right; anchors.rightMargin: Theme.s(52)
        anchors.bottom: parent.bottom; anchors.bottomMargin: footer.height - Theme.s(22)
        width: Theme.s(300)
        height: attachCol.implicitHeight + Theme.s(20)
        radius: Theme.s(16)
        color: "#1C1C1F"
        border.width: 1; border.color: Theme.white(0.1)
        z: 6
        MouseArea { anchors.fill: parent }
        Column {
            id: attachCol
            x: Theme.s(10); y: Theme.s(10)
            width: parent.width - Theme.s(20)
            spacing: Theme.s(8)
            HoverButton {
                width: parent.width; height: Theme.s(48); radius: Theme.s(11)
                onClicked: { ep.attach = false; picker.running = true; }
                Row {
                    x: Theme.s(10); anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.s(12)
                    Rectangle {
                        width: Theme.s(30); height: Theme.s(30); radius: Theme.s(9); color: Theme.accentSoft
                        Icon { anchors.centerIn: parent; path: "M12 16 V4 M7 9 L12 4 L17 9 M5 20 H19"; size: Theme.s(15); color: Theme.accent }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text { text: "Upload a file"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.Medium }
                        Text { text: "PDF, spreadsheet or image"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                    }
                }
            }
            Text { leftPadding: Theme.s(6); topPadding: Theme.s(4); text: "From this chat"; color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
            Text { leftPadding: Theme.s(6); bottomPadding: Theme.s(6); text: "No images in this chat yet."; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
        }
    }
    // the file picker (a normal dialog); the chosen file becomes a chip over the box
    Process {
        id: picker
        command: ["zenity", "--file-selection", "--title=Attach a file",
            "--file-filter=Documents and images | *.pdf *.csv *.xls *.xlsx *.ods *.png *.jpg *.jpeg *.webp *.gif *.txt *.md",
            "--file-filter=All files | *"]
        stdout: StdioCollector { onStreamFinished: { EveData.addAttachment(text); input.forceActiveFocus(); } }
    }

    // ================= sidebar =================
    Rectangle {
        visible: ep.side
        anchors.fill: parent
        radius: Theme.s(24)
        color: Qt.rgba(0, 0, 0, 0.45)
        z: 7
        MouseArea { anchors.fill: parent; onClicked: ep.side = false }
    }
    Rectangle {
        visible: ep.side
        width: Theme.s(300); height: parent.height
        z: 8
        radius: Theme.s(24)
        color: Theme.surface === "glass" ? Qt.rgba(24 / 255, 24 / 255, 27 / 255, 0.97) : "#121214"
        Rectangle { anchors.right: parent.right; width: Theme.s(24); height: parent.height; color: parent.color }
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.white(0.08) }
        MouseArea { anchors.fill: parent }
        Flickable {
            anchors.fill: parent
            anchors.margins: Theme.s(12)
            contentHeight: sideCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            WheelScroll {}
            Column {
                id: sideCol
                width: parent.width
                spacing: Theme.s(4)
                RowLayout {
                    width: parent.width
                    Row {
                        Layout.fillWidth: true
                        leftPadding: Theme.s(4)
                        spacing: Theme.s(10)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.s(22); height: Theme.s(22); radius: Theme.s(11)
                            gradient: Gradient { GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.25) } GradientStop { position: 1; color: Qt.darker(Theme.accent, 1.6) } }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: EveData.assistantName; color: Theme.text; font.family: Theme.sans; font.pointSize: Theme.sf(11.25); font.weight: Font.Bold }
                    }
                    HoverButton {
                        implicitWidth: Theme.s(32); implicitHeight: Theme.s(32)
                        onClicked: ep.side = false
                        Icon { anchors.centerIn: parent; path: "M5 4 H19 A2 2 0 0 1 21 6 V18 A2 2 0 0 1 19 20 H5 A2 2 0 0 1 3 18 V6 A2 2 0 0 1 5 4 Z M9 4 V20"; size: Theme.s(17); color: Theme.text }
                    }
                }
                Item { width: 1; height: Theme.s(6) }
                SideItem { label: "New chat"; icon: "M4 20 H8 L19 9 L15 5 L4 16 Z M13.5 6.5 L17.5 10.5"; bold: true; onClicked: { EveData.newChat(); ep.side = false; input.forceActiveFocus(); } }
                // search chats
                Rectangle {
                    width: parent.width; height: Theme.s(38); radius: Theme.s(10)
                    color: search.activeFocus ? Theme.white(0.06) : "transparent"
                    Icon { x: Theme.s(10); anchors.verticalCenter: parent.verticalCenter; path: "M16 16 L20 20 M11 5 A6 6 0 1 0 11.01 5"; size: Theme.s(15); color: Theme.text2 }
                    TextInput {
                        id: search
                        x: Theme.s(35); width: parent.width - Theme.s(45)
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13)
                        onTextChanged: ep.query = text.toLowerCase()
                        Text { visible: !search.text; text: "Search chats"; color: Theme.text2; font: search.font }
                    }
                }
                Text { topPadding: Theme.s(12); bottomPadding: Theme.s(6); leftPadding: Theme.s(10); text: "Apps"; color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                Grid {
                    width: parent.width
                    columns: 3
                    spacing: Theme.s(6)
                    Repeater {
                        model: EveData.apps
                        delegate: HoverButton {
                            id: appB
                            required property var modelData
                            width: (sideCol.width - Theme.s(12)) / 3; height: Theme.s(64); radius: Theme.s(12)
                            hoverFill: false
                            color: EveData.app && EveData.app === appB.modelData.id ? Theme.accentSoft : hovered ? Theme.white(0.09) : Theme.white(0.05)
                            onClicked: { EveData.openApp(appB.modelData.id); ep.side = false; }
                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.s(6)
                                Icon { anchors.horizontalCenter: parent.horizontalCenter; path: appB.modelData.icon; size: Theme.s(17); color: Theme.accent }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: appB.modelData.name; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                            }
                        }
                    }
                }
                Text { topPadding: Theme.s(14); bottomPadding: Theme.s(4); leftPadding: Theme.s(10); text: "Projects"; color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                Repeater {
                    model: EveData.projects
                    delegate: Column {
                        id: proj
                        required property var modelData
                        property bool expanded: false
                        width: sideCol.width
                        SideItem {
                            label: proj.modelData.name + "  ·  " + proj.modelData.chats.length
                            icon: "M3 7 A2 2 0 0 1 5 5 H9 L11 7 H19 A2 2 0 0 1 21 9 V17 A2 2 0 0 1 19 19 H5 A2 2 0 0 1 3 17 Z"
                            iconColor: proj.expanded ? Theme.accent : Theme.muted
                            onClicked: proj.expanded = !proj.expanded
                        }
                        Item {
                            visible: proj.expanded
                            x: Theme.s(17)
                            width: parent.width - Theme.s(17)
                            height: projChats.implicitHeight
                            Rectangle { width: 1; height: parent.height; color: Theme.white(0.1) }
                            Column {
                                id: projChats
                                x: Theme.s(10)
                                width: parent.width - Theme.s(10)
                                Repeater {
                                    model: proj.modelData.chats
                                    delegate: SideItem { required property var modelData; label: modelData; height: Theme.s(30) }
                                }
                                SideItem { label: "New chat in project"; icon: "M12 5 V19 M5 12 H19"; iconColor: Theme.dim; height: Theme.s(30) }
                            }
                        }
                    }
                }
                Text { visible: pinnedRep.count > 0; topPadding: Theme.s(14); bottomPadding: Theme.s(4); leftPadding: Theme.s(10); text: "Pinned"; color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                Repeater {
                    id: pinnedRep
                    model: EveData.chats.filter(c => c.pinned && (!ep.query || c.title.toLowerCase().indexOf(ep.query) >= 0))
                    delegate: SideItem { required property var modelData; label: modelData.title; icon: "M9 4 H15 L14 9 L17 12 H7 L10 9 Z M12 12 V20"; iconColor: Theme.accent; active: EveData.current === modelData.id; deletable: true; onDeleteRequested: ep.askDelete(modelData.id); onClicked: { EveData.openChat(modelData.id); ep.side = false; } }
                }
                Text { topPadding: Theme.s(14); bottomPadding: Theme.s(4); leftPadding: Theme.s(10); text: "Chats"; color: Theme.dim; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
                Repeater {
                    model: EveData.chats.filter(c => !c.pinned && (!ep.query || c.title.toLowerCase().indexOf(ep.query) >= 0)).sort((a, b) => b.updated - a.updated)
                    delegate: SideItem { required property var modelData; label: modelData.title; active: EveData.current === modelData.id; deletable: true; onDeleteRequested: ep.askDelete(modelData.id); onClicked: { EveData.openChat(modelData.id); ep.side = false; } }
                }
                Text { visible: EveData.chats.length === 0; leftPadding: Theme.s(10); text: "No chats yet"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            }
        }
    }

    // ================= picture viewer =================
    Rectangle {
        id: viewer
        visible: ep.viewing !== null
        anchors.fill: parent
        radius: Theme.s(24)
        color: Qt.rgba(0, 0, 0, 0.92)
        z: 30
        focus: visible
        Keys.onEscapePressed: ep.viewing = null
        onVisibleChanged: if (visible) forceActiveFocus()
        MouseArea { anchors.fill: parent; onClicked: ep.viewing = null }
        Image {
            id: big
            anchors.fill: parent
            anchors.margins: Theme.s(20); anchors.topMargin: Theme.s(64); anchors.bottomMargin: Theme.s(56)
            source: ep.viewing ? ep.viewing.url : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            MouseArea { anchors.centerIn: parent; width: big.paintedWidth; height: big.paintedHeight }   // clicks on the picture keep it open
        }
        Text { visible: big.status === Image.Loading; anchors.centerIn: parent; text: "Loading…"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
        Text {
            x: Theme.s(20); y: Theme.s(24)
            width: parent.width - Theme.s(80)
            elide: Text.ElideMiddle
            text: ep.viewing ? ep.viewing.name : ""
            color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(14); font.weight: Font.DemiBold
        }
        HoverButton {
            anchors.right: parent.right; anchors.rightMargin: Theme.s(14); y: Theme.s(14)
            width: Theme.s(36); height: Theme.s(36); radius: Theme.s(11)
            onClicked: ep.viewing = null
            Icon { anchors.centerIn: parent; path: Icons.close; size: Theme.s(15); color: Theme.text }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.s(14)
            spacing: Theme.s(8)
            HoverButton {
                width: saveRow.implicitWidth + Theme.s(28); height: Theme.s(34); radius: Theme.s(17)
                hoverFill: false
                color: hovered ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
                // saved to ~/Downloads under its own name; a notification says where
                onClicked: Quickshell.execDetached(["sh", "-c", 'd="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"; mkdir -p "$d" && curl -fsS -o "$d/$2" "$1" && notify-send -a Tide "Picture saved" "$d/$2"', "save", ep.viewing.url, ep.viewing.name])
                Row {
                    id: saveRow
                    anchors.centerIn: parent
                    spacing: Theme.s(8)
                    Icon { anchors.verticalCenter: parent.verticalCenter; path: "M12 4 V15 M7 10 L12 15 L17 10 M5 20 H19"; size: Theme.s(14); color: Theme.ink }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Save to Downloads"; color: Theme.ink; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold }
                }
            }
            HoverButton {
                width: openLabel.implicitWidth + Theme.s(28); height: Theme.s(34); radius: Theme.s(17)
                hoverFill: false
                color: hovered ? Theme.white(0.16) : Theme.white(0.1)
                onClicked: Qt.openUrlExternally(ep.viewing.url)
                Text { id: openLabel; anchors.centerIn: parent; text: "Open in browser"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
            }
        }
    }

    // ================= delete confirmation =================
    Rectangle {
        visible: ep.confirmDelete !== null
        anchors.fill: parent
        radius: Theme.s(24)
        color: Qt.rgba(0, 0, 0, 0.55)
        z: 30
        MouseArea { anchors.fill: parent; onClicked: ep.confirmDelete = null }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.s(64), Theme.s(360))
            height: confirmCol.implicitHeight + Theme.s(40)
            radius: Theme.s(18)
            color: "#1C1C1F"
            border.width: 1; border.color: Theme.white(0.1)
            MouseArea { anchors.fill: parent }   // clicks on the card don't close it
            Column {
                id: confirmCol
                x: Theme.s(20); y: Theme.s(20)
                width: parent.width - Theme.s(40)
                spacing: Theme.s(10)
                Text { text: "Delete this chat?"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(16); font.weight: Font.DemiBold }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "“" + (ep.confirmDelete ? ep.confirmDelete.title : "") + "” and all its messages will be deleted. This can't be undone."
                    color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(13)
                    lineHeight: Theme.s(19); lineHeightMode: Text.FixedHeight
                }
                Item { width: 1; height: Theme.s(6) }
                Row {
                    anchors.right: parent.right
                    spacing: Theme.s(8)
                    HoverButton {
                        width: cancelLabel.implicitWidth + Theme.s(28); height: Theme.s(34); radius: Theme.s(10)
                        color: hovered ? Theme.white(0.12) : Theme.white(0.07)
                        hoverFill: false
                        onClicked: ep.confirmDelete = null
                        Text { id: cancelLabel; anchors.centerIn: parent; text: "Cancel"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
                    }
                    HoverButton {
                        width: deleteLabel.implicitWidth + Theme.s(28); height: Theme.s(34); radius: Theme.s(10)
                        hoverFill: false
                        color: hovered ? "#FF7B74" : "#FF6961"
                        onClicked: { EveData.remove(ep.confirmDelete.id); ep.confirmDelete = null; }
                        Text { id: deleteLabel; anchors.centerIn: parent; text: "Delete"; color: "#FFFFFF"; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold }
                    }
                }
            }
        }
    }

    component SideItem: HoverButton {
        id: si
        property string label
        property string icon: ""
        property color iconColor: Theme.text2
        property bool bold: false
        property bool active: false
        property bool deletable: false
        signal deleteRequested()
        width: parent ? parent.width : 0
        height: Theme.s(36)
        hoverFill: false
        HoverHandler { id: siHover }
        HoverButton {
            visible: si.deletable && siHover.hovered
            anchors.right: parent.right; anchors.rightMargin: Theme.s(4)
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.s(28); height: Theme.s(28); radius: Theme.s(8)
            z: 1
            onClicked: si.deleteRequested()
            Icon { anchors.centerIn: parent; path: "M5 7 H19 M10 7 V5 H14 V7 M7 7 L8 19 H16 L17 7"; size: Theme.s(14); color: hovered ? "#FF6961" : Theme.muted }
        }
        color: active ? Theme.white(0.08) : hovered ? Theme.white(0.06) : "transparent"
        Row {
            x: Theme.s(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s(10)
            Icon { visible: si.icon !== ""; anchors.verticalCenter: parent.verticalCenter; path: si.icon; size: Theme.s(15); color: si.iconColor }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: si.width - Theme.s(30) - (si.icon ? Theme.s(25) : 0) - (si.deletable && siHover.hovered ? Theme.s(26) : 0)
                elide: Text.ElideRight
                text: si.label
                color: si.bold || si.active ? Theme.text : Theme.soft
                font.family: Theme.sans; font.pointSize: Theme.sf(9.375); font.weight: si.bold ? Font.Medium : Font.Normal
            }
        }
    }
    component MenuItem: HoverButton {
        id: mi
        property string label
        property string icon
        property bool danger: false
        width: parent ? parent.width : 0
        height: Theme.s(36)
        Row {
            x: Theme.s(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s(10)
            Icon { anchors.verticalCenter: parent.verticalCenter; path: mi.icon; size: Theme.s(15); color: mi.danger ? "#FF6961" : Theme.text }
            Text { anchors.verticalCenter: parent.verticalCenter; text: mi.label; color: mi.danger ? "#FF6961" : Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
        }
    }
}
