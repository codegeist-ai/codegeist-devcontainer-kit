# Document The Host Capability Matrix

- ID: `T002`
- Type: `docs`
- Status: `open`
- Parent: `none`
- Public Tracking: `pending issue creation`

## Goal

Add one concise host-capability matrix that tells contributors which local
capabilities are needed for the normal check, devcontainer use, and each broad
integration-test category.

## Context

The current README documents Docker, KVM, display forwarding, browsers, and QEMU
in their individual sections, but it does not provide one entry-point table for
contributors deciding which checks their host can run. This documentation task
is intentionally suitable for a first contribution and remains unimplemented.

## Acceptance Criteria

- The source README has one compact matrix covering `task check`, normal VS Code
  Dev Containers use, Docker-backed integration tests, KVM/QEMU tests, and
  visible browser tests.
- Each row distinguishes required host capabilities from optional capabilities
  and links to existing detailed sections instead of repeating them.
- The matrix does not promise support for an untested host, display transport,
  or virtualization configuration.
- Contributor documentation points to the matrix where host prerequisites are
  discussed.

## Files

- `README.md`
- `CONTRIBUTING.md`

## Non-Goals

- Changing the image, Compose configuration, or test behavior.
- Adding support for a new operating system or container runtime.
- Rewriting the existing detailed browser, QEMU, or test documentation.

## Verification

- Run `task check`.
- Review every matrix link from the rendered Markdown.
- Confirm every claimed capability is backed by an existing test or documented
  runtime contract.
