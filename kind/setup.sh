#!/usr/bin/env bash
# kind/setup.sh — Create kind cluster and deploy SPIRE
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
CLUSTER="spiffe-lab"
SPIRE_NS="spire"

log()   { echo -e "${BLUE}[setup]${NC} $*"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
die()   { echo -e "${RED}[error]${NC} $*"; exit 1; }

command -v kind    &>/dev/null || die "kind not found — https://kind.sigs.k8s.io"
command -v kubectl &>/dev/null || die "kubectl not found"
command -v docker  &>/dev/null || die "docker not found"
docker info &>/dev/null        || die "Docker not running"

log "╔══════════════════════════════════════════════════╗"
log "║   SPIFFE Standalone — kind Cluster Setup         ║"
log "╚══════════════════════════════════════════════════╝"

# ─── Cluster ────────────────────────────────────────────────────────────────
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
  log "Cluster '${CLUSTER}' already exists, reusing."
else
  log "Creating kind cluster '${CLUSTER}'..."
  kind create cluster --name "${CLUSTER}" --config kind-config.yaml
  ok "Cluster created"
fi

kubectl config use-context "kind-${CLUSTER}"

# ─── SPIRE Server ───────────────────────────────────────────────────────────
log "Deploying SPIRE Server..."
kubectl apply -f spire/k8s/namespace.yaml
kubectl apply -f spire/k8s/server-service-account.yaml
kubectl apply -f spire/k8s/server-cluster-role.yaml
kubectl apply -f spire/k8s/server-configmap.yaml
kubectl apply -f spire/k8s/server-bundle-configmap.yaml   # must exist before server starts
kubectl apply -f spire/k8s/server-statefulset.yaml
kubectl apply -f spire/k8s/server-service.yaml
kubectl -n "${SPIRE_NS}" rollout status statefulset/spire-server --timeout=120s
ok "SPIRE Server ready"

# ─── SPIRE Agent ────────────────────────────────────────────────────────────
log "Deploying SPIRE Agent..."
kubectl apply -f spire/k8s/agent-service-account.yaml
kubectl apply -f spire/k8s/agent-cluster-role.yaml
kubectl apply -f spire/k8s/agent-configmap.yaml
kubectl apply -f spire/k8s/agent-daemonset.yaml
kubectl -n "${SPIRE_NS}" rollout status daemonset/spire-agent --timeout=120s
ok "SPIRE Agent ready"

# ─── Controller Manager (auto-registration via ClusterSPIFFEID CRDs) ────────
log "Deploying SPIRE Controller Manager..."
kubectl apply -f spire/k8s/cluster-spiffe-id.yaml 2>/dev/null || true

# ─── Demo app ───────────────────────────────────────────────────────────────
if [ -d "demo" ]; then
  log "Deploying demo app..."
  kubectl apply -f demo/ 2>/dev/null || true
fi

# ─── Health check ───────────────────────────────────────────────────────────
log "Waiting for SPIRE components to fully initialize..."
sleep 15
log "Checking SPIRE health..."
kubectl -n "${SPIRE_NS}" exec spire-server-0 -c spire-server -- \
  /opt/spire/bin/spire-server healthcheck && ok "Server: healthy"

NOT_READY=$(kubectl -n "${SPIRE_NS}" get pods -l app=spire-agent \
  -o jsonpath='{.items[?(@.status.containerStatuses[0].ready==false)].metadata.name}')
if [ -n "${NOT_READY}" ]; then
  die "Some agent pods are not ready: ${NOT_READY}"
fi
ok "Agent(s): healthy (all pods Ready)"

log "══════════════════════════════════════════════════"
ok "Setup complete!"
log ""
log "Trust domain:  spiffe://example.org"
log "Cluster:       kind-${CLUSTER}"
log ""
log "Next steps:"
log "  kubectl -n ${SPIRE_NS} exec -it spire-server-0 -- /opt/spire/bin/spire-server agent list"
log "  kubectl apply -f spire/k8s/test-workload.yaml"
log "  See README.md for lab exercises"
