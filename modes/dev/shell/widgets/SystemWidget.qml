import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import ".."
import "../services"

// System at a glance (360 wide, like the design's cards): CPU, memory, GPU, network
// speed and temperature from Stats (already running for the bar) and every mounted
// drive from Drives (checked every 5 minutes), so the widget adds no polling of its
// own. Settings → Widgets hides sections (theme.json "widgets"."system"). Small is
// rings for CPU, memory and GPU with the network speed under them.
Item {
    id: sw
    property string size: "medium"
    readonly property bool small: size === "small"
    implicitWidth: Theme.s(small ? 260 : 360)
    implicitHeight: (small ? mini.implicitHeight : col.implicitHeight) + Theme.s(32)

    function rate(b) { return b >= 1048576 ? (b / 1048576).toFixed(1) + " MB/s" : Math.round(b / 1024) + " KB/s"; }

    // the last 60 seconds of network rates, sampled from Stats once a second
    property var rxHist: []
    property var txHist: []
    Timer {
        interval: 1000; repeat: true
        running: Widgets.systemShows("network") && !sw.small
        onTriggered: {
            sw.rxHist = sw.rxHist.concat([Stats.rx]).slice(-60);
            sw.txHist = sw.txHist.concat([Stats.tx]).slice(-60);
        }
    }

    component Meter: ColumnLayout {
        id: m
        property string label
        property string value
        property real progress: -1
        Layout.fillWidth: true
        spacing: Theme.s(6)
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: m.label; color: Theme.text; font.family: Theme.sans; font.pixelSize: Theme.s(12) }
            Text { text: m.value; color: Theme.text2; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
        }
        Rectangle {
            visible: m.progress >= 0
            Layout.fillWidth: true
            implicitHeight: Theme.s(4); radius: Theme.s(2)
            color: Theme.white(0.18)
            Rectangle {
                width: parent.width * Math.min(1, Math.max(0, m.progress)); height: parent.height; radius: Theme.s(2)
                color: m.progress >= 0.9 ? Theme.red : Theme.accent
            }
        }
    }

    // one direction of the network: arrow, rate and a sparkline of the last minute
    component Rate: ColumnLayout {
        id: r
        property string arrow
        property real value
        property var hist: []
        property color tint
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: Theme.s(6)
        Text { text: r.arrow + " " + sw.rate(r.value); color: r.tint; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
        Canvas {
            Layout.fillWidth: true
            implicitHeight: Theme.s(22)
            property var h: r.hist
            onHChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.reset();
                if (h.length < 2) return;
                const max = Math.max(1024, ...h), step = width / 59;
                c.beginPath();
                h.forEach((v, i) => {
                    const x = width - (h.length - 1 - i) * step, y = height - 1 - (v / max) * (height - 2);
                    i ? c.lineTo(x, y) : c.moveTo(x, y);
                });
                c.strokeStyle = r.tint;
                c.lineWidth = 1.5;
                c.stroke();
                c.lineTo(width, height); c.lineTo(width - (h.length - 1) * step, height); c.closePath();
                c.fillStyle = Qt.rgba(r.tint.r, r.tint.g, r.tint.b, 0.15);
                c.fill();
            }
        }
    }

    // a ring with the value inside and a label under it (small)
    component UsageRing: Column {
        id: g
        property real value: 0
        property string label
        spacing: Theme.s(6)
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.s(56); height: Theme.s(56)
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"; strokeColor: Theme.white(0.14); strokeWidth: Theme.s(4)
                    PathAngleArc { centerX: Theme.s(28); centerY: Theme.s(28); radiusX: Theme.s(25); radiusY: Theme.s(25); startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    fillColor: "transparent"; strokeWidth: Theme.s(4); capStyle: ShapePath.RoundCap
                    strokeColor: g.value <= 0 ? "transparent" : g.value >= 0.9 ? Theme.red : Theme.accent
                    PathAngleArc { centerX: Theme.s(28); centerY: Theme.s(28); radiusX: Theme.s(25); radiusY: Theme.s(25); startAngle: -90; sweepAngle: 360 * Math.max(0, Math.min(1, g.value)) }
                }
            }
            Text { anchors.centerIn: parent; text: Math.round(g.value * 100) + "%"; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: g.label; color: Theme.text2; font.family: Theme.sans; font.pixelSize: Theme.s(11) }
    }

    ColumnLayout {
        id: mini
        visible: sw.small
        x: Theme.s(18); y: Theme.s(16)
        width: Theme.s(224)
        spacing: Theme.s(12)
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: "System"; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold }
            Text { visible: Stats.temp >= 0; text: Stats.temp + "°C"; color: Theme.text2; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
        }
        RowLayout {
            Layout.fillWidth: true
            UsageRing { Layout.fillWidth: true; visible: Widgets.systemShows("cpu"); value: Stats.cpu / 100; label: "CPU" }
            UsageRing { Layout.fillWidth: true; visible: Widgets.systemShows("memory"); value: Stats.ramUsed / Stats.ramTotal; label: "Memory" }
            UsageRing { Layout.fillWidth: true; visible: Widgets.systemShows("gpu") && Stats.gpu >= 0; value: Stats.gpu / 100; label: "GPU" }
        }
        RowLayout {
            visible: Widgets.systemShows("network")
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: "↓ " + sw.rate(Stats.rx); color: Theme.netDown; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
            Text { text: "↑ " + sw.rate(Stats.tx); color: Theme.netUp; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
        }
    }

    ColumnLayout {
        id: col
        visible: !sw.small
        x: Theme.s(18); y: Theme.s(16)
        width: Theme.s(324)
        spacing: Theme.s(12)
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: "System"; color: Theme.soft; font.family: Theme.sans; font.pixelSize: Theme.s(12); font.weight: Font.DemiBold }
            Text { visible: Stats.temp >= 0; text: Stats.temp + "°C"; color: Theme.text2; font.family: Theme.mono; font.pixelSize: Theme.s(12) }
        }
        Meter { visible: Widgets.systemShows("cpu"); label: "CPU"; value: Stats.cpu + "%"; progress: Stats.cpu / 100 }
        Meter { visible: Widgets.systemShows("memory"); label: "Memory"; value: Stats.gb(Stats.ramUsed) + " / " + Stats.gbTotal(Stats.ramTotal) + " GB"; progress: Stats.ramUsed / Stats.ramTotal }
        Meter {
            visible: Widgets.systemShows("gpu") && Stats.gpu >= 0
            label: "GPU"
            value: Stats.gpu + "%" + (Stats.vramTotal > 0 ? "  ·  " + Stats.gb(Stats.vramUsed) + " / " + Stats.gbTotal(Stats.vramTotal) + " GB" : "")
            progress: Stats.gpu / 100
        }
        RowLayout {
            visible: Widgets.systemShows("network")
            Layout.fillWidth: true
            spacing: Theme.s(14)
            Rate { arrow: "↓"; value: Stats.rx; hist: sw.rxHist; tint: Theme.netDown }
            Rate { arrow: "↑"; value: Stats.tx; hist: sw.txHist; tint: Theme.netUp }
        }
        ColumnLayout {
            visible: Widgets.systemShows("drives") && Drives.list.length > 0
            Layout.fillWidth: true
            spacing: Theme.s(12)
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.white(0.1) }
            Repeater {
                model: Drives.list
                delegate: Meter {
                    required property var modelData
                    label: modelData.label
                    value: modelData.missing ? "not mounted" : Drives.gb(modelData.used) + " / " + Drives.gb(modelData.size)
                    progress: modelData.missing ? -1 : modelData.pct / 100
                }
            }
        }
    }
}
