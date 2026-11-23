import QtQuick
import QtQuick.Layouts
import ".."
import "../services"

// Settings → AI: one switch for every AI piece in Tide (the bar's AI button, Eve in
// the island and its shortcut, "Talk to Eve" in the launcher, the Eve panel). The
// connection is a placeholder until an integration fills in services/EveData.qml.
ColumnLayout {
    spacing: Theme.s(18)
    Heading { text: "AI"; sub: "Turn this off if you don't use an assistant: everything AI disappears from Tide, and nothing else changes." }
    SCard {
        SRow {
            label: "AI features"
            sub: "The AI button in the bar, " + EveData.assistantName + " in the island (Super+Alt+E), Talk to " + EveData.assistantName + " in the launcher, and the " + EveData.assistantName + " panel"
            SToggle { on: Theme.aiEnabled; onToggled: Theme.set("aiEnabled", !on) }
        }
        SRow {
            last: true
            label: "Integration"
            sub: "Not set up yet. The panel shows demo content until an assistant is connected."
            Text { text: "Not set up yet"; color: Theme.muted; font.family: Theme.sans; font.pixelSize: Theme.s(13) }
        }
    }
}
