include Makefile

.DEFAULT_GOAL := help-all

.PHONY: help-all
help-all: ## Show this help
	@awk '\
	/^###> / { section = $$0; sub(/^###> */, "", section); sub(/ *###$$/, "", section); printf "\n\033[1;36m%s\033[0m\n", section; next } \
	/^###< / { next } \
	/^[a-zA-Z_-]+:.*$$/ { name = $$1; sub(/:$$/, "", name); doc = ""; if ($$0 ~ /## /) { split($$0, a, "## "); doc = a[2] } printf "\033[32m%-18s\033[0m %s\n", name, doc }' \
	Makefile GNUmakefile

.PHONY: help
help: help-all

.PHONY: dev-tunnel
dev-tunnel: ## Start a public HTTPS tunnel (cloudflared) and wire the shop to it
	@bin/dev-tunnel.sh

.PHONY: dev-tunnel-down
dev-tunnel-down: ## Stop and remove the cloudflared tunnel container
	@docker rm -f cloudflared 2>/dev/null || true
