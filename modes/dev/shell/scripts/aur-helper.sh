#!/usr/bin/env bash
# The AUR helper the update center uses: the one picked in Settings → System, or the one
# found here. Every AUR command Tide runs asks this script (updates.py, updates.sh,
# aur-review.sh), so supporting another helper means teaching it here and there.
#   aur-helper.sh [choice]          prints yay or paru (nothing: no helper)
#   aur-helper.sh --json [choice]   {"use": "yay", "auto": "yay", "found": ["yay", "paru"]}
# choice: auto (default), yay or paru; one that isn't installed falls back to auto.
# Auto: the one installed; with both, yay when it has been used here (~/.config/yay or
# ~/.cache/yay), otherwise paru.
json=0
[ "$1" = --json ] && { json=1; shift; }
choice=${1:-auto}
found=()
for h in yay paru; do command -v "$h" >/dev/null 2>&1 && found+=("$h"); done
auto=
if [ ${#found[@]} -eq 1 ]; then
    auto=${found[0]}
elif [ ${#found[@]} -eq 2 ]; then
    if [ -d "$HOME/.config/yay" ] || [ -d "${XDG_CACHE_HOME:-$HOME/.cache}/yay" ]; then auto=yay; else auto=paru; fi
fi
use=$auto
case " ${found[*]} " in *" $choice "*) use=$choice ;; esac
if [ $json = 1 ]; then
    list=$(printf '"%s",' "${found[@]}"); list=${list%,}
    printf '{"use": "%s", "auto": "%s", "found": [%s]}\n' "$use" "$auto" "$list"
else
    echo "$use"
fi
