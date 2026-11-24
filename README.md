# Tide

A Quickshell shell for Hyprland: a bar with an island, widgets, a control center,
Settings, themes ("modes") with sessions, a game launcher, park mode with a kid space,
an update center and a login screen manager. Lightweight, and every feature can be
turned off. The shell itself is in `modes/dev/shell`; its full notes are in
`modes/dev/README.md`.

## Install

On an Arch-based system (Arch, CachyOS, EndeavourOS…):

```sh
git clone https://github.com/xirorz/Tide.git
cd Tide
./install.sh
```

It starts with a few quick choices, each with a recommended answer (Enter) and most
with Skip: AUR helper (yay or paru, when there's neither), web browser, file manager
(Super+E), terminal (Super+Enter), code editor, video player, games (Steam, Lutris),
Bluetooth and Flatpak. `./install.sh --yes` takes the recommended answers without asking.

Then the installer checks the PC, installs whatever is missing (from the
official repos and the AUR, with yay or paru; it installs yay if there's neither) and
sets Tide up: Hyprland's config, the lock and idle screens, the wallpaper daemon,
fonts, colours, and SilentSDDM as the login screen. Files it replaces are kept next to
them as `<file>.before-tide`. It's safe to run again; `./install.sh --dry-run` only
shows what it would do. Then restart, pick Hyprland on the login screen and log in.

It works from a bare console right after installing Arch or CachyOS: you need your user
(with sudo), a network connection and git (`sudo pacman -S git`).

Tide lives in `~/.config/Tide` (the installer links it there if you cloned it
elsewhere). Your own settings are made on first use and stay out of the repo; extras
only your PC needs (its hardware, apps, startup programs) go in `hypr/local.lua`.

## Credits

- Login screen theme: [SilentSDDM](https://github.com/uiriansan/SilentSDDM) by uiriansan (GPL-2.0)
- Fonts (SIL Open Font License, licences next to each in `fonts/`): Inter, Geist,
  DM Sans, IBM Plex Sans, Space Grotesk, Orbitron, Monoton, JetBrains Mono, Fredoka
- Steam helper: `vendor/ugos-steam` (built into `bin/tide-steam`)
