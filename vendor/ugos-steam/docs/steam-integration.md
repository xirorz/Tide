# Steam integration

The OS does not replace Steam. Steam runs hidden in the background, signed in through
its own window, and the OS's screens show its library, hours and achievements and tell
it to install and start games. The player never has to look at Steam, and the OS never
sees a password.

Two commands do the work. Both are OS components, separate from the plugin manager,
and both print JSON so the shell can run them the way it runs `ugos-plugin`:

- **`ugos-steam`** (`crates/ugos-steam`): everything about Steam.
- **`ugos-playtime`** (`crates/ugos-playtime`): hours for games the OS launches itself
  (emulators). Its hook lines and store are in `crates/ugos-playtime/README.md`.

What Steam exposes, and how that was found out, is in
`research/steam-check/findings.md`.

## How it talks to Steam

`ugos-steam start` runs `steam -silent -cef-enable-debugging -devtools-port 8080`.
With that, the Steam client offers a DevTools port on 127.0.0.1. `ugos-steam` connects
to it and runs small scripts inside Steam's shared page, where the client's own
`SteamClient`, `appStore` and `collectionStore` objects live. This is the same
internal interface Steam's own screens use. It is not a public one.

- Every script is in `crates/ugos-steam/src/js.rs`, with the Steam version they were
  verified on at the top: **client build Oct 21 2026, version 1792618285,
  SteamClient023**. `ugos-steam version` prints that next to the running client's
  version.
- When a Steam update removes a call, the command fails with `steam-call-missing` and
  names the call. When a call answers in another shape: `unexpected-shape` with the
  script's name. Neither is a crash. Fix the script in `js.rs`.
- The websocket and HTTP client is about 200 lines in `src/ws.rs`, with no
  dependencies. It can only connect to 127.0.0.1.

## Settings

| Flag | Environment | Default | |
|---|---|---|---|
| `--steam-command` | `UGOS_STEAM_COMMAND` | `steam` | The command that starts Steam; may be a wrapper script. `-shutdown` is passed to the same command to stop it. |
| `--port` | `UGOS_STEAM_PORT` | `8080` | The debugging port. Always on 127.0.0.1. |
| `--state` | `UGOS_STEAM_STATE` | `/var/lib/ugos/steam` | Where answers are kept (below). |
| `--steam-root` | `UGOS_STEAM_ROOT` | `~/.local/share/Steam`, then `~/.steam/steam` | Steam's own folder, read only when Steam is not running and nothing is kept. |

## Commands

Every command prints one JSON value and exits with 0. A failure prints this and exits
with 1:

```json
{ "error": { "code": "not-ready", "message": "Steam is not ready: an account has to be chosen first" } }
```

### status

```json
{ "status": "ready", "account": "playerone", "persona": "Player", "settings_loaded": true,
  "phase": "ready", "message": "Steam is ready" }
```

`status` is one of `not-installed`, `not-running`, `starting`, `needs-account-choice`,
`needs-sign-in`, `ready`. `account` (the sign-in name) and `persona` (the display
name) are there only when ready. Added 2026-11-10, all additions: `settings_loaded`
(see `overlay`), `preparing` (games Steam is starting right now, see `running`; left
out when empty), and `phase` with `message` (see "Phases and messages").

**The account list is only reported once it is real** (2026-11-10, after version 23 on
the Legion Go answered "Choose a Steam account" seconds before Steam signed in by
itself). Steam shows its account list for a few seconds while it signs a remembered
account in automatically. `status` therefore says `starting` ("Starting Steam"), not
`needs-account-choice`, while either of these holds:

1. Steam's own sign-in state says it is busy signing in. Recorded on the development
   PC: the state is 1 while Steam sits at the list waiting for a choice, 3 and then 4
   while it signs in, 5 when signed in. Anything but 1 with the list still up is
   "starting".
2. Steam has been in the waiting state for less than the settle time, 4 seconds by
   default (`--settle SECONDS` or `UGOS_STEAM_SETTLE`; 0 switches it off). This timer
   is needed because, just before an automatic sign-in begins, Steam is in the waiting
   state too and nothing recorded tells that moment from a real wait. The time is
   counted inside Steam from the first look that finds it waiting, so it does not
   matter how often `status` is asked, and it starts over when the state changes.

With no saved account, and for the form for name and password, nothing can sign in
by itself, so `needs-sign-in` is reported at once. `start` waits through all of this
(up to its `--wait`), so its answer is the settled one. With two or more saved
accounts and no automatic sign-in the answer is still `needs-account-choice`, 4
seconds later than before.

### start, stop

`start [--wait 90]` starts Steam hidden and returns the status once Steam knows
whether someone is signed in, or after the wait. It then checks that the port listens
on 127.0.0.1 only; if anything else listens on it, Steam is stopped again and the
error is `debug-port-exposed`. Starting an already running Steam does nothing.

`stop` (no app id) shuts Steam down the way its own Exit does and waits until it is
gone. Both print the status.

### accounts, choose-account

```json
{ "accounts": [
  { "account": "playerone", "persona": "Player", "remembered": true, "last_login": 1794300000 },
  { "account": "playertwo", "persona": "Player", "remembered": true, "last_login": 1794300001 } ] }
```

