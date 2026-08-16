# Texttile

Texttile is a blog CMS for two people who write together. Phoenix, LiveView and
SQLite in one Docker image. One volume holds the whole installation: the
database and every uploaded file. Nothing else is needed to run it.

You can think of Texttile as a self-hosted alternative to WordPress, Ghost and
Substack, in the spirit of "one container, your data".

## What makes Texttile special?

These are the promises the product is built on. Keep them intact.

### 1. Nothing is loaded from outside

A reader's browser talks to this server and to nothing else. No CDN, no
third-party script, no tracker, no captcha, no hosted font, no external video
player. The statistics are counted here, the spam filter runs here, the mail
leaves from here. A change that adds an outside call breaks the product, not
just a rule.

### 2. Light enough for a slow line

Texttile is written for a person reading on a phone far from a data center.
Pages stay small, JavaScript stays little, and a picture is only ever as large
as the screen asks for. Weigh every kilobyte you add. Continuously repainting
animations are out; they cost the reader battery and the writer frames.

### 3. Written together

Two people work on the same entry at the same time. Only the body text is
locked, and only softly: the holder writes, the other one watches the text
arrive live and can take over in one click. Tiles, tags, settings and publish
controls stay free for both, last write wins per field. The admin area shows
who is on which screen. This is the hero feature, and it is why the lock is a
GenServer and not a database column.

### 4. The writer's Markdown, byte for byte

The body is plain text, not a document tree. What the writer typed is what is
stored, character for character, so a version diff shows real edits and
nothing else. Never normalize, reflow or clean Markdown, and never introduce an
editor that serializes it from a tree (ProseMirror, TipTap, Milkdown).

### 5. Minimal, and everybody is an admin

A part is right when nothing is left to take away. There are no roles and no
permission matrix: `ADMIN_USERS` is the whole access model, and it is built for
people who trust each other. Settings have no Save button. When a feature needs
a configuration switch to be bearable, the feature is wrong.

### 6. Mobile first

Reading and writing are laid out for a phone. A wide screen gets the same
screens with more room, never a different product. Judge a UI change on the
phone screenshot first.

## A note from Klaus

I like ambitious ideas, simple systems, and software that feels obvious. Do not
keep complexity because it is already there. Do not add machinery because it
looks architecturally impressive. Understand the real constraint, then fight for
the smallest model that makes the correct behavior unsurprising.

Channel both "measure twice, cut once" and YAGNI. Fight scope creep. Propose a
bold idea when it truly helps, and say so plainly instead of building it behind
my back.

A question is read-only. If I ask how hard something is, why something happens,
or whether something should be done, answer it and offer the change. Do not
start editing.

Match the ceremony to the task. One agent in one pass beats a panel for
ordinary work.

The rest of this file helps you find your way and make changes well. Treat it as
good defaults, not as scripture. My preferences in the moment beat anything
written here. If a rule fights the task in front of you, say so and get my
sign-off before breaking it.

## A small glossary

Use this language in code, in the UI and when talking to me.

- **you** means the agent reading this file and changing Texttile.
- **we, us, maintainers** mean Klaus and the people building Texttile.
- **admin** means a person named in `ADMIN_USERS` who signs in and writes.
- **reader** means anybody who is not signed in.
- **entry** means one blog item, a post or a page. Every word a person reads
  says entry. The routes and modules keep the older noun on purpose:
  `/admin/texts`, `TexttileWeb.TextsLive`, `Texttile.Articles`.
- **text** means the written content of an entry: the title and the body.
- **working copy** means the text in the editor.
- **live version** means the version `live_version_id` points at. It is the only
  text a reader, the feed or a subscriber mail ever gets, and only publishing
  moves it. Every reader path goes through `Articles.as_read/1`.
- **version** means a stored copy of a title and a body. Nothing else is
  versioned.
- **tile** means one picture or one video in a gallery.
- **gallery** means the one ordered set of tiles an entry has. Its order lives
  in `gallery_date` and nowhere else.
- **rendition** means a scaled picture or a converted video. It is made again on
  demand and never backed up.
- **the lock** means the soft document lock on the body text.
- **admin area** means the signed-in area behind `/admin`, `TexttileWeb.Admin`.
  Never "the desk". `Admin` alone names the person.
- **installation** means everything under `/data`: the database and the uploads.
- **bundle** means one entry's folder inside an import or export zip. The format
  contract is `IMPORT.md`.

## The three ways to hurt yourself

1. **Taking port 4000, or killing by pattern.** Port 4000 belongs to Klaus and
   to `make start`. Never bind it and never kill its process. Use 4440 for tests
   through `TEST_PORT` and 4441 to 4449 for your own servers. Never `pkill -f`,
   never `pgrep | kill`, never kill a PID you found by matching a name or a
   worktree path: your own process carries that path in its argv, and this
   machine runs several servers at once. Kill only a PID you captured at spawn.
2. **Writing over the shared development state.** Every worktree shares the main
   checkout's `texttile_dev.db`, its `priv/uploads` and its `.env`. That is real
   data Klaus works in. Remove only the records your own run created, through
   the application or by exact identifier. Never delete development data
   wholesale, and never re-run a cleanup script from an earlier round without
   first checking what it now matches.
