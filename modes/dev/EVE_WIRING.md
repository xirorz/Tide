# Wiring Eve into Tide's island

The island already draws Eve live mode exactly as designed. It doesn't talk to Eve
itself: it shows whatever state it's given, and it runs commands when the user
presses its buttons. Wiring Eve means doing two things.

Shell dir used below: `~/.config/Tide/modes/dev/shell` (`Q` for short).

## 1. Drive the island (Eve → island)

Call these over Quickshell IPC: `qs -p $Q ipc call eve <function> [args]`.

| Call | What the island does |
| --- | --- |
| `start` | Opens Eve in the island: orb, "Listening", mic on. |
| `end` | Closes it and clears steps, terminal and caption. |
| `stage <listening\|thinking\|working\|speaking>` | Switches the orb animation, the label and the layout. `working` grows the island to 660x330 with the steps and terminal; any other stage clears them. |
| `say "<text>"` | Sets the caption at once (e.g. streaming transcript chunks: send the whole text so far). |
| `sayTyped "<text>"` | Types the caption out at the design's pace with the accent caret (0.5 letters/45ms while listening, 0.75 while speaking). |
| `step "<text>" <icon>` | Adds a working step with a spinner; earlier steps get a check. Icons: `terminal`, `containers`, `browser`, `log`. |
| `stepsDone` | Checks off the last step. |
| `term "<line>" <kind>` | Adds a terminal line. Kinds: `cmd` (light), `out` (muted), `ok` (accent). |
| `mute <true\|false>` | Sets the mic state shown ("Mic muted", greyed wave). |
| `status` | Returns `{"active", "stage", "muted"}` as JSON. |

A typical turn:

```sh
qs -p $Q ipc call eve start
qs -p $Q ipc call eve say "Eve, is the barbershop site up?"     # as the user speaks
qs -p $Q ipc call eve stage thinking
qs -p $Q ipc call eve stage working
qs -p $Q ipc call eve step "Checked containers" containers
qs -p $Q ipc call eve term '$ docker ps --filter name=barbershop' cmd
qs -p $Q ipc call eve term 'barbershop-web   Up 41 days (healthy)' out
qs -p $Q ipc call eve stepsDone
qs -p $Q ipc call eve stage speaking
qs -p $Q ipc call eve sayTyped "The site is up and healthy."
qs -p $Q ipc call eve end                                        # or leave it on listening
```

There is also a global shortcut, `tide:eve` (start / end), not bound to a key yet.

## 2. Hear the user's buttons (island → Eve)

Set commands in `theme.json` under `"eveHooks"` (the comments below are only for
this guide; JSON has none). Each runs with `sh -c`, with
`$1` = `muted` or `unmuted`:

```json
"eveHooks": {
  "start": "",   // user started Eve (launcher row, tide:eve, or `ipc call eve start`)
  "end":   "",   // user pressed the red X
  "mute":  "",   // user toggled the mic button ($1 is the new state)
  "type":  ""    // user pressed "type instead"
}
```

## 3. Turn off the preview

`"eveDemo": true` plays the design's preview loop when Eve is started and no
`start` hook is set. Set it to `false` once Eve drives the island (setting a
`start` hook also stops the preview from running).

Files: `shell/services/Eve.qml` (state, IPC, hooks, preview) and
`shell/island/EveLive.qml` (the view).

## Island priority (how Eve shares the island)

- Tools you open (launcher, calculator, clipboard, capture, power, wallpapers)
  always go on top. Eve keeps running underneath: keep sending IPC calls as usual.
  When the tool closes, the island returns to Eve in whatever state you've set since.
- `ipc call eve start` while a tool is open starts Eve in the background; she
  appears when the tool closes. Starting her yourself (launcher row, `tide:eve`)
  always shows her right away.
- Notification banners and the volume pop-up never cover Eve (or a tool). They only
  show on an empty island; notifications still land in the control center.
- The control center can be open alongside Eve.
- `qs -p $Q ipc call island state` returns what the island shows right now
  (`idle`, `eve`, `calculator`, …).

## Game launcher → "Pause local AI while playing" (stub)

The game launcher (Mod+G, `shell/games/GameLauncher.qml`) shows the design's switch
"Pause local AI while playing". It's only remembered for now
(`~/.local/state/tide/games.json` → `"pauseAi"`, `Games.pauseAi` in
`shell/services/Games.qml`); nothing is paused yet.

Where to wire it: `Games.launch(g)` starts a game and `Games.runningIds` changes when
one starts or quits. When `Games.pauseAi` is on, a hook there would:

- on launch: stop or unload the local models (for example `systemctl --user stop`
  the model server units, or the AI backend's own "unload" call) and remember what
  was running;
- when `runningIds` becomes empty again: start what was stopped.

The design's "frees 18.4 GB VRAM" note can come from `Resources.procs` (VRAM by
process) for the model servers. Keep it a no-op when Settings → AI is off.
