# Release Build Workflow

Use this rule whenever creating or pushing the runtime release branch for this
repository.

## Command

- Prefer the local `/release-build` command from `.oc_local/commands/` for
  release branch work.
- The release command must use the repo task entrypoint:
  `task release-build -- release --push`.
- The release artifact is the orphan `release` branch, not a version tag.
- After the release branch is pushed, update the parent checkout's
  `.devcontainer` submodule to `origin/release` so the gitlink is ready for a
  follow-up commit.
- Do not create or push version tags for this repository.

## Branch Contract

- The first `release` branch commit must be orphaned from `main`.
- The release branch tree must contain only runtime files needed by consuming
  `.devcontainer` submodule checkouts.
- Later release branch commits may build on the existing `release` branch
  history, but must keep the tree runtime-only.
- Remove old local and remote `v*` version tags when migrating to this workflow.

## Verification

- Stop if the worktree is dirty before release creation.
- Verify no `v*` tags remain locally or on `origin` before release work.
- Run `tests/release-build.sh` before updating the release branch.
- After `task release-build -- release --push`, verify `origin/release` exists.
- Fetch `origin/release` in `.devcontainer`, check it out there, and verify the
  submodule commit matches the release branch.
- Verify the parent worktree only has the expected `.devcontainer` gitlink
  change after the release workflow completes.
