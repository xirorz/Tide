#!/usr/bin/env bash
# Run by `wl-paste --watch` for every new clip (text and images): store it in
# cliphist, note which app it came from and when, then run the cleanup cycle.
dir="$(cd "$(dirname "$0")" && pwd)"
cliphist store || exit 0
id=$(cliphist list | head -1 | cut -f1)
app=$(hyprctl activewindow -j 2>/dev/null | python3 -I -c 'import json,sys
try: print(json.load(sys.stdin).get("class", ""))
except Exception: print("")')
[ -n "$id" ] && python3 -I "$dir/clipmeta.py" add "$id" "$app"
python3 -I "$dir/clipmeta.py" cleanup
