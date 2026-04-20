# codegeist-devcontainer-kit

Shared devcontainer kit intended to be checked out as `.devcontainer/` inside
`codegeist.ai` and related Codegeist repositories.

## Purpose

- keep the complete devcontainer surface in one dedicated repository
- let consuming repositories mount the kit directly as `.devcontainer/`
- preserve repo-local launchers such as `start.sh` in the consuming repository
- prepare the current `codegeist.ai/.devcontainer/` directory for a clean
  extraction into its own repository

## Current Contents

- `Dockerfile` - development image with Java 25, GraalVM, Maven, Docker tools,
  Nix, and supporting CLI tooling
- `docker-compose.yml` - compose-based devcontainer runtime definition
- `compose.local.yml.example` - tracked starter file for the ignored local
  compose overlay
- `devcontainer.json` - VS Code devcontainer entrypoint
- `entrypoint.sh` - Docker daemon bootstrap inside the workspace container
- `.env` - tracked compose defaults
- `.local.env.example` - local-only environment template
- `tests/` - launcher regression and devcontainer smoke tests

## Integration Model

This repository is intended to be added to a consuming repository as a Git
submodule or checked-out directory mounted at `.devcontainer/`.

The current files keep their existing relative-path assumptions, for example:

- `docker-compose.yml` uses `context: ..`
- `tests/devcontainer-smoke.sh` defaults to the parent repository root above
  `.devcontainer/`

That means the repository is intentionally designed to live at the consuming
repo path `.devcontainer/`, not as an arbitrary nested directory.

## Local Overrides

- `.local.env` is intentionally not tracked here
- consumers should create `.local.env` from `.local.env.example`
- managed worktree launchers may symlink `.devcontainer/.local.env` back to a
  root-local file in the consuming repository
- `compose.local.yml` is intentionally ignored so each checkout can add local
  compose overlays without touching the shared base file
- `start.sh` recreates `compose.local.yml` from
  `compose.local.yml.example` when it is missing

## Development Notes

- the repository uses a restrictive whitelist `.gitignore` so only the intended
  checked-in devcontainer files remain versioned
- `compose.local.yml.example` shows how a checkout can disable the OpenCode
  file watcher locally inside the container when bind-mounted workspace trees
  would otherwise keep `opencode` busy even while idle
- changes should stay focused on devcontainer behavior and not absorb unrelated
  consumer-repo workflow code such as project-specific `start.sh` launchers
