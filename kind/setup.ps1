# kind/setup.ps1 — Create kind cluster and deploy SPIRE (Windows PowerShell)
#Requires -Version 5.1
Set-StrictMode -Version Latest
# Do NOT use $ErrorActionPreference="Stop" — it treats any native-command stderr
# as a fatal exception. Use explicit exit-code checks via the run() helper below.
$ErrorActionPreference = "Continue"

$CLUSTER  = "spiffe-lab"
$SPIRE_NS = "spire"

function log  { param($msg) Write-Host "[setup] $msg" -ForegroundColor Cyan }
function ok   { param($msg) Write-Host "[ok]    $msg" -ForegroundColor Green }
function die  { param($msg) Write-Host "[error] $msg" -ForegroundColor Red; exit 1 }

# Helper: run a native command; die with a message if it exits non-zero.
function run {
    param([string]$Desc, [scriptblock]$Cmd)
    & $Cmd
    if ($LASTEXITCODE -ne 0) { die "$Desc failed (exit $LASTEXITCODE)." }
}

# Fix console encoding so box-drawing / Unicode chars render correctly
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8

# ─── Refresh PATH (picks up winget/choco/scoop installs without shell restart) ─
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("PATH","User")

# ─── Prerequisite checks (in dependency order) ──────────────────────────────
#  1. Docker Desktop installed  — kind uses Docker to run cluster nodes
#  2. Docker Desktop running    — daemon must be up before `kind create cluster`
#  3. kind installed            — creates/manages the local k8s cluster
#  4. kubectl installed         — talks to the cluster once it exists

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    die "Docker Desktop not found.`n  Install: https://www.docker.com/products/docker-desktop/"
}
$null = docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    die "Docker Desktop is not running.`n`n  Start Docker Desktop and wait for the whale icon in the`n  system tray, then re-run this script."
}

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    die "kind not found.`n  Install: winget install Kubernetes.kind`n  See README.md for more options."
}
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    die "kubectl not found.`n  Install: winget install Kubernetes.kubectl`n  See README.md for more options."
}

log "╔══════════════════════════════════════════════════╗"
log "║   SPIFFE Standalone — kind Cluster Setup         ║"
log "╚══════════════════════════════════════════════════╝"

# ─── Cluster ────────────────────────────────────────────────────────────────
$existing = kind get clusters 2>&1   # stderr ("No kind clusters found.") is normal here
if ("$existing" -match "(?m)^$CLUSTER$") {
    log "Cluster '$CLUSTER' already exists, reusing."
} else {
    log "Creating kind cluster '$CLUSTER'..."
    run "kind create cluster" { kind create cluster --name $CLUSTER --config kind-config.yaml }
    ok "Cluster created"
}

run "kubectl use-context" { kubectl config use-context "kind-$CLUSTER" }

# ─── SPIRE Server ────────────────────────────────────────────────────────────
log "Deploying SPIRE Server..."
run "namespace"          { kubectl apply -f spire/k8s/namespace.yaml }
run "server-sa"          { kubectl apply -f spire/k8s/server-service-account.yaml }
run "server-clusterrole" { kubectl apply -f spire/k8s/server-cluster-role.yaml }
run "server-configmap"   { kubectl apply -f spire/k8s/server-configmap.yaml }
run "server-bundle-cm"   { kubectl apply -f spire/k8s/server-bundle-configmap.yaml }   # must exist before server starts
run "server-statefulset" { kubectl apply -f spire/k8s/server-statefulset.yaml }
run "server-service"     { kubectl apply -f spire/k8s/server-service.yaml }
run "server rollout"     { kubectl -n $SPIRE_NS rollout status statefulset/spire-server --timeout=120s }
ok "SPIRE Server ready"

# ─── SPIRE Agent ─────────────────────────────────────────────────────────────
log "Deploying SPIRE Agent..."
run "agent-sa"          { kubectl apply -f spire/k8s/agent-service-account.yaml }
run "agent-clusterrole" { kubectl apply -f spire/k8s/agent-cluster-role.yaml }
run "agent-configmap"   { kubectl apply -f spire/k8s/agent-configmap.yaml }
run "agent-daemonset"   { kubectl apply -f spire/k8s/agent-daemonset.yaml }
run "agent rollout"     { kubectl -n $SPIRE_NS rollout status daemonset/spire-agent --timeout=120s }
ok "SPIRE Agent ready"

# ─── Controller Manager (ClusterSPIFFEID CRDs — optional, skip if missing) ──
log "Deploying SPIRE Controller Manager..."
$null = kubectl apply -f spire/k8s/cluster-spiffe-id.yaml 2>&1

# ─── Demo app (optional) ─────────────────────────────────────────────────────
if (Test-Path "demo") {
    log "Deploying demo app..."
    $null = kubectl apply -f demo/ 2>&1
}

# ─── Health check ─────────────────────────────────────────────────────────────
log "Waiting for SPIRE components to fully initialize..."
Start-Sleep -Seconds 15

log "Checking SPIRE health..."
run "server healthcheck" { kubectl -n $SPIRE_NS exec spire-server-0 -c spire-server -- /opt/spire/bin/spire-server healthcheck }
ok "Server: healthy"

# Agent readiness is already confirmed by rollout status above.
# Double-check via pod Ready condition rather than exec (agent binary
# needs the admin socket which is not reachable from kubectl exec).
$notReady = kubectl -n $SPIRE_NS get pods -l app=spire-agent `
  -o jsonpath='{.items[?(@.status.containerStatuses[0].ready==false)].metadata.name}' 2>&1
if ($notReady -and "$notReady".Trim() -ne "") {
    die "Some agent pods are not ready: $notReady"
}
ok "Agent(s): healthy (all pods Ready)"

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
