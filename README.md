# Tide

A Quickshell shell for Hyprland: a bar with an island, widgets, a control center,
Settings, themes ("modes") with sessions, a game launcher, park mode with a kid space,
an update center and a login screen manager. Lightweight, and every feature can be
turned off. The shell itself is in `modes/dev/shell`; its full notes are in
`modes/dev/README.md`.

## Install (early: tested on one Arch/CachyOS PC)

1. Clone into `~/.config/Tide`.
2. Point Hyprland at it: copy `install/hyprland-loader.lua` to `~/.config/hypr/hyprland.lua`
   (back up yours first). The loader picks the active mode's config; Dev's is
   `hypr/hyprland.lua`, which loads the look from `modes/dev/hypr.lua`.
   It reads monitors from `~/.config/hypr/monitors.conf` (Settings → Monitors writes it).
3. Needs: Hyprland 0.57+ (Lua config), Quickshell 0.3+, matugen, awww, mpvpaper,
   PipeWire (`pw-play`, `pactl`), Python 3, `notify-send`, zenity, kitty (update window).
   Optional: yay or paru (AUR updates), Flatpak, Steam, Lutris, OpenRGB, SDDM with
   SilentSDDM (login screen), a Rust toolchain for the Steam helper
   (`bin/build-tide-steam`), a local AI server for the AI panel (`modes/dev/EVE_WIRING.md`).
4. Log in to Hyprland. Per-user settings (`modes/dev/theme.json`, `mode`, notification
   rules, emulators, AI backends) are made on first use and are not part of the repo.

A first-run setup that detects each system and installs what's missing is planned
(see "Before release" in `modes/dev/README.md`). Until then `hypr/hyprland.lua` still
carries one PC's apps and keys.

## Credits

- Login screen theme: [SilentSDDM](https://github.com/uiriansan/SilentSDDM) by uiriansan (GPL-2.0)
- Fonts (SIL Open Font License, licences next to each in `fonts/`): Inter, Geist,
  DM Sans, IBM Plex Sans, Space Grotesk, Orbitron, Monoton, JetBrains Mono, Fredoka
- Steam helper: `vendor/ugos-steam` (built into `bin/tide-steam`)
