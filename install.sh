#!/usr/bin/env bash
# Tide installer: run it once from the cloned folder, as yourself (not root).
#   ./install.sh            check this PC, install what's missing, set Tide up
#   ./install.sh --dry-run  only say what it would do
# It's safe to run again: anything already there is left as it is. Files it replaces
# are kept next to them as <file>.before-tide.
set -euo pipefail

DRY=0
[ "${1:-}" = --dry-run ] && DRY=1
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
TIDE="$HOME/.config/Tide"
B=$'\e[1m' D=$'\e[2m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[0m'
step() { printf '\n%s● %s%s\n' "$B" "$1" "$R"; }
say() { printf '  %s\n' "$*"; }
run() { if [ $DRY = 1 ]; then printf '  %swould run:%s %s\n' "$D" "$R" "$*"; else "$@"; fi; }
backup() {  # keep the user's own file once, next to it
    if [ -e "$1" ] && [ ! -e "$1.before-tide" ]; then run cp -a "$1" "$1.before-tide"; say "kept yours as $1.before-tide"; fi
}

# ---- the system ----
step "Checking this PC"
[ "$(id -u)" = 0 ] && { echo "Run it as yourself, not root (it asks for your password when it needs to)."; exit 1; }
command -v pacman >/dev/null || { echo "Tide's installer needs an Arch-based system (pacman) for now."; exit 1; }
say "Arch-based system: yes"

# ---- where Tide lives: ~/.config/Tide ----
step "Placing Tide in ~/.config/Tide"
if [ "$(readlink -f "$TIDE" 2>/dev/null)" = "$HERE" ]; then
    say "already there"
else
    if [ -e "$TIDE" ]; then run mv "$TIDE" "$TIDE.before-tide-$(date +%Y%m%d-%H%M%S)"; say "moved the old ~/.config/Tide aside"; fi
    run mkdir -p "$HOME/.config"
    run ln -s "$HERE" "$TIDE"
    say "linked $TIDE → $HERE"
fi