With more than one saved account, or with Steam's "ask which account each time"
turned on, a hidden Steam waits at its account list. `choose-account NAME` presses
that account in Steam's own list and prints the status that follows: `ready`, or
`needs-sign-in` if Steam now wants a password or a Steam Guard code. `NAME` is the
account name; the display name works only when a single saved account has it.

### library

`library` lists owned games; `library --all` adds applications, tools and the rest.

```json
{
  "source": "steam", "stale": false, "fetched_at": 1794325691, "account": "playerone",
  "games": [
    { "appid": 238960, "name": "Path of Exile", "kind": "game", "installed": true, "installed_elsewhere": [],
      "size_on_disk": 71627951692, "minutes_played": 67408, "last_played": 1791152617,
      "cover": "https://shared.steamstatic.com/store_item_assets/steam/apps/238960/…/library_capsule.jpg?t=1794180437",
      "icon": "https://shared.steamstatic.com/community_assets/images/apps/238960/1110764a….jpg" },
    { "appid": 108710, "name": "Alan Wake", "kind": "game", "installed": false, "installed_elsewhere": [],
      "size_on_disk": 0, "minutes_played": 0, "last_played": 0,
      "cover": "https://shared.steamstatic.com/store_item_assets/steam/apps/108710/library_600x900.jpg?t=1769717707",
      "icon": "https://shared.steamstatic.com/community_assets/images/apps/108710/ec795351….jpg" } ]
}
```

- `source: "steam"`: fresh from the running client. The answer is also kept on disk.
- `source: "cache", stale: true`: Steam is not ready; this is what it said at
  `fetched_at`.
- `source: "local-files", stale: true`: Steam is not ready and nothing is kept.
  Installed games only, read from `libraryfolders.vdf`, the `appmanifest` files and
  `localconfig.vdf` (hours). `cover` is then a local file path, or null.

**`installed` means installed on this device.** `installed_elsewhere` (added
2026-11-10; `installed` kept its name) lists the other computers of the same account
that Steam found on the network and that have the game installed, by name, for
example `["station"]`. Steam can stream from those (Remote Play). A game that is only
on another computer has `installed: false`, `size_on_disk: 0` and a non-empty
`installed_elsewhere`, so the shell still offers Install and may say where the game
already is. A name can be an empty string when Steam gives none.

How it is decided: Steam's own `installed` flag follows the "most available" computer
and is therefore true for a game that is only on another PC. `ugos-steam` reads the
entry for this machine instead (client id "0" in the app's per-computer list) and then
checks it against the disk: the app counts as installed here when one of Steam's
library folders, as the client lists them, holds a finished `appmanifest_<appid>.acf`
(state flag 4). The files decide. Only when a library folder cannot be read (a drive
not mounted) is the client's word for this machine taken as it is.

`kind` is `game`, `application`, `tool`, `demo` or `other`. The default list is what
Steam itself files under games. `cover` is the portrait cover (600x900).

### game APPID

Hours and achievements for one game, installed or not.

```json
{
  "source": "steam", "stale": false, "fetched_at": 1794325701,
  "game": { "appid": 1086940, "name": "Baldur's Gate 3", "kind": "game", "installed": false, "…": "as in library" },
  "hours_played": 450.1,
  "achievements_unlocked": 54, "achievements_total": 54,
  "achievements": [
    { "id": "BG3_Quest01", "name": "Descent From Avernus",
      "description": "Take control of the nautiloid and escape the Hells.",
      "icon": "https://shared.steamstatic.com/community_assets/images/apps/1086940/0cb31fd9….jpg",
      "unlocked": true, "unlocked_at": 1692382722, "global_percent": 0.0, "hidden": false } ]
}
```

Kept per game the same way as the library. A game never asked about while Steam was
ready is still answered from the kept library, with `achievements: null`.
`global_percent` is always 0 for now: the call used here does not carry the worldwide
figures. Steam's own achievement page gets them with a separate request to Steam's
servers (`CPlayer_GetGlobalAchievementPercentages`), and the public address
`api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v2/?gameid=APPID`
has them without a key, but it cannot be fetched from inside the client's page. Not
wired up; it needs a web request of our own.

### folders

```json
{ "folders": [
  { "index": 0, "path": "/home/player/.local/share/Steam", "label": "", "capacity": 1000203837440, "free": 103659446272, "default": false, "mounted": true, "apps": 9 },
  { "index": 1, "path": "/mnt/Data/SteamLibrary", "label": "", "capacity": 983334674432, "free": 373154189312, "default": true, "mounted": true, "apps": 6 } ] }
```

Adding a folder is not built yet (Steam has `SteamClient.InstallFolder.AddInstallFolder`).

### install, uninstall

`install APPID [--folder INDEX] [--dry-run] [--accept-licences]`. Without `--folder`
the game goes to Steam's default folder. No Steam window appears.

```json
{ "appid": 1509960, "name": "PICO PARK", "folder": 1, "bytes_needed": 80009044, "bytes_free": 373554360320, "started": true, "quiet": true,
  "dialog_title": "Install", "phase": "installing", "message": "Installing" }
```

- `--dry-run` asks Steam how much space is needed and prints the same object with
  `started: false`. Use it for the "install?" screen. It does not open Steam's install
  wizard at all (it puts the app on the install manager's list, reads the size and
  takes it off again), so there is nothing that could show.
- A real install has to go through Steam's install wizard, and Steam's own interface
  answers the wizard by opening an "Install" dialog together with Steam's main window.
  (That was the window seen on the Legion Go with version 21, where the size query
  still opened the wizard.) `ugos-steam` now puts Steam's interface into its own
  silent case for the length of the call, so no dialog is made; `js.rs`, `install`,
  explains how. `quiet: true` says that worked. `quiet: false` means a Steam update
  moved the piece this relies on: the game is still installed, but through the visible
  wizard, and `js.rs` needs a look.
- When the game's publisher wants a licence agreement accepted, nothing is installed
  and the error lists the agreements:

  ```json
  { "error": { "code": "licence-required",
      "message": "this game has 1 licence agreement(s) the player must accept first; nothing was installed",
      "licences": [ { "id": "291480_eula_0", "version": 4, "url": "https://store.steampowered.com//eula/291480_eula_0?l=english&cc=US&client=1" } ] } }
  ```

  The shell shows the text behind each `url` and, only when the player accepts, runs
  the install again with `--accept-licences`. The agreements are asked for before the
  install is started, so Steam's own agreement window does not come up.
- After `started: true` the game is in Steam's download queue; follow it with
  `downloads` and see it turn `installed: true` in `library`.

- `dialog_title` (a real install only) is the title Steam's own Install dialog has in
  the client's language, for a session that lets exactly that Steam window through
  when `quiet` is false. See "Steam's windows" below.

`uninstall APPID` removes an installed game without Steam's confirmation window, so
the shell must ask first:

```json
{ "appid": 1509960, "name": "PICO PARK", "removed": true, "phase": "removed", "message": "The game was removed" }
```

### downloads, pause, resume

```json
{
  "state": "Downloading", "paused": false, "appid": 1509960, "bytes_per_second": 830476,
  "percent": 42.0, "seconds_left": 57, "installing": true,
  "items": [
    { "appid": 1509960, "name": "PICO PARK", "active": true, "paused": false, "completed": false,
      "queue_index": 0, "scheduled_for": 0, "bytes_done": 80009044, "bytes_total": 248906844, "error": "" } ]
}
```

`state` is Steam's own word (`None`, `Starting`, `Downloading`, `Finalizing`,
`Stopping`, …). `appid` is 0 when nothing is being downloaded. `seconds_left` is -1
when unknown. `bytes_done` and `bytes_total` add up every stage of the item (download,
unpack, write), so use `percent` for a progress bar. `scheduled_for` is when Steam
plans to update the item by itself. `pause` and `resume` switch all downloads off and
on and print the same object.

