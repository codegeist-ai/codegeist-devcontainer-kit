# Configure Whisper Transcription Language

- ID: `T013`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues/19`
- Tracking Key: `791d8a22-d76d-4dc5-b1f1-9f35a03aa972`

## Goal

Allow users to select the spoken language passed to `whisper-cli` through an
optional devcontainer environment variable, while preserving automatic language
detection when the variable is absent.

## Context

`cmds/oc-record` currently invokes `whisper-cli --language auto`. Explicitly
selecting a known language can avoid detection errors, especially for short
recordings. The language choice is user- and workspace-specific, so it belongs
in the ignored `.codegeist/.local.env` file rather than a checked-in default.

The user requested environment-variable support only and will set the desired
value in their own local env file. This task must not edit or commit that file.

## Scope

In scope:

- Read `OC_RECORD_LANGUAGE` in `cmds/oc-record`.
- Default to `auto` when `OC_RECORD_LANGUAGE` is unset or empty.
- Pass the selected value to `whisper-cli --language` without evaluating it as
  shell syntax.
- Test both the default value and an explicit value such as `de` through the
  existing recorder integration path.
- Document the variable in `.local.env.example`, `README.md`, and
  `README_release.md`.
- Explain that `.codegeist/.local.env` is read by Compose when the container is
  created, so an existing container must be recreated to receive a changed
  value.

Out of scope:

- Editing or committing a user's `.codegeist/.local.env` file.
- Hard-coding German or another language as the shared default.
- Automatically detecting locale settings or translating transcripts.
- Adding language validation or maintaining a separate language-code list.
- Changing the Whisper model, audio capture format, microphone gain, or tmux
  shortcuts.

## Acceptance Criteria

- `OC_RECORD_LANGUAGE=de` causes `oc-record` to invoke
  `whisper-cli --language de`.
- An unset or empty `OC_RECORD_LANGUAGE` continues to invoke
  `whisper-cli --language auto`.
- The value remains one argument and is not interpreted by Bash.
- Existing recording, transcription, transcript insertion, and failure behavior
  remains unchanged.
- The existing real recorder integration verifies the language argument without
  introducing a parallel fake contract test.
- Source and consumer documentation describe the optional variable, its `auto`
  fallback, and the required container recreation after changing the local env
  file.

## Verification

- `bash -n cmds/oc-record tests/oc-record.sh`
- `tests/oc-record.sh`
- `task check`
- `task tests-run`
- `git diff --check`

## File Targets

- `cmds/oc-record`
- `tests/oc-record.sh`
- `.local.env.example`
- `README.md`
- `README_release.md`
- `docs/tasks/T013_configure_whisper_transcription_language.md`

## Implementation Notes

- Resolve the language once with `language="${OC_RECORD_LANGUAGE:-auto}"` and
  pass it through the existing quoted `whisper-cli` argument list.
- Extend the deterministic Whisper helper in `tests/oc-record.sh` to capture or
  assert the argument used by the recorder. Keep the existing real Pulse,
  FFmpeg, tmux, and Whisper paths intact.

## Implementation Plan

1. Validate the stored GitHub Issue linkage before changing runtime files.
2. Resolve `OC_RECORD_LANGUAGE` once in `cmds/oc-record`, defaulting an unset or
   empty value to `auto`, and pass the result as one quoted `--language`
   argument.
3. Isolate `tests/oc-record.sh` from a caller-provided language, then extend its
   existing deterministic Whisper helper to assert both the `auto` fallback and
   an explicit `de` value without adding another test harness.
4. Add a commented `OC_RECORD_LANGUAGE=de` example to `.local.env.example` and
   document the variable, fallback, and container-recreation requirement in
   `README.md` and `README_release.md`.
5. Run the listed syntax, recorder, fast-contract, full integration, and diff
   checks.
6. After successful verification, close Issue `#19` as completed, verify its
   canonical linkage, record verification results here, and set this task to
   `solved`.

## Verification Results

- `bash -n cmds/oc-record tests/oc-record.sh` passed.
- `tests/oc-record.sh` passed against real tmux, Pulse, FFmpeg, and the existing
  real and deterministic Whisper paths.
- The deterministic Whisper path verified explicit `de`, empty-to-`auto`, and
  unset-to-`auto` language selection without changing transcript behavior.
- `task check` passed.
- `task tests-run` passed all generic devcontainer kit tests.
- `git diff --check` passed.
- GitHub Issue `#19` was closed with reason `completed`; read-back confirmed the
  sole Tracking Key match and complete canonical linkage.

## Cancellation Reason

- `none`
