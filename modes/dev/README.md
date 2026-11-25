# Tide · Dev mode (Quickshell)

The Dev mode top bar and the island, built from the design canvas
(`~/.config/Tide/design/Dev Mode — Bar & AI Corner.html`).

## What's in this first pass

- **Bar:** floating 38px pills (glass or dark), workspace dots, window title,
  network activity, resource rings with the hover card (VRAM first), tray,
  updates count, AI button, control cluster (music wave, device batteries,
  sound, notifications, Ethernet/Wi-Fi).
- **Island:** at rest (time and date), the recording pill, the morph animation
  with the springy curve, the screen dim, and the launcher (apps, modes, quick
  tools, inline math with Enter to copy).

- **Control center:** click the control cluster (or
  `qs -p ~/.config/Tide/modes/dev/shell ipc call controlcenter toggle`). Network and
  Wi-Fi list (nmcli), Bluetooth, Stay awake (systemd-inhibit), Dark/Glass,
  output and volume (PipeWire), screenshot/record/OCR/color/timer (Ax-Shell's
  scripts, plus `scripts/record.sh` for region/window/screen recording), now
  playing, and notifications. Escape or a click outside closes it.
- **Notifications:** Tide is the notification daemon. New ones grow the island
  into a banner for 5s (paused while hovered); more arriving meanwhile update it
  in place with a count and "+N more". The bell shows a dot for ones that
  arrived since the control center was last opened.
- **Calculator:** in the island, from the launcher or the global shortcut
  `tide:calculator` (`qs ... ipc call island calculator`). Type or click; Enter
  evaluates, click the result to copy it, Escape closes.

- **Clipboard (SUPER+V) and capture (SUPER+S):** island states. Clipboard reads
  cliphist (click copies, trash deletes, Clear all wipes); capture shares its
  commands with the control center (`services/Capture.qml`).

- **Power menu (SUPER+Escape) and volume pop-up:** the pop-up shows on any
  volume or mute change (not while the control center is open).
- **Clipboard extras:** `scripts/clip-store.sh` records the app and time of each
  clip in `~/.local/state/tide/clipmeta.json`; set `clipboardCleanup` to true to
  keep `clipboardMax` entries and drop ones older than `clipboardDays`.

- **Voice dictation:** SUPER+R (whisper-paste, to the clipboard) and SUPER+SHIFT+R (obs-voice, a note) go
  through `scripts/voice.sh`, which runs the scripts unchanged and shows the island
  pill: mic, time and level, then Transcribing…, then the result.
- **Wallpaper picker (SUPER+W):** an island state (no dim, so you watch it change):
  search, display dropdown, Images | Videos, Grow/Fade/Wipe, and the grid; click
  selects, double-click or Enter applies. RGB sync and accent are always on. Applying runs `scripts/wallpaper-apply.sh` (awww or mpvpaper,
  `~/.current.wall`, matugen, OpenRGB) the same way Ax-Shell did.
- **Eve live mode:** the island draws it from `services/Eve.qml`; the preview
  loop plays until Eve is wired. See `EVE_WIRING.md`.

- **Resource center:** click the resource rings (global shortcut `tide:resources`).
  GPU (the biggest-VRAM card) with VRAM by process, CPU, memory, disk, network
  with 1 min / 5 min / 1 hr history, and processes by VRAM/CPU/RAM with End
  (never offered for Hyprland and its parents, the shell, audio, portals, session or
  root processes: those say "System process"). End asks first ("End firefox (11)?"),
  and if it's still running 3 s later offers Force quit. The search box
  (`scripts/procsearch.py`) finds every process by name, command line or user, with
  same-program processes as one row (ending it ends them all), plus matching systemd
  user services with Stop; Esc clears it.
- **Lighting:** RGB takes the wallpaper's main color at full saturation
  (`scripts/rgb-apply.sh`); the control center's Lighting slider sets "rgbBrightness".

