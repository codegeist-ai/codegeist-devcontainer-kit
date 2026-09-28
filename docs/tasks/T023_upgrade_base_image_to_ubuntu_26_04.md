# Upgrade Base Image To Ubuntu 26.04

- ID: `T023`
- Type: `build`
- Status: `planned`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `1a7b2d81-18ad-4cf3-a351-5e2cfe6559cd`

## Goal

Migrate the source and released devcontainer image from Debian 12 Bookworm to
the official Ubuntu 26.04 LTS base while preserving the supported development
toolchain, rootless Podman, rootful Docker-in-Docker, browser, display, audio,
QEMU, security, infrastructure, and Dev Containers lifecycle contracts.

Use the stable `ubuntu:26.04` OCI tag rather than `latest` or `rolling`, and
prove the resulting runtime reports Ubuntu 26.04 before changing documentation
or considering the migration complete.

## Context

`Dockerfile.base` currently starts from `debian:bookworm-slim`. Its main APT
transaction mixes distribution packages with several signed third-party
repositories and direct binary installations. An operating-system migration is
therefore broader than changing the `FROM` line.

Ubuntu 26.04 LTS is the Resolute release. The official Ubuntu OCI image
publishes the stable `26.04` and `resolute` tags. Use `ubuntu:26.04` so the image
continues to receive the supported 26.04 base refreshes without moving to a
later Ubuntu release automatically.

The repository configuration currently contains Debian-specific third-party
sources:

- Docker's key and repository use `download.docker.com/linux/debian` with the
  distribution codename.
- Microsoft's product repository is hard-coded to Debian 12 Bookworm and
  supplies packages including PowerShell.
- HashiCorp uses the base distribution codename dynamically.
- The VS Code, NodeSource, Nushell, GitHub CLI, and OpenTofu repositories use
  distribution-independent channels, but their packages still need installation
  and runtime verification on the new base.

As of task creation, Docker documents Ubuntu Resolute 26.04 as supported and
publishes a `resolute` APT suite. HashiCorp also publishes a `resolute` suite.
Microsoft package availability and the correct Ubuntu 26.04 product-repository
configuration must be revalidated during implementation; do not keep the Debian
12 repository or silently mix Debian packages into the Ubuntu image.

Ubuntu 26.04 changes the distribution versions of Python, Podman, QEMU,
iptables, system libraries, and many build dependencies. Directly downloaded
binaries and `.deb` files may also depend on glibc, OpenSSL, ICU, audio, X11, or
other libraries whose resolved versions differ from Bookworm. A successful APT
transaction alone does not prove runtime compatibility.

## Scope

In scope:

- Replace `debian:bookworm-slim` with the official `ubuntu:26.04` base image.
- Change Docker's signed APT source from the Debian endpoint to the supported
  Ubuntu Resolute endpoint while retaining Docker CE, CLI, containerd, Compose,
  and Buildx behavior.
- Replace the hard-coded Microsoft Debian 12 product source with the supported
  Ubuntu 26.04 source or another official Microsoft installation path that keeps
  PowerShell functional without cross-distribution package mixing.
- Revalidate every configured third-party APT source against Ubuntu 26.04 and
  keep signed keyring-based repository configuration.
- Revalidate every package in the main Ubuntu APT transaction and make only the
  smallest package-name or dependency changes required by real build failures.
- Verify direct `.deb`, archive, installer-script, npm, PyPI, Nix, GraalVM, and
  standalone binary installations against the new userspace.
- Add image assertions for `ID=ubuntu`, `VERSION_ID=26.04`, and
  `VERSION_CODENAME=resolute`.
- Preserve normal-user creation, UID/GID alignment, passwordless maintenance
  commands, login-shell PATH setup, and generated devcontainer behavior.
- Preserve Docker-in-Docker and rootless Podman runtime behavior, not only their
  command presence.
- Update current source, release, contributor, and local agent documentation
  from Debian-specific language to Ubuntu 26.04 where it describes active
  behavior.
- Keep the release-copy contract so `Dockerfile.base` remains the source for the
  runtime release branch's `Dockerfile`.

Out of scope:

