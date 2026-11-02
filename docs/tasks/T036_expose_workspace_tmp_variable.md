# Expose Workspace Temporary Directory Variable

- ID: `T036`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `e84c24d5-ce22-4b8f-93b2-2edc35fab995`

## Goal

Expose one container-wide variable for the existing workspace temporary directory:

```bash
DEVCONTAINER_WORKSPACE_TMP="$DEVCONTAINER_WORKSPACE_FOLDER/.tmp"
```

Use this variable wherever kit scripts currently construct that path.

## Context

`initialize.sh` already prepares `.tmp`. This task only names that existing
location; it does not add storage management.

## Scope

1. Set the resolved `<workspace>/.tmp` value through the existing generated
   environment/Compose configuration and the direct `docker-run` task.
2. Replace repeated path construction in container-side scripts with direct
   reads of `DEVCONTAINER_WORKSPACE_TMP`.
3. Adjust existing test fixtures and assertions, then document the variable and
   one shell example in `README.md` and `README_release.md`. Explain that existing
   containers need recreation to receive the new environment variable.

Keep this to direct configuration and variable substitutions. Add no helpers,
wrappers, hooks, services, configuration options, or fallback discovery.
Changes to `TMPDIR`, storage creation, retention, cleanup, permissions, and
release publication are out of scope.

## Acceptance Criteria

- The variable contains the absolute workspace path followed by `/.tmp`, retaining
  the workspace-facing path rather than resolving the symlink to `/tmp/ws-data`.
- Compose/Dev Containers and `docker-run` supply it container-wide, including
  terminals, `docker exec`, `devcontainer exec`, and `oc` children.
- Linked worktrees and test fixtures receive their own workspace value. Repeated
  initialization preserves existing `.tmp` directories or symlinks.
- Shell logs, HTTP proxy state/logs, and recordings use the variable at their
  existing locations and permissions.
- Source and release documentation explain the value, disposable-storage
  contract, usage, and recreation requirement.

## Verification

- Add small assertions to existing initialization, Compose, container-exec,
  worktree, and `docker-run` tests. Reuse their fixtures and repeated-start checks.
- Supply the new variable in affected consumer fixtures and run their existing
  tests. Do not create another test suite or test framework.
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

- None.

## Implementation Notes

Set the variable when the container is created: an entrypoint-only export does
not reach later `docker exec` processes. Edit the source checkout and use the
existing workspace path directly.

## Implementation And Verification Results

Completed on 2026-11-01:

- The generated environment, Compose mapping, and direct `docker-run` task supply
  the workspace-facing `.tmp` path. Shell logging, proxy state/logging, and
  recording consume it directly; `oc` explicitly passes it to new tmux panes.
- The initializer assertion failed before implementation because the new variable
  was missing, then passed. Existing fixtures cover linked worktrees, repeated
  initialization, and preservation of both real `.tmp` directories and symlinks.
- `tests/initialize.sh`, `tests/opencode-bash.sh`, and `task check`: passed.
- `task tests-run`: passed in 97 seconds, including stale parent-variable
  isolation, Docker and Dev Containers exec, direct Docker startup, worktrees,
  real tmux/HTTP/shell consumers, recorder missing-transport handling, and existing
  browser and KVM regressions.
- The suite's advisory image scan recorded 535 HIGH and 25 CRITICAL findings in
  `.tmp/image-cve-scan/report.json`; the scanner completed successfully.
- `git --no-pager diff --check`: passed. Source and release documentation explain
  usage and the rebuild/recreation needed to update existing containers.

## Cancellation Reason

Not cancelled.
