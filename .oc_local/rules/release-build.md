# Release Build Workflow

Use this rule whenever creating or pushing release tags for this repository.

## Command

- Prefer the local `/release-build` command from `.oc_local/commands/` for
  release tag work.
- The release command must use the repo task entrypoint:
  `task release-build -- <tag> --push`.
- After a new release tag is pushed, update the parent checkout's
  `.devcontainer` submodule to that exact tag so the gitlink is ready for a
  follow-up commit.
- Do not create or push release tags manually when the command is available.

## Existing Tags

- Before choosing a new version, check whether the current `HEAD` already has a
  normal SemVer tag matching `vX.Y.Z`.
- If `HEAD` already has a matching release tag, do not create another tag for
  the same commit.
- If that tag exists locally but not on `origin`, push the existing tag instead
  of creating a new one.
- If the tag already exists locally and remotely, report that there is nothing
  to release.

## Choosing The Next Tag

- Start from the latest normal SemVer tag in Git.
- Inspect commits and the diff since that tag before choosing the increment.
- Choose the smallest honest SemVer increment:
  - `PATCH` for fixes, tests, docs, build or release workflow fixes,
    `.gitignore` changes, and submodule gitlink updates.
  - `MINOR` for backwards-compatible runtime capabilities that consumers can
    adopt without migration.
  - `MAJOR` for breaking runtime behavior, removed files, renamed entrypoints,
    or changed defaults that require consumer migration.
- When several changes exist, choose the highest required increment.

## Verification

- Stop if the worktree is dirty before release creation.
- Run `tests/release-build.sh` before creating a new tag.
- After `task release-build -- <tag> --push`, verify the tag exists on `origin`.
- Fetch tags in `.devcontainer`, check out the new tag there, and verify the
  submodule is exactly on that tag.
- Verify the parent worktree only has the expected `.devcontainer` gitlink
  change after the release workflow completes.
