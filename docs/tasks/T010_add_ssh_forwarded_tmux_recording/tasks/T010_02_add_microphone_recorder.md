# Add Microphone Recorder

- ID: `T010_02`
- Type: `feature`
- Status: `blocked`
- Parent: `T010` (`docs/tasks/T010_add_ssh_forwarded_tmux_recording/task.md`)
- Public Tracking: `pending issue creation`
- Tracking Key: `8b94f5fb-9c79-418a-8aec-de025a00854b`

## Goal

Add one command that safely toggles recording from the forwarded Pulse endpoint
into a timestamped WAV file below the workspace `.tmp/recordings/` directory.

## Context

`T010_01` defines the fixed Pulse server endpoint as
`tcp:127.0.0.1:47130`. The image already contains Pulse-enabled `ffmpeg`, tmux,
`procps`, and `flock`, and `Dockerfile.base` already copies the complete `cmds/`
directory to `/usr/local/bin`.

The implementation should remain one Bash command with one active recording per
container user. It must not introduce an audio service or configuration layer.

## Scope

In scope:

- Add `cmds/oc-record` as a single toggle command receiving a tmux pane target.
- Resolve the workspace from `DEVCONTAINER_WORKSPACE_FOLDER`, the pane's Git
  root, or the pane directory in that order.
- Record Pulse source `default` as mono, 48 kHz PCM WAV through `ffmpeg`.
- Keep user-scoped temporary PID, output-path, lock, and diagnostic state.
- Validate stale state before sending signals.
- Report start, saved output, and actionable failures through tmux.
- Add deterministic tests using a fake `ffmpeg` process.

Out of scope:

- tmux key registration, which belongs to `T010_03`.
- Audio source selection, configuration flags, or endpoint discovery.
- Multiple simultaneous recordings.
- Audio playback, transcription, conversion, or upload.
- New packages or image layers.

## Acceptance Criteria

- The first invocation starts exactly one background `ffmpeg` process with
  `PULSE_SERVER=tcp:127.0.0.1:47130`.
- The output path matches
  `.tmp/recordings/YYYYMMDD-HHMMSS-NNNNNNNNN.wav` under the resolved workspace.
- `ffmpeg` receives `-f pulse -i default -ac 1 -ar 48000 -c:a pcm_s16le` plus
  non-interactive, concise logging flags.
- A second invocation sends `SIGINT` to the verified recorder so the WAV file is
  finalized.
- Rapid invocations are serialized and cannot start two recorders.
- Incomplete or stale state is removed without signaling an unrelated process.
- Immediate `ffmpeg` failure removes active state and incomplete output and
  displays a concise diagnostic location.
- A stop timeout preserves state for a safe retry and does not escalate to
  `SIGKILL`.
- The behavior is covered without requiring a real microphone or network
  endpoint.

## Verification

- `bash -n cmds/oc-record tests/oc-record.sh tests/docker-build.sh`
- Run `tests/oc-record.sh` in the built image with an isolated tmux server and a
  fake `ffmpeg`.
- Verify start arguments, one output file, `SIGINT` handling, stale state,
  immediate failure cleanup, and repeatability.
- Verify `command -v oc-record` returns `/usr/local/bin/oc-record` in the image.
- Run `tests/docker-build.sh` after the focused behavior passes.

## File Targets

- `cmds/oc-record`
- `tests/oc-record.sh`
- `tests/docker-build.sh`

## Dependencies

- `T010_01` defines the fixed SSH-forwarded Pulse endpoint.
- Existing `ffmpeg`, `tmux`, `procps`, and `flock` commands in the image.

## Implementation Notes

1. Require one pane-target argument and query `#{pane_current_path}` through
   tmux instead of interpolating a path into the binding command.
2. Use a restrictive umask and one user-scoped `flock` around the complete state
   transition.
3. Store only the recorder PID and exact output path. Write state atomically
   after launching `ffmpeg`.
4. Before stopping, require a live PID whose command line identifies both
   `ffmpeg` and the stored output path.
5. Start `ffmpeg` with `-nostdin -hide_banner -loglevel error`; redirect its
   diagnostic stream to the temporary log and perform a short bounded liveness
   check for immediate failures.
6. On stop, send `SIGINT` and wait for a short bounded interval. Remove state
   only after confirmed exit.
7. Keep helper functions limited to repeated messaging, state validation, and
   cleanup behavior within the one script.

## Cancellation Reason

- `none`
