# Install Bitwarden CLI

- ID: `T016`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `1b586f37-f831-40c9-a9bb-9ebea2ea51fe`

## Goal

Install the verified official Bitwarden CLI as `bw` in the base devcontainer
image so users can authenticate against Bitwarden-compatible servers such as
Vaultwarden from inside the container.

## Context

The devcontainer already supplies password-store, Gitea, GitHub, and
infrastructure CLIs, but it does not include a client for a user's Vaultwarden
vault. Users need `bw` to configure a self-hosted server, authenticate
interactively with a password, personal API key, or optional browser-based SSO,
and retrieve secrets through an explicitly unlocked session.

The official `cli-v2026.8.0` release publishes the Linux x64 asset
`bw-linux-2026.8.0.zip` with SHA-256
`367f618e9fcccaac4980ec12c7bafd01df739b5f3cb1af31bc9045cf75eea1d6`.
The native release avoids coupling the CLI to the image's Node 24 runtime.

This task installs the executable and gives its local application state a
project-scoped persistent path. It does not choose a server, authenticate a user,
unlock a vault, persist a decrypted session, or render retrieved values into an
environment file.

## Scope

In scope:

- Add pinned version and SHA-256 build arguments for the official Linux x64
  Bitwarden CLI release.
- Download, verify, extract, and install `bw` as `/usr/local/bin/bw`.
- Extend the built-image smoke test to verify the executable path and exact
  version without contacting a vault.
- Document manual Vaultwarden server configuration and password, personal API
  key, and optional SSO login paths.
- Document the separate unlock step and session cleanup commands.
- Set `BITWARDENCLI_APPDATA_DIR` to the repository's ignored
  `.codegeist/secrets/bitwarden-cli` path so CLI state survives container
  recreation and is shared by managed worktrees.
- Run the full integration suite because the generated runtime image changes.

Out of scope:

- Preconfiguring a Bitwarden or Vaultwarden server URL.
- Storing client IDs, client secrets, master passwords, or `BW_SESSION` values.
- Automating login, unlock, synchronization, lock, or logout.
- Rendering a secure note, attachment, or custom fields into an env file.
- Loading generated secrets into Compose, shells, OpenCode, or other processes.
- Testing against a real Bitwarden, Vaultwarden, or OpenID Connect server.
- Editing generated release content directly inside `.devcontainer/`.
- Publishing a runtime release before this task is saved and fully verified.

## Acceptance Criteria

- The base image contains executable `/usr/local/bin/bw` from official release
  `2026.8.0`.
- The downloaded Linux x64 archive is verified against SHA-256
  `367f618e9fcccaac4980ec12c7bafd01df739b5f3cb1af31bc9045cf75eea1d6`
  before extraction.
- `tests/docker-build.sh` verifies the command path, executable bit, and exact
  `bw --version` result through the existing built-image smoke path.
- Source and release documentation explain manual server configuration,
  password login, personal API-key login, optional SSO login, vault unlock, and
  cleanup without including real credentials.
- Documentation states that SSO requires a compatible Vaultwarden OpenID Connect
  configuration and that API-key or SSO login normally still requires
  `bw unlock` before vault contents can be read.
- Root and managed-worktree containers set `BITWARDENCLI_APPDATA_DIR` to
  `$DEVCONTAINER_REPO_ROOT/.codegeist/secrets/bitwarden-cli`.
- The state path is persisted through the existing repository mount, remains
  ignored by Git, and is not migrated from `~/.config/Bitwarden CLI`.
- Build, startup, and tests do not create Bitwarden configuration, contact a
  vault, or persist credential material.
- Existing devcontainer, browser, QEMU/KVM, recording, and release-copy behavior
  remains functional.

## Verification

- `bash -n tests/docker-build.sh`
- `task check`
- `task tests-run`
- `tests/release-build.sh`
- `git diff --check`
- Inspect the built image for `/usr/local/bin/bw` and version `2026.8.0` without
  performing authentication.

## File Targets

- `Dockerfile.base`
- `docker-compose.yml`
- `tests/docker-build.sh`
- `tests/compose-config.sh`
- `tests/devcontainer-worktree-up.sh`
- `README.md`
- `README_release.md`
- `docs/tasks/T016_install_bitwarden_cli.md`

## Dependencies

- Official Bitwarden clients release `cli-v2026.8.0` and its published Linux
  x64 asset digest.

## Implementation Notes

- Use the standard official `bw-linux` artifact so the documented CLI behavior,
  including optional SSO, matches Bitwarden's normal distribution.
- Keep version and digest arguments near the other pinned image-tool inputs.
- Use `curl -fsSL`, `sha256sum -c -`, `unzip`, and `install -m 0755`, then remove
  the archive and extracted temporary file in the same image layer.
- Redirect the build and smoke-test version probes through a temporary
  `BITWARDENCLI_APPDATA_DIR` and remove it afterward because even `bw --version`
  initializes CLI state when the default data directory is absent.
- Keep all login operations user-initiated. In particular, never place personal
  API-key values in Docker build arguments, image layers, tracked examples, shell
  command arguments, or test fixtures.

## Implementation Plan

1. Add the pinned Bitwarden CLI version, digest, verified download, extraction,
   and installation to `Dockerfile.base`.
2. Extend `tests/docker-build.sh` with offline path, executable, and version
   assertions.
3. Update `README.md` and `README_release.md` with the manual Vaultwarden login
   and unlock contract.
4. Set and test a repository-scoped persistent `BITWARDENCLI_APPDATA_DIR` for
   root and managed-worktree containers.
5. Run syntax, fast, image, integration, release-copy, and diff checks.
6. Record concrete verification results and set this task to `solved` only after
   all required checks pass.

## Verification Results

- On 2026-09-16, the official `bw-linux-2026.8.0.zip` archive matched SHA-256
  `367f618e9fcccaac4980ec12c7bafd01df739b5f3cb1af31bc9045cf75eea1d6`
  during the image build and the installed command reported `2026.8.0`.
- The build and smoke probes used disposable `BITWARDENCLI_APPDATA_DIR` paths;
  direct image inspection confirmed that no root or workspace-user Bitwarden
  configuration directory and no build probe directory remained in the image.
- `bash -n tests/docker-build.sh` passed.
- `task check` passed, including the release-copy contract test.
- `task docker-build` passed and produced the final local image with executable
  `/usr/local/bin/bw` at the expected version.
- The first `task tests-run` attempt reached the existing visible Wayland browser
  regression and exited with transient timeout status `124`. An immediate
  isolated `tests/browser-smoke.sh` rerun passed, and the complete final
  `task tests-run` rerun passed all generic devcontainer tests in 133 seconds.
- `tests/release-build.sh` passed after the final implementation.
- `git diff --check` passed.
- No server configuration, login, unlock, vault request, credential, or session
  material was created by the implementation or its tests.
- On 2026-09-17, Compose resolved `BITWARDENCLI_APPDATA_DIR` to the main
  repository's `.codegeist/secrets/bitwarden-cli` path for both root and managed
  worktree containers.
- `bash -n tests/compose-config.sh tests/devcontainer-worktree-up.sh` passed.
- The follow-up `task check` passed, including the release-copy contract test.
- The follow-up `task tests-run` passed all generic devcontainer kit tests in
  146 seconds, including the root and managed-worktree runtime assertions.
- The follow-up `git diff --check` passed.

## Cancellation Reason

- `none`
