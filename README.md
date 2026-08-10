# texttile

A minimal blog CMS with multiplayer editing. Phoenix, LiveView, and SQLite in
one Docker image. One volume holds all state. No external services are
required.

Status: early development. Do not use it for a real site yet.

## Principles

- Minimal. A part is right when nothing is left to take away.
- Self-contained. One image, one volume, no external service, no tracker.
  Everything a reader loads comes from this server.
- Light in the browser. Small pages and little JavaScript, so the blog opens
  on a slow line far from a data center.
- Written together. Two people work on the same entry at the same time, and
  the admin area shows who is where.
- Mobile first. Reading and writing are laid out for a phone; a wide screen
  gets the same screens with more room.
- Everybody is an admin. No roles, no permission matrix: `ADMIN_USERS` is the
  whole access model.

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
writes that header itself. The comment rate limit and the reader count both
read it, so a header the caller may write is a header a spammer may change.
Without the variable both count by the address of the connection, which is
right everywhere except behind a proxy. Of a header that carries a list
(`X-Forwarded-For`), the last entry counts: that is the one the proxy
appended, and everything before it is what the caller sent.

## Run with Docker

```sh
docker run -d --name texttile \
  -p 4000:4000 \
  -v texttile-data:/data \
  -e SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  -e PHX_HOST=blog.example.com \
  -e ADMIN_USERS=klaus,julia \
  ghcr.io/texttile-blog/texttile:latest
```

The container prepares the data directories, runs migrations, drops root, and
starts the server. All state lives in `/data`. Without `ADMIN_USERS` the site
runs, but nobody can sign in. Put your username there before the first start.

The image is `linux/amd64`. An update is: pull the new image, start the
container again.

```sh
docker pull ghcr.io/texttile-blog/texttile:latest
docker rm -f texttile
# then the docker run above again
```

`latest` is the last commit on `main`. Every build also gets its commit as a
tag (`ghcr.io/texttile-blog/texttile:<sha>`), so an installation can stay on
one build.

## Readers and admins

Readers get the list of published entries at `/blog`, each entry at its own
address, and every published page in the menu. A post lives under the day it
went live, `/2026/08/23/harbor-mornings`; a page lives at its slug alone,
`/about-us`. Admins sign in at `/login` and work at `/admin`, which sends
them on to the entries at `/admin/texts`.

The root, `/`, is the front door. It sends the reader to `/blog`, or it
shows the one page you picked in Settings > Front page. The list keeps
`/blog` either way, so a bookmark of it stays good when you change your
mind.

The list shows ten entries a page and then a pager. Change the number in
Settings > Front page. Over the list stands the archive: one line of years,
and the months of the open year under it, only the months that carry
something. Both are addresses (`/blog?y=2026&m=8`), so a year or a month can
be copied and bookmarked. Under an entry stand the way to the entry before
it and the one after it, and the About block from Settings > About.

An entry that is not live yet answers at the address it will wear, but only
for somebody signed in; a reader gets a 404 there. So the way out of the
editor leads into the real reader's page, drafts included.

Changing the slug or the publish date of a live entry moves it, because the
address of a post carries its date. The old address stays alive as a
permanent redirect, and the editor lists what is standing under the address
field, each with a Delete for the day you want it gone.

The blog can sit behind one shared password (Settings > Access). It is an
access word to hand around, not a login: it is stored in plain text, one
word opens the whole blog, and it guards the blog or nothing. No entry has a
switch of its own.

While the blog is protected, the editor of every entry shows the word under
Share, so you never have to go and look it up. Once an entry is live, the
same block holds the lines to hand on: the title, the address, and the
password under it. Copy puts them on the clipboard.

## Pictures and videos

Pictures and videos go into an entry the same way: paste one into the body,
drop one on it, or add it to the entry's gallery. Every original file is kept
as it came, below `UPLOADS_PATH`, and nothing leaves the server: no external
player, no third-party host.

One roof holds for a picture and for a video: Settings > Storage > Biggest
upload, 512 MB by default. The browser turns a bigger file away before the
upload starts, and the server stops reading one that arrives anyway.
Settings > Storage also reports what lies in each folder of the volume, how
much it weighs, and how much room is left.

A picture is scaled to display sizes on demand, capped by Settings > Images
> Max longer edge. A video is converted once, by ffmpeg, into one MP4 (H.264
and AAC) that every browser plays, plus a poster frame. Settings > Videos >
Max longer edge caps it, 1280 px by default; nothing is ever scaled up. A
new value applies to what is converted after the change, because a converted
video is never made again.

