# Track B — kind (Kubernetes)

> **Full Kubernetes experience on your laptop.**
> Mirrors what you'd do on AKS/EKS/GKE — same manifests, same concepts.

---

## Prerequisites

Install in this order — each step depends on the one before it:

| # | Dependency | Why |
|---|-----------|-----|
| 1 | **Docker Desktop** (running) | kind runs cluster nodes as Docker containers |
| 2 | **kind** | creates and manages the local Kubernetes cluster |
| 3 | **kubectl** | sends commands to the cluster |

### Installing on macOS / Linux

```bash
# 1. Docker Desktop — https://www.docker.com/products/docker-desktop/
#    (start it before running setup.sh)

# 2. kind
brew install kind          # macOS
# or: https://kind.sigs.k8s.io/docs/user/quick-start/#installation

# 3. kubectl
brew install kubectl       # macOS
# or: https://kubernetes.io/docs/tasks/tools/
```

### Installing on Windows

```powershell
# 1. Docker Desktop — download and install first, then START it:
#    https://www.docker.com/products/docker-desktop/
#    Wait for the whale icon in the system tray before continuing.

# 2. kind
winget install Kubernetes.kind          # Windows Package Manager (recommended)
choco install kind                      # Chocolatey
scoop install kind                      # Scoop
# or download: https://github.com/kubernetes-sigs/kind/releases

# 3. kubectl
winget install Kubernetes.kubectl       # Windows Package Manager (recommended)
choco install kubernetes-cli            # Chocolatey
scoop install kubectl                   # Scoop
# or download: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/
```

> 💡 **After installing kind/kubectl on Windows**, open a new terminal so the updated `PATH` takes effect — or `setup.ps1` will do it for you automatically.

> 💡 **Verify all three are ready:**
> ```powershell
> docker info          # must show server info (not an error)
> kind --version
> kubectl version --client
> ```

---

## ⚡ Quick Start

### macOS / Linux (bash)

```bash
cd kind/
./setup.sh

# Verify SPIRE is running
kubectl -n spire get pods
```

### Windows — Option 1: PowerShell (native, no extra tools needed)

```powershell
cd kind\
.\setup.ps1

# Verify SPIRE is running
kubectl -n spire get pods
```

### Windows — Option 2: Git Bash or WSL2

```bash
cd kind/
./setup.sh

# Verify SPIRE is running
kubectl -n spire get pods
```

> 💡 **Git Bash** ships with Git for Windows. **WSL2** is recommended for the full Linux experience.
> Both options support all advanced lab scripts as well.

---

## What `setup.sh` Does

```
1. Creates a 3-node kind cluster ("spiffe-lab")
2. Deploys SPIRE Server (StatefulSet in spire namespace)
3. Deploys SPIRE Agent (DaemonSet — one per node)
4. Waits for health checks to pass
5. Registers sample workloads
6. Deploys the mTLS demo app (same frontend/backend as Track A)
```

---

## Labs

> 💡 **Every command below is on a single line** — click the copy button on any code block to grab it exactly.  
> **Windows PowerShell users:** `kubectl` commands work as-is. Where bash and PowerShell differ, both variants are shown.

---

### Lab 1: Explore the Cluster

> Works as-is on macOS, Linux, Windows PowerShell, Git Bash, and WSL2.

See all SPIRE components (pods, services, configmaps, volumes):
```bash
kubectl -n spire get pods,svc,configmap,pvc
```

Tail the SPIRE Server logs:
```bash
kubectl -n spire logs spire-server-0
```

Tail the SPIRE Agent logs across all nodes:
```bash
kubectl -n spire logs -l app=spire-agent --tail=50
```

---

### Lab 2: Node Attestation via k8s_psat

On Kubernetes, agents use **Projected Service Account Tokens** to prove which node they're on.

List attested nodes:

```bash
kubectl -n spire exec -it spire-server-0 -- /opt/spire/bin/spire-server agent list
```

> Each agent's SPIFFE ID encodes the cluster and node UID:  
> `spiffe://example.org/spire/agent/k8s_psat/spiffe-lab/<node-uid>`

Inspect the projected token volume the agent uses — **bash / Git Bash / WSL2:**
```bash
kubectl -n spire get pod -l app=spire-agent -o yaml | grep -A5 "projected"
```

**Windows PowerShell:**
```powershell
kubectl -n spire get pod -l app=spire-agent -o yaml | Select-String -Pattern "projected" -Context 0,5
```

---

### Lab 3: Workload Attestation

**Step 1 —** Deploy a test workload:
```bash
kubectl apply -f spire/k8s/test-workload.yaml
```

**Step 2 —** Exec in and fetch an X.509 SVID — **bash / Git Bash / WSL2:**
```bash
kubectl exec -it test-workload -- /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock
```

**Windows PowerShell:**
```powershell
kubectl exec -it test-workload -- /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock
```

> Same command on both platforms — no line continuation needed!

**Step 3 —** See all registration entries on the server:
```bash
kubectl -n spire exec -it spire-server-0 -- /opt/spire/bin/spire-server entry show
```

---

### Lab 4: ClusterSPIFFEID — Automatic Registration

Instead of manually registering every workload, use the Controller Manager CRD.

**Step 1 —** Apply the ClusterSPIFFEID policy:
```bash
kubectl apply -f spire/k8s/cluster-spiffe-id.yaml
```

**Step 2 —** Deploy a new pod — it gets a SPIFFE ID automatically — **bash / Git Bash / WSL2:**
```bash
kubectl run auto-workload --image=ghcr.io/spiffe/spire-agent:1.9.6 --command -- sleep 3600
```

