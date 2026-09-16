# Install Docker Pass Credential Helper

- ID: `T015`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues/21`
- Tracking Key: `60934bf5-4535-4507-8612-d138d7984b2a`

## Goal

Install the verified official `docker-credential-pass v0.9.9` binary in the
base devcontainer image without configuring users' Docker, GPG, or
password-store state.

## Context

The image already includes Docker, GnuPG, and `pass`, but it does not include
the Docker credential helper that stores registry credentials through the
user's password store. Without a native helper, Docker may place base64-encoded
credentials in its configuration file.

The official `v0.9.9` release publishes the Linux amd64 asset
`docker-credential-pass-v0.9.9.linux-amd64` with SHA-256
`ae80a143101672b53c65cd5aa05028897068d39e2649adff83a520ef3218355d`.
The Debian Bookworm `golang-docker-credential-helpers` package is older and
adds unrelated desktop secret-service dependencies, so this task uses the
official release binary instead.

This task supplies the executable only. Each user remains responsible for
selecting or creating a GPG key, initializing `pass`, and choosing whether to
configure Docker explicitly with `"credsStore": "pass"`.

## Scope

In scope:

- Add pinned version and SHA-256 build arguments for the official Linux amd64
  `docker-credential-pass` release.
- Download, verify, and install the helper as
  `/usr/local/bin/docker-credential-pass` in the base image.
- Extend the built-image smoke test to verify that the installed helper is
  executable and reports the expected version.
- Document the helper's purpose, its GPG and `pass init` prerequisites, and the
  optional user-owned Docker configuration.
- Run the full integration suite because the generated runtime image changes.

Out of scope:

- Creating or importing GPG keys.
- Running `pass init` or modifying a user's password store.
- Creating or modifying `~/.docker/config.json` or setting `credsStore`
  automatically.
- Performing a real registry login or storing test credentials.
- Adding Git, Gitea, or Tea credential-helper behavior.
- Installing the Debian `golang-docker-credential-helpers` package or desktop
  keyring dependencies.
- Editing generated release content directly inside `.devcontainer/`.
- Publishing a runtime release before this task is saved and fully verified.

## Acceptance Criteria

- The base image contains an executable
  `/usr/local/bin/docker-credential-pass` from official release `v0.9.9`.
- The downloaded Linux amd64 binary is verified against SHA-256
  `ae80a143101672b53c65cd5aa05028897068d39e2649adff83a520ef3218355d`
  before installation.
- `tests/docker-build.sh` verifies the helper's path, executability, and
  expected version through the existing built-image smoke path.
- The build and tests do not initialize GPG or `pass`, modify Docker credential
  configuration, contact a registry, or create credential material.
- Source and consumer documentation explain that users must initialize their
  own password store and may opt into `"credsStore": "pass"` themselves.
- Existing Docker, devcontainer lifecycle, browser, QEMU/KVM, recording, and
  release-copy behavior remains functional.

## Verification

- `bash -n tests/docker-build.sh`
- `task check`
- `task tests-run`
- `tests/release-build.sh`
- `git diff --check`
- Inspect the built image output for `docker-credential-pass v0.9.9` without
  exercising credential storage.

## File Targets

- `Dockerfile.base`
- `tests/docker-build.sh`
- `README.md`
- `README_release.md`
- `docs/tasks/T015_install_docker_credential_pass.md`

## Dependencies

- Official Docker credential helpers release `v0.9.9` and its published Linux
  amd64 checksum.
- Coordinate edits to `Dockerfile.base`, `tests/docker-build.sh`, `README.md`,
  and `README_release.md` with `T014`; neither task depends on the other.

## Implementation Notes

- Keep the helper version and checksum next to the existing pinned image-tool
  arguments so the download contract is reviewable.
- Use `curl -fsSL`, `sha256sum -c -`, and `install -m 0755`, then remove the
  temporary download in the same image layer.
- Do not add configuration or startup hooks. Installing the helper must not
  change behavior until Docker selects it or the user opts in.
- Keep documentation examples free of real key identities, registry addresses,
  usernames, passwords, and tokens.

## Implementation Plan

1. Revalidate the official `v0.9.9` Linux amd64 asset name and checksum
   immediately before editing the image.
2. Add the pinned helper version, checksum, verified download, and installation
   to `Dockerfile.base` without changing user configuration.
3. Extend `tests/docker-build.sh` with non-destructive path, executable, and
   version assertions against the built image.
4. Update `README.md` and `README_release.md` with the manual GPG, `pass init`,
   and optional Docker configuration contract.
5. Run syntax and fast checks, then rebuild and execute `task tests-run`.
6. Run the release-copy smoke test and diff checks, record concrete results,
   close the linked Issue as completed, and set the task to `solved` only after
   all verification succeeds.

## Verification Results

- On 2026-09-16, the official `v0.9.9` Linux amd64 binary matched SHA-256
  `ae80a143101672b53c65cd5aa05028897068d39e2649adff83a520ef3218355d`
  and reported
  `docker-credential-pass (github.com/docker/docker-credential-helpers) v0.9.9`.
- `bash -n tests/docker-build.sh` passed.
- `task check` passed, including the release-copy contract test.
- `task tests-run` passed in 520 seconds, including the built-image helper
  assertion and all devcontainer, browser, QEMU/KVM, recording, and submodule
  workflows.
- A direct invocation from `codegeist-devcontainer-kit:local` reported the
  expected `docker-credential-pass` version without storing credentials.
- `tests/release-build.sh` passed after the full integration suite.
- `git diff --check` passed.
- No GPG key, password store, Docker credential configuration, registry login,
  or credential material was created by the implementation or its tests.
- GitHub Issue `#21` was closed as completed and read back with its canonical
  task linkage intact before this task was marked solved.

## Cancellation Reason

- `none`
