# Remove Microphone Integration

- ID: `T027`
- Type: `refactor`
- Status: `specified`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `00f631fe-9648-4b20-82c0-04cb12e676ab`

## Goal

Remove the shared microphone recording and transcription workflow, including its
OpenCode/tmux shortcuts, recorder command, dedicated dependencies, configuration,
tests, and runtime documentation.

## Context

`cmds/oc` binds tmux Prefix + R and Alt + R to `oc-record`. The recorder captures
SSH-forwarded Pulse audio with FFmpeg, transcribes it with whisper.cpp, and pastes
the transcript into the OpenCode pane. It also manages recording status and
workspace recording files. This integration is no longer required in the shared
kit. Tasks `T010` through `T013` describe its historical implementation.

`T022` separately removes default host networking. A consuming project may opt
into host networking for its own needs, but that overlay must not be documented
as restoring the recorder after this task removes it.

## Scope

In scope:

- Remove `cmds/oc-record` and the recorder bindings from `cmds/oc`.
- Remove recorder-only status handling, transcription, transcript insertion,
  model downloads, and `OC_RECORD_LANGUAGE` configuration.
- Remove the whisper.cpp image build and dedicated build inputs; inspect other
  packages and remove them only when they exist exclusively for this integration.
- Remove recorder installation and packaging references, dedicated tests, and
  suite requirements for SSH microphone forwarding or real audio capture.
- Update source and release READMEs, contributor guidance, examples, and local
  agent guidance to stop advertising the removed workflow or requiring its setup.
- Preserve historical task records; add concise supersession notes where needed
  to distinguish past implementation from the current supported contract.

Out of scope:

- Removing the `oc` command, OpenCode, tmux, or clipboard support.
- Removing FFmpeg or other tools still used for terminal capture, browser tests,
  or other supported workflows.
- Removing visible or headless Chrome or implementing T022's network change.
- Modifying user SSH/PipeWire configuration, stopping user-managed forwards, or
  deleting existing recordings, transcripts, models, profiles, or secret state.
- Editing generated `.devcontainer/` content, publishing releases, or creating
  commits.

## Acceptance Criteria

- New images do not install `oc-record` or the recorder-specific whisper.cpp CLI
  and build inputs.
- `oc` continues to launch OpenCode in tmux inside and outside an existing session
  with argument forwarding and clipboard behavior intact.
- `oc` does not install Prefix + R or Alt + R recorder bindings or recorder status
  behavior. No automatic cleanup of unrelated existing tmux bindings is added.
- No supported entrypoint downloads a transcription model, captures microphone
  audio, or inserts a microphone transcript into OpenCode.
- Active configuration examples no longer expose `OC_RECORD_LANGUAGE`.
- Main tests and release verification do not require a Pulse endpoint, forwarded
  microphone, audio recording, or transcription model download.
- Runtime packaging and fast release-contract tests reflect removal of
  `cmds/oc-record`; shared tools needed elsewhere remain available.
- Current documentation no longer advertises the removed shortcuts, recorder,
  transcription, or microphone forwarding as kit functionality.
- Existing user files and host forwarding configuration remain untouched.

## Verification

- Run shell syntax checks for affected scripts and `task check`.
- Run the existing `oc`/tmux tests after adapting their recorder expectations;
  verify launch behavior inside and outside tmux and argument forwarding.
- Run release-layout checks and inspect staged runtime contents for stale
  `oc-record` installation or packaging references.
- Build the affected image and verify recorder-specific commands are absent and
  shared capture tools remain available.
- Run the updated main test entrypoint without a microphone forward or model
  download; record any unrelated integration prerequisites explicitly.
- Search active source/configuration/docs for stale recorder, whisper.cpp,
  `OC_RECORD_LANGUAGE`, and microphone-prerequisite references, excluding
  intentionally retained historical task context.
- Run `git diff --check`.

## File Targets

- `cmds/oc`
- `cmds/oc-record`
- `Dockerfile.base`
- `.local.env.example`
- `Taskfile.yaml`
- `scripts/release-build.sh` and related release-layout helpers
- `tests/oc-record.sh`, `oc`/tmux tests, image smoke tests, and suite entrypoint
- `tests/release-build.sh`
- `README.md`
- `README_release.md`
- `CONTRIBUTING.md`
- `.oc_local/rules/` where microphone behavior or prerequisites are documented
- Historical task records `T010` through `T013` and related `T022` references

## Dependencies

- No prerequisite implementation of `T022` or `T024` is required.
- Coordinate overlapping test, packaging, and documentation changes with `T022`.

## Implementation Notes

- Inspect package use before removing dependencies: FFmpeg remains part of the
  documented terminal-capture toolchain independently of microphone recording.
- Keep implementation limited to feature removal; do not replace the recorder
  with a new extension framework or another transcription service.

## Cancellation Reason

Not cancelled.
