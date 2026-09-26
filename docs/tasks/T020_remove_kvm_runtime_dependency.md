# Remove KVM Runtime Dependency

- ID: `T020`
- Type: `refactor`
- Status: `planned`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `d8c2c6cf-7c45-4342-b207-ba2dfe7de075`

## Goal

Remove the shared devcontainer runtime's explicit KVM configuration and host KVM
dependency while keeping the installed QEMU and related virtualization tools.
Keep privileged mode only because the current entrypoint starts a rootful nested
Docker daemon.

## Context

`docker-compose.yml` currently maps `/dev/kvm` into the workspace container and
adds the host KVM device group. `initialize.sh` supports that mapping by writing
`DEVCONTAINER_KVM_GID` into the generated `.devcontainer/.env` file. The QEMU
smoke test separately requires `/dev/kvm`, adds the device and group to its test
container, and boots Alpine with KVM acceleration.

The runtime also sets `privileged: true`. That setting is not required for the
explicit KVM device mapping. It is required by the current rootful
Docker-in-Docker design: `entrypoint.sh` starts `dockerd` inside the workspace
container, and the documented Docker DinD contract requires a privileged outer
container for normal operation.

Privileged mode grants broad host-device access and can therefore expose
`/dev/kvm` when the host provides it even after the explicit Compose device and
group entries are removed. This task removes the KVM configuration and startup
dependency; it does not claim to isolate KVM from an otherwise privileged
container. Preventing that access requires a separate nested-Docker architecture
change.

## Scope

In scope:

- Remove the explicit `/dev/kvm` device mapping and KVM group addition from the
  shared Compose runtime.
- Remove KVM GID discovery and `DEVCONTAINER_KVM_GID` generation from
  `initialize.sh`.
- Remove the corresponding environment cleanup and positive KVM assertions from
  the test helpers and runtime tests.
- Add negative assertions that Compose no longer requests an explicit KVM device
  or supplemental KVM group.
- Keep `privileged: true` and document that rootful Docker-in-Docker is its sole
  current justification.
- Convert the Alpine QEMU smoke test from KVM acceleration to TCG software
  emulation, without `--privileged`, `/dev/kvm`, or a KVM group.
- Keep QEMU, `qemu-kvm`, VM utilities, and related automation tools installed in
  `Dockerfile.base`.
- Update source, release, contributor, and local agent documentation to remove
  KVM as a runtime and test prerequisite.

Out of scope:

- Removing QEMU, `qemu-kvm`, cloud-image, networking, or VM automation packages
  from the image.
- Removing nested Docker or changing its user-visible behavior.
- Replacing rootful DinD with rootless Docker, a host Docker socket, a sidecar,
  or another container runtime.
- Removing `privileged: true` from the Compose service or DinD-specific test
  commands.
- Guaranteeing that `/dev/kvm` is inaccessible from the privileged workspace
  container.
- Editing generated release content directly in the `.devcontainer/` submodule.
- Publishing a release or changing Git history.

## Acceptance Criteria

- `docker-compose.yml` contains no explicit `/dev/kvm`, KVM group, `KVM_GID`, or
  `DEVCONTAINER_KVM_GID` configuration.
- Generated `.devcontainer/.env` files no longer contain
  `DEVCONTAINER_KVM_GID`.
- The resolved Compose container configuration has no explicit KVM device entry
  and no KVM-specific supplemental group.
- The workspace service remains privileged, with adjacent documentation stating
  that rootful Docker-in-Docker requires it.
- Existing nested Docker integration tests continue to prove that `dockerd`
  starts and is usable by the workspace user.
- The QEMU smoke test boots the pinned Alpine ISO with TCG software emulation and
  does not pass `--privileged`, `--device`, or `--group-add` to `docker run`.
- The QEMU smoke path has no `/dev/kvm` availability, permission, or nested
  virtualization prerequisite.
- `Dockerfile.base` continues to install the existing QEMU and VM utility
  packages, including `qemu-kvm`, `qemu-system-x86`, and `qemu-utils`.
- Source and release documentation accurately describe software-emulated QEMU
  usage and the retained DinD privilege boundary.
- No source file describes KVM as a required host facility for the standard
  runtime or test suite.

## Security Decision

Retain `privileged: true` for this task because `entrypoint.sh` starts a rootful
`dockerd` and the repository tests require nested Docker to remain functional.
Docker's official DinD documentation states that privileged mode is required for
Docker-in-Docker to function properly.

Do not replace the setting with an unverified capability list. A rootful Docker
daemon needs namespace, mount, cgroup, networking, iptables, and storage-driver
operations that are intentionally broad and vary with the host. Rootless Docker
or a remote daemon could change that boundary, but either option changes image,
entrypoint, persistence, networking, and test contracts and therefore needs a
separate task.

The retained privilege means removal of explicit KVM Compose entries reduces
configuration coupling and eliminates startup failure on hosts without
`/dev/kvm`; it is not a device-denial security control.

## File Targets

- `docker-compose.yml`
- `initialize.sh`
- `tests/helpers.sh`
- `tests/initialize.sh`
- `tests/compose-config.sh`
- `tests/qemu-alpine-smoke.sh`
- `tests/docker-build.sh`
- `README.md`
- `README_release.md`
- `CONTRIBUTING.md`
- `.oc_local/rules/devcontainer-kit.md`
- `.oc_local/rules/software-tests.md`
- `docs/tasks/T020_remove_kvm_runtime_dependency.md`

## Implementation Plan

1. Remove the KVM device, supplemental group, related Compose comments, and KVM
   GID generation while retaining and clarifying privileged DinD operation.
2. Update initializer and Compose contract tests to assert the absence of
   generated KVM state and explicit KVM runtime configuration.
3. Change the Alpine QEMU smoke test to TCG acceleration, remove all KVM and
   privileged test arguments, and adjust its timeout only if measured software
   emulation requires it.
4. Keep direct built-image assertions for QEMU executables so package retention
   remains independently visible even if the boot smoke test fails early.
5. Rewrite source, release, contributor, and agent guidance around QEMU software
   emulation, the removed KVM prerequisite, and the retained DinD privilege
   boundary.
6. Run focused syntax and contract checks, the TCG smoke test, the full
   integration suite, release-copy verification, and whitespace validation.
7. Record concrete verification results and set this task to `solved` only after
   all required checks pass.

## Verification

- `bash -n initialize.sh tests/helpers.sh tests/initialize.sh tests/compose-config.sh tests/qemu-alpine-smoke.sh tests/docker-build.sh`
- `task check`
- `tests/initialize.sh`
- `tests/compose-config.sh`
- `task qemu-alpine-smoke`
- `task tests-run`
- `tests/release-build.sh`
- `git diff --check`
- Inspect resolved container configuration to confirm no explicit `/dev/kvm`
  device or KVM-specific supplemental group is requested.
- Inspect the built image to confirm `qemu-system-x86_64`, `qemu-img`, and the
  retained QEMU packages remain available.

## Verification Results

Not run; this task currently documents the agreed implementation plan only.

## Cancellation Reason

Not cancelled.
