import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../components/Icons.js" as Icons
import ".."
import "../components"
import "../services"

// The island's clipboard history (500x470): newest first, each with a thumbnail by
// kind (text, link, color swatch, image). Click a row to copy it, the trash icon
// (shown on hover) deletes it, Clear all empties the history. Escape closes.
Item {
    id: cp
    signal closeRequested()
    property string copiedId: ""

    function reset() {
        copiedId = "";
        list.positionViewAtBeginning();
        ClipHist.refresh();
        forceActiveFocus();
    }
    focus: true
    Keys.onEscapePressed: cp.closeRequested()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.s(14)
        spacing: Theme.s(10)

        // header
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.s(4)
            Layout.rightMargin: Theme.s(4)
            Row {
                Layout.fillWidth: true
                Text { text: "Clipboard"; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.type.h2[0]; font.weight: Theme.type.h2[1] }
                Text {
                    anchors.baseline: parent.children[0].baseline
                    text: " · " + ClipHist.entries.length + (ClipHist.entries.length === 1 ? " item" : " items")
                    color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12)
                }
            }
            Row {
                spacing: Theme.s(4)
                HoverButton {
                    width: clearLbl.implicitWidth + Theme.s(20); height: Theme.s(28)
                    onClicked: ClipHist.clearAll()
                    Text { id: clearLbl; anchors.centerIn: parent; text: "Clear all"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                }
                HoverButton {
                    width: Theme.s(28); height: Theme.s(28)
                    onClicked: cp.closeRequested()
                    Icon { anchors.centerIn: parent; path: Icons.close; size: Theme.s(14); color: Theme.muted }
                }
            }
        }

        // entries (scrolls, no scrollbar)
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.s(4)
            boundsBehavior: Flickable.StopAtBounds
            model: ClipHist.entries
            WheelScroll {}
            delegate: ClipRow {
                required property var modelData
                width: list.width
                entry: modelData
            }

            Text {
                visible: ClipHist.entries.length === 0
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.s(30)
                text: "Nothing copied yet."
                color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(12)
            }
        }
    }

    component ClipRow: Rectangle {
        id: row
        property var entry
        readonly property bool copied: cp.copiedId === entry.id
        readonly property bool code: entry.kind === "text" && /[(){};=]/.test(entry.text)
        height: Theme.s(56)
        radius: Theme.s(12)
        color: copied ? Theme.accentSoft : rowHover.hovered ? Theme.white(0.07) : "transparent"

        HoverHandler { id: rowHover }

        // decode image entries once for the thumbnail
        property string thumb: ""
        Process {
            running: row.entry.kind === "image"
            command: ["sh", "-c", "mkdir -p \"$1\" && f=\"$1/$2.png\" && { [ -s \"$f\" ] || cliphist decode \"$2\" > \"$f\"; } && echo \"$f\"",
                      "sh", ClipHist.thumbDir, row.entry.id]
            stdout: StdioCollector { onStreamFinished: row.thumb = text.trim() }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // copy, then close: you got what you came for
            onClicked: { ClipHist.copy(row.entry.id); cp.closeRequested(); }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.s(10)
            anchors.rightMargin: Theme.s(8)
            spacing: Theme.s(12)

            // thumbnail by kind
            ClippingRectangle {
                implicitWidth: Theme.s(40); implicitHeight: Theme.s(40); radius: Theme.s(10)
                color: row.entry.kind === "color" ? row.entry.text : Theme.white(0.08)
                border.width: row.entry.kind === "color" ? 1 : 0
                border.color: Theme.white(0.2)
                Icon {
                    anchors.centerIn: parent
                    visible: row.entry.kind === "text" || row.entry.kind === "link"
                    path: row.entry.kind === "link" ? Icons.link : Icons.lines
                    color: Theme.text2
                }
                Image {
                    anchors.fill: parent
                    visible: row.entry.kind === "image"
                    source: row.thumb ? "file://" + row.thumb : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(80, 80)
                    asynchronous: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.s(2)
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: row.entry.text
                    color: Theme.text
                    font.family: row.code ? Theme.mono : Theme.sans
                    font.pointSize: (row.code ? Theme.sf(12) : Theme.sf(12.5)) * 0.75
                }
                Text { text: ClipHist.metaLine(row.entry); color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
            }
            Text {
                visible: row.copied
                rightPadding: Theme.s(4)
                text: "Copied"
                color: Theme.accent; font.family: Theme.sans; font.pixelSize: Theme.s(11)
            }
            HoverButton {
                implicitWidth: Theme.s(28); implicitHeight: Theme.s(28)
                opacity: rowHover.hovered ? 1 : 0
                onClicked: ClipHist.remove(row.entry.id)
                Icon { anchors.centerIn: parent; path: Icons.trash; size: Theme.s(14); color: Theme.muted }
            }
        }
    }
}
