# Audit Mutable Toolchain Inputs

- ID: `T004`
- Type: `chore`
- Status: `open`
- Parent: `none`
- Public Tracking: `pending issue creation`
- Contribution Level: `intermediate`
- Effort: `medium`

## Goal

Inventory mutable build-time installer and package inputs, assess their
reproducibility risks, and define a small set of focused improvements that can be
implemented and reviewed independently.

## Context

`Dockerfile.base` currently combines explicitly versioned downloads with
`releases/latest` assets, scripts fetched from `main`, unversioned npm and pip
packages, moving APT repositories, and installers executed from network pipes.
Tests verify the resulting tools, but the repository has no complete input
inventory, integrity classification, or documented update policy. This audit and
its proposed improvements remain unimplemented.

## Acceptance Criteria

- A repo-owned document inventories every network-fetched image-build input in
  `Dockerfile.base`, including its source, current selector, architecture
  assumptions, available integrity mechanism, and existing verification.
- Inputs are classified consistently as immutable, version-selected, or mutable.
- The audit prioritizes risks without claiming the complete image is
  reproducible when APT repositories or other moving sources remain.
- The audit proposes a bounded first set of improvements, with an update method
  and focused verification strategy for each proposal.
- Proposed improvements are split into reviewable follow-up tasks or Issues
  rather than a single bulk pinning change.
- Existing intentional choices, including tools that currently follow latest
  upstream channels, are identified instead of silently reclassified as defects.

## Files

- `Dockerfile.base`
- `tests/docker-build.sh`
- `README.md`
- `README_release.md`
- `docs/`

## Non-Goals

- Pinning, upgrading, or replacing packages and installers as part of the audit.
- Generating a lockfile for Debian APT repositories.
- Claiming bit-for-bit image reproducibility.
- Running or publishing a release.

## Verification

- Compare the inventory against every URL, package-manager install, and external
  repository declaration in `Dockerfile.base`.
- Confirm each proposed improvement names an update path and deterministic
  focused check.
- Run `task check` for documentation and release-contract validation.
- Confirm no Dockerfile, installer, package selector, or runtime behavior changed
  while completing the audit.
