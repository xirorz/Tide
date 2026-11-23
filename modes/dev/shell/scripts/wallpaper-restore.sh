#!/usr/bin/env bash
# At login (the shell starting, services/Wallpapers.qml): start the video wallpapers
# again. awww brings back still images by itself; mpvpaper doesn't remember anything.
# ~/.local/state/tide/wallpaper.json says what each screen shows (wallpaper-apply.sh
# writes it); without it, the last wallpaper applied, on every screen, if it's a video.
# Both draw on the background layer and the one that starts last is on top, so the video
# waits for awww's picture to be up first; a video already playing above awww is left
# alone (running this twice is fine), one that ended up under it is started again.
state="$HOME/.local/state/tide/wallpaper.json"
recent="$HOME/.local/state/tide/wallpapers-recent"
# where each screen's background layers are, bottom first: "<monitor> <namespace> <pid>"
layers() {
    hyprctl layers -j | python3 -I -c 'import json,sys
for mon, v in json.load(sys.stdin).items():
    for l in v["levels"].get("0", []):
        print(mon, l["namespace"], l["pid"])'
}
# awww itself (images; it brings back each screen's own): started again if it isn't
# running, e.g. it was started before this session's display was known
if ! pgrep -x awww-daemon >/dev/null && systemctl --user cat ax-shell-awww.service >/dev/null 2>&1; then
    systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
    systemctl --user reset-failed ax-shell-awww.service
    systemctl --user restart ax-shell-awww.service
fi
mons=$(hyprctl monitors -j | python3 -I -c 'import json,sys; print(" ".join(m["name"] for m in json.load(sys.stdin)))')
for m in $mons; do
    f=$(python3 -I -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))
except Exception: pass' "$state" "$m")
    [ -z "$f" ] && [ ! -f "$state" ] && f=$(head -1 "$recent" 2>/dev/null)
    case "${f,,}" in *.mp4|*.webm|*.mkv|*.mov) ;; *) continue ;; esac
    [ -f "$f" ] || continue
    # awww's picture first (at login they start together), for up to 15 s
    if pgrep -x awww-daemon >/dev/null; then
        for _ in $(seq 30); do layers | grep -q "^$m awww-daemon " && break; sleep 0.5; done
    fi
    order=$(layers | awk -v m="$m" '$1 == m { print $2 " " $3 }')
    vpid=$(echo "$order" | awk '$1 == "mpvpaper" { print $2; exit }')
    if [ -n "$vpid" ]; then
        # playing: fine when nothing of awww's is above it
        echo "$order" | awk '$1 == "mpvpaper" { v = 1; next } v && $1 == "awww-daemon" { under = 1 } END { exit !under }' || continue
        kill "$vpid" 2>/dev/null; sleep 0.3
    fi
    setsid mpvpaper -o '--loop --no-audio' "$m" "$f" >/dev/null 2>&1 &
    echo "video  $m  $f"
done

# the lights: Tide's wallpaper colour again (scripts/rgb-apply.sh). At login OpenRGB's
# server restarts and an older theme script sets its own saved colour when it does, so
# this waits for that to have run (up to a minute), then puts the wallpaper's colour back
if [ -x "$HOME/.local/bin/matugen-openrgb-sync" ] && [ -f "$HOME/.config/Tide/colors/colors.css" ]; then
    (
        start=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
        for _ in $(seq 60); do
            # the old script's last run ended after this login started
            done_at=$(systemctl --user show matugen-openrgb.service -p InactiveEnterTimestampMonotonic --value 2>/dev/null)
            if systemctl --user -q is-active openrgb-server.service 2>/dev/null \
               && [ "$(systemctl --user show matugen-openrgb.service -p ActiveState --value 2>/dev/null)" != activating ] \
               && [ "${done_at:-0}" -ge $(( start * 1000000 - 5000000 )) ]; then
                break
            fi
            sleep 1
        done
        sleep 1
        bash "$(dirname "$(readlink -f "$0")")/rgb-apply.sh" >/dev/null 2>&1
    ) &
fi
