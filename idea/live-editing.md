# Texttile — Collaboration & Versioning Spec (v1)

Scope: how two editors share one article, how the edit lock and takeover work, and how text versions are stored and restored. This is the v1 model. Full concurrent text editing (CRDT/Yjs) is explicitly **out of scope** — see §7.

---

## 1. Collaboration model

Two admins may have the same article open at the same time. **The text is the only thing that is locked. Everything else is freely editable by both at all times.** State the rule that plainly in the UI too — it needs no further explanation.

|Part|Concurrency model|Rationale|
|---|---|---|
|**Text** (title + Markdown body)|**Exclusive lock** — one editor at a time|High conflict risk; merging concurrent text requires a CRDT|
|**Gallery tiles** (order, captions, add/remove)|**Free for everyone** — always concurrently editable|Low conflict risk; a reorder is a single atomic move|
|**Article settings** — tags, date, slug, password protection, comment settings, and any setting added later|**Free for everyone** — always concurrently editable|Each is an atomic field or set operation; nothing to merge. Last write wins per field.|
|**Publish controls**|**Free for everyone**, but guarded by confirmation|Not a merge problem — a side-effect problem (see below)|

Any article-level setting introduced after v1 defaults to "free for everyone". Only extend the lock if a field genuinely needs character-level merging — in practice, only the body does.

**Consequences to implement:**

- A person **without** the text lock is not a passive spectator. They see the text live in read-only mode, and they can still reorder, caption, add and remove gallery tiles. This must be obvious in the UI — the gallery should not look disabled.
- Gallery changes broadcast to everyone via PubSub regardless of who holds the text lock.
- Gallery conflict resolution: last write wins per operation. No locking, no merge logic.

**Publishing while someone else is editing:**

The edit lock does not restrict publishing — both admins may publish or unpublish at any time. The risk here is not a conflict but an irreversible side effect: making a half-finished draft public and, if the newsletter fires on publish, sending it to subscribers. Guard it with context instead of a lock:

- If someone else currently holds the text lock, the publish confirmation must say so explicitly: "Julia is editing this article right now. Publish anyway?"
- Newsletter dispatch must be a separate, explicitly confirmed step — never an automatic side effect of flipping the publish flag. Publishing is reversible; a sent newsletter is not.
- Unpublishing needs no confirmation.

**Live read-only preview of the text:**

- The lock holder's changes stream to the other person's screen in near-real-time (debounced, e.g. every 300–500 ms of typing).
- Implementation: the editing LiveView broadcasts text changes over PubSub; the read-only LiveView renders them. **No CRDT, no operational transformation, no client-side merge** — there is only ever one writer, so there is nothing to merge.
- The read-only view shows who is writing and shows a "take over editing" control.

---

## 2. Edit lock mechanics

**One GenServer per open article** owns the lock state. All lock operations go through it, so Elixir's message serialization gives mutual exclusion for free — no database locking, no optimistic-concurrency retries.

The GenServer holds: `article_id`, current holder (`user_id`, `pid`), `acquired_at`, `last_keystroke_at`.

**Acquiring:**

- Opening an article whose lock is free → acquire it automatically. No "start editing" button for the common case.
- Opening an article whose lock is held → read-only mode + takeover control.

**Releasing — three paths, all must be implemented:**

1. **Explicit:** user navigates away or closes the editor → release.
2. **Process death (the important one):** the GenServer `Process.monitor`s the holder's LiveView pid. On `:DOWN`, start a **grace period of 45 seconds** before releasing, so a page reload or a brief mobile network drop does not cost the lock. If the same user reconnects within the grace period, they silently get the lock back.
3. **Inactivity timeout:** no keystroke for **15 minutes** → release automatically. This is the most common real-world case (forgotten tab, phone in pocket) and it means most handovers never require a takeover at all.

**Race condition:** if two people request the lock simultaneously, the GenServer processes them in order. The first wins; the second receives a clean rejection and stays read-only with a message naming the winner.

---

## 3. Takeover flow

Triggered when a read-only person wants the text lock while someone holds it.

**Step 1 — Confirmation dialog with context.** The dialog must state _who_ holds the lock and _how active they are_. Distinguish two states based on `last_keystroke_at`:

- Active (keystroke within the last 30 s): "Julia is typing right now."
- Idle: "Julia has had this open for 42 minutes but hasn't typed for 12 minutes."

This is the difference between an informed decision and a blind one. Do not show a generic "are you sure?".

**Step 2 — Flush before switching.** This ordering is mandatory and must not be reordered for convenience:

