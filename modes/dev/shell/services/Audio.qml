pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import ".."

// The output sinks the control center and the volume pop-up switch between
// ("speakersSink" / "headphonesSink" in theme.json are parts of their names), and
// the default sink's volume.
Singleton {
    id: root
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    function sinkFor(part) { return sinks.find(n => (n.description || n.name).indexOf(part) >= 0) || null; }
    readonly property var speakers: sinkFor(Theme.speakersSink)
    readonly property var headphones: sinkFor(Theme.headphonesSink)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property bool headphonesActive: sink !== null && sink === headphones

    function setVolume(v) { if (sink && sink.audio) sink.audio.volume = Math.max(0, Math.min(1, v)); }
    function use(node) { if (node) Pipewire.preferredDefaultAudioSink = node; }
    // headphones <-> studio speakers
    function toggleOutput() { use(headphonesActive ? speakers : headphones); }

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }
}
