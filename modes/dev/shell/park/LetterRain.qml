import QtQuick
import ".."
import "../services"

// Letter Rain: typing practice. A big letter drifts down and the voice says it; pressing
// that key pops it (a star). A wrong key is just a soft boop. A letter that reaches the
// grass floats back up and is said again: nothing is ever lost. Level 1: a few letters,
// slow; level 2: the whole alphabet; level 3: two at a time, a bit faster.
Item {
    id: g
    property real k: 1
    function u(px) { return Math.round(px * k); }
    focus: true

    readonly property var levelsDef: [
        { set: "ABCDEFGH", speed: 45, goal: 8, many: 1 },
        { set: "ABCDEFGHIJKLMNOPQRSTUVWXYZ", speed: 60, goal: 10, many: 1 },
        { set: "ABCDEFGHIJKLMNOPQRSTUVWXYZ", speed: 75, goal: 12, many: 2 }
    ]
    property int level: Math.min(3, Park.levels.letters || 1)
    property int done: 0
    readonly property var def: levelsDef[level - 1]
    readonly property var colors: ["#FF5C8A", "#3E6AD8", "#2FA055", "#8F57D0", "#E08A00"]

    ListModel { id: letters }
    ListModel { id: bursts }

    function drop() {
        const ch = def.set[Math.floor(Math.random() * def.set.length)];
        for (let i = 0; i < letters.count; i++) if (letters.get(i).ch === ch) return drop();
        const s = u(190);
        letters.append({ ch: ch, lx: u(200) + Math.random() * (width - u(400) - s), ly: -s, ls: s, col: colors[Math.floor(Math.random() * colors.length)] });
        Park.say("letter-" + ch.toLowerCase());
    }
    function start() { letters.clear(); for (let i = 0; i < def.many; i++) Qt.callLater(drop); }
    Component.onCompleted: Qt.callLater(start)
    onLevelChanged: start()


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

    function press(ch) {
        lastAct = Date.now();
        for (let i = 0; i < letters.count; i++) {
            const l = letters.get(i);
            if (l.ch !== ch) continue;
            bursts.append({ x0: l.lx + l.ls / 2, y0: l.ly + l.ls / 2, made: Date.now() });
            letters.remove(i);
            Park.fx("pop"); Park.star(1);
            done++;
            if (done >= def.goal) {
                done = 0;
                Park.say(level < 3 ? "great" : "wow"); Park.fx("ding");
                nudgeAfterLevel.restart();
                if (level < 3) { level++; Park.levelUp("letters", level); }
                else start();
                return;
            }
            dropLater.restart();
            return;
        }
        Park.fx("boop");
    }
    Timer { id: dropLater; interval: 900; onTriggered: { while (letters.count < g.def.many) g.drop(); } }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#B9D4FF" }
            GradientStop { position: 1; color: "#E8F1FF" }
        }
    }
    Hills { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: g.u(160) }

    Timer {
        interval: 16; repeat: true; running: true
        onTriggered: {
            for (let i = 0; i < letters.count; i++) {
                const l = letters.get(i);
                let y = l.ly + g.u(g.def.speed) * 0.016;
                // reached the grass: back to the top, and said again
                if (y + l.ls > g.height - g.u(110)) { y = -l.ls; Park.say("letter-" + l.ch.toLowerCase()); }
                letters.setProperty(i, "ly", y);
            }
            for (let j = bursts.count - 1; j >= 0; j--)
                if (Date.now() - bursts.get(j).made > 450) bursts.remove(j);
        }
    }

    Repeater {
        model: letters
        delegate: Item {
            required property string ch
            required property real lx
            required property real ly
            required property real ls
            required property string col
            x: lx; y: ly; width: ls; height: ls
            Rectangle { y: g.u(10); width: parent.width; height: parent.height; radius: g.u(36); color: Qt.darker(col, 1.25) }
            Rectangle {
                width: parent.width; height: parent.height; radius: g.u(36); color: "white"
                Text { anchors.centerIn: parent; text: ch; color: col; font.family: "Fredoka"; font.variableAxes: ({ "wght": 640 }); font.pixelSize: g.u(140); font.weight: Font.Bold }
            }
        }
    }
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
                    width: g.u(12); height: g.u(34); radius: width / 2; color: "#FFCE3D"
                    x: -width / 2; y: -height / 2
                    transform: [Translate { id: tr; y: -g.u(60) }, Rotation { angle: index * 45 }]
                    NumberAnimation on opacity { from: 1; to: 0; duration: 420 }
                    Component.onCompleted: rays.start()
                    NumberAnimation { id: rays; target: tr; property: "y"; from: -g.u(60); to: -g.u(150); duration: 420; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter; y: g.u(48)
        spacing: g.u(14)
        Repeater { model: 3; delegate: Rectangle { required property int index; width: g.u(22); height: width; radius: width / 2; color: index < g.level ? "#3E6AD8" : Qt.rgba(62 / 255, 106 / 255, 216 / 255, 0.25) } }
    }
    StarCount { anchors.right: parent.right; anchors.rightMargin: g.u(40); y: g.u(28); k: g.k }
    HomeButton { id: homeBtn; x: g.u(40); y: g.u(28); k: g.k; tint: "#3E6AD8"; nudge: g.tick < g.nudgeUntil }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.BlankCursor
        onPressed: m => { if (homeBtn.contains(mapToItem(homeBtn, m.x, m.y))) Park.home(); }
    }
    BigCursor { x: ma.mouseX; y: ma.mouseY; k: g.k; visible: ma.containsMouse }

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Escape) { Park.home(); return; }
        const t = (e.text || "").toUpperCase();
        if (/^[A-Z]$/.test(t)) g.press(t);
        e.accepted = true;
    }
}
