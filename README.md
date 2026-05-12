# SPIFFE & SPIRE — Standalone Hands-On Tutorial

> **Learn workload identity from scratch on a single machine. No cloud account needed.**

[![SPIFFE](https://img.shields.io/badge/SPIFFE-Standard-blue)](https://spiffe.io)
[![SPIRE](https://img.shields.io/badge/SPIRE-v1.9-green)](https://github.com/spiffe/spire)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED)](https://docs.docker.com/compose/)
[![kind](https://img.shields.io/badge/kind-Kubernetes-326CE5)](https://kind.sigs.k8s.io/)

---

## ⚡ 60-Second Quickstart

```bash
git clone https://github.com/jeevanbisht/spiffe-standalone.git
cd spiffe-standalone

# Track A — Docker Compose (simplest, no Kubernetes)
cd docker-compose && docker compose up -d
docker compose exec frontend curl http://localhost:3000/orders
# ← Served over mTLS using SPIFFE SVIDs, zero passwords!

# Track B — kind (full Kubernetes experience)
cd kind && ./setup.sh
```

**Only requirement: [Docker Desktop](https://www.docker.com/products/docker-desktop/)**

---

## 🗺️ Two Learning Tracks

### 🐳 Track A — Docker Compose
*Best for: absolute beginners, quick demos, non-Kubernetes environments*

```
spiffe-standalone/docker-compose/
├── docker-compose.yml      ← One file runs everything
├── spire/                  ← SPIRE Server + Agent config
│   ├── server.conf
│   └── agent.conf
├── apps/
│   ├── frontend/           ← Node.js service (fetches SVID, calls backend)
│   └── backend/            ← Node.js service (mTLS server, verifies caller)
└── labs/                   ← Step-by-step lab exercises
```

**What runs:**
```
docker-compose up
    ├── spire-server   (SPIRE CA + registry)
    ├── spire-agent    (issues SVIDs to workloads)
    ├── frontend       (gets SVID → calls backend over mTLS)
    └── backend        (gets SVID → serves with mTLS, verifies caller)
```

### ☸️ Track B — kind (Kubernetes)
*Best for: cloud engineers, those preparing for AKS/EKS/GKE deployments*

```
spiffe-standalone/kind/
├── setup.sh               ← Creates cluster + deploys SPIRE
├── spire/k8s/             ← All Kubernetes manifests
├── advanced/
│   ├── disk-ca/           ← Custom root CA (replaces Azure Key Vault)
│   ├── two-cluster/       ← Federation between two kind clusters
│   └── envoy/             ← Transparent mTLS with Envoy sidecar
└── labs/                  ← Hands-on exercises
```

---

## 📋 Prerequisites

| Requirement | Version | Check |
|-------------|---------|-------|
| Docker Desktop | 4.x+ | `docker --version` |
| docker compose | v2 (built-in) | `docker compose version` |
| **Track B only:** kind | 0.20+ | `kind --version` |
| **Track B only:** kubectl | 1.28+ | `kubectl version --client` |

> 💡 **Windows users:** Use PowerShell or Git Bash. All scripts are POSIX-compatible.

```bash
# Run the prereqs checker
./check-prereqs.sh
```

---

## 📚 Learning Path

```
[START]
   │
   ▼
Read concepts (10 min)
docs/concepts.md
   │
   ├─── Track A (Docker Compose) ──────────────────────────┐
   │                                                        │
   │  docker-compose/README.md                             │
   │    ├── Lab 1: Spin up SPIRE + services                │
   │    ├── Lab 2: Fetch & inspect X.509 SVIDs             │
   │    ├── Lab 3: Fetch & decode JWT-SVIDs                │
   │    ├── Lab 4: Watch mTLS handshake                    │
   │    ├── Lab 5: Break it — remove registration entry    │
   │    └── Lab 6: Observe automatic SVID rotation         │
   │                                                        │
   └─── Track B (kind) ────────────────────────────────────┘

  kind/README.md
    ├── Lab 1: Deploy SPIRE on Kubernetes
    ├── Lab 2: Node attestation (k8s_psat)
    ├── Lab 3: Workload attestation deep dive
    ├── Lab 4: Registration entries + ClusterSPIFFEID CRDs
    ├── Lab 5: [Advanced] Custom disk-based root CA
    ├── Lab 6: [Advanced] Two-cluster federation
    └── Lab 7: [Advanced] Envoy transparent mTLS
                │
               [DONE] — Ready for cloud deployment (see SPIFFEBasics repo)
```

---

## 🔗 Next Steps After This Tutorial

Once comfortable here, graduate to cloud deployments:
- **Azure:** [github.com/jeevanbisht/SPIFFEBasics](https://github.com/jeevanbisht/SPIFFEBasics) — AKS, Key Vault CA, OIDC federation
- **SPIFFE Docs:** [spiffe.io/docs](https://spiffe.io/docs/latest/)
- **CNCF SPIFFE/SPIRE:** [github.com/spiffe/spire](https://github.com/spiffe/spire)
