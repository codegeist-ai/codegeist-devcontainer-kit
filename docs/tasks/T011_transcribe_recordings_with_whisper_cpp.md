# Transcribe Recordings With whisper.cpp

- ID: `T011`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues/17`
- Tracking Key: `cb9d5c52-c613-4ab4-bf58-d4ad575b1c45`

## Goal

Automatically transcribe each finalized tmux microphone recording to a text file
with whisper.cpp before the recorder stop operation completes.

## Context

`T010_02` added the `oc-record` toggle that writes mono, 48 kHz PCM WAV files to
the workspace `.tmp/recordings/` directory. Transcription was intentionally out
of scope for that task.

The devcontainer should install the whisper.cpp CLI but should not embed the
approximately 488 MB multilingual `small` model in the image. The first
transcription in each container may take longer while the model is downloaded.
Model persistence across container restarts is not required: the model belongs
directly under `/tmp` and is downloaded again when absent.

The download path must stay simple. Do not add another lock, state file, cache
manager, daemon, or retry workflow. The existing `oc-record` lock already
serializes recorder stop operations within one workspace. A unique temporary
download file is sufficient to prevent an interrupted transfer from appearing at
the final model path.

## Scope

In scope:

- Build and install a pinned CPU-capable `whisper-cli` release in the
  devcontainer image.
- On recorder stop, check for the multilingual `small` model at a documented
  path below `/tmp`.
- Download the model when it is absent, using a temporary file followed by a
  successful-download rename so an interrupted transfer is not mistaken for a
  usable model.
- Verify the downloaded model against its pinned SHA256 checksum before use.
- Keep model lookup and download inside the existing serialized recorder stop
  path without introducing model-specific locking.
- Run language auto-detection and wait for transcription to finish before the
  recorder stop operation completes.
- Write `<recording-basename>.txt` beside the corresponding WAV file.
- Keep the finalized WAV when model download or transcription fails, report a
  concise tmux error, and retain actionable diagnostics.
- Document the first-use download, network requirement, temporary model path,
  blocking behavior, output path, and failure behavior.

Out of scope:

- Bundling a Whisper model in the image.
- Persisting the model outside `/tmp` or across container restarts.
- A dedicated model-download lock, download state machine, cache configuration,
  daemon, or background worker.
- Background transcription after the recorder stop operation returns.
- Manual model selection, language selection, translation, subtitles,
  diarization, or GPU acceleration.
- Transcribing arbitrary files through a separate user-facing command.

## Acceptance Criteria

- `whisper-cli` is installed in the built image from a pinned whisper.cpp
  release and reports its version successfully.
- The multilingual `small` model path is
  `/tmp/whisper.cpp/ggml-small.bin`.
- When the model exists, transcription uses it without a network request.
- When the model is absent, the stop operation downloads it from a pinned
  source and validates SHA256
  `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b`
  before making it available at the final model path.
- A failed download does not leave the final model path populated and does not
  create a successful transcript.
- No model-specific lock file or persistent download state is introduced.
- A successful stop retains the existing WAV and creates a TXT file with the same
  basename in `.tmp/recordings/`.
- The transcription uses the multilingual model with automatic language
  detection and CPU execution.
- The stop invocation waits for download and transcription, while the existing
  tmux `run-shell -b` binding keeps the tmux client responsive.
- A download or transcription failure returns a non-zero status, preserves the
  finalized WAV, removes an unsuccessful TXT file, restores the prior tmux status
  style, and identifies the diagnostic log to inspect.
- Existing recording startup, process identity validation, `SIGINT`
  finalization, stale-state recovery, and one-recorder-per-workspace behavior
  remain intact.
- Consumer documentation states that `/tmp` model contents can disappear at a
  container restart and the next transcription then downloads the model again.

## Verification

- `bash -n cmds/oc-record tests/oc-record.sh tests/docker-build.sh`
- `task check`
- `tests/docker-build.sh`, including `whisper-cli --version` and the existing
  successful recorder stop extended to require the downloaded model checksum and
  matching TXT path.
- Run the existing real tmux, Pulse, FFmpeg, and `ffprobe` recorder assertions
  together with the automatic transcript assertions.
- `task tests-run`
- `git diff --check`

## File Targets

- `Dockerfile.base`
- `cmds/oc-record`
- `tests/oc-record.sh`
- `tests/docker-build.sh`
- `README.md`
- `README_release.md`
- `docs/tasks/T011_transcribe_recordings_with_whisper_cpp.md`

## Dependencies

- `T010_02` provides the existing recorder stop and workspace-lock behavior.
- Runtime network access to the pinned model source is required when the model
  is absent from `/tmp`.
- Existing image tools include `curl`, `ffmpeg`, tmux, and `flock`.

## Implementation Plan

1. Install the pinned whisper.cpp CLI in `Dockerfile.base`:
   - Add `cmake` to the existing APT toolchain transaction.
   - Add `WHISPER_CPP_VERSION=1.9.4` and source SHA256
     `57e280cee375ab02425b806ad5146b99f6eb9357e3c2b31357c8a6af2e2e44ae`
     as build arguments beside the other pinned external tools.
   - Download the `v1.9.4` source archive from `codeload.github.com`, verify it,
     and configure a Release static build without optional acceleration
     backends.
   - Build `whisper-cli`, install only the executable in `/usr/local/bin`, run
     `whisper-cli --version`, and remove the source archive and build tree in the
     same image layer.
   - Update the Dockerfile header so the new version input, runtime purpose, and
     `cmds/oc-record` relationship are visible without reconstructing the build.

2. Extend the valid recorder-stop branch in `cmds/oc-record` without creating a
   second command:
   - Preserve the existing PID validation, `SIGINT`, bounded wait, state cleanup,
     and status-style restoration through WAV finalization.
   - Replace the immediate saved message and exit with the synchronous
     transcription sequence while continuing to hold the existing workspace
     lock.
   - Keep recording startup and stale-state recovery unchanged.

3. Prepare `/tmp/whisper.cpp/ggml-small.bin` with direct shell operations:
   - Define the pinned Hugging Face revision URL and existing model SHA256 near
     the other transcription constants in `oc-record`.
   - Use `[ -f "$model" ]` as the normal reuse check; do not hash an already
     present model on every transcription.
   - When absent, create `/tmp/whisper.cpp`, announce the first-use download in
     tmux, and use `curl -fL` to download into a unique `mktemp` file in that
     directory.
   - Validate the downloaded file with `sha256sum -c`, then `mv` it to
     `ggml-small.bin`. Remove the process-specific temporary file on every
     failure path.
   - Do not create a model lock or model state file.

4. Transcribe the finalized recording directly:
   - Pass the existing mono, 48 kHz PCM16 WAV to `whisper-cli`; the pinned CLI's
     miniaudio decoder converts input to the required mono 16 kHz float samples,
     so no additional FFmpeg conversion or temporary audio file is needed.
   - Invoke `whisper-cli` with the downloaded model, `--language auto`,
     `--output-txt`, and output prefix `${output%.wav}`. The installed build has
     only the CPU backend, and the TXT writer does not include timestamps, so
     runtime GPU and timestamp switches are unnecessary.
   - Require successful CLI exit and the expected TXT file, clear successful
     diagnostics, and report both saved paths through tmux.

5. Keep failure handling local and observable:
   - Reuse `.tmp/recordings/.oc-record.log` for download and whisper diagnostics
     instead of adding separate logs.
   - On failure, remove the process-specific download file and unsuccessful TXT
     file; retain the finalized recording and diagnostic log.
   - Return non-zero with a concise tmux message naming the retained WAV and log.
   - Keep cleanup directly beside each failure; do not add a cleanup framework.

6. Extend `tests/oc-record.sh` and `tests/docker-build.sh`:
   - Assert the installed CLI version before recorder integration runs.
   - In the existing successful real tmux/Pulse test container, allow the first
     stop to exercise the real model download and require the pinned checksum,
     matching TXT path, preserved WAV, and restored status style.
   - Preserve the current unavailable-Pulse test as a pre-transcription failure
     that neither downloads a model nor creates a transcript.

7. Update `README.md` and `README_release.md` together:
   - Describe that stopping `Prefix + R` waits for transcription while tmux
     remains responsive because the binding itself is backgrounded.
   - Document WAV and TXT naming, the `/tmp/whisper.cpp/ggml-small.bin` path,
     approximately 488 MB first-use download, runtime network requirement, model
     loss at container restart, automatic language detection, and CPU execution.
   - Explain that transcription failure preserves the WAV and points to
     `.oc-record.log`.

8. Run focused syntax and image checks first, then `task check`, the full
   `task tests-run` integration suite, and `git diff --check`. Record concrete
   results in this task only after implementation succeeds.

## Implementation Notes

- The model URL should use Hugging Face repository revision
  `5359861c739e955e79d9a303bcbc70fb988958b1` rather than the mutable `main`
  path.
- In whisper.cpp `v1.9.4`, `read_audio_data` configures miniaudio for mono output
  at `WHISPER_SAMPLE_RATE`; this makes a separate conversion of the recorder's
  valid PCM16 WAV redundant.
- No release manifest entry is needed because `Dockerfile.base` is already
  copied to release `Dockerfile` and `cmds/oc-record` is already an explicit
  runtime file.

## Verification Results

- `bash -n cmds/oc-record tests/oc-record.sh tests/docker-build.sh`: passed.
- `task check`: passed.
- Targeted image build and recorder integration checks passed, including the
  pinned `whisper-cli` version, real model download and checksum, WAV retention,
  TXT creation, and existing tmux/Pulse/FFmpeg behavior.
- `git diff --check`: passed.
- `tests/browser-smoke.sh`: passed when run in isolation.
- Three initial `task tests-run` attempts were blocked by the existing visible
  Chrome Wayland smoke timing out with exit status 124. Each run reached the
  `checking real visible Chrome with invalid X11 and a real Wayland compositor`
  step after the Whisper and recorder checks had passed. The isolated browser
  smoke subsequently passed, identifying the failure as intermittent and
  outside this task's changed files.
- A later `task tests-run` retry passed all generic devcontainer kit tests in
  132 seconds, including the browser smoke and all Whisper recorder coverage.

The implementation and required verification are complete. Linked Issue #17 was
closed with reason `completed` and read back with its canonical task linkage
intact.

## Cancellation Reason

- `none`
