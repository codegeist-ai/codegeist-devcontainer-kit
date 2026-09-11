# Integrate tmux Recorder

- ID: `T010_03`
- Type: `feature`
- Status: `blocked`
- Parent: `T010` (`docs/tasks/T010_add_ssh_forwarded_tmux_recording/task.md`)
- Public Tracking: `pending issue creation`
- Tracking Key: `9a51fbcd-dd93-46bd-beeb-b726ba5a8719`

## Goal

Expose the microphone recorder through tmux `Prefix + R` and ship the complete
feature in the generated devcontainer runtime release.

## Context

The existing `oc` wrapper configures the tmux server's clipboard option before
creating a new session or window. `T010_02` adds the globally installed
`oc-record` command. This task adds one binding to the same existing wrapper and
updates only the release, integration tests, and remaining usage documentation
needed to ship it.

## Scope

In scope:

- Register `Prefix + R` in both branches of `cmds/oc`.
- Pass only the active tmux pane ID to `oc-record`.
- Preserve current OpenCode arguments, working directory, session/window, and
  OSC 52 clipboard behavior.
- Extend the real tmux wrapper test to verify the binding.
- Add `cmds/oc-record` to the exact runtime release manifest and release test.
- Complete consumer documentation for the shortcut, output, errors, and manual
  end-to-end check.
- Run final repository verification as part of this integration task.

Out of scope:

- Changing the recorder state machine from `T010_02`.
- Adding configurable tmux keys, session management, or a tmux configuration
  file.
- Adding a separate verification task.
- Publishing a release branch unless separately requested after implementation.

## Acceptance Criteria

- Outside tmux, `oc` starts its session with `Prefix + R` bound to
  `oc-record "#{pane_id}"`.
- Inside tmux, `oc` installs the same binding before opening its new window.
- The binding uses background `run-shell` so recording startup and shutdown do
  not block normal tmux interaction.
- Existing wrapper tests continue to prove argument boundaries, working
  directory, window count, and `set-clipboard on` behavior.
- The release branch tree contains both `cmds/oc` and `cmds/oc-record` and no
  unintended source-only files.
- Consumer documentation explains `Ctrl+B`, uppercase `R`, the output path, and
  expected behavior when the SSH forward is unavailable.
- `task check` and `task tests-run` pass with all child behavior included.

## Verification

- `bash -n cmds/oc tests/opencode-tmux-wrapper.sh tests/release-build.sh
  scripts/release-build.sh`
- Run `tests/opencode-tmux-wrapper.sh` against the built image and verify the
  binding in both outside- and inside-tmux cases.
- Run `tests/release-build.sh` and inspect its exact expected runtime tree.
- Run `git diff --check`.
- Run `task check`.
- Run `task tests-run`.
- With `T010_01` configured, press `Prefix + R`, record briefly, stop with the
  same shortcut, and inspect the WAV with `ffprobe`.
- Repeat without the SSH forward and confirm only recorder startup fails.

## File Targets

- `cmds/oc`
- `tests/opencode-tmux-wrapper.sh`
- `scripts/release-build.sh`
- `tests/release-build.sh`
- `README.md`
- `README_release.md`
- `.oc_local/rules/devcontainer-kit.md`

## Dependencies

- `T010_01` provides the documented SSH forwarding prerequisite.
- `T010_02` provides the tested `oc-record` command.

## Implementation Notes

1. Update the `cmds/oc` contract header and register the binding on the same
   tmux server already receiving `set-clipboard on`.
2. Use `run-shell -b 'oc-record "#{pane_id}"'`; do not pass pane paths through a
   shell command string.
3. Extend `tests/opencode-tmux-wrapper.sh` rather than adding another tmux
   integration fixture.
4. Add `cmds/oc-record` next to `cmds/oc` in `scripts/release-build.sh`, the
   release fixture source list, and the exact expected runtime tree.
5. Keep `Dockerfile.base` unchanged because it already copies all of `cmds/`
   with executable permissions.
6. Add shortcut and recording usage beside `OpenCode In tmux` in both READMEs;
   reuse the forwarding prerequisite written by `T010_01` rather than
   duplicating it.
7. Update the local kit rule with the shipped shortcut, single-recorder, and
   `.tmp` output contract while preserving the forwarding constraints from
   `T010_01`.

## Cancellation Reason

- `none`
