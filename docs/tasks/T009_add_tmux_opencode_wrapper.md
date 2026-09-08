# Add tmux OpenCode Wrapper

- ID: `T009`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues/14`
- Tracking Key: `8c07608d-3f7a-41a2-9551-d3bd40e3469f`

## Goal

Provide an `oc` command that starts `opencode --auto -c` in tmux while safely
forwarding any additional OpenCode arguments.

## Context

Long-running interactive OpenCode sessions should survive terminal disconnects
without requiring users to assemble the tmux command manually. The installed
OpenCode CLI supports both `--auto` and `-c`, but the current image does not
include tmux.

A manual `task code-open-test` found that exposing `scripts/oc` only through the
workspace scripts path does not work in normal non-login VS Code terminals. The
command must be installed directly in the image at `/usr/local/bin/oc`.

The wrapper should remain deliberately small. Outside tmux, each invocation
starts and attaches to a new session. Inside tmux, it opens a new window in the
existing session instead of creating a nested session. It does not name, find,
reuse, list, or otherwise manage sessions.

After the first release, restarting OpenCode through `oc` exposed a clipboard
regression: tmux defaults `set-clipboard` to `external`, which rejects OSC 52
clipboard updates sent by applications such as the OpenCode TUI.

## Scope

In scope:

- Install tmux through the existing Debian APT transaction.
- Add an executable runtime wrapper installed globally as `/usr/local/bin/oc`.
- Run `opencode --auto -c` in a new attached tmux session when invoked outside
  tmux.
- Run `opencode --auto -c` in a new tmux window when invoked inside tmux.
- Preserve the invocation working directory and forward all additional
  arguments without losing argument boundaries.
- Add focused wrapper, image, and release-copy coverage.
- Document the command and explicitly note that `--auto` automatically approves
  permissions that are not denied by configuration.

Out of scope:

- Reusing, naming, discovering, listing, or cleaning up tmux sessions.
- Creating nested tmux sessions.
- Replacing or modifying the original `opencode` command.
- Adding configuration files, key bindings, plugins, status bars, or other tmux
  customization.
- Making `--auto` or `-c` optional.
- Publishing the generated `release` branch.

## Acceptance Criteria

- A newly built image provides a working `tmux` command.
- A normal non-login container shell resolves `oc` to `/usr/local/bin/oc`.
- `oc` starts a new attached tmux session when `TMUX` is unset.
- `oc` opens a new window when `TMUX` is set.
- Both paths execute `opencode --auto -c` from the caller's working directory.
- Additional arguments, including values containing spaces, reach OpenCode
  unchanged and after the required options.
- OpenCode's OSC 52 copy action is accepted by tmux and reaches its clipboard
  integration.
- Tests can inspect and stop the created session and window through separate
  tmux client commands.
- The wrapper contains no session lookup, reuse, cleanup, or custom naming
  behavior.
- The runtime release manifest contains the `oc` wrapper.
- Source and release documentation show concise usage and explain the `--auto`
  security implication.
- Existing fast checks and the complete image/runtime suite pass.

## Verification

- Run `git --no-pager diff --check`.
- Run `bash -n cmds/oc tests/opencode-tmux-wrapper.sh`.
- Run `task check`.
- Run the real tmux wrapper test in the built image.
- Run `task tests-run` because the base image and runtime bundle change.

## File Targets

- `Dockerfile.base`
- `cmds/oc`
- `scripts/release-build.sh`
- `tests/opencode-tmux-wrapper.sh`
- `tests/docker-build.sh`
- `tests/devcontainer-up.sh`
- `tests/code-open-test.sh`
- `tests/release-build.sh`
- `Taskfile.yaml`
- `README.md`
- `README_release.md`
- `.oc_local/rules/devcontainer-kit.md`
- `docs/tasks/T009_add_tmux_opencode_wrapper.md`

## Dependencies

- Debian Bookworm's `tmux` package.
- The installed OpenCode CLI with `--auto` and `--continue` support.
- Docker access for image-level verification.

## Implementation Notes

- Keep user-facing container commands under `cmds/` and copy the complete
  directory to `/usr/local/bin` during the image build.
- Use `tmux new-session -c "$PWD"` outside tmux and `tmux new-window -c "$PWD"`
  when `TMUX` is non-empty.
- Pass `opencode --auto -c "$@"` as separate arguments to tmux so no `sh -c` or
  quoting helper is needed.
- Use `exec` for the selected tmux call. Do not add dependency prechecks,
  session names, session lookup, retries, cleanup, or custom diagnostics.
- Set the tmux server's `set-clipboard` option to `on` before OpenCode starts so
  application-originated OSC 52 updates are accepted. This server-wide option
  is required for TUI copy and permits other applications in that server to set
  the outer terminal clipboard.
- Test both branches against an isolated real tmux server in the built image.
  Replace only OpenCode with a recorder so no AI session starts.
- Add `tmux` to the existing APT layer and verify command availability without
  pinning a Debian package version.
- Update the bounded runtime manifest and its exact-tree test together so
  consumers receive `cmds/oc` from the generated release branch.
- Preserve the unrelated existing `.devcontainer` gitlink change.

## Implementation Plan

1. Add Debian's `tmux` package to the existing APT transaction in
   `Dockerfile.base`, then copy all of `.devcontainer/cmds/` to `/usr/local/bin`
   with executable permissions. Extend `tests/docker-build.sh` with `tmux -V`;
   do not add a new install layer, version pin, configuration, or server setup.
2. Add executable `cmds/oc` with the normal script header and
   `set -euo pipefail`. Use one `TMUX` check and these two direct command shapes:

   ```bash
   exec tmux new-window -c "$PWD" opencode --auto -c "$@"
   exec tmux new-session -c "$PWD" opencode --auto -c "$@"
   ```
3. Add `tests/opencode-tmux-wrapper.sh`. Use a short isolated `TMUX_TMPDIR` and
   real tmux client commands to create, inspect, and stop sessions and windows.
   Replace only OpenCode with a recorder and include one argument containing
   spaces to prove that `"$@"` remains intact.
4. Add `cmds/*` to the `task check` syntax command. Run the
   real tmux test from `tests/docker-build.sh`, where the newly built image
   provides tmux and global commands. Make the normal non-login shell checks in
   `tests/devcontainer-up.sh` and `tests/code-open-test.sh` require
   `/usr/local/bin/oc`. No new Taskfile task or shared test helper is needed.
5. Add `cmds/oc` to `scripts/release-build.sh` and both matching lists in
   `tests/release-build.sh`. Update the exact release-tree listing in `README.md`.
   Rely on the existing copy and exact-tree test rather than adding another
   release mechanism.
6. Add a short usage section to `README.md` and `README_release.md` covering
   `oc`, argument forwarding, the new-session/new-window split, and the security
   effect of fixed `--auto`. Add one matching default-toolchain bullet to
   `.oc_local/rules/devcontainer-kit.md`.
7. Run the focused shell checks, `git --no-pager diff --check`, `task check`, and
   `task tests-run`. Keep the existing `.devcontainer` gitlink untouched. After
   verification, close Issue `#14`, verify its canonical link and completed
   state, record the results here, and set this task to `solved`.

## Previous Verification Results

- `bash -n cmds/oc tests/opencode-tmux-wrapper.sh tests/devcontainer-up.sh
  tests/code-open-test.sh` passed.
- `git --no-pager diff --check` and `task check` passed, including the exact
  release tree with `cmds/oc`.
- `task tests-run` passed in 122 seconds after rebuilding the image.
- The image installed `oc` at `/usr/local/bin/oc` with executable permissions.
- Non-login Devcontainer shell coverage resolved `oc` globally, and the wrapper
  test controlled real isolated tmux sessions and windows while preserving an
  argument containing spaces.
- GitHub Issue `#14` was closed with reason `completed`; read-back confirmed its
  closed state, non-pull-request identity, and unique complete canonical task
  linkage.

## Clipboard Regression Verification

- `bash -n cmds/oc tests/opencode-tmux-wrapper.sh`,
  `git --no-pager diff --check`, and `task check` passed.
- A newly built image passed the real tmux integration test for both wrapper
  branches. The simulated OpenCode process sent OSC 52, and tmux exposed the
  decoded `oc clipboard test` value after the wrapper enabled
  `set-clipboard on`.
- `task tests-run` passed in 125 seconds.
- GitHub Issue `#14` was closed again with reason `completed`; read-back
  confirmed its closed state and complete canonical task linkage.

## Open Questions

- `none`

## Cancellation Reason

- `none`
