# ADR-003: Worktrees share one development database, and the dev server is on the network

## Status
Accepted

## Date
2026-08-03

## Context
Several agents and Klaus work in parallel, each in a Git worktree. A fresh
empty database in every worktree is a bad test: real entries, pictures and
comments are what show a change working. Mobile first means a phone must
reach the development server.

## Decision
Every worktree shares the main checkout's `texttile_dev.db`, its
`priv/uploads` and its `.env`. The development server listens on the network
address, not on `localhost`, so a phone in the same network reaches it.
`bin/dev-host` prints the address that gets picked; `DEV_HOST` replaces it.

Port 4000 belongs to Klaus and to `make start`. Tests use 4440 through
`TEST_PORT`. Agents start their own servers on 4441 to 4449 and kill only a
PID they captured at spawn.

## Alternatives Considered

### A database per worktree
- Pros: no agent can hurt another agent's data
- Cons: every worktree starts empty, and a snapshot would need pulling per
  worktree
- Rejected: an empty database hides the defects that real data shows

## Consequences
- The shared database is real data. An agent removes only the records its own
  run created, through the application or by exact identifier. Never a
  wholesale delete.
- Never kill by pattern: several servers run on this machine at once and
  every process carries the worktree path in its argv.
- `make db-pull` fetches a consistent staging snapshot to the shared checkout
  root for a realistic database.

## Sources
- #4 "Share the dev database across all worktrees"
- #16 "The development server runs on the network address"
- `AGENTS.md`, "The three ways to hurt yourself" and "Dev servers"
