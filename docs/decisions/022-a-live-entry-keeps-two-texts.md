# ADR-022: A live entry keeps two texts, and every reader path takes the live one

## Status
Accepted

## Date
2026-08-10

## Context
A keystroke in a live entry used to be on the site the same second, so a
half-written sentence was published by writing it. Two admins write live
(ADR-008), autosave writes every few seconds (ADR-009), and a reader must
never see a sentence in the middle of being typed.

## Decision
A live entry keeps two texts: the working copy in the editor, and the
version `live_version_id` points at. Only publishing moves the pointer.
Typing moves the working copy alone. The bar says which is which: the state
word turns to "Live · draft" and the button to "Publish changes", which
hands the text over with the same day, address and state, and no mail. The
menu offers "Discard the changes", which puts the published text back and
keeps what was thrown away as a version.

Only the title and the body split in two. Tags, the address, the tiles and
the switches have one state and go live as they change. Every path that
hands an entry to a reader (the list, the entry, the tag archive, the
search, the feed, the subscriber mail) goes through `Articles.as_read/1`.
`Texttile.Articles.Reading` names the audience: `:reader` gets the live
version and nothing that is not live; `:admin` gets the working copy, with
a strip over the site page that says so. Since #99, publishing commits the
publication state, the snapshot, the log entry and the mail choice together.

## Alternatives Considered

### A separate draft column beside the body
- Rejected: the live text is already a version (ADR-009), so a pointer is
  enough and the version list marks it **live**

### A branch or fork of the entry
- Rejected: two rows for one address, and nothing in the product asks for
  more than one pending change

## Consequences
- A new reader path must name its audience in `Reading`, or it cannot hand
  out the working copy by accident.
- The entries overview marks a live entry whose working copy ran ahead with
  "edited since publishing".
- Export takes the text the readers have; an entry never live exports its
  working copy (ADR-012).

## Sources
- #47 "A live entry keeps two texts, and nine open tabs stay alive"
- #99 "Keep publication state and live versions consistent"
- `lib/texttile/articles/reading.ex`, `AGENTS.md`, "The two texts of an entry"
