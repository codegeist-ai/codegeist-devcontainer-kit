# Upgrade Base Image To Ubuntu 26.04

- ID: `T023`
- Type: `build`
- Status: `solved`
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

Before implementation, `Dockerfile.base` started from `debian:bookworm-slim`. Its main APT
transaction mixes distribution packages with several signed third-party
repositories and direct binary installations. An operating-system migration is
therefore broader than changing the `FROM` line.

Ubuntu 26.04 LTS is the Resolute release. The official Ubuntu OCI image
publishes the stable `26.04` and `resolute` tags. Use `ubuntu:26.04` so the image
continues to receive the supported 26.04 base refreshes without moving to a
later Ubuntu release automatically.

The repository configuration contained Debian-specific third-party
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

- T014 was reconciled to preserve Ubuntu 26.04 when its independent pinned-tool
  refresh is implemented later.
- Coordinate with `T020` and `T022` if they are implemented concurrently because
  they modify the same integration suite and runtime documentation. They are not
  semantic prerequisites for the base-image migration.
- Revalidate external repository support immediately before implementation;
  package repositories are moving dependencies even though the Ubuntu base tag
  is stable.

## Implementation Plan

1. Update focused tests for the Ubuntu base, exact runtime identity, Ubuntu
   Docker source, PowerShell, VS Code, Python tools, and QEMU.
2. Migrate `Dockerfile.base` directly to Ubuntu 26.04, install PowerShell from
   Microsoft's supported universal package, remove `qemu-kvm`, and replace the
   base image's `ubuntu` account with the configured workspace user.
3. Build the complete image and fix only reproduced Ubuntu failures. Preserve
   every other installation mechanism and pinned tool version.
4. Update current documentation, then run focused checks, the complete real
   integration suite, release-copy verification, and whitespace validation.

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

- `Dockerfile.base` now uses `ubuntu:26.04` directly. The image built
  successfully and reported matching
  `ID`, `VERSION_ID`, and `VERSION_CODENAME` values. Docker and HashiCorp used
  their signed Resolute repositories; no active Bookworm, Docker Debian, or
  Microsoft Debian 12 source remained.
- Microsoft did not publish PowerShell in its Ubuntu 26.04 product index during
  implementation. The image therefore installs Microsoft's officially supported
  universal PowerShell 7.6.6 package; both `pwsh` and `code` started successfully.
- Ubuntu's built-in `ubuntu` account was removed before creating the configured
  workspace user. `qemu-kvm` was unavailable and unnecessary because
  `qemu-system-x86` provides the tested emulator commands and KVM execution.
- The first full-suite Podman run reproduced missing overlay storage support, so
  `fuse-overlayfs` was added. The next run reproduced Podman's missing `pasta`
  network helper, so `passt` was added. No other compatibility packages or
  fallback paths were introduced.
- `task check`, `task docker-build`, `tests/dockerfile-merge.sh`, and the focused
  `tests/docker-build.sh` image and tool checks passed.
- `task tests-run` passed all real integrations in 563 seconds, including nested
  Docker, rootless Podman hello-world, QEMU/KVM, Chrome headless and visible
  Wayland, FFmpeg/Pulse/Whisper, Vault, OpenCode, UID/GID and mounts, worktrees,
  parallel branches, and submodule consumption.
- Release-copy verification passed with `Dockerfile.base` copied byte-for-byte
  as release `Dockerfile`.

## Cancellation Reason

Not cancelled.
