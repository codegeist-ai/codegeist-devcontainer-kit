# Remove Default Host Gateway Alias

- ID: `T033`
- Type: `chore`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `40b66f79-56e9-497f-a4ad-ca47de1142e4`

## Goal

Remove the unused default `host.docker.internal:host-gateway` mapping from the
shared Compose runtime.

## Context

The kit's runtime scripts do not depend on this alias. Since T032, SSH X11 uses
the server IPv4 address derived from `SSH_CONNECTION`. Before this change, the
other references were documentation, a Compose assertion, and a synthetic
hostname in launcher tests.

## Scope

- Remove the mapping and its otherwise empty `extra_hosts` section from source
  `docker-compose.yml`.
- Remove the obsolete alias-presence assertion in `tests/dockerfile-merge.sh`.
- Use a neutral hostname such as `ssh-host.example` in the Chrome launcher test.
- Adjust source and release documentation to describe the new default.

Out of scope: replacement aliases, forwarding services, DNS/firewall changes,
consuming-project override changes, and release publication.

## Acceptance Criteria

- Default resolved Compose no longer adds the `host.docker.internal` alias.
- The separate generated container-hostname mapping remains functional.
- Existing SSH X11, Chrome-launcher, and Compose tests pass.
- Documentation matches the runtime behavior. Removing an alias does not imply
  blocking network access to the host.

## Verification

- Run `tests/dockerfile-merge.sh` and `tests/chrome-launcher.sh`.
- Run `task check`, `task tests-run`, and `git diff --check`.

## File Targets

- `docker-compose.yml`
- `tests/dockerfile-merge.sh`
- `tests/chrome-launcher.sh`
- `README.md`
- `README_release.md`

## Dependencies

- None; T032 is already implemented.

## Implementation Notes

- Edit source files, not the consumed `.devcontainer/` submodule.
- Keep the existing generated hostname entry in `initialize.sh`; it serves a
  different purpose from the removed host-gateway alias.

## Cancellation Reason

Not cancelled.

## Verification Results

Verified on 2026-10-30:

- Removed the default alias and its empty `extra_hosts` section from source
  Compose. Removed the obsolete presence assertion and changed the synthetic
  Chrome test hostname to `ssh-host.example`.
- Source and release guides describe the omitted alias without claiming host
  network access is blocked.
- `tests/dockerfile-merge.sh`, `tests/chrome-launcher.sh`, and `task check`: passed.
- `task tests-run`: passed in 517 seconds, including Compose, nested Docker,
  browser, worktree/submodule integration, and advisory CVE scanning.
- Resolved Compose output retained each fixture's generated hostname-to-loopback
  mapping and contained no `host.docker.internal` entry.
- `git diff --check`: passed.
- Source changes are complete; the consumed runtime submodule was not edited and
  no release was published for this task.
