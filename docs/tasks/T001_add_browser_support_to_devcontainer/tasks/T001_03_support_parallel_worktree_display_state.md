# Support Parallel Worktree Display State

- ID: `T001_03`
- Type: `feature`
- Status: `open`
- Parent: `T001`
- Source Reference: `docs/tasks/T001_add_browser_support_to_devcontainer/task.md`

## Goal

Make visible browser support robust when multiple Codegeist devcontainers run in
parallel from worktrees on the same host, including separate SSH X11 forwarding
display values per VS Code or Dev Containers CLI instance.

## Context

The current display propagation fix captures the host-side `DISPLAY` seen by
`initializeCommand` as `DEVCONTAINER_DISPLAY` and passes that generated value
into the container as `DISPLAY`. This avoids stale display inheritance from later
VS Code or Docker Compose processes.

That behavior is appropriate when each devcontainer instance has isolated
generated files, for example when VS Code opens the selected worktree directly.
It is not sufficient for multiple parallel VS Code sessions that open the same
repository root with different `BRANCH` values, because those sessions still
share root-side generated files under `.devcontainer/`.

The kit should not reserve or increment X11 ports itself. SSH and VS Code own the
forwarding listener allocation; this task is about preserving the display value
that belongs to each devcontainer/worktree instance.

## Scope

In scope:

- Define the supported parallel worktree contract for visible browser sessions.
- Verify that directly opened worktrees keep independent generated display state.
- Decide whether root plus different `BRANCH` values should be supported in
  parallel or explicitly documented as unsupported.
- If supporting root plus parallel `BRANCH`, introduce branch-scoped generated
  files for `.env` and Compose overlays.
- Ensure Compose project naming does not collide across parallel branch
  workspaces.
- Add tests that simulate two branch workspaces with different `DISPLAY` values.
- Update source and release documentation.

Out of scope:

- Implementing VNC, noVNC, or a remote desktop layer.
- Reserving or incrementing X11 ports manually in `initialize.sh`.
- Managing SSH X11 listener allocation inside the shared kit.
- Adding project-specific browser profiles, credentials, bookmarks, or service
  URLs.

## Acceptance Criteria

- Two worktree devcontainer starts can run in parallel without overwriting each
  other's generated display state.
- A test proves branch workspace A receives one generated `DISPLAY` value and
  branch workspace B receives a different generated `DISPLAY` value.
- Existing root, current-branch alias, and worktree startup flows still pass.
- Documentation explains the recommended workflow for parallel browser sessions.
- Documentation clearly states any unsupported workflow, especially multiple
  root-opened VS Code sessions sharing the same `.devcontainer/.env`.

## Verification

- `bash -n initialize.sh tests/*.sh`
- `git --no-pager diff --check`
- Targeted worktree display-state tests.
- `task tests-run`

## File Targets

- `initialize.sh`
- `docker-compose.yml`
- `devcontainer.json`
- `tests/initialize.sh`
- `tests/worktree.sh`
- `tests/devcontainer-current-branch-up.sh`
- `README.md`
- `README_release.md`
- `docs/memory-bank/chat.md`

## Dependencies

- `T001_02`
- Current `DEVCONTAINER_DISPLAY` behavior from `initialize.sh` and
  `docker-compose.yml`.

## Implementation Notes

- Implemented reconnect-safe runtime state: `initialize.sh` now atomically writes
  `.devcontainer/.env` and `.devcontainer/.Xauthority.gen` into the selected
  worktree as well as the root Compose input when `BRANCH` selects a worktree.
- Implemented launcher-time recovery: `scripts/chrome.sh` rereads the selected
  workspace state on every launch, probes SSH-loopback X11 with `xdpyinfo`, and
  normalizes only the requested display's `/unix:N` Xauthority cookie before
  Chrome starts, so another parallel SSH session is never selected as fallback.
- Implemented deterministic smoke coverage in `tests/chrome-launcher.sh`: two
  workspace launchers run in parallel with distinct displays, authority files,
  profiles, and capture files; separate cases cover successful reconnect
  recovery and rejection before `google-chrome` starts.
- Implemented host Wayland discovery and a generated one-socket Compose mount.
  A socket that appears after container creation still requires recreation
  because Docker cannot add a new bind mount to an existing container.
- Remaining scope: simultaneous first-time root starts with different `BRANCH`
  values still share root-side Compose input files during container creation.
  Existing containers use their selected worktree state and are isolated for
  subsequent Chrome launches and SSH reconnects.
- Preferred minimal approach: keep the recommended parallel workflow as
  selecting or preparing the worktree, then opening the worktree path directly in
  VS Code. Add tests proving this direct-worktree path keeps
  `DEVCONTAINER_DISPLAY` isolated per worktree.
- Larger optional approach: generate branch-scoped files under a path such as
  `.devcontainer/generated/<branch-id>/`, make Dev Containers load those
  branch-specific `.env` and Compose files, and ensure the Compose project name
  is branch-specific.
- If branch-scoped generated files are not implemented, document root plus
  multiple parallel `BRANCH` sessions as unsafe because they share root-side
  generated files.

## Cancellation Reason

- `none`
