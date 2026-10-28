# ADR-009: A version holds the title and the body, and is made on deliberate actions only

## Status
Accepted

## Date
2026-08-06

## Context
Autosave writes the working copy every few seconds. A history made of
autosaves is noise. Tiles, tags, status and slug are shared and live between
both admins (ADR-008), so a version of them would restore a state nobody
ever saw together.

## Decision
A version is a full copy of the title and the body, nothing else
(`Texttile.Articles.Version`). It is made on a deliberate save, on a publish,
on a handover of the lock and before a restore. Never on an autosave, and
never when the text is byte-identical to the newest version. Autosave writes
the working copy and keeps no history. The Versions tab shows a word-level
diff and restores a version; the restore itself snapshots the text first.

## Alternatives Considered

### Version every autosave
- Rejected: hundreds of near-identical rows and a diff that shows typing, not
  edits

### Version the whole entry
- Rejected: tiles, tags and switches have one shared state; versioning them
  would be a lie

## Consequences
- The live version an entry points at (ADR-022) is one of these rows, so
  publishing is a version plus a pointer.
- A version diff shows real edits only, which is what ADR-007 pays for.
- Restoring never loses work: the pre-restore snapshot is a version too.

## Sources
- #10 "text-only versions with dedupe, restore with pre-restore snapshot"
- `AGENTS.md`, "How it works"
- `lib/texttile/articles/version.ex`
