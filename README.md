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
- `devcontainer.json` - VS Code devcontainer entrypoint
- `entrypoint.sh` - Docker daemon bootstrap inside the workspace container
- `launch.sh` - checked-in launcher implementation used by `../start.sh`
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
- tracked `.env` and `compose.local.yml` live in the consuming repository root
  so every managed worktree shares one checked-in overlay and one checked-in
  default env file

## Development Notes

- the repository uses a restrictive whitelist `.gitignore` so only the intended
  checked-in devcontainer files remain versioned
- changes should stay focused on devcontainer behavior and not absorb unrelated
  consumer-repo workflow code such as project-specific `start.sh` launchers
