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
