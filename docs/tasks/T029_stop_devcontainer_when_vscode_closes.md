# Stop Devcontainers When VS Code Closes

- ID: `T029`
- Type: `fix`
- Status: `blocked`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `e85dc218-ed44-4a79-a94b-bfec1fb121c6`

## Goal

Stop the workspace's Compose services when its VS Code Dev Containers window
closes normally, so workspace processes do not keep running unattended.

## Context

The workspace uses `sleep infinity` and runs independently of the editor.
Dev Containers must explicitly stop it when the window closes. Previously,
`devcontainer.json` omitted `shutdownAction`; the Dev Container specification
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

## Implementation And Verification Results

- Source `devcontainer.json` now explicitly selects `stopCompose`. Source and
  consumer documentation describe normal-close behavior and its limits.
- The consumed `.devcontainer/` submodule was not edited for this task.
- `jq -e '.shutdownAction == "stopCompose"' devcontainer.json`: passed.
- `task check`: passed, including runtime release packaging.
- `task tests-run`: passed in 504 seconds on 2026-10-29, including the CVE scan
  and existing lifecycle integrations. These CLI checks do not prove editor-close
  shutdown behavior.
- `git diff --check`: passed.
- The user tested normal window closure after restarting with the published
  setting and reported that the container did not stop. This acceptance check
  failed; the task is blocked pending a verified shutdown-monitor fix or an
  explicitly accepted workaround.

### Failed Close Investigation

- Source and consumed `.devcontainer/devcontainer.json` both contain
  `shutdownAction: stopCompose`; adding the setting did not resolve the behavior.
- Container-local VS Code server logs show a disconnected management connection
  waiting for reconnection. This does not establish why the shutdown failed:
  the extension's shutdown-monitor log is not available inside this container.
- Upstream has matching open issues:
  - https://github.com/microsoft/vscode-remote-release/issues/8818
    (`stopCompose` over Remote SSH).
  - https://github.com/microsoft/vscode-remote-release/issues/6056
    (containers remain running after a Remote SSH editor window closes).
  - https://github.com/microsoft/vscode-remote-release/issues/8991
    (reports include shutdown monitors invoking Docker on the wrong machine or
    failing to find it). These are possible causes, not a confirmed diagnosis
    of this checkout.
- The user supplied a shutdown-monitor excerpt starting at 23:35 on 2026-10-29.
  Its configuration selects `stopCompose`; subsequent records through 23:45 are
  empty message arrays. The excerpt contains no cleanup request, cleanup start,
  Docker stop attempt, or error. It therefore does not demonstrate a Docker
  command failure or establish the wrong-machine failure reported upstream.
- The monitor start coincides with a new container-side editor connection;
  correlate the monitor with the window that was actually closed. The supplied
  excerpt may belong to the reopened session rather than the failed close.
- A subsequent excerpt from the preceding session establishes the failure:
  cleanup was received at 23:34:36, followed by the configured ten-second delay.
  At 23:34:46 the initial container-shell probe failed with
  `Shell server failed: Error: spawn docker ENOENT`. No Compose stop command
  was reached. This is a process-spawn failure, not a Docker socket permission
  denial or a failed Compose stop operation.
- ENOENT can mean the Docker executable is unavailable in the monitor's execution
  environment, or that its configured working directory does not exist there.
  Remote SSH reports in issue 8991 include the same signature. The provided
  excerpt alone does not identify which machine ran the monitor.
- Remaining evidence: correlate the shutdown-monitor process location and the
  installed local/remote extension versions with the path failure below. Do not
  install a local daemon or change the Docker endpoint speculatively: official Remote SSH usage
  does not require a local Docker client.
- The laptop resolves `docker` to `/usr/bin/docker`; absence of a local CLI is
  ruled out by the user's successful `docker --version` (29.9.1). The user also
  confirmed the configured remote repository cwd does not exist on the laptop.
  A Node child-process probe with a known executable and nonexistent cwd reproduced
  ENOENT, strongly supporting a local monitor receiving a remote cwd.
- Inspected the published Dev Containers 0.471.0 package in disposable storage
  without installing or patching it. The extension declares UI execution; its
  shutdown monitor constructs a local child-process executor from the supplied
  cwd and spawns Docker with that cwd. No documented remote-shutdown-location
  switch was found in the contributed settings. This supports the execution-
  context diagnosis; the user's installed extension version is not yet recorded.
- There is no verified repo-local fix at this point. Creating the remote path
  on the laptop, selecting `/usr/bin/docker`, or merely pointing a local CLI at
  a different daemon does not establish correct remote cwd/Compose-file handling.
  Preserve the supported configuration and do not introduce these speculative
  workarounds as a fix.
- Official workflow reference:
  https://code.visualstudio.com/remote/advancedcontainers/develop-remote-host
- Capture only operation/error lines and version/path information. Do not copy
  configuration messages with full environment or credentials.
- No watchdog, forced process termination, or host workaround has been added.
  A custom shutdown mechanism remains outside the accepted scope until the
  exact failure is established and any scope change is accepted.

### Manual Close Check

Use a consuming test checkout with the changed `devcontainer.json` and open it
through VS Code Dev Containers. In a separate terminal on its Docker host:

```bash
docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}'
docker inspect --format '{{.State.Running}} {{.State.Status}}' <container-id>
```

Record the ID before closing the final attached test window, then repeat the
inspect command after normal closure. Expect `false exited`. If VS Code removes
the container instead, record that outcome and verify its absence. Do not close
the active implementation session as an automated test or claim that manually
running `docker stop` verifies the editor lifecycle.
