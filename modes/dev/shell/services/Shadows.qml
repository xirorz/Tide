pragma Singleton
import QtQuick
import Quickshell

// Surfaces whose shadow is drawn in the separate shadow layer (glass mode only).
Singleton {
    id: root
    property var items: []
    function add(s) { if (items.indexOf(s) < 0) items = items.concat([s]); }
    function remove(s) { items = items.filter(x => x !== s); }
}
