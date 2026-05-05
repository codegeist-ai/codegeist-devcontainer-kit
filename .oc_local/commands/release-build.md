---
description: Build and push the next devcontainer release tag
agent: build
---
Build and push a runtime-only devcontainer release tag for this repository.

Use the existing `task release-build -- <tag> --push` workflow. Do not create
Git tags manually.

Then:

1. Review `git --no-pager status --short --branch`.
2. Stop if the worktree is not clean.
3. Fetch remote tags with `git fetch origin --tags`.
4. Check whether `HEAD` already has a normal SemVer tag:
   `git tag --points-at HEAD --list 'v[0-9]*.[0-9]*.[0-9]*'`.
5. If `HEAD` already has one or more matching tags, pick the highest SemVer tag
   on `HEAD` and do not create another tag for the same commit.
6. If the selected existing tag is missing on `origin`, push only that tag with
   `git push origin <tag>`.
7. If the selected existing tag is already on `origin`, report that there is
   nothing to release.
8. If `HEAD` has no matching tag, determine the latest existing SemVer tag with
   `git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*'`.
9. Inspect the commits and diff since the latest tag:
   `git log <last-tag>..HEAD --oneline` and `git diff <last-tag>..HEAD`.
10. Choose the next tag according to `.opencode/rules/semver.md` and
    `.oc_local/rules/release-build.md`.
11. Verify the chosen tag does not exist locally and does not exist on `origin`.
12. Run `tests/release-build.sh`.
13. Run `task release-build -- <next-tag> --push`.
14. Verify the remote tag exists with
    `git ls-remote --tags origin refs/tags/<next-tag> refs/tags/<next-tag>^{}`.
15. Fetch tags inside the `.devcontainer` submodule with
    `git -C .devcontainer fetch origin --tags`.
16. Check out the release tag in the `.devcontainer` submodule with
    `git -C .devcontainer checkout <next-tag>`.
17. Verify `.devcontainer` points at the release tag with
    `git submodule status .devcontainer` and
    `git -C .devcontainer describe --tags --exact-match HEAD`.
18. Verify the parent repository shows the expected `.devcontainer` gitlink
    change with `git --no-pager status --short --branch`.
19. Report the tag name, tag object, release commit, parent commit, pushed
    remote, and the new `.devcontainer` submodule commit.

Do not infer a release when the worktree is dirty.
Do not create a second release tag for a commit that already has a SemVer tag.
Do not skip `tests/release-build.sh` before creating a new tag.
Do not commit the `.devcontainer` gitlink automatically unless the user asks for
that commit explicitly.
