#!/usr/bin/env bash
# Counts pending updates without touching the live pacman database:
# checkupdates (pacman-contrib), yay or paru -Qua (AUR) and flatpak.
c=0
if command -v checkupdates >/dev/null 2>&1; then c=$((c + $(checkupdates 2>/dev/null | wc -l))); fi
h=$(bash "$(dirname "$(readlink -f "$0")")/aur-helper.sh" "${TIDE_AUR_HELPER:-auto}")
if [ -n "$h" ]; then c=$((c + $("$h" -Qua 2>/dev/null | wc -l))); fi
if command -v flatpak >/dev/null 2>&1; then c=$((c + $(flatpak remote-ls --updates 2>/dev/null | wc -l))); fi
echo "$c"
