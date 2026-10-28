# ADR-019: A video is converted once by ffmpeg, one at a time, at the lowest priority

## Status
Accepted

## Date
2026-08-08

## Context
Videos must play from here (ADR-017). A phone's recording is a large file in
a container not every browser reads. The conversion is the most expensive
thing the server does, and the site must stay quick while it runs on one
small machine.

## Decision
An uploaded video is kept exactly as it came, like every picture. What a page
plays is one derived file, an MP4 (H.264 and AAC) that every browser reads,
plus a poster frame beside it. Settings > Videos > Max longer edge caps the
size, 1280 px by default, and nothing is scaled up. Since #97 the output
runs at a constant 30 fps; existing conversions keep theirs. A new setting
applies to what is converted after the change, because a converted video is
never made again.

ffmpeg does the work gently: one video at a time (`Texttile.Videos.Queue`),
one thread, the lowest scheduling priority, idle disk priority where the
kernel offers it, under a task supervisor. A server that stops
mid-conversion picks the video up again at start. The server reads which
container a file really holds before ffmpeg opens it, and ffmpeg runs with
the local disk as its only source. In the words a video is a player that
fetches nothing but its poster until play is pressed.

## Alternatives Considered

### An external player or a video host
- Rejected: ADR-017

### Convert on demand like pictures (ADR-005)
- Rejected: a conversion takes minutes; no page can wait for it, and it is
  made once and backed up (ADR-023)

### Several renditions or adaptive streaming
- Rejected: one file every browser reads, capped by one setting

## Consequences
- The image carries ffmpeg and util-linux (for ionice). `make tools`
  installs the same on a laptop.
- Videos decide the machine size: four shared CPUs and 1 GB before the first
  upload. Words and pictures run on one CPU and 512 MB.
- The admin area shows the conversion state on the tile; the reader's
  gallery leaves a tile out until it is ready.
- Uploaded files answer range requests, which is how a player seeks.

## Sources
- #22 "Self-hosted video: upload it, ffmpeg converts it, the page plays it"
- #97 "Convert videos at a fixed 30 fps"
- `lib/texttile/videos.ex`, `README.md`, "How big the machine must be"
