# ADR-023: The backup pulls; the server holds nothing that reaches the copies

## Status
Accepted

## Date
2026-08-10

## Context
The installation is one directory (ADR-001), so a backup is a copy of it. A
push to an object store needs a credential on the server, and whoever breaks
into the server then holds the key to the copies. Renditions are made again
on demand (ADR-005) and often make up half of what travels.

## Decision
Texttile is backed up by pulling. A machine the owner keeps (a Raspberry Pi,
a NAS) fetches the whole installation on a clock of its own and holds the
token; the server holds nothing that reaches the copies. Three read-only
endpoints under `/backup` want `Authorization: Bearer <token>`:
the manifest, one original by id, and a consistent copy of the database made
with `VACUUM INTO`. Never a token in the address line. Nothing takes a path
from the caller: an id is resolved against the database.

The token is shown once and stored as a hash. An address allowlist is a
second lock, never the first. While the feature is off, or the caller is not
allowed, all three answer 404 rather than 403. Every call is logged, and one
caller may fetch 600 times a minute. Every original carries a SHA-256 in the
database (`Texttile.Backup.Fingerprint`), taken once outside the write
transaction, so a manifest is a query and not a walk over the disk. The
rendition cache is never backed up.

`scripts/texttile-backup.sh` is the client: it archives instead of mirrors,
keeps the server's layout, copies the database last, rotates dated database
copies and verifies every file's hash before moving it into place.

## Alternatives Considered

### Push to S3-compatible storage
- Rejected: the server would hold a credential that can delete the copies

### Snapshot the volume at the host
- Rejected: Bunny volumes have no automatic backups, and a host snapshot
  ties the owner to the host

### A backup that mirrors deletions
- Rejected: a copy that faithfully repeats a deletion is no backup

## Consequences
- `make db-pull` reads the same API for development snapshots.
- The token opens a copy of the site: the blog password in clear, every
  password hash and session, every commenter's address. The README says so.
- A restore is a copy of `files/` and the newest database, then a start.

## Sources
- #41 "Pull the backup: a machine you keep fetches the whole installation"
- `lib/texttile/backup.ex`, `scripts/texttile-backup.sh`, `README.md`, "Backup"
