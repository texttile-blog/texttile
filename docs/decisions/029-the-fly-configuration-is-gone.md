# ADR-029: The Fly configuration is gone; Bunny is the only host the repository knows

## Status
Accepted. Supersedes the Fly recovery part of ADR-027.

## Date
2026-10-28

## Context
ADR-027 moved staging to Bunny Magic Containers and kept `fly.toml` and a
README section as a way back. Staging has run on Bunny since then. The Fly
file, the README section and a few comments and examples still named Fly, so
a reader had to find out which host was real.

## Decision
`fly.toml` and the README section "Deploy on Fly.io" are removed. The rules
that hold on every host stay in the README, without Fly commands: one
machine, never two (ADR-001), and how big the machine must be for video.
Examples of `CLIENT_IP_HEADER` name `x-real-ip`, the header Bunny writes.

## Alternatives Considered

### Keep `fly.toml` as recovery
- Rejected: a configuration nobody deploys drifts from the image, and the
  recovery path is the backup (ADR-023), not a second host

## Consequences
- A way back to Fly starts from the Fly documentation and the README rules,
  not from a file in this repository.
- The Fly machine and volume are outside the repository. This record does
  not touch them.

## Sources
- ADR-027; `README.md`, "Get it running"; `bunny.json`
