#!/usr/bin/env bash
# oc-record.sh - verify the recorder against real tmux, FFmpeg, and Pulse
#
# Why this exists:
# - The recorder coordinates real process identity, signals, tmux session state,
#   and WAV finalization; replacing those integrations previously hid inherited
#   tmux-option behavior that failed in a fresh session.
#
# Inputs:
# - OC_RECORD_BIN selects the recorder, defaulting to the source command.
# - OC_RECORD_EXPECT_START_FAILURE=true verifies the real unavailable-forward
#   path. The normal path requires Pulse at tcp:127.0.0.1:47130.
#
# Side effects:
# - Records short microphone samples below a cleanup-trapped test directory.
# - Creates and removes an isolated tmux server without touching user sessions.
#
# Related files:
# - ../cmds/oc-record
# - ../docs/tasks/T010_add_ssh_forwarded_tmux_recording/tasks/T010_02_add_microphone_recorder.md

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

owns_suite=0
if [ -z "${suite_tmp_dir:-}" ]; then
  setup_suite
  owns_suite=1
fi

mode="success"
if [ "${OC_RECORD_EXPECT_START_FAILURE:-false}" = "true" ]; then
  mode="start-failure"
fi

fixture_dir="$suite_tmp_dir/oc-record-$mode"
recorder="${OC_RECORD_BIN:-$project_root/cmds/oc-record}"
socket_name="oc-record-${mode}-$$"
session_name="recorder"
unrelated_pid=""

mkdir -p "$fixture_dir"
tmux -L "$socket_name" new-session -d -s "$session_name" -c "$fixture_dir"
socket_path="$(tmux -L "$socket_name" display-message -p -t "$session_name" '#{socket_path}')"
export TMUX="$socket_path,0,0"
pane="$(tmux display-message -p -t "$session_name" '#{pane_id}')"

cleanup() {
  local output=""
  local pid=""
  local state_file=""

  for state_file in "$fixture_dir"/*/.tmp/recordings/.oc-record.state; do
    [ -f "$state_file" ] || continue
    IFS=$'\t' read -r pid output <"$state_file" || true
    if [[ "$pid" =~ ^[0-9]+$ ]] \
      && grep -Ezxq '(.*/)?ffmpeg' "/proc/$pid/cmdline" 2>/dev/null \
      && grep -Fzxq -- "$output" "/proc/$pid/cmdline" 2>/dev/null; then
      kill -INT "$pid" 2>/dev/null || true
    fi
  done

  if [ -n "$unrelated_pid" ]; then
    kill "$unrelated_pid" 2>/dev/null || true
    wait "$unrelated_pid" 2>/dev/null || true
  fi

  tmux -L "$socket_name" kill-server 2>/dev/null || true

  if [ "$owns_suite" -eq 1 ]; then
    cleanup_suite
  fi
}

trap cleanup EXIT

run_recorder() {
  local workspace="$1"

  DEVCONTAINER_WORKSPACE_FOLDER="$workspace" "$recorder" "$pane"
}

assert_wav_contract() {
  local output="$1"
  local actual=""
  local expected=""

  expected="codec_name=pcm_s16le
sample_rate=48000
channels=1"
  actual="$(ffprobe -v error \
    -select_streams a:0 \
    -show_entries stream=codec_name,sample_rate,channels \
    -of default=noprint_wrappers=1 \
    "$output")"
  [ "$actual" = "$expected" ] \
    || fail "recorded WAV contract mismatch: expected [$expected], actual [$actual]"
}

if [ "$mode" = "start-failure" ]; then
  workspace="$fixture_dir/workspace"
  mkdir -p "$workspace"
  tmux set-option -t "$pane" status-style "bg=blue,fg=white"

  set +e
  run_recorder "$workspace"
  failure_status="$?"
  set -e

  recording_dir="$workspace/.tmp/recordings"
  [ "$failure_status" -ne 0 ] || fail "missing Pulse forward did not fail recorder startup"
  [ ! -e "$recording_dir/.oc-record.state" ] \
    || fail "failed real FFmpeg startup left recorder state"
  [ -z "$(find "$recording_dir" -maxdepth 1 -name '*.wav' -print -quit)" ] \
    || fail "failed real FFmpeg startup left an incomplete WAV file"
  [ "$(tmux show-options -A -t "$pane" -v status-style)" = "bg=blue,fg=white" ] \
    || fail "failed real FFmpeg startup did not restore the tmux status style"
  [ -s "$recording_dir/.oc-record.log" ] \
    || fail "failed real FFmpeg startup did not retain a diagnostic log"

  pass "oc-record reports a real unavailable Pulse forward safely"
  exit 0
