# Fix Local Wayland IPC Permissions

- ID: `T017`
- Type: `bug`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `63818095-e5b3-45dc-a12a-5e755b217428`

## Goal

Allow VS Code and other XDG clients to create private IPC sockets when a locally
opened devcontainer forwards the host Wayland socket through
`/tmp/codegeist-wayland`.

## Context

Local Wayland discovery sets `XDG_RUNTIME_DIR=/tmp/codegeist-wayland` for the
workspace container and bind-mounts only the host Wayland socket beneath that
path. Docker creates the missing parent directory as root, so VS Code's agent
host, which runs as the configured workspace user, fails repeatedly with
`listen EACCES` while creating `vscode-ipc-*.sock`. Remote SSH sessions without a
forwarded Wayland socket do not activate this path.

## Scope

In scope:

- Give the generated Wayland runtime directory workspace-user ownership and mode
  `0700` before VS Code attaches.
- Restrict the ownership change to the kit-generated runtime path selected by
  `DEVCONTAINER_WAYLAND_RUNTIME_DIR` and `XDG_RUNTIME_DIR`.
- Add a real container regression that creates a Unix socket as the workspace
  user in the generated runtime directory.
- Document the runtime-directory ownership contract.

Out of scope:

- Changing host Wayland socket ownership or permissions.
- Mutating arbitrary user-provided XDG runtime directories.
- Adding new X11 or Wayland mounts.
- Changing SSH display-forwarding behavior.

## Acceptance Criteria

- The generated `/tmp/codegeist-wayland` directory is owned by the configured
  container UID/GID with mode `0700` when local Wayland forwarding is active.
- The workspace user can listen on and close a Unix socket beneath that path.
- The host Wayland socket remains mounted and usable at the generated target.
- Startup without local Wayland forwarding remains unchanged.
- Source and release documentation describe the IPC-safe runtime directory.

## Verification

- `bash -n entrypoint.sh tests/compose-config.sh`
- Focused `tests/compose-config.sh` through the shared fixture setup
- `task check`
- `task tests-run`
- `git diff --check`

## File Targets

- `entrypoint.sh`
- `tests/compose-config.sh`
- `README.md`
- `README_release.md`
- `.oc_local/rules/devcontainer-kit.md`
- `docs/tasks/T017_fix_local_wayland_ipc_permissions.md`

## Implementation Notes

- The container entrypoint runs before the VS Code agent attaches and is already
  allowed to use passwordless sudo for required runtime preparation.
- Keep the repair idempotent because `postStartCommand` invokes the same
  entrypoint helper again on later starts.
- Do not remove global Wayland environment values: visible applications and the
  reconnect-aware Chrome launcher still rely on the generated runtime contract.

## Verification Results

- On 2026-09-18, the focused regression reproduced the reported failure as the
  workspace user with `listen EACCES` at
  `/tmp/codegeist-wayland/devcontainer-ipc-test.sock` before the fix.
- The first ownership implementation exposed the `sudo -E` post-start branch,
  which runs the entrypoint as root. The final implementation uses generated
  `DEVCONTAINER_UID` and `DEVCONTAINER_GID`, so both entrypoint invocations keep
  the runtime directory assigned to the workspace user.
- `bash -n entrypoint.sh tests/compose-config.sh` passed.
- The focused Compose fixture passed with the mounted Wayland socket, runtime
  user ownership, mode `0700`, and a real Node Unix socket listen/close cycle.
- `task check` passed, including the release-copy contract test.
- `task tests-run` passed all generic devcontainer kit tests in 149 seconds.
- `git diff --check` passed.

## Cancellation Reason

- `none`
