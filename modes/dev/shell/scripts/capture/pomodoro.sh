#!/bin/bash

set -u

WORK_MINUTES=25
BREAK_MINUTES=5
LONG_BREAK_MINUTES=15
POMODOROS_PER_LONG_BREAK=4
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
PID_FILE="$RUNTIME_DIR/tide-pomodoro.pid"

is_running() {
  [[ -r "$PID_FILE" ]] || return 1
  local pid
  read -r pid < "$PID_FILE"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null \
    | grep -Fq "/scripts/capture/pomodoro.sh"
}

if [[ "${1:-}" == "status" ]]; then
  is_running
  exit $?
fi

if is_running; then
  read -r running_pid < "$PID_FILE"
  kill "$running_pid" 2>/dev/null || true
  notify-send "Pomodoro Timer" "Timer stopped" -a "Pomodoro"
  exit 0
fi

printf '%s\n' "$$" > "$PID_FILE"
sleep_pid=""
cleanup() {
  rm -f "$PID_FILE"
}
stop_timer() {
  if [[ -n "$sleep_pid" ]]; then
    kill "$sleep_pid" 2>/dev/null || true
  fi
  exit 0
}
wait_period() {
  sleep "$1" &
  sleep_pid=$!
  wait "$sleep_pid"
  sleep_pid=""
}
trap cleanup EXIT
trap stop_timer INT TERM

# Initialize counters
pomodoro_count=0

# Main loop
while true; do
  # Work period
  notify-send "Pomodoro Timer" "Work time! ($WORK_MINUTES minutes)" -a "Pomodoro"
  wait_period "${WORK_MINUTES}m"

  ((pomodoro_count++))

  if ((pomodoro_count % POMODOROS_PER_LONG_BREAK == 0)); then
    notify-send "Pomodoro Timer" "Great job! Take a long break ($LONG_BREAK_MINUTES minutes)" -a "Pomodoro"
    wait_period "${LONG_BREAK_MINUTES}m"
  else
    notify-send "Pomodoro Timer" "Good work! Take a short break ($BREAK_MINUTES minutes)" -a "Pomodoro"
    wait_period "${BREAK_MINUTES}m"
  fi

done
