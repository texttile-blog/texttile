# ADR-001: One Phoenix app, one SQLite file, one Docker image, one volume

## Status
Accepted

## Date
2026-08-02

## Context
Texttile is a blog for two people who write together and run it themselves.
The person who runs it is not an operator by trade. The product promise is
"one container, your data": a reader's browser talks to one server, and the
whole installation can be moved by moving one directory.

## Decision
One Phoenix application serves the reader pages and the admin area. State is
one SQLite file plus a directory of uploads, both under `/data`. The app ships
as one Docker image that prepares `/data`, runs the migrations, drops root and
starts the server. `DATABASE_PATH` and `UPLOADS_PATH` are the whole contract
between the app and its host (`Texttile.Config`). A missing configuration
variable stops the boot with a message that names it.

## Alternatives Considered

### PostgreSQL
- Pros: several writers, managed hosting, no single-writer limit
- Cons: a second process or a hosted service, a second thing to back up, a
  connection string to manage
- Rejected: the installation would no longer be one directory, and the backup
  would no longer be one file copy

### Several containers or a managed platform per concern
- Cons: the reader's data would spread over services the blog owner does not
  hold
- Rejected: it breaks "one container, your data"

## Consequences
- One machine, never two. SQLite takes one writer and a volume mounts on one
  machine. A second machine would answer readers out of a second, older
  database. `README.md` says this for every host, not only Fly.
- `/data` is the complete installation. Copying it is the restore procedure.
- The database is copied only with `VACUUM INTO` or `.backup`, never with a
  plain `cp` of a live file.
- Long work (video conversion, import, hashing for the backup manifest) must
  stay out of the write transaction, because one open writer blocks every save.
- Migrations run once, in the container command, not as a child of the
  supervision tree.

## Sources
- #1 "Project setup: Phoenix app, SQLite, Docker runtime, Fly config, CI"
- `README.md`, "One machine, never two"
- `lib/texttile/config.ex`, `Dockerfile`, `docker-entrypoint.sh`
