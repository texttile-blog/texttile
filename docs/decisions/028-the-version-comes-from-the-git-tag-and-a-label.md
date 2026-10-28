# ADR-028: The version comes from the Git tag, counted up by a pull request label

## Status
Accepted. Supersedes the version source of ADR-024.

## Date
2026-10-23

## Context
Every pull request had to raise the version in `mix.exs` (ADR-024), so two
open pull requests always collided on that line, and the order of the merges
decided who had to rebase.

## Decision
Nobody writes a version number into the code. The publish counts the version
itself: one step up from the newest `v<version>` tag, the patch number
unless the merged pull request carries the label `minor` or `major`. It sets
the tag on the merge commit before it builds and hands the number to the
image as `TEXTTILE_VERSION`, which `mix.exs` reads. A commit that is tagged
already keeps its number, so a re-run finishes the same version. Development
and the test suite run as `0.0.0`. The build argument is declared late in
the `Dockerfile` so a new number does not throw away the cached dependency
layers.

## Alternatives Considered

### Keep the number in `mix.exs`
- Rejected: the merge collision was the cost that motivated the change

### Conventional commits parsed for the bump
- Rejected: one label on the pull request is one decision in one place, set
  with `--label minor` and checked once more before the merge

## Consequences
- Settings shows the number of the build, and it is the only mark of which
  build runs.
- The label is part of opening a pull request: none for a repair, `minor`
  for a capability, `major` when behavior, stored data or configuration
  breaks.
- The five image tags and the never-moving exact tag of ADR-024 stay.

## Sources
- #79 "Take the version from the Git tag, not from mix.exs"
- `.github/workflows/publish.yml`, `mix.exs`, `Dockerfile`
