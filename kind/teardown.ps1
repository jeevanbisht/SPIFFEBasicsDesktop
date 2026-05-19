# kind/teardown.ps1 — Delete all SPIFFE kind clusters (Windows PowerShell)
#Requires -Version 5.1
Set-StrictMode -Version Latest

function log { param($msg) Write-Host "[teardown] $msg" -ForegroundColor Cyan }
function ok  { param($msg) Write-Host "[ok]       $msg" -ForegroundColor Green }

log "Deleting all SPIFFE kind clusters..."

foreach ($cluster in @("spiffe-lab", "cluster-a", "cluster-b")) {
    $existing = kind get clusters 2>$null
    if ($existing -match "(?m)^$cluster$") {
        kind delete cluster --name $cluster
        ok "Deleted: $cluster"
    } else {
        log "Cluster not found (already deleted): $cluster"
    }
}

ok "All clusters deleted."
ok "Run '.\setup.ps1' to start fresh."
