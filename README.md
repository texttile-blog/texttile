# texttile

A minimal blog CMS with multiplayer editing. Phoenix, LiveView, and SQLite in
one Docker image. One volume holds all state. No external services are
required.

Status: early development. Do not use it for a real site yet.

## Configuration

Texttile reads its configuration from environment variables at start.

| Variable          | Required in prod | Default                     | Purpose                                           |
| ----------------- | ---------------- | --------------------------- | ------------------------------------------------- |
| `DATABASE_PATH`   | yes              | `/data/texttile.db` (image) | SQLite database file                              |
| `UPLOADS_PATH`    | yes              | `/data/uploads` (image)     | directory for uploaded files                      |
| `ADMIN_USERS`     | yes              | none                        | usernames that may sign in, separated by commas   |
| `SECRET_KEY_BASE` | yes              | none                        | signs cookies; generate with `mix phx.gen.secret` |
| `PHX_HOST`        | yes              | `example.com`               | public hostname                                   |
| `PORT`            | no               | `4000`                      | HTTP port                                         |
| `MAIL_ADAPTER`    | no               | local preview mailbox       | `resend`, `postmark`, `brevo`, `smtp`, or `ses`   |
| `MAIL_FROM`       | no               | `texttile@PHX_HOST`         | sender address for outgoing mail                  |
| `CLIENT_IP_HEADER`| no               | none, the socket address    | header a trusted proxy writes, e.g. `fly-client-ip` |

Each mail adapter loads exactly the credentials it needs:

| `MAIL_ADAPTER` | Variables                                                                          |
| -------------- | ---------------------------------------------------------------------------------- |
| `resend`       | `RESEND_API_KEY`                                                                   |
| `postmark`     | `POSTMARK_API_KEY`                                                                 |
| `brevo`        | `BREVO_API_KEY`                                                                    |
| `smtp`         | `SMTP_HOST`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_PORT` (default 587, STARTTLS) |
| `ses`          | `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`                         |

A missing variable stops the app at boot with a message that names it. Without
`MAIL_ADAPTER`, mail goes to a preview mailbox (`/dev/mailbox`, dev only).

Set `CLIENT_IP_HEADER` only when a proxy stands in front of Texttile and
writes that header itself. The comment rate limit counts by it, so a header
the caller may write is a header a spammer may change. Without the variable
the rate limit counts by the address of the connection, which is right
everywhere except behind a proxy.

## Run with Docker

```sh
docker run -d --name texttile \
  -p 4000:4000 \
  -v texttile-data:/data \
  -e SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  -e PHX_HOST=blog.example.com \
  ghcr.io/texttile-blog/texttile:latest
```

The container prepares the data directories, runs migrations, drops root, and
starts the server. All state lives in `/data`. An update is: pull the new
image, start the container again.

## Readers and admins

Readers get the blog at the root: the list of published texts at `/`, each
text at its own address, and every published page in the menu. A post lives
under the day it went live, `/2026/08/23/harbor-mornings`; a page lives at
its slug alone, `/about-us`. Admins sign in at `/login` and work at `/admin`.

The list shows ten texts a page and then a pager. Change the number in
Settings > Front page. Under a text stand the way to the text before it and
the one after it, and the About block from Settings > About.

The blog can sit behind one shared password (Settings > Access). It is an
access word to hand around, not a login: it is stored in plain text, one
entry opens the whole blog, and it guards the blog or nothing. No text has a
switch of its own.

## Comments

Readers can comment under every text that allows it (the switch is in the
text's settings). There is no approval queue. By default a new address gets
one confirmation mail. The comment appears when its reader follows the
mailed link, and every later comment from that address appears at once.
Turn the confirmation off in Settings > Comments and no comment waits for
anything. Admins see all comments at `/admin/comments` and can delete them.

Spam protection is built in and always on: a honeypot field, a time trap,
and a rate limit per caller. No captcha, no Google, no third parties.

## Accounts

`ADMIN_USERS` names everybody who may sign in. It holds usernames,
separated by commas:

```sh
ADMIN_USERS="kb,julia"
```

A name on that list has no account at first. Its owner opens the site, types
the name on the sign-in screen, and chooses a password there, along with an
email address and a displayed name. That creates the account, and a
confirmation goes to the address. From then on the name signs in with that
password. Nobody is invited: adding the name to `ADMIN_USERS` is the
invitation.

The list stays in charge. Take a name out and its access ends at once, in
every open browser, whether or not the account is still there. Put it back
and the account works again.

The username is the only thing an outsider has to guess to reach the
password screen of a name that has no account yet. Pick names that are not
obvious, and keep `ADMIN_USERS` down to the people who need it.

### A forgotten password

The sign-in screen has a "Forgot your password?" link. It asks for the email
address of the account and sends a link that sets a new password. The link
works one time, and for 24 hours. Outgoing mail has to work for this, so a
real installation sets `MAIL_ADAPTER`.

Every account has an address: the first sign-in asks for one, exactly so
this reset always has somewhere to go. The profile changes it later. An
address is for the reset and for notifications. It is never a sign-in
identity, and a name that left `ADMIN_USERS` gets no link either.

When the mail cannot go out, the way back is to delete the account in
Settings; its owner then signs in again with the same name and a fresh
password. For the only account of a site, delete the row in the database
instead.

## Import from another system

Texttile imports texts from a zip archive of bundles: one folder per text,
with Markdown, settings, and pictures. A picture can be a file in the bundle
or a URL that the server downloads, so a migration zip stays small.
[IMPORT.md](IMPORT.md) is the complete format contract, written so that a
script or an AI agent can convert any export (WordPress, for example) into
bundles. The import itself lives in Settings: upload the zip, read the
validation report, start the import.

## Deploy on Fly.io

`fly.toml` in this repo deploys from source with one volume for the database
and the uploads. Its header documents the one-time setup (app, volume,
secrets, certificate).

## Development

Requires Elixir 1.19+, Erlang/OTP 28+, and Node.js (for browser tests).

```sh
make start       # dev server on port 4000, no configuration needed
make test        # unit tests plus end-to-end browser tests
make db-pull     # pull the production snapshot next to the dev database
make db-delete   # delete the shared development SQLite database
```

The development server listens on all interfaces, and `make start` opens
the address of the network instead of `localhost`: the address of the cable
network first, then Wi-Fi, then `127.0.0.1`. A phone in the same network
reaches the server at that address, and `http://localhost:4000` keeps
working on this machine. `bin/dev-host` prints the address that gets
chosen. Everybody in that network can open the site and the dev routes, so
start the server on a network you trust.

All git worktrees of the repository share the dev state of the main
checkout: the `texttile_dev.db` database, the `priv/uploads` folder, and the
`.env` file. `make db-pull` writes the production snapshot to
`texttile-demo.db` in that same checkout root. Outside a git checkout,
everything stays next to the code.
Stop the development server before running `make db-delete`. The next
`make start` recreates the database and applies all migrations.

In development the sign-in list holds `admin`, so the first sign-in with that
name creates the account. `ADMIN_USERS` in `.env` replaces the list. To test
a real mail adapter locally, copy `.env.example` to `.env` in the main
checkout; dev loads it on every start, from every worktree, and real
environment variables win over `.env` values.