1. Server asks the current holder's client to immediately flush unsaved changes.
2. Autosave completes.
3. A version snapshot is created (see §5, trigger: handover).
4. Only then does the lock transfer.

Without this, the displaced editor loses the seconds between the last autosave and the takeover — which users experience as data loss. If the flush does not complete within ~3 seconds (client unreachable), proceed anyway using the last autosaved state and log it.

**Step 3 — Notify the displaced editor.** Requirements:

- **Not a blocking modal.** The editor transitions into read-only mode with an inline, non-intrusive notice.
- The notice must contain the reassurance explicitly: **"Klaus is editing now. Your changes are saved."** The fear in that moment is lost work; address it in the first sentence.
- The notice includes a control to take the lock back.
- Any keystrokes typed in the moment between flush and lock transfer are discarded, but the input must become non-editable immediately so the user does not keep typing into a dead field.

**Wording:** in the UI, this is "Take over editing", never "kick out" or "remove". Same function, very different feel for two people who know each other.

---

## 4. Autosave vs. versions

Two distinct mechanisms — do not conflate them:

- **Autosave**: debounced (~2–3 s after typing stops) write of the working state directly into the `articles` row. No history, no user interaction, no UI beyond a subtle "saved" indicator. Purpose: crash and disconnect safety.
- **Version**: a deliberate, restorable point in time, stored in a separate table. See below.

---

## 5. Versioning — **text only**

**Deliberate scope decision: versions cover text only.** A version stores the **title** and the **Markdown body**. Nothing else.

Explicitly **not** versioned: gallery contents and tile order, tags, publish status, slug, comments, statistics.

Rationale (do not "improve" on this):

- The UI stays comprehensible: "restore this text" is one clear promise. "Restore this text and the gallery it had and the tags it had, but not the URL and not the publish state" is not.
- Diffing plain text is trivial and renders well on a narrow mobile screen. Diffing a gallery reordering does not.
- It removes an entire class of bug: since versions never reference images, images can be deleted immediately when removed from a gallery. **No soft-delete, no orphan retention, no reference-counting garbage collection.**

**Schema:**

```
articles          → id, title, body, slug, status, published_at, updated_at, ...
article_versions  → id, article_id, title, body, created_by_user_id, created_at, label
```

Store full copies, not diffs. A blog article is a few kilobytes; a hundred versions stay well under a megabyte, and full copies make restore a trivial field copy instead of a replay chain.

**Version creation triggers:**

1. **Manual save** — the user presses "Save version". Optional short label.
2. **On publish** — automatic. "This is how it went live" is the single most valuable version.
3. **On handover** — automatic, created during the takeover flush (§3, step 3). This is what makes takeover safe: you can always return to the state the other person had.

**Do not** create a version on every autosave. That is how WordPress accumulates hundreds of junk revisions per article.

Deduplication: if the text is byte-identical to the most recent version, do not create a new one (relevant for publish-immediately-after-save).

**Restore semantics:**

- Restoring writes the version's title and body into the article's working state. It does **not** touch gallery, tags, slug, publish status or `published_at`. Restoring content must never take a published article offline or break its URL.
- Restoring requires holding the text lock.
- Restoring itself creates a version of the pre-restore state first, so restore is always undoable.

**Diff UI:**

- Show a list of versions: relative time, author, label if present.
- Show a diff between any version and the current text, and between two versions.
- Word-level or line-level diff, whichever renders more legibly on a phone. Mobile is the primary target: a side-by-side two-column diff will not work — use a single-column inline diff with additions and deletions marked.

---

## 6. Not in v1 — do not build

- Concurrent text editing with merged edits and remote cursors (Yjs/CRDT/OT).
- Paragraph-level or block-level locking. It requires stable block identities, which Markdown does not have, and it creates worse UX than a document lock.
- Versioning of gallery, tags or publish state.
- Comment moderation history, statistics history.

---

## 7. Keep the upgrade path open

Full concurrent editing may be added later. To make that a component swap rather than a rewrite:

- Implement the text editor as a **single, isolated LiveView hook** with a narrow interface:
    - **in:** initial text, remote text updates, read-only flag
    - **out:** local text changes, cursor position, activity ping (feeds `last_keystroke_at`)
- No other part of the application may reach into the editor's internal state.
- Keep the article's Markdown available as a plain `body` column at all times. If a CRDT is introduced later it becomes the editing-time source of truth, but a materialized Markdown column must remain for rendering, RSS, search and versioning.
- Versioning as specified here is independent of the editing mechanism and survives such a migration unchanged.