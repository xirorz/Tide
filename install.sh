#!/usr/bin/env bash
# Tide installer: run it once from the cloned folder, as yourself (not root).
#   ./install.sh            a few questions (browser, file manager, ...), then it checks
#                           this PC, installs what's missing and sets Tide up
#   ./install.sh --yes      no questions: only what Tide needs (choices skipped)
#   ./install.sh --dry-run  only say what it would do (combine with --yes)
# It's safe to run again: anything already there is left as it is. Files it replaces
# are kept next to them as <file>.before-tide.
set -euo pipefail

DRY=0 YES=0
for a in "$@"; do case $a in --dry-run) DRY=1 ;; --yes|-y) YES=1 ;; esac; done
[ -t 0 ] || YES=1          # not typed at a terminal: no questions
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

# ---- what you'd like with it (each can be skipped) ----
# ask "question" "key|Label|packages" ... → sets ANSWER to the key. Nothing is
# recommended: Enter means Skip where there is one, otherwise a number is needed.
ask() {
    local q=$1; shift
    local opts=("$@") i=1 o skip=""
    for o in "${opts[@]}"; do [ "${o%%|*}" = skip ] && skip=skip; done
    if [ $YES = 1 ]; then ANSWER=${skip:-${opts[0]%%|*}}; return; fi
    printf '\n  %s%s%s\n' "$B" "$q" "$R"
    for o in "${opts[@]}"; do o=${o#*|}; printf '    %s%d%s  %s\n' "$B" $i "$R" "${o%%|*}"; i=$((i + 1)); done
    while true; do
        read -r -p "  Number${skip:+ (Enter = skip)}: " n
        if [ -z "$n" ] && [ -n "$skip" ]; then ANSWER=skip; return; fi
        if [[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#opts[@]} ]; then ANSWER=${opts[$((n - 1))]%%|*}; return; fi
    done
}
pkgs_of() {  # the packages of the chosen option
    local o; for o in "${@:2}"; do [ "${o%%|*}" = "$1" ] && { o=${o#*|}; echo "${o#*|}"; return; }; done
}
EXTRA=()
step "A few choices"
[ $YES = 1 ] && say "no questions (--yes): only what Tide needs"

if [ -z "$(bash "$HERE/modes/dev/shell/scripts/aur-helper.sh" 2>/dev/null || true)" ]; then
    O=("yay|yay|" "paru|paru|"); ask "AUR helper (Tide needs one: some of its parts are in the AUR)" "${O[@]}"; WANT_HELPER=$ANSWER
fi
O=("firefox|Firefox|firefox" "chromium|Chromium|chromium" "brave|Brave|brave-bin" "zen|Zen Browser|zen-browser-bin" "chrome|Google Chrome|google-chrome" "skip|Skip (keep what I have)|")
ask "Web browser" "${O[@]}"; BROWSER=$ANSWER; EXTRA+=($(pkgs_of "$ANSWER" "${O[@]}"))
O=("nemo|Nemo|nemo" "nautilus|Nautilus (GNOME Files)|nautilus" "thunar|Thunar|thunar" "dolphin|Dolphin|dolphin" "skip|Skip (keep what I have)|")
ask "File manager (Super+E)" "${O[@]}"; FILES=$ANSWER; EXTRA+=($(pkgs_of "$ANSWER" "${O[@]}"))
O=("kitty|Kitty|kitty" "alacritty|Alacritty|alacritty" "foot|Foot|foot" "ghostty|Ghostty|ghostty" "wezterm|WezTerm|wezterm")
ask "Terminal (Super+Enter)" "${O[@]}"; TERMINAL=$ANSWER; EXTRA+=($(pkgs_of "$ANSWER" "${O[@]}"))
# Bluetooth: only when the PC has it (no question)
BLUETOOTH=no
if [ -n "$(ls /sys/class/bluetooth 2>/dev/null)" ]; then BLUETOOTH=yes; EXTRA+=(bluez bluez-utils); say "Bluetooth: this PC has it, so it's set up"; fi
# a laptop: power modes (Power saver / Balanced / Performance), unless TLP or tuned
# already manage power (they'd fight)
LAPTOP=no
if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    LAPTOP=yes
    if pacman -Q tlp >/dev/null 2>&1 || pacman -Q tuned >/dev/null 2>&1 || pacman -Q tuned-ppd >/dev/null 2>&1; then
        say "Laptop: battery found (TLP or tuned manages power, so Tide leaves it to them)"
    else
        EXTRA+=(power-profiles-daemon); say "Laptop: battery found, power modes set up"
    fi
fi

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
    awww mpvpaper matugen-bin ffmpeg
    # sound, media, screens, network
    pipewire pipewire-pulse wireplumber libpulse playerctl brightnessctl networkmanager
    # clipboard, capture, OCR, recording
    wl-clipboard cliphist grim slurp tesseract tesseract-data-eng gpu-screen-recorder
    # Tide's tools
    python libnotify zenity pacman-contrib curl polkit xdg-utils
    # the login screen (SilentSDDM by uiriansan) and the lock screen's font
    sddm sddm-silent-theme ttf-iosevka-nerd
    # the volume app the control center opens
    pavucontrol
)
PKGS+=("${EXTRA[@]}")
mapfile -t MISSING < <(pacman -T "${PKGS[@]}" 2>/dev/null || true)
if [ ${#MISSING[@]} -eq 0 ]; then
    say "everything Tide needs is installed"
else
    say "missing: ${MISSING[*]}"
    # an AUR helper for the packages that live in the AUR (yay or paru; yay if neither)
    HELPER=$(bash "$HERE/modes/dev/shell/scripts/aur-helper.sh" 2>/dev/null || true)
    if [ -z "$HELPER" ]; then
        HELPER=${WANT_HELPER:-yay}
        say "no AUR helper: installing $HELPER"
        run sudo pacman -S --needed --noconfirm git base-devel
        if [ $DRY = 0 ]; then
            tmp=$(mktemp -d)
            git clone --depth 1 "https://aur.archlinux.org/$HELPER-bin.git" "$tmp/$HELPER-bin"
            (cd "$tmp/$HELPER-bin" && makepkg -si --noconfirm)
            rm -rf "$tmp"
        else
            say "would build $HELPER-bin from the AUR"
        fi
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

# the lock screen, sized for the screens here (redone at every login)
if [ $DRY = 1 ]; then say "would size the lock screen for this PC's screens"
else "$HERE/bin/tide-lockconf" || true; fi

# ---- services ----
step "Services"
run mkdir -p "$HOME/.config/systemd/user"
run cp "$HERE/install/systemd/tide-awww.service" "$HOME/.config/systemd/user/tide-awww.service"
run systemctl --user daemon-reload
say "wallpaper daemon: tide-awww (started at login)"
# SilentSDDM as the login screen
if [ ! -f /etc/sddm.conf.d/zz-tide-theme.conf ] && ! grep -qsx 'Current=silent' /etc/sddm.conf /etc/sddm.conf.d/*.conf; then
    if [ $DRY = 1 ]; then say "would set SilentSDDM as the login screen theme"
    else printf '# Tide: SilentSDDM as the login screen (Settings → Login screen)\n[Theme]\nCurrent=silent\n' | sudo tee /etc/sddm.conf.d/zz-tide-theme.conf >/dev/null || {
             sudo mkdir -p /etc/sddm.conf.d
             printf '# Tide: SilentSDDM as the login screen (Settings → Login screen)\n[Theme]\nCurrent=silent\n' | sudo tee /etc/sddm.conf.d/zz-tide-theme.conf >/dev/null; }
    fi
    say "login screen theme: SilentSDDM"
fi
# Hyprland as the session the login screen starts: SDDM starts the last one used (its
# state file), and an auto-login names one too; both become Hyprland. A theme set in
# another SDDM file becomes SilentSDDM too (the last file read wins).
SESSION=hyprland.desktop
if [ $DRY = 1 ]; then say "would make Hyprland the login screen's session"
else
    sudo python3 -I - "$SESSION" "$USER" <<'PY'
import glob, os, re, sys
session, user = sys.argv[1:]
def put(path, sec, key, val, only_if_set=False):
    try: lines = open(path).read().splitlines()
    except OSError:
        if only_if_set: return
        lines = []
    cur, at, end = None, None, None
    for i, l in enumerate(lines):
        t = l.strip()
        if t.startswith("[") and t.endswith("]"):
            if cur == sec and end is None: end = i
            cur = t[1:-1]
        elif cur == sec and "=" in t and t.split("=", 1)[0].strip() == key: at = i
    if at is not None: lines[at] = f"{key}={val}"
    elif only_if_set: return
    elif cur == sec and end is None: lines.append(f"{key}={val}")
    elif end is not None: lines.insert(end, f"{key}={val}")
    else: lines += [f"[{sec}]", f"{key}={val}"]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(lines) + "\n")
put("/var/lib/sddm/state.conf", "Last", "Session", "/usr/share/wayland-sessions/" + session)
put("/var/lib/sddm/state.conf", "Last", "User", user)
for f in ["/etc/sddm.conf"] + glob.glob("/etc/sddm.conf.d/*.conf"):
    put(f, "Autologin", "Session", session, only_if_set=True)
    # /etc/sddm.conf is read last: a theme named there would hide SilentSDDM
    if not f.endswith("zz-tide-theme.conf"):
        put(f, "Theme", "Current", "silent", only_if_set=True)
PY
    sudo chown sddm:sddm /var/lib/sddm/state.conf 2>/dev/null || true
fi
say "login screen: Hyprland is the session"
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

# ---- your choices as Tide's defaults ----
step "Your apps"
if [ $DRY = 1 ]; then say "would set Tide's terminal to $TERMINAL and file manager to $FILES"
else
    python3 -I - "$HERE/modes/dev/theme.json" "$TERMINAL" "$FILES" <<'PY'
import json, sys, os
p, term, files = sys.argv[1:]
try: d = json.load(open(p))
except Exception: d = {}
d["terminal"] = term
if files != "skip": d["fileManager"] = files
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
PY
fi
say "Super+Enter: $TERMINAL$([ "$FILES" != skip ] && echo ", Super+E: $FILES")"
case $BROWSER in
    firefox) desk=firefox.desktop ;; chromium) desk=chromium.desktop ;; brave) desk=brave-browser.desktop ;;
    zen) desk=zen.desktop ;; chrome) desk=google-chrome.desktop ;; *) desk= ;;
esac
if [ -n "$desk" ]; then run xdg-settings set default-web-browser "$desk" || true; say "default browser: $BROWSER"; fi
if [ "$BLUETOOTH" = yes ]; then run sudo systemctl enable bluetooth.service; say "Bluetooth: on (from the next start)"; fi
if [ "$LAPTOP" = yes ] && [[ " ${EXTRA[*]} " == *" power-profiles-daemon "* ]]; then run sudo systemctl enable --now power-profiles-daemon.service; say "power modes: on"; fi
# Tide's network controls use NetworkManager: turned on for the next start if it isn't
# running (nothing is stopped now, so the install keeps its connection)
if ! systemctl -q is-active NetworkManager.service 2>/dev/null; then
    run sudo systemctl enable NetworkManager.service
    for other in systemd-networkd.service iwd.service dhcpcd.service; do
        systemctl -q is-enabled "$other" 2>/dev/null && run sudo systemctl disable "$other"
    done
    say "network: NetworkManager from the next start"
fi

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
    say "${G}Tide is installed.${R} Restart, pick Hyprland on the login screen and log in."
    say "Then: Super+W for a wallpaper, Super+Space for the launcher, Super+D for the control center."
fi
