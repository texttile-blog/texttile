# ADR-017: Nothing is loaded from outside

## Status
Accepted

## Date
2026-08-08

## Context
A reader's browser is the reader's. Every third-party script, font, player
or counter tells another company who reads what, and costs the reader a
connection on a slow line. The blog owner should not need an account
anywhere else to run the site.

## Decision
A reader's browser talks to this server and to nothing else. No CDN, no
third-party script, no tracker, no captcha, no hosted font, no external video
player. The statistics are counted here (ADR-020), the spam filter runs here
(ADR-015), the mail leaves from here (ADR-002), video is converted and played
from here (ADR-019). Fonts are the system font stack. The editor's packages
are bundled from npm, never from a CDN. A change that adds an outside call
breaks the product, not just a rule.

The one outside connection the server makes is the import fetching pictures
by URL (ADR-012), on the admin's explicit request, and guarded.

## Alternatives Considered

### A web font from Google Fonts or a self-hosted web font
- Rejected: a hosted font is an outside call; a self-hosted one is weight on
  a slow line that the system stack delivers for free

### YouTube or Vimeo embeds
- Rejected: an external player loads scripts and tells the host who watched

### A hosted analytics or comment service
- Rejected: counted here, stored here

## Consequences
- Every new capability is judged first by what it loads and where from.
- Pages stay small. Weigh every kilobyte.
- Features that the market solves with a service (captcha, analytics,
  newsletter, video) are built in, in their smallest form.

## Sources
- #24 "Write down the principles and the product decisions"
- `AGENTS.md`, "Nothing is loaded from outside"
- `assets/css/base.css`, the font variables
