# Add A Read-Only Release Preview

- ID: `T003`
- Type: `feature`
- Status: `open`
- Parent: `none`
- Public Tracking: https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues/4
- Contribution Level: `intermediate (help wanted)`
- Effort: `medium`

## Goal

Let contributors materialize and inspect the exact runtime-only release tree
without creating a commit, updating a Git ref, or publishing a branch.

## Context

The current `scripts/release-build.sh` owns the runtime file manifest and creates
the generated release commit after the heavyweight release gate. The focused
release test exercises that workflow in a temporary fixture, but there is no
contributor command that only writes a preview tree. This capability remains
unimplemented.

## Acceptance Criteria

- A documented command writes the release tree to an explicit temporary or
  caller-selected directory without changing repository refs or commits.
- Preview and publication use one canonical runtime manifest; file lists are not
  duplicated in separate implementation paths.
- The preview maps `Dockerfile.base` to `Dockerfile` and `README_release.md` to
  `README.md` exactly like release publication.
- A deterministic test compares preview contents and paths with the existing
  release assembly contract.
- Existing maintainer-only publication and full-suite verification gates remain
  unchanged.

## Files

- `Taskfile.yaml`
- `scripts/release-build.sh`
- `tests/release-build.sh`
- `README.md`
- `CONTRIBUTING.md`

## Non-Goals

- Publishing the `release` branch.
- Weakening the clean-`main` or full-suite release gate.
- Building the devcontainer image during preview.

## Verification

- Run the new focused preview test.
- Run `task check`.
- Confirm `git status --short --branch` and relevant local refs are unchanged by
  the preview command.
