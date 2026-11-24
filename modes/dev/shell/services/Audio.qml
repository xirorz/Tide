pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import ".."

// Sound: the outputs and inputs (the control center picks the default of each) and
// their volumes. "speakersSink" / "headphonesSink" in theme.json (parts of names) are
// what the volume pop-up's quick switch flips between.
Singleton {
    id: root
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    function sinkFor(part) { return part ? sinks.find(n => (n.description || n.name).indexOf(part) >= 0) || null : null; }
    // both named outputs exist here: the control center shows them as two buttons
    readonly property bool quickPair: speakers !== null && headphones !== null
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

    // every output and input (the control center lists them), and the input's volume
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)
    readonly property var source: Pipewire.defaultAudioSource
    readonly property real inVolume: source && source.audio ? source.audio.volume : 0
    function setInVolume(v) { if (source && source.audio) source.audio.volume = Math.max(0, Math.min(1, v)); }
    function useSource(node) { if (node) Pipewire.preferredDefaultAudioSource = node; }
    function label(n) { return n ? (n.description || n.nickname || n.name) : "None"; }

    PwObjectTracker { objects: [root.sink, root.source].filter(n => n) }
}