The conversion is the most expensive thing this server does, so it stays out
of everybody's way: one video at a time, ffmpeg on one thread, at the lowest
scheduling priority, and with idle disk priority where the kernel offers it.
While a video converts, the admin area shows the state on its tile and under
the entry; the reader's page shows the video once it is ready. The upload
takes `.mp4`, `.mov`, `.m4v`, `.webm`, `.avi` and `.mkv`.

The container brings ffmpeg. On a development machine, `make tools` installs
it.

## Language

A blog has one language, and Settings > Site is where you pick it. English
and German are shipped. The choice reaches everything a person reads: the
reader pages, the admin area, the dates, and every mail the blog sends. It
also sets `lang` on every page and `<language>` in the feed.

What you write yourself is not touched. Titles, entries, tags, the About
text and the site description stay in the language you wrote them in; only
the words around them change.

English is the language of the source, so it has no translation file: a
sentence nobody translated is shown in English. Each other language is
exactly one file, `priv/gettext/<code>/LC_MESSAGES/default.po`, and it holds
all of them, the error messages and the sentences the browser says included.

To add a language:

```sh
# 1. add {"fr", "Français"} to @languages in lib/texttile/i18n.ex
# 2. write the file
mix gettext.merge priv/gettext --locale fr
# 3. translate every msgstr in priv/gettext/fr/LC_MESSAGES/default.po
mix test test/texttile/translations_test.exs   # names every gap
```

Nothing else changes: the settings menu reads the list, and the new language
is there.

## Feed

The blog has an RSS feed at `/feed.xml`. It carries every published post,
newest first, with the whole entry. Each page points at it from its head, and
the footer carries an RSS link.

A blog behind the shared password has no feed: `/feed.xml` answers 404 and
no page offers a link. A feed reader cannot enter a password, and the entries
would travel out of the gate. Remove the password to get the feed back.

## Comments

