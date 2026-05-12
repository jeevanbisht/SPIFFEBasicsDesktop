# 🧪 SPIFFE/SPIRE Hands-On Labs

> All labs run on your laptop. No cloud account needed.

## Quick Navigation

### 🐳 Track A — Docker Compose Labs
No Kubernetes required. Start here if you're new to SPIFFE.

| Lab | What You Learn | Time |
|-----|---------------|------|
| [Lab 1: Your First SVID](../docker-compose/README.md#lab-1-see-your-first-svid) | What a SPIFFE ID looks like | 5 min |
| [Lab 2: mTLS Call](../docker-compose/README.md#lab-2-call-the-backend-over-mtls) | Service-to-service mTLS in action | 5 min |
| [Lab 3: Inspect Certificate](../docker-compose/README.md#lab-3-inspect-the-actual-certificate) | X.509 SAN field, openssl deep-dive | 10 min |
| [Lab 4: JWT-SVID](../docker-compose/README.md#lab-4-decode-a-jwt-svid) | Decode JWT claims, audience restriction | 10 min |
| [Lab 5: Break It](../docker-compose/README.md#lab-5-break-it--what-happens-without-a-valid-svid) | What mTLS enforcement looks like | 10 min |
| [Lab 6: Watch Rotation](../docker-compose/README.md#lab-6-watch-svid-rotation) | Automatic cert rotation at 50% TTL | 15 min |
| [Lab 7: Add a Service](../docker-compose/README.md#lab-7-add-a-new-service) | Register a new workload entry | 10 min |
| [Lab 8: Explore State](../docker-compose/README.md#lab-8-explore-spire-server-state) | Trust bundles, entries, agents | 10 min |

**Total: ~75 minutes**

### ☸️ Track B — Kubernetes (kind) Labs
For cloud engineers. Mirrors production AKS/EKS/GKE deployments.

| Lab | What You Learn | Level |
|-----|---------------|-------|
| [Lab 1: Explore Cluster](../kind/README.md#lab-1-explore-the-cluster) | SPIRE on K8s components | Beginner |
| [Lab 2: Node Attestation](../kind/README.md#lab-2-node-attestation-via-k8s_psat) | k8s_psat — how agents prove identity | Intermediate |
| [Lab 3: Workload Attestation](../kind/README.md#lab-3-workload-attestation) | Pod → SPIFFE ID mapping | Intermediate |
| [Lab 4: ClusterSPIFFEID CRDs](../kind/README.md#lab-4-clusterSpiffeID--automatic-registration) | Auto-registration with Controller Manager | Intermediate |
| [Lab 5: Custom Root CA](../kind/README.md#lab-5-custom-disk-based-root-ca) | Disk CA, certificate hierarchy | Advanced |
| [Lab 6: Federation](../kind/README.md#lab-6-two-cluster-federation) | Cross-cluster SPIFFE trust | Advanced |
| [Lab 7: Envoy mTLS](../kind/README.md#lab-7-envoy-transparent-mtls) | Transparent mTLS — app knows nothing | Advanced |

## Prerequisites

```bash
# Check what you need
cd ..
./check-prereqs.sh
```

## How Labs Are Structured

Each lab follows this pattern:
1. **Concept** — one paragraph explaining WHY this matters
2. **Commands** — copy-paste ready
3. **Expected output** — so you know it worked
4. **What to notice** — points out the important thing

## 💡 Tips

- Labs build on each other within a track — do them in order
- You can do Track A and Track B independently
- All commands are copy-pasteable — no manual editing needed
- Stuck? Each README has a troubleshooting section
