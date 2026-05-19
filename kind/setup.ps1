# kind/setup.ps1 — Create kind cluster and deploy SPIRE (Windows PowerShell)
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$CLUSTER  = "spiffe-lab"
$SPIRE_NS = "spire"

function log  { param($msg) Write-Host "[setup] $msg" -ForegroundColor Cyan }
function ok   { param($msg) Write-Host "[ok]    $msg" -ForegroundColor Green }
function die  { param($msg) Write-Host "[error] $msg" -ForegroundColor Red; exit 1 }

# ─── Prerequisite checks ────────────────────────────────────────────────────
foreach ($tool in @("kind", "kubectl", "docker")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        die "$tool not found. See README.md for Windows install instructions."
    }
}
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { die "Docker is not running. Start Docker Desktop first." }

log "╔══════════════════════════════════════════════════╗"
log "║   SPIFFE Standalone — kind Cluster Setup         ║"
log "╚══════════════════════════════════════════════════╝"

# ─── Cluster ────────────────────────────────────────────────────────────────
$existing = kind get clusters 2>$null
if ($existing -match "(?m)^$CLUSTER$") {
    log "Cluster '$CLUSTER' already exists, reusing."
} else {
    log "Creating kind cluster '$CLUSTER'..."
    kind create cluster --name $CLUSTER --config kind-config.yaml
    if ($LASTEXITCODE -ne 0) { die "kind cluster creation failed." }
    ok "Cluster created"
}

kubectl config use-context "kind-$CLUSTER"

# ─── SPIRE Server ────────────────────────────────────────────────────────────
log "Deploying SPIRE Server..."
kubectl apply -f spire/k8s/namespace.yaml
kubectl apply -f spire/k8s/server-service-account.yaml
kubectl apply -f spire/k8s/server-cluster-role.yaml
kubectl apply -f spire/k8s/server-configmap.yaml
kubectl apply -f spire/k8s/server-statefulset.yaml
kubectl apply -f spire/k8s/server-service.yaml
kubectl -n $SPIRE_NS rollout status statefulset/spire-server --timeout=120s
ok "SPIRE Server ready"

# ─── SPIRE Agent ─────────────────────────────────────────────────────────────
log "Deploying SPIRE Agent..."
kubectl apply -f spire/k8s/agent-service-account.yaml
kubectl apply -f spire/k8s/agent-cluster-role.yaml
kubectl apply -f spire/k8s/agent-configmap.yaml
kubectl apply -f spire/k8s/agent-daemonset.yaml
kubectl -n $SPIRE_NS rollout status daemonset/spire-agent --timeout=120s
ok "SPIRE Agent ready"

# ─── Controller Manager (auto-registration via ClusterSPIFFEID CRDs) ─────────
log "Deploying SPIRE Controller Manager..."
kubectl apply -f spire/k8s/cluster-spiffe-id.yaml 2>$null

# ─── Demo app ─────────────────────────────────────────────────────────────────
if (Test-Path "demo") {
    log "Deploying demo app..."
    kubectl apply -f demo/ 2>$null
}

# ─── Health check ─────────────────────────────────────────────────────────────
Start-Sleep -Seconds 5
log "Checking SPIRE health..."
kubectl -n $SPIRE_NS exec -it spire-server-0 -- /opt/spire/bin/spire-server healthcheck
ok "Server: healthy"

$agentPod = kubectl -n $SPIRE_NS get pod -l app=spire-agent -o name | Select-Object -First 1
kubectl -n $SPIRE_NS exec -it $agentPod -- /opt/spire/bin/spire-agent healthcheck
ok "Agent: healthy"

log "══════════════════════════════════════════════════"
ok "Setup complete!"
log ""
log "Trust domain:  spiffe://example.org"
log "Cluster:       kind-$CLUSTER"
log ""
log "Next steps:"
log "  kubectl -n $SPIRE_NS exec -it spire-server-0 -- /opt/spire/bin/spire-server agent list"
log "  kubectl apply -f spire/k8s/test-workload.yaml"
log "  See README.md for lab exercises"
