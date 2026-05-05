# Submodule Editing Policy

Do not edit the checked-out `.devcontainer/` or `.opencode/` submodule trees
directly during normal project work.

## Why

- `.devcontainer/` and `.opencode/` are reusable shared repositories mounted
  into this project as submodules.
- Direct edits inside those paths create detached submodule changes that are
  easy to miss when committing the parent repository.
- Project-specific behavior belongs in parent-repo overlays such as
  `.oc_local/`, root scripts, tests, and docs.

## Required Approach

- Put project-specific OpenCode commands, rules, and skills under `.oc_local/`.
- Put project-specific devcontainer behavior in parent-repo files or local
  overlay inputs instead of modifying `.devcontainer/` directly.
- If shared submodule behavior truly must change, stop and ask first. Treat it
  as explicit submodule work that needs its own review, test, commit, and parent
  gitlink update.

## Applies To

- `.devcontainer/`
- `.opencode/`