Readers can comment under every entry that allows it (the switch is in the
entry's settings). There is no approval queue. By default a new address gets
one confirmation mail. The comment appears when its reader follows the
mailed link, and every later comment from that address appears at once.
Turn the confirmation off in Settings > Comments and no comment waits for
anything.

A reader can give the address of their own site with the comment. The name
over the comment then leads there, with `nofollow`, and a bare
`christel.example` is enough.

Comment while signed in and the form fills itself: the name, the address and
the website come from your account and this blog, the three fields take no
typing, and the comment stands under the entry at once. The sign-in already
proved the address, so no confirmation mail goes out. The comment counts
show under each card, on `/blog` and on `/admin`.

Admins see all comments at `/admin/comments` and on the Comments tab of each
text. There they can do three things to a comment:

- **Release** a comment whose reader has not confirmed the address. It puts
  that one comment under the entry. The address itself stays unconfirmed, so
  the next comment from it waits again.
- **Edit** the words. The name and the address stay as the reader sent them,
  and the comment is marked "edited" in the admin area.
- **Delete** it into the trash. Readers stop seeing it at once, and it waits
  30 days at the foot of `/admin/comments`, where Restore puts it back. After
  30 days the comment is removed from the database for good.

Every admin also gets the comment by mail, unless "Mail me every new
comment" is switched off in Settings > Comments. The mail leaves when the
comment stands under the entry, so a comment that still waits for its
reader mails nobody. The address of the reader is never in it.

Spam protection is built in and always on: a honeypot field, a time trap,
and a rate limit per caller. No captcha, no Google, no third parties.

## Newsletter

Readers can put their address on the newsletter list through the form in
the footer of every page. The address gets one confirmation mail and
receives entries only after its reader follows the mailed link. Admins see
the list at `/admin/newsletter` and can add addresses by hand; an added
address is confirmed at once.

When a post goes live with "Email subscribers" checked (the switch is in
the entry's settings), every confirmed address gets one plain email: the
title, the first paragraph, and the address the entry lives at. If the
blog sits behind the shared password, the mail includes it. Every mail
carries the way off the list. The email goes out once per entry;
publishing the same entry again does not send it again.

The subscribe form wears the same spam protection as the comment form.

## Stats

Texttile counts its own readers at `/admin/stats`, and each entry again on
its Stats tab in the editor. Nothing is loaded from anywhere else and
nothing is sent anywhere else.

Every reader page reports itself to this server with one small request. It
carries three things: the address of the page, the entry it shows, and the
address the reader came from. No cookie is set, none is read, and none is
sent with that request.

The server turns the caller into one number for the day: their IP address
and their browser line, hashed together with a secret this server draws
every morning and keeps in memory only. The secret is never written to
disk and is gone at midnight, so no row can be traced back to an address,
and nothing links the same reader to two days. That is what "people" counts:
a reader who comes back next week counts as one person each time. The IP
address itself is never stored.

Four rules keep the numbers about people, not machines:

- The report needs JavaScript, so almost everything that crawls the web
  never reports at all.
- A browser line that says bot is dropped, and so is a page the browser
  only fetched ahead.
- One reader counts once per page every half hour, so reloading changes
  nothing.
- One caller writes at most 60 views a minute.

An admin reading their own blog is not a reader: while you are signed in,
no page reports itself. Drafts, scheduled entries and previews count for
nobody.

The numbers live in the `page_views` table in your database, one row per
counted view. They are yours; nothing leaves the server.

The referrer and the address of a page come from the browser, so the
tables of sources and of other addresses hold the 20 biggest and say so
when they are full. The top entries table counts entries, which the blog
knows itself, so it holds 20 without a word.

If a proxy stands in front of Texttile, set `CLIENT_IP_HEADER` (see
[Configuration](#configuration)). Without it every reader behind the proxy
shares one address, and the counter reads them as one person.

## Accounts

`ADMIN_USERS` names everybody who may sign in. It holds usernames,
separated by commas:

```sh
ADMIN_USERS="klaus,julia"
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

Texttile imports entries from a zip archive of bundles: one folder per entry,
with Markdown, settings, and pictures. A picture can be a file in the bundle
or a URL that the server downloads, so a migration zip stays small.
[IMPORT.md](IMPORT.md) is the complete format contract, written so that a
script or an AI agent can convert any export (WordPress, for example) into
bundles. The import itself lives in Settings: upload the zip, read the
validation report, start the import.

## Backup

Texttile is backed up by pulling, not by pushing. A machine you keep, a
Raspberry Pi at home or a NAS, fetches the whole installation on a clock of
its own. The backup machine holds the token; this server holds nothing that
reaches your copies. Whoever breaks into the server therefore cannot delete
them, which is the one property a push to an object store does not have.

Switch it on in Settings, section Backup:

1. Tick **Serve a backup client at /backup**. Off on a fresh install.
2. Press **Create a token**. It is shown once, and stored here as a hash.
   Write it into the configuration of the backup machine now.
3. Optionally name the addresses the backup machine calls from. Empty is the
   usual case: the token alone decides.

**Last fetched** on the same screen dates the last run, with the address it
came from. A backup that stopped running says nothing until the day you need
it, so that line is where you see it.

### What the client copies

| Data                        | Copied           | Why                                  |
| --------------------------- | ---------------- | ------------------------------------ |
| the SQLite database         | in full, per run | a few MB, and it changes constantly  |
| image and video originals   | what is new      | large, but written once and kept     |
| what ffmpeg made of a video | what is new      | a conversion no page can wait for    |
| the logo and the favicon    | what is new      | small, and not made again by itself  |
| the rendition cache         | never            | made again the moment a page asks    |

Leaving the cache out often halves what travels. After a restore, the
renditions are made again as readers arrive.

### The client

`scripts/texttile-backup.sh` in this repository is the client. It needs
`curl`, `jq`, `flock`, and `sha256sum` (Debian, Raspberry Pi OS:
`apt install curl jq`). Copy it to the backup machine and write its
configuration to `~/.texttile-backup.conf`:

```sh
TEXTTILE_URL=https://blog.example.com
TEXTTILE_TOKEN=<the token Settings showed once>
BACKUP_DIR=/mnt/backup/texttile
DB_KEEP=30          # dated database copies to keep
```

Then run it from cron, every day at 03:17, with mail on failure:

```
17 3 * * * /home/pi/texttile-backup.sh >> /var/log/texttile-backup.log 2>&1
```

It exits non-zero on any failure, so cron reports it.

What it does, and why:

- **It archives, it does not mirror.** A file that disappears from the site
  stays in the backup. A copy that faithfully repeats a deletion is no backup.
- **The layout matches the server.** Restoring is a copy, not a script.
- **The database comes last**, after every file, so the copied database never
  names a picture that is missing from the copy.
- **Database copies are dated and rotated** (30 by default). A few MB a day
  buys a month of points to go back to. The originals are never rotated.
- **Every file is its own request**, downloaded to `.part` and moved into
  place only after its SHA-256 matches. An interrupted run costs one file.

### To restore

1. Copy `files/` into the uploads directory (`UPLOADS_PATH`, `/data/uploads`
   in the image).
2. Copy the newest `db/texttile-*.db` to the database path (`DATABASE_PATH`,
   `/data/texttile.db` in the image).
3. Start the container. The renditions are made again on demand.

### The endpoints

Three, all read-only, all wanting `Authorization: Bearer <token>`. Never a
token in the address line: an address goes into the access log of this
server, of every proxy on the way, and into your shell history.

| Endpoint               | Answers                                                |
| ---------------------- | ------------------------------------------------------ |
| `GET /backup/manifest` | JSON: the database, and every file with size and hash  |
| `GET /backup/db`       | a consistent copy of the database, made with `VACUUM INTO` |
| `GET /backup/file/:id` | one original, by the id the manifest gave it           |

While the feature is switched off, all three answer 404 rather than 403: a
scanner learns nothing about what this server can do. An address that is not
on the allowlist gets the same answer. Every call is logged, served or
refused, and one caller may fetch 600 times a minute.

The first manifest of an existing blog reads every uploaded file once, to
hash it. After that a hash is stored beside the file's size and write time,
and a manifest is a query: ten gigabytes of pictures cost that one first run
and nothing after it.

## Deploy on Fly.io

`fly.toml` in this repo deploys from source with one volume for the database
and the uploads. Its header documents the one-time setup (app, volume,
secrets, certificate).

### Which version runs

Settings > Version names the version of the running build, and every release
raises that number. The page is behind the sign-in and the number stands
nowhere else: a public version number tells an attacker which holes to try.
Name it when you report a problem.

### How big the machine must be

The video conversion decides this, and nothing else does. A blog of words
and pictures runs on one shared CPU and 512 MB of memory (`shared-cpu-1x`,
the `[[vm]]` section of `fly.toml` as it stands).

Videos want more. Give the machine four shared CPUs and 1 GB
(`shared-cpu-4x`) before you upload the first one:

```toml
[[vm]]
  cpu_kind = "shared"
  cpus = 4
  memory = "1gb"
```

ffmpeg runs on one thread at the lowest priority, so the other three keep
the site quick while a video converts, and the gigabyte is what the
conversion itself needs. Videos also need room on the volume: the original
and the converted file live side by side. A machine that stops
mid-conversion loses nothing; the queue picks up every unfinished video when
the app starts again.

## Development

Requires Elixir 1.19+, Erlang/OTP 28+, Node.js (for browser tests), and
ffmpeg (for the video conversion; `make tools` installs it).

```sh
make tools       # install the command line tools: ffmpeg and ffprobe
make start       # dev server on port 4000, no configuration needed
make test        # unit tests plus end-to-end browser tests
make check       # everything CI checks: warnings, formatting, tests
make db-pull     # pull the production snapshot next to the dev database
make db-delete   # delete the shared development SQLite database
```

The development server listens on all interfaces, and `make start` opens
the address of the network instead of `localhost`: the address of the cable
network first, then Wi-Fi, then `127.0.0.1`. A phone in the same network
reaches the server at that address, and `http://localhost:4000` keeps
working on this machine. `bin/dev-host` prints the address that gets
chosen. Everybody in that network can open the site and the dev routes, so
start the server on a network you trust. `DEV_HOST` replaces the address:
`DEV_HOST=localhost make start` writes `http://localhost:4000` into the
links that leave the server, mails included.

All git worktrees of the repository share the dev state of the main
checkout: the `texttile_dev.db` database, the `priv/uploads` folder, and the
`.env` file. `make db-pull` writes the snapshot to `texttile-snapshot.db` in
that same checkout root. Outside a git checkout, everything stays next to the
code.
Stop the development server before running `make db-delete`. The next
`make start` recreates the database and applies all migrations.

Text a person reads goes through `gettext`. After you write a new sentence,
`mix gettext.extract --merge` puts it into the template and into every
language file; `mix precommit` refuses a template that is out of date, so a
sentence cannot slip past the translations unnoticed. The sentences the
browser hooks say are the exception the tool cannot see by itself: they are
listed in `TexttileWeb.JsStrings`, and the layout hands them to
`assets/js/i18n.js` as `data-words`.

In development the sign-in list holds `admin`, so the first sign-in with that
name creates the account. `ADMIN_USERS` in `.env` replaces the list. To test
a real mail adapter locally, copy `.env.example` to `.env` in the main
checkout; dev loads it on every start, from every worktree, and real
environment variables win over `.env` values.