# ---- packages ----
step "Packages"
PKGS=(
    git base-devel
    # the compositor and the shell
    hyprland quickshell uwsm xdg-desktop-portal-hyprland hyprpolkitagent hyprlock hypridle hyprpicker
    # wallpapers and colours
    awww-git mpvpaper matugen-bin imagemagick ffmpeg
    # sound, media, screens, network
    pipewire pipewire-pulse wireplumber libpulse playerctl brightnessctl networkmanager
    # clipboard, capture, OCR, recording
    wl-clipboard cliphist grim slurp tesseract tesseract-data-eng gpu-screen-recorder
    # Tide's tools
    python libnotify zenity kitty pacman-contrib curl polkit xdg-utils
    # the login screen (SilentSDDM by uiriansan) and the lock screen's font
    sddm sddm-silent-theme ttf-iosevka-nerd
)
mapfile -t MISSING < <(pacman -T "${PKGS[@]}" 2>/dev/null || true)
if [ ${#MISSING[@]} -eq 0 ]; then
    say "everything Tide needs is installed"
else
    say "missing: ${MISSING[*]}"
    # an AUR helper for the packages that live in the AUR (yay or paru; yay if neither)
    HELPER=$(bash "$HERE/modes/dev/shell/scripts/aur-helper.sh" 2>/dev/null || true)
    if [ -z "$HELPER" ]; then
        say "no AUR helper: installing yay"
        run sudo pacman -S --needed --noconfirm git base-devel
        if [ $DRY = 0 ]; then
            tmp=$(mktemp -d)
            git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
            (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
            rm -rf "$tmp"
        else
            say "would build yay-bin from the AUR"
        fi
        HELPER=yay
    fi
    case $HELPER in
        yay) run yay -S --needed --noconfirm --answerdiff None --answerclean None --removemake "${MISSING[@]}" ;;
        paru) run paru -S --needed --noconfirm --skipreview "${MISSING[@]}" ;;
    esac
fi

# ---- Hyprland: the loader points at Tide ----
step "Hyprland"
run mkdir -p "$HOME/.config/hypr"
if cmp -s "$HERE/install/hyprland-loader.lua" "$HOME/.config/hypr/hyprland.lua"; then
    say "Tide's loader is already in place"
else
    backup "$HOME/.config/hypr/hyprland.lua"
    run cp "$HERE/install/hyprland-loader.lua" "$HOME/.config/hypr/hyprland.lua"
    say "~/.config/hypr/hyprland.lua now loads Tide"
fi
if [ ! -f "$HOME/.config/hypr/monitors.conf" ]; then
    if [ $DRY = 1 ]; then say "would write monitors.conf (every screen at its preferred mode)"
    else echo 'monitor=,preferred,auto,1' > "$HOME/.config/hypr/monitors.conf"; fi
    say "monitors: each screen at its best mode (change them in Settings → Monitors)"
fi
# the lock and idle configs: Tide's, unless they already are (Tide's Settings edit them)
for f in hyprlock.conf hypridle.conf; do
    mark=$([ $f = hypridle.conf ] && echo "Written by Tide" || echo "Tide/colors/hyprlock-colors.conf")
    if ! grep -qs "$mark" "$HOME/.config/hypr/$f"; then
        backup "$HOME/.config/hypr/$f"
        run cp "$HERE/install/$f" "$HOME/.config/hypr/$f"
        say "$f: Tide's"
    fi
done

# ---- services ----
step "Services"
run mkdir -p "$HOME/.config/systemd/user"
run cp "$HERE/install/systemd/tide-awww.service" "$HOME/.config/systemd/user/tide-awww.service"
run systemctl --user daemon-reload
say "wallpaper daemon: tide-awww (started at login)"
# SilentSDDM as the login screen
if ! grep -qsx 'Current=silent' /etc/sddm.conf /etc/sddm.conf.d/*.conf; then
    if [ $DRY = 1 ]; then say "would set SilentSDDM as the login screen theme"
    else printf '# Tide: SilentSDDM as the login screen (Settings → Login screen)\n[Theme]\nCurrent=silent\n' | sudo tee /etc/sddm.conf.d/zz-tide-theme.conf >/dev/null || {
             sudo mkdir -p /etc/sddm.conf.d
             printf '# Tide: SilentSDDM as the login screen (Settings → Login screen)\n[Theme]\nCurrent=silent\n' | sudo tee /etc/sddm.conf.d/zz-tide-theme.conf >/dev/null; }
    fi
    say "login screen theme: SilentSDDM"
fi
dm=$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)
if [ "$(basename "${dm:-none}")" != sddm.service ]; then
    [ -n "$dm" ] && say "your login screen was $(basename "$dm"): switching to SDDM"
    run sudo systemctl enable -f sddm.service
fi

# ---- fonts, colours, folders ----
step "Fonts, colours and folders"
run mkdir -p "$HOME/.local/share/fonts/tide"
if [ $DRY = 1 ]; then say "would copy Tide's fonts to ~/.local/share/fonts/tide"
else find "$HERE/fonts" -name '*.ttf' -exec cp -u {} "$HOME/.local/share/fonts/tide/" \;; fc-cache -f "$HOME/.local/share/fonts/tide" >/dev/null; fi
say "fonts: Tide's (also for the lock screen)"
if [ ! -f "$HERE/colors/colors.css" ]; then
    # until the first wallpaper: colours from Tide's blue
    run matugen color hex "#3C8CE0" -c "$HERE/colors/matugen.toml"
    say "colours: Tide's default (they follow your wallpaper from the first one you pick)"
fi
[ -f "$HERE/mode" ] || { if [ $DRY = 1 ]; then say "would set the mode to dev"; else echo dev > "$HERE/mode"; fi; }
run mkdir -p "$HOME/wallpapers"
say "wallpapers go in ~/wallpapers (Super+W)"

# ---- the Steam helper: only with Steam on the PC ----
if command -v steam >/dev/null && [ ! -x "$HERE/bin/tide-steam" ]; then
    step "Steam helper (installs games from the launcher)"
    pacman -T rust >/dev/null 2>&1 || run sudo pacman -S --needed --noconfirm rust
    run "$HERE/bin/build-tide-steam"
fi

step "Done"
if [ $DRY = 1 ]; then
    say "that was a dry run: nothing was changed"
else
    say "${G}Tide is installed.${R} Log out (or restart), pick Hyprland on the login screen and log in."
    say "Then: Super+W for a wallpaper, Super+Space for the launcher, Super+D for the control center."
fi
