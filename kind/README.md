# Track B — kind (Kubernetes)

> **Full Kubernetes experience on your laptop.**
> Mirrors what you'd do on AKS/EKS/GKE — same manifests, same concepts.

---

## Prerequisites

- Docker Desktop running
- `kind` installed: `brew install kind` or [docs](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- `kubectl` installed

```bash
./check-prereqs.sh
```

---

## ⚡ Quick Start

```bash
cd kind/
./setup.sh

# Verify SPIRE is running
kubectl -n spire get pods
```

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

### Lab 1: Explore the Cluster

```bash
# See SPIRE components
kubectl -n spire get pods,svc,configmap,pvc

# SPIRE Server logs
kubectl -n spire logs spire-server-0

# SPIRE Agent logs (pick any agent pod)
kubectl -n spire logs -l app=spire-agent --tail=50
```

### Lab 2: Node Attestation via k8s_psat

On Kubernetes (unlike Docker Compose), agents use **Projected Service Account Tokens** to prove which node they're on:

```bash
# See the attested nodes
kubectl -n spire exec -it spire-server-0 -- \
  /opt/spire/bin/spire-server agent list

# The agent's SPIFFE ID encodes the cluster and node:
# spiffe://example.org/spire/agent/k8s_psat/spiffe-lab/<node-uid>

# Inspect the projected token the agent uses
kubectl -n spire get pod -l app=spire-agent -o yaml | \
  grep -A5 "projected"
```

### Lab 3: Workload Attestation

```bash
# Deploy a test workload
kubectl apply -f spire/k8s/test-workload.yaml

# Exec in and fetch an SVID
kubectl exec -it test-workload -- \
  /opt/spire/bin/spire-agent api fetch x509 \
    -socketPath /run/spire/sockets/agent.sock

# See registration entries
kubectl -n spire exec -it spire-server-0 -- \
  /opt/spire/bin/spire-server entry show
```

### Lab 4: ClusterSPIFFEID — Automatic Registration

Instead of manually registering every workload, use the Controller Manager CRD:

```bash
# Apply a ClusterSPIFFEID that auto-registers all pods
kubectl apply -f spire/k8s/cluster-spiffe-id.yaml

# Deploy a new pod — it gets a SPIFFE ID automatically!
kubectl run auto-workload --image=ghcr.io/spiffe/spire-agent:1.9.6 \
  --command -- sleep 3600

kubectl exec -it auto-workload -- \
  /opt/spire/bin/spire-agent api fetch x509 \
    -socketPath /run/spire/sockets/agent.sock
# SPIFFE ID: spiffe://example.org/ns/default/sa/default
# (Generated automatically by Controller Manager!)
```

---

## Advanced Labs

### Lab 5: Custom Disk-Based Root CA

Replace the self-signed CA with a custom root CA (simulates Azure Key Vault CA):

```bash
cd advanced/disk-ca/
./setup-custom-ca.sh
```

This creates a proper CA hierarchy:
```
Root CA (generated locally with openssl)
└── SPIRE Server Intermediate CA
    └── SVIDs for workloads
```

### Lab 6: Two-Cluster Federation

Run two separate kind clusters and federate them:

```bash
cd advanced/two-cluster/
./setup-federation.sh

# After setup, workloads in cluster-a can verify SVIDs from cluster-b
kubectl --context kind-cluster-a exec -it test-workload -- \
  /opt/spire/bin/spire-agent api fetch x509 \
    -socketPath /run/spire/sockets/agent.sock 2>&1 | grep "CA #"
# CA #1: cluster-a.io root
# CA #2: cluster-b.io root  ← federated bundle!
```

### Lab 7: Envoy Transparent mTLS

Deploy Envoy as a sidecar — your app code never touches a certificate:

```bash
cd advanced/envoy/
kubectl apply -f k8s/

# The app speaks plain HTTP internally; Envoy handles mTLS
kubectl -n demo exec -it deployment/frontend-envoy -c app -- \
  curl http://backend-envoy.demo.svc.cluster.local:8080/orders
# ← Plain HTTP call from the app perspective
# ← But Envoy upgrades to mTLS between pods!
```

---

## Cleanup

```bash
./teardown.sh
# OR
kind delete clusters spiffe-lab cluster-a cluster-b
```

---

## ▶️ Ready for Cloud? [SPIFFEBasics — Azure Tutorial](https://github.com/jeevanbisht/SPIFFEBasics)
