# Tide

A Quickshell shell for Hyprland: a bar with an island, widgets, a control center,
Settings, themes ("modes") with sessions, a game launcher, park mode with a kid space,
an update center and a login screen manager. Lightweight, and every feature can be
turned off. The shell itself is in `modes/dev/shell`; its full notes are in
`modes/dev/README.md`.

![Tide on a 4K screen](docs/screenshots/desktop.jpg)

## Screenshots

Close-ups at full size (taken on a 4K screen, interface at 115%), so the text is readable.

**The island**: the clock in the middle of the bar morphs into everything else.

| | |
|---|---|
| ![Launcher](docs/screenshots/launcher.png) | ![All apps](docs/screenshots/all-apps.png) |
| Launcher: recent apps and quick tools | Show all apps, A to Z |
| ![Math in the launcher](docs/screenshots/launcher-math.png) | ![Calculator](docs/screenshots/calculator.png) |
| Type math in the launcher | Calculator |
| ![Power menu](docs/screenshots/power-menu.png) | ![Themes](docs/screenshots/themes.png) |
| Power menu | Themes (modes) |
| ![Wallpapers](docs/screenshots/wallpapers.png) | ![Island at rest](docs/screenshots/island.png) |
| Wallpapers (images and videos) | The island at rest |

**Resource center**: GPU, CPU, memory, disk, network and processes, no terminal needed.

![Resource center](docs/screenshots/resource-center.png)

**Bar, control center and update center**

| | | |
|---|---|---|
| ![Control center](docs/screenshots/control-center.png) | ![Update center](docs/screenshots/updates.png) | ![Bar](docs/screenshots/bar-right.png) |
| Control center | Update center (hold back any package) | The bar's right side |

**Game launcher**: Steam, emulators and Lutris in one place; right-click a game for SteamGridDB art.

![Game launcher](docs/screenshots/game-launcher.jpg)
![Game art from SteamGridDB](docs/screenshots/game-art.jpg)

**Settings**

| | |
|---|---|
| ![Appearance](docs/screenshots/settings-appearance.png) | ![Monitors](docs/screenshots/settings-monitors.png) |
| Appearance | Monitors |
| ![Games](docs/screenshots/settings-games.png) | ![Login screen](docs/screenshots/settings-login-screen.png) |
| Games | Login screen (SilentSDDM) |
| ![Keybinds](docs/screenshots/settings-keybinds.png) | ![Terminal greeting](docs/screenshots/terminal-greeting.png) |
| Keybinds | Terminal greeting |

**Desktop widgets**

![Widgets](docs/screenshots/widgets.jpg)

## Install

On an Arch-based system (Arch, CachyOS, EndeavourOS…):

```sh
git clone https://github.com/xirorz/Tide.git
cd Tide
./install.sh
```

It asks only a few things, with nothing pre-picked: your web browser and file manager
(or skip, to keep what you have), your terminal, and the terminal greeting (Tide's wave
or a random Pokémon). It asks for an AUR helper too if the PC has none. Bluetooth is set up only when the PC has it. `./install.sh --yes` asks
nothing and installs only what Tide needs.

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

- Login screen theme: [SilentSDDM](https://github.com/uiriansan/SilentSDDM) by uiriansan (GPL-3.0), installed from its own AUR package (`sddm-silent-theme`); Tide ships none of its files and only writes its own settings file next to the theme
- Fonts (SIL Open Font License, licences next to each in `fonts/`): Inter, Geist,
  DM Sans, IBM Plex Sans, Space Grotesk, Orbitron, Monoton, JetBrains Mono, Fredoka
- Steam helper: `vendor/ugos-steam` (built into `bin/tide-steam`)

## Support

Tide is free and stays free. If it's useful to you and you'd like to say thanks, you
can buy me a coffee — completely optional, and appreciated.

[![Support Tide on Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Tide-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/xirorz)
