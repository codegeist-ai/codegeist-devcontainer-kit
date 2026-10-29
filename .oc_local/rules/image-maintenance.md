# Image Maintenance

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
