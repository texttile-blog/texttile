#!/bin/sh
# Bunny assigns a group to its persistent volume. Keep that group when dropping
# privileges so File.cp can preserve metadata on newly created upload files.
set -eu

database_dir=$(dirname "$DATABASE_PATH")
mkdir -p "$database_dir" "$UPLOADS_PATH"

if [ "$(id -u)" = 0 ]; then
  # The container sandbox can deny ioprio_set. Keep conversion running with
  # ionice's documented fallback, while retaining nice and ffmpeg's limits.
  mkdir -p /usr/local/bin
  cat > /usr/local/bin/ionice <<'IONICE'
#!/bin/sh
exec /usr/bin/ionice -t "$@"
IONICE
  chmod 755 /usr/local/bin/ionice
  export PATH="/usr/local/bin:$PATH"
  chown nobody "$database_dir" "$UPLOADS_PATH"
  volume_gid=$(stat -c '%g' "$UPLOADS_PATH")
  exec gosu "nobody:$volume_gid" sh -c '/app/bin/migrate && exec /app/bin/server'
fi

/app/bin/migrate
exec /app/bin/server
