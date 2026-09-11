# Add Microphone Recorder

- ID: `T010_02`
- Type: `feature`
- Status: `solved`
- Parent: `T010` (`docs/tasks/T010_add_ssh_forwarded_tmux_recording/task.md`)
- Public Tracking: `https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues/16`
- Tracking Key: `8b94f5fb-9c79-418a-8aec-de025a00854b`

## Goal

Add one command and tmux `Prefix + R` shortcut that safely toggle recording from
the forwarded Pulse endpoint into a timestamped WAV file below the workspace
`.tmp/recordings/` directory.

## Context

`T010_01` defines the fixed Pulse server endpoint as
`tcp:127.0.0.1:47130`. The image already contains Pulse-enabled `ffmpeg`, tmux,
`procps`, and `flock`, and `Dockerfile.base` already copies the complete `cmds/`
directory to `/usr/local/bin`.

The implementation should remain one small Bash command with one active
recording per workspace. It must not introduce an audio service, daemon,
configuration layer, or recording modes.

## Scope

In scope:

- Add `cmds/oc-record` as a single toggle command receiving a tmux pane target.
- Use `DEVCONTAINER_WORKSPACE_FOLDER` directly as the output workspace.
- Record Pulse source `default` as mono, 48 kHz PCM WAV through `ffmpeg`.
- Keep one state file, lock file, and diagnostic log in `.tmp/recordings/`.
- Validate stale state before sending signals.
- Report only start, saved output, and concise failures through tmux.
- Add deterministic tests using a fake `ffmpeg` process.
- Register tmux `Prefix + R` through the existing `oc` wrapper.
- Add the recorder to the exact runtime release manifest.
- Document the shortcut, output, and unavailable-forward behavior.
- Preserve existing `oc` arguments, working directory, session, window, and
  clipboard behavior.

Out of scope:

- Audio source selection, configuration flags, or endpoint discovery.
- Multiple simultaneous recordings in one workspace.
- Audio playback, transcription, conversion, or upload.
- New packages or image layers.
- Configurable tmux keys, a tmux configuration file, or another wrapper layer.

## Acceptance Criteria

- The first invocation starts exactly one background `ffmpeg` process with
  `PULSE_SERVER=tcp:127.0.0.1:47130`.
- The output path matches `.tmp/recordings/YYYYMMDD-HHMMSS.wav` under the
  resolved workspace.
- `ffmpeg` receives `-f pulse -i default -ac 1 -ar 48000 -c:a pcm_s16le` plus
  non-interactive, concise logging flags.
- A second invocation sends `SIGINT` to the verified recorder so the WAV file is
  finalized.
- A workspace-local lock prevents rapid invocations from starting two
  recorders.
- Incomplete or stale state is removed without signaling an unrelated process.
- Immediate `ffmpeg` failure removes active state and incomplete output and
  displays a concise error.
- Stop sends only `SIGINT`, waits briefly for WAV finalization, and never
  escalates to `SIGKILL`.
- Outside and inside tmux, `oc` binds `Prefix + R` to background execution of
  `oc-record "#{pane_id}"`.
- Existing `oc` argument, working-directory, session, window, and clipboard
  behavior remains unchanged.
- The exact runtime release contains both `cmds/oc` and `cmds/oc-record`.
- Consumer documentation explains `Ctrl+B`, uppercase `R`, the output path, and
  the missing-forward failure boundary.
- The behavior is covered without requiring a real microphone or network
  endpoint.

## Verification

- `bash -n cmds/oc-record tests/oc-record.sh tests/docker-build.sh`
- Run `tests/oc-record.sh` in the built image with fake `ffmpeg` and a tmux
  message sink.
- Verify start arguments and output, `SIGINT` handling, duplicate-start
  prevention, and stale-state safety.
- Verify `command -v oc-record` returns `/usr/local/bin/oc-record` in the image.
- Run `tests/docker-build.sh` after the focused behavior passes.
- Run `tests/opencode-tmux-wrapper.sh` against the built image and verify the
  binding in both wrapper branches.
- Run `tests/release-build.sh`, `git diff --check`, `task check`, and
  `task tests-run`.
- With the SSH forward active, record through the shortcut and inspect the WAV
  with `ffprobe`.

## File Targets

- `cmds/oc-record`
- `cmds/oc`
- `tests/oc-record.sh`
- `tests/opencode-tmux-wrapper.sh`
- `tests/docker-build.sh`
- `scripts/release-build.sh`
- `tests/release-build.sh`
- `README.md`
- `README_release.md`
- `.oc_local/rules/devcontainer-kit.md`

## Dependencies

- `T010_01` defines the fixed SSH-forwarded Pulse endpoint.
- Existing `ffmpeg`, `tmux`, `procps`, and `flock` commands in the image.

## Implementation Notes

1. Require one pane-target argument only for tmux messages. Use
   `DEVCONTAINER_WORKSPACE_FOLDER` directly for paths; the devcontainer runtime
   guarantees it.
2. Create `.tmp/recordings/` below the resolved workspace with a restrictive
   umask. Keep `.oc-record.state`, `.oc-record.lock`, and `.oc-record.log` there.
3. Hold one `flock` across each start or stop transition. Store only the
   recorder PID and exact output path in the state file; the lock serializes
   access and stale or partial state is safe to discard.
4. Before stopping, require a live PID whose command line identifies both
   `ffmpeg` and the stored output path.
5. Start `ffmpeg` with `-nostdin -hide_banner -loglevel error`; redirect its
   diagnostic stream to `.oc-record.log` and perform one short liveness check.
6. On stop, send `SIGINT` and wait briefly for exit before reporting the saved
   path. Preserve state when the process does not exit; do not use `SIGKILL`.
7. Keep the script direct. Add helper functions only for repeated tmux messages
   or state validation.
8. Invoke `ffmpeg`, `tmux`, `flock`, and other commands installed by
   `Dockerfile.base` directly. Verify their presence in image tests rather than
   adding runtime availability checks.
9. Register `run-shell -b 'oc-record "#{pane_id}"'` on key `R` in both `oc`
   wrapper branches. Do not add `.tmux.conf` or configurable key behavior.
10. Add `cmds/oc-record` beside `cmds/oc` in the release source and expected
    runtime lists. Keep `Dockerfile.base` unchanged because it already copies
    the complete `cmds/` directory.

## Verification Results

- `task check` passed, including the exact runtime release-tree fixture.
- `tests/oc-record.sh` passed against the source command and the globally
  installed command in the built image.
- The built-image tmux test passed for `Prefix + R` in both `oc` wrapper paths
  while preserving argument, window, session, and clipboard behavior.
- A real forwarded microphone recording was finalized and identified by
  `ffprobe` as mono, 48 kHz `pcm_s16le` audio.
- `task tests-run` passed. An initial unrelated visible-browser timeout was
  followed by successful isolated browser verification and a successful full
  suite rerun.
- GitHub Issue `#16` was closed with reason `completed` and its canonical task
  linkage was verified after closure.

## Cancellation Reason

- `none`
