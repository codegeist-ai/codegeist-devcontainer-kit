#!/usr/bin/env bash
# oc-record.sh - verify the recorder toggle without a real microphone endpoint
#
# Why this exists:
# - A fake FFmpeg process makes start, SIGINT stop, locking, and stale-state
#   behavior deterministic while preserving the real command-line contract.
#
# Inputs:
# - OC_RECORD_BIN selects the recorder, defaulting to the source command.
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

fixture_dir="$suite_tmp_dir/oc-record"
fake_bin="$fixture_dir/bin"
capture_file="$fixture_dir/ffmpeg.capture"
expected_file="$fixture_dir/ffmpeg.expected"
message_file="$fixture_dir/tmux.messages"
signal_file="$fixture_dir/ffmpeg.signals"
pid_file="$fixture_dir/ffmpeg.pids"
recorder="${OC_RECORD_BIN:-$project_root/cmds/oc-record}"
unrelated_pid=""

mkdir -p "$fake_bin"

cat >"$fake_bin/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${!#}" >>"$TMUX_MESSAGE_FILE"
EOF

cat >"$fake_bin/ffmpeg" <<'EOF'
#!/usr/bin/env python3
import os
from pathlib import Path
import signal
import sys
import time

output = Path(sys.argv[-1])
capture = Path(os.environ["FAKE_FFMPEG_CAPTURE"])
capture.write_text(
    f'PULSE_SERVER={os.environ["PULSE_SERVER"]}\n'
    + "".join(f"ARG={argument}\n" for argument in sys.argv[1:])
)
output.touch()

if os.environ.get("FAKE_FFMPEG_FAIL") == "1":
    raise SystemExit(23)

with Path(os.environ["FAKE_FFMPEG_PIDS"]).open("a") as stream:
    stream.write(f"{os.getpid()}\n")


def stop_recording(_signal, _frame):
    with Path(os.environ["FAKE_FFMPEG_SIGNAL"]).open("a") as stream:
        stream.write(f"{os.getpid()}\n")
    with output.open("a") as stream:
        stream.write("finalized\n")
    raise SystemExit(0)


signal.signal(signal.SIGINT, stop_recording)
while True:
    time.sleep(0.1)
EOF

chmod +x "$fake_bin/tmux" "$fake_bin/ffmpeg"

run_recorder() {
  local workspace="$1"
  shift

  DEVCONTAINER_WORKSPACE_FOLDER="$workspace" \
    PATH="$fake_bin:$PATH" \
    TMUX_MESSAGE_FILE="$message_file" \
    FAKE_FFMPEG_CAPTURE="$capture_file" \
    FAKE_FFMPEG_SIGNAL="$signal_file" \
    FAKE_FFMPEG_PIDS="$pid_file" \
    "$@" "$recorder" '%1'
}

cleanup() {
  local pid=""

  if [ -f "$pid_file" ]; then
    while IFS= read -r pid; do
      kill -KILL "$pid" 2>/dev/null || true
    done <"$pid_file"
  fi

  if [ -n "$unrelated_pid" ]; then
    kill "$unrelated_pid" 2>/dev/null || true
    wait "$unrelated_pid" 2>/dev/null || true
  fi

  if [ "$owns_suite" -eq 1 ]; then
    cleanup_suite
  fi
}

trap cleanup EXIT

# Start and stop use the exact Pulse/FFmpeg contract and finalize one WAV file.
workspace="$fixture_dir/start-stop workspace"
mkdir -p "$workspace"
run_recorder "$workspace" env

recording_dir="$workspace/.tmp/recordings"
state_file="$recording_dir/.oc-record.state"
IFS=$'\t' read -r recorder_pid output <"$state_file"

[[ "$output" =~ /\.tmp/recordings/[0-9]{8}-[0-9]{6}\.wav$ ]] \
  || fail "recorder output does not use the timestamped workspace WAV path"
kill -0 "$recorder_pid" 2>/dev/null \
  || fail "recorder process did not remain active after startup"

{
  printf 'PULSE_SERVER=tcp:127.0.0.1:47130\n'
  printf 'ARG=%s\n' \
    -nostdin -hide_banner -loglevel error \
    -f pulse -i default \
    -ac 1 -ar 48000 -c:a pcm_s16le \
    "$output"
} >"$expected_file"

diff -u "$expected_file" "$capture_file" \
  || fail "recorder did not preserve the FFmpeg invocation contract"
grep -F "Microphone recording started: $output" "$message_file" >/dev/null \
  || fail "recorder did not report the started output"

run_recorder "$workspace" env
[ ! -e "$state_file" ] || fail "recorder left active state after stopping"
[ -s "$signal_file" ] || fail "recorder did not stop FFmpeg with SIGINT"
grep -Fx "finalized" "$output" >/dev/null \
  || fail "recorder reported success before the WAV was finalized"
grep -F "Microphone recording saved: $output" "$message_file" >/dev/null \
  || fail "recorder did not report the saved output"

# Concurrent toggles serialize into one start and one stop, never two recorders.
workspace="$fixture_dir/concurrent"
mkdir -p "$workspace"
: >"$capture_file"
: >"$signal_file"
run_recorder "$workspace" env &
first_toggle_pid="$!"
run_recorder "$workspace" env &
second_toggle_pid="$!"
wait "$first_toggle_pid"
wait "$second_toggle_pid"

[ "$(grep -c '^PULSE_SERVER=' "$capture_file")" -eq 1 ] \
  || fail "concurrent toggles started more than one FFmpeg process"
[ ! -e "$workspace/.tmp/recordings/.oc-record.state" ] \
  || fail "concurrent start and stop left active state"
[ "$(find "$workspace/.tmp/recordings" -maxdepth 1 -name '*.wav' | wc -l)" -eq 1 ] \
  || fail "concurrent toggles created more than one WAV file"

# A reused PID that does not identify FFmpeg is discarded without being signaled.
workspace="$fixture_dir/stale-state"
recording_dir="$workspace/.tmp/recordings"
mkdir -p "$recording_dir"
sleep 30 &
unrelated_pid="$!"
printf '%s\t%s\n' "$unrelated_pid" "$recording_dir/stale.wav" \
  >"$recording_dir/.oc-record.state"

run_recorder "$workspace" env
kill -0 "$unrelated_pid" 2>/dev/null \
  || fail "stale recorder state signaled an unrelated process"
run_recorder "$workspace" env

# Immediate FFmpeg failure removes incomplete output and active state.
workspace="$fixture_dir/start-failure"
mkdir -p "$workspace"
set +e
run_recorder "$workspace" env FAKE_FFMPEG_FAIL=1
failure_status="$?"
set -e

[ "$failure_status" -ne 0 ] || fail "immediate FFmpeg failure returned success"
[ ! -e "$workspace/.tmp/recordings/.oc-record.state" ] \
  || fail "immediate FFmpeg failure left active state"
[ -z "$(find "$workspace/.tmp/recordings" -maxdepth 1 -name '*.wav' -print -quit)" ] \
  || fail "immediate FFmpeg failure left an incomplete WAV file"
grep -F "Microphone recording failed; check" "$message_file" >/dev/null \
  || fail "immediate FFmpeg failure did not report its diagnostic log"

pass "oc-record toggles one safe workspace WAV recording"
