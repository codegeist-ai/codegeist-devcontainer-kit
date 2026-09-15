# Refresh Pinned Base Image Tools

- ID: `T014`
- Type: `chore`
- Status: `planned`
- Parent: `none`
- Public Tracking: `https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues/20`
- Tracking Key: `ee840b41-1970-4996-b555-301faff68424`

## Goal

Update the explicitly pinned GraalVM, Hugo, VHS, and Tea installations in the
base devcontainer image to their current compatible releases while preserving
the existing Java, operating-system, Node.js, and Helm major-version contracts.

## Context

An update audit on 2026-09-15 compared every directly managed application in
`Dockerfile.base` with its authoritative package or release source. Floating
APT, npm, PyPI, GitHub-latest, and installer-script dependencies already resolve
their configured current candidates during an uncached build. Five of the nine
explicit application pins are current, while these four have newer compatible
releases:

- GraalVM Community JDK 25: `25.0.2` to JDK `25.0.4.1` in Graal release
  `25.3.4.1`.
- Hugo Extended: `0.147.9` to `0.166.0`.
- VHS: `0.11.0` to `0.12.0`.
- Tea: `0.14.2` to `0.15.0`.

GraalVM's current release tag and archive name no longer derive from one plain
JDK version value. The Linux x64 archive is published under tag
`graal-25.3.4.1` as
`graalvm-community-jdk-25i3-25.0.4.1_linux-x64_bin.tar.gz`. Hugo likewise
changed its Linux archive suffix from `Linux-64bit` to `linux-amd64`.

The parent repository currently has an intentional uncommitted `.devcontainer`
gitlink update from the preceding release workflow. This task must not absorb,
reset, or otherwise change that existing user state unless a later explicit
save instruction includes it.

## Scope

In scope:

- Update the four pinned application versions in `Dockerfile.base`.
- Represent GraalVM's release tag and archive version separately so the current
  official Linux x64 asset URL is explicit and reviewable.
- Update the Hugo asset path for the current official Linux amd64 naming.
- Keep the existing Tea and VHS installation mechanisms while changing their
  pinned versions.
- Extend the existing image smoke test to assert the four installed versions,
  not only that the commands start.
- Review source and consumer documentation for stale exact-version statements
  and update only those affected by these pins.
- Run the full real integration suite because the generated runtime image and
  several user-facing CLI binaries change.

Out of scope:

- Migrating `debian:bookworm-slim` to Debian 13 `trixie`.
- Moving Node.js from the `node_24.x` channel to Node.js 26.
- Moving from Helm 3 to Helm 4.
- Pinning every currently floating APT, npm, PyPI, installer-script, or
  GitHub-latest dependency.
- Changing current pins for ttyd `1.7.7`, Trivy `0.74.0`, Gitleaks `8.30.1`,
  whisper.cpp `1.9.4`, or ssh-audit `3.9.0`.
- Editing generated release content directly inside `.devcontainer/`.
- Editing the `.opencode/` submodule directly; version-specific shared tool
  guidance must be changed in the agent-kit source repository through its own
  workflow.
- Publishing a runtime release before this task is saved and fully verified.

## Acceptance Criteria

- The image installs GraalVM Community JDK `25.0.4.1` from Graal release
  `25.3.4.1`, and both `java` and `native-image` start successfully.
- The image installs Hugo Extended `0.166.0` from the official
  `linux-amd64` archive.
- The image installs VHS `0.12.0` and Tea `0.15.0` from their official Linux
  amd64 artifacts.
- `tests/docker-build.sh` checks the exact installed versions for GraalVM, Hugo,
  VHS, and Tea through the existing built-image smoke path.
- Existing image tools, devcontainer lifecycle behavior, browser support,
  QEMU/KVM, microphone recording, and release-copy behavior remain functional.
- Debian Bookworm, Node.js 24, and Helm 3 remain unchanged.
- Any affected exact-version documentation is current, while historical solved
  task records remain unchanged.
- The pre-existing parent `.devcontainer` gitlink change is preserved and is
  not included accidentally in implementation-only edits.

## Verification

- `bash -n tests/docker-build.sh`
- `task check`
- `task tests-run`
- `tests/release-build.sh`
- `git diff --check`
- Inspect the built image outputs for exact GraalVM, Hugo, VHS, and Tea versions.

## File Targets

- `Dockerfile.base`
- `tests/docker-build.sh`
- `README.md`
- `README_release.md`
- `docs/tasks/T014_refresh_pinned_base_image_tools.md`

## Dependencies

- Authoritative upstream Linux amd64 release artifacts for GraalVM release
  `25.3.4.1`, Hugo `0.166.0`, VHS `0.12.0`, and Tea `0.15.0`.
- A separate upstream agent-kit documentation change if its version-specific
  GraalVM or Hugo inventory still reflects the old image after this task lands.

## Implementation Notes

- Keep the smallest source change: split only the GraalVM release identity from
  its archive identity, and change the Hugo filename template only where the
  upstream naming requires it.
- Do not introduce new checksums for previously unhashed downloads as part of a
  version-only refresh. Treat download-verification hardening as separate work.
- Use the existing `tests/docker-build.sh` image rather than creating a parallel
  update-audit harness.
- Do not infer a successful update from Dockerfile text alone; exact runtime
  version output from the rebuilt image is required.

## Implementation Plan

1. Revalidate all four release identities and Linux amd64 asset names immediately
   before editing because the source URLs are external moving dependencies.
2. Update GraalVM, Hugo, VHS, and Tea arguments and download paths in
   `Dockerfile.base` without changing unrelated installation policies.
3. Extend `tests/docker-build.sh` with exact runtime version assertions for the
   four changed tools.
4. Review `README.md` and `README_release.md` for affected current-version facts;
   keep historical task records untouched.
5. Run syntax and fast checks, then rebuild and execute the complete real
   `task tests-run` suite.
6. Run the release-copy smoke test and diff checks, record concrete results in
   this task, close the linked Issue as completed, and set the task to `solved`
   only after all verification succeeds.

## Cancellation Reason

- `none`
