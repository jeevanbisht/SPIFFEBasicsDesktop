#!/usr/bin/env bash
set -euo pipefail
BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${BLUE}[envoy-setup]${NC} $*"; }
ok()  { echo -e "${GREEN}[ok]${NC} $*"; }

log "Registering Envoy demo workloads with SPIRE..."

# Get the first node's UID (for the agent SPIFFE ID)
NODE_UID=$(kubectl get node -o jsonpath='{.items[0].metadata.uid}')
AGENT_ID="spiffe://example.org/spire/agent/k8s_psat/spiffe-lab/${NODE_UID}"

log "Agent SPIFFE ID: ${AGENT_ID}"

kubectl -n spire exec -it spire-server-0 -- \
  /opt/spire/bin/spire-server entry create \
    -parentID "${AGENT_ID}" \
    -spiffeID "spiffe://example.org/ns/demo/sa/frontend" \
    -selector "k8s:ns:demo" \
    -selector "k8s:sa:frontend" \
    -ttl 3600 2>/dev/null && ok "Frontend registered" || log "May already exist"

kubectl -n spire exec -it spire-server-0 -- \
  /opt/spire/bin/spire-server entry create \
    -parentID "${AGENT_ID}" \
    -spiffeID "spiffe://example.org/ns/demo/sa/backend" \
    -selector "k8s:ns:demo" \
    -selector "k8s:sa:backend" \
    -ttl 3600 2>/dev/null && ok "Backend registered" || log "May already exist"

ok ""
ok "Workloads registered! Now deploy the Envoy demo:"
ok "  kubectl apply -f k8s/"
ok ""
ok "Test the mTLS connection (plain HTTP from app, mTLS between Envoy proxies):"
ok "  kubectl -n demo exec -it deployment/frontend-envoy -c app -- \\"
ok "    curl http://localhost:9000/demo"
