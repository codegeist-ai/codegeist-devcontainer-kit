# Install Podman Alongside Docker

- ID: `T021`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `e662058f-1335-4644-9a24-73bbbca42e84`

## Goal

Install Podman alongside the existing Docker toolchain and prove that the
workspace user can run a real hello-world container with it. Start with only the
Podman package and add no supporting configuration or package until a concrete
test failure demonstrates that it is required.

## Context

The image currently installs Docker Engine, Docker CLI, Compose, Buildx, and
containerd. `entrypoint.sh` starts a nested rootful Docker daemon, and the shared
Compose service remains privileged for that Docker-in-Docker contract.

Podman is available in Debian Bookworm's standard repositories. This task is an
incremental installation and reality check, not yet a migration from nested
Docker to Podman. Docker behavior must remain unchanged while the repository
establishes the smallest Podman configuration that actually works in the current
devcontainer runtime.

Rootless Podman commonly uses subordinate UID/GID ranges, user-mode networking,
and a rootless storage driver. Do not configure those facilities preemptively.
Run the real container smoke test first, diagnose any observed failure, and add
only the smallest dependency or configuration justified by that failure.

The initial runtime probe after installing only `podman` failed before pulling
the image because Podman found multiple subordinate IDs but could not execute
`newuidmap`:

```text
Error: command required for rootless mode with multiple IDs: exec: "newuidmap": executable file not found in $PATH
```

This observed failure justifies adding Debian's `uidmap` package. No other
companion package or configuration is justified unless the next real run exposes
another failure.

After adding `uidmap`, Podman pulled the hello-world image successfully and then
failed while creating its rootless network namespace:

```text
Error: could not find slirp4netns, the network namespace can't be configured: exec: "slirp4netns": executable file not found in $PATH
```

This second observed failure justifies adding Debian's `slirp4netns` package.
The run had not demonstrated a need for any storage helper or configuration.

## Scope

In scope:

- Add Debian's `podman` package to the existing main APT installation in
  `Dockerfile.base`.
- Verify the installed `podman` command in the built-image smoke path.
- Run a fully qualified hello-world image with `podman run --rm` as the normal
  workspace user, without `sudo`.
- Diagnose a failing run from its actual error output before adding any package,
  subordinate ID range, storage setting, runtime directory, or networking
  configuration.
- If the smoke test exposes a real missing prerequisite, update this task with
  the observed failure and add only the prerequisite needed to pass it.
- Document Podman as an additional container tool without changing the existing
  Docker workflow.
- Run the full integration suite because the image contents and container-engine
  behavior change.

Out of scope unless the initial smoke test proves a concrete need:

- Adding `fuse-overlayfs`, `passt`, Buildah, Skopeo, or other recommended
  companion packages explicitly.
- Writing `/etc/subuid` or `/etc/subgid` entries for the workspace user.
- Adding `containers.conf`, `storage.conf`, registry configuration, aliases, or
  wrapper scripts.
- Adding a Podman-specific volume or otherwise making Podman images and
  containers survive devcontainer recreation.

Out of scope for this task:

- Removing Docker packages, Docker CLI, Compose, Buildx, containerd, or
  `dockerd`.
- Replacing Docker-in-Docker with Podman.
- Removing or narrowing `privileged: true`.
- Redirecting the Docker CLI or Compose to a Podman API socket.
- Starting a persistent Podman API service or systemd unit.
- Installing `podman-docker` or replacing the `docker` command.
- Guaranteeing Docker and Podman image-store interoperability.
- Editing generated release content directly inside the `.devcontainer/`
  submodule.
- Publishing a release or changing Git history.

## Acceptance Criteria

- `Dockerfile.base` installs `podman` from the configured Debian Bookworm
  repositories.
- `Dockerfile.base` installs `uidmap` because the initial rootless run proved
  that `newuidmap` is required by the generated subordinate ID mapping.
- `Dockerfile.base` installs `slirp4netns` because the next rootless run proved
  that it is required to configure the container network namespace.
- The existing `docker` executable, nested Docker daemon, Compose, and Buildx
  remain installed and functional.
