# Contributing To The Devcontainer Kit

Contributions improve the shared development environment used by Codegeist
repositories. Start with a GitHub Issue when proposing behavior, toolchain, or
workflow changes, and keep pull requests focused on one reviewable outcome.

## Repository Ownership

This repository owns the generic VS Code Dev Containers runtime, its image
toolchain, host-side initialization, shared runtime scripts, release assembly,
tests, and kit-specific documentation.

The `main` branch is the canonical source and contribution target. The
`release` branch is generated from reviewed source by `scripts/release-build.sh`
and contains only the runtime files consumed at `.devcontainer/`. Do not use a
generated `release` checkout, or a consuming repository's `.devcontainer/`
submodule checkout, as an implementation target.

## Contribution Workflow

1. Check the repository's [Issues](https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues)
   and [roadmap listing](https://github.com/users/codegeist-ai/projects/1) before
   starting overlapping work.
2. An Issue labeled `status:ready` must link its canonical local task under
   `docs/tasks/`. For a small unplanned fix, a maintainer may confirm that no new
   task is needed; state the reason in the pull request. Always use an existing
   task when one defines the work. Follow the [task guide](docs/tasks/README.md).
3. Make the smallest source change on a branch based on `main`.
4. Run the normal deterministic check:

   ```bash
   task check
   ```

5. Run `task tests-run` when changing the image, Dev Containers lifecycle,
   Docker/Compose behavior, QEMU, browser runtime, or another contract covered
   only by the broad integration suite.
6. Open a pull request that links the public Issue and applicable local task,
   explains the source and release impact, and records the verification performed.
   If no new task was required, state `No local task needed:` and the
   maintainer-approved reason.

`task check` validates shell syntax and focused source-to-release contracts. It
is non-interactive, does not build the image or start Docker, QEMU, Dev
Containers, or browsers, and does not publish or modify this repository's Git
history. Its focused release fixture copies only required source inputs into a
cleanup-trapped OS temporary directory, so the check leaves no repo-local test
directory, cache, log, or copied local state behind.

## Extension Boundaries

Keep shared, repository-agnostic runtime behavior in this source repository.
Consuming repositories should use `.codegeist/.local.env`,
`.codegeist/compose.local.yml`, and `.codegeist/Dockerfile` for documented
runtime extensions instead of editing `.devcontainer/`. New persistent secret
files belong under ignored `.codegeist/secrets/`, while new disposable artifacts
belong under the initializer-managed `.tmp` link. Project-specific OpenCode
behavior belongs in the consuming repository's `.oc_local/` overlay, not in its
`.opencode/` or `.devcontainer/` submodule.

Do not edit this source repository's nested `.devcontainer/` or `.opencode/`
submodules as part of ordinary kit work.

## Release Publication

Release publication is maintainer-only. Contributors should not run the
release-publishing workflow or push the generated `release` branch. Maintainers
publish only from clean, reviewed `main` after the full release verification
gate documented in `README.md` has passed.

## Shared Policies

Codegeist's account-wide policies apply here and are maintained centrally:

The visible [Codegeist personal account profile](https://github.com/codegeist-ai)
is sourced from
[`codegeist-ai/codegeist-ai`](https://github.com/codegeist-ai/codegeist-ai).
The separate [`codegeist-ai/.github`](https://github.com/codegeist-ai/.github)
repository remains the source for shared community defaults used here and in
other Codegeist repositories.

- [GitHub account and repository model](https://github.com/codegeist-ai/.github/blob/main/GITHUB_ACCOUNT_MODEL.md)
- [Code of Conduct](https://github.com/codegeist-ai/.github/blob/main/CODE_OF_CONDUCT.md)
- [Security Policy](https://github.com/codegeist-ai/.github/blob/main/SECURITY.md)
- [Support Policy](https://github.com/codegeist-ai/.github/blob/main/SUPPORT.md)

Do not report vulnerabilities in a public Issue; follow the shared Security
Policy.

## License

Contributions are provided under the repository's
[Zero-Clause BSD (`0BSD`) license](LICENSE).
