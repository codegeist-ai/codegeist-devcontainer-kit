# Project Test Verification

Use this rule when making code, script, or workflow changes in this repository.

## Normal Check

- Run `task check` as the normal deterministic verification before handing off
  changes. It covers shell syntax and focused source-to-release contracts
  without Docker, QEMU, browser, or Dev Containers builds.
- Keep the focused release fixture in a cleanup-trapped OS temporary directory
  and copy only its explicit source inputs. `task check` must not create
  `.test-tmp/` or copy ignored workspace state, caches, profiles, or logs.
- Run the complete `task tests-run` suite when changes affect the image, Dev
  Containers lifecycle, Docker/Compose behavior, QEMU, browser runtime, or
  another integration contract covered only by that suite.
- Targeted tests are still useful while iterating, but they do not replace a
  relevant final `task check` or broad-suite attempt.
- Do not run `docker system prune`, `docker builder prune`, or other Docker
  cleanup commands automatically before tests. If Docker storage is too tight,
  stop and ask for approval before pruning cache, images, containers, or volumes.
- If `task tests-run` cannot complete because the environment is blocked, for
  example Docker tmpfs exhaustion or missing host tooling, report the blocker
  explicitly and include the targeted tests that did pass.

## Reality Over CI Compatibility

- Prefer the real local command, service, device, protocol, and lifecycle path
  when the repository provides that integration. CI compatibility is not a
  project requirement by itself and does not justify replacing real behavior
  with a fake, mock, or weaker assertion.
- Do not create tests solely to make behavior runnable in CI. A test may require
  documented local prerequisites such as Docker, KVM, a display server, or the
  SSH-forwarded Pulse endpoint and should fail clearly when they are absent.
- Use a fake or mock only when it proves a distinct behavior that cannot be
  exercised safely or observably with the real dependency. Do not retain one
  merely for speed, non-interactivity, or hypothetical CI portability.
- Keep test side effects narrow and explicit. Real integration tests may create
  disposable containers, recordings, screenshots, or VM fixtures under the
  existing temporary test paths and must clean them after the run.