### launch, stop APPID, running

`launch APPID` presses Play and returns:

```json
{ "appid": 238960, "name": "Path of Exile", "launched": true, "phase": "preparing", "message": "Preparing the game" }
```

`launch APPID --wait` stays until the game has **run and closed**, and prints:

```json
{ "appid": 238960, "name": "Path of Exile", "launched": true, "ended": "exited", "phase": "ended", "message": "The game was closed" }
```

`appid`, `name`, `launched` and `ended` are as before; `phase` and `message` were added
on 2026-11-10. This is the form for the shell's "run something and show the menu over it".

**What the wait follows.** Steam starts a game as a "game action" (`LaunchApp`): it
begins, goes through tasks (update, first-time setup such as creating the Proton
prefix, creating the process), may ask the player something, may report an error, and
ends when the game's process is up. `launch` starts listening to those events inside
Steam before it presses Play (`RegisterForGameActionStart`, `…TaskChange`,
`…UserRequest`, `…ShowError`, `…End`, and `GameSessions.RegisterForAppLifetimeNotifications`),
and each look also reads Steam's list of active actions (`GetActiveGameActions`) and
its running apps. The rule, in `src/launch.rs`:

- while the game action is active, the game is being prepared, even if the app shows
  up as running and goes away again (a setup step runs as the app; that is what ended
  the wait too early on the Legion Go with version 22);
- once the action has ended, the game is running while Steam lists it as running;
- it has ended when it ran after that and is gone;
- it failed when Steam reported an error, or when the action ended and no game came
  up within 20 seconds.

**Bounds.** Steam may spend `--prepare-timeout` seconds preparing (default 900, 15
minutes). After that the launch is cancelled and the error is `launch-timeout`.

**Ending it.** Ending the command (SIGTERM) calls a launch that is still being
prepared off, or asks a running game to close, and then waits up to 20 seconds for it
to be gone: `"ended": "stopped"` with phase `ended`, or `"ended": "still-running"` with
phase `stopping` if it has not gone.

**Failures** exit with 1 and carry the same two fields next to the error:

```json
{ "error": { "code": "launch-failed", "message": "Steam could not start the game (AppError_51)" },
  "appid": 238960, "name": "Path of Exile", "phase": "failed", "message": "The game could not be started",
  "steam_error": "AppError_51", "detail": null, "task": "CreatingProcess" }
```

`launch-did-not-start` (phase `not-started`): the action ended with no error and no
game appeared, which is what a launch cancelled inside a Steam window looks like, and
also a game that closes at once. `launch-timeout` (phase `timed-out`). `task` is
Steam's own name for the last step, for logs.

