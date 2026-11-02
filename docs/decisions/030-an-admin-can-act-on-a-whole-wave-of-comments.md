# ADR-030: An admin can act on a whole wave of comments at once

## Status
Accepted, amends ADR-014

## Date
2026-11-02

## Context
ADR-014 lets an admin release, edit and delete one comment at a time. That
holds until a spam wave arrives: 68 waiting comments and a hundred more behind
them cannot be cleared one row at a time, and the waiting ones stay in the
admin area for as long as nobody acts.

## Decision
The Comments overview has a box on each row and one line over the list. With
nothing ticked the line acts on every comment of the filter, across its pages.
With boxes ticked it acts on those. Every action asks first and names the
number, and the question fixes the list, so a comment that arrives while the
question stands is not part of the answer.

A filter offers what its comments can do: Release and Delete on Not confirmed
yet, Restore on Trash, Delete everywhere else. Restore is there so that a
Delete of a whole filter has a way back.

ADR-014 still stands: nothing waits for an admin, and no comment needs one to
appear. A bulk Release does not confirm an address, and it mails nobody.

## Alternatives Considered

### Select all takes the page only
- Rejected: a wave of 500 comments would take 20 rounds of the same two clicks

### Release on the All filter
- Rejected: the number on the button would have to count only the waiting
  comments of the selection, and the filter already says which ones those are

### A second list, or a queue for spam
- Rejected: one list with a filter is the smallest model that clears a wave

## Consequences
- A bulk Release has no way back except Delete, so its question says so.
- One bulk action sends one message, `{:comments_changed, article_ids}`, so a
  wave does not wake every open screen once per comment.
- The per-row actions stay as they were, and the editor's Comments tab has no
  boxes.

## Sources
- The spam wave on the Comments screen, November 2026
- `lib/texttile/comments.ex`, `lib/texttile_web/live/comments_live.ex`
