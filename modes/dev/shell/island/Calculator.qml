import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components/Icons.js" as Icons
import "MathEval.js" as M
import ".."
import "../components"
import "../services"

// The island calculator (320x480): history line, the expression, the live result in
// the accent, and a 4x5 keypad. Typing works too: digits and operators, Enter for =,
// Backspace deletes, Escape closes. Clicking the result copies it.
Item {
    id: calc
    signal closeRequested()

    readonly property string expr: IslandState.calcExpr
    readonly property var live: M.evalMath(expr)

    function pretty(e) {
        return e.replace(/\*/g, " × ").replace(/\//g, " ÷ ").replace(/\+/g, " + ").replace(/(\d)-/g, "$1 − ");
    }
    function press(k) {
        if (k === "AC") { IslandState.calcExpr = ""; IslandState.calcHist = ""; return; }
        if (k === "back") { IslandState.calcExpr = expr.slice(0, -1); return; }
        if (k === "=") {
            const v = M.evalMath(expr);
            if (v === null) return;
            IslandState.calcHist = pretty(expr) + " =";
            IslandState.calcExpr = String(parseFloat(v.toPrecision(12)));
            return;
        }
        IslandState.calcExpr = expr + k;
    }
    function copyResult() {
        const v = live !== null ? live : null;
        if (v === null) return;
        Quickshell.execDetached(["wl-copy", M.plain(v)]);
    }
    function reset() { forceActiveFocus(); }

    focus: true
    Keys.onPressed: event => {
        const t = event.text;
        if (event.key === Qt.Key_Escape) calc.closeRequested();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || t === "=") press("=");
        else if (event.key === Qt.Key_Backspace) press("back");
        else if (event.key === Qt.Key_Delete) press("AC");
        else if (/^[0-9.+\-*/()%^]$/.test(t)) press(t);
        else if (t === "x" || t === "×") press("*");
        else if (t === "÷") press("/");
        else if (t === "−") press("-");
        else return;
        event.accepted = true;
    }

    readonly property string numBg: Theme.white(0.08)
    readonly property string fnBg: Theme.white(0.04)
    readonly property var keys: [
        ["AC", "AC", "fn"], ["(", "(", "fn"], [")", ")", "fn"], ["÷", "/", "op"],
        ["7", "7", "num"], ["8", "8", "num"], ["9", "9", "num"], ["×", "*", "op"],
        ["4", "4", "num"], ["5", "5", "num"], ["6", "6", "num"], ["−", "-", "op"],
        ["1", "1", "num"], ["2", "2", "num"], ["3", "3", "num"], ["+", "+", "op"],
        ["%", "%", "fn"], ["0", "0", "num"], [".", ".", "num"], ["=", "=", "eq"]
    ]

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.s(16)
        spacing: Theme.s(12)

        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: "Calculator"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.type.h2[0]; font.weight: Theme.type.h2[1] }
            HoverButton {
                implicitWidth: Theme.s(26); implicitHeight: Theme.s(26)
                onClicked: calc.closeRequested()
                Icon { anchors.centerIn: parent; path: Icons.close; size: Theme.s(14); color: Theme.muted }
            }
        }

        // display: history, expression, live result (click to copy)
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: Theme.s(84)
            Layout.leftMargin: Theme.s(6)
            Layout.rightMargin: Theme.s(6)
            Layout.topMargin: Theme.s(6)
            Layout.bottomMargin: Theme.s(10)
            spacing: Theme.s(4)
            Text {
                Layout.fillWidth: true
                Layout.minimumHeight: Theme.s(18)
                horizontalAlignment: Text.AlignRight
                // same as the expression: 13px down to 8px, then cut off on the left
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Theme.s(8)
                elide: Text.ElideLeft
                text: IslandState.calcHist
                color: Theme.dim
                font.family: Theme.mono
                font.pixelSize: Theme.s(13)
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                // long expressions shrink to fit (36px down to 22px, about 60%), and
                // only past that cut off on the left so the newest digits stay visible
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Theme.s(22)
                elide: Text.ElideLeft
                text: calc.expr ? calc.pretty(calc.expr) : "0"
                color: Theme.text
                font.family: Theme.mono
                font.pixelSize: Theme.s(36)
                font.weight: Font.Medium
                font.letterSpacing: -0.02 * 36
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: calc.copyResult() }
            }
            Text {
                Layout.alignment: Qt.AlignRight
                Layout.minimumHeight: Theme.s(18)
                text: calc.live !== null && calc.expr && String(calc.live) !== calc.expr ? "= " + M.fmt(calc.live) : ""
                color: Theme.accent
                font.family: Theme.mono
                font.pixelSize: Theme.s(13)
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: calc.copyResult() }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 4
            rowSpacing: Theme.s(8)
            columnSpacing: Theme.s(8)
            uniformCellWidths: true
            uniformCellHeights: true
            Repeater {
                model: calc.keys
                delegate: HoverButton {
                    required property var modelData
                    readonly property string kind: modelData[2]
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.s(14)
                    hoverFill: false
                    color: kind === "op" ? Theme.accentSoft : kind === "eq" ? Theme.accent : kind === "fn" ? calc.fnBg : calc.numBg
                    onClicked: calc.press(modelData[1])
                    Text {
                        anchors.centerIn: parent
                        text: modelData[0]
                        color: kind === "op" ? Theme.accent : kind === "eq" ? Theme.ink : kind === "fn" ? Theme.text2 : Theme.text
                        font.family: Theme.sans
                        font.pixelSize: Theme.s(18)
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
}
