# ADR-015: Spam protection is three invisible filters, never a captcha

## Status
Accepted

## Date
2026-08-07

## Context
The comment form and the newsletter form are open to anybody. A captcha is a
third-party script (ADR-017), a hurdle for a real reader, and useless on a
slow line. The filter has to run here and show nothing.

## Decision
Every public form carries three filters that never show themselves: a
honeypot field, a time trap (a signed stamp of the moment the form was drawn;
a submit younger than a person's typing is a script), and a rate limit per
caller. A dropped submission is answered like a stored one, so nothing learns
from the difference.

The rate limiter (`Texttile.RateLimiter`) is a sliding window per key in one
ETS table, pruned as it is read and swept once a minute. Comments and
newsletter requests share one bucket. A second, wider bucket stands in front
of the view counter (ADR-020), and a third in front of the backup endpoints
(ADR-023). Nothing is kept but timestamps that expire within the minute.

Behind a proxy the caller's address comes from `CLIENT_IP_HEADER`, set only
when the proxy writes that header itself; of a list, the last entry counts.

## Alternatives Considered

### A hosted captcha (reCAPTCHA, hCaptcha, Turnstile)
- Rejected: a script from outside, a hurdle for the reader, and a dependency
  on a company's judgment of who is human

### A spam service (Akismet)
- Rejected: every comment would leave the server

### A rate limit in the database or in Redis
- Rejected: an ETS table in the one process that is already running, with
  nothing to back up and nothing to install

## Consequences
- Spam protection is always on and has no setting.
- A proxy that passes `X-Forwarded-For` through instead of appending lets the
  caller choose their address. The README says when to set the header.
- The honeypot and the time trap live in one component the forms share.

## Sources
- #15, #18 "The subscribe form wears the same spam protection"
- #30 the second bucket, #41 the third
- `lib/texttile/rate_limiter.ex`, `README.md`, "Behind a proxy"
