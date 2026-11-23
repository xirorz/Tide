#!/usr/bin/env bash
# Record the screen with gpu-screen-recorder, same settings as Ax-Shell's screenrecord.sh.
#   record.sh region | window | screen <monitor>
# Tells the island when recording starts and ends (the red recording pill).

shell_dir="$(cd "$(dirname "$0")/.." && pwd)"
save_dir="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
mkdir -p "$save_dir"

case "$1" in
    region)
        geo=$(slurp -f "%wx%h+%x+%y") || exit 0
        target=(-w "$geo")
        ;;
    window)
        geo=$(hyprctl activewindow -j | python3 -c 'import json,sys; w=json.load(sys.stdin); print("%dx%d+%d+%d" % (w["size"][0], w["size"][1], w["at"][0], w["at"][1]))') || exit 0
        target=(-w "$geo")
        ;;
    screen)
        target=(-w "${2:-screen}")
        ;;
    *)
        echo "usage: record.sh region | window | screen <monitor>" >&2
        exit 1
        ;;
esac

out="$save_dir/$(date +%Y-%m-%d-%H-%M-%S).mp4"
qs -p "$shell_dir" ipc call recording start
gpu-screen-recorder "${target[@]}" -q ultra -a default_output -ac opus -cr full -f 60 -o "$out"
qs -p "$shell_dir" ipc call recording stopped
