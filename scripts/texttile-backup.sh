#!/usr/bin/env bash
#
# texttile-backup.sh - pull-based backup client for a self-hosted Texttile.
#
# Fetches the manifest from your Texttile instance, downloads every file it
# does not have yet, then downloads a consistent copy of the database.
#
# Archive semantics: files are only ever ADDED here. A file removed from the
# site stays in your backup. This is a backup, not a mirror.
#
# Requirements: curl, jq, flock, and sha256sum or shasum
#   (Debian, Raspberry Pi OS: apt install curl jq)
#
# Configuration comes from the environment or from a config file
# (default ~/.texttile-backup.conf):
#
#   TEXTTILE_URL=https://texttile.example.com
#   TEXTTILE_TOKEN=<the token from Settings, section Backup>
#   BACKUP_DIR=/mnt/backup/texttile
#   DB_KEEP=30          # dated database copies to keep (default 30)
#
# Usage:
#   ./texttile-backup.sh
#
# Cron, every day at 03:17, with mail on failure:
#   17 3 * * * /home/pi/texttile-backup.sh >> /var/log/texttile-backup.log 2>&1
#
# To restore:
#   1. copy files/ into the uploads directory of the installation
#   2. copy the newest db/texttile-*.db to the database path
#   3. start the container; the image renditions are made again on demand

set -euo pipefail

# ---------------------------------------------------------------- configuration

CONFIG_FILE="${TEXTTILE_BACKUP_CONFIG:-$HOME/.texttile-backup.conf}"
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
fi

TEXTTILE_URL="${TEXTTILE_URL:-}"
TEXTTILE_TOKEN="${TEXTTILE_TOKEN:-}"
BACKUP_DIR="${BACKUP_DIR:-}"
DB_KEEP="${DB_KEEP:-30}"

die() { printf 'texttile-backup: %s\n' "$*" >&2; exit 1; }
log() { printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

[ -n "$TEXTTILE_URL"   ] || die "TEXTTILE_URL is not set (environment or $CONFIG_FILE)"
[ -n "$TEXTTILE_TOKEN" ] || die "TEXTTILE_TOKEN is not set (environment or $CONFIG_FILE)"
[ -n "$BACKUP_DIR"     ] || die "BACKUP_DIR is not set (environment or $CONFIG_FILE)"

TEXTTILE_URL="${TEXTTILE_URL%/}"   # take off a trailing slash

for cmd in curl jq flock; do
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done

# The two commands that are spelled differently on Linux and on macOS.
if command -v sha256sum >/dev/null 2>&1; then
  sha256_of() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  die "required command not found: sha256sum (or shasum)"
fi

if stat -c%s . >/dev/null 2>&1; then
  file_size() { stat -c%s "$1"; }
else
  file_size() { stat -f%z "$1"; }
fi

FILES_DIR="$BACKUP_DIR/files"
DB_DIR="$BACKUP_DIR/db"
mkdir -p "$FILES_DIR" "$DB_DIR"

# One run at a time: a long first sync must not meet the daily cron.
exec 9>"$BACKUP_DIR/.lock"
flock -n 9 || { log "another run is in progress, stopping here"; exit 0; }

TMPDIR_RUN="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_RUN"; }
trap cleanup EXIT

# The token travels in the header, never in the address: an address goes
# into the access log of every machine on the way.
api() {
  curl -fsS --location \
       --retry 3 --retry-delay 5 --retry-connrefused \
       --connect-timeout 15 --max-time 3600 \
       -H "Authorization: Bearer $TEXTTILE_TOKEN" \
       "$@"
}

# ------------------------------------------------------------------- manifest

log "fetching the manifest from $TEXTTILE_URL"
MANIFEST="$TMPDIR_RUN/manifest.json"
api "$TEXTTILE_URL/backup/manifest" -o "$MANIFEST" \
  || die "could not fetch the manifest. Check the address, the token, and that the backup API is switched on in Settings."

jq -e 'has("files") and has("database")' "$MANIFEST" >/dev/null 2>&1 \
  || die "the manifest is not JSON of the shape this client expects"

