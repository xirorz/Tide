import QtQuick
import QtQuick.Shapes
import "../components/Icons.js" as Icons
import Quickshell
import Quickshell.Widgets
import ".."
import "../components"
import "../services"

// THE ISLAND: the center pill of the bar. One element that morphs (width, height and
// corner radius together, 0.42s with a slight springy overshoot) into each tool,
// then shrinks back to the clock. Content fades in after the shape settles.
Item {
    id: isl
    required property var screen

    readonly property bool here: IslandState.screenName === "" || IslandState.screenName === screen.name
    readonly property string mode: here ? IslandState.mode : "idle"
    // while recording, the clock is replaced by the recording pill
    // voice dictation and screen recording replace the clock while they run
    readonly property var voiceShapes: ({ recording: "voiceRec", transcribing: "voiceBusy", done: "voiceDone", error: "voiceDone" })
    // a timed mode (Session.qml) shows its time left in place of the clock, after
    // dictation and recording; clicking it shows the mode and when it ends. Holding
    // Mod+Esc while locked in takes over the island with the emergency-exit ring.
    property bool sessionInfo: false
    Timer { id: infoClose; interval: 4000; onTriggered: isl.sessionInfo = false }
    readonly property string shape: Session.holdVisible && here ? "sessionHold"
                                  : mode === "idle" && Voice.state !== "idle" ? voiceShapes[Voice.state]
                                  : mode === "idle" && Recording.active ? "recording"
                                  : mode === "idle" && Session.active && Session.endsAt > 0 ? (sessionInfo ? "sessionInfo" : "session")
                                  : mode === "eve" && Eve.stage === "working" && Eve.term.length > 0 ? "eveWork" : mode
    readonly property bool isOpen: mode !== "idle"
    // open tools take the keyboard and close on an outside click; the banner doesn't
    readonly property bool grabs: isOpen && ["notification", "volume", "brightness", "eve"].indexOf(mode) < 0
    // the rest of the screen dims slightly while a tool is open
    readonly property bool dims: isOpen && ["notification", "volume", "brightness", "recording", "eve", "eveWork", "voiceRec", "voiceBusy", "voiceDone", "session", "sessionInfo", "sessionHold"].indexOf(shape) < 0
    property alias body: body

    readonly property var sizes: ({
        idle: [220, 38, 19],
        launcher: [620, 640, 28],
        calculator: [320, 480, 30],
        clipboard: [500, 470, 28],
        capture: [560, 214, 28],
        notification: [500, 92, 32],
        power: [520, 144, 36],
        volume: [380, 48, 24],
        brightness: [300, 48, 24],
        recording: [132, 38, 19],
        session: [150, 38, 19],
        sessionInfo: [300, 38, 19],
        sessionHold: [340, 64, 32],
        confirm: [500, 120, 32],
        wallpapers: [760, 420, 28],
        resources: [1180, 772, 26],
        cleanup: [640, 680, 28],
        // voice dictation: as big as the old whisper overlay (160x64), so it pops
        voiceRec: [240, 64, 32],
        voiceBusy: [236, 64, 32],
        voiceDone: [248, 64, 32],
        eve: [600, 150, 34],
        themes: [640, 200, 32],
        eveWork: [660, 330, 34]
    })
    // the table is at the design's size; Appearance → Interface size scales it
    readonly property var designSize: (shape === "notification" && IslandState.bannerActions ? [500, 132, 32] : sizes[shape] || sizes.idle).map(v => Theme.s(v))
    // a panel bigger than the screen (a laptop) shrinks to fit, keeping its shape; its
    // content scales with it (fit)
    readonly property real fit: Math.min(1, (screen.width - Theme.s(48)) / designSize[0], (screen.height - Theme.s(10) - Theme.s(24)) / designSize[1])
    readonly property var size: designSize.map(v => v * fit)
    // corner radius after Appearance → roundness (never more than half the height)
    readonly property real sizeR: Math.min(size[1] / 2, size[2] * Theme.radiusScale)
    Connections { target: Theme; function onRadiusScaleChanged() { isl.morph(); } }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // the morph (motion sheet): 420ms, width, height and radius together; spring when
    // it grows, Standard (no dip) when it shrinks back.
    // When the island had content, it fades out first (150ms), then the shape
    // moves; new content fades in once the shape has started to settle.
    // Reduced motion: no morph, the shape jumps and the content just fades.
    property string lastShape: "idle"
    readonly property var pillShapes: ["idle", "recording", "voiceRec", "voiceBusy", "voiceDone", "session", "sessionInfo", "sessionHold"]
    onSizeChanged: morph()
    function morph() {
        if (body.width === size[0] && body.height === size[1] && body.radius === sizeR) { lastShape = shape; return; }
        // a panel's content fades before the shape moves; so does the clock (or another
        // pill) turning into a pill, or it ghosts in the stretching shape
        const hadContent = pillShapes.indexOf(lastShape) < 0 || pillShapes.indexOf(shape) >= 0 && lastShape !== shape;
        lastShape = shape;
        morphAnim.stop();
        if (Theme.reduceMotion) { body.width = size[0]; body.height = size[1]; body.radius = sizeR; return; }
        // opening and growing spring; closing and shrinking settle straight in (Standard)
        const shrinking = size[0] * size[1] < body.width * body.height;
        const curve = shrinking ? Theme.standard : Theme.islandSpring;
        wAnim.to = size[0]; wAnim.easing.bezierCurve = curve;
        hAnim.to = size[1]; hAnim.easing.bezierCurve = curve;
        rAnim.to = sizeR;
        waitHide.duration = hadContent ? Theme.durHide : 0;
        morphAnim.start();
    }
    SequentialAnimation {
        id: morphAnim
        PauseAnimation { id: waitHide; duration: 0 }
        ParallelAnimation {
            NumberAnimation { id: wAnim; target: body; property: "width"; duration: Theme.durMorph; easing.type: Easing.BezierSpline }
            NumberAnimation { id: hAnim; target: body; property: "height"; duration: Theme.durMorph; easing.type: Easing.BezierSpline }
            NumberAnimation { id: rAnim; target: body; property: "radius"; duration: Theme.durMorph; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.islandSpring }
        }
    }

    Item {
        id: body
        x: Math.round((isl.width - width) / 2)
        y: Theme.s(10)
        // set by morph(); starts at the resting size
        width: Theme.s(220)
        height: Theme.s(38)
        property real radius: Theme.s(19)
        z: 10
        Component.onCompleted: { width = isl.size[0]; height = isl.size[1]; radius = isl.sizeR; }

        // with the Text and icons bar the resting clock is bare text too; the island's
        // surface fades in as soon as it grows into anything else
        Surface {
            anchors.fill: parent; kind: "island"; radius: body.radius
            opacity: Theme.barStyle === "text" && isl.shape === "idle" ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.durHide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
        }
        // clicks on the island's own background stay in the island (they used to fall
        // through to the outside-click catcher and close it)
        MouseArea { anchors.fill: parent; enabled: isl.grabs }

        ClippingRectangle {
            anchors.fill: parent
            radius: body.radius
            color: "transparent"

            // ---- at rest: time and date only ----
            HoverButton {
                visible: opacity > 0
                enabled: isl.shape === "idle"
                // leaving: grows a little and fades to black (150ms) as the island opens;
                // coming back: fades in once the shape has settled
                PillFade { on: isl.shape === "idle" }
                scale: isl.shape === "idle" || Theme.reduceMotion ? 1 : 1.08
                Behavior on scale { NumberAnimation { duration: Theme.durHide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
                anchors.fill: parent
                followRoundness: false
                radius: body.radius
                onClicked: IslandState.open("launcher", isl.screen.name)
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.s(10)
                    Text {
                        anchors.baseline: date.baseline
                        text: Qt.formatDateTime(clock.date, "h:mm AP")
                        color: Theme.text
                        font.family: Theme.sans
                        font.pixelSize: Theme.s(13)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        id: date
                        text: Qt.formatDateTime(clock.date, "ddd, MMM d")
                        color: Theme.muted
                        font.family: Theme.sans
                        font.pixelSize: Theme.s(12)
                    }
                }
            }

            // ---- recording: red dot + elapsed time; only the stop square ends it ----
            Item {
                visible: opacity > 0
                enabled: isl.shape === "recording"
                // leaving: grows a little and fades to black (150ms) as the island opens;
                // coming back: fades in once the shape has settled
                PillFade { on: isl.shape === "recording" }
                scale: isl.shape === "recording" || Theme.reduceMotion ? 1 : 1.08
                Behavior on scale { NumberAnimation { duration: Theme.durHide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
                anchors.fill: parent
                // clicking the pill opens the launcher, like the clock does (the
                // recording keeps going; the red dot shows on the launcher)
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: IslandState.open("launcher", isl.screen.name)
                }
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.s(9)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.s(9); height: Theme.s(9); radius: Theme.s(5)
                        color: Theme.red
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: isl.shape === "recording"
                            NumberAnimation { from: 1; to: 0.3; duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOutCss }
                            NumberAnimation { from: 0.3; to: 1; duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOutCss }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Recording.time
                        color: Theme.text
                        font.family: Theme.mono
                        font.pixelSize: Theme.s(13)
                        font.weight: Font.Medium
                    }
                    // the stop button: a 10px square with a 24px hit area
                    HoverButton {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.s(24); height: Theme.s(24); radius: Theme.s(7)
                        onClicked: Recording.stop()
                        Rectangle {
                            anchors.centerIn: parent
                            width: Theme.s(10); height: Theme.s(10); radius: Theme.s(2)
                            color: Theme.fg(0.8)
                        }
                    }
                }
            }

            // ---- a timed mode: its icon and time left (a lock when locked in); a click
            // shows the mode and when it ends for a few seconds ----
            Item {
                anchors.fill: parent
                visible: opacity > 0
                PillFade { on: isl.shape === "session" || isl.shape === "sessionInfo" }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { isl.sessionInfo = !isl.sessionInfo; if (isl.sessionInfo) infoClose.restart(); }
                }
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.s(8)
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: Theme.s(15)
                        color: Theme.accent
                        path: Session.locked ? "M7 11 V8 A5 5 0 0 1 17 8 V11 M5 11 H19 V20 H5 Z" : "M12 4 A8 8 0 1 0 12.01 4 M12 8 V12 L15 14"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: isl.shape === "sessionInfo" ? Session.name + " · ends at " + Qt.formatTime(new Date(Session.endsAt * 1000), "h:mm AP") : Session.timeText(Session.secondsLeft)
                        color: Theme.text
                        font.family: isl.shape === "sessionInfo" ? Theme.sans : Theme.mono
                        font.pixelSize: Theme.s(13)
                        font.weight: Font.Medium
                    }
                }
            }

            // ---- the emergency exit: hold Mod+Esc 5 s while locked in ----
            Item {
                anchors.fill: parent
                visible: opacity > 0
                PillFade { on: isl.shape === "sessionHold" }
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.s(14)
                    Item {
                        width: Theme.s(40); height: Theme.s(40)
                        anchors.verticalCenter: parent.verticalCenter
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                fillColor: "transparent"; strokeColor: Theme.white(0.14); strokeWidth: Theme.s(4)
                                PathAngleArc { centerX: Theme.s(20); centerY: Theme.s(20); radiusX: Theme.s(17); radiusY: Theme.s(17); startAngle: 0; sweepAngle: 360 }
                            }
                            ShapePath {
                                fillColor: "transparent"; strokeColor: Theme.red; strokeWidth: Theme.s(4); capStyle: ShapePath.RoundCap
                                PathAngleArc { centerX: Theme.s(20); centerY: Theme.s(20); radiusX: Theme.s(17); radiusY: Theme.s(17); startAngle: -90; sweepAngle: 360 * Session.holdProgress }
                            }
                        }
                        Text { anchors.centerIn: parent; text: Math.max(1, Math.ceil(5 - 5 * Session.holdProgress)); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(14) }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s(2)
                        Text { text: "Keep holding to end " + Session.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13); font.weight: Font.DemiBold }
                        Text { text: "Let go to stay locked in"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                    }
                }
            }

            // ---- voice dictation: big mic + 5 live bars (+ time), then Transcribing…, then the result ----
            HoverButton {
                visible: opacity > 0
                enabled: isl.shape === "voiceRec"
                // leaving: grows a little and fades to black (150ms) as the island opens;
                // coming back: fades in once the shape has settled
                PillFade { on: isl.shape === "voiceRec" }
                scale: isl.shape === "voiceRec" || Theme.reduceMotion ? 1 : 1.08
                Behavior on scale { NumberAnimation { duration: Theme.durHide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard } }
                anchors.fill: parent
                followRoundness: false
                radius: body.radius
                // like the clock and the recording pill: a click opens the launcher
                // (dictation keeps going, the red dot shows); the stop square stops
                onClicked: IslandState.open("launcher", isl.screen.name)
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.s(18)
                    Icon { anchors.verticalCenter: parent.verticalCenter; path: Icons.mic; size: Theme.s(26); stroke: 2.2; color: Theme.red }
                    VoiceBars { anchors.verticalCenter: parent.verticalCenter; live: true }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Voice.time
                        color: Theme.muted
                        font.family: Theme.mono
                        font.pixelSize: Theme.s(13)
                    }
                    // stop: same as pressing SUPER+R again (goes on to Transcribing…)
                    HoverButton {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.s(24); height: Theme.s(24); radius: Theme.s(7)
                        onClicked: Voice.stop()
                        Rectangle {
                            anchors.centerIn: parent
                            width: Theme.s(10); height: Theme.s(10); radius: Theme.s(2)
                            color: Theme.fg(0.8)
                        }
                    }
                }
            }
            // Transcribing… and the result are two pills, so one fades out before the other comes in
            Item {
                anchors.fill: parent
                visible: opacity > 0
                PillFade { on: isl.shape === "voiceBusy" }
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.s(14)
                    VoiceBars { anchors.verticalCenter: parent.verticalCenter; live: false }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Transcribing…"
                        color: Theme.text
                        font.family: Theme.sans
                        font.pixelSize: Theme.s(15)
                        font.weight: Font.Medium
                    }
                }
            }
            Item {
                id: voiceResult
                anchors.fill: parent
                visible: opacity > 0
                PillFade { on: isl.shape === "voiceDone" }
                // kept while it fades out (Voice goes back to idle at the same moment)
                property bool failed: false
                Connections { target: Voice; function onStateChanged() { if (Voice.state === "done" || Voice.state === "error") voiceResult.failed = Voice.state === "error"; } }
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.s(14)
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        path: voiceResult.failed ? Icons.close : Icons.check
                        size: Theme.s(22); stroke: 2.4
                        color: voiceResult.failed ? Theme.red : Theme.accent
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: voiceResult.failed ? "Couldn't transcribe" : Voice.doneText
                        color: Theme.text
                        font.family: Theme.sans
                        font.pixelSize: Theme.s(15)
                        font.weight: Font.Medium
                    }
                }
            }

            // ---- launcher ----
            FadeIn {
                active: isl.shape === "launcher"
                Launcher {
                    id: launcher
                    width: Theme.s(620)
                    height: Theme.s(640)
                    onCloseRequested: IslandState.close()
                }
                onShown: item.reset()
            }

            // ---- calculator ----
            FadeIn {
                active: isl.shape === "calculator"
                Calculator {
                    id: calculator
                    width: Theme.s(320)
                    height: Theme.s(480)
                    onCloseRequested: IslandState.close()
                }
                onShown: item.reset()
            }

            // ---- clipboard history ----
            FadeIn {
                active: isl.shape === "clipboard"
                ClipboardPanel {
                    id: clipboard
                    width: Theme.s(500)
                    height: Theme.s(470)
                    onCloseRequested: IslandState.close()
                }
                onShown: item.reset()
            }

            // ---- capture ----
            FadeIn {
                active: isl.shape === "capture"
                CapturePanel {
                    id: capture
                    width: Theme.s(560)
                    height: Theme.s(214)
                    onCloseRequested: IslandState.close()
                }
                onShown: item.reset()
            }

            // ---- resource center ----
            FadeIn {
                active: isl.shape === "resources"
                ResourceCenter {
                    id: resources
                    width: Theme.s(1180)
                    height: Theme.s(772)
                    scale: isl.fit
                    transformOrigin: Item.TopLeft
                    onCloseRequested: IslandState.close()
                }
                onShown: item.reset()
            }

            // ---- free up space ----
            FadeIn {
                active: isl.shape === "cleanup"
                CleanupPanel {
                    id: cleanup
                    width: Theme.s(640)
                    height: Theme.s(680)
                    scale: isl.fit
                    transformOrigin: Item.TopLeft
                    onCloseRequested: IslandState.close()
                }
                onShown: item.reset()
            }

            // ---- theme picker (modes) ----
            FadeIn {
                active: isl.shape === "themes"
                ThemesPanel {
                    id: themes
                    width: Theme.s(640)
                    height: Theme.s(200)
                    onCloseRequested: IslandState.close()
                }
                onShown: item.reset()
            }

            // ---- wallpaper picker ----
            FadeIn {
                active: isl.shape === "wallpapers"
                WallpaperPanel {
                    id: wallpapers
                    width: Theme.s(760)
                    height: Theme.s(420)
                    onCloseRequested: IslandState.close()
                }
                onShown: item.reset()
            }

            // ---- asking before a lock-in starts by hand ----
            FadeIn {
                active: isl.shape === "confirm"
                ConfirmStart {
                    id: confirmStart
                    width: Theme.s(500)
                    height: Theme.s(120)
                }
                onShown: item.reset()
            }

            // ---- power menu ----
            FadeIn {
                active: isl.shape === "power"
                PowerMenu {
                    id: power
                    width: Theme.s(520)
                    height: Theme.s(144)
                    onCloseRequested: IslandState.close()
                }
                onShown: item.reset()
            }

            // ---- brightness pop-up ----
            FadeIn {
                active: isl.shape === "brightness"
                BrightnessPopup {
                    width: Theme.s(300)
                    height: Theme.s(48)
                }
            }

            // ---- volume pop-up ----
            FadeIn {
                active: isl.shape === "volume"
                VolumePopup {
                    width: Theme.s(380)
                    height: Theme.s(48)
                }
            }

            // ---- Eve live mode (island/EveLive.qml: a local add-on, not in the shared
            // repo; without it this part of the island is simply empty) ----
            FadeIn {
                active: isl.shape === "eve" || isl.shape === "eveWork"
                Loader {
                    width: isl.size[0]
                    height: isl.size[1]
                    source: Qt.resolvedUrl("EveLive.qml")
                }
            }

            // ---- notification banner ----
            FadeIn {
                active: isl.shape === "notification"
                NotificationBanner {
                    width: Theme.s(500)
                    height: Theme.s(92)
                }
            }
        }

        // still recording (the screen, or your voice) while something else is in the
        // island: a pulsing red dot inside the top-right corner. Closing what's on top
        // brings the recording pill back.
        Rectangle {
            visible: (Recording.active && isl.shape !== "recording")
                     || (Voice.state === "recording" && isl.shape !== "voiceRec")
            readonly property real inset: Math.max(Theme.s(7), body.radius * 0.26)
            x: body.width - width - inset
            y: inset
            z: 20
            width: Theme.s(11); height: Theme.s(11); radius: Theme.s(5.5)
            color: Theme.red
            border.width: 2
            border.color: "#000000"
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: parent.visible
                NumberAnimation { from: 1; to: 0.35; duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOutCss }
                NumberAnimation { from: 0.35; to: 1; duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOutCss }
            }
        }
    }

    // .content: fade in 0.3s after a 0.12s delay, sliding down 6px
    component FadeIn: Item {
        id: fi
        property bool active: false
        signal shown()
        // the tool itself: built in the background once the bar is up (Boot.settled),
        // or right away if it's opened before then, and kept afterwards
        default property Component content
        readonly property alias item: ld.item
        property bool wanted: false
        // stays drawn while it fades out, so switching tools crossfades
        visible: active || holder.opacity > 0
        width: parent ? parent.width : 0
        height: parent ? parent.height : 0
        onActiveChanged: {
            if (active) { wanted = true; outAnim.stop(); anim.restart(); shown(); }
            else { anim.stop(); outAnim.restart(); }
        }

        Item {
            id: holder
            width: parent.width
            height: parent.height
            opacity: 0
            enabled: fi.active
            Loader {
                id: ld
                // opened before it was built: finish it now (a background build in
                // progress completes at once when asynchronous turns off)
                asynchronous: !fi.wanted && !Boot.finishNow
                active: fi.wanted || Boot.settled
                sourceComponent: fi.content
                onLoaded: if (!fi.wanted) Boot.ready("island")
            }
        }
        // in: wait for the old content to go (150ms) and the shape to start
        // settling (120ms), then fade in over 300ms rising 6px
        SequentialAnimation {
            id: anim
            PropertyAction { target: holder; property: "opacity"; value: 0 }
            PropertyAction { target: holder; property: "y"; value: Theme.reduceMotion ? 0 : -6 }
            PauseAnimation { duration: Theme.reduceMotion ? 0 : Theme.durHide + Theme.delayReveal }
            ParallelAnimation {
                NumberAnimation { target: holder; property: "opacity"; to: 1; duration: Theme.reduceMotion ? 150 : Theme.durReveal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
                NumberAnimation { target: holder; property: "y"; to: 0; duration: Theme.reduceMotion ? 0 : Theme.durReveal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
            }
        }
        // out: 150ms, before the shape moves
        ParallelAnimation {
            id: outAnim
            NumberAnimation { target: holder; property: "opacity"; to: 0; duration: Theme.durHide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
            NumberAnimation { target: holder; property: "y"; to: Theme.reduceMotion ? 0 : -4; duration: Theme.durHide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard }
        }
    }
}
