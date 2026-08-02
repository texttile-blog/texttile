#!/bin/sh
# Prepares the data directories, then drops root privileges.
# Host volumes are often mounted with root ownership. The app runs as nobody.
set -e

mkdir -p "$(dirname "$DATABASE_PATH")" "$UPLOADS_PATH"

if [ "$(id -u)" = "0" ]; then
  chown nobody "$(dirname "$DATABASE_PATH")" "$UPLOADS_PATH"
  exec gosu nobody "$@"
fi

exec "$@"