- Moving to Ubuntu 26.10, `ubuntu:latest`, `ubuntu:rolling`, or an unpinned
  development image.
- Replacing APT with Nix, Homebrew, or another primary package manager.
- Removing Docker, Podman, QEMU, browser, audio, infrastructure, or security
  tooling merely because migration exposes a compatibility problem.
- Upgrading independently pinned application versions unless the current pin
  cannot run on Ubuntu 26.04 and the smallest compatible adjustment is recorded.
- Changing Node.js 24, Java 25, Helm 3, or other intentional major-version
  contracts without a separately justified requirement.
- Replacing rootful Docker-in-Docker, removing `privileged: true`, or changing
  workspace networking as part of the operating-system migration.
- Rewriting historical solved task records that correctly describe the Debian
  environment in which they were implemented.
- Editing generated release content directly inside the `.devcontainer/`
  submodule.
- Publishing a release or changing Git history.

## Repository And Package Decisions

- Use Ubuntu's normal `/etc/os-release` values to derive `resolute` only for
  repositories that officially publish a matching suite.
- Use Docker's Ubuntu repository and key URL; do not point Ubuntu at Docker's
  Debian repository.
- Use an official Microsoft Ubuntu 26.04 source for Microsoft product packages.
  If it is unavailable or does not provide every required package, stop and
  document the blocker or use another upstream-supported installation method.
  Do not fall back silently to Debian Bookworm or an older Ubuntu suite.
- Keep generic signed repositories generic when their upstream contract is
  distribution-independent, but prove package dependency resolution in the real
  image build.
- Preserve `--no-install-recommends` and APT-list cleanup unless an observed
  Ubuntu runtime failure requires a documented exception.
- Do not preemptively add compatibility libraries. Add a package only when the
  image build or a focused runtime check demonstrates the need.

## Acceptance Criteria

- `Dockerfile.base` uses `FROM ubuntu:26.04` and contains no active Bookworm base
  or Debian Docker/Microsoft product repository configuration.
- The built image reports `ID=ubuntu`, `VERSION_ID=26.04`, and
  `VERSION_CODENAME=resolute` from `/etc/os-release`.
- Docker CE packages install from Docker's official Ubuntu Resolute repository,
  and nested `dockerd`, `docker ps`, Compose, and Buildx remain functional.
- Microsoft packages install through an official Ubuntu-compatible source;
  `pwsh` and `code` start successfully without a Debian 12 package source.
- HashiCorp, OpenTofu, NodeSource, Nushell, GitHub CLI, and VS Code repository
  setup completes with valid signatures and no unsupported-suite fallback.
- Every package currently required from the main distribution transaction is
  either installed under the same name or replaced with a documented Ubuntu
  equivalent that preserves behavior.
- Python and the existing `pip --break-system-packages` installation complete;
  `ddgr`, `graphifyy`, `lxml_html_clean`, `ssh-audit`, and `trafilatura` import or
  start through focused smoke checks.
- Rootless Podman runs the fully qualified hello-world image as the normal
  workspace user without `sudo`.
- The normal workspace user, UID/GID mapping, writable bind mounts, sudo policy,
  shell completion, profile scripts, Nix installation, and OpenCode bootstrap
  continue to work.
- Chrome headless and visible Wayland/X11 paths, FFmpeg/Pulse recording,
  whisper.cpp, Vault Agent, Bitwarden CLI state, Docker credential helper,
  QEMU smoke behavior, and security scanners retain their tested contracts.
- Directly installed CLIs and native binaries start without missing shared
  libraries on Ubuntu 26.04.
- `tests/dockerfile-merge.sh` expects the Ubuntu base and still proves local
  Dockerfile fragments are appended to the kit image correctly.
- Source and release documentation describe Ubuntu 26.04 as the current base and
  no current-behavior text incorrectly attributes active packages to Debian
  Bookworm.
- Historical completed task documents remain unchanged unless they are actively
  maintained current-behavior references rather than historical records.
- Release-copy verification proves the Ubuntu-based `Dockerfile.base` becomes
  the release branch's `Dockerfile` without adding unrelated files.

## File Targets

