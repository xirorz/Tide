#!/usr/bin/env bash
# Thumbnails for the wallpaper picker: ~/.cache/tide/wallthumbs/<md5 of file name>.png
# Images are scaled to 480px wide; videos get a frame from 1s in. Existing thumbnails are kept.
dir="${1:-$HOME/wallpapers}"
out="$HOME/.cache/tide/wallthumbs"
mkdir -p "$out"
for f in "$dir"/*; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f")
    h=$(printf "%s" "$name" | md5sum | cut -d' ' -f1)
    t="$out/$h.png"
    [[ -s "$t" ]] && continue
    case "${name,,}" in
        *.mp4|*.webm|*.mkv|*.mov) ffmpeg -loglevel error -y -ss 1 -i "$f" -frames:v 1 -vf scale=480:-1 "$t" 2>/dev/null || ffmpeg -loglevel error -y -ss 1 -i "$f" -frames:v 1 -vf "setparams=colorspace=bt709:color_trc=bt709:color_primaries=bt709,scale=480:-1" "$t" ;;
        *) magick "$f[0]" -thumbnail 480x "$t" 2>/dev/null ;;
    esac
done
echo done