total="$(jq -r '.files | length' "$MANIFEST")"
version="$(jq -r '.texttile_version // "unknown"' "$MANIFEST")"
log "Texttile $version, $total file(s) in the manifest"

# ---------------------------------------------------------------------- files

downloaded=0
skipped=0
gone=0
failed=0

while IFS=$'\t' read -r id path size sha; do
  [ -n "$id" ] || continue

  # The path comes from the server. Refuse anything that could write
  # outside the backup directory.
  case "$path" in
    /*|*..*|"")
      log "REFUSED a suspicious path from the server: $path"
      failed=$((failed + 1))
      continue
      ;;
  esac

  dest="$FILES_DIR/$path"

  # The originals never change under their name, so having the file at
  # the right size is enough to skip it. The hash below is what proves
  # a download arrived whole.
  if [ -f "$dest" ] && [ "$(file_size "$dest" 2>/dev/null || echo -1)" = "$size" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  part="$dest.part"

  # A file deleted between the manifest and now is no error: the next
  # manifest will not name it either.
  status="$(curl -sS --location \
                 --retry 3 --retry-delay 5 --retry-connrefused \
                 --connect-timeout 15 --max-time 3600 \
                 -H "Authorization: Bearer $TEXTTILE_TOKEN" \
                 -o "$part" -w '%{http_code}' \
                 "$TEXTTILE_URL/backup/file/$id" || echo 000)"

  if [ "$status" = "404" ]; then
    log "gone from the site since the manifest: $path"
    rm -f "$part"
    gone=$((gone + 1))
    continue
  fi

  if [ "$status" != "200" ]; then
    log "FAILED to download ($status): $path"
    rm -f "$part"
    failed=$((failed + 1))
    continue
  fi

  actual="$(sha256_of "$part")"
  if [ -n "$sha" ] && [ "$sha" != "null" ] && [ "$actual" != "$sha" ]; then
    log "FAILED the checksum: $path (expected $sha, got $actual)"
    rm -f "$part"
    failed=$((failed + 1))
    continue
  fi

  # Into place only now: an interrupted run costs one file, not the lot.
  mv -f "$part" "$dest"
  downloaded=$((downloaded + 1))
done < <(jq -r '.files[] | [.id, .path, .size, (.sha256 // "")] | @tsv' "$MANIFEST")

log "files: $downloaded new, $skipped already here, $gone gone from the site, $failed failed"

# ------------------------------------------------------------------- database
# Last on purpose: the database in this backup then never names a picture
# that is missing from it.

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
db_part="$TMPDIR_RUN/texttile-$stamp.db"

log "fetching the database"
if ! api "$TEXTTILE_URL/backup/db" -o "$db_part"; then
  log "FAILED to fetch the database"
  failed=$((failed + 1))
else
  # Every SQLite file starts with this.
  if [ "$(head -c 15 "$db_part" 2>/dev/null)" != "SQLite format 3" ]; then
    log "FAILED: what arrived is no SQLite file"
    failed=$((failed + 1))
  else
    mv -f "$db_part" "$DB_DIR/texttile-$stamp.db"
    ln -sfn "texttile-$stamp.db" "$DB_DIR/latest.db"
    db_size="$(file_size "$DB_DIR/texttile-$stamp.db")"
    log "database saved: texttile-$stamp.db ($db_size bytes)"

    # Dated copies are rotated. The files are never rotated: a picture
    # you took out of the blog is a picture this archive keeps.
    # shellcheck disable=SC2012
    ls -1t "$DB_DIR"/texttile-*.db 2>/dev/null \
      | tail -n +$((DB_KEEP + 1)) \
      | while read -r old; do
          log "rotating out $(basename "$old")"
          rm -f "$old"
        done
  fi
fi

# -------------------------------------------------------------------- summary

if [ "$failed" -gt 0 ]; then
  log "finished WITH $failed ERROR(S)"
  exit 1
fi

log "finished"
exit 0
