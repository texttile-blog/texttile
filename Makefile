# Port 4000 belongs to the human developer (make start).
# Agents never use it; they run on 4440+ (see AGENTS.md).

# The product notes live in the personal vault. The copies in this repo are
# read-only mirrors, see the `idea` target.
VAULT ?= $(HOME)/vault/texttile
VAULT_MAIN := texttile - elixir multiplayer cms.md

.PHONY: prepare test kill-port-4000 start idea

prepare:
	mix deps.get
	mix assets.setup
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
	@test -f "$(VAULT)/$(VAULT_MAIN)" || { echo "Main note not found: $(VAULT)/$(VAULT_MAIN)" >&2; exit 1; }
	@cp "$(VAULT)/$(VAULT_MAIN)" idea.md
	@mkdir -p idea
	@for f in "$(VAULT)"/*.md; do \
		name="$$(basename "$$f")"; \
		if [ "$$name" != "$(VAULT_MAIN)" ]; then cp "$$f" "idea/$$name"; fi; \
	done
	@echo "Synced from $(VAULT):"
	@git status --short idea.md idea/ || true

start:
	@$(MAKE) kill-port-4000
	@$(MAKE) prepare
	mix ecto.migrate
	open http://localhost:4000
	mix phx.server
