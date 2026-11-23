#!/usr/bin/env bash
# hypridle → Tide: one idle step (dim | lock | dpms | suspend | resume). Tide decides
# whether an app may hold it off (Settings → Apps and Hyprland → Idle). If Tide isn't
# running to answer, the step happens anyway, so a crash never leaves the PC unlocked.
step="$1"
shell_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(qs -p "$shell_dir" ipc call idle step "$step" 2>/dev/null)" == ok ]]; then exit 0; fi
case "$step" in
    lock) loginctl lock-session ;;
    dpms) hyprctl dispatch 'hl.dsp.dpms({ action = "off" })' ;;
    suspend) systemctl suspend ;;
esac
