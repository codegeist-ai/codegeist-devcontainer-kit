# Refresh Image Tools and Review CVEs

- ID: `T031`
- Type: `chore`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `cd28130d-6d6f-4f88-95e2-92e79ae7416c`

## Goal

Keep image tools current and apply available supported updates for reported
vulnerabilities. Findings without a compatible released fix, including CRITICAL
findings, are documented but do not block builds or releases.

## Scope

- Refresh outdated direct pins, checksums, and upstream asset names.
- Refresh npm to current major 12, compatible with Node >=24.15, to pick up
  dependency fixes independently of the NodeSource bundle.
- Build and scan the actual image, distinguish installed tools from Nixpkgs
  source lockfiles and development headers, and report remaining findings.
- Preserve Ubuntu 26.04, Node 24, Helm 3, and the existing functional contracts.
- Do not hand-patch vendored dependencies inside upstream release binaries.

## Acceptance Criteria

- New tool pins resolve to official upstream assets and image smoke tests pass.
- Updated image is scanned with Trivy, retaining unfixed findings in the report.
- Remaining findings identify cases where a dependency fix is not yet shipped
  in the latest compatible tool release; CRITICAL alone is not a blocker.
- Documentation and local maintenance guidance match the selected versions and
  remediation policy.

## File Targets

- `Dockerfile.base`, `tests/docker-build.sh`
- `README.md`, `README_release.md`, local image-maintenance guidance

## Verification

- `task check`, `task tests-run`, and `git diff --check`.
- Scan `codegeist-devcontainer-kit:local` with the updated image's Trivy and
  record HIGH/CRITICAL findings without suppressing unfixed entries.

## Dependencies

- Official upstream assets and current Trivy databases.
- Overlaps the older T014 pin-refresh proposal; its public Issue is not managed
  by this local task.

## Implementation Notes

- Gitleaks 8.30.1, ttyd 1.7.7, and ssh-audit 3.9.0 remain at the latest observed
  upstream release on 2026-10-29. Embedded-library fixes may require later releases.
- Reports stay in disposable `/tmp/opencode/`; this task holds the durable summary.

## Cancellation Reason

Not cancelled.

## Changes And Verification Results

Verified on 2026-10-29:

| Tool | Previous pin | Updated pin |
| --- | --- | --- |
| GraalVM JDK | 25.0.2 | 25.0.4.1.1 (Graal 25.4.4.1.1) |
| Hugo Extended | 0.147.9 | 0.169.0 |
| VHS | 0.11.0 | 0.12.1 |
| Tea | 0.14.2 | 0.16.0 |
| Bitwarden CLI | 2026.8.0 | 2026.10.1 |
| docker-credential-pass | 0.9.9 | 0.9.12 |
| Trivy | 0.74.0 | 0.76.1 |
| whisper.cpp | 1.9.4 | 1.9.5 |
| PowerShell | 7.6.6 | 7.6.9 |

- npm is explicitly refreshed to major 12 (resolved 12.2.1). npm 12 requires
  explicit lifecycle-script approval; the managed image-tool installation
  restores those scripts so OpenCode's postinstall and native CLI setup work.
  A failed real OpenCode startup test identified this requirement; the final
  full suite passed after the correction.
- Updated Bitwarden/whisper archive hashes and the credential helper's published
  checksum. Updated Graal/Hugo asset naming and version smoke assertions.
- Floating tools refreshed through the rebuild. Observed VS Code 1.144.0,
  OpenCode 1.19.5, JBang 0.142.0, and Go 1.26.8. Ubuntu/Node/Helm major contracts
  remain unchanged.
- `task tests-run`: passed on the final image in 257 seconds, including real
  OpenCode startup, Docker/Podman, QEMU, browser, worktree, and submodule checks.
- `task check` and `git diff --check`: passed.

### Remaining Scan Findings

Trivy 0.76.1 scanned the actual final `codegeist-devcontainer-kit:local` image,
ID `sha256:0f6f6a3e1809543ff30f9b576ab9e4fdcb42bf3b4ed4504bcb37349927d93c29`,
without excluding unfixed vulnerabilities. The disposable full report is
`/tmp/opencode/updated-image-cve-report.json`.

- 562 HIGH/CRITICAL package/advisory matches: 25 CRITICAL and 537 HIGH. This is
  not a count of distinct CVEs and is not directly comparable with the earlier
  running-rootfs scan, which also included a mounted VS Code server.
- 295 matches concern `linux-libc-dev` development headers, not the host kernel.
  No Ubuntu finding has a fixed Ubuntu package version listed in this scan.
- 100 matches concern Cargo lockfiles in the Nixpkgs source tree, not evidence
  that those programs are installed.
- Remaining categories: 148 Go-binary, 10 Java, 3 Node package matches, plus
  6 non-header Ubuntu matches. Do not hide these remaining findings.
- Of the 25 CRITICAL matches, 12 concern headers, 12 concern Nixpkgs lockfiles,
  and one concerns the Go stdlib embedded in the current Gitleaks 8.30.1 release
  (`CVE-2025-68121`). No newer official Gitleaks release was available at review.
- No CRITICAL finding remains for the updated VHS or Hugo binaries, or the
  image's VS Code `shell-quote` dependency.
- Current published tools still embed older dependencies: examples include k9s,
  Gitleaks, JBang, and npm 12.2.1 (undici 6.29.0). Scanner-listed dependency fixes
  are retained as follow-up information, not applied by modifying vendor binaries
  or their bundled dependency trees. Recheck compatible upstream releases during
  subsequent maintenance.
- No severity gate, suppression, source commit, or runtime release was added.

### Automatic Scan Follow-up

- `tests/run.sh` runs `tests/image-cve-scan.sh` after the image-build tests.
- Trivy reports HIGH/CRITICAL findings, including unfixed ones, without failing
  on findings. A scanner execution failure fails verification.
- The latest report and reusable databases are under `.tmp/image-cve-scan/`,
  outside the suite's cleanup-trapped fixture directory. These are disposable.
- The release workflow's mandatory `task tests-run` now includes the scan; a
  standalone `task docker-build` or devcontainer start does not run it.
- Verified standalone scan with fresh databases: completed in about 42 seconds.
  The subsequent full `task tests-run` passed in 89 seconds; its cached CVE scan
  took 19 seconds and reported 537 HIGH / 25 CRITICAL matches without blocking.
  `task check` and `git diff --check` also passed.
