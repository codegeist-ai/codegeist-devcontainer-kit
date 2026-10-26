# Forward Vault Environment To Devcontainer

- ID: `T026`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `70441449-00c5-4e69-906d-ae02862fdd7a`

## Goal

Forward the optional host environment variables `VAULT_ADDR` and `VAULT_TOKEN`
to this repository's workspace container through its project Compose overlay.

## Context

The variables are already set outside the devcontainer. They must reach the
Docker Compose process launched by VS Code Remote SSH before container creation.
The project overlay `.codegeist/compose.local.yml` is copied by initialization
to `.devcontainer/compose.user.gen.yml` for Compose to load.

Use the project overlay so forwarding applies only to this repository. Both
variables are optional and may be empty. The intended token variable name is
`VAULT_TOKEN`; `VAUTL_TOKEN` in the discussion was a typo.

## Scope

In scope:

- Add the two optional environment mappings to the `workspace` service in
  `.codegeist/compose.local.yml`.
- Update the overlay header to describe its inputs and recreation requirement.
- Record verification results in this task.

Out of scope:

- Shared `docker-compose.yml`, initializer, entrypoint, or release changes.
- Forwarding `GH_TOKEN`, `GITEA_SERVER_TOKEN`, or additional host variables.
- Creating `secrets.hcl`, authenticating to Vault, or rendering secrets.
- SSH configuration, CA installation, or changes to `.codegeist/.local.env`.

## Acceptance Criteria

- Non-empty `VAULT_ADDR` and `VAULT_TOKEN` values from the Compose process
  environment are passed unchanged to the workspace container.
- Each missing or explicitly empty variable resolves to an empty string without
  a missing-variable warning or a startup requirement introduced by this change.
- Only the project overlay opts into these mappings; shared kit defaults remain
  unchanged.
- Tracked configuration contains variable references rather than actual values.
  Verification does not print real tokens or write them to repository files.
- The overlay documents that the variables must be available to the host Compose
  process and that an existing container must be recreated to receive changes.

## Implementation Plan

1. Replace `services: {}` in the project overlay with the mappings below and
   update its header comments.
2. Verify Compose resolution with non-secret test inputs and empty/unset inputs.
3. Run `task check`, review the diff, and record the results in this task.

## Verification

- Resolve the Compose configuration with the project overlay and harmless dummy
  values for both variables; assert exact resolved values without printing the
  full configuration.
- Repeat with both variables unset, both explicitly empty, and each variable
  independently absent. Assert empty-string fallbacks and successful resolution.
  Isolate these checks from local env files that could supply fallback values.
- Use only dummy credentials for these checks; no Vault request is needed.
- `task check`
- `git --no-pager diff --check`

## File Targets

- `.codegeist/compose.local.yml`
- `docs/tasks/T026_forward_vault_environment_to_devcontainer.md`

## Dependencies

- The VS Code Remote SSH/Compose process must inherit the host variables for
  non-empty forwarding. A variable set only in an unrelated terminal is not
  sufficient.

## Implementation Notes

The project overlay uses optional Compose interpolation:

```yaml
services:
  workspace:
    environment:
      VAULT_ADDR: ${VAULT_ADDR:-}
      VAULT_TOKEN: ${VAULT_TOKEN:-}
```

Keep the placeholders in the overlay; Compose resolves them at runtime. Do not
edit generated `.devcontainer/compose.user.gen.yml` manually. Recreate the
container after initialization refreshes that bridge to apply the environment.
Preserve the existing unrelated `.devcontainer` gitlink change.

## Verification Results

- Docker Compose v5.6.1 resolved `.devcontainer/docker-compose.yml` together with
  the project overlay for five cases: both variables set, both unset, both empty,
  only the address unset, and only the token unset. All passed without warnings.
- Checks used a restricted process environment, `--env-file /dev/null`, an
  isolated project directory, and `config --no-env-resolution --format json` to
  avoid loading local env files. Only dummy values were supplied. Assertions
  accounted for Compose escaping literal dollar signs as `$$` in config output.
- `TMPDIR="$PWD/.tmp" task check` passed shell syntax, runtime-release contract,
  and runtime worktree task checks.
- `git --no-pager diff --check` passed.

## Cancellation Reason

- `none`
