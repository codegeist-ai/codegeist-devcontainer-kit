# Devcontainer Kit Conventions

Use this rule when changing the reusable devcontainer runtime, toolchain, or
local override templates in this repository.

## Default Toolchain

- Keep Mermaid CLI (`@mermaid-js/mermaid-cli`, `mmdc`) in the default image
  toolchain. It supports repo-owned software documentation diagrams without
  requiring per-project installation.
- Keep `tiktoken-cli` in the default image npm toolchain. It supports AI and
  documentation workflows that need token counting without requiring
  per-project installation.
- When changing default image tools, update the matching documentation and smoke
  coverage if the tool is part of the documented development contract.

## Compose Overrides

- Keep `compose.local.yml` and `compose.local.yml.example` empty by default with
  `services: {}` unless a concrete local override is needed.
- Shared runtime behavior belongs in `docker-compose.yml` or generated
  `compose.local.gen.yml`; `compose.local.yml` is only the stable include point
  for local or consuming-repository customizations.
