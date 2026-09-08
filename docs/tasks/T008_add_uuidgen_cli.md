# Add uuidgen CLI

- ID: `T008`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues/13`
- Tracking Key: `2b86d449-31de-4f3b-ae07-640c4769271a`

## Goal

Add the `uuidgen` CLI to the shared devcontainer image through Debian's
`uuid-runtime` package.

## Context

The shared image does not currently provide `uuidgen`. Debian Bookworm ships the
command in the `uuid-runtime` package, so it can be added to the existing APT
installation transaction without another repository or installer.

## Scope

In scope:

- Install Debian's `uuid-runtime` package in the shared image.
- Add image smoke coverage that generates and validates a UUID.
- Document `uuidgen` availability for source contributors and release consumers.
- Update the project-local default-toolchain rule.

Out of scope:

- Running or configuring `uuidd` as a persistent service.
- Adding UUID libraries, wrappers, aliases, or project-specific generation
  workflows.
- Pinning a package version outside the Debian Bookworm repository policy.
- Publishing the generated `release` branch.

## Acceptance Criteria

- A newly built image exposes a working `uuidgen` command.
- The image smoke test generates a UUID with the expected canonical text shape.
- `uuid-runtime` is installed through the existing Debian APT transaction.
- Source and release documentation mention `uuidgen` and show concise usage.
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
- `docs/tasks/T008_add_uuidgen_cli.md`

## Dependencies

- Debian Bookworm's `uuid-runtime` package.
- Docker access for image-level verification.

## Implementation Notes

- Add `uuid-runtime` to the existing shared APT install transaction; do not add
  another package-install layer or third-party repository.
- Verify observable `uuidgen` output without pinning the Debian package version.
- Treat the packaged `uuidd` daemon as an unused package component; this task
  only promises the `uuidgen` CLI.

## Complexity Assessment

- Implementation complexity is low because Debian already packages the command.
- Verification cost is higher than the code change because the base image must
  be rebuilt and the complete runtime suite exercised.

## Implementation Plan

1. Update `Dockerfile.base` without adding another image layer or package
   source. Add `uuid-runtime` to the existing Debian APT transaction and update
   the file header so UUID generation is part of the documented image contract.
2. Extend the existing command-availability block in `tests/docker-build.sh`.
   Generate one default random UUID with `uuidgen` and validate its canonical
   lowercase hexadecimal `8-4-4-4-12` text shape. Do not assert a package
   version or depend on the `uuidd` service.
3. Add a concise UUID-generation section to `README.md` and
   `README_release.md`. State that Debian's `uuid-runtime` package provides the
   command, show a minimal `uuidgen` invocation, and avoid library, daemon, or
   application-specific guidance.
4. Add `uuidgen` to the existing default-toolchain contract in
   `.oc_local/rules/devcontainer-kit.md`. Do not create another rule file.
5. Verify in increasing scope with `git --no-pager diff --check`, shell syntax
   for the changed smoke test, `task check`, and `task tests-run`. Record the
   final results in this task.
6. After all verification succeeds, close GitHub Issue `#13` with reason
   `completed`, read back its state and canonical linkage, and change this task
   to `solved`. Leave runtime release publication to the separate release
   workflow.

## Verification Results

- `git --no-pager diff --check` and `bash -n tests/docker-build.sh` passed.
- `task check` passed, including the release-copy contract test.
- `task tests-run` passed after rebuilding the image, exercising the `uuidgen`
  output check, and running the complete generic devcontainer suite; the run
  finished in 438 seconds.
- A targeted check against `codegeist-devcontainer-kit:local` confirmed that
  `uuid-runtime` is installed and `uuidgen` emits the expected canonical UUID
  text shape.
- GitHub Issue `#13` was closed with reason `completed`; read-back confirmed one
  complete canonical task block and exactly one matching Tracking Key.

## Open Questions

- `none`

## Cancellation Reason

- `none`
