---
description: Build and push the devcontainer release branch
agent: build
---
Build and push the runtime-only `release` branch for this repository, then move
the local `.devcontainer/` submodule checkout to the pushed release commit.

Always execute @.opencode/commands/save.md first so pending task work is
committed, rebased, and synchronized before the release branch is built. Only
after that save workflow finishes successfully, use the existing
`task release-build -- release --push` workflow. This repository publishes the
runtime artifact through the `release` branch, not through SemVer or Git release
tags.

Then:

1. Execute @.opencode/commands/save.md for the current task state and wait until
   it reports synchronized local and remote base branches.
2. Review `git --no-pager status --short --branch`.
3. Stop if the worktree is not clean.
4. Run `tests/release-build.sh`.
5. Run `task release-build -- release --push`.
6. Verify the remote release branch exists with
   `git ls-remote --heads origin refs/heads/release`.
7. Verify the release branch commit contains only runtime files with
    `git ls-tree -r --name-only release`.
8. Verify the release branch publishes the consumer guide as its primary README
   with `git show release:README.md` and compare it to `README_release.md`.
9. Record the pushed release commit with
   `git rev-parse release` and
   `git ls-remote --heads origin refs/heads/release`.
10. Update the local `.devcontainer/` submodule checkout to the pushed release.
11. Fetch the release branch inside the `.devcontainer` submodule with
    `git -C .devcontainer fetch origin release`.
12. Check out the just-pushed release commit in the `.devcontainer` submodule with
    `git -C .devcontainer checkout origin/release`.
13. Verify `.devcontainer` points at the same release commit with
    `git -C .devcontainer rev-parse HEAD`,
    `git submodule status .devcontainer`, and
    `git -C .devcontainer log -1 --format=%s`.
14. Verify the parent repository shows the expected `.devcontainer` gitlink
    change with `git --no-pager status --short --branch`.
15. Report the release branch name, local release commit, remote release commit,
    and the new `.devcontainer` submodule commit.

Do not create or push release tags.
Do not use SemVer selection for this repository's release workflow.
Do not start the release branch build until @.opencode/commands/save.md has
finished successfully.
Do not skip updating `.devcontainer/` to the just-pushed `origin/release` commit
after the release branch push succeeds.
Do not skip `tests/release-build.sh` before updating the release branch.
Do not update `.opencode/` as part of this workflow; the release commit belongs
to the `.devcontainer/` submodule.
Do not commit the `.devcontainer` gitlink automatically unless the user asks for
that commit explicitly.
