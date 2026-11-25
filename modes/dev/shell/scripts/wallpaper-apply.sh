#!/usr/bin/env bash
# Apply a wallpaper the way Ax-Shell did, so both shells agree:
#   wallpaper-apply.sh <file> <outputs: all | DP-1,HDMI-A-1> <transition: grow|fade|wipe> <rgb: 0|1>
# Images go through awww, videos through mpvpaper (looping). ~/.current.wall points at
# it (a video's thumbnail stands in), matugen recolors from it, and with rgb=1 the
# lights follow (Ax-Shell's lighting theme and brightness).
file="$1"; outputs="${2:-all}"; transition="${3:-grow}"; rgb="${4:-0}"
[[ -f "$file" ]] || { echo "no such file: $file" >&2; exit 1; }
name=$(basename "$file")
thumb="$HOME/.cache/tide/wallthumbs/$(printf "%s" "$name" | md5sum | cut -d' ' -f1).png"

if [[ "$outputs" == all ]]; then
    mons=$(hyprctl monitors -j | python3 -I -c 'import json,sys; print(" ".join(m["name"] for m in json.load(sys.stdin)))')
else
    mons=${outputs//,/ }
fi

case "${name,,}" in
    *.mp4|*.webm|*.mkv|*.mov)
        for m in $mons; do
            pkill -f "mpvpaper.* $m " 2>/dev/null
            setsid mpvpaper -o '--loop --no-audio' "$m" "$file" >/dev/null 2>&1 &
        done
        colors_from="$thumb"
        ;;
    *)
        for m in $mons; do pkill -f "mpvpaper.* $m " 2>/dev/null; done
        # motion sheet: 600ms ease-in-out; Grow starts from the cursor on the screen
        # it's on (awww counts from the bottom-left), the other screens grow from center
        cur=$(hyprctl cursorpos)
        for m in $mons; do
            pos=center
            if [[ "$transition" == grow ]]; then
                pos=$(hyprctl monitors -j | python3 -I -c 'import json,sys
cx, cy = (int(float(v)) for v in sys.argv[2].split(","))
for mon in json.load(sys.stdin):
    if mon["name"] == sys.argv[1]:
        x, y = cx - mon["x"], cy - mon["y"]
        w, h = mon["width"], mon["height"]
        print(f"{x},{h - y}" if 0 <= x < w and 0 <= y < h else "center")' "$m" "$cur")
            fi
            awww img "$file" -o "$m" -t "$transition" --transition-pos "$pos" --transition-duration 0.6 \
                --transition-bezier 0.42,0,0.58,1 --transition-fps 60 --transition-step 255 -f Nearest &
        done
        wait
        colors_from="$file"
        ;;
esac

# the current wallpaper, for anything that reads it (Ax-Shell, hyprlock, the picker)
ln -sfn "$colors_from" "$HOME/.current.wall"
# what each screen shows, so scripts/wallpaper-restore.sh can start videos again at login
state="$HOME/.local/state/tide/wallpaper.json"
mkdir -p "$(dirname "$state")"
python3 -I - "$state" "$file" $mons <<'PY'
import json, sys
p, f, mons = sys.argv[1], sys.argv[2], sys.argv[3:]
try:
    d = json.load(open(p))
except Exception:
    d = {}
d.update({m: f for m in mons})
json.dump(d, open(p, "w"), indent=2)
PY
# recent list for the picker's Recent filter (newest first, unique, 24 kept)
recent="$HOME/.local/state/tide/wallpapers-recent"
mkdir -p "$(dirname "$recent")"
{ echo "$file"; grep -vxF "$file" "$recent" 2>/dev/null; } | head -24 > "$recent.tmp" && mv "$recent.tmp" "$recent"

# Tide's own colours first (~/.config/Tide/colors: colors.css for the shell,
# hyprlock-colors.conf), from the picker's thumbnail when there is one: the same colours
# as the full image, many times faster. Through scripts/matugen.sh: matugen 4 would
# otherwise wait for a colour to be picked.
mat_from="$colors_from"
[[ -s "$thumb" ]] && mat_from="$thumb"
"$(dirname "$0")/matugen.sh" image -c "$HOME/.config/Tide/colors/matugen.toml" "$mat_from"
# tinted apps follow the new colours (only while Tinted is on for apps)
"$HOME/.config/Tide/bin/tide-apptint" refresh >/dev/null 2>&1 &
# then your own matugen setup (other apps' themes), if you have one, without waiting
if [[ -f "$HOME/.config/matugen/config.toml" ]]; then
    "$(dirname "$0")/matugen.sh" image "$colors_from" >/dev/null 2>&1 &
fi

if [[ "$rgb" == 1 ]]; then
    # the lights take the wallpaper's color, vivid, at "rgbBrightness" (scripts/rgb-apply.sh)
    bash "$(dirname "$0")/rgb-apply.sh" >/dev/null 2>&1 &
fi
