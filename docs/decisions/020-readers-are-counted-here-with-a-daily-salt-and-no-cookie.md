# ADR-020: Readers are counted here, with a daily salt, no cookie and no stored address

## Status
Accepted

## Date
2026-08-08

## Context
The writers want to know what is read. A hosted counter is an outside call
(ADR-017), a cookie needs a banner, and a stored IP address is personal
data. The numbers should be about people, not about crawlers.

## Decision
Every reader page reports itself to this server with one small request that
carries the page address, the entry and the referrer. No cookie is set, read
or sent. The server turns the caller into one number for the day: IP address
and browser line hashed with a secret the server draws every morning and
keeps in memory only (`Texttile.Stats.Salt`). The secret never touches disk
and is gone at midnight, so no row can be traced back and nothing links a
reader to two days. The IP address itself is never stored.

Four rules keep the numbers about people: the report needs JavaScript, so
crawlers mostly never report; a browser line that says bot and a page only
fetched ahead are dropped; one reader counts once per page every half hour;
one caller writes at most 60 views a minute. A signed-in admin is not a
reader, and drafts, scheduled entries and previews count for nobody.

The rows live in `page_views` in the owner's database.

## Alternatives Considered

### A hosted analytics service
- Rejected: counted here, stored here, nothing leaves

### Server-side counting from the access log
- Rejected: the log counts every crawler, and the server would have to keep
  addresses to deduplicate

### A persistent visitor identifier
- Rejected: it would link a reader across days, which is the thing the daily
  salt exists to prevent

## Consequences
- "People" means readers of that day. A reader who comes back next week
  counts as one person each time, and the README says so.
- Behind a proxy without `CLIENT_IP_HEADER`, every reader shares one address
  and counts as one person.
- Tables of referrers and addresses come from the browser and are capped at
  20 rows.

## Sources
- #30 "Count the readers, without a cookie and without a bot"
- #67 "Stats picks a window and opens a day"
- `lib/texttile/stats.ex`, `README.md`, "Stats"
