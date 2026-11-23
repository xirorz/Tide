#!/usr/bin/env bash
# Wraps the voice scripts (obs-voice, whisper-paste) without changing them and tells
# the island what is happening: recording, transcribing, then done or error.
#   voice.sh <tool> stop          (the island's stop button: never starts one)
#   voice.sh obs-voice toggle      (SUPER+R)
#   voice.sh whisper-paste toggle  (SUPER+SHIFT+R)
shell_dir="$(cd "$(dirname "$0")/.." && pwd)"
tool="${1:-obs-voice}"
action="${2:-toggle}"      # toggle (the keys) | stop (the island's stop button)
case "$tool" in
    obs-voice)     bin="$HOME/.local/bin/obs-voice";     pidf="${XDG_STATE_HOME:-$HOME/.local/state}/obs-voice/rec.pid" ;;
    whisper-paste) bin="$HOME/.local/bin/whisper-paste"; pidf="${XDG_STATE_HOME:-$HOME/.local/state}/whisper-paste/rec.pid" ;;
    *) echo "usage: voice.sh obs-voice|whisper-paste [toggle]" >&2; exit 2 ;;
esac
island() { qs -p "$shell_dir" ipc call voice "$@" >/dev/null 2>&1; }
# what happened, for troubleshooting: ~/.local/state/tide/voice.log
log() { mkdir -p "$HOME/.local/state/tide"; echo "$(date '+%F %T') $tool: $*" >> "$HOME/.local/state/tide/voice.log"; }

# a mode that limits apps can turn dictation off (Settings → Themes); stopping always works
if ! { [[ -f "$pidf" ]] && kill -0 "$(cat "$pidf")" 2>/dev/null; } && [[ "$action" != stop ]] \
   && [[ "$(qs -p "$shell_dir" ipc call session useTool dictation 2>/dev/null)" == false ]]; then
    exit 0
fi

if [[ -f "$pidf" ]] && kill -0 "$(cat "$pidf")" 2>/dev/null; then
    # recording: stopping it runs the transcription inside the script
    island transcribing
    log "stop -> transcribing"
    if "$bin" stop >>"$HOME/.local/state/tide/voice.log" 2>&1; then island done; log "done"; else island error; log "error (exit $?)"; fi
elif [[ "$action" == stop ]]; then
    # nothing is recording: just clear the island
    island cancel
else
    if "$bin" start; then
        island start "$tool"
        log "start"
        # the island shows recording now, so close the script's own overlay
        # (whisper-paste-ui.py) and its mic monitor; the script copes with it gone
        uipid=$(cat "$(dirname "$pidf")/ui.pid" 2>/dev/null)
        if [[ -n "$uipid" ]]; then
            pkill -P "$uipid" 2>/dev/null
            kill "$uipid" 2>/dev/null
        fi
    else
        island error
        log "start failed"
    fi
fi