`running` prints what is running and, added 2026-11-10, what Steam is in the middle
of starting:

```json
{ "running": [ { "appid": 238960, "name": "Path of Exile" } ],
  "preparing": [ { "appid": 1509960, "name": "PICO PARK", "action": "LaunchApp", "task": "RunningInstallScript" } ] }
```

`status` carries the same `preparing` list when it is not empty.

`stop APPID` asks a running game to close and prints
`{ "appid": 238960, "was_running": true, "phase": "stopping", "message": "Closing the game" }`.
With `--wait` it stays until the game has really gone (20 seconds at most) and then
says phase `ended`, "The game was closed"; if the game is still there, `stopping`.

### Progress lines (`--progress`)

Without `--progress` every command prints one JSON value, as before. With it, the
long commands (`start`, `stop`, `install`, `uninstall`, `launch --wait`, `stop APPID
--wait`) also say what is going on while they work: **one JSON object per line**, each
with `phase` and `message`, and the last line is the command's answer, also on one
line. Read line by line; show `message`; act on `phase`.

```
$ ugos-steam launch 1509960 --wait --progress
{"appid":1509960,"message":"Preparing the game","name":"PICO PARK","phase":"preparing","task":null}
{"appid":1509960,"message":"Preparing the game","name":"PICO PARK","phase":"preparing","task":"RunningInstallScript"}
{"appid":1509960,"message":"Starting the game","name":"PICO PARK","phase":"starting"}
{"appid":1509960,"message":"The game is running","name":"PICO PARK","phase":"running"}
{"appid":1509960,"message":"Closing the game","name":"PICO PARK","phase":"stopping"}
{"appid":1509960,"ended":"stopped","launched":true,"message":"The game was closed","name":"PICO PARK","phase":"ended"}
```

While Steam is preparing the game each line also carries, added 2026-11-10 for the
launch screen (all additions; `message` and the rest are unchanged):

| Field | |
|---|---|
| `task` | Steam's own name for the step, as it reports it (`ProcessingShaderCache`). An empty string or null before Steam has named one. |
| `task_message` | Plain English for that step ("Preparing graphics for the first run"). "Preparing the game" for no name or a name not in the table below. Also present on `needs-attention` lines. |
| `percent` | 0 to 100, whole numbers, **only when Steam counts the step**. Absent otherwise: do not draw a bar then. |
| `skippable` | true when the step can be skipped with `launch-skip` (shader processing). Always present on `preparing` lines. |

```
{"appid":1887840,"message":"Preparing the game","name":"Another Crab's Treasure","phase":"preparing","skippable":false,"task":"SynchronizingCloud","task_message":"Syncing your saved games"}
{"appid":1887840,"message":"Preparing the game","name":"Another Crab's Treasure","percent":41,"phase":"preparing","skippable":true,"task":"ProcessingShaderCache","task_message":"Preparing graphics for the first run"}
```

A line is printed when the phase, Steam's task or the percentage changes, not on a
timer (so at most about a hundred lines for one counted step). `stopping`
is printed the moment the command is told to end, and the final line only when the
game has gone. The task names in this example are illustrations: what Steam really
calls its steps has not been recorded (see "Verified, and not").

### Launch steps (task names)

Every step name that could be established, with its words. The table is `TASKS` in
`src/task.rs`. **A name that is not here is not an error**: it is passed through in
`task` with the generic `task_message` "Preparing the game".

| Task name | `task_message` | Percentage | Can be skipped | Known from |
|---|---|---|---|---|
| (none, or empty) | Preparing the game | no | no | seen on the Legion Go |
| `SynchronizingCloud` | Syncing your saved games | no | no | seen on the Legion Go |
| `SynchronizingControllerConfig` | Setting up the controller | no | no | seen on the Legion Go |
| `ProcessingShaderCache` | Preparing graphics for the first run | yes (to be confirmed) | yes (to be confirmed) | seen on the Legion Go |
| `ShowEula` | The game has a licence agreement to accept | no | no | Steam's interface code; phase is `needs-attention` |
| `ShowLaunchOption` | Steam asks how to start the game | no | no | Steam's interface code; `needs-attention` |
| `ShowDurationControl` | Steam has a notice about play time | no | no | Steam's interface code; `needs-attention` |
| `UpdatingContent` | Updating the game | yes | no | expected name, never seen |
| `VerifyingFiles` | Checking the game files | yes | no | expected name, never seen |
| `RunningInstallScript` | Setting the game up for the first run | no | no | expected name, never seen |
| `UpdatingAppInfo` | Checking for updates | no | no | expected name, never seen |
| `CreatingProcess` | Starting the game | no | no | expected name, never seen |
| `WaitingGameWindow` | Starting the game | no | no | expected name, never seen |

"Seen on the Legion Go": printed by version 23 on 2026-11-10 at 22:55 UTC for a first
launch (none, `SynchronizingCloud`, `ProcessingShaderCache`, then the game) and for
the second launch (none, `SynchronizingControllerConfig`, then the game). Steam's
full list of step names is not in anything recorded; the "expected" rows are guesses
that cost nothing if the name never comes. "Percentage: yes" means Steam is asked for
a count during that step, and the field appears only if Steam gives one.

