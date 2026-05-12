# Makefile — SPIFFE Standalone Tutorial helper commands
# Usage: make <target>

.PHONY: help up down logs status labs clean prereqs

help: ## Show this help
	@echo ""
	@echo "SPIFFE Standalone Tutorial"
	@echo "=========================="
	@echo ""
	@echo "Track A (Docker Compose):"
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*##"}; {printf "  make %-18s %s\n", $$1, $$2}'
	@echo ""

prereqs: ## Check all prerequisites
	@bash check-prereqs.sh

up: ## Start Track A (Docker Compose) — builds images if needed
	@cd docker-compose && docker compose up -d --build
	@echo ""
	@echo "✅ Services starting... watch with: make logs"
	@echo "   Once healthy, try:   curl http://localhost:3000/demo"

down: ## Stop Track A
	@cd docker-compose && docker compose down

clean: ## Stop Track A and delete all data (CA keys, database)
	@cd docker-compose && docker compose down -v
	@echo "✅ Cleaned up (volumes deleted)"

logs: ## Stream logs from all Track A services
	@cd docker-compose && docker compose logs -f

status: ## Show status of Track A services
	@cd docker-compose && docker compose ps

demo: ## Run the full mTLS demo (requires Track A to be running)
	@echo "=== Frontend identity ==="
	@curl -s http://localhost:3000/my-identity | python3 -m json.tool
	@echo ""
	@echo "=== Call backend over mTLS ==="
	@curl -s http://localhost:3000/demo | python3 -m json.tool

inspect-cert: ## Inspect the frontend's X.509-SVID certificate
	@docker compose -f docker-compose/docker-compose.yml exec frontend sh -c \
		'/opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock -write /tmp/ 2>/dev/null && openssl x509 -in /tmp/svid.0.pem -text -noout'

server-entries: ## List all SPIRE registration entries
	@docker compose -f docker-compose/docker-compose.yml exec spire-server \
		/opt/spire/bin/spire-server entry show

server-agents: ## List attested SPIRE agents
	@docker compose -f docker-compose/docker-compose.yml exec spire-server \
		/opt/spire/bin/spire-server agent list

server-bundle: ## Show the trust bundle (CA certificate)
	@docker compose -f docker-compose/docker-compose.yml exec spire-server \
		/opt/spire/bin/spire-server bundle show

kind-up: ## Start Track B (kind/Kubernetes cluster + SPIRE)
	@cd kind && bash setup.sh

kind-down: ## Delete Track B kind cluster
	@kind delete cluster --name spiffe-lab 2>/dev/null && echo "✅ Cluster deleted" || echo "No cluster to delete"
