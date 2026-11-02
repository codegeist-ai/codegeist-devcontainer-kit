# Image Maintenance

Maintain the image toolchain and review pinned software before runtime releases.

## Maintenance

- Keep `Dockerfile.base` tools on current compatible upstream releases and apply
  available security fixes; update hashes, asset names, smoke checks, and docs
  together.
- Distinguish a fixed dependency version from an available fixed tool release.
  Do not hand-patch bundled libraries in third-party binaries.
- Record remaining CVEs, including CRITICAL findings, when no compatible released
  fix exists. Those findings are not build or release blockers by themselves.
- Scan the actual built image for image conclusions. A running rootfs also
  includes runtime changes and mounts. Separate Nixpkgs source-lockfile and
  kernel-header findings from installed executable components.
- Keep unfixed findings visible in review reports. Do not add a blanket severity
  gate that contradicts this remediation policy.
- OpenCode can install npm dependencies after image creation. Assess those from
  generated lockfiles or installed packages; an image-only scan does not cover
  runtime downloads. T037 owns adding their required pre-release verification.

## Pinned-Version Review Before Release

Perform this review for every real runtime release, before `/save`, release
verification, or publication, including agent-invoked `task release:update`.
Use fresh upstream results for each release invocation. Disposable release test
fixtures do not trigger this review.

1. Derive the inventory from the current `Dockerfile.base` and its repo-owned
   installation inputs, not a separately maintained tool list. Include version
   ARGs, fixed npm/pip versions, versioned download URLs, base-image tags, and
   runtime-major constraints.
2. Check official vendor releases or package registries for newer stable versions
   with the required platform/architecture artifacts. Use the vendor's version
   scheme. Keep base images and runtimes on supported LTS tracks; consider
   non-LTS tracks only when explicitly requested. Check installed tools' runtime
   requirements before proposing a newer LTS major, and retain the current
   supported LTS when required tools do not support the newer one. Report the
   compatibility constraint instead of forcing the upgrade.
3. Show a compact `Tool | Current pin | Available stable version | Source` table.
   Report unavailable or ambiguous metadata as `unchecked`, never as up to date.
4. When updates or unchecked entries exist, ask which exact tool/version changes
   the user approves and how to handle unchecked entries. Wait for that decision
   before editing pins. A release request alone does not approve updates.
   Keep declined pins and continue the release with those versions. Include any
   unchecked entries in the question so the user can request further investigation
   or explicitly proceed with their existing pins. When all entries are checked
   and none has an update, report that result and proceed without an update prompt.
5. Apply only approved updates, including matching checksums, asset names, tests,
   and documentation. Keep exact pins for tools already pinned exactly. Then run
   the normal save and commit-bound release verification. If save/rebase changes
   pins, repeat the review for the affected entries before continuing.

Include the review results and approved, retained, or unchecked versions in the
release summary. Related workflow: `.oc_local/commands/release-build.md` and
`.oc_local/rules/release-build.md`.
