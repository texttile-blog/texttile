# ADR-012: Import and export share one bundle format, and it is a Hugo page bundle

## Status
Accepted

## Date
2026-08-06

## Context
People arrive from WordPress, Ghost, Substack or a static site. Each export
looks different, and no importer can know them all. The owner also needs a
way out that is not the database file.

## Decision
The import takes a zip of bundles: one folder per entry with an `index.md`
(front matter plus the Markdown) and its files beside it. `IMPORT.md` is the
complete format contract, written so a script or an AI agent can convert any
export into bundles. A picture may be a file in the bundle or a URL the
server downloads; a film travels only as a file.

The import runs in two steps: `validate` reads every bundle and answers a
dry-run report with nothing written; `run` imports the healthy bundles one
after the other, each in one transaction. Remote fetches are guarded: no
private addresses, the address resolved once and pinned, no redirects, a
size cap per picture and caps on what the zip unpacks to.

Every entry exports itself as the same bundle: `index.md` with the published
text and `gallery/` with the originals, tiles numbered `001_` in gallery
order and the files in the words under `xxx_`. The zip is at the same time a
Hugo page bundle and a bundle this or another Texttile imports again.

## Alternatives Considered

### One importer per source system
- Cons: every system's export changes, and the importer would own all of
  them
- Rejected: one contract, and the conversion is the converter's job

### Export as a database dump
- Rejected: the backup (ADR-023) is that; an export is one entry a person can
  read and take elsewhere

## Consequences
- The import is the one place that fetches from the network, and it is where
  the complexity belongs: the contexts stay plain.
- A change to the bundle format changes `IMPORT.md` in the same pull request.
- Comments travel with the import (#40) but not with the export: a copy of an
  entry is its text and its pictures.

## Sources
- #12 "Import bundles from other systems", #49 "An entry hands out a copy of itself"
- #54, #57 the zip under the one upload roof, taken over instead of copied
- `IMPORT.md`, `lib/texttile/import.ex`, `lib/texttile/export.ex`
