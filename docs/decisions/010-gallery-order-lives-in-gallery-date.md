# ADR-010: The gallery's order lives in `gallery_date` and nowhere else

## Status
Accepted

## Date
2026-08-06

## Context
An entry has one ordered set of tiles. Two admins may sort it at the same
time (the gallery is outside the lock, ADR-008). A position column breaks
under concurrent drags: two moves renumber the same rows and the result is a
list neither saw. Most pictures already carry a natural order, the capture
date.

## Decision
Tiles are ordered by `gallery_date`, oldest first, the id as the tiebreak. The
date starts as the EXIF capture date when the file has one, otherwise as the
upload moment. A drag writes one new date for the moved tile: the midpoint of
its new neighbours, a second outside at the ends. When two dates sit too close
for a midpoint, the whole gallery's dates are spread a second apart again, in
the order the eye already sees. The lightbox offers a date picker that
resorts the gallery at once. Every change is broadcast as `gallery_changed`.

## Alternatives Considered

### A position integer
- Cons: every drag renumbers rows; two admins dragging at once renumber over
  each other
- Rejected: a date is one write per drag and commutes with the other admin's
  write

### Order by upload time only
- Rejected: photos from a trip arrive out of order; the capture date is the
  order the writer means

## Consequences
- There is no second ordering concept to keep in sync. Export numbers the
  tiles in `gallery_date` order (ADR-012).
- Deleting a tile opens a ten second undo window, and a sweeper makes it
  final across restarts.
- The reader's gallery, the editor's tiles and the lightbox all read one
  sort.

## Sources
- #11 "The gallery: pictures in the editor, ordered by a date"
- `lib/texttile/gallery.ex`
