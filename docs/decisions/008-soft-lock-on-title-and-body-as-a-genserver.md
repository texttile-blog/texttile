# ADR-008: The soft lock on title and body is a GenServer, and everything else stays free

## Status
Accepted

## Date
2026-08-06

## Context
Two people work on the same entry at the same time. This is the hero feature.
Two editors typing into the same body would overwrite each other; two admins
sorting tiles or editing tags rarely collide. A lock must survive a reload and
a short network drop, and a forgotten tab must not hold the text for ever.

## Decision
The title and the body are locked, and only softly: the holder writes, the
other one watches the text arrive live and can take over in one click. The
lock is one GenServer per open entry (`Texttile.Articles.Lock`), under a
Registry and a DynamicSupervisor of its own. Elixir's message ordering gives
mutual exclusion for free: no database locking, no retries. The process lives
only as long as its lock.

Releasing has three paths: explicit when the editor closes, process death
with a 45 second grace period, and a 15 minute idle timeout. A takeover asks
the holder to flush first: it saves what is in flight, snapshots a version
and answers within 3 seconds, or it is not waited for.

Tiles, tags, settings and publish controls stay free for both admins, last
write wins per field. The gallery is deliberately outside the lock: it is the
conflict-poor half of the editor.

## Alternatives Considered

### A lock column in the database
- Cons: no clean expiry on process death, a stale row after a crash, and
  polling to notice a change
- Rejected: the GenServer dies with the editor and the registry forgets it

### Operational transformation or CRDT merging of the body
- Pros: both could type at once
- Cons: a merge rewrites the writer's text, which breaks the byte-for-byte
  promise (ADR-007), and the weight of the machinery is out of proportion for
  two people who trust each other
- Rejected: one writes, one watches, one click takes over

### Lock the whole entry
- Rejected: the gallery, tags and switches would wait for nothing

## Consequences
- The lock lives beside the database, not in it. Tests clear it explicitly.
- The holder's keystrokes travel over PubSub to the watcher's read-only view.
- The admin area shows who is on which screen, so a takeover is never a
  surprise.
- Any new field of an entry has to decide: behind the lock (text only) or
  free with last write wins.

## Sources
- #10, #11 "the gallery deliberately stays outside the document lock"
- `AGENTS.md`, "Written together"
- `lib/texttile/articles/lock.ex`