- **Updates:** click the updates count in the bar (no shortcut). Lists pacman
  (System, which needs a restart after, and Apps and libraries), AUR (paru) and
  Flatpak updates with versions and download sizes, and says whether Arch news
  or CachyOS news was posted since your last upgrade (`scripts/updates.py`;
  `"updatesCachyNews": false` leaves CachyOS out). "Update" runs
  `sudo pacman -Syu`, then `paru -Sua` and `flatpak update -y`, in a floating kitty
  (`scripts/update-run.sh`, Hyprland class `tide-updates`). The panel follows the
  terminal: stage, percent, the package being installed, and when pacman is
  asking something. The bar shows a spinner and the percent, then a check mark.
  When it's done: what was updated, Restart now (kernel or drivers), and any
  `.pacnew` files to review with `pacdiff`. snap-pac takes the snapshots; turning
  "Take a snapshot" off sets `SNAP_PAC_SKIP` for pacman. To rehearse without
  installing anything: `qs -p shell ipc call updates dryRun true`.
  The window is Tide's own: `scripts/update-kitty.conf` (panel colors, JetBrains
  Mono, padding; your kitty.conf isn't used), 1120×720, rounded, with a heading
  for each step and a clear "All done" or "Something didn't finish" at the end.
  The package-manager commands live only in those two scripts, so other
  systems can get their own later.

- **Themes / modes (Super+T):** the island widens into a row of cards, one per
  mode, with a check on the active one; click a card (or arrows + Enter) to switch.
  The launcher lists them too ("Switch theme", or type a mode's name). Switching
  runs the mode manager, `tide-mode` (on your PATH from `~/.config/Tide/bin`).
  Each mode is a folder in `~/.config/Tide/modes` with a `mode.json` (name,
  description, its Hyprland config, how to start and find its shell, card
  colors). `tide-mode list`, `tide-mode <mode>`, `tide-mode <mode> --dry-run`.
  It checks the Hyprland config before reloading and stays put if it fails.
  `~/.config/hypr/hyprland.lua` loads whichever config the active mode names.
  Not yet: per-mode wallpaper, colors, cursor and GTK/Qt theme, and the mode
  builder in Settings.
- **Settings:** the gear in the control center, or "Settings" in the launcher
  (`qs -p shell ipc call settings open <section>`). Built so far: Themes (your
  modes with Apply), Appearance (surface, accent from wallpaper, roundness, glass
  blur, animation speed, reduce motion, GTK/Qt dark), Keybinds (searchable, read
  from your Hyprland config by `scripts/keybinds.py`) and System (update center
  and clipboard switches), and Monitors: drag screens on the desk (they snap
  edge to edge), and per screen pick resolution and refresh rate (drop-downs,
  from its real modes), scale, rotation and the main screen, plus Display: VRR
  (off, on, fullscreen only), 10-bit output, wide color gamut, SDR brightness and
  saturation (for SDR content while HDR is on; HDR itself is on hold). Apply changes
  Hyprland live and asks "Keep these settings?" in a bar pinned to the bottom of
  Settings; without Keep it goes back after 15 s. Keep writes
  `~/.config/hypr/monitors.conf` (`scripts/monitors-save.py`, first save of a day
  backs it up as `monitors.conf.before-tide-DATE`), which both Tide's and
  Ax-Classic's configs read, now including `transform` for rotation.
  Next: the new-theme wizard, recording keybinds, Tablet, drives to watch, Apps
  and Hyprland.
- **Tablet (Settings → Tablet, only while Hyprland sees a drawing tablet):**
  the pen always stays on the tablet's own screen. Tablet plugins live in
  `~/.config/Tide/plugins/<name>/` with a `plugin.json` (name, USB ids to match, a
  Settings page, a background daemon command, its app). `scripts/tablets.py` +
  `services/Tablets.qml` check every 3 s and run a plugin's daemon only while its
  tablet is plugged in (and not while its own app is open). Plugins are your own:
  none ship with Tide.
- **Capture tools** run Tide's own copies in `shell/scripts/capture/` (screenshot,
  OCR, color picker, Pomodoro timer), and the monitor-input keys run
  `~/.config/Tide/bin/switch-monitor-input.sh`; wallpaper thumbnails are always
  generated by Tide. Colors come from `~/.config/Tide/colors` (Tide's own matugen
  config and templates, written on every wallpaper change).
