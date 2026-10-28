# ADR-026: The email address is the identity, every account is an admin, and a deleted account keeps its row

## Status
Accepted

## Date
2026-08-19

## Context
Texttile is built for two people who trust each other. A username carried
nothing: the address signs in, and what stands under an entry is the
displayed name. A first admin of a new installation has nobody inside to
invite them. Taking access away must not take a byline away from what a
person wrote.

## Decision
An account is an email address, a password and the name readers see. There
is no username, no registration, no role and no permission matrix: the
accounts are the whole access model, every one of them an admin.

An account comes into being in two ways, and both end in a mailed link that
sets its first password. `ADMIN_USERS` names addresses that get an account
at the start of the server, once per address ever made here, so the first
admin gets in without anybody to invite them. Settings > Users invites an
address on a click, with the same link, without a deploy. Whoever reads
that inbox is who the account belongs to. While no account has a password,
the server writes every link into its log (ADR-002). An invitation link
works once and for a week; a forgotten-password link once and for 24 hours.
Moving your own address asks for the password first.

Taking access away means deleting the account. The row stays with a
`deleted_at`: out of every list, out of every browser, its address free
again, and still the name under everything it wrote, marked `(deleted)` in
the admin area. `Accounts.here/0` leaves it out. Nobody deletes their own
account, and the last one cannot go. Revoking somebody named in
`ADMIN_USERS` means deleting the account and taking the address out of the
variable.

The sign-in lasts two days, fourteen when "Stay signed in" is ticked. The
session row and the cookie end together.

## Alternatives Considered

### A username
- Rejected in #61: it carried none of the identity

### Roles (owner, editor, reader)
- Rejected: two people who trust each other need none, and a permission
  matrix is machinery

### `ADMIN_USERS` as the live guest list
- Rejected: it made an account for every address at every start, which
  undid a deletion at the next restart

### Hard-deleting an account
- Rejected: a reader would see an entry lose its byline

## Consequences
- `ADMIN_USERS` says who is invited at boot, nothing more. The README
  states the trade: the variable is operator configuration.
- The account keeps its row, so every query over accounts decides whether
  the deleted ones belong in it.
- The public forgot-password form leaves an account without a password
  alone, so a stranger cannot kill an invitation.

## Sources
- #5, #6 the first sign-in list; #43 "The sign-in lasts two days"
- #61 "The email address is the identity, and the username is gone"
- `AGENTS.md`, "Minimal, and everybody is an admin"; `lib/texttile/accounts.ex`
