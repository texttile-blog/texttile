# ADR-025: The publish and the deploy start from a green CI run of the same commit

## Status
Accepted

## Date
2026-08-14

## Context
A push to `main` started CI, the deploy and the publish at the same second.
The two shorter runs finished first, so a red test suite once reported a
build that staging already ran and that the registry carried under a
version tag that never moves (ADR-024).

## Decision
The publish is a `workflow_run` on the finished CI run, and it stops unless
that run reports success on a push to `main`. It checks out the commit CI
passed on (`head_sha`), not the head of the branch, which the event points
at. A hand-started run still publishes: the person starting it stands for
the build. The staging deploy runs after the publish, from the same
immutable image tag (ADR-027). Publishes of different commits run side by
side under a concurrency group per commit, because a shared group cancels
the waiting run and lost two builds in a minute (#82).

## Alternatives Considered

### One workflow that tests, publishes and deploys in sequence
- Rejected: the test job is the long one and would be duplicated or coupled
  to the registry login

### Publish on tag push by hand
- Rejected: every merge to `main` that passes CI is a build; nobody tags by
  hand

## Consequences
- An image tag stands for good, so a commit that fails the suite never
  carries a number.
- A red CI publishes nothing, and the README says that a broken version
  stays broken.
- Every published build also gets a GitHub release with the pull requests
  since the one before (#50).

## Sources
- #56 "The deploy and the publish wait for a green CI"
- #82 "Let publishes of different commits run side by side"
- `.github/workflows/publish.yml`
