# Expose Workspace Temporary Directory Variable

- ID: `T036`
- Type: `feature`
- Status: `specified`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `e84c24d5-ce22-4b8f-93b2-2edc35fab995`

## Goal

Expose a shared runtime environment variable for the opened workspace's
temporary directory:

```bash
DEVCONTAINER_WORKSPACE_TMP="$DEVCONTAINER_WORKSPACE_FOLDER/.tmp"
```

Scripts and user commands should consume this value instead of repeatedly
constructing the workspace `.tmp` path themselves.

## Context

`initialize.sh` already prepares `.tmp`, normally a symlink to `/tmp/ws-data`,
and preserves any existing `.tmp` path. Several container-side commands construct
`$DEVCONTAINER_WORKSPACE_FOLDER/.tmp` independently for logs, recordings, and
proxy state. The new variable should expose that existing location consistently.

## Scope

- Derive and supply `DEVCONTAINER_WORKSPACE_TMP` through the existing generated
  environment/Compose contract and the repository's direct `docker-run` task.
- Make it container-wide, including terminals, `docker exec`,
  `devcontainer exec`, and commands started through `oc`.
- Use the workspace-facing absolute path ending in `/.tmp`, not the resolved
  symlink target `/tmp/ws-data` or a literal unexpanded variable expression.
- Update kit-owned container-side consumers to use the variable directly for
  workspace temporary files, preserving their existing paths and permissions.
- Update relevant fixtures, tests, source documentation, and the release guide.

Out of scope: changing `TMPDIR`, relocating or cleaning existing data, changing
`.tmp` creation or retention, adding per-command fallback discovery, and release
publication.

## Acceptance Criteria

- In normal container execution, `DEVCONTAINER_WORKSPACE_TMP` equals the actual
  value of `DEVCONTAINER_WORKSPACE_FOLDER` followed by `/.tmp`.
- Both Compose/Dev Containers and the direct `docker-run` task supply it to the
  container environment, rather than only exporting it in an entrypoint shell.
- A directly opened linked worktree receives its own checkout's `.tmp` path;
  inherited parent-workspace variables do not leak into test fixtures.
- Repeated initialization keeps the value correct and preserves existing `.tmp`
  directories or symlinks. No additional temporary directory is introduced.
- Shell logs, HTTP proxy state/logs, and recordings use the shared variable.
  Their externally visible locations and access permissions remain correct.
- Documentation names the variable, its value, its disposable-storage contract,
  and a short example of using it from a shell.

## Verification

- Check generated/resolved runtime configuration and read the actual variable
  through `docker exec` and `devcontainer exec`.
- Cover ordinary checkouts, directly opened linked worktrees, repeated
  initialization, and the direct `docker-run` task.
- Run affected consumer tests with explicit fixture values for the new variable.
- Run `task check`, `task tests-run`, and `git --no-pager diff --check`.

## File Targets

- `initialize.sh`, `docker-compose.yml`, `Taskfile.yaml`
- `entrypoint.sh`, `cmds/oc`, `cmds/oc-record`
- `scripts/opencode-bash.sh`, `scripts/opencode-http-log.py`
- `tests/initialize.sh`, `tests/compose-config.sh`, `tests/helpers.sh`
- `tests/devcontainer-up.sh`, `tests/devcontainer-worktree-up.sh`, and affected
  Docker/runtime consumer fixtures
- `README.md`, `README_release.md`

## Dependencies

- No mandatory dependency. Coordinate overlapping entrypoint edits with
  [T035](T035_minimize_container_entrypoint.md) while keeping startup minimal.

## Implementation Notes

Derive the value in the normal runtime configuration instead of adding another
initialization hook or wrapper. Dockerfile build-time environment expansion and
entrypoint-only exports do not establish this value for later `docker exec`
processes. Keep host-side workspace discovery separate from container consumers.
Implement in the source checkout, not the consumed `.devcontainer/` submodule.

## Cancellation Reason

Not cancelled.
