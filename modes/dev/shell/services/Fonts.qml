pragma Singleton
import QtQuick
import Quickshell

// Tide's own fonts (~/.config/Tide/fonts, each with its OFL license), loaded here so the
// shell never depends on fonts installed on the system or by another project.
//   interface: Inter (default), Geist, DM Sans, IBM Plex Sans, Space Grotesk
//   clock widget: Inter Light (default), Monoton, Space Grotesk, Orbitron, JetBrains Mono
//   numbers: JetBrains Mono
Singleton {
    id: root
    readonly property string dir: "file://" + Quickshell.env("HOME") + "/.config/Tide/fonts/"
    readonly property var files: [
        "inter/Inter[opsz,wght].ttf", "geist/Geist[wght].ttf", "dmsans/DMSans[opsz,wght].ttf",
        "ibmplexsans/IBMPlexSans[wdth,wght].ttf", "spacegrotesk/SpaceGrotesk[wght].ttf",
        "orbitron/Orbitron[wght].ttf", "monoton/Monoton-Regular.ttf", "jetbrainsmono/JetBrainsMono[wght].ttf",
        "fredoka/Fredoka[wdth,wght].ttf"      // park mode's kid space (OFL, Google Fonts)
    ]
    property var loaded: []
    Instantiator {
        model: root.files
        delegate: FontLoader {
            required property var modelData
            source: root.dir + encodeURI(modelData).replace(/\[/g, "%5B").replace(/\]/g, "%5D")
            onStatusChanged: if (status === FontLoader.Ready) root.loaded = root.loaded.concat([name]);
                             else if (status === FontLoader.Error) console.warn("font not loaded:", modelData)
        }
    }

    readonly property var interfaceFonts: ["Inter", "Geist", "DM Sans", "IBM Plex Sans", "Space Grotesk"]
    readonly property var clockFonts: [
        { label: "Inter Light", value: "Inter", weight: Font.Light },
        { label: "Monoton", value: "Monoton", weight: Font.Normal },
        { label: "Space Grotesk", value: "Space Grotesk", weight: Font.Light },
        { label: "Orbitron", value: "Orbitron", weight: Font.Normal },
        { label: "JetBrains Mono", value: "JetBrains Mono", weight: Font.Light }
    ]
}
