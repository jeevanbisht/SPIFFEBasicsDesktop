#!/usr/bin/env bash
# advanced/two-cluster/setup-federation.sh
# Creates two kind clusters and configures SPIFFE federation between them
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${BLUE}[federation]${NC} $*"; }
ok()  { echo -e "${GREEN}[ok]${NC} $*"; }

log "╔══════════════════════════════════════════════════╗"
log "║   SPIFFE Two-Cluster Federation Setup            ║"
log "╚══════════════════════════════════════════════════╝"

# ─── Create Cluster A ──────────────────────────────────────────────────────
log "Creating Cluster A (trust domain: cluster-a.example.org)..."
kind create cluster --name cluster-a --config cluster-a/kind-config.yaml 2>/dev/null || \
  log "Cluster A already exists"

kubectl config use-context kind-cluster-a

kubectl apply -f cluster-a/namespace.yaml
kubectl apply -f cluster-a/server-configmap.yaml
kubectl apply -f cluster-a/server-statefulset.yaml
kubectl apply -f cluster-a/server-service.yaml
kubectl apply -f cluster-a/agent-configmap.yaml
kubectl apply -f cluster-a/agent-daemonset.yaml
kubectl -n spire rollout status statefulset/spire-server --timeout=120s
ok "Cluster A: SPIRE running"

# ─── Create Cluster B ──────────────────────────────────────────────────────
log "Creating Cluster B (trust domain: cluster-b.example.org)..."
kind create cluster --name cluster-b --config cluster-b/kind-config.yaml 2>/dev/null || \
  log "Cluster B already exists"

kubectl config use-context kind-cluster-b

kubectl apply -f cluster-b/namespace.yaml
kubectl apply -f cluster-b/server-configmap.yaml
kubectl apply -f cluster-b/server-statefulset.yaml
kubectl apply -f cluster-b/server-service.yaml
kubectl apply -f cluster-b/agent-configmap.yaml
kubectl apply -f cluster-b/agent-daemonset.yaml
kubectl -n spire rollout status statefulset/spire-server --timeout=120s
ok "Cluster B: SPIRE running"

# ─── Configure Federation ─────────────────────────────────────────────────
log "Getting Cluster B bundle endpoint IP..."
CLUSTER_B_IP=$(kubectl --context kind-cluster-b -n spire get svc spire-server \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "10.96.0.100")

log "Configuring Cluster A to trust Cluster B..."
kubectl --context kind-cluster-a -n spire exec -it spire-server-0 -- \
  /opt/spire/bin/spire-server federation create \
    -trustDomain "cluster-b.example.org" \
    -bundleEndpointURL "https://${CLUSTER_B_IP}:8443" \
    -bundleEndpointProfile "https_spiffe" 2>/dev/null || \
  log "Federation entry may already exist"

log "Configuring Cluster B to trust Cluster A..."
CLUSTER_A_IP=$(kubectl --context kind-cluster-a -n spire get svc spire-server \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "10.96.0.100")

kubectl --context kind-cluster-b -n spire exec -it spire-server-0 -- \
  /opt/spire/bin/spire-server federation create \
    -trustDomain "cluster-a.example.org" \
    -bundleEndpointURL "https://${CLUSTER_A_IP}:8443" \
    -bundleEndpointProfile "https_spiffe" 2>/dev/null || \
  log "Federation entry may already exist"

ok ""
ok "Federation configured!"
ok ""
ok "Verify federated bundles are syncing:"
ok "  kubectl --context kind-cluster-a -n spire exec -it spire-server-0 -- \\"
ok "    /opt/spire/bin/spire-server bundle show -id spiffe://cluster-b.example.org"
ok ""
ok "See kind/README.md Lab 6 for the cross-cluster mTLS demo."
