# ADR-013: A post lives under the day it went live; a move leaves a permanent redirect

## Status
Accepted

## Date
2026-08-07

## Context
A blog's addresses are shared and bookmarked. A post and a page are different
things: a post belongs to a day, a page is pointed at from the menu. An entry
that is not live yet should already have an address so the way out of the
editor leads into the real reader's page.

## Decision
A post lives at `/2026/08/23/harbor-mornings`: the day it went live, then the
slug. A page lives at its slug alone, `/about-us`. There is one address per
entry and no second one; the bare slug of a post is a 404. A draft answers at
its future address for a signed-in admin and 404s for a reader.

Changing the slug or the publish date of a live entry moves it. The old
address stays alive as a permanent redirect (`Texttile.Articles.Redirect`),
listed under the address field with a Delete for the day it should go. Only a
live entry leaves one behind: before an entry is live no reader ever had the
address.

## Alternatives Considered

### Slug-only addresses for posts
- Rejected: a blog writes a post's address the way a blog does, and a day
  keeps slugs from colliding across years

### No redirect, address never changes
- Rejected: a date correction or a better slug is a normal edit; the shared
  link must keep working

## Consequences
- The development routes (the dashboard, the mail preview) stand in front
  of the four-segment reader routes, or `/dev/dashboard/...` reads as a
  post.
- The canonical link of an entry omits query parameters, and a page used as
  the front page names `/` as canonical.
- The subscriber mail and the feed carry the dated address.

## Sources
- #14 "The desk moves to /edit, posts get dated addresses"
- #29 "an entry has an address before it is live", #93
- `lib/texttile/articles/redirect.ex`
