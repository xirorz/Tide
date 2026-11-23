#!/usr/bin/env bash
# The AUR step of an update (update-run.sh runs it inside the update window).
#   aur-review.sh <real|dry> <review 0|1>
# The helper is yay or paru (scripts/aur-helper.sh; TIDE_AUR_HELPER is the Settings →
# System choice). With review on (the default) every AUR package with an update is
# asked about first: show its build script (PKGBUILD, read-only, in the window), skip it,
# or skip all the rest. After that the helper runs without its own review/diff menu,
# because each package has had its question; its other questions (Proceed? clean build?
# remove make dependencies? password) still come up here as usual. Nothing is answered
# for you. A dry run asks the same questions but builds nothing.
mode=$1 review=${2:-1}
here=$(dirname "$(readlink -f "$0")")
helper=$(bash "$here/aur-helper.sh" "${TIDE_AUR_HELPER:-auto}")
hex=${TIDE_ACCENT:-#F2A23C}; hex=${hex#\#}; hex=${hex: -6}
A=$(printf '\e[38;2;%d;%d;%dm' 0x${hex:0:2} 0x${hex:2:2} 0x${hex:4:2})
B=$'\e[1m' D=$'\e[38;2;154;154;160m' R=$'\e[0m'

if [ -z "$helper" ]; then
    echo "No AUR helper (yay or paru) found, so AUR packages are left as they are."
    exit 0
fi
# the update itself, without the helper's own review menus
case $helper in
    yay) run=(yay -Sua --answerdiff None --answeredit None) ;;
    paru) run=(paru -Sua --skipreview) ;;
esac
go() {
    if [ "$mode" = dry ]; then echo ":: rehearsal: ${run[*]} would run now"; exit 0; fi
    exec "${run[@]}"
}

[ "$review" = 1 ] || go

mapfile -t pkgs < <("$helper" -Qua -q 2>/dev/null)
if [ ${#pkgs[@]} -eq 0 ]; then
    echo "${D}No AUR updates.${R}"
    exit 0
fi
printf '%s%d AUR package%s to update%s %s(with %s). AUR build scripts are written by other users; you can read each one first.%s\n\n' \
    "$B" ${#pkgs[@]} "$([ ${#pkgs[@]} = 1 ] || echo s)" "$R" "$D" "$helper" "$R"

for p in "${pkgs[@]}"; do
    read -r -p "Review the build script for ${B}${p}${R}?  ${A}y${R} show it  ${A}n${R} skip  ${A}a${R} skip all remaining  [y/N/a] " a
    case $a in
        [Aa]*) echo "${D}Skipping the review for the rest.${R}"; break ;;
        [Yy]*)
            f=$(mktemp)
            { printf '%sBuild script (PKGBUILD) for %s — read-only%s\n%s↑ ↓ / Space to scroll · q to close%s\n\n' "$B" "$p" "$R" "$D" "$R"
              "$helper" -Gp "$p" 2>&1; } > "$f"
            less -R -P "$p · ↑ ↓ / Space to scroll · q to close" "$f"
            rm -f "$f"
            read -r -p "Continue the update? [Y/n] " c
            case $c in [Nn]*) echo; echo "Update cancelled. Nothing from the AUR was installed."; exit 1 ;; esac
            ;;
    esac
done
echo
go
