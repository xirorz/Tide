import QtQuick

// A big arrow pointer for small hands (the system one is hidden in the games).
Canvas {
    property real k: 1
    width: Math.round(54 * k); height: Math.round(64 * k)
    z: 100
    onPaint: {
        const c = getContext("2d"); c.reset();
        c.scale(width / 24, height / 28);
        c.fillStyle = "#FFFFFF"; c.strokeStyle = "#1F2340"; c.lineWidth = 1.6; c.lineJoin = "round";
        c.beginPath(); c.moveTo(3, 2); c.lineTo(20, 13); c.lineTo(12, 14.5); c.lineTo(16, 24); c.lineTo(12.5, 25.5);
        c.lineTo(8.5, 16); c.lineTo(3, 21); c.closePath(); c.fill(); c.stroke();
    }
}
