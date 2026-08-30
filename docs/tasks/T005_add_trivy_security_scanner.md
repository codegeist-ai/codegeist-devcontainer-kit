# Add Trivy Security Scanner

- ID: `T005`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues/10`
- Tracking Key: `0aa4d327-01da-48e4-a397-6eccd7d333a1`

## Goal

Add a pinned Trivy installation to the shared devcontainer toolchain so
consuming repositories can scan Dockerfiles, local projects, and container
images from inside the development environment.

## Context

The image already provides network and protocol security scanners, but it does
not include a unified scanner for container images, Infrastructure as Code,
dependency vulnerabilities, and secrets. Trivy should be installed as a shared
tool rather than requiring every consuming repository to extend the image.

The installation must remain reproducible and reviewable. The documented usage
must distinguish static Dockerfile misconfiguration checks from vulnerability
checks against a built container image.

## Scope

In scope:

- Install the current approved Trivy release through a pinned Docker build
  argument and the corresponding official versioned installer.
- Verify the installed version during the image build.
- Add focused image-level smoke coverage that proves Trivy can detect a known
  Dockerfile misconfiguration without relying on mutable check updates.
- Document Dockerfile, filesystem, and container-image scan commands for source
  contributors and release-kit consumers.
- Document severity filtering and non-zero CI exit-code behavior.

Out of scope:

- Adding repository-specific Trivy policies, ignore files, or CI workflows.
- Automatically scanning projects during devcontainer startup or image build.
- Publishing the generated `release` branch.
- Changing unrelated security tools or the existing `.devcontainer` submodule
  checkout.

## Acceptance Criteria

- The built devcontainer image exposes a working `trivy` command at the pinned
  version.
- A focused smoke test scans an intentionally unsafe Dockerfile and confirms
  that Trivy reports the expected high-severity non-root-user violation.
- Source and release documentation show commands for `trivy config`, `trivy fs`,
  and `trivy image`.
- Documentation explains that Dockerfile scanning finds configuration problems,
  while image scanning finds vulnerabilities in the resulting image contents.
- Documentation shows how `--severity` and `--exit-code 1` create a CI gate.
- Existing fast checks and the full image/runtime suite pass.

## Verification

- Run `task check`.
- Run `tests/docker-build.sh` through the repository test harness or equivalent
  targeted setup.
- Run `task tests-run` because the image toolchain changes.
- Run `git --no-pager diff --check`.

## Verification Results

- `git --no-pager diff --check` passed.
- `task check` passed.
- `task tests-run` passed, including the image build and deterministic Trivy
  `DS-0002` smoke check.
- GitHub Issue `#10` was closed with reason `completed` and its canonical task
  linkage was revalidated.

## File Targets

- `Dockerfile.base`
- `tests/docker-build.sh`
- `README.md`
- `README_release.md`
- `docs/tasks/T005_add_trivy_security_scanner.md`

## Dependencies

- Official Trivy release artifacts and checksums for the pinned version.
- Docker access for image-level verification.

## Implementation Notes

- Pin Trivy `0.74.0` with `ARG TRIVY_VERSION=0.74.0`.
- Fetch the official installer from the matching `v${TRIVY_VERSION}` source tag
  and request that exact release so the installer verifies the release checksum.
- Keep the scanner opt-in; installing Trivy must not add startup scans or network
  side effects to consuming repositories.
- Build a minimal unsafe Dockerfile fixture in `tests/docker-build.sh`, run
  `trivy config` with check and version updates disabled, and assert both the
  expected `DS-0002` high-severity finding and exit code from JSON output.
- Update both maintained README variants, but do not edit the generated
  `.devcontainer/README.md` submodule content.

## Implementation Plan

1. Extend the image contract in `Dockerfile.base`.
   Add `TRIVY_VERSION=0.74.0` beside the other pinned tool arguments, document
   the input in the file header, and install Trivy from the official installer
   at the matching `v${TRIVY_VERSION}` source tag. Pass the same explicit release
   tag to the installer and finish the layer with `trivy --version` so a missing
   or invalid binary fails the image build.
2. Add a functional Trivy smoke check to `tests/docker-build.sh`.
   Create an isolated fixture under the existing suite temporary directory with
   a minimal Dockerfile that ends in `USER root`. Run the built image against
   that read-only fixture with `trivy config`, disabled check/version updates,
   `HIGH` severity, JSON output, and `--exit-code 1`. Require exit status `1`,
   then use `jq` to assert the embedded `DS-0002` check, `HIGH` severity, and
   root-user message so scanner startup or parsing failures cannot satisfy the
   test. The image build itself verifies that the pinned binary starts through
   the final `trivy --version` command in its installation layer.
3. Expand source documentation in `README.md`.
   Add Trivy to the image toolchain summary and extend `Security Scan Tools` with
   concise commands for Dockerfile/IaC scanning through `trivy config`, combined
   project scanning through `trivy fs --scanners vuln,misconfig,secret`, and
   built-image scanning through `trivy image`. Explain that config scans inspect
   policy and construction choices rather than packages installed in the final
   image, and show `--severity HIGH,CRITICAL --exit-code 1` as the CI-gate shape.
4. Mirror the consumer-facing contract in `README_release.md`.
   Document the same installed command and usage boundaries for projects that
   consume the runtime-only release. Keep wording specific to the released kit
   and leave `.devcontainer/README.md` untouched because it is generated
   submodule content rather than a source target.
5. Verify from narrowest to broadest scope.
   Run `git --no-pager diff --check`, `task check`, the image build smoke through
   the normal test harness, and finally `task tests-run` because the base image
   toolchain changed. Confirm that no generated release branch or unrelated
   `.devcontainer` submodule state was modified. Close and revalidate the linked
   Issue as completed only after all verification passes, then set this task to
   `solved`.

## Open Questions

- None.

## Cancellation Reason

- `none`
