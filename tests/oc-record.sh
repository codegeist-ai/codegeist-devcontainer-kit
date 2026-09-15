#!/usr/bin/env bash
# oc-record.sh - verify the recorder against real tmux, FFmpeg, and Pulse
#
# Why this exists:
# - The recorder coordinates real process identity, signals, tmux session state,
#   and WAV finalization; replacing those integrations previously hid inherited
#   tmux-option behavior that failed in a fresh session.
# - Recorder stop also exercises the real whisper.cpp model download and TXT
#   output contract without introducing a separate transcription test harness.
# - A deterministic Whisper output additionally proves that tmux receives exact
#   transcript bytes without a trailing Enter; real tmux, Pulse, and FFmpeg stay
#   in that insertion path.
#
# Inputs:
# - OC_RECORD_BIN selects the recorder, defaulting to the source command.
# - OC_RECORD_EXPECT_START_FAILURE=true verifies the real unavailable-forward
#   path. The normal path requires Pulse at tcp:127.0.0.1:47130.
# - The suite controls OC_RECORD_LANGUAGE internally so caller configuration
#   cannot change the fallback assertions.
#
# Side effects:
# - Records short microphone samples below a cleanup-trapped test directory.
# - Creates and removes an isolated tmux server without touching user sessions.
#
# Related files:
# - ../cmds/oc-record
# - ../docs/tasks/T010_add_ssh_forwarded_tmux_recording/tasks/T010_02_add_microphone_recorder.md
# - ../docs/tasks/T012_insert_transcript_into_opencode_input.md

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
whisper_model="/tmp/whisper.cpp/ggml-small.bin"
whisper_model_sha256="1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
insertion_text='Review $(literal); keep symbols
and internal lines'
insertion_bracketed_text="$(printf '\033[200~%s\033[201~' "$insertion_text")"

unset OC_RECORD_LANGUAGE OC_RECORD_EXPECT_LANGUAGE

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
  [ ! -e "$whisper_model" ] \
    || fail "failed recorder startup downloaded the Whisper model before transcription"

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
transcript="${output%.wav}.txt"
[ -f "$transcript" ] || fail "recorder stop did not create the matching TXT transcript"
[ -f "$whisper_model" ] || fail "recorder stop did not download the Whisper model"
printf '%s  %s\n' "$whisper_model_sha256" "$whisper_model" | sha256sum -c - >/dev/null \
  || fail "downloaded Whisper model checksum mismatch"

# Use deterministic Whisper output for the pane-input assertion while keeping
# the preceding download and transcription path real. The pane requests
# bracketed paste through a real PTY and captures the exact resulting bytes.
workspace="$fixture_dir/transcript-insertion"
recording_dir="$workspace/.tmp/recordings"
capture_file="$fixture_dir/transcript-pane-input"
expected_capture="$fixture_dir/expected-transcript-pane-input"
fake_bin="$fixture_dir/fake-whisper-bin"
mkdir -p "$workspace" "$fake_bin"

cat >"$fake_bin/whisper-cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output_prefix=""
language=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --language)
      shift
      language="$1"
      ;;
    --output-file)
      shift
      output_prefix="$1"
      ;;
  esac
  shift
done

[ -n "$output_prefix" ]
[ "$language" = "${OC_RECORD_EXPECT_LANGUAGE:-auto}" ]
if [ "${OC_RECORD_FAKE_EMPTY:-false}" = "true" ]; then
  : >"${output_prefix}.txt"
else
  printf 'Review $(literal); keep symbols\nand internal lines\r\n' >"${output_prefix}.txt"
fi
EOF
chmod +x "$fake_bin/whisper-cli"

tmux respawn-pane -k -t "$pane" \
  "printf '\\033[?2004h'; stty raw -echo; dd bs=1 count=${#insertion_bracketed_text} of='$capture_file' status=none; exec sleep 300"
sleep 0.2
OC_RECORD_LANGUAGE=de OC_RECORD_EXPECT_LANGUAGE=de \
  PATH="$fake_bin:$PATH" run_recorder "$workspace"
