# ADR-018: One shared password guards the whole blog or nothing, and a guarded blog has no feed

## Status
Accepted

## Date
2026-08-08

## Context
A blog for family and friends wants a gate without accounts for readers. A
feed reader cannot answer a password screen. Uploaded pictures are reachable
by address, so a gate on the pages alone leaks the pictures.

## Decision
The blog can sit behind one shared password (Settings > Access). It is an
access word to hand around, not a login: stored in plain text, one word opens
the whole blog, and it guards the blog or nothing. No entry has a switch of
its own. `Settings.guarded?/0` is the one place the rule is read: the gate,
the newsletter mail, the newsletter screen and the feed.

A guarded blog has no feed: `/feed.xml` answers 404 and no page offers the
link. The password also covers uploaded files, renditions and the home-screen
icon. A browser keeps a file for a day, for itself only
(`private, max-age=86400`); no shared cache ever holds one. A password change
revokes reader access, but not what a browser already holds.

While the blog is guarded, the editor shows the word under Share, with the
title and address to hand on.

## Alternatives Considered

### A password per entry
- Rejected: a feature that needs a switch per entry is the wrong feature;
  one word, one blog

### Reader accounts
- Rejected: readers are anybody who is not signed in; accounts are the two
  writers (ADR-026)

### A feed with the password in the URL
- Rejected: the entries would travel out of the gate into every feed service

## Consequences
- The feed (`/feed.xml`) is RSS with every published post, newest first, an
  ETag for a 304 on repeat polls, and a private cache header.
- The feed, the gate and the sign-in state have to agree on every reader
  path; "Signed in and signed out" is on the surface checklist.
- The server cannot recall copies already downloaded.

## Sources
- #20 "RSS feed for a blog without a password"
- #69 "Protect uploaded media with the blog password", #95
- `lib/texttile/feed.ex`, `lib/texttile/settings.ex`
