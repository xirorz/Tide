import QtQuick

// Snappy wheel scrolling for a Flickable/ListView: put it inside the list.
// A standard notch (angleDelta 120) moves `step` pixels (about 3 rows) at once,
// with no flick animation. High-resolution and free-spin wheels send small
// angleDelta steps, which scale the same way.
WheelHandler {
    id: ws
    // the nearest Flickable above (children of a Flickable land in its contentItem)
    property var flick: {
        let p = parent;
        while (p && typeof p.cancelFlick !== "function") p = p.parent;
        return p;
    }
    property real step: 140
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
        const f = ws.flick;
        if (!f || f.contentHeight <= f.height) return;
        // go by notches: Qt on Wayland reports every wheel as a "touchpad" and sends a
        // tiny 15px pixelDelta per notch, so neither can be trusted. Hi-res and
        // free-spin wheels send fractions of a notch, which scale the same way.
        const dy = event.angleDelta.y / 120 * ws.step;
        const top = f.originY;
        const bottom = f.originY + f.contentHeight - f.height;
        f.cancelFlick();
        f.contentY = Math.max(top, Math.min(bottom, f.contentY - dy));
        event.accepted = true;
    }
}
