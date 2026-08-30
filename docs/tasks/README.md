# Task Docs

This directory stores lightweight, resumable task handoff files for this
repository. GitHub Issues are the public discussion and tracking entrypoint;
local task files retain implementation detail that is useful across sessions.

GitHub Mirror: https://github.com/codegeist-ai/codegeist-devcontainer-kit

## Conventions

- Top-level tasks use `TNNN_<slug>.md`, starting at `T001`.
- Child tasks live under the parent task directory in `tasks/` and use ids such
  as `T001_01`.
- A task is represented either by a standalone markdown file or by `task.md`
  inside a task directory, never both.
- Durable task documentation stays in English.
- New public-facing tasks include a `Public Tracking` field. Use `pending issue
  creation` until an Issue exists, then replace it with the Issue URL.

## Status Values

- `open` - task is ready for clarification, planning, or implementation.
- `specified` - scope and acceptance criteria are clarified.
- `planned` - implementation plan is recorded.
- `solved` - implementation and verification are complete.
- `finalized` - solved task has been reviewed for related docs and task state.
- `cancelled` - task is intentionally closed without implementation.

## Issue To Task To Pull Request

1. Open or identify a GitHub Issue for the public problem statement.
2. Create or update the local task specification with the Issue URL in `Public
   Tracking`, concrete acceptance criteria, file targets, non-goals, and
   verification.
3. Keep task status current as the work is specified, implemented, verified, or
   cancelled.
4. Link both the GitHub Issue and local task path from the pull request.
5. Let the pull request close the Issue when the accepted implementation is
   merged; update the local task to `solved` or `finalized` in the same change
   when appropriate.

A local task may be drafted before public tracking exists, but `pending issue
creation` means the contributor rollout is incomplete rather than privately
tracked forever.