- **Settings, more:** Apps and Hyprland (default terminal and file manager through
  `~/.config/Tide/bin/tide-open`, which Super+Enter and Super+E call; browser via
  xdg-settings; audio app; hypridle timings written by `scripts/hypridle.py` with a
  backup; Stay awake, shared with the control center through `services/Idle.qml`).
  Idle: hypridle runs as its systemd user unit (the Idle service starts it again if a
  Hyprland crash takes it down) and asks Tide before every step
  (`scripts/idle-step.sh`; if Tide isn't running the step just happens). Tide dims
  the screens itself (no backlight on these monitors) and decides who may hold idle
  off (`scripts/idle-blockers.py`): Stay awake, games and full-screen video
  ("idleKeepGames", on), and any app asking to stay awake unless it's on "Ignore
  keep-awake from these apps" ("idleIgnore"). D-Bus ScreenSaver requests can't be
  traced to an app, so hypridle still honors those.
  System → Drives to watch (`scripts/drives.py`, `services/Drives.qml`: a
  notification when a drive passes its level, 90% unless set, once until it drops
  back). Keybinds: click a shortcut, pick modifiers, press the key, Save
  (`scripts/keybind-set.py`: clash check, backup, verify, reload). Appearance →
  Bar style: Pills or Text and icons (`barStyle`).
- **Device batteries** (headset, mouse, controller) are read straight from the
  kernel every 2 s (`scripts/peripherals.py`), so a device shows up right after it
  connects; UPower took about a minute.
- **Desktop widgets** (Settings → Widgets, off by default): a layer under your
  windows on the screen you pick (main or another one) with the design's Clock,
  Weather (Open-Meteo, once you set a place; °F/°C), Now playing (wavy seek bar,
  controls), Quick notes and Calendar + reminders (kept in `~/.local/state/tide/`).
  "Edit widgets" on the desktop: drag to move, the corner handle to resize, − to
  remove, a gallery to add; positions and sizes are saved in theme.json "widgets".
  Resizing snaps between layouts rather than shrinking text (the catalog in
  `services/Widgets.qml` says which): Weather and Now playing have small / medium /
  large (small weather is just the sky; large adds five days; small Now playing is a
  pill; large has a big cover), Calendar small is a "Today" tile, System small is
  rings, 3D printer small drops temperatures and controls. The clock scales freely
  (0.5×–3×) and Quick notes within 0.8×–1.6×. The clock has its own font
  (Settings → Widgets). The optional System widget (from the gallery) shows CPU,
  memory, GPU, network and drives, each section switchable in Settings → Widgets.
  **Drives** are one list for the System widget, the resource center's Disk card and
  the fill alerts: theme.json `drives` ([{path, name}]), edited in Settings → Widgets
  (type a mount path, Enter; rename, reorder, remove; Reset re-detects). An empty
  list is filled once with the mounted drives.
  The optional **3D printer** widget (Bambu Lab, the design's LabWidgets card without
  the camera) reads the printer over its local MQTT feed (`shell/scripts/bambu.py`,
  Python's standard library only; `services/Printer.qml`), only while it's on the
  desktop: status, file, progress, time left, layer, nozzle, bed and AMS spools,
  plus a notification when a print ends. Light, Pause / Resume and Stop (with a
  confirm) need the printer in LAN mode; a refused or unanswered command greys them
  out with a note. Set up in Settings → Widgets → 3D printer (Find printer listens
  for the printer's own announcements on UDP 2021). The access code is kept only in
  `~/.local/state/tide/secrets.json` (chmod 600), never in theme.json.
  The home lab widget comes later.
- **Eve panel** (`shell/eve/EvePanel.qml` in a floating window, `eve/EveWindow.qml`,
  opened by the bar's AI button): a real window, so Mod+drag moves it and
  Mod+right-drag resizes it; it opens at the design's 572 × 828 on the right (window
  rule `tide-eve`) and remembers the size you leave it at (`eveSize`). The design's
  panel: fading header (sidebar, title, power, new chat, pin /
  rename / delete menu, close), home (wallpaper-colored orb, greeting, cards,
  suggestions), chat (bubbles, replies with Worked for and telemetry, tool cards),
  input (thinking, mic with the live-transcription line and bars, + for the attach
  popover with a file picker that adds chips, send, Approve for me / Full access) and the sidebar (New chat,
  search, Apps, Projects, Pinned, Chats). UI only: every bit of data comes from
  `shell/services/EveData.qml`, which holds the design's demo content and empty
  stubs (`loadChats`, `loadApps`, `sendMessage`). Connecting an assistant later
  means filling in that one file; Tide stores no chats and calls no AI service.
  **Settings → AI** turns every AI piece on or off (bar button, Eve in the island
  and Super+Alt+E, Talk to Eve in the launcher, the panel).
- **Eve:** Super+Alt+E starts live mode in the island (replaces the old
  voice-window key, Super+Alt+V).

## Needs

Fonts ship with Tide in `~/.config/Tide/fonts/` (each with its OFL license) and are
loaded by `shell/services/Fonts.qml`, so nothing depends on system fonts:
Inter, Geist, DM Sans, IBM Plex Sans, Space Grotesk (interface, Settings →
Appearance), Monoton, Orbitron (clock), JetBrains Mono (numbers).

- quickshell, Qt 6.9 or newer (for `RectangularShadow`)
- fonts: none to install (they ship with Tide, see above)
- `pacman-contrib` (checkupdates), `wl-clipboard`, NetworkManager (`nmcli`), `curl`
- optional: `paru`, `flatpak`, `pywal` (accent from the wallpaper), `upower`,
  `kitty` and `snap-pac` (updates), `pacdiff` (in pacman-contrib)

## Try it

```sh
# stop Ax-Shell first so the bars don't overlap
pkill -f Ax-Shell
qs -p ~/.config/Tide/modes/dev/shell
```

Add the Hyprland side once, in `~/.config/hypr/hyprland.lua`:

```lua
dofile(os.getenv("HOME") .. "/.config/Tide/modes/dev/hypr.lua")
```

Open the launcher by clicking the clock, or bind a key to the global shortcut
`tide:launcher` (example in `hypr.lua`). From a terminal:

```sh
qs -p ~/.config/Tide/modes/dev/shell ipc call island toggle launcher
qs -p ~/.config/Tide/modes/dev/shell ipc call recording start   # preview the recording pill
```

Edits hot-reload on save.

## Game launcher

Mod + G (or the launcher's "Gaming library"): `shell/games/GameLauncher.qml`, the
design's full-screen launcher, scaled from its 1440 × 900 artboard to the screen. The
selected game's art fills the background; the sidebar has search, All games /
Recently played / Favorites and one entry per platform with counts; the hero shows the
platform, title, "Played 3 weeks ago · 39 h", Play (Resume when it's running),
favourite and the "Pause local AI while playing" switch (a stub, see EVE_WIRING.md);
the shelf is the covers. Arrows move, Enter plays, typing searches, Esc clears the
search then closes.

Steam (basic, `shell/scripts/games.py`, local files only): installed games from every
library in `steamapps/libraryfolders.vdf` (`appmanifest_*.acf`; Proton, runtimes and
redistributables left out), last played and playtime from the signed-in account's
`userdata/<id>/config/localconfig.vdf`, art from its `config/grid` or
`appcache/librarycache/<appid>/`, and Steam's own app type from the binary
`appcache/appinfo.vdf` (only the installed apps' entries are read): apps that aren't
games (Blender, Lossless Scaling) stay hidden unless "Show non-game apps" is on (sidebar,
above the emulator buttons). Play runs `steam -silent steam://rungameid/<id>`
and the launch card follows what happens: Steam starting, Steam getting the game ready,
the game's process (`SteamLaunch AppId=<id>`) appearing; then the launcher gets out of
the way. Resume focuses the game's window. Favourites: `~/.local/state/tide/games.json`.
Owned games that aren't installed come from Tide's Steam helper, `bin/tide-steam`
(source in `vendor/ugos-steam`, a Rust tool; docs in `vendor/ugos-steam/docs`): it
talks to the running Steam client through its debugging port on this PC only. Their
covers are greyed with an Install badge; Install asks Steam for the size (a dry run),
shows it with the free space, then installs with no Steam window (licence agreements
are shown first when a game has them). Progress shows on the card and in the hero
("Downloading 42% · 3.1 GB of 7.4 GB"), Cancel stops it, a notification says when it's
done; Uninstall is in the game's details (it asks first). If the helper can't answer
(a Steam update changed its private interface) only installed games show, with a quiet
note. The sidebar's Installed filter shows what's ready to play.

Lutris: installed games from `~/.local/share/lutris/pga.db` (read only) with its cover
art and banners, launched with `lutris lutris:rungameid/<id>`; Settings → Games can
turn them off. Games added by hand (Settings → Games → Add a game: a program, AppImage
or script, a name, a cover) are in `~/.config/Tide/games.json` and start directly.
Settings → Games is also where emulators are added (found ones are offered) and where
"Show non-game apps" lives; the launcher's "Add a game or emulator" opens it.

Emulators ("Add a game or emulator" / "Emulator settings" in the sidebar, mouse and
keyboard): pick one of the known emulators (Eden, Ryujinx, Citron, Azahar, PCSX2,
Dolphin, DuckStation, mGBA, PPSSPP, Cemu, melonDS) or a custom one, point it at its
program (Browse…, or `flatpak run …`) and the game folders (suggested from the
emulator's own config and ROM folders named for the platform). Saved in
`~/.config/Tide/emulators.json`; games.py finds the games by file type, titles come
from the file names (region and revision tags dropped, "Zelda, The" → "The Zelda"),
covers from an image with the same name next to the game or in a `covers` folder (else
the design's gradient art). "Emulator settings" opens the selected game's emulator
normally (its settings live there). Play runs `<program> <arguments>` with `{rom}` as the game's
file (each emulator's usual full-screen flags by default). The game starts detached,
so a Tide restart never closes it; Tide keeps its last played and play time. Tide
only launches: settings stay in the emulator.

Controllers (`scripts/gamepad.py`, the kernel's input devices; Xbox, 8BitDo and Steam
Controller layouts, and PlayStation's by vendor id): while the launcher is open, D-pad
or left stick moves (left from the first column goes into the sidebar's categories,
right comes back), A plays (or picks the category), B goes back, Y favourites, X jumps
to the next first letter, LB / RB change category, Start plays. The Guide / Home / PS
button opens the launcher from anywhere (`gamepad.py guide`, always on); over a
fullscreen game it has to be held for a second, so the game keeps a quick press. The
hints at the bottom show the pad's buttons while one is connected, the keyboard's
otherwise.

## Themes and the mode builder

Settings → Themes → **Save current setup as new theme** (`settings/ThemeWizard.qml`),
in the design's four steps: name it and pick what it keeps (widget layout, wallpaper
and accent, bar layout, dark or glass, open apps and where they sit, monitor
arrangement); apps (suggestions from the name, from the word → category map in
`~/.config/Tide/app-suggestions.json`, so "Drawing" offers Krita, GIMP, Blender…; which
Tide tools stay usable: Calculator, Clipboard, Capture and Dictation by default, Eve,
the wallpaper picker and widget editing off; "Only allow these apps": other apps are set aside on a hidden
workspace, not closed, and come back when it ends; the chosen apps open when it
starts); time and limits (15 min to 2 hours or no limit, repeat days and a start
time, "Lock me in until time is up"); review. `bin/tide-mode save` captures the setup
into `modes/<id>/mode.json` ("base": "dev": same shell and Hyprland config, its own
settings on top).

Switching saves what changed in the theme you leave (Dev remembers everything a theme
can change), so each theme keeps its own layout. A theme with a timer, limit or
lockout starts a session (`~/.local/state/tide/session.json`, `services/Session.qml`):
a countdown that switches back to the previous theme, set-aside windows, and
schedules that start themes on their days. While locked in nothing switches; the
emergency exit is holding Mod + Esc for 5 seconds (the island shows a ring that
fills; a tap under 0.4 s still opens the power menu). While a timed theme runs, the
island shows a timer pill after dictation and recording (a click shows the theme and
when it ends); a set-aside app gets an island notice ("Firefox isn't allowed in Focus
· 18 min left"); the launcher lists only the allowed apps. Five minutes before a
scheduled start a notice offers Start now / Skip today; a start that passed while the
PC was off is skipped. Saved themes can be edited (the wizard, prefilled) unless
they're locked in. Mod + Ctrl + 1…9 switch to the
themes in picker order; Mod + T is the island picker. Saved themes have a delete
button (with a confirm); Dev can't be deleted. Ax-Classic (the old Ax-Shell setup) is
hidden from Tide ("hidden": true in its mode.json); `tide-mode ax-classic` still
switches to it.

## Motion and type

From the design's "Tide motion and typography" sheet, as tokens in `Theme.qml`:
the Spring and Standard curves, timings (island morph 420ms, reveal 300ms after
120ms, hide 150ms, panel drop 260ms, hover 180ms, wallpaper 600ms, accent
crossfade 500ms), the type scale, and `"reduceMotion"` in theme.json.

Opening, the island springs out while the clock grows a little and fades to
black, then the panel fades in. Closing, it settles into place with no
overshoot.

Settings → Appearance changes these live: animation speed (`motionSpeed`,
0 = off), reduce motion, and corner roundness (`roundness`, 0–24, 18 = the
design), which scales the bar, panels and island and sets Hyprland's window
corners; glass blur (`glassBlur`) sets Hyprland's blur. `hypr.lua` reads both
back from theme.json on every reload.

**Interface size** (Settings → Appearance, `uiScale`): Small 1 (the design),
Medium 1.15, Large 1.3. Every size in the shell goes through `Theme.s(px)`
(`Theme.sf(pt)` for point sizes), and the type tokens scale with it. A widget's
own resize multiplies on top, and Eve's saved size is kept in design units. The
change applies live. Settings also reloads Hyprland so `hypr.lua` scales the Eve
window rule. Some things stay the same at every size: 1px hairlines and borders,
shadows, animation timings and distances, window gaps and hyprlock. Widgets keep
their saved positions, so on a small screen Large can make them overlap until
you move them.

## Settings (`theme.json`)

`surface` (glass/dark for the bar and the island), `monitor` (the Hyprland
monitor the shell runs on), fonts, which pywal colors drive the accent and the music bars,
workspace count, the audio app for right-clicking the speaker, the AI toggle
URL and window class, the command that stops a recording, how often
updates are checked, and the updates panel's switches (`updatesAur`,
`updatesFlatpak`, `updatesSnapshot`, `updatesCachyNews`), and the clipboard
cleaner (`clipboardCleanup`, on: keeps the newest `clipboardMax` entries for
`clipboardDays` days).

## Where it can't match the design exactly

- **Blur strength:** the design uses blur(28px) on the bar and 40px on panels,
  plus saturate(180%). Hyprland has one global blur and a "vibrancy" setting
  instead, so `hypr.lua` uses one close value. Tune by eye.
- **Tray icons** are app icons, not the design's line icons. They're tinted to
  the design's grey (#C7C7CC) so they sit in with the rest.
- **Accent from pywal:** pywal doesn't mark one color as "the accent", so
  `walAccent` picks one (color4 by default). The canvas's sample palettes are
  used when pywal isn't installed (#F2A23C).
- **Temp** in the hover card is the CPU temperature.
- **Updates panel:** AUR
  rows have no download size (paru doesn't report one), and the panel closes
  when the update starts so the terminal gets the keyboard; click the percent
  to watch it.
- **Island opening** uses a softer spring than the sheet (about 1% overshoot
  instead of 4%).
- **Notification dot** stays hidden until the island's notification banner is
  built, so this shell doesn't take over notifications from your current daemon.

## Park mode (the kid space)

Hold Super+Alt+P for 1.5 s to park: every window goes to a hidden workspace and keeps
running (`bin/tide-park`), your apps' sound is muted (new streams too, every 3 s), and
Hyprland's `tide-park` key map leaves only the combo working. The screen becomes the
kid space (`shell/park/`, `shell/services/Park.qml`): the parked screen with a pulsing
Play button, his picture tiles, the games (Bubble Pop for the mouse, Letter Rain for
typing; Paint, Catch the Star and Animal Match are dimmed until built), and after an
hour of play the sleepy "time's up" screen. Hold the combo again to come back: every
window returns where it was and your sound comes back. Super+Ctrl+Alt+P unparks without
the shell, in case it isn't running. His stars and levels: `~/.local/state/tide/park-kid.json`.
Voice lines are made once with Breeze TTS (Eve's server, port 8180) and kept in
`~/.cache/tide/park-sound/` (`shell/scripts/park-sound.py`); the kid space's font is
Fredoka (OFL, `fonts/fredoka/`). This keeps things out of reach of little hands; it
isn't security (the lock screen is).

## Before release (packaging)

Right now Tide assumes this machine: pacman + an AUR helper + Flatpak for updates, kitty
for the update terminal, fish as the shell, snap-pac for snapshots. Before it's
packaged for other people, a first-run check should detect what each system
actually uses (package manager such as pacman, apt, dnf, zypper or Flatpak only;
AUR helper; terminal such as kitty, Alacritty, foot or WezTerm; shell such as
fish, zsh or bash; snapshot tool; GPUs and monitors), install or offer only what's
missing, and pick matching commands. The update commands already live only in
`shell/scripts/updates.py` and `shell/scripts/update-run.sh`, so each package
manager can be added there as its own backend without touching the panel.

The installer sets everything up as one piece: it installs all dependencies, and the
login screen too. SilentSDDM by uiriansan (`sddm-silent-theme`, GPL-2.0, credited in
Settings → Login screen) is installed and made SDDM's theme by default, then managed
from Settings → Login screen (`bin/tide-login-screen`). The AUR helper is detected
(`shell/scripts/aur-helper.sh`: yay or paru), not assumed.

Tide's Steam helper (`bin/tide-steam`) is built from `vendor/ugos-steam` with
`bin/build-tide-steam` (needs a Rust toolchain; it runs at low priority). A release
should either ship the built binary or run that script at setup; without it the game
launcher still shows installed Steam games from Steam's files.

"Pause local AI while playing" (game launcher, Settings → Games) is personal to a
setup with a local AI: it only shows when Settings → AI is on, and stays a stub
(EVE_WIRING.md) until it's wired to the AI backend.

The 3D printer widget's "Find printer" needs UDP port 2021 open for broadcasts from
the local network (a firewall such as ufw drops them by default); setup should offer
that, and typing the printer's address and serial works without it.
