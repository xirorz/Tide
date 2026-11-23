#!/usr/bin/env bash
# Restart the Tide shell (SUPER+ALT+B). Matches only the qs process itself.
dir="$(cd "$(dirname "$0")/.." && pwd)"
pkill -f "^(/usr/bin/)?qs -p $dir\$"
sleep 0.5
exec uwsm-app -- qs -p "$dir"