sleep 1
OC_RECORD_LANGUAGE=de OC_RECORD_EXPECT_LANGUAGE=de \
  PATH="$fake_bin:$PATH" run_recorder "$workspace"

for _ in {1..20}; do
  [ -f "$capture_file" ] && [ "$(wc -c <"$capture_file")" -ge "${#insertion_bracketed_text}" ] \
    && break
  sleep 0.1
done

printf '%s' "$insertion_bracketed_text" >"$expected_capture"
cmp -s "$expected_capture" "$capture_file" \
  || fail "recorder did not bracket-paste the exact transcript without Enter"
insertion_output="$(find "$recording_dir" -maxdepth 1 -name '*.wav' -print -quit)"
[ -s "$insertion_output" ] || fail "transcript insertion did not retain its WAV"
[ -f "${insertion_output%.wav}.txt" ] || fail "transcript insertion did not retain its TXT"

# A successful empty transcript must leave pane input untouched.
workspace="$fixture_dir/empty-transcript"
empty_capture="$fixture_dir/empty-transcript-pane-input"
tmux respawn-pane -k -t "$pane" \
  "printf '\\033[?2004h'; stty raw -echo; cat >'$empty_capture'"
sleep 0.2
OC_RECORD_FAKE_EMPTY=true OC_RECORD_LANGUAGE= OC_RECORD_EXPECT_LANGUAGE=auto \
  PATH="$fake_bin:$PATH" run_recorder "$workspace"
sleep 1
OC_RECORD_FAKE_EMPTY=true OC_RECORD_LANGUAGE= OC_RECORD_EXPECT_LANGUAGE=auto \
  PATH="$fake_bin:$PATH" run_recorder "$workspace"
sleep 0.2
[ ! -s "$empty_capture" ] \
  || fail "empty transcript unexpectedly changed pane input"
tmux respawn-pane -k -t "$pane" 'sleep 300'

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
[ -f "${concurrent_outputs[0]%.wav}.txt" ] \
  || fail "concurrent recorder stop did not create the matching TXT transcript"

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
IFS=$'\t' read -r stale_recorder_pid stale_output \
  <"$workspace/.tmp/recordings/.oc-record.state"
sleep 1
run_recorder "$workspace"
[ "$(tmux show-options -A -t "$pane" -v status-style)" = "bg=magenta,fg=white" ] \
  || fail "stale recorder state did not recover the saved tmux status style"
[ -f "${stale_output%.wav}.txt" ] \
  || fail "recovered recorder stop did not create the matching TXT transcript"

# If the invoking pane disappears during recording, stop still finalizes and
# transcribes before reporting that insertion could not be completed.
workspace="$fixture_dir/missing-pane"
recording_dir="$workspace/.tmp/recordings"
PATH="$fake_bin:$PATH" run_recorder "$workspace"
IFS=$'\t' read -r missing_pane_pid missing_pane_output \
  <"$recording_dir/.oc-record.state"
kill -0 "$missing_pane_pid" 2>/dev/null \
  || fail "missing-pane recorder did not remain active before target removal"
sleep 1
tmux new-window -d -t "$session_name:" 'sleep 300'
tmux kill-pane -t "$pane"

set +e
PATH="$fake_bin:$PATH" run_recorder "$workspace" >/dev/null 2>&1
missing_pane_status="$?"
set -e

[ "$missing_pane_status" -ne 0 ] \
  || fail "missing target pane did not fail transcript insertion"
[ -s "$missing_pane_output" ] \
  || fail "missing target pane did not retain the finalized WAV"
[ -f "${missing_pane_output%.wav}.txt" ] \
  || fail "missing target pane did not retain the completed TXT transcript"
[ -s "$recording_dir/.oc-record.log" ] \
  || fail "missing target pane did not retain insertion diagnostics"

pass "oc-record toggles safe real tmux recordings and inserts TXT transcripts"
