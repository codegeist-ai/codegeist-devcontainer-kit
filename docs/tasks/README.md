# Task Docs

This directory stores lightweight, resumable task handoff files for this
repository.

## Conventions

- Top-level tasks use `TNNN_<slug>.md`, starting at `T001`.
- Child tasks live under the parent task directory in `tasks/` and use ids such
  as `T001_01`.
- A task is represented either by a standalone markdown file or by `task.md`
  inside a task directory, never both.
- Durable task documentation stays in English.

## Status Values

- `open` - task is ready for clarification, planning, or implementation.
- `specified` - scope and acceptance criteria are clarified.
- `planned` - implementation plan is recorded.
- `solved` - implementation and verification are complete.
- `finalized` - solved task has been reviewed for related docs and task state.
- `cancelled` - task is intentionally closed without implementation.
