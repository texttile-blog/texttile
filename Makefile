# Port 4000 belongs to the human developer (make start).
# Agents never use it; they run on 4440+ (see AGENTS.md).

# The product notes live in the personal vault. The copies in this repo are
# read-only mirrors, see the `idea` target.
VAULT ?= $(HOME)/vault/texttile

.PHONY: prepare test kill-port-4000 start idea db-delete db-pull

# Local, stable path for the remote DB snapshot. Point TablePlus at this file.
DB_LOCAL := tmp/texttile-demo.db

# Development state is shared by all worktrees, see config/dev.exs.
DB_DEV := $(shell common_dir="$$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; if [ -n "$$common_dir" ]; then dirname "$$common_dir"; else pwd; fi)/texttile_dev.db

prepare:
	mix deps.get
	mix assets.setup
	npm --prefix assets install
	npm --prefix assets exec -- playwright install chromium
	mix compile

test: prepare
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

# Overwrite the product notes from the vault. The vault always wins.
# Edit the notes in the vault, never here.
idea:
	@test -d "$(VAULT)" || { echo "Vault not found: $(VAULT)" >&2; exit 1; }
	@mkdir -p idea
	@rsync -a --delete --exclude '.DS_Store' --exclude '.obsidian/' "$(VAULT)/" idea/
	@echo "Synced from $(VAULT):"
	@git status --short idea/ || true

# Pull a consistent snapshot of the production SQLite DB to $(DB_LOCAL).
# VACUUM INTO gives a stable copy of the live WAL database; never copy the raw file.
db-pull:
	@echo "Waking the machine..."
	@curl -fs -o /dev/null --max-time 30 https://texttile.fly.dev/ || true
	fly ssh console -a texttile -C "/app/bin/texttile rpc \"File.rm(~s{/data/db/snapshot.db}); Texttile.Repo.query!(~s{VACUUM INTO '/data/db/snapshot.db'})\""
	@mkdir -p tmp
	@rm -f $(DB_LOCAL)
	fly ssh sftp get /data/db/snapshot.db $(DB_LOCAL) -a texttile
	@echo "Snapshot ready: $(abspath $(DB_LOCAL))"

# Delete the shared development database. The next `make start` recreates it.
db-delete:
	@pids="$$(lsof -t "$(DB_DEV)" "$(DB_DEV)-shm" "$(DB_DEV)-wal" 2>/dev/null | sort -u || true)"; \
	if [ -n "$$pids" ]; then \
		echo "Database is in use by process(es): $$pids" >&2; \
		echo "Stop the development server before running make db-delete." >&2; \
		exit 1; \
	fi
	@rm -f -- "$(DB_DEV)" "$(DB_DEV)-shm" "$(DB_DEV)-wal"
	@echo "Deleted development database: $(DB_DEV)"

# Optional: a git-ignored .env (see .env.example) is loaded into the server,
# e.g. to test a real mail adapter locally. Dev needs no env vars by default.
start:
	@$(MAKE) kill-port-4000
	@$(MAKE) prepare
	mix ecto.migrate
	open http://localhost:4000
	@if [ -f .env ]; then set -a && . ./.env && set +a; fi; mix phx.server
