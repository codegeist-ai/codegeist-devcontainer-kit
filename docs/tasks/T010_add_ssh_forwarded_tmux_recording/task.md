# Add SSH-Forwarded tmux Recording

- ID: `T010`
- Type: `feature`
- Status: `blocked`
- Parent: `none`
- Public Tracking: `pending issue creation`
- Tracking Key: `16e17108-68b7-4927-912a-0a8ffa266d01`

## Goal

Let a Linux user press tmux `Prefix + R` to start or stop recording their local
microphone into a timestamped WAV file under the workspace `.tmp/recordings/`
directory.

## Context

VS Code Remote SSH does not forward microphone audio. The feature therefore
needs a documented local PipeWire-to-SSH path, one small recorder command, and
integration with the existing `oc` tmux and release contracts.

The work is split by responsibility so the SSH prerequisite, recording process,
and shipped tmux integration can be implemented and reviewed independently.
Public tracking remains blocked until the user approves the exact GitHub Issue
previews and Issue creation is verified.

## Scope

In scope:

- Define a secure, manual SSH forwarding contract for a Linux PipeWire client.
- Add one toggle command that records the forwarded microphone with `ffmpeg`.
- Bind the recorder to tmux `Prefix + R` through the existing `oc` wrapper.
- Ship and document the recorder in the generated runtime release.
- Verify each behavior inside the child task that introduces it.

Out of scope:

- Automatic changes to local SSH or remote SSH server configuration.
- New packages, services, Compose configuration, or initialization behavior.
- Non-Linux audio clients, playback, transcription, uploads, or multiple
  simultaneous recordings.
- A separate final verification task.

## Acceptance Criteria

- The local PipeWire Pulse socket can be forwarded to remote loopback port
  `47130` using the documented SSH configuration.
- `cmds/oc-record` safely toggles one mono, 48 kHz WAV recording below
  `.tmp/recordings/`.
- `Prefix + R` invokes the recorder without changing existing `oc` session,
  window, argument-forwarding, or clipboard behavior.
- Missing audio forwarding affects only recorder startup, not the devcontainer
  or ordinary OpenCode use.
- The recorder, documentation, and tests are present in the runtime release.
- Every child task passes its own focused verification before it is solved.

## Child Tasks

- `tasks/T010_01_add_ssh_microphone_forwarding.md` - define and document the
  secure Linux PipeWire SSH forwarding prerequisite.
- `tasks/T010_02_add_microphone_recorder.md` - implement the single-process
  recording toggle and its focused behavior tests.
- `tasks/T010_03_integrate_tmux_recorder.md` - add the tmux shortcut, complete
  runtime packaging and documentation, and verify the shipped integration.

## Verification

- Use the verification section in each child task; do not defer child behavior
  to a standalone verification task.
- After all children are solved, run the repository's final `task check` and
  `task tests-run` commands as part of `T010_03`.

## File Targets

- `tasks/T010_01_add_ssh_microphone_forwarding.md`
- `tasks/T010_02_add_microphone_recorder.md`
- `tasks/T010_03_integrate_tmux_recorder.md`

## Dependencies

- `T010_02` depends on the endpoint contract from `T010_01`.
- `T010_03` depends on the working recorder from `T010_02`.

## Implementation Notes

1. Complete `T010_01`, then `T010_02`, then `T010_03`.
2. Keep the fixed endpoint `tcp:127.0.0.1:47130`, Pulse source `default`, one
   active recording per user, and one fixed tmux shortcut.
3. Do not introduce configuration abstractions or fallback transports without a
   concrete new requirement.
4. Replace every pending `Public Tracking` value with its approved Issue URL
   before implementing that task.

## Cancellation Reason

- `none`