**Windows PowerShell:**
```powershell
kubectl run auto-workload --image=ghcr.io/spiffe/spire-agent:1.9.6 --command -- sleep 3600
```

**Step 3 —** Fetch the auto-assigned SVID:
```bash
kubectl exec -it auto-workload -- /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock
```

> Expected SPIFFE ID: `spiffe://example.org/ns/default/sa/default` — generated automatically!

---

## Advanced Labs

> 💡 Labs 5 and 6 use shell scripts (`.sh`). Run them via **Git Bash** or **WSL2** on Windows.  
> All `kubectl` commands work in PowerShell as-is.

---

### Lab 5: Custom Disk-Based Root CA

Replace the self-signed CA with a custom root CA (simulates Azure Key Vault CA).

```bash
cd advanced/disk-ca/
```
```bash
./setup-custom-ca.sh
```

This creates a proper CA hierarchy:
```
Root CA (generated locally with openssl)
└── SPIRE Server Intermediate CA
    └── SVIDs for workloads
```

---

### Lab 6: Two-Cluster Federation

Run two separate kind clusters and federate them.

**Step 1 —** Run the federation setup:
```bash
cd advanced/two-cluster/
```
```bash
./setup-federation.sh
```

**Step 2 —** Verify cluster-a workloads see both trust roots — **bash / Git Bash / WSL2:**
```bash
kubectl --context kind-cluster-a exec -it test-workload -- /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock 2>&1 | grep "CA #"
```

**Windows PowerShell:**
```powershell
kubectl --context kind-cluster-a exec -it test-workload -- /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock 2>&1 | Select-String "CA #"
```

> Expected output:
> ```
> CA #1: cluster-a.io root
> CA #2: cluster-b.io root  ← federated bundle!
> ```

---

### Lab 7: Envoy Transparent mTLS

Deploy Envoy as a sidecar — your app code never touches a certificate.

**Step 1 —** Deploy Envoy — **bash / Git Bash / WSL2:**
```bash
cd advanced/envoy/
```

**Windows PowerShell:**
```powershell
cd advanced\envoy\
```

**Step 2 —** Apply manifests (same on all platforms):
```bash
kubectl apply -f k8s/
```

**Step 3 —** Make a plain HTTP call — Envoy transparently upgrades it to mTLS:
```bash
kubectl -n demo exec -it deployment/frontend-envoy -c app -- curl http://backend-envoy.demo.svc.cluster.local:8080/orders
```

---

## Cleanup

### macOS / Linux

```bash
./teardown.sh
# OR
kind delete clusters spiffe-lab cluster-a cluster-b
```

### Windows

```powershell
.\teardown.ps1
# OR
kind delete clusters spiffe-lab cluster-a cluster-b
```

---

## 🔧 Troubleshooting

### SPIRE Server pod stuck in Pending
```bash
kubectl -n spire describe pod spire-server-0
# Common cause: PVC not bound (storage class issue)
# Fix: kind uses standard local-path storage — wait 30s or recreate cluster
```

### SPIRE Agent CrashLoopBackOff
```bash
kubectl -n spire logs -l app=spire-agent --previous
# Common causes:
# 1. Server not ready — agents start before server is healthy
# 2. Token audience mismatch — check agent.conf token_path and projected volume audience
```

### `spire-server agent list` shows no agents
k8s_psat attestation takes ~10 seconds. Wait and retry. If still empty:
```bash
# bash / Git Bash / WSL2
kubectl -n spire logs spire-server-0 | grep -i "attestation\|error\|psat"
```
```powershell
# PowerShell
kubectl -n spire logs spire-server-0 | Select-String -Pattern "attestation|error|psat" -CaseSensitive:$false
```

### `api fetch x509` returns "no identity issued"
The workload has no matching registration entry. Check:
```bash
kubectl -n spire exec -it spire-server-0 -- \
  /opt/spire/bin/spire-server entry show
# Verify selectors match your workload's namespace/service account
```

### `setup.sh` fails at rollout status timeout
```bash
# bash / Git Bash / WSL2
kubectl -n spire get events --sort-by='.lastTimestamp' | tail -20
kind delete cluster --name spiffe-lab && ./setup.sh  # full reset
```
```powershell
# PowerShell
kubectl -n spire get events --sort-by='.lastTimestamp' | Select-Object -Last 20
kind delete cluster --name spiffe-lab; .\setup.ps1
```

### kind cluster creation fails (port conflicts)
```bash
# Check if a cluster already exists
kind get clusters
# Delete and recreate
kind delete cluster --name spiffe-lab
./setup.sh          # bash
# .\setup.ps1       # PowerShell
```

### Windows: `setup.ps1` execution blocked by policy

```powershell
# Run once to allow local scripts (requires admin PowerShell)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# Then run:
.\setup.ps1
```

### Windows: `kind` or `kubectl` not found after install

Restart your terminal (or VS Code / Windows Terminal) after installing via winget/choco/scoop
so the updated `PATH` takes effect.

### Windows: line-ending issues if editing `.sh` files

If you edit `.sh` files on Windows, ensure they use Unix line endings (LF, not CRLF):

```powershell
# In VS Code: click "CRLF" in the status bar → select "LF"
# Or with git:
git config core.autocrlf input
```

---

## ▶️ Ready for Cloud? [SPIFFEBasics — Azure Tutorial](https://github.com/jeevanbisht/SPIFFEBasics)
