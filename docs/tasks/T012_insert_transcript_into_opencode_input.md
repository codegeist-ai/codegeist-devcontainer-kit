# Insert Transcript Into OpenCode Input

- ID: `T012`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues/18`
- Tracking Key: `6963fa06-d0b5-42fc-ae1a-5630f5dae877`

## Goal

Insert each successful microphone transcript into the current OpenCode tmux
pane's input without submitting it, so the user can review and edit the text
before sending a prompt.

## Context

`T011` extended `oc-record` so stopping a recording writes a TXT transcript
beside the finalized WAV. The tmux binding already passes the active pane ID to
`oc-record`, which provides the target for inserting that transcript into the
OpenCode terminal.

The insertion must behave like a paste, not like automatic prompt submission.
The user explicitly selected insertion without Enter so generated text remains
reviewable before OpenCode processes it.

## Scope

In scope:

- Insert a successful, non-empty transcript into the pane that invoked the stop
  operation.
- Preserve internal line breaks and text content while removing trailing line
  endings that could act as unintended submission input.
- Use tmux buffer operations so transcript contents are not evaluated as shell
  syntax or interpolated into a tmux command.
- Keep the WAV and TXT outputs unchanged and available after insertion.
- Report an actionable pane message and non-zero result when insertion fails,
  while retaining the completed recording and transcript.
- Extend the existing recorder integration test with deterministic transcript
  content and a real isolated tmux pane.
- Document the insertion and no-auto-submit behavior in source and consumer
  documentation.

Out of scope:

- Automatically pressing Enter or submitting the transcript to OpenCode.
- Deleting the WAV or TXT after insertion.
- Selecting another pane, session, or OpenCode instance.
- Clipboard integration, transcript editing, prompt templates, or command
  interpretation.
- A second recorder command or a parallel fake contract test.

## Acceptance Criteria

- A successful non-empty transcription is pasted into the tmux pane passed to
  `oc-record` when the stop operation is invoked.
- The pasted text is not automatically submitted and remains available for user
  review and editing.
- Trailing CR/LF characters are removed before insertion; internal line breaks
  and other transcript characters remain intact.
- Transcript text is handled as data and is not evaluated by Bash or tmux.
- An empty successful transcript leaves the pane input unchanged.
- A missing or invalid pane causes a concise failure after transcription without
  removing the finalized WAV or TXT.
- Existing recording, process validation, status restoration, model download,
  transcription, and diagnostics behavior remains intact.
- Tests exercise known transcript text through the existing real tmux recorder
  integration and verify insertion without Enter.
- `README.md` and `README_release.md` describe that the transcript is inserted
  but not submitted.

## Verification

- `bash -n cmds/oc-record tests/oc-record.sh`
- `task check`
- `tests/oc-record.sh`
- `task tests-run`
- `git diff --check`

## File Targets

- `cmds/oc-record`
- `tests/oc-record.sh`
- `README.md`
- `README_release.md`
- `docs/tasks/T012_insert_transcript_into_opencode_input.md`

## Implementation Notes

- Treat the pane argument supplied by the second `Prefix + R` invocation as the
  current insertion target.
- `oc-record` strips trailing CR/LF characters from the completed TXT in memory,
  stores non-empty text in a process-specific tmux buffer, and uses
  `paste-buffer -p -r -d -b <buffer> -t "$pane"` so an OpenCode pane that
  enabled bracketed paste receives internal LF characters as pasted text. It
  never invokes `send-keys Enter`.
- Pane messages fall back to stderr when the target disappears. A failed paste
  removes its named buffer, returns non-zero, and retains WAV, TXT, and the
  diagnostic log.
- `tests/oc-record.sh` retains the real Whisper model and transcription path,
  then uses deterministic Whisper output in additional real tmux, Pulse, and
  FFmpeg cycles to assert exact insertion, empty output, and a missing pane.

## Verification Results

- `bash -n cmds/oc-record tests/oc-record.sh` passed on 2026-09-14.
- `tests/oc-record.sh` passed on 2026-09-14.
- `task check` passed on 2026-09-14.
- `task tests-run` passed on 2026-09-14, including the real recorder,
  devcontainer, browser, QEMU, and submodule integration paths.
- `git diff --check` passed on 2026-09-14.
- GitHub Issue `#18` was read back as closed with reason `completed`; its
  canonical task path and unique Tracking Key match this task.

## Cancellation Reason

- `none`