fi

# Start and stop record real Pulse audio, expose yellow through real tmux option
# inheritance, and finalize the documented WAV format.
workspace="$fixture_dir/start-stop workspace"
mkdir -p "$workspace"
tmux set-option -u -t "$pane" status-style 2>/dev/null || true
initial_style="$(tmux show-options -A -t "$pane" -v status-style)"
run_recorder "$workspace"

recording_dir="$workspace/.tmp/recordings"
state_file="$recording_dir/.oc-record.state"
IFS=$'\t' read -r recorder_pid output <"$state_file"

[[ "$output" =~ /\.tmp/recordings/[0-9]{8}-[0-9]{6}\.wav$ ]] \
  || fail "recorder output does not use the timestamped workspace WAV path"
kill -0 "$recorder_pid" 2>/dev/null \
  || fail "real FFmpeg recorder did not remain active after startup"
[ "$(tmux show-options -A -t "$pane" -v status-style)" = "bg=yellow,fg=black" ] \
  || fail "recorder did not make the real tmux status bar yellow"

sleep 1
run_recorder "$workspace"

[ ! -e "$state_file" ] || fail "recorder left active state after stopping"
[ "$(tmux show-options -A -t "$pane" -v status-style)" = "$initial_style" ] \
  || fail "recorder did not restore the inherited tmux status style"
[ -s "$output" ] || fail "recorder did not finalize a non-empty WAV file"
assert_wav_contract "$output"

# Concurrent toggles serialize into one real FFmpeg start and one SIGINT stop.
workspace="$fixture_dir/concurrent"
mkdir -p "$workspace"
run_recorder "$workspace" &
first_toggle_pid="$!"
run_recorder "$workspace" &
second_toggle_pid="$!"
wait "$first_toggle_pid"
wait "$second_toggle_pid"

[ ! -e "$workspace/.tmp/recordings/.oc-record.state" ] \
  || fail "concurrent toggles left active recorder state"
mapfile -t concurrent_outputs < <(find "$workspace/.tmp/recordings" -maxdepth 1 -name '*.wav')
[ "${#concurrent_outputs[@]}" -eq 1 ] \
  || fail "concurrent toggles created ${#concurrent_outputs[@]} WAV files instead of one"
assert_wav_contract "${concurrent_outputs[0]}"

# A reused PID that is not real FFmpeg is never signaled; the recovered style
# becomes the base style for the new real recording.
workspace="$fixture_dir/stale-state"
recording_dir="$workspace/.tmp/recordings"
mkdir -p "$recording_dir"
sleep 30 &
unrelated_pid="$!"
printf '%s\t%s\n' "$unrelated_pid" "$recording_dir/stale.wav" \
  >"$recording_dir/.oc-record.state"
printf 'bg=magenta,fg=white\n' >"$recording_dir/.oc-record.status-style"
tmux set-option -t "$pane" status-style "bg=yellow,fg=black"

run_recorder "$workspace"
kill -0 "$unrelated_pid" 2>/dev/null \
  || fail "stale recorder state signaled an unrelated process"
[ "$(tmux show-options -A -t "$pane" -v status-style)" = "bg=yellow,fg=black" ] \
  || fail "recovered recording did not activate the yellow tmux status style"
sleep 1
run_recorder "$workspace"
[ "$(tmux show-options -A -t "$pane" -v status-style)" = "bg=magenta,fg=white" ] \
  || fail "stale recorder state did not recover the saved tmux status style"

pass "oc-record toggles safe real tmux and Pulse WAV recordings"
