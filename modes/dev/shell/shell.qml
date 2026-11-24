//@ pragma UseQApplication
// Tide · Dev mode shell (Quickshell)
// Run:  qs -p ~/.config/Tide/modes/dev/shell
import QtQuick
import Quickshell
import Quickshell.Wayland
import "services"
import "eve"
import "widgets"
import "games"
import "park"

ShellRoot {
    Variants {
        // only the monitor named in theme.json (or the first one if it isn't connected)
        model: {
            const all = Quickshell.screens;
            const pick = all.filter(s => s.name === Theme.monitor);
            return pick.length > 0 ? pick : all.slice(0, 1);
        }

        Scope {
            id: perScreen
            required property var modelData

            // reserves the bar's space: 10px top + 38px pill. Hyprland's gaps_out (12)
            // then puts windows at y=60 like the design.
            PanelWindow {
                screen: perScreen.modelData
                anchors { top: true; left: true; right: true }
                implicitHeight: 1
                color: "transparent"
                exclusiveZone: Theme.s(48)
                mask: Region {}
                WlrLayershell.namespace: "tide-spacer"
            }

            // rebuilt when Dark/Glass changes: the layer's name, and so whether
            // Hyprland's blur rule applies, is fixed when the window is created
            Variants {
                model: [Theme.surface]
                Scope {
                    id: look
                    required property var modelData
                    // glass only: the unblurred shadow layer, created first so it sits under the shell
                    LazyLoader {
                        active: look.modelData === "glass"
                        ShadowWindow { screen: perScreen.modelData }
                    }
                    ShellWindow {
                        screen: perScreen.modelData
                    }
                }
            }
        }
    }

    // desktop widgets: on the screen picked in Settings → Widgets (the main one by default)
    Variants {
        model: {
            if (!Widgets.enabled) return [];
            const want = Widgets.screen || Theme.monitor;
            const pick = Quickshell.screens.filter(s => s.name === want);
            return pick.length > 0 ? pick : Quickshell.screens.slice(0, 1);
        }
        WidgetLayer {
            required property var modelData
            screen: modelData
        }
    }

    // the Eve panel: one floating window (hidden when Settings → AI is off)
    EveWindow {}

    // park mode (hold Super+Alt+P): over everything on every screen while parked
    Variants {
        model: Park.parked || Park.preview ? Quickshell.screens : []
        ParkScreen {}
    }

    // the game launcher (Mod+G): full screen on the main monitor while open
    LazyLoader {
        active: Games.open
        GameLauncher {}
    }

    // load the island's state (IPC + global shortcut), the recording service, the
    // notification daemon and the tablet plugins (their daemons) at startup
    Component.onCompleted: {
        IslandState.mode;
        Session.active;
        Games.open;
        Park.parked;
        Power.hasBattery;
        Recording.active;
        Notifications.unseen;
        Voice.state;
        Wallpapers.files;
        Tablets.plugins;
        Drives.list;
        Idle.awake;
        Fonts.loaded;
    }
}
