# ADR-005: Originals are kept as they came; renditions are made on demand and thrown away

## Status
Accepted

## Date
2026-08-04

## Context
A picture is only ever as large as the screen asks for, and a reader may be on
a slow line far from the server. The same picture is wanted at several sizes:
the admin thumbnail, the reader size, the lightbox. The sizes change when the
Images setting changes. A backup must not grow with every size ever made.

## Decision
Every uploaded file is kept below `UPLOADS_PATH` exactly as it came. A
rendition is scaled the moment a page first needs it and answered from a cache
after that. The longer edge stays within Settings > Images > Max longer edge,
and nothing is ever scaled up. An image holds a small, known set of cached
sizes; anything else is dropped on the next ask. The whole cache is
disposable: clearing it costs the next reader a moment and nothing else.

Later refinements kept the rule: progressive JPEGs, two lightbox sizes, a day
of browser cache per rendition, and the HDR gain map dropped when a rendition
is written.

## Alternatives Considered

### Scale at upload time into fixed sizes
- Cons: a changed setting would need a re-run over every picture, and the
  sizes would be stored and backed up for ever
- Rejected: on demand means the setting applies at once and the cache is
  never backed up

### An image CDN
- Rejected: nothing is loaded from outside (ADR-017)

## Consequences
- `cache/` below the uploads root is never backed up (ADR-023). After a
  restore, renditions are made again as readers arrive.
- The uploads layout is `site/`, `images/`, `videos/`, `cache/`, the same on a
  laptop, in a container and on any host.
- One roof holds for pictures and videos: Settings > Storage > Biggest upload.

## Sources
- #5, #44 "An entry takes each picture once", #92, #95
- `lib/texttile/images.ex`, `lib/texttile/uploads.ex`
