import QtQuick
import ".."
import "../components"
import "../services"

// Quick notes (design: 340 × 150): a plain text pad, saved as you type
// (~/.local/state/tide/notes.md). Resizing changes the box (boxW × boxH, design
// pixels), not the text, so a bigger pad shows more lines.
Item {
    id: nw
    property real boxW: 340
    property real boxH: 150
    implicitWidth: Theme.s(boxW)
    implicitHeight: Theme.s(boxH)
    Text { x: Theme.s(16); y: Theme.s(16); text: "Quick notes"; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold }
    Flickable {
        id: fl
        x: Theme.s(16); y: Theme.s(42)
        width: nw.implicitWidth - Theme.s(32); height: nw.implicitHeight - Theme.s(42) - Theme.s(14)
        contentHeight: pad.contentHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        TextEdit {
            id: pad
            width: fl.width
            wrapMode: TextEdit.Wrap
            text: Widgets.notes
            color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(13)
            selectByMouse: true
            selectionColor: Theme.white(0.2)
            enabled: !Widgets.editing
            onTextChanged: if (text !== Widgets.notes) Widgets.setNotes(text)
            onCursorRectangleChanged: if (cursorRectangle.y + cursorRectangle.height > fl.contentY + fl.height) fl.contentY = cursorRectangle.y + cursorRectangle.height - fl.height
            Text { visible: !pad.text && !pad.activeFocus; text: "Jot something down…"; color: Theme.dim; font: pad.font }
        }
    }
}
