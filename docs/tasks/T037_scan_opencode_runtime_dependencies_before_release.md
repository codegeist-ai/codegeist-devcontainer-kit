# Scan OpenCode Runtime Dependencies Before Release

- ID: `T037`
- Type: `test`
- Status: `specified`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `551f2d1b-8486-46d6-80f0-83777f2f7475`

## Goal

Before every runtime release, start the shipped OpenCode, identify the npm
dependencies it downloads or installs during initialization, and scan those
resolved dependencies with Trivy.

## Context

A try-container inspection observed downloads of `@opencode-ai/plugin`,
`@opencode-ai/sdk`, and transitive packages during OpenCode startup. The existing
image CVE scan covers image contents, but dependencies created afterward in a
running container or mounted workspace are outside that image snapshot.

Generated dependency manifests and installed packages must be inspected before
the test fixture is removed. A successful scanner exit with an empty or
unsupported target does not demonstrate coverage of these runtime dependencies.

## Scope

- Start the actual shipped OpenCode through its normal initialization path in
  a fresh test container/workspace with isolated configuration and dependency
  caches. Verify completed initialization rather than only running `--version`.
- Inventory generated or changed `package.json` files, supported lockfiles,
  and installed packages in workspace-local and user-local OpenCode state.
  Record package names, resolved versions, locations, and direct/transitive
  relationships where available. Distinguish package downloads from registry
  metadata checks and security-audit requests.
- Run Trivy against the generated dependency artifacts and installed tree before
  cleanup, using a scanner mode that actually detects the resolved packages.
- Integrate the check into the existing test and release-verification workflow.
  Every release requires fresh evidence from its verification run, associated
  with the exact source commit, tested image, and OpenCode version. A stale
  report or image-only verification must not satisfy this requirement.
- Retain a structured dependency inventory, JSON scan report, and completion
  metadata under workspace `.tmp/`. Reuse the Trivy database cache where useful,
  while keeping OpenCode's discovery environment fresh.
- Update release instructions and relevant test documentation.

Out of scope: automatic dependency upgrades, changing the advisory CVE policy,
scanning on ordinary user OpenCode starts, personal account authentication,
and release publication during implementation.

## Acceptance Criteria

- Every release verifies a real OpenCode startup and its resulting npm dependency
  state through the existing release entrypoint/workflow.
- The inventory identifies the actual installed package versions, including
  transitive runtime dependencies, rather than only declared version ranges.
- Trivy output demonstrably includes the discovered packages. Missing supported
  inputs, incomplete package coverage, or an unexpectedly empty scan are reported
  as verification failures when runtime dependency artifacts exist.
- If successful initialization genuinely creates no additional dependency
  artifacts, record an explicit not-applicable result with supporting inventory;
  do not describe this as a completed package scan.
- Initialization, inventory, scanner execution, or required evidence failures
  prevent release verification from being accepted. Evidence cannot be reused
  as a substitute for the check before a later release.
- Findings, including unfixed CRITICAL vulnerabilities, remain visible and
  advisory under the existing repository policy. Scanner execution success and
  absence of vulnerabilities are reported as different outcomes.
- Reports identify the source commit, image ID, OpenCode/Trivy versions, and scan
  time. Test credentials, personal configuration, and private conversation data
  are not copied into fixtures or reports.
- The check remains part of development/release verification and adds no
  supervision or scanning logic to the normal container entrypoint.

## Verification

- Run the real startup and scan with empty OpenCode dependency caches; verify
  known discovered packages appear with their resolved versions in the report.
- Verify scanner failure, missing evidence, incomplete coverage, and stale
  evidence reject release verification using disposable fixtures.
- Verify advisory findings remain reported without becoming a blanket severity
  gate. Test any no-additional-dependencies branch without treating missing data
  from a failed startup as a successful empty result.
- Run `task check`, `task tests-run`, and `git --no-pager diff --check`.

## File Targets

- `tests/docker-build.sh`, `tests/opencode-http.py`, `tests/opencode-tmux-wrapper.sh`
- `tests/image-cve-scan.sh`, `tests/run.sh`, and focused runtime-scan helpers as needed
- `scripts/release-build.sh`, `tests/release-build.sh`, `Taskfile.yaml`
- `.oc_local/commands/release-build.md`, `.oc_local/rules/release-build.md`
- `README.md` and the relevant release-verification documentation

## Dependencies

- [T031](T031_refresh_image_tools_and_review_cves.md): existing Trivy image scan
  and advisory findings policy.
- [T034](T034_log_opencode_http_requests.md): OpenCode startup/proxy integration
  and HTTP metadata useful for identifying runtime package downloads.

## Implementation Notes

Reuse existing container/test entrypoints and scan conventions. Keep the check
small and non-interactive; use a bounded startup-completion condition instead
of an arbitrary sleep. Network access for package discovery and database updates
is an expected prerequisite.

A top-level `package.json` may contain unresolved dependency ranges. Trivy uses
supported lockfiles or installed package manifests under `node_modules` to
identify resolved dependencies. Check support for the files actually produced:
[Trivy Node.js coverage](https://trivy.dev/latest/docs/coverage/language/nodejs/).
Preserve the fast, Docker-free `task check` contract; release-gate tests use
disposable repositories while the real startup/scan belongs to integration tests.

## Cancellation Reason

Not cancelled.
