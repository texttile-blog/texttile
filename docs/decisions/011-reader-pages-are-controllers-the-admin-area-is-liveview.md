# ADR-011: Reader pages are controllers and small scripts; the admin area is LiveView

## Status
Accepted

## Date
2026-08-06

## Context
Texttile is written for a person reading on a phone far from a data center.
A LiveView page opens a WebSocket and ships the LiveView client, which a
reader does not need. The admin area, in turn, is collaborative: presence,
live text from the other admin, live tiles, live counts.

## Decision
Reader pages (`/blog`, an entry, the tag archive, the gate, the comment and
newsletter forms, the feed) are plain controllers with server-rendered HTML
and a small separate script bundle (`esbuild public`). Posting a comment is a
plain form round trip. The admin area behind `/admin` is LiveView, with its
own bundle (`esbuild texttile`), and the editor chunk loads only on the
editor (ADR-007).

## Alternatives Considered

### LiveView everywhere
- Cons: a socket and the client library on every reader page, for nothing a
  reader does
- Rejected: pages stay small, JavaScript stays little

### A single-page app for the admin area
- Rejected: LiveView gives presence, PubSub and live updates without a second
  stack

## Consequences
- Weigh every kilobyte added to the public bundle. Continuously repainting
  animations are out on both faces.
- A reader-facing feature is a controller, a template and at most a small
  script. Stats reporting, the lightbox and the video player are such
  scripts.
- Phone first: a UI change is judged on the phone screenshot before the
  desktop one.

## Sources
- #13 "The public site: readers get the blog at the root"
- `AGENTS.md`, "Light enough for a slow line", "How it works"
- `mix.exs`, the `assets.build` alias
