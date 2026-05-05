---
description: Build and push the devcontainer release branch
agent: build
---
Build and push the runtime-only `release` branch for this repository.

Use the existing `task release-build -- release --push` workflow. Do not create
Git tags manually.

Then:

1. Review `git --no-pager status --short --branch`.
2. Stop if the worktree is not clean.
3. Verify no version tags remain locally with `git tag --list 'v*'`.
4. Verify no version tags remain on `origin` with
   `git ls-remote --tags origin 'refs/tags/v*'`.
5. Run `tests/release-build.sh`.
6. Run `task release-build -- release --push`.
7. Verify the remote release branch exists with
   `git ls-remote --heads origin refs/heads/release`.
8. Verify the release branch commit contains only runtime files with
   `git ls-tree -r --name-only release`.
9. Fetch the release branch inside the `.devcontainer` submodule with
   `git -C .devcontainer fetch origin release`.
10. Check out the release branch in the `.devcontainer` submodule with
    `git -C .devcontainer checkout origin/release`.
11. Verify `.devcontainer` points at the release branch with
    `git submodule status .devcontainer` and
    `git -C .devcontainer log -1 --format=%s`.
12. Verify the parent repository shows the expected `.devcontainer` gitlink
    change with `git --no-pager status --short --branch`.
13. Report the release branch name, local release commit, remote release commit,
    and the new `.devcontainer` submodule commit.

Do not create version tags.
Do not skip `tests/release-build.sh` before updating the release branch.
Do not commit the `.devcontainer` gitlink automatically unless the user asks for
that commit explicitly.