3. **Reaching production, or working on `main`.** Never deploy, never touch a
   live database, and never point a server at production data unless you were
   told to. `texttile-staging` and `texttile-demo` are real sites. Never commit
   on `main`; every branch starts in a sibling worktree. When a task is next to
   any of this, say exactly what you are about to touch before you touch it.

## Hit every surface

The most common defect in this repo is a change that works on the path you
tested and is missing everywhere else. Before you call a change done, walk this
list and say which entries applied.

- **The two texts of an entry.** A live entry has a working copy and a live
  version. Decide which one your change reads. Readers, the list, the tag
  archive, the search, the feed and the subscriber mail take the live version
  through `Articles.as_read/1`. A signed-in admin sees the working copy on the
  site instead, with a strip that says so.
- **Signed in and signed out.** A draft answers at its future address for an
  admin and 404s for a reader. The blog password gate and the feed have to
  agree.
- **Both people.** Two admins may have the same entry open. Check the lock
  holder and the read-only watcher, the takeover, and what PubSub broadcasts.
- **Reverse states.** If you added a way in, add the way out and the way to see
  it. Publish needs unpublish, protect needs unprotect, delete needs restore,
  subscribe needs unsubscribe, import needs export. A one-way door is a bug.
- **Language.** Every sentence a person reads goes through `gettext`. Run
  `mix gettext.extract --merge` and translate the German file; `mix precommit`
  refuses an out-of-date template. Sentences the browser says live in
  `TexttileWeb.JsStrings` and reach `assets/js/i18n.js` as `data-words`.
- **Phone and desktop.** Judge both screenshots together, phone first.
- **Settings.** A new switch belongs in Settings with a default that fits a
  fresh installation, and it saves itself with no Save button.
- **Docs.** `README.md` is for the person running Texttile: update it in the
  same pull request as any change to environment variables, ports, Docker,
  deployment or Make targets. `IMPORT.md` is the bundle format contract.
  `PHOENIX.md` is the framework guide. This file holds the permanent rules.

## Dev servers

- `make prepare` installs dependencies, assets and the Playwright browser.
  `make tools` installs ffmpeg and ffprobe, which the video conversion shells
  out to.
- `make start` runs the development server on port 4000. That one is Klaus's.
  Start your own on 4441 to 4449.
- The server listens on the network address, not on `localhost`, so a phone in
  the same network reaches it. `bin/dev-host` prints the address that gets
  picked, and `DEV_HOST` replaces it.
- Development needs no environment variables. A git-ignored `.env` in the main
  checkout is loaded from every worktree, and real environment variables win
  over it. Mail from the development machine goes out through the adapter that
  `.env` configures, so `/dev/mailbox` can stay empty.
- The development sign-in list holds `admin`, so the first sign-in with that
  name creates the account. `ADMIN_USERS` in `.env` replaces the list.
- Stop what you started, by the PID you tracked. See rule 1.

## Test data

An empty database is a bad test. Work from real data instead of pointing at it.

- `make db-pull` fetches a consistent snapshot of `texttile-staging` to
  `texttile-snapshot.db` in the shared checkout root. It uses `VACUUM INTO`,
  which is safe while a server has the file open.
- Copy a SQLite database only with `VACUUM INTO`, `.backup` or `make db-pull`. A
  plain `cp` of a live file is a corrupt copy, and it needs the `-wal` and
  `-shm` siblings.
- Never send test mail to a personal address. Use the local preview mailbox or
  the Resend addresses `delivered@resend.dev` and `bounced@resend.dev`. Ask
  before any real recipient.

## Verifying

- **Write the failing test first.**
- Test business logic with unit tests under `test/texttile`. Test what a user
  was promised through the real UI, with headless browser tests under
  `test/e2e`.
- Browser tests enter screens through the `TexttileWeb.E2E` helpers, which wait
  for the live page and for the gallery's `data-ready`. Never act on a page you
  did not wait for.
- A test that creates state outside the transaction (locks, presence,
  registries, application environment, uploads) clears it. Shared cleanup lives
  in `test/support/data_case.ex`.
- Before a pull request, run `mix test --max-cases 4`. One green run under a
  different command is not enough. `make check` runs what CI runs, in the order
  CI runs it.
- Treat a failure that only happens in CI as an ordering or timing race until
  you have disproved it. Reproduce suspected contamination by ordering the files
  with `--seed 0`, and timing races under CPU load. Rerunning proves nothing.
- Finish every UI change with `/visual-qa` in a headless browser, and judge the
  desktop and phone screenshots together.

## Pull requests

- Never work on `main`. Create every branch from `main` in a sibling worktree
  named `../texttile-<slug>`, then enter it with EnterWorktree so the session
  and the terminals follow. Keep at most ten registered worktrees. Never force
  a removal, and never remove a dirty or unintegrated one. If you cannot get
  under the limit safely, ask what to remove.
- Use `feature/<slug>` for a user-facing capability, a change across several
  modules, or work that will need more than two commits. Use a short branch name
  for anything smaller.
