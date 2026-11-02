---
description: Build and push the devcontainer release branch
agent: build
---
Build and push the runtime-only `release` branch for this repository, then move
the local `.devcontainer/` submodule checkout to the pushed release commit.

First complete the pinned-version review in @.oc_local/rules/image-maintenance.md.
Wait for any update or unchecked-entry decisions required by that review.
Then execute @.opencode/commands/save.md so approved updates and pending task work
are committed, rebased, and synchronized before the release branch is built. Only
after that save workflow finishes successfully, use the existing
`task release:update -- release --push` workflow. This repository publishes the
runtime artifact through the `release` branch, not through SemVer or Git release
tags.

Then:

1. Review the current image's explicit software pins against fresh official
   upstream metadata as required by `image-maintenance.md`. Show the version table,
   resolve update/unchecked-entry decisions, and apply only approved updates.
2. Execute @.opencode/commands/save.md for the current task state and wait until
   it reports synchronized local and remote base branches.
   If save/rebase changes pins, review the affected entries again before continuing;
   save any resulting approved edits before release verification.
3. Review `git --no-pager status --short --branch`.
4. Stop if the worktree is not clean.
5. Run the full verification suite again with `task tests-run`. Confirm its real
   browser smoke starts non-headless Chrome over loopback X11 with matching
   Xauthority state shaped like Remote SSH forwarding.
6. Run `tests/release-build.sh`.
7. Confirm `tea login list` contains the Gitea login, repair its persistent Git
   integration with `tea login helper setup`, and run
   `task release:update -- release --push`. The release script suppresses Askpass
   and uses only Tea's host-specific credential helper for the Gitea push.
8. Verify the remote release branch exists with
   `GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false git -c
   http.sslVerify=false ls-remote --heads origin refs/heads/release`.
9. Verify the release branch commit contains only runtime files with
     `git ls-tree -r --name-only release`.
10. Verify the release branch publishes the consumer guide as its primary README
    with `git show release:README.md` and compare it to `README_release.md`.
11. Record the pushed release commit with
    `git rev-parse release` and
    `GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false git -c
    http.sslVerify=false ls-remote --heads origin refs/heads/release`.
12. Update the local `.devcontainer/` submodule checkout to the pushed release.
13. Fetch the release branch inside the `.devcontainer` submodule with
     `GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false git -c
     credential.helper= -C .devcontainer fetch origin release`. This public
     GitHub fetch is intentionally anonymous and does not use Tea.
14. Check out the just-pushed release commit in the `.devcontainer` submodule with
     `git -C .devcontainer checkout origin/release`.
15. Verify `.devcontainer` points at the same release commit with
     `git -C .devcontainer rev-parse HEAD`,
     `git submodule status .devcontainer`, and
     `git -C .devcontainer log -1 --format=%s`.
16. Verify the parent repository shows the expected `.devcontainer` gitlink
     change with `git --no-pager status --short --branch`.
17. Report the pinned-version review and user decisions, release branch name,
     local release commit, remote release commit, and the new `.devcontainer`
     submodule commit.

Do not create or push release tags.
Do not use SemVer selection for this repository's release workflow.
Do not skip the pinned-version review or treat release authorization as approval
to update tool versions.
Do not start the release branch build until @.opencode/commands/save.md has
finished successfully.
Do not skip `task tests-run` after the save workflow and clean-worktree check;
release builds must always retest the current saved state before publishing.
Do not continue unless `.test-tmp/release-verification` matches the current commit
and contains `suite-isolated-network=passed`; `scripts/release-build.sh` also
enforces this gate.
Do not skip updating `.devcontainer/` to the just-pushed `origin/release` commit
after the release branch push succeeds.
Do not skip `tests/release-build.sh` before updating the release branch.
After the shared save step, do not update `.opencode/` as part of release
publication; the release commit belongs to the `.devcontainer/` submodule.
Do not commit the `.devcontainer` gitlink automatically unless the user asks for
that commit explicitly.