- `Dockerfile.base`
- `tests/docker-build.sh`
- `tests/dockerfile-merge.sh`
- Additional existing runtime tests only when Ubuntu exposes a real uncovered
  compatibility failure
- `README.md`
- `README_release.md`
- `CONTRIBUTING.md`
- `.oc_local/rules/devcontainer-kit.md`
- `docs/tasks/T023_upgrade_base_image_to_ubuntu_26_04.md`

The final changed-file set should remain limited to observed migration needs.
Do not edit every historical mention of Debian indiscriminately.

## Dependencies And Sequencing

- Complete or reconcile `T014` first. Its planned pinned-tool refresh explicitly
  preserves Debian Bookworm, while this task replaces that operating-system
  contract and touches the same Dockerfile and image tests.
- Coordinate with `T020` and `T022` if they are implemented concurrently because
  they modify the same integration suite and runtime documentation. They are not
  semantic prerequisites for the base-image migration.
- Revalidate external repository support immediately before implementation;
  package repositories are moving dependencies even though the Ubuntu base tag
  is stable.

## Implementation Plan

1. Record a Bookworm baseline before editing:
   - Build the current image and capture installed command versions, selected APT
     package origins, `/etc/os-release`, and relevant runtime smoke results.
   - Keep the baseline focused on comparison data; do not commit generated
     package inventories or raw build logs.
2. Create a disposable Ubuntu 26.04 build probe:
   - Change only the base image and distribution-specific repository endpoints
     in the probe.
   - Run `apt-get update` and inspect failures by repository and package rather
     than applying broad compatibility workarounds.
   - Confirm Docker and HashiCorp use their supported `resolute` suites and
     determine the official Microsoft Ubuntu 26.04 source.
3. Update `Dockerfile.base` with the smallest validated source changes:
   - Switch to `ubuntu:26.04`.
   - Switch Docker from `/linux/debian` to `/linux/ubuntu`.
   - Replace the Microsoft Debian 12 Bookworm product source with the verified
     Ubuntu 26.04 source.
   - Keep generic signed repositories unchanged unless the probe proves a
     compatibility requirement.
4. Resolve distribution-package differences one failure at a time. Preserve
   package behavior and record the reason for every renamed, added, or removed
   package in this task's implementation or verification notes.
5. Build the complete image and extend `tests/docker-build.sh` to assert Ubuntu
   identity, critical package origins, Python tools, PowerShell, and representative
   native binaries in addition to the existing tool smoke coverage.
6. Update `tests/dockerfile-merge.sh` for the Ubuntu base assertion and run the
   focused image and merge tests before broader runtime work.
7. Run the real Dev Containers lifecycle and verify nested Docker, rootless
   Podman, user identity, mounts, browsers, audio, QEMU, Vault, OpenCode, and
   worktree behavior. Fix only failures caused by the Ubuntu migration.
8. Rewrite current source, release, contributor, and local agent guidance to
   identify Ubuntu 26.04 and its package sources. Preserve accurate historical
   task records.
9. Run the full integration suite, release-copy verification, security-relevant
   checks, and whitespace validation. Record concrete results and set this task
   to `solved` only after the full image and runtime contracts pass.

## Verification

- `bash -n tests/docker-build.sh tests/dockerfile-merge.sh`
- `task check`
- `task docker-build`
- Inspect `/etc/os-release` in `codegeist-devcontainer-kit:local` and require
  Ubuntu `26.04` with codename `resolute`.
- Inspect configured APT source files and package policies to confirm Docker,
  Microsoft, HashiCorp, and other third-party packages come from the intended
  Ubuntu-compatible signed repositories.
- Run focused commands for `docker`, `dockerd`, `docker compose`, Buildx,
  `podman`, `pwsh`, `code`, Python-installed tools, Chrome, FFmpeg,
  `whisper-cli`, QEMU, Vault, Terraform, OpenTofu, and security scanners.
- `tests/dockerfile-merge.sh`
- `tests/docker-build.sh`
- `task tests-run`
- `tests/release-build.sh`
- `git diff --check`

## Verification Results

Not run; this task currently records the Ubuntu 26.04 migration scope, known
repository changes, compatibility risks, and implementation plan only.

## Cancellation Reason

Not cancelled.