**Shader processing is not a question.** Steam announces `ProcessingShaderCache` as a
request to the player, because its own window for it has a Skip button. Version 23
therefore printed `needs-attention` ("Steam needs your attention") for it, which is
wrong: it finishes by itself. It is now `preparing` with `skippable: true`. Any other
request, including one with an unknown name, is still `needs-attention`: showing
Steam's window when it was not needed costs little, hiding it when it was needed
leaves the launch stuck.

**Where the percentage comes from.** `SteamClient.Apps.GetGameActionDetails(action id,
callback)`, which Steam's own launch window asks about once a second; it answers with
`strNumDone` and `strNumTotal`, and the percentage is the whole part of done times 100
over total, exactly as Steam's window computes it. That call and sum are from Steam's
interface code. Whether shader processing fills those two numbers has not been seen.

### launch-skip APPID

Skips the step the game's launch is on, as the Skip button in Steam's own launch
window does. Only for a step with `skippable: true`, which today means shader
processing; at any other step, or with no launch going, nothing is sent to Steam and
the error is `nothing-to-skip`.

```json
{ "appid": 1887840, "skipped": true, "task": "ProcessingShaderCache", "phase": "preparing", "message": "Preparing the game" }
```

It is for the player's press on our launch screen. **Nothing calls it by itself**, in
`ugos-steam` or anywhere else, and nothing should: skipping shader processing makes a
game stutter until its shaders are built while playing.

How it works: a request is answered with `SteamClient.Apps.ContinueGameAction(action
id, answer)`. The answer sent for shaders is `"SkipShaders"`. **That word is from
memory of the client's interface, not from anything recorded or read today**; if it
is wrong the command will report `skipped: true` and nothing will happen. First thing
to check on the Legion Go.

### Shader settings in Steam (not changed by anything here)

Steam, Settings, Downloads:

- **Enable Shader Pre-caching.** Steam downloads ready-made shaders for the games and
  the graphics chip in use, along with game updates. With it off there is nothing to
  process at launch, and games build shaders while playing (stutter).
- **Allow background processing of Vulkan shaders.** With it on, Steam processes the
  downloaded shaders in the background while no game runs, so the launch step is short
  or absent. With it off (the default), a game's shaders are processed when it is
  launched, which is the "Processing Vulkan shaders" window with its Skip button.

Both are kept **per computer**: Steam stores its shader cache settings under
`ShaderCacheManager` in `userdata/<account>/config/localconfig.vdf`, the same local
file as the overlay switch, not in the synced account settings. Only that key's
presence in the local file was seen (its contents were not read), and the names
these two switches have inside the client were not recorded. For a console, turning
background processing on would move most of this wait out of the launch; that is a
choice for the owner, and `ugos-steam` has no command for either switch.

### Phases and messages

Every answer of a long-running command has `phase` (a fixed name: new ones may be
added, none will be renamed) and `message` (English, for the screen as it is: no
command, number, path or technical word). The table is `PHASES` in `src/say.rs`.

| Phase | Message | When |
|---|---|---|
| `not-installed` | Steam is not installed | `status`, and any command that needs Steam |
| `not-running` | Steam is not running | `status`; the answer of `stop` |
| `starting-steam` | Starting Steam | `start` while it works; `status` while Steam is starting |
| `choose-account` | Choose a Steam account | Steam is showing its account list |
| `needs-attention` | Steam needs your attention | Steam wants something in a window of its own: a sign-in, or during a launch a licence text, a launch option or a play-time notice. Not shader processing. |
| `ready` | Steam is ready | `status`, and the answer of `start` |
| `stopping-steam` | Closing Steam | `stop` while it works |
| `preparing` | Preparing the game | Steam is updating or setting the game up; also the answer of `launch` without `--wait` |
| `starting` | Starting the game | Steam's part is done, the game is coming up |
| `running` | The game is running | |
| `stopping` | Closing the game | The game was told to close and has not gone yet |
| `ended` | The game was closed | It ran and is gone, or was stopped |
| `failed` | The game could not be started | Steam reported an error |
| `not-started` | The game did not start | The launch ended with no game and no error |
| `timed-out` | Steam took too long to prepare the game | `--prepare-timeout` passed |
| `ready-to-install` | Ready to install | Answer of `install --dry-run` |
| `installing` | Installing | `install` while it works, and its answer (the download goes on in Steam) |
| `needs-licence` | The game has a licence agreement to accept | `install` stopped with `licence-required` |
| `removing` | Removing the game | `uninstall` while it works |
| `removed` | The game was removed | Answer of `uninstall` |

### overlay

`overlay status` prints `{ "enabled": true }`.

`overlay off` (and `on`) change Steam's "Enable the Steam Overlay while in-game"
setting, read it back, and say whether it stuck:

```json
{ "enabled": false, "applied": true, "attempts": 1 }
```

- `enabled`: the value read back at the end.
- `applied`: the value asked for was read back three times in a row, a second apart.
- `attempts`: how many times it had to be sent; 0 when it already had the value.

When it does not stick, the command exits with 1:

```json
{ "error": { "code": "setting-not-applied", "message": "Steam's setting enable_overlay did not take the value after 10 attempt(s)" },
  "applied": false, "enabled": true, "attempts": 10 }
```

