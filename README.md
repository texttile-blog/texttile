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
| `SECRET_KEY_BASE` | yes              | none                        | signs cookies; generate with `mix phx.gen.secret` |
| `PHX_HOST`        | yes              | `example.com`               | public hostname                                   |
| `PORT`            | no               | `4000`                      | HTTP port                                         |
| `MAIL_ADAPTER`    | no               | local preview mailbox       | `resend`, `postmark`, `brevo`, `smtp`, or `ses`   |
| `MAIL_FROM`       | no               | `texttile@PHX_HOST`         | sender address for outgoing mail                  |

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

## First run

A fresh installation has no accounts. Open the site in a browser within 30
minutes of the start. The setup screen asks for a username, an email address,
and a password, and makes this account the first admin.

After 30 minutes the setup screen closes. To open it again, restart the
server. Once an account exists, the setup screen stays closed permanently.

A confirmation mail goes to the address you enter. It contains the username.
It does not contain the password.

## Deploy on Fly.io

`fly.toml` in this repo deploys from source with one volume for the database
and the uploads. Its header documents the one-time setup (app, volume,
secrets, certificate).

## Development

Requires Elixir 1.19+, Erlang/OTP 28+, and Node.js (for browser tests).

```sh
make start   # dev server on port 4000, no configuration needed
make test    # unit tests plus end-to-end browser tests
```

All git worktrees of the repository use one dev database: the
`texttile_dev.db` file in the main checkout. Outside a git checkout, the
database file stays next to the code.

Development needs no environment variables. To test a real mail adapter
locally, copy `.env.example` to `.env`; dev loads it on every start, and real
environment variables win over `.env` values.
