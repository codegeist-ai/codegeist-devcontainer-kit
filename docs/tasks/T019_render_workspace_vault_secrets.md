# Render Workspace Vault Secrets

- ID: `T019`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `6b5afe05-1df0-4089-8ba8-eb5c0003b9b7`

## Goal

Render optional workspace secrets with Vault Agent when the devcontainer starts
and always provide `/run/secrets` as an in-memory filesystem.

## Scope

In scope:

- Add `/run/secrets` as a `tmpfs` mount for the workspace service in
  `docker-compose.yml`.
- In `entrypoint.sh`, check for `secrets.hcl` at the selected workspace root.
- When the file exists, run `vault agent` with that file as its configuration
  before starting the requested container command.
- Continue normally when `secrets.hcl` is absent.
- Let the existing shell failure behavior propagate Vault Agent failures.

Out of scope:

- Parsing or validating `secrets.hcl`.
- Enforcing template destinations or requiring `/run/secrets` as a destination.
- Generating, copying, or modifying Vault configuration.
- Changes to `initialize.sh`.
- Host-side secret directories, random paths, or bind mounts.

## Acceptance Criteria

- The workspace service always mounts a `tmpfs` at `/run/secrets`.
- A workspace-root `secrets.hcl` is passed to `vault agent` during entrypoint
  startup.
- A missing `secrets.hcl` does not change normal container startup.
- `secrets.hcl` remains solely responsible for Vault behavior and render
  destinations.
- A failing Vault Agent invocation prevents the requested container command from
  starting.

## Verification

- `bash -n entrypoint.sh`
- Resolve the Compose configuration and confirm `/run/secrets` is a `tmpfs`.
- Run focused entrypoint checks with and without a workspace-root `secrets.hcl`.

## File Targets

- `entrypoint.sh`
- `docker-compose.yml`
- `tests/entrypoint-vault.sh`
- `tests/run.sh`
- `tests/dockerfile-merge.sh`
- `README.md`
- `README_release.md`
- `docs/tasks/T019_render_workspace_vault_secrets.md`

## Dependencies

- Vault CLI is already installed in the devcontainer image.

## Implementation Notes

- Keep the entrypoint branch to one file-existence check and one Vault Agent
  invocation.
- Use the selected workspace path from `DEVCONTAINER_WORKSPACE_FOLDER`.
- Do not add lifecycle management, cleanup logic, destination checks, or fallback
  paths.

## Verification Results

- `bash -n entrypoint.sh tests/dockerfile-merge.sh tests/entrypoint-vault.sh`
  passed.
- `tests/dockerfile-merge.sh` passed and confirmed that Compose resolves
  `/run/secrets` as a `tmpfs`.
- `tests/entrypoint-vault.sh` passed directly against the source entrypoint and
  real local Vault CLI, confirming that a malformed workspace `secrets.hcl`
  prevents the requested command from running without using a test image.
- `task docker-build` passed after workspace storage was restored and produced
  `codegeist-devcontainer-kit:local` with the current source entrypoint.
- `tests/docker-run.sh` passed against the freshly built image.
- `task check` passed, including the release-copy contract test.
- `git diff --check` passed.

## Cancellation Reason

- `none`
