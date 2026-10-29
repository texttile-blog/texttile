# ADR-016: The newsletter is double opt-in and sends one mail per entry

## Status
Accepted

## Date
2026-08-07

## Context
Readers want to hear about a new entry without visiting. A list of addresses
that never confirmed is a spam list, and a mail that goes out twice for the
same entry is noise. The mail must leave from this server (ADR-002), not from
a mailing service.

## Decision
A reader joins through the form in the footer and gets one confirmation
mail; the address receives entries only after the link was followed. An
admin can add an address by hand, and that address is confirmed at once:
the admin vouches for it. Every mail carries the way off the list.

When a post goes live with "Email subscribers" checked, every confirmed
address gets one email: the preview picture as a square, the title, who
wrote it and when, the lead, and a button to the entry. If the blog sits
behind the shared password, the mail includes it. The mail is HTML with a
plain-text part, in the layout every mail of the blog shares
(`TexttileWeb.MailHTML`), and its button wears the theme's solid colour.
The square travels inside the mail as an inline attachment (a content id),
so it shows behind the blog password and opening the mail asks this server
for nothing. The mail
goes out once per entry (`notified_on`); publishing again, or publishing
changes to a live entry, never sends it again. Publishing never mails by
itself: `Publishing.plan/3` says what a click means, the dialog draws the
plan, and `run/3` carries out the same plan.

## Alternatives Considered

### A hosted newsletter (Mailchimp, Buttondown, Substack)
- Rejected: the list would leave the server, and the reader's address with it

### A mail with the whole entry
- Rejected: the mail gives a taste, the lead; readers read on the site,
  and a correction after publishing reaches them there

### The picture as a link to this server
- Cons: pictures sit behind the blog password, so the link would need a
  signed address that opens the gate for one file, and every opened mail
  would ask this server for it
- Rejected: the square travels inside the mail instead. Brevo's API takes
  no content id, so with Brevo the mail goes without the picture

## Consequences
- The subscriber mail takes the live version through `Articles.as_read/1`,
  never the working copy (ADR-022).
- `Newsletter.notify_published/2` is the one path for the mail, from a
  click and from the scheduler alike. Setting `notified_on` from empty to
  today in one update is the lock that keeps it to one mail.
- The subscribe form carries the filters of ADR-015.

## Sources
- #18 "Newsletter: subscribers, double opt-in, the go-live email"
- #86, #91 the mails shortened, the lead paragraph dropped
- feature/html-mails: every mail in one HTML layout, the lead and the
  square back in the entry mail
- `lib/texttile/newsletter.ex`, `lib/texttile/articles/publishing.ex`
