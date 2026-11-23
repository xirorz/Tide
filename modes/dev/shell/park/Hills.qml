import QtQuick

// The two green hills along the bottom of his space.
Canvas {
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c = getContext("2d"); c.reset();
        const w = width, h = height;
        c.fillStyle = "#9BDB7A"; c.beginPath(); c.moveTo(0, h * 0.6);
        c.bezierCurveTo(w * 0.17, h * 0.3, w * 0.33, h * 0.85, w * 0.5, h * 0.55);
        c.bezierCurveTo(w * 0.67, h * 0.25, w * 0.83, h * 0.3, w, h * 0.6); c.lineTo(w, h); c.lineTo(0, h); c.closePath(); c.fill();
        c.fillStyle = "#7CCB5E"; c.beginPath(); c.moveTo(0, h * 0.8);
        c.bezierCurveTo(w * 0.2, h * 0.55, w * 0.42, h, w * 0.62, h * 0.75);
        c.bezierCurveTo(w * 0.8, h * 0.6, w * 0.92, h * 0.65, w, h * 0.8); c.lineTo(w, h); c.lineTo(0, h); c.closePath(); c.fill();
    }
}
