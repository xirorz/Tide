#!/usr/bin/env bash
# Light the RGB with the wallpaper's color, vivid like Ax-Shell's "wallpaper" lighting
# theme: the hue of matugen's primary at the full saturation of on-primary (matugen's
# pastel primary alone washes out to near white on LEDs). Only "rgbBrightness" in
# theme.json (percent, 10-100) decides how bright. Goes through the user's own
# matugen-openrgb-sync, so the headset and the multi-color panels follow too.
#   rgb-apply.sh [brightness]
dir="$(cd "$(dirname "$0")/../.." && pwd)"
css="$HOME/.config/Tide/colors/colors.css"
sync="$HOME/.local/bin/matugen-openrgb-sync"
bright="${1:-$(python3 -I -c 'import json,sys
try: print(int(json.load(open(sys.argv[1])).get("rgbBrightness", 10)))
except Exception: print(10)' "$dir/theme.json")}"

vivid=$(python3 -I - "$css" <<'PY'
import re, sys, colorsys
css = open(sys.argv[1]).read()
def hsv(name):
    m = re.search(r"--" + name + r":\s*#([0-9A-Fa-f]{6})", css)
    h = m.group(1)
    return colorsys.rgb_to_hsv(*(int(h[i:i+2], 16) / 255 for i in (0, 2, 4)))
hue, s_pri, _ = hsv("primary")
_, s_on, _ = hsv("on-primary")
r, g, b = colorsys.hsv_to_rgb(hue, max(s_on, s_pri, 0.72), 1.0)
print(f"#{int(r*255):02X}{int(g*255):02X}{int(b*255):02X}")
PY
) || exit 1

# the sync script reads a named color from a css file: hand it the wallpaper's
# colors plus ours (it still takes the panels' palette from the same file)
tmp=$(mktemp --suffix=.css)
{ cat "$css"; echo "  --tide-rgb: $vivid;"; } > "$tmp"
"$sync" "$tmp" tide-rgb --brightness "$bright" >/dev/null 2>&1
rc=$?
rm -f "$tmp"
echo "rgb: $vivid at $bright%"
exit $rc
