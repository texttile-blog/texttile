# Port 4000 belongs to the human developer (make start).
# Agents never use it; they run on 4440+ (see AGENTS.md).

.PHONY: prepare tools test check kill-port-4000 start dev-reset db-pull

# Development state is shared by all worktrees, see config/dev.exs.
SHARED_ROOT := $(shell common_dir="$$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; if [ -n "$$common_dir" ]; then dirname "$$common_dir"; else pwd; fi)
DB_DEV := $(SHARED_ROOT)/texttile_dev.db
UPLOADS_DEV := $(SHARED_ROOT)/priv/uploads

# Local, stable path for the remote DB snapshot. Point TablePlus at this file.
DB_LOCAL := $(SHARED_ROOT)/texttile-snapshot.db

# The command line tools the app runs: ffmpeg and ffprobe for the video
# conversion. Run this once per machine; the container has them already.
tools:
	@bin/install-tools

prepare:
	mix deps.get
	mix assets.setup
	npm --prefix assets install
	npm --prefix assets exec -- playwright install chromium
	mix compile

test: prepare
	npm --prefix assets test
	mix test

# What CI runs, in the order CI runs it, so a red build is something
# you saw here first. CI checks the formatting before it runs a single
# test, and a branch whose tests are green still fails there.
check: prepare
	mix compile --warnings-as-errors
	mix format --check-formatted
	npm --prefix assets test
	mix test

kill-port-4000:
	@pids="$$(lsof -tiTCP:4000 -sTCP:LISTEN 2>/dev/null)"; \
	if [ -n "$$pids" ]; then \
		echo "Stopping processes on port 4000: $$pids"; \
		kill $$pids 2>/dev/null || true; \
		sleep 1; \
		pids="$$(lsof -tiTCP:4000 -sTCP:LISTEN 2>/dev/null)"; \
		if [ -n "$$pids" ]; then \
			echo "Force stopping processes on port 4000: $$pids"; \
			kill -9 $$pids 2>/dev/null || true; \
		fi; \
	fi

# Pull a consistent snapshot of a running SQLite DB to $(DB_LOCAL).
# VACUUM INTO gives a stable copy of the live WAL database; never copy the raw file.
# This repository deploys texttile-staging, so that is the default.
# The demo: `make db-pull FLY_APP=texttile-demo`.
FLY_APP ?= texttile-staging

db-pull:
	@echo "Waking the machine..."
	@curl -fs -o /dev/null --max-time 30 https://$(FLY_APP).fly.dev/ || true
	fly ssh console -a $(FLY_APP) -C "/app/bin/texttile rpc \"File.rm(~s{/data/db/snapshot.db}); Texttile.Repo.query!(~s{VACUUM INTO '/data/db/snapshot.db'})\""
	@rm -f -- "$(DB_LOCAL)"
	fly ssh sftp get /data/db/snapshot.db "$(DB_LOCAL)" -a $(FLY_APP)
	@echo "Snapshot ready: $(abspath $(DB_LOCAL))"

# Throw the whole development installation away: the shared database and
# the files that belong to it. Both halves go together, because a
# database without its uploads is a site full of pictures that are not
# there. Every worktree shares this state (see config/dev.exs). The next
# `make start` makes an empty installation and migrates it.
dev-reset:
	@pids="$$(lsof -t "$(DB_DEV)" "$(DB_DEV)-shm" "$(DB_DEV)-wal" 2>/dev/null | sort -u || true)"; \
	if [ -n "$$pids" ]; then \
		echo "Database is in use by process(es): $$pids" >&2; \
		echo "Stop the development server before running make dev-reset." >&2; \
		exit 1; \
	fi
	@rm -f -- "$(DB_DEV)" "$(DB_DEV)-shm" "$(DB_DEV)-wal"
	@echo "Deleted development database: $(DB_DEV)"
	@rm -rf -- "$(UPLOADS_DEV)"
	@echo "Deleted development uploads: $(UPLOADS_DEV)"

# Optional: a git-ignored .env (see .env.example) is loaded into the server,
# e.g. to test a real mail adapter locally. Dev needs no env vars by default.
start:
	@$(MAKE) kill-port-4000
	@$(MAKE) prepare
	mix ecto.migrate
	@host="$$(bin/dev-host)"; \
	echo "Server: http://$$host:4000"; \
	( \
		tries=0; \
		while [ $$tries -lt 300 ]; do \
			if curl -fsS -o /dev/null --max-time 2 "http://$$host:4000/"; then \
				open "http://$$host:4000"; \
				exit 0; \
			fi; \
			tries=$$((tries + 1)); \
			sleep 0.4; \
		done; \
		echo "The server did not answer within two minutes; open http://$$host:4000 yourself." >&2 \
	) &
	@if [ -f .env ]; then set -a && . ./.env && set +a; fi; mix phx.server
