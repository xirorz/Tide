import QtQuick
import ".."

// The design's .eq: four 2.5px bars in the wallpaper colors, each scaling 0.3 → 1 → 0.3
// over 0.9s ease-in-out, offset by -0.3s, -0.6s and -0.15s.
Row {
    id: eq
    property bool running: true
    spacing: Theme.s(2)
    height: Theme.s(12)
    property real phase: 0
    NumberAnimation on phase {
        from: 0; to: 1; duration: 900
        loops: Animation.Infinite
        // reduced motion: the bars hold still
        running: eq.running && !Theme.reduceMotion
    }
    Repeater {
        model: [0, 0.3, 0.6, 0.15]
        delegate: Rectangle {
            required property var modelData
            required property int index
            width: Theme.s(2.5)
            height: Theme.s(12)
            radius: Theme.s(2)
            color: Theme.eq[index]
            transform: Scale {
                origin.y: Theme.s(12)
                yScale: {
                    // keyframes 0%,100% → 0.3, 50% → 1, ease-in-out each half
                    let p = (eq.phase + modelData / 0.9) % 1;
                    let t = p < 0.5 ? p * 2 : (1 - p) * 2;
                    t = t * t * (3 - 2 * t);
                    return 0.3 + 0.7 * t;
                }
            }
        }
    }
}
