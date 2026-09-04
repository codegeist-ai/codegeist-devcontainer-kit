# Add OpenTofu CLI

- ID: `T007`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues/12`
- Tracking Key: `7f3c1a94-8b62-4e17-a5d9-2c4f6b81e730`

## Goal

Add the OpenTofu `tofu` CLI alongside Terraform in the shared devcontainer image
using the official OpenTofu Debian repository.

## Context

The base image already installs Terraform from HashiCorp's APT repository.
OpenTofu should be available as an additional infrastructure-as-code CLI without
removing or replacing the existing `terraform` command. Official OpenTofu
installation guidance for Debian-based systems uses signed repository metadata
and installs the `tofu` package.

## Scope

In scope:

- Configure the official signed OpenTofu APT repository in `Dockerfile.base`.
- Install the current `tofu` package alongside Terraform.
- Add image smoke coverage for both `tofu -version` and `terraform version`.
- Document OpenTofu availability and basic usage for source contributors and
  release consumers.
- Update the project-local default-toolchain rule to include OpenTofu.

Out of scope:

- Removing or replacing Terraform.
- Adding OpenTofu configuration, providers, state backends, credentials, or
  project-specific infrastructure workflows.
- Pinning an OpenTofu version outside the official APT repository policy.
- Creating or pushing release tags or selecting a SemVer release.

## Acceptance Criteria

- A newly built image exposes a working `tofu` command.
- `tofu -version` succeeds in the image smoke test.
- The existing `terraform` command remains installed and `terraform version`
  succeeds in the image smoke test.
- OpenTofu packages are installed from the official signed OpenTofu Debian
  repository rather than Debian's default package sources.
- Source and release documentation describe OpenTofu alongside Terraform and
  include a concise `tofu` usage example.
- Existing fast checks and the full image/runtime suite pass.

## Verification

- Run `git --no-pager diff --check`.
- Run `task check`.
- Run `tests/docker-build.sh` through the repository test harness or equivalent
  targeted setup.
- Run `task tests-run` because the base image toolchain changes.

## File Targets

- `Dockerfile.base`
- `tests/docker-build.sh`
- `README.md`
- `README_release.md`
- `.oc_local/rules/devcontainer-kit.md`
- `docs/tasks/T007_add_opentofu_cli.md`

## Dependencies

- Official OpenTofu Debian package repository and signing keys.
- Docker access for image-level verification.

## Implementation Notes

- Follow the official OpenTofu Debian installation contract and keep repository
  key material under `/etc/apt/keyrings`.
- Keep Terraform and OpenTofu as distinct native commands: `terraform` and
  `tofu`.
- Reuse the existing image package-installation style instead of adding a new
  wrapper script.

## Complexity Assessment

- Implementation complexity is low: extend one existing APT repository layer,
  add one package to the existing install transaction, and add two direct smoke
  commands.
- Verification cost is higher than the code complexity because changing the base
  image requires a Docker rebuild and the complete runtime suite.
- The two official OpenTofu signing keys are required by the upstream Debian
  installation contract. Add only the binary `deb` source because the image does
  not build OpenTofu from source packages.
- Do not add a version argument, installer wrapper, helper function, alias,
  separate package-install layer, provider setup, or Terraform/OpenTofu
  abstraction.

## Implementation Plan

1. Extend the existing third-party APT repository block in `Dockerfile.base`.
   Download the two official OpenTofu signing keys into `/etc/apt/keyrings`, make
   them readable, and add one binary repository entry for
   `https://packages.opentofu.org/opentofu/tofu/any/`. Add `tofu` next to
   `terraform` in the existing shared APT install transaction and update the
   Dockerfile contract header. Do not create another `RUN apt-get` layer.
2. Extend `tests/docker-build.sh` with direct `tofu -version` and
   `terraform version` commands in the existing command-availability smoke
   block. Assert successful execution only; do not pin or compare mutable
   version output.
3. Add one concise infrastructure-tool section to `README.md` and
   `README_release.md`. State that both native commands are available, show a
   minimal `tofu` example, and avoid migration, provider, backend, or state
   guidance.
4. Add `tofu` to the existing infrastructure-tool list in
   `.oc_local/rules/devcontainer-kit.md`. Do not create a new rule file.
5. Verify in increasing scope with `git --no-pager diff --check`, `task check`,
   the image build smoke path, and `task tests-run`. Record results in this task;
   publish the runtime-only release through the separate post-save release
   workflow.

## Verification Results

- `git --no-pager diff --check` and `bash -n tests/docker-build.sh` passed.
- `task check` passed, including the release-copy contract test.
- `task tests-run` passed after exercising the real image build, both IaC CLI
  smoke commands, and the complete generic devcontainer suite; the run finished
  in 448 seconds.
- A targeted check against `codegeist-devcontainer-kit:local` confirmed working
  `tofu` and `terraform` commands, installed `tofu` and `terraform` packages,
  and the official OpenTofu repository URL in the image APT source.
- GitHub Issue `#12` was closed with reason `completed`; read-back confirmed one
  complete canonical task block and exactly one matching Tracking Key.

## Open Questions

- `none`

## Cancellation Reason

- `none`