How it works, and why: Steam's settings reach the client in pieces. Before anyone is
signed in the client has about a third of them (86 of 270 on the development PC) and
neither this setting nor the toast one is among them; they arrive with the account's
settings during sign-in. The settings store has no "loaded" flag, so the signal used
is "the setting is there and is a yes or no". Each round waits for that, sends the
value unless it is already right, and then reads it back three times; a value that
changes back (overwritten by settings that arrived later) starts another round. Ten
rounds at most, about 40 seconds at worst. The overlay switch is kept per computer.

`status` does not wait for the settings: `ready` still means "signed in, library
loaded", so the library shows as early as before. It now also says
`"settings_loaded": true` or `false`. The setting commands do their own waiting.

### toasts

`toasts status` prints `{ "enabled": true }`. `toasts off` (and `on`) change Steam's
"disable all toasts" setting and answer like `overlay off` (`enabled`, `applied`,
`attempts`; exit 1 with `setting-not-applied`).

> **`toasts off` and `toasts on` change the Steam account's setting on every
> computer.** Steam keeps this switch with the account and syncs it
> (`userdata/<account>/7/remote/sharedconfig.vdf`, `DisableAllToasts`), unlike the
> overlay switch, which is per computer. Turning toasts off on the console turns them
> off in the same account's Steam on a PC at its next start, and the other way round.
> Seen on 2026-11-10: after the Legion Go turned toasts off, the development PC's
> Steam had them off at its next start.
>
> Nothing in `ugos-steam` runs these two by itself, and nothing should: they are for
> a choice the player makes. The command's help says the same.

A toast is Steam's small pop-up (download finished, friend online, achievement). It
is a window of its own, so under the kiosk compositor it would cover the screen. About
23 seconds after an install started, the "download complete" toast was the one Steam
window that still appeared in the live check. Steam keeps showing the few toasts it
marks critical. Because the switch is the account's, the cleaner way for the console
is to keep Steam's toast windows off the screen in the session (the image already
hides Steam's windows by default) and leave the account's setting alone.

This is also the most likely reason `toasts off` "did not take" at start-up on the
Legion Go: the value was sent right after sign-in, and the account's synced settings,
arriving a moment later, put the old value back. That was not reproduced on the
development PC (there the value sent at the first `ready` stuck), so it is a
conclusion from where the setting is stored, not an observation.

### version

```json
{ "ugos_steam": "0.1.0", "verified_on": "Steam client build Oct 21 2026 (version 1792618285, SteamClient023)",
  "client": { "version": 1792618285, "built": "Oct 21 2026 21:09:51", "interface": "SteamClient023" } }
```

### Error codes

| Code | Meaning |
|---|---|
| `not-installed`, `not-running`, `not-ready` | Steam's state does not allow the command; `status` says which. |
| `steam-call-missing`, `unexpected-shape`, `script-failed`, `timeout` | Steam did not answer as expected. After a Steam update, look in `js.rs`. |
| `debug-port-exposed` | The debugging port was reachable from outside; Steam was stopped. |
| `connection-failed` | The port answers but the conversation failed. |
| `nothing-to-skip` | `launch-skip`: the launch is not at a step that can be skipped. |
| `setting-not-applied` | `overlay` or `toasts` `off`/`on`: the value did not stick. |
| `launch-failed`, `launch-did-not-start`, `launch-timeout` | `launch --wait`: see there. |
| `account-not-found`, `no-account-choice` | `choose-account`: no such saved account, or Steam is not showing its list. |
| `not-owned`, `already-installed`, `app-not-installed` | The app id does not fit the command. |
| `no-such-folder`, `no-space` | `install`: bad `--folder`, or not enough room (nothing was started). |
| `licence-required` | `install`: see above. |
| `install-needs-attention` | `install`: Steam wants a product key, a password or a sign-up; cancelled. |
| `install-failed` | `install`: Steam's install manager refused or failed. |
| `io`, `cannot-run`, `bad-argument` | This machine: a file, the Steam command, an argument. |

## State folder

`/var/lib/ugos/steam` on the data partition (it survives system updates):

```
library.json         everything the account owns, as Steam last said, with the time
games/<appid>.json   one game's details and achievements, as last fetched
```

Both are replaced whole (write, rename). They hold names, hours and web addresses.
No token, cookie or password is ever read or written by `ugos-steam`; it never opens
`config.vdf` or `loginusers.vdf`.

## What the shell does for each status

| Status | Shell |
|---|---|
| `not-installed` | Hide Steam's part of the library, or say Steam is not part of this system. |
| `not-running` | Run `ugos-steam start`. Meanwhile show `library` (kept or local, marked stale). |
| `starting` | Show "Steam is starting" and ask again in a second or two. A first start downloads the Steam client and takes minutes. |
| `needs-account-choice` | Show `accounts` as a list; on a choice run `choose-account NAME`. |
| `needs-sign-in` | Bring Steam's own sign-in window to the front (it is a normal window; under the kiosk compositor the newest window is on top) and wait for `ready`. The player signs in there, by QR code with the Steam mobile app or with a keyboard. The OS never asks for or handles the password. |
| `ready` | Library, game pages, install, launch. |

