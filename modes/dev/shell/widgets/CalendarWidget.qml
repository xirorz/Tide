import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// Calendar + reminders (design: 360 wide): the month with a dot on days that have
// reminders, the picked day's reminders, and + to add one (kept by Tide). Small is a
// "Today" tile instead: the date, big, and the next three reminders.
Item {
    id: cal
    property string size: "medium"
    readonly property bool small: size === "small"
    implicitWidth: Theme.s(small ? 220 : 360)
    implicitHeight: (small ? today.implicitHeight : col.implicitHeight) + Theme.s(36)
    readonly property var upcoming: Widgets.reminders.filter(r => r.date >= key(clk.date))
        .sort((a, b) => (a.date + a.time).localeCompare(b.date + b.time)).slice(0, 3)
    function when(r) {
        if (r.date === key(clk.date)) return r.time || "Today";
        const d = new Date(r.date + "T12:00:00");
        return Qt.formatDate(d, "ddd") + (r.time ? " " + r.time : "");
    }

    // small: today
    ColumnLayout {
        id: today
        visible: cal.small
        x: Theme.s(18); y: Theme.s(18)
        width: Theme.s(184)
        spacing: Theme.s(10)
        Column {
            spacing: Theme.s(0)
            Text { text: Qt.formatDate(clk.date, "dddd"); color: Theme.accent; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold }
            Text { text: clk.date.getDate(); color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(48); font.weight: Font.Light }
            Text { text: Qt.formatDate(clk.date, "MMMM yyyy"); color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.white(0.1) }
        Text { visible: cal.upcoming.length === 0; text: "Nothing coming up."; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
        Repeater {
            model: cal.small ? cal.upcoming : []
            delegate: Column {
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.s(1)
                Text { width: parent.width; elide: Text.ElideRight; text: modelData.title; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
                Text { text: cal.when(modelData); color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
            }
        }
    }
    SystemClock { id: clk; precision: SystemClock.Hours }
    property date shown: new Date(clk.date.getFullYear(), clk.date.getMonth(), 1)
    property date picked: clk.date
    property bool adding: false
    function key(d) { return Qt.formatDate(d, "yyyy-MM-dd"); }
    readonly property var dayReminders: Widgets.reminders.filter(r => r.date === key(picked))
    readonly property var cells: {
        const first = new Date(shown.getFullYear(), shown.getMonth(), 1);
        const days = new Date(shown.getFullYear(), shown.getMonth() + 1, 0).getDate();
        const out = [];
        for (let i = 0; i < first.getDay(); i++) out.push(null);
        for (let d = 1; d <= days; d++) out.push(new Date(shown.getFullYear(), shown.getMonth(), d));
        return out;
    }

    ColumnLayout {
        id: col
        visible: !cal.small
        x: Theme.s(18); y: Theme.s(18)
        width: Theme.s(324)
        spacing: Theme.s(14)
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: Qt.formatDate(cal.shown, "MMMM yyyy"); color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
            HoverButton { implicitWidth: Theme.s(28); implicitHeight: Theme.s(28); onClicked: cal.shown = new Date(cal.shown.getFullYear(), cal.shown.getMonth() - 1, 1); Icon { anchors.centerIn: parent; path: "M15 6 L9 12 L15 18"; color: Theme.text } }
            HoverButton { implicitWidth: Theme.s(28); implicitHeight: Theme.s(28); onClicked: cal.shown = new Date(cal.shown.getFullYear(), cal.shown.getMonth() + 1, 1); Icon { anchors.centerIn: parent; path: "M9 6 L15 12 L9 18"; color: Theme.text } }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 7
            columnSpacing: Theme.s(2); rowSpacing: Theme.s(2)
            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]
                delegate: Text { required property var modelData; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; bottomPadding: Theme.s(4); text: modelData; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
            }
            Repeater {
                model: cal.cells
                delegate: HoverButton {
                    id: day
                    required property var modelData
                    readonly property bool today: modelData && cal.key(modelData) === cal.key(clk.date)
                    readonly property bool sel: modelData && cal.key(modelData) === cal.key(cal.picked)
                    readonly property bool dot: modelData && Widgets.reminders.some(r => r.date === cal.key(modelData))
                    Layout.fillWidth: true
                    implicitHeight: Theme.s(38); radius: Theme.s(10)
                    enabled: modelData !== null
                    hoverFill: false
                    color: sel ? Theme.accent : today ? Theme.white(0.14) : hovered && modelData ? Theme.white(0.08) : "transparent"
                    onClicked: cal.picked = modelData
                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.s(2)
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: day.modelData ? day.modelData.getDate() : ""; color: day.sel ? Theme.ink : Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: day.sel ? Font.DemiBold : Font.Normal }
                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: Theme.s(4); height: Theme.s(4); radius: Theme.s(2); color: day.dot ? (day.sel ? Theme.ink : Theme.accent) : "transparent" }
                    }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.white(0.1) }
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: cal.key(cal.picked) === cal.key(clk.date) ? "Today" : Qt.formatDate(cal.picked, "dddd, MMMM d"); color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold }
            HoverButton {
                implicitWidth: Theme.s(26); implicitHeight: Theme.s(26); radius: Theme.s(13)
                hoverFill: false
                color: Theme.white(hovered ? 0.2 : 0.12)
                onClicked: { cal.adding = !cal.adding; if (cal.adding) titleIn.forceActiveFocus(); }
                Icon { anchors.centerIn: parent; path: cal.adding ? "M6 12 H18" : "M12 5 V19 M5 12 H19"; size: Theme.s(13); color: Theme.text }
            }
        }
        // add a reminder: what, and when (optional)
        RowLayout {
            visible: cal.adding
            Layout.fillWidth: true
            spacing: Theme.s(6)
            Field { id: titleIn; Layout.fillWidth: true; hint: "Reminder"; onAccepted: cal.addNow() }
            Field { id: timeIn; implicitWidth: Theme.s(90); hint: "9:00 AM"; onAccepted: cal.addNow() }
        }
        Repeater {
            model: cal.dayReminders
            delegate: Rectangle {
                id: rem
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Theme.s(44); radius: Theme.s(12)
                color: Theme.white(0.08)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.s(10); anchors.rightMargin: Theme.s(6)
                    spacing: Theme.s(10)
                    Rectangle { implicitWidth: Theme.s(3); implicitHeight: Theme.s(26); radius: Theme.s(2); color: Theme.accent }
                    Column {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { width: parent.width; elide: Text.ElideRight; text: rem.modelData.title; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.Medium }
                        Text { visible: rem.modelData.time !== ""; text: rem.modelData.time; color: Theme.text2; font.family: Theme.mono; font.pixelSize: Theme.s(11) }
                    }
                    HoverButton {
                        implicitWidth: Theme.s(24); implicitHeight: Theme.s(24); radius: Theme.s(8)
                        onClicked: Widgets.removeReminder(rem.modelData.id)
                        Icon { anchors.centerIn: parent; path: "M5 12 L10 17 L19 7"; size: Theme.s(13); color: Theme.text2 }
                    }
                }
            }
        }
        Text { visible: cal.dayReminders.length === 0 && !cal.adding; topPadding: Theme.s(2); bottomPadding: Theme.s(2); text: "Nothing scheduled."; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
    }
    function addNow() {
        Widgets.addReminder(titleIn.text, key(picked), timeIn.text);
        titleIn.text = ""; timeIn.text = "";
        adding = false;
    }
    component Field: Rectangle {
        id: fld
        property alias text: ti.text
        property string hint
        signal accepted()
        implicitHeight: Theme.s(32); radius: Theme.s(9)
        color: Qt.rgba(0, 0, 0, 0.3)
        border.width: 1; border.color: ti.activeFocus ? Theme.accentLine : Theme.white(0.12)
        function forceActiveFocus() { ti.forceActiveFocus(); }
        TextInput {
            id: ti
            anchors.fill: parent; anchors.leftMargin: Theme.s(10); anchors.rightMargin: Theme.s(10)
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12)
            onAccepted: fld.accepted()
            Keys.onEscapePressed: cal.adding = false
            Text { visible: !ti.text; anchors.verticalCenter: parent.verticalCenter; text: fld.hint; color: Theme.dim; font: ti.font }
        }
    }
}
