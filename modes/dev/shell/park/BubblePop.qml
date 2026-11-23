import QtQuick
import ".."
import "../services"

// Bubble Pop (design artboard 3): mouse practice. Big bubbles float up; clicking one pops
// it (a pop sound; a star every 3). Each level has smaller, faster bubbles; he starts
// at the level he reached last time. The cursor is drawn big; the house goes home.
Item {
    id: g
    property real k: 1
    function u(px) { return Math.round(px * k); }
    focus: true

    readonly property var levelsDef: [
        { size: 230, speed: 22, goal: 8 },
        { size: 170, speed: 40, goal: 10 },
        { size: 120, speed: 60, goal: 12 }
    ]
    property int level: Math.min(3, Park.levels.bubble || 1)
    property int popped: 0                // this level
    property int total: 0                 // this game, for the stars
    readonly property var def: levelsDef[level - 1]
    readonly property var colors: [["#9EDBFF", "#5BB4F5"], ["#FFB3CC", "#FF6F9C"], ["#C9F0A8", "#6CCB4A"], ["#E3C8FF", "#A66BF0"], ["#FFE3A3", "#FFB938"]]

    ListModel { id: bubbles }
    ListModel { id: bursts }

    function spawn(atBottom) {
        const s = u(def.size * (0.85 + Math.random() * 0.3));
        const c = colors[Math.floor(Math.random() * colors.length)];
        bubbles.append({ bx: u(140) + Math.random() * (width - u(280) - s), by: atBottom ? height + Math.random() * u(200) : u(160) + Math.random() * (height - u(260) - s),
                         bs: s, c1: c[0], c2: c[1], wob: Math.random() * 6.28, sp: u(def.speed) * (0.8 + Math.random() * 0.4) });
    }
    function fill() { bubbles.clear(); for (let i = 0; i < 4; i++) spawn(false); }
    Component.onCompleted: Qt.callLater(fill)
    onLevelChanged: fill()


    // the way home: after a level, or 10 s without playing, the house pulses (and now and
    // then the voice says to press it)
    property real lastAct: Date.now()
    property real nudgeUntil: 0
    property real lastNudgeVoice: 0
    property real tick: Date.now()
    function nudgeHome() {
        nudgeUntil = Date.now() + 6000;
        if (Date.now() - lastNudgeVoice > 30000) { lastNudgeVoice = Date.now(); Park.say("home"); }
    }
    Timer { id: nudgeAfterLevel; interval: 2000; onTriggered: g.nudgeHome() }
    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: { g.tick = Date.now(); if (g.tick - g.lastAct > 10000 && g.tick > g.nudgeUntil + 4000) g.nudgeHome(); }
    }

    function pop(i) {
        lastAct = Date.now();
        const b = bubbles.get(i);
        bursts.append({ x0: b.bx + b.bs / 2, y0: b.by + b.bs / 2, made: Date.now() });
        bubbles.remove(i);
        Park.fx("pop");
        popped++; total++;
        if (total % 3 === 0) Park.star(1);
        if (popped >= def.goal) {
            popped = 0;
            Park.say(level < 3 ? "great" : "wow");
            Park.fx("ding");
            nudgeAfterLevel.restart();
            if (level < 3) { level++; Park.levelUp("bubble", level); }
            else fill();
            return;
        }
        spawn(true);
    }

    // the sky
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#FFD6E5" }
            GradientStop { position: 1; color: "#FFE9D6" }
        }
    }

    // floating up, wobbling side to side
    Timer {
        interval: 16; repeat: true; running: true
        onTriggered: {
            const dt = 0.016;
            for (let i = bubbles.count - 1; i >= 0; i--) {
                const b = bubbles.get(i);
                const wob = b.wob + dt * 1.6;
                bubbles.setProperty(i, "wob", wob);
                bubbles.setProperty(i, "by", b.by - b.sp * dt);
                bubbles.setProperty(i, "bx", b.bx + Math.sin(wob) * g.u(0.6));
                if (b.by + b.bs < 0) { bubbles.remove(i); g.spawn(true); }
            }
            for (let j = bursts.count - 1; j >= 0; j--)
                if (Date.now() - bursts.get(j).made > 450) bursts.remove(j);
        }
    }

    Repeater {
        model: bubbles
        delegate: Rectangle {
            required property real bx
            required property real by
            required property real bs
            required property string c1
            required property string c2
            x: bx; y: by; width: bs; height: bs; radius: bs / 2
            gradient: Gradient {
                GradientStop { position: 0; color: "white" }
                GradientStop { position: 0.35; color: c1 }
                GradientStop { position: 1; color: c2 }
            }
            Rectangle { x: parent.width * 0.2; y: parent.height * 0.16; width: parent.width * 0.22; height: width; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.8) }
        }
    }
    // pops: a ring of white rays that grows and fades
    Repeater {
        model: bursts
        delegate: Item {
            required property real x0
            required property real y0
            x: x0; y: y0
            Repeater {
                model: 8
                delegate: Rectangle {
                    required property int index
                    width: g.u(10); height: g.u(30); radius: width / 2; color: "white"
                    x: -width / 2; y: -height / 2
                    transform: [Translate { id: tr; y: -g.u(40) }, Rotation { angle: index * 45 }]
                    NumberAnimation on opacity { from: 1; to: 0; duration: 420 }
                    Component.onCompleted: rays.start()
                    NumberAnimation { id: rays; target: tr; property: "y"; from: -g.u(40); to: -g.u(110); duration: 420; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    // level dots and stars
    Row {
        anchors.horizontalCenter: parent.horizontalCenter; y: g.u(48)
        spacing: g.u(14)
        Repeater { model: 3; delegate: Rectangle { required property int index; width: g.u(22); height: width; radius: width / 2; color: index < g.level ? "#FF5C8A" : Qt.rgba(1, 92 / 255, 138 / 255, 0.25) } }
    }
    StarCount { anchors.right: parent.right; anchors.rightMargin: g.u(40); y: g.u(28); k: g.k }
    HomeButton { id: homeBtn; x: g.u(40); y: g.u(28); k: g.k; tint: "#FF5C8A"; nudge: g.tick < g.nudgeUntil }

    // the big cursor; clicks pop bubbles (the topmost one under it)
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.BlankCursor
        onPressed: m => {
            if (homeBtn.contains(mapToItem(homeBtn, m.x, m.y))) { Park.home(); return; }
            for (let i = bubbles.count - 1; i >= 0; i--) {
                const b = bubbles.get(i);
                const dx = m.x - (b.bx + b.bs / 2), dy = m.y - (b.by + b.bs / 2);
                if (dx * dx + dy * dy <= (b.bs / 2) * (b.bs / 2)) { g.pop(i); return; }
            }
        }
    }
    BigCursor { x: ma.mouseX; y: ma.mouseY; k: g.k; visible: ma.containsMouse }
    Keys.onEscapePressed: Park.home()
}