Game page: `game APPID`. Install: `install APPID --dry-run` for the size and `folders`
for the choice of drive, then `install`, then `downloads` once a second while
something is active. Play: `launch APPID --wait` under the shell's menu.

## Steam's windows

What the compositor saw on the development PC (Hyprland, Steam through XWayland,
client build Oct 21 2026). Every one has the window class **`steam`**; they differ by
title.

| Window | Title | Class | Size | When |
|---|---|---|---|---|
| Install dialog | `Install` | `steam` | 540x480 | Only when an install goes through Steam's visible wizard (`quiet: false`, or version 21's size query). Seen. |
| Main window | `Steam` | `steam` | fills its tile | Comes up together with the Install dialog. Otherwise hidden with `-silent`. Seen. |
| Account list / sign-in | `Sign in to Steam` | `steam` | | Status `needs-account-choice` and `needs-sign-in`. Shown even with `-silent`. Seen. |
| Toast | `notificationtoasts_3_desktop` | `steam` | 283x70 | A download finished, and other notifications. Seen. The number in the middle may differ. |

- **The titles are the English ones.** "Install" is Steam's text for its
  `#GameAction_Install` label and "Sign in to Steam" likewise comes from its language
  files; with Steam in another language they are different words. The image must keep
  Steam in English, or take the title from `dialog_title` in the `install` answer,
  which asks Steam for that label in its own language (falling back to "Install"; the
  lookup itself is not verified, see below).
- **Can they change with a Steam version?** Yes. They are display texts, not an
  interface: Valve can reword a label or rename a window in any client update, and
  the toast window's name is an internal one. The class `steam` has been stable for
  years but is not promised either. Treat a title match as something to re-check
  after Steam updates, and prefer `quiet: true` (no dialog at all) over showing it.
- A game's own windows have the class `steam_app_<appid>`, not `steam`.

**During a game's first launch.** On the Legion Go with version 23 the owner saw
Steam's "Processing Vulkan shaders" window, then a Steam window, then the game. That
first window belongs to the `ProcessingShaderCache` step; the title is as the owner
reported it, and neither its exact title nor its class was recorded by a program
(nothing was launched on the PC). With version 22 a Steam setup window appeared
while Steam created the Proton prefix; also not recorded. From Steam's interface code, the windows a launch
can bring up are its launch progress dialog, a licence text (popup named
`EULA_<appid>`), a launch-option choice, a play-time notice, a cloud save conflict
and a launch error dialog; all are Steam's own windows, so the class is expected to
be `steam`, and the titles are localised texts. `launch --wait` reports
`needs-attention` while Steam is asking something, which is the moment to let Steam's
window through. Record the real titles on the Legion Go with the compositor's window
list during a first launch.

## What the OS image needs

Not done yet; the image and the shell are separate work.

1. **Steam installed for the `player` user.** Steam needs 32-bit libraries (i386) and
   keeps itself and, by default, the games under the user's home folder
   (`~/.local/share/Steam`). The system partition is replaced by updates, so that
   folder must live on the data partition.
2. **Started at boot through `ugos-steam start`**, inside the session (Steam needs the
   display), once the player has turned Steam on. `start` adds `-silent`, so no window
   appears when an account is remembered. Do not start it for someone who does not use
   Steam: with no saved account its sign-in window comes up.
3. **Steam in English.** The sign-in window is recognised by its title ("Sign in to
   Steam").
4. **Overlay off:** run `ugos-steam overlay off` once Steam is `ready` and check
   `applied` in the answer (it retries by itself for up to about 40 seconds). It is a
   per-computer setting. **Do not run `toasts off` automatically:** it changes the
   account's setting on every computer (see `toasts`). Keep Steam's toast windows off
   the screen in the session instead.
   Windows Steam can still create by itself, which the session should keep behind
   the shell unless the shell asked for them: the sign-in and account windows (wanted,
   see `needs-sign-in`), critical toasts, and anything Steam shows when a game is
   started (first-time setup, cloud conflict, launch options). Those were not looked
   at here, since no game was started.
5. **The debugging port must stay local and out of the browser app's reach.** Whoever
   can open that port controls the Steam client.
   - Steam binds it to 127.0.0.1 and `ugos-steam start` checks that.
   - Checked on the development PC: a websocket request carrying an `Origin` header,
     as every web page's request does, got no answer from the port, while one without
     it was accepted; the target list has no cross-origin permission header; a request
     with a foreign `Host` was refused (500). So a page in the browser app should not
     get in.
   - That is Steam's own protection and could change with a Steam update. The image
     should add its own: a firewall rule that only lets the shell's and Steam's
     processes connect to 127.0.0.1:8080, or the browser app in a network namespace
     without the host's loopback. Not built.
6. **Game updates.** Once signed in, Steam downloads pending updates by itself. Its
   own settings limit that (no downloads while playing is the default); `pause` and
   `resume` are there for the OS.
7. **`ugos-playtime recover` once at boot**, and the hook lines from its README in
   `settings.toml`.

## Verified, and not

Checked against the real client on the development PC on 2026-11-10 (details in
`research/steam-check/findings.md`, section "Service check"):

- `status` in the states not-installed, not-running, starting, needs-account-choice
  and ready; `start`, `stop`; `accounts`; `choose-account`; `library`, also from the
  cache with Steam stopped; `game` for an installed and a never-installed game;
  `folders`; `downloads` idle and during an install; `overlay status`; `version`.
- `install --dry-run`; a full `install` of an 80 MB game to the default folder,
  followed to "fully installed" in its appmanifest; `uninstall` of the same game
  (manifest and files gone); `install` of two games with licence agreements, which
  stopped with `licence-required` and installed nothing.

Checked on 2026-11-10 with the compositor's window list (Hyprland, every 0.2 s,
before, during and 16 to 25 seconds after each command; script
`research/steam-check/watch_windows.py`):

