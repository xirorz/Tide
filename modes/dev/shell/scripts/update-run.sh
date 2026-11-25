#!/usr/bin/env bash
# Runs the update inside the floating terminal (class tide-updates).
#   update-run.sh <real|dry> <aur 0|1> <flatpak 0|1> <snapshot 0|1> [run id] [review 0|1]
# AUR packages go through scripts/aur-review.sh: with review on (the default) each
# one's build script can be read here first.
# Everything the terminal shows is copied to $DIR/log (script(1) keeps pacman on a
# real tty, so its questions still work). Lines starting with "::tide::" are markers
# the updates panel follows: run <id>, step <name>, rc <step> <code>, end <seconds>.
mode=$1 aur=$2 flat=$3 snap=$4 id=$5 review=${6:-1}
# held back in the panel (comma-separated names): skipped, and said so
held=${TIDE_HELD:-}
held=${held//[^A-Za-z0-9@._+,-]/}
export TIDE_HELD=$held
here=$(dirname "$(readlink -f "$0")")
DIR="${XDG_RUNTIME_DIR:-/tmp}/tide-updates"
mkdir -p "$DIR"
LOG="$DIR/log"
: > "$LOG"
echo $$ > "$DIR/pid"
start=$(date +%s)
mark() { echo "::tide:: $*" >> "$LOG"; }
mark run "$id"
finish() { [ -f "$DIR/pid" ] || return; mark end $(( $(date +%s) - start )); rm -f "$DIR/pid"; }
trap finish EXIT
trap 'exit 129' HUP

# headings in the window: the accent (TIDE_ACCENT, from the shell) and greys
hex=${TIDE_ACCENT:-#F2A23C}; hex=${hex#\#}; hex=${hex: -6}
A=$(printf '\e[38;2;%d;%d;%dm' 0x${hex:0:2} 0x${hex:2:2} 0x${hex:4:2})
B=$'\e[1m' D=$'\e[38;2;154;154;160m' R=$'\e[0m'
say() { printf '%s\n' "$*"; }
heading() { printf '\n%s%s●%s %s%s%s  %s%s%s\n\n' "$A" "" "$R" "$B" "$1" "$R" "$D" "$2" "$R"; }
printf '\e]2;Updates\a'
clear
printf '\n%sUpdates%s\n%sAnswer questions and type your password right here. The panel follows along.%s\n' "$B" "$R" "$D" "$R"

step() {  # step <name> <command>
    case $1 in
        pacman) heading "System packages" "pacman" ;;
        aur) heading "AUR packages" "$(bash "$here/aur-helper.sh" "${TIDE_AUR_HELPER:-auto}")" ;;
        flatpak) heading "Flatpak apps" "flatpak" ;;
    esac
    mark step "$1"
    script -qfea -c "$2" "$LOG"
    local rc=$?
    mark rc "$1" "$rc"
    return $rc
}

if [ "$mode" = dry ]; then
    # a rehearsal with the design's sample output: nothing is installed
    fake=$(mktemp)
    cat > "$fake" <<'EOF'
say() { printf '%s\n' "$1"; sleep "${2:-0.25}"; }
say ':: Synchronizing package databases...' 0.6
say ' core is up to date'; say ' extra is up to date'; say ' cachyos is up to date'
say ':: Starting full system upgrade...' 0.5
say 'resolving dependencies...'; say 'looking for conflicting packages...'
say ''; say 'Packages (3)  linux-cachyos-6.17.9-1  mesa-25.2.7-1  firefox-145.0.1-1'; say ''
say 'Total Download Size:   244.00 MiB'
read -r -p ':: Proceed with installation? [Y/n] ' a
say ':: Retrieving packages...' 1.2
say '(1/3) checking keys in keyring' 0.4; say '(2/3) checking package integrity' 0.4
say ':: Processing package changes...'
say '(1/3) upgrading linux-cachyos' 0.9; say '(2/3) upgrading mesa' 0.9; say '(3/3) upgrading firefox' 0.9
say 'warning: /etc/pacman.conf installed as /etc/pacman.conf.pacnew'
say ':: Running post-transaction hooks...' 0.6
say '(1/2) Updating linux initcpios...' 1; say '(2/2) Install DKMS modules' 1
EOF
    step pacman "bash $fake"
    [ "$aur" = 1 ] && step aur "bash '$here/aur-review.sh' dry $review"
    [ "$flat" = 1 ] && step flatpak "bash -c 'echo \":: flatpak update -y\"; sleep 2; echo \"Updates complete.\"'"
    rm -f "$fake"
else
    # snap-pac takes the before/after snapshots; SNAP_PAC_SKIP turns that off
    [ -n "$held" ] && printf '%sHeld back (not updated): %s%s\n' "$D" "${held//,/, }" "$R"
    ign=""; [ -n "$held" ] && ign=" --ignore $held"
    if [ "$snap" = 1 ]; then step pacman "sudo pacman -Syu$ign"; else step pacman "sudo env SNAP_PAC_SKIP=y pacman -Syu$ign"; fi
    ok=$?
    [ $ok = 0 ] && [ "$aur" = 1 ] && step aur "bash '$here/aur-review.sh' real $review"
    if [ $ok = 0 ] && [ "$flat" = 1 ]; then
        if [ -z "$held" ]; then step flatpak "flatpak update -y"
        else
            # every app with an update except the held ones (nothing left: skipped)
            apps=$(flatpak remote-ls --updates --columns=application 2>/dev/null | grep -vxF -f <(tr ',' '\n' <<< "$held") | tr '\n' ' ')
            [ -n "${apps// /}" ] && step flatpak "flatpak update -y $apps"
        fi
    fi
fi

finish
took=$(( $(date +%s) - start ))
took_s=$(( took / 60 ))m$(( took % 60 ))s; [ $took -lt 60 ] && took_s=${took}s
if [ "${ok:-0}" = 0 ] && ! grep -q '^::tide:: rc [a-z]* [1-9]' "$LOG"; then
    printf '\n%s✓%s %sAll done%s %sin %s%s\n' "$A" "$R" "$B" "$R" "$D" "$took_s" "$R"
else
    printf '\n\e[38;2;255;105;97m✕%s %sSomething didn\x27t finish.%s %sThe output above says what happened.%s\n' "$R" "$B" "$R" "$D" "$R"
fi
read -r -s -n 1 -p "${D}Press any key to close this window.${R}"
