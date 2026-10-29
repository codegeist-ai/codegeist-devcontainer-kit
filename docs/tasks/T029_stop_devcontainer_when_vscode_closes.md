# Stop Devcontainers When VS Code Closes

- ID: `T029`
- Type: `fix`
- Status: `specified`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `e85dc218-ed44-4a79-a94b-bfec1fb121c6`

## Goal

Stop the workspace's Compose services when its VS Code Dev Containers window
closes normally, so workspace processes do not keep running unattended.

## Context

The workspace uses `sleep infinity` and runs independently of the editor.
Dev Containers must explicitly stop it when the window closes. The current
`devcontainer.json` omits `shutdownAction`; the Dev Container specification
already defaults to `stopCompose` for Compose projects. Making the value explicit
documents intent but does not by itself prove the observed shutdown works.

Use the standard lifecycle mechanism and verify the real VS Code/Remote SSH
workflow. Stopped containers may remain listed in `docker ps -a`; deletion is
not required. The CLI reality-test fixture intentionally remains available and
does not establish editor-window shutdown behavior.

## Scope

- Set `"shutdownAction": "stopCompose"` in source `devcontainer.json`.
- Document normal window-close behavior and its limits in source and release
  guides.
- Verify a real window close stops the associated Compose services. Investigate
  the Dev Containers log if it does not, rather than assuming the explicit value
  fixed the behavior.

Out of scope: crash/network-disconnect guarantees, watchdogs, custom shutdown
daemons, deleting containers or data, stopping unrelated projects, changing
reality-test retention, and publishing a release.

## Acceptance Criteria

- Source configuration explicitly selects `stopCompose` and ships unchanged
  through the existing runtime packaging.
- Closing the final VS Code Dev Containers window attached to a test workspace
  normally stops its Compose services; no workspace processes remain running in
  that stopped container. Unrelated projects remain available.
- The task records the observed host-side container state after closing the
  window. A CLI startup test alone is not accepted as shutdown verification.
- Documentation distinguishes normal close from crashes or lost SSH connections
  and stopping from deletion, without claiming guaranteed shutdown on disconnect.
- If shutdown still fails, retain the concrete diagnostic and leave the task
  open or blocked until the normal-close behavior is resolved.

## File Targets

- `devcontainer.json`
- `README.md`
- `README_release.md`
- Existing configuration tests only if they already cover lifecycle settings

## Dependencies

- A real VS Code Dev Containers/Remote SSH session and a separate SSH-host
  terminal for observing the stopped container.

## Verification

- Run `task check` and `git diff --check`.
- Open a disposable consuming workspace in VS Code using the updated runtime
  configuration; record its container ID on the Docker host.
- Close its final attached VS Code window normally. In the separate host
  terminal, inspect that ID and confirm it is no longer running.
- If it stays running, inspect the Dev Containers log for the stop request and
  failure before choosing any further change.

## Implementation Notes

- Change the source configuration, not the consumed `.devcontainer/` submodule.
- Keep this a small configuration and real-workflow verification task; no new
  automated editor-control test framework is needed.

## Cancellation Reason

Not cancelled.
