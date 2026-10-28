# Log OpenCode Shell Starts

- ID: `T028`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `dcc83d04-bfd0-4f2c-9af2-df5d402ecba8`

## Goal

Always log shell-start metadata and full arguments for OpenCode launched through `oc`, using the
existing Bash and an intentionally small wrapper.

## Scope

- Install `scripts/opencode-bash.sh` as `/usr/local/lib/oc-shell/bash`.
- Set `SHELL` to that wrapper in both `oc` tmux launch paths.
- Append timestamp, PID, parent PID, working directory, and full shell arguments to the workspace's
  existing `.tmp/opencode-shell.log`; abort if logging fails.
- Restore `SHELL=/bin/bash` and `exec /bin/bash "$@"` after logging.
- Include the script in runtime packaging, tests, and consumer documentation.

Out of scope: daemon control, cgroups, per-child-process tracing, command/output
capture beyond the supplied shell arguments, log rotation, direct `opencode`
launches, and release publication.

## Acceptance Criteria

- Every wrapper invocation appends one metadata record; no activation flag exists.
- New logs are owner-only without changing the executed command's umask.
- Bash receives unchanged arguments; stdout, stderr, exit status, and PID survive
  the handoff. Logging errors prevent the command from executing.
- Both existing tmux paths select the wrapper without changing argument handling.
- The runtime tree and built image include the executable wrapper.

## File Targets

- `scripts/opencode-bash.sh`, `cmds/oc`, `Dockerfile.base`
- `scripts/stage-runtime-tree.sh`, `tests/release-build.sh`
- `tests/opencode-bash.sh`, `tests/opencode-tmux-wrapper.sh`, `tests/docker-build.sh`
- `README.md`, `README_release.md`

## Dependencies

- None. The initializer already provides workspace `.tmp/`.

## Verification

- Run the focused wrapper test and real tmux wrapper integration.
- Run `task check` and `task tests-run` for image/lifecycle integration.
- Run `git diff --check` and record results here.

## Implementation Notes

- Keep the installed basename `bash`: OpenCode selects Bash-specific invocation
  behavior from the basename. Log full arguments with Bash `%q` quoting on one
  line; they include supplied commands and may contain sensitive values. Do not
  capture process environment or output.

## Cancellation Reason

Not cancelled.

## Verification Results

- `bash tests/opencode-bash.sh`: passed metadata append, argument boundaries,
  PID handoff, stdout/stderr, exit status, log permissions, unchanged umask, and
  rejection before command side effects when logging fails.
- `task check`: passed shell syntax, exact runtime packaging, and worktree tests.
- `task tests-run`: all integrations passed in 508 seconds on 2026-10-28,
  including image installation, both real tmux paths, and the installed-wrapper
  test. No real OpenCode model request was needed for these contract checks.
- `git diff --check`: passed.
- Simplified the image checks to run tmux and shell-wrapper tests in one
  container. Wrapper tests now execute the file directly, covering executable
  permissions and its shebang. Both tests passed in the existing image after
  this change; `task check` passed again.
- No release was published and the running workspace installation was not changed.
- Follow-up: added full shell arguments in `argv` using Bash quoting. Focused
  tests passed for argument boundaries and single-line encoding of multiline
  commands; `task check` and `git diff --check` passed again. Earlier image/full
  suite results precede this argument-logging extension.
