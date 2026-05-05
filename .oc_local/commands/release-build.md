---
description: Build and push the devcontainer release branch
agent: build
---
Build and push the runtime-only `release` branch for this repository.

Use the existing `task release-build -- release --push` workflow. This repository
publishes the runtime artifact through the `release` branch, not through SemVer
or Git release tags.

Then:

1. Review `git --no-pager status --short --branch`.
2. Stop if the worktree is not clean.
3. Run `tests/release-build.sh`.
4. Run `task release-build -- release --push`.
5. Verify the remote release branch exists with
   `git ls-remote --heads origin refs/heads/release`.
6. Verify the release branch commit contains only runtime files with
   `git ls-tree -r --name-only release`.
7. Fetch the release branch inside the `.devcontainer` submodule with
   `git -C .devcontainer fetch origin release`.
8. Check out the release branch in the `.devcontainer` submodule with
   `git -C .devcontainer checkout origin/release`.
9. Verify `.devcontainer` points at the release branch with
   `git submodule status .devcontainer` and
   `git -C .devcontainer log -1 --format=%s`.
10. Verify the parent repository shows the expected `.devcontainer` gitlink
    change with `git --no-pager status --short --branch`.
11. Report the release branch name, local release commit, remote release commit,
    and the new `.devcontainer` submodule commit.

Do not create or push release tags.
Do not use SemVer selection for this repository's release workflow.
Do not skip `tests/release-build.sh` before updating the release branch.
Do not commit the `.devcontainer` gitlink automatically unless the user asks for
that commit explicitly.
