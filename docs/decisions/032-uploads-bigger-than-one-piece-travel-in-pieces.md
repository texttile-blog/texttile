# ADR-032: Uploads bigger than one piece travel in pieces

## Status
Accepted

## Date
2026-11-24

## Context
Since staging moved to Bunny Magic Containers (ADR-027), every browser
upload larger than a few megabytes fails: the gallery refuses photographs
from a phone, and a film could not arrive at all. The logs on
blog.breyer.berlin showed 58 of 63 upload requests on one day starting and
never finishing. Controlled probes against the site reproduced it: a
request body is carried to the server only up to about 3 MiB, and past
that the connection between the platform's edge and the container dies
before the server can answer. The same probes through a local server
showed no limit at all, so the limit belongs to the hosting path, not to
the application.

The server cannot change what an edge drops, and the hosting offers no
setting for it (the pull zone for the CDN endpoint exposes no request-size
knob; asking Bunny support to raise the limit is possible but leaves the
application dependent on one platform's goodwill and gives nothing to a
reader on a bad phone line, where a half-sent 8 MB photograph is lost
whole today anyway).

## Decision
The browser sends a big file as pieces: 1 MiB per request, in order, one
after the other. Each piece rides as the bare body of a POST to a
`/chunks` address beside the upload it belongs to, carrying the upload's
token, its index, the piece count, the whole file's size and the name in
the query. The server stashes every piece in the machine's temporary
space and, when the last piece lands, welds the pieces into one file and
runs the very action a whole-file upload always ran. Answers, refusals
and duplicates are therefore byte for byte what they always were.

- A piece that never arrived, or a server that restarted between pieces,
  answers 409 with `restart: true`; the browser starts the file over from
  piece 0, and piece 0 empties the stash first.
- The stash lives in the temporary space, not on the volume: pieces are
  halves of a file on its way, not installation data. A stash nobody came
  back for within a day is swept when the next upload starts.
- A file at or under one piece still travels as one piece, so small
  uploads cost exactly one request as before.
- The whole-file addresses stay. A tab that is open while a new build
  arrives keeps uploading the old way.

## Alternatives Considered

### Ask Bunny to raise the request-size limit
- Pros: no code at all
- Cons: an outside dependency for a core act of the product, and no help
  on a phone line that drops mid-photograph
- Rejected as the only fix; still worth doing as a hosting improvement.

### Bypass the edge for uploads (a second endpoint)
- Pros: the upload protocol stays as it was
- Cons: a second address to keep certificates and cookies honest on, the
  container behind it is the same one whose intake showed the limit, and
  the admin area would talk to two hosts
- Rejected: more moving parts for an untested detour.

## Consequences
- The upload protocol is now two addresses per upload (whole file,
  pieces), both behind the same sign-in and the same roof.
- A photograph of any size arrives on the slowest line that can carry a
  megabyte at a time, and a dropped piece costs its own megabyte.
- The pieces are 1 MiB by agreement between `assets/js/chunks.js` and
  `TexttileWeb.ChunkedUpload`; the browser could change its piece size
  without the server caring, since the server never assumes one.
