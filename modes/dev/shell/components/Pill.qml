import QtQuick
import ".."
import QtQuick.Layouts

// A 38px bar pill (radius 19) holding a row of items.
Item {
    id: p
    property string kind: "bar"
    property real padH: Theme.s(15)
    property alias spacing: row.spacing
    default property alias content: row.data

    implicitHeight: Theme.s(38)
    implicitWidth: row.implicitWidth + padH * 2

    Surface { anchors.fill: parent; kind: p.kind; radius: Theme.s(19) }

    RowLayout {
        id: row
        x: p.padH
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.s(8)
    }
}
