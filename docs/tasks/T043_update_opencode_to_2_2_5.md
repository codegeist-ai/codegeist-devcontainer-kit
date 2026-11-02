# Update OpenCode To 2.2.5

- ID: `T043`
- Type: `chore`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `8365a3dc-3ff6-4a15-9cd9-916dff77f652`

## Goal

Ship OpenCode CLI pinned to 2.2.5 with the existing `oc` workflow, and review newer
versions of pinned image software before every release with user-approved updates.

## Context

At specification time, `Dockerfile.base` installed the unpinned `opencode-ai` npm
package and the running development container reported version 1.19.5.
OpenCode 2 uses the separate `@opencode/cli` package. The initial 2.0.0 migration
was verified below; the user then explicitly selected the fixed 2.2.5 release
and requested a fresh pinned-version review with an update question before each
release.

The previous `cmds/oc` launched `opencode --auto -c` through tmux. Integrations also
depend on the logging Bash wrapper, proxy/CA environment, workspace configuration,
and CLI startup/model commands. Verify these against 2.2.5 rather than assuming
major-version compatibility.

Sources:

- [Official OpenCode 2 installation](https://opencode.ai/v2/docs/)
- [Exact npm release metadata](https://registry.npmjs.org/@opencode%2Fcli/2.2.5)

## Scope

1. Replace `opencode-ai` with `@opencode/cli@2.2.5` in the existing npm installation
   step, retaining the global `opencode` entrypoint.
2. Check 2.2.5's actual CLI/configuration behavior and make only the compatibility
   changes needed by the kit's existing launchers and tests.
3. Add an exact built-image version assertion and update source/release docs with
   the version and container rebuild requirement.
4. Require fresh upstream checks of explicit image software pins before every
   agent-guided release. Ask which available updates may be applied before save
   and verification; retain declined pins and report unchecked entries explicitly.

Keep the update direct: no additional installer, wrapper layer, automatic upgrade
service, or unrelated tool updates. Release publication and migration/deletion of
real user sessions, credentials, or mounted configuration are out of scope.

## Acceptance Criteria

- A rebuilt image installs `@opencode/cli` at exactly 2.2.5, and the real
  `opencode --version` output confirms that version.
- `oc` starts the real 2.2.5 CLI outside and inside tmux, preserves argument
  boundaries and the intended continue/permission behavior, and retains the
  existing clipboard and recorder bindings. Required flag changes are documented.
- Supported workspace configuration loads, shell logging and
  `DEVCONTAINER_WORKSPACE_TMP` remain usable, and real OpenCode HTTP/TLS requests
  work through the existing proxy and CA configuration.
- Existing smoke tests retain their behavioral coverage; obsolete CLI commands
  are replaced with verified 2.2.5 equivalents when needed.
- Documentation identifies the installed version and rebuild requirement. Runtime
  changes remain limited to installation and demonstrated compatibility needs.
- Release rules and `/release-build` require the pinned-version review before
  `/save`, followed by the existing commit-bound tests and publication workflow.
  A release request alone does not approve new version updates.

## Verification

- Inspect the exact 2.2.5 release and CLI help before adapting `--auto -c`,
  `debug startup`, or `models --refresh --pure` usage.
- Use disposable configuration/state for real CLI startup and integration checks.
  Wrapper argument-capture tests alone do not prove 2.2.5 compatibility.
- Extend `tests/docker-build.sh` with the version assertion and run the affected
  existing OpenCode, tmux, shell, proxy, and Dev Containers checks.
- Run `task check`, `task tests-run`, and `git --no-pager diff --check`. Record
  results and the suite's advisory CVE findings in this task.
- Review the release instructions for no updates, approved/declined updates,
  unavailable metadata, and pins changed by save/rebase.

## File Targets

- `Dockerfile.base`, `cmds/oc`, `docker-compose.yml`
- `tests/docker-build.sh`, `tests/devcontainer-up.sh`, `tests/compose-config.sh`
- `tests/opencode-tmux-wrapper.sh`, `tests/opencode-bash.sh`, `tests/opencode-http.py`
- `scripts/opencode-bash.sh`, `scripts/opencode-http-log.py` only if required
- `README.md`, `README_release.md`, `.oc_local/rules/devcontainer-kit.md`
- `.oc_local/rules/image-maintenance.md`, `.oc_local/rules/release-build.md`,
  `.oc_local/commands/release-build.md`

## Dependencies

- Published `@opencode/cli@2.2.5` and its Linux x64 native package.
- Existing image-build and integration-test prerequisites.

## Blockers

None.

## Implementation Notes

Work in the source checkout. If compatibility requires shared agent-kit changes,
record the specific upstream dependency rather than editing the consumed
`.opencode/` submodule. Preserve user-owned state while testing the upgrade.

## Implementation And Verification Results

### Initial 2.0.0 Validation

Verified on 2026-11-02 before the user selected 2.2.5:

- Replaced the npm package in the existing image installation step. The rebuilt
  image reports `opencode v2.0.0`; npm confirms `@opencode/cli@2.0.0` under
  `/usr/local/lib`. The exact version assertion failed against 1.19.5 first.
- `oc` now passes `--standalone --auto -c`. Each pane's private backend inherits
  its shell/proxy/CA settings and ends with the CLI; the container proxy keeps its
  existing independent lifetime.
- Renamed the Compose setting to `OPENCODE_FILEWATCHER_DISABLE`, which 2.0.0
  actually reads. Documented that change, the removed root `--model` argument,
  and the required container rebuild and new `oc` pane.
- Replaced removed `debug startup` and `models --refresh --pure` checks with real
  V2 configuration requests and a bounded foreground server. Tests verify the
  supported workspace template, actual TUI startup inside/outside tmux, real
  catalog traffic through TLS interception, and shell execution through the
  logging wrapper with owner-only log permissions. User state remains isolated.
- Preserved the clean-image `/tmp/opencode` assertion before the version check:
  OpenCode 2 creates that runtime directory even for `--version`.
- `tests/docker-build.sh`, `task check`, and `git --no-pager diff --check`: passed.
- `task tests-run`: passed in 110 seconds, including the new OpenCode checks and
  existing browser, Docker, KVM, lifecycle, worktree, and submodule integrations.
- Advisory image scan: 535 HIGH and 24 CRITICAL findings; scanner completed
  successfully. The full report is `.tmp/image-cve-scan/report.json`.
- Follow-up test simplification separates proxy and native OpenCode checks,
  delegates shell API authentication to the CLI, and uses `communicate()` for
  stdin-lease shutdown and output draining. `tests/docker-build.sh`, `task check`,
  and `git --no-pager diff --check` passed again after this refactor.

### Final 2.2.5 Pin And Release Review

Completed on 2026-11-02:

- Pinned `@opencode/cli@2.2.5` and updated both exact-version assertions and the
  consumer/source documentation. Renamed this task to match the selected version
  while retaining its ID and Tracking Key.
- The first 2.2.5 suite exposed its changed model-catalog URL. The HTTP test now
  requires a fresh HTTPS 200 response from
  `models.opencode.ai/experimental/v2.0/api.json`, as used by upstream 2.2.5.
- Added the mandatory per-release pinned-version review to
  `.oc_local/rules/image-maintenance.md` and referenced it before `/save` in the
  release command, related rules, and source README. Reviewed the no-update,
  approved/declined-update, unchecked-metadata, and changed-after-save cases.
- `task check` and `git --no-pager diff --check`: passed. Final `task tests-run`
  passed in 106 seconds, including exact 2.2.5 image/TUI checks, real proxy and
  shell integration, workspace configuration, and the existing runtime suite.
- Final advisory image scan: 535 HIGH and 24 CRITICAL findings; scanner completed
  successfully. Latest report: `.tmp/image-cve-scan/report.json`.

### Release Preparation

- Fresh upstream review on 2026-11-02 confirmed all 14 exact tool pins are current.
  npm 12.2.1 and Node.js 24.22.2 are current within the selected major lines.
- The user requested supported LTS tracks and compatible updates. Ubuntu 26.04
  LTS is retained instead of Ubuntu 26.10. Node.js 26.13.0 LTS is available, but
  the current Renovate 44.202.0 package declares Node.js `^24.11.0`, so Node.js
  24.x LTS is retained for compatibility. No additional pin changes are required.
- Captured that LTS and runtime-compatibility preference in the pinned-version
  review rule. The release review had no unchecked entries.

## Cancellation Reason

Not cancelled.
