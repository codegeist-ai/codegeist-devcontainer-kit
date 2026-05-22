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
- Keep `yq`, `iproute2`, `iputils-ping`, `socat`, and `direnv` in the default
  image toolchain. They support YAML/config editing, network diagnostics,
  socket debugging, and `.envrc`-based project workflows without per-project
  installation. Do not add shell hooks for `direnv` by default.
- Keep Kubernetes and infrastructure administration tools in the default image:
  `kubectl`, `helm`, `k9s`, `talosctl`, `terraform`, and `ansible`. Install the
  CLI tools from their latest upstream channels unless the repository later
  records a version-pinning policy.
- Keep QEMU/KVM and related VM utility tools in the default image: `qemu-kvm`,
  `qemu-system-x86`, `qemu-utils`, `cloud-image-utils`, `bridge-utils`, `kmod`,
  `iptables`, `dnsmasq`, `cpio`, `sshpass`, `pwgen`, `expect`, and
  `tigervnc-viewer`. Verify QEMU with the Alpine ISO smoke test and keep that
  test KVM-only so the suite proves `/dev/kvm` works inside the container.
- When changing default image tools, update the matching documentation and smoke
  coverage if the tool is part of the documented development contract.

## Compose Overrides

- Keep `compose.local.yml` and `compose.local.yml.example` empty by default with
  `services: {}` unless a concrete local override is needed.
- Shared runtime behavior belongs in `docker-compose.yml` or generated
  `compose.local.gen.yml`; `compose.local.yml` is only the stable include point
  for local or consuming-repository customizations.
- Keep the `.devcontainer` and `.opencode` submodules configured with their
  `release` branches in `.gitmodules` so the shared update workflow can refresh
  both gitlinks non-interactively.

## Runtime Release Workflow

- Publish runtime artifacts through the `release` branch only. Do not use SemVer
  selection or Git release tags for this repository's release workflow.
- Before building the release branch, run the shared save workflow to completion
  so pending task work is committed, rebased, and synchronized on `main`.
- After save, require a clean worktree, rerun `task tests-run`, run
  `tests/release-build.sh`, then publish with
  `task release-build -- release --push`.
- After the release branch is pushed, update only the local `.devcontainer/`
  submodule checkout to `origin/release` and report the parent gitlink change;
  do not commit that gitlink automatically unless the user explicitly asks.
