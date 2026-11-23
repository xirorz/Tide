import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Settings → Notifications: per-app rules. Every app that has sent a notification is
// listed to mute; Steam's own pop-ups for what Tide already tells you are hidden.
ColumnLayout {
    spacing: Theme.s(18)
    Component.onCompleted: Games.refresh()      // is Steam here (its row)

    Heading { text: "Notifications"; sub: "Tide shows every app's notifications. Mute the ones you don't want." }

    SCard {
        title: "Steam"
        SRow {
            last: true
            label: "Hide Steam's download and install pop-ups"
            sub: "Tide tells you when a game it installs or removes is done. Friend messages still show."
            SToggle { on: Notifications.steamTideNotices; onToggled: Notifications.setSteamTideNotices(!on) }
        }
    }

    SCard {
        id: appsCard
        title: "Apps"
        readonly property var names: {
            const l = Notifications.apps.slice();
            if (Games.raw.some(g => g.platform === "steam") && !l.some(a => a.toLowerCase() === "steam")) l.push("Steam");
            return l.sort((a, b) => a.localeCompare(b));
        }
        SRow {
            visible: appsCard.names.length === 0
            last: true
            label: "No notifications yet"
            sub: "Apps show up here once they've sent one"
        }
        Repeater {
            model: appsCard.names
            delegate: SRow {
                required property string modelData
                required property int index
                last: index === appsCard.names.length - 1
                label: modelData
                sub: Notifications.isMuted(modelData) ? "Muted: its notifications don't show" : (modelData.toLowerCase() === "steam" ? "Muting Steam hides all its pop-ups" : "Shows its notifications")
                SBtn { label: Notifications.isMuted(modelData) ? "Unmute" : "Mute"; onClicked: Notifications.setMuted(modelData, !Notifications.isMuted(modelData)) }
            }
        }
    }
}
