# Harden Docker Access for OpenCode

- ID: `T039`
- Type: `feature`
- Status: `specified`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `fcf195fb-108f-4f75-a655-bada1287ce95`

## Goal

Keep Docker usable from OpenCode while ensuring that workloads delegated to the
managed Docker daemon cannot bypass the outbound port policy established in T038.

## Context

`docker run`, builds, and related operations delegate work to a daemon that is
not a child of OpenCode. Restricting the Docker CLI process therefore does not
automatically restrict the resulting containers or BuildKit workers. The user
approved Docker hardening as a follow-up while retaining useful Docker and
ordinary `sudo` workflows.

## Scope

- Apply the effective `OPENCODE_ALLOWD_PORTS` policy to managed Docker containers
  and build execution initiated by OpenCode, including Docker/BuildKit networking
  that otherwise runs outside its process scope.
- Preserve approved `build`, `run`, and `exec` workflows. Inventory the kit's
  existing DinD, KVM, privileged test-container, and nested Dev Containers needs
  before defining supported profiles and documented restrictions.
- Control bypass options such as host/shared network namespaces, unrestricted
  privileges and capabilities, devices, critical host mounts, and access to an
  unrestricted Docker socket or alternate managed-daemon endpoint.
- Enforce controls at the actual Docker authority and network boundaries,
  regardless of whether requests use the Docker CLI or direct API calls.
- Protect the enforcement configuration from the managed OpenCode process tree,
  including elevated commands. Keep normal workspace and permitted administrative
  operations available.
- Fail closed when required policy or enforcement is missing or invalid, with
  actionable diagnostics and no unrestricted fallback.

Out of scope: a generic Docker platform rewrite, image vulnerability remediation,
control of arbitrary remote services reached over allowed ports, and release
publication during implementation.

## Acceptance Criteria

- Approved Docker build/run/exec workflows remain functional under the documented
  policy. Their workloads reach allowed ports and cannot reach forbidden ports
  over IPv4 or IPv6.
- The same result holds for build-step traffic, network/namespace selection,
  extra capabilities, privileged requests, and mount/socket-based bypass attempts.
  Unsupported unsafe modes are rejected explicitly rather than silently exempted.
- Direct Engine API access and relevant BuildKit interfaces cannot bypass rules
  enforced through the normal CLI path. A shell wrapper or client environment
  variable alone is not accepted as enforcement.
- The managed process tree cannot disable the controls or obtain an unrestricted
  managed-daemon endpoint through ordinary or elevated commands.
- DinD/KVM/privileged integration requirements have an explicit compatibility
  assessment and supported profiles or clear limitations; do not blindly apply
  blanket restrictions that make the kit's existing workflows unusable.
- Missing policy, unavailable enforcement, or undecidable authorization fails
  before the protected workload gains unrestricted access.
- Documentation identifies the trusted control plane, scope of managed Docker
  workloads, configuration, supported operations, and remaining limitations.

## Verification

- Exercise real Docker run/build/exec flows against reachable allowed and denied
  test endpoints over both address families, including required DNS/local access.
- Test direct API requests, BuildKit/build networking, host/shared networks,
  privilege/capability changes, critical mounts, and raw socket/alternate endpoint
  access. Include attempts made through `sudo`.
- Verify missing/invalid policy and unavailable enforcement reject workloads.
- Run relevant existing DinD/KVM/devcontainer tests, `task check`,
  `task tests-run`, and `git --no-pager diff --check` in isolated fixtures.

## File Targets

- Runtime policy helpers introduced by T038 and `cmds/oc`
- Docker daemon setup, `entrypoint.sh`, `Dockerfile.base`, `docker-compose.yml`
- `.local.env.example` and relevant task/runtime configuration
- Docker, BuildKit, OpenCode, and Dev Containers integration tests
- `README.md`, `README_release.md`, relevant runtime rules

## Dependencies

- [T038](T038_restrict_opencode_outbound_ports.md): port-policy semantics,
  protected process scope, and enforcement boundary.

## Blockers

None at specification time. Implementation follows T038 and must resolve the
documented privileged-workflow compatibility requirements before completion.

## Implementation Notes

Prefer the smallest mechanism that enforces the policy at a trusted boundary.
Treat command-line filtering and `DOCKER_HOST` selection as routing conveniences,
not security boundaries. Network enforcement must also cover the actual daemon
and build/container traffic; authorizing an API request does not inspect every
later action of its workload.

If evaluating Docker authorization plugins, account for their documented limits:
gRPC/BuildKit paths, non-JSON bodies, and upgraded/streamed connections are not
uniformly covered. Verify the selected mechanism against the installed versions:
[Docker authorization plugins](https://docs.docker.com/engine/extend/plugins_authorization/).
Preserve normal `sudo` use while preventing control-plane modification; do not
claim an unbypassable policy while retaining an unrestricted path to that plane.

## Cancellation Reason

Not cancelled.
