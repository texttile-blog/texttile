# Port 4000 belongs to the human developer (make start).
# Agents never use it; they run on 4440+ (see AGENTS.md).

.PHONY: prepare test kill-port-4000 start

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

start:
	@$(MAKE) kill-port-4000
	@$(MAKE) prepare
	mix ecto.migrate
	open http://localhost:4000
	mix phx.server