- No Docker command, symlink, alias, socket, or environment variable is redirected
  to Podman.
- The built image exposes an executable `podman` command and reports its version.
- The normal workspace user, without `sudo`, successfully runs and removes a
  fully qualified hello-world container image with Podman.
- The successful smoke command does not rely on a manually prepared user home or
  machine-local Podman configuration outside the image.
- No Podman storage volume is added; Podman state may disappear when the
  devcontainer is recreated.
- No subordinate ID configuration or companion package is added without a
  recorded test failure that requires it.
- Existing Docker and devcontainer integration tests continue to pass.
- Source and release documentation describe Podman as an additional tool and do
  not claim that it replaces Docker.

## File Targets

- `Dockerfile.base`
- `tests/docker-build.sh`
- `tests/devcontainer-up.sh`
- `README.md`
- `README_release.md`
- `.oc_local/rules/devcontainer-kit.md`
- `docs/tasks/T021_install_podman_alongside_docker.md`

Additional files may be added only when an observed Podman smoke-test failure
demonstrates that the current target list is insufficient.

## Implementation Notes

- Preserve the existing `apt-get install --no-install-recommends` policy. Do not
  turn recommended packages into explicit dependencies before the runtime test
  proves they are needed.
- Use a fully qualified image reference so the smoke test cannot block on
  short-name resolution or an interactive registry choice.
- Run the functional smoke inside the real Dev Containers lifecycle, where the
  workspace user and current outer-container permissions match normal use.
- Capture the exact Podman failure before expanding scope. Record the command,
  relevant error, and resulting minimal change in this task's implementation
  notes or verification results.
- Keep Podman's default ephemeral per-user storage unless a later task defines a
  persistence contract.

## Implementation Plan

1. Add `podman` to the main APT package list in `Dockerfile.base`, run the real
   smoke test, and add `uidmap` and `slirp4netns` for their separately reproduced
   rootless runtime failures.
2. Extend the built-image smoke test with command-path and version checks.
3. Extend the real devcontainer smoke path to run a fully qualified hello-world
   image through Podman as the workspace user without `sudo`.
4. If the run fails, diagnose the exact failure and amend the implementation only
   with the smallest required package or configuration; do not apply the common
   rootless setup list speculatively.
5. Document the resulting proven Podman behavior in `README.md`,
   `README_release.md`, and the local toolchain rule while preserving Docker as
   the current default engine.
6. Run syntax, fast, image, Podman runtime, full integration, release-copy, and
   whitespace checks.
7. Record concrete verification results and set this task to `solved` only after
   both Podman hello-world and all existing Docker contracts pass.

## Verification

- `bash -n tests/docker-build.sh tests/devcontainer-up.sh`
- `task check`
- `task docker-build`
- Verify `command -v podman` and `podman --version` in the built image.
- In a real workspace container, as the workspace user, run
  `podman run --rm docker.io/library/hello-world` without `sudo`.
- Confirm `docker ps`, Docker Compose, and the existing nested Docker smoke paths
  still work.
- `task tests-run`
- `tests/release-build.sh`
- `git diff --check`

## Verification Results

- `bash -n tests/docker-build.sh tests/devcontainer-up.sh` passed.
- `task check` passed, including the focused release-copy contract test.
- `task docker-build` passed with Podman, `uidmap`, and `slirp4netns` installed
  from Debian Bookworm packages.
- The built-image smoke path found `/usr/bin/podman` and accepted
  `podman --version`.
- A direct privileged image probe ran
  `podman run --rm docker.io/library/hello-world` successfully as the image's
  normal `dev` user without `sudo`.
- `task tests-run` passed all generic devcontainer kit tests in 151 seconds. Its
  real `devcontainer up` path ran the same fully qualified hello-world image
  with Podman as the generated workspace user and retained the nested Docker
  smoke contract.
- `tests/release-build.sh` passed through `task check` and `task tests-run`.
- `git diff --check` passed.
- No Podman API service, Docker redirection, persistent Podman volume, explicit
  storage driver, or subordinate-ID configuration was added.

## Cancellation Reason

Not cancelled.
