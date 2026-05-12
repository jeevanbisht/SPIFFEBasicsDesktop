#!/usr/bin/env bash
set -euo pipefail
BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${BLUE}[teardown]${NC} $*"; }
ok()  { echo -e "${GREEN}[ok]${NC} $*"; }

log "Deleting all SPIFFE kind clusters..."

for cluster in spiffe-lab cluster-a cluster-b; do
  if kind get clusters 2>/dev/null | grep -q "^${cluster}$"; then
    kind delete cluster --name "${cluster}"
    ok "Deleted: ${cluster}"
  else
    log "Cluster not found (already deleted): ${cluster}"
  fi
done

ok "All clusters deleted."
ok "Run './setup.sh' to start fresh."
