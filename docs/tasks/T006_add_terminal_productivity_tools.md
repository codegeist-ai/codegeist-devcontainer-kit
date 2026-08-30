# Add Terminal Productivity Tools

- ID: `T006`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues/11`
- Tracking Key: `6411db28-0778-41fb-b54f-46a9e721e79e`

## Goal

Add current upstream releases of Neovim, Gum, ripgrep, bat, btop, eza, dust,
and fzf to the shared devcontainer image so consuming repositories have a
modern terminal productivity toolset without project-local image extensions.

## Context

The image already installs Debian's `ripgrep` package, but it does not provide
the other requested commands. Debian Bookworm packages are older and Debian's
`bat` package exposes `batcat` rather than the upstream `bat` command. The
selected contract is therefore to install all eight tools from their latest
official upstream releases.

The installations should stay direct and reviewable. Each tool should use a
small shell command that downloads and installs its expected Linux x86_64
artifact. Do not introduce a generic asset-download function, Python helper,
version pin, or command symlink. Dynamic `latest` resolution intentionally means
that future image builds can receive newer upstream versions.

## Scope

In scope:

- Install `nvim`, `gum`, `rg`, `bat`, `btop`, `eza`, `dust`, and `fzf` from the
  latest official upstream GitHub releases.
- Remove Debian's `ripgrep` package so the image has one intentional `rg`
  installation.
- Use direct `releases/latest/download` URLs when the upstream asset name is
  stable.
- Use a short `curl` plus `jq` asset lookup when the latest artifact name
  contains its release version.
- Preserve Neovim's runtime files by installing its release tree under `/opt`
  and exposing its existing `bin` directory through `PATH`.
- Add focused image smoke coverage for all eight commands.
- Document purpose, typical usage, installation source, and relevant TTY or
  terminal constraints for source contributors and release consumers.

Out of scope:

- Adding shell aliases, replacing standard commands, or creating command
  symlinks.
- Installing Neovim plugins, configuration, themes, language servers, or user
  dotfiles.
- Enabling fzf keybindings or changing user-owned shell startup files.
- Adding gum-based project workflows or repository-specific interactive menus.
- Pinning release versions or adding an automated dependency update workflow.
- Publishing the generated `release` branch.
- Committing the currently pending `.devcontainer` parent gitlink update.

## Acceptance Criteria

- A newly built image exposes working `nvim`, `gum`, `rg`, `bat`, `btop`, `eza`,
  `dust`, and `fzf` commands.
- Each command comes from the latest official upstream release resolved during
  the image build, not from Debian's package version.
- `bat` is installed as the native upstream command without a `batcat` alias or
  symlink.
- The Dockerfile uses small tool-specific shell commands rather than a generic
  installer function or Python helper.
- Temporary release archives and extraction directories are removed in their
  installation layers.
- Image smoke coverage starts every command through a non-interactive version or
  headless invocation without asserting mutable version strings.
- Source and release documentation explain each tool, show concise usage
  examples, and identify interactive or terminal-specific behavior.
- Existing fast checks and the full image/runtime suite pass.

## Verification

- Run `git --no-pager diff --check`.
- Run `task check`.
- Run `tests/docker-build.sh` through the repository test harness or equivalent
  targeted setup.
- Run `task tests-run` because the base image toolchain changes.

## File Targets

- `Dockerfile.base`
- `tests/docker-build.sh`
- `README.md`
- `README_release.md`
- `docs/tasks/T006_add_terminal_productivity_tools.md`

## Dependencies

- GitHub release metadata and Linux x86_64 assets from the official upstream
  repositories for Neovim, Gum, ripgrep, bat, btop, eza, dust, and fzf.
- Docker access for image-level verification.

## Implementation Notes

- Resolve `latest` dynamically at image-build time; do not add version build
  arguments for these tools.
- Prefer fixed `releases/latest/download/<asset>` URLs where upstream publishes
  a stable asset filename. Otherwise select one exact Linux x86_64 asset URL
  from the latest-release JSON with `jq`.
- Keep each download, extraction, installation, and cleanup sequence local to
  its tool. Let `curl -f`, `jq -e`, `tar`, and `install` surface their native
  failures rather than wrapping every command in custom error handling.
- Install the complete Neovim distribution under `/opt/nvim` and add
  `/opt/nvim/bin` to the existing image `PATH`.
- Install upstream `bat` directly at `/usr/local/bin/bat`; do not install or
  link `batcat`.
- The image is already AMD64-specific in several upstream installation paths, so
  this task does not add a new multi-architecture abstraction.
- Keep interactive defaults untouched. `btop`, interactive `gum` commands, and
  `fzf` require a usable terminal when used interactively.
- The implementation uses stable latest-download URLs for Neovim, btop, and
  eza. Gum, ripgrep, bat, dust, and fzf use one short latest-release API asset
  lookup each because their archive filenames contain the release version.
- The existing system login profile also prepends `/opt/nvim/bin`; Debian login
  shells otherwise replace the Docker image `PATH` and hide the installed
  `nvim` command.

## Implementation Plan

1. Update the image contract in `Dockerfile.base`.
   Extend the header to name the terminal productivity tools and their dynamic
   upstream-release behavior. Remove `ripgrep` from the APT package transaction
   and prepend `/opt/nvim/bin` to `PATH` without replacing any existing path.
2. Install Neovim and Gum from their latest releases.
   Download Neovim's stable `nvim-linux-x86_64.tar.gz` latest-release asset,
   extract the complete tree into `/opt/nvim`, and remove the archive. Resolve
   Gum's versioned Linux x86_64 archive with a short latest-release API query,
   extract its executable into `/usr/local/bin`, and remove the archive.
3. Install the search and display tools.
   Resolve ripgrep's latest static x86_64 Linux archive and install `rg` into
   `/usr/local/bin`. Resolve bat's latest GNU x86_64 Linux archive and install
   its native `bat` binary directly. Download btop's stable x86_64 Linux Musl
   asset and install `btop`. Keep each sequence explicit and clean its temporary
   extraction directory immediately.
4. Install eza, dust, and fzf.
   Download eza's stable latest x86_64 GNU archive directly. Resolve dust's and
   fzf's versioned x86_64 Linux archives through small latest-release API
   queries. Extract and install only the expected executable from each archive,
   then remove temporary files.
5. Extend `tests/docker-build.sh` with one command-availability smoke block.
   Run `nvim` headlessly and invoke `--version` for `gum`, `rg`, `bat`, `btop`,
   `eza`, `dust`, and `fzf`. Do not compare exact version output because latest
   releases are intentionally mutable.
6. Document the terminal toolset in `README.md` and `README_release.md`.
   Explain each command's purpose and include concise examples for editing,
   interactive selection, text search, highlighted file output, resource
   monitoring, directory listing, disk-usage inspection, and fuzzy filtering.
   Document that eza icons require a suitable Nerd Font, dust can be expensive
   on large trees, and btop, gum, and fzf have interactive TTY paths. State that
   the kit installs commands side by side without aliases, standard-command
   replacement, shell integration, or user configuration.
7. Verify from narrowest to broadest scope.
   Run the diff check, fast checks, focused image smoke through the normal test
   harness, and the complete runtime suite. Preserve the existing uncommitted
   `.devcontainer` gitlink change and do not publish a release as part of T006.

## Verification Results

- `git --no-pager diff --check` passed.
- `task check` passed, including the release-copy contract test.
- `task tests-run` passed after exercising the real image build and all eight
  command smoke checks; the complete generic devcontainer suite finished in 120
  seconds.
- An initial full-suite attempt failed before the changed layers because the
  existing `scc` download received a transient connection reset. A later build
  exposed and corrected eza's `./eza` archive path and the final full run passed.

## Open Questions

- `none`

## Cancellation Reason

- `none`