- Before the fix, `install --dry-run` mapped two Steam windows after 0.75 s: "Install"
  (540x480, closed again by the cancel) and Steam's main window "Steam", which stayed.
- After the fix: `install --dry-run`, no window and no new page in Steam. `install` of a
  game with a licence agreement (stops with `licence-required`): no window. Full
  `install` of PICO PARK: no window from the install; one toast window
  ("notificationtoasts", 283x70) when the download finished. `uninstall`: no window.
- `toasts status`; `toasts on` with toasts already on was accepted and left them on.

**Confirmed on the Legion Go with version 23 (2026-11-10, from its log
`/var/lib/ugos/logs/steam-day-*.log` and the OS work's report):**

- `overlay off` answered `{ "applied": true, "attempts": 0, "enabled": false }`.
- `launch --wait --progress` followed a first launch and a second one: `preparing`
  with Steam's task names (so the task name is where `js_actions.inc` expects it),
  `running`, `stopping` when the owner closed the game, `ended` with
  `"ended": "stopped"`. The screen did not drop back during preparing.
- `game` gave real worldwide achievement percentages on a later call (23.4 where the
  call 90 seconds earlier had 0.0): Steam loads them after the first request, so
  `global_percent` is 0 only until then.

**Checklist for the Legion Go (version 24 changes, none of it run against Steam):**

1. `start` with one remembered account: the answer goes from "Starting Steam" to
   ready and never says "Choose a Steam account". Note Steam's `login_state` values on
   the way if they differ from 1, 3, 4, 5.
2. With two saved accounts and "ask each time": `needs-account-choice` after about 4
   seconds.
3. A first launch with shader processing: the lines say `preparing`, not
   `needs-attention`, with `task_message` "Preparing graphics for the first run" and
   `skippable: true`.
4. Whether `percent` appears and climbs during shader processing. If it never
   appears, `GetGameActionDetails` does not count that step and another source is needed.
5. `launch-skip APPID` during shader processing: does the game start at once? If
   nothing happens, the answer word "SkipShaders" is wrong.
6. `launch-skip` at any other moment: `nothing-to-skip`.
7. The exact title and class of the shader window and of the Steam window that
   followed it (compositor's window list during a first launch).
8. Task names not in the table: add them with words.

**Not verified live at all (written 2026-11-10 after live use of Steam on the
development PC was stopped; to be checked on the Legion Go by the OS work):**

- Everything about `launch --wait`'s new waiting: that Steam's game-action callbacks
  have the argument order assumed in `js_actions.inc`, which fields
  `GetActiveGameActions` gives per action, what the task names are, and that a first
  launch really goes preparing, starting, running, ended. The logic is unit tested on
  sequences written from the Legion Go report and from Steam's interface code.
- `cancel_launch` (`CancelGameAction`), used when the wait is ended or times out.
- `running` and `status` listing a game in `preparing`.
- `stop APPID --wait`.
- The read-back and retry of `overlay off` and `toasts off` against a real client, and
  that it fixes the Legion Go's start-up case. On the PC, before the stop, plain sends
  of both settings took and held, and the settings' arrival during sign-in was traced
  (`research/steam-check/probe_r_settings_timeline.js`).
- `dialog_title`: whether `LocalizationManager.LocalizeString` exists under that name
  in the client. If not, the field is the English "Install".
- `--progress` lines against a real Steam.

No test in the workspace starts or contacts a Steam client: the unit tests use
recorded and written-down answers, and the two socket tests talk to a pretend server
they start themselves on a free port. There is no live test to opt into. Should one
be added, it must run only with an explicit environment variable set and must not be
run on the development PC, whose Steam is the owner's own account.

Not checked against the real client (older list):

- `installed_elsewhere` with a real other computer: the development PC is the one that
  has the games, and it saw no other computer (every app had only the entry for this
  machine). The per-computer list and Steam's own code for it were read there; the
  remote case is covered by hand-built unit tests. It needs a look on the Legion Go.
- `toasts off`: not sent, the owner's setting was left alone.

- `launch`, `launch --wait`, `running` with a game in it, `stop APPID` on a running
  game: no game was started on that PC. They are unit tested with constructed answers.
- `overlay off`: the owner's setting was not to be changed. `overlay on`, with the
  setting already on, was accepted and left it on.
- `install --accept-licences`: accepting an agreement in the owner's name was not
  done. The listing of the agreements is checked; the accept call is not.
- `pause` and `resume`: the calls were accepted, but no download was running, and
  Steam's `paused` flag did not change. Their effect is unknown.
- `needs-sign-in`: the form for name and password was never on screen (both accounts
  were remembered). It is told from the account list by its text fields.
- `debug-port-exposed`: only by unit test.
