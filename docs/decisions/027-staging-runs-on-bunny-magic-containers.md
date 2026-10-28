# ADR-027: Staging runs on Bunny Magic Containers; Fly stays as a manual recovery configuration

## Status
Accepted

## Date
2026-10-17

## Context
Staging ran on Fly.io with one machine and a 3 GiB volume. The demo and
staging are real sites. One machine, never two (ADR-001), holds on every
host. The migration had to keep the data and the runtime secrets.

## Decision
`staging.texttile.blog` runs on Bunny Magic Containers. `bunny.json` records
the app, the single region (`DE`), the replica limit of one and the 4 GB
persistent volume, which preserves at least the Fly capacity in decimal GB.
The publish workflow deploys staging after it publishes a tested commit,
from that commit's immutable image tag (ADR-025). `scripts/deploy-bunny.py`
refuses unexpected replicas, regions, volume sizes or volume identities,
waits for the replacement pod and checks the pages over HTTPS.
`CLIENT_IP_HEADER=x-real-ip` reads the visitor address Bunny supplies.

The stopped Fly machine and its volume stay for recovery. `fly.toml` is a
manual recovery configuration, not an active deployment target, and the Fly
deploy workflow is disabled. `make db-pull` reads the backup API (ADR-023)
instead of Fly SSH.

## Alternatives Considered

### Stay on Fly
- The decision moved staging; the README keeps the Fly section for a
  separate installation and for recovery

### Two regions or a standby replica
- Rejected: a second machine answers out of a second, older database

## Consequences
- Never undeploy, scale down or recreate the Bunny app as a deployment
  step: Bunny does not guarantee volume reattachment after scaling down.
- Bunny volumes have no automatic backups; the pull backup is the backup.
- A deployment briefly stops the single instance while Bunny transfers the
  volume.

## Sources
- #75 "Move staging from Fly to Bunny"
- `README.md`, "Deploy staging on Bunny"; `bunny.json`; `scripts/deploy-bunny.py`