- Branch names, commits and pull request text are English. Add no co-author and
  no generation trailer.
- Raise the version in `mix.exs` in the same pull request, before you open it.
  Read the version on `main`, not on your branch, and raise it by one step: the
  patch number for a repair or a small change, the minor number for a new
  capability, the major number when behavior, stored data or configuration
  breaks. Never lower it and never skip a step. If another pull request takes
  your number first, raise yours again on top of theirs. Settings shows this
  number, and it is the only mark of which build runs.
- Rebase onto the latest `main` before you open a pull request.
- Open a normal pull request, never a draft: a draft gets no review bot. Title in
  plain language, body with the problem in a sentence or two and then how you
  solved it. End with the model and the harness that did the work. UI changes
  carry before and after images.
- One concern per pull request. If the description says "also", split it.
- Every open pull request gets `/review-pr`. Fix findings with commits on its
  branch. Review agents leave untracked `*_probe_test.exs` files behind: turn a
  real finding into a fix plus a real test, and never commit a probe.
- When you babysit a pull request, poll checks and comments newer than the last
  push, verify each bot finding against the source, fix the real ones, and
  dismiss a false positive with a written reason. Stay quiet when nothing is
  new. Stop when the bots are green on the latest commit.
- Never merge a pull request.

## How it works

One Phoenix application serves both faces of the blog. Reader pages are
controllers and small scripts; the admin area is LiveView. State is one SQLite
file plus a directory of uploads, both under `/data`.

The lock is one GenServer per open entry, under a Registry and a DynamicSupervisor
of its own, so Elixir's message ordering gives mutual exclusion for free. The
lock holder's keystrokes go out over PubSub and land in the watcher's read-only
view. Autosave writes the working copy and keeps no history. A version is made
on a deliberate save, on a publish, on a handover and before a restore, never on
an autosave, and never when the text is byte-identical to the newest one.

The body editor is one isolated LiveView hook over CodeMirror. Its inputs are
text, remote updates and a read-only flag. Its outputs are changes, cursor and
activity pings. Nothing else may reach into it.

Pictures are scaled on demand and cached. A video is converted once by ffmpeg,
one at a time, on one thread, at the lowest scheduling priority, under a task
supervisor. Mail leaves in a supervised task, so a click never waits for another
server.

## Where code lives

- `lib/texttile/` holds the contexts: `articles` (editing, publishing, reading,
  versions, the lock, redirects, the schedule), `gallery`, `comments`,
  `newsletter`, `stats`, `videos`, `uploads`, `import`, `backup`, `settings`,
  `accounts`.
- `lib/texttile_web/live/` holds the admin screens: editor, texts, comments,
  newsletter, stats, settings, profile, import.
- `lib/texttile_web/controllers/` holds the reader pages and the feed.
  `lib/texttile_web/components/` holds the shared markup.
- `assets/js/` holds the hooks. `body_ed.js` is the editor, `gallery.js` the
  tiles, `i18n.js` the browser sentences. `assets/js_test/` runs under
  `node --test`.
- `test/texttile/` is unit, `test/texttile_web/` is controller and LiveView,
  `test/e2e/` is browser, `test/support/` holds the cases and fixtures.
- `priv/gettext/` holds one file per language. English is the source and has
  none.
- `config/`, `Dockerfile`, `fly.toml`, `Makefile` and
  `scripts/texttile-backup.sh` are the runtime and the operations.
- Read `PHOENIX.md` before writing Phoenix code.

## Configuration and runtime

- Texttile reads its configuration from environment variables at boot, and a
  missing one stops the boot with a message that names it. `README.md` holds the
  table. Keep it true.
- Keep both Fly configurations aligned. This checkout deploys `texttile-staging`
  to `staging.texttile.blog`. The `texttile-blog/demo` repository deploys
  `texttile-demo` to `demo.texttile.blog` from the published image. Only the app
  name, `PHX_HOST` and the demo `[build]` section may differ. Mirror changes to
  Fly settings, ports, volume paths and image names into the demo repository.
- One machine, never two. SQLite takes one writer and a volume mounts on one
  machine. `README.md` says what a second one costs.
- Treat `/data` as the complete installation.

## Taste

- Keep it simple. Channel YAGNI unless told otherwise.
- Type safety where it earns its place, not everywhere.
- Comments explain how a thing is used and what is not obvious, not every line.
  A comment moves when its code moves.
- Complexity belongs at the edges: the adapters, the converters, the importer.
  The contexts stay plain and the UI stays dumb.
- Write focused tests that protect real behavior. No endless smoke tests, and no
  regression test for a feature that is gone.
- Be careful with anything destructive that Klaus did not ask for.

## Prose

- Apply `/ste-writing` to English pull request text, documentation, error
  messages and UI copy. Strict mode for procedures and errors, flavored mode
  everywhere else.
- Never use an em dash. Use a comma, a colon, parentheses or two sentences.
- Say **entry**, not "text", in everything a person reads. Say **admin area**,
  never "the desk".
- Keep it short. A sentence a reader has to read twice is a sentence to rewrite.
