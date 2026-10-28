# ADR-014: A comment waits for its reader's confirmation, never for an admin

## Status
Accepted

## Date
2026-08-07

## Context
Two people run the blog in their spare time. An approval queue is a chore
that fills up, and a comment that waits for days is a comment nobody writes
again. Spam must still stay out, and a reader who was once trusted should not
be asked again.

## Decision
There is no approval queue. By default a new address gets one confirmation
mail; the comment appears when its reader follows the link, and every later
comment from that address appears at once. Settings > Comments can turn the
confirmation off, and then every comment appears the moment it is sent. One
rule, one wording, everywhere: the row and the rule sentence live in one
component.

An admin can make one exception at a time: release one waiting comment
while its address stays unconfirmed, edit the words (marked "edited" in the
admin area), or delete into a trash that keeps the comment 30 days. Every
admin gets a comment by mail when it stands under the entry, unless they
switch that off. Commenting while signed in needs no confirmation: the
sign-in already proved the address.

## Alternatives Considered

### A moderation queue
- Rejected: nothing waits for an admin, and no comment needs one to appear

### Confirmation per comment
- Rejected: one confirmation per address, remembered; the next comment
  appears at once

### Hard delete
- Rejected: delete needs restore (a one-way door is a bug), so the trash
  holds 30 days

## Consequences
- The waiting comment stands in its poster's own session only, so they see
  it while nobody else does.
- A released comment does not confirm the address; the next one waits again.
- Spam is held out by the invisible filters of ADR-015, not by the queue
  that does not exist.

## Sources
- #15 "Comments: readers write, one confirmation per address, no queue"
- #25 "Comments admin: a trash of 30 days, an edit, and a release for one comment"
- `lib/texttile/comments.ex`
