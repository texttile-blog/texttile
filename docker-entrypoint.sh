#!/bin/sh
# Prepares the data directories, then drops root privileges.
# Host volumes are often mounted with root ownership. The app runs as nobody.
set -e

mkdir -p "$(dirname "$DATABASE_PATH")" "$UPLOADS_PATH"

# Opt in to receiving HTTP files on the uploads volume before the app starts.
# Plug reads PLUG_TMPDIR at boot and owns its temporary-file cleanup.
if [ -n "${PLUG_TMPDIR:-}" ]; then
  mkdir -p "$PLUG_TMPDIR"
  if [ "$(id -u)" = "0" ]; then
    chown nobody "$PLUG_TMPDIR"
  fi
fi

if [ "$(id -u)" = "0" ]; then
  chown nobody "$(dirname "$DATABASE_PATH")" "$UPLOADS_PATH"
  exec gosu nobody "$@"
fi

exec "$@"
