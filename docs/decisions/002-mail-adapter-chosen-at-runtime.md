# ADR-002: Mail leaves through a Swoosh adapter chosen at runtime

## Status
Accepted

## Date
2026-08-02

## Context
The blog sends mail for invitations, password links, comment confirmations,
comment notifications and the subscriber mail. Every installation has a
different mail provider, and the image is built once for all of them.

## Decision
`MAIL_ADAPTER` selects the Swoosh adapter at boot: `resend`, `postmark`,
`brevo`, `smtp` or `ses`. Each adapter loads exactly the credentials it
needs, and nothing else is read. Without the variable, mail goes to the local
preview mailbox at `/dev/mailbox`, which is for development only. Mail that
goes to many people or follows a reader's action (the subscriber mail, the
comment mails) leaves from a supervised task, so a click never waits for
another server. An invitation or password link is sent in the request, so
the screen can say when it did not go out.

While no account has a password, the server also writes every link it mails
into its own log. That is the way into a fresh installation whose mail does
not work yet (see ADR-026).

## Alternatives Considered

### One fixed provider
- Rejected: the blog owner picks the provider; the image must not

### Sending every mail inline in the request
- Cons: a slow mail server makes a publish or a comment wait
- Rejected for bulk and reader mail: it leaves in a task, and the click
  answers at once

## Consequences
- Adding a provider is one adapter clause in `config/runtime.exs` and one row
  in the README table.
- A broken mail configuration is found at boot or in the log, not by a reader
  who never got a confirmation.
- Test mail never goes to a personal address: the preview mailbox or the
  Resend test addresses.

## Sources
- #1, "Add Swoosh mailer with runtime adapter selection via MAIL_ADAPTER"
- `README.md`, "Mail"
- `config/runtime.exs`, `lib/texttile/mailer.ex`
