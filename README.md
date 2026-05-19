# SPIFFE & SPIRE — Standalone Hands-On Tutorial

> **Learn workload identity from scratch on a single machine. No cloud account needed.**

[![SPIFFE](https://img.shields.io/badge/SPIFFE-Standard-blue)](https://spiffe.io)
[![SPIRE](https://img.shields.io/badge/SPIRE-v1.9-green)](https://github.com/spiffe/spire)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED)](https://docs.docker.com/compose/)
[![kind](https://img.shields.io/badge/kind-Kubernetes-326CE5)](https://kind.sigs.k8s.io/)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

---

## 🎯 What You'll Learn

| Track | Focus | Requirement | Labs |
|-------|-------|-------------|------|
| [**🐳 Track A — Docker Compose**](./docker-compose/README.md) | SPIFFE concepts, mTLS, SVID inspection | Docker Desktop only | 8 labs |
| [**☸️ Track B — kind/Kubernetes**](./kind/README.md) | K8s attestation, federation, Envoy mTLS | Docker Desktop + kind | 7 labs |

**Total: 15 hands-on labs. No cloud. No sign-ups. No cost.**

After completing this tutorial, graduate to the cloud: **[SPIFFEBasics → Azure AKS deployment](https://github.com/jeevanbisht/SPIFFEBasics)**

---

## 🤔 The Problem SPIFFE/SPIRE Solves

In modern distributed systems, **services need to prove who they are** to other services. The traditional approach:

```
❌ Traditional (broken) approach
─────────────────────────────────
• Long-lived API keys stored in environment variables
• Shared database passwords in config files
• IP-based allowlists ("trust everything from 10.0.0.x")
• Certificates that never rotate
• No cryptographic proof of workload identity
```

```
✅ SPIFFE/SPIRE approach
─────────────────────────
• Every workload gets a cryptographic identity (SVID)
• Short-lived, auto-rotating certificates (default: 1 hour)
• Identity is based on workload attributes — not IP or hostname
• Mutual TLS between all services — zero shared secrets
• Works across Docker, Kubernetes, VMs, bare metal, cloud
```

---

## 📐 Architecture Overview

```
+----------------------------------------------------------------+
|                      SPIRE Architecture                        |
|                                                                |
|  +--------------+          +-----------------------------+     |
|  | SPIRE Server |          |           Node              |     |
|  |              |<-------->|  +-------------+            |     |
|  |  - CA / PKI  |   mTLS   |  | SPIRE Agent |            |     |
|  |  - Registry  |          |  |             |<-----+     |     |
|  |  - Policies  |          |  | - Attests   |      |     |     |
|  +--------------+          |  | - Issues    |  Workload  |     |
|                            |  |   SVIDs     |  API (Unix |     |
|                            |  +-------------+  socket)   |     |
|                            |        ^           |        |     |
|                            |        |    +------v------+ |     |
|                            |        |    |  Workload   | |     |
|                            |        |    |  (your app) | |     |
|                            |        |    |             | |     |
|                            |        |    |  Gets SVID  | |     |
|                            |        +----+-------------+ |     |
|                            +-----------------------------+     |
+----------------------------------------------------------------+
```

### Key Concepts at a Glance

| Concept | What It Is |
|---------|-----------|
| **SPIFFE** | Standard — defines what a workload identity looks like |
| **SPIFFE ID** | URI like `spiffe://example.org/service/frontend` |
| **SVID** | X.509 cert or JWT token that carries the SPIFFE ID |
| **SPIRE** | Implementation — issues and manages SVIDs |
| **Trust Domain** | Security boundary (like a DNS domain for identities) |
| **Node Attestation** | How an agent proves *which node* it's running on |
| **Workload Attestation** | How an agent proves *which process* is requesting an SVID |

> 📖 **Full glossary:** [docs/glossary.md](./docs/glossary.md)

---

## ⚡ 60-Second Quickstart

```bash
git clone https://github.com/jeevanbisht/SPIFFEBasicsDesktop.git
cd SPIFFEBasicsDesktop

# Track A — Docker Compose (no Kubernetes needed)
cd docker-compose
docker compose up -d --build
# Wait ~60 seconds, then:
curl http://localhost:3000/demo
# ← Served over mTLS using SPIFFE SVIDs, zero passwords!

# Track B — kind/Kubernetes
cd ../kind && ./setup.sh          # macOS/Linux (bash)
# Windows PowerShell:
cd ..\kind; .\setup.ps1
# Windows Git Bash / WSL2:
# cd ../kind && ./setup.sh
```

**Only requirement: [Docker Desktop](https://www.docker.com/products/docker-desktop/)**

---

## 📋 Prerequisites

| Requirement | Version | Install | Check |
|-------------|---------|---------|-------|
| Docker Desktop | 4.x+ | [docker.com](https://www.docker.com/products/docker-desktop/) | `docker --version` |
| docker compose | v2 (built-in) | Included in Docker Desktop | `docker compose version` |
| **Track B only:** kind | 0.20+ | [kind.sigs.k8s.io](https://kind.sigs.k8s.io/docs/user/quick-start/) · Windows: `winget install Kubernetes.kind` | `kind --version` |
| **Track B only:** kubectl | 1.28+ | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) · Windows: `winget install Kubernetes.kubectl` | `kubectl version --client` |

> 💡 **Windows users:** Use PowerShell (`.\setup.ps1`) or Git Bash / WSL2 (`./setup.sh`) for Track B scripts.

```bash
# Auto-check all prerequisites
./check-prereqs.sh
```

---

## 🗂️ Repository Structure

```
SPIFFEBasicsDesktop/
├── README.md                     ← You are here
├── Makefile                      ← Convenience commands (make up, make demo...)
├── check-prereqs.sh              ← Prerequisite checker
├── docs/
│   ├── concepts.md               ← Core SPIFFE/SPIRE concepts (read first!)
│   ├── glossary.md               ← Full term reference (30+ entries)
│   └── architecture/
│       └── overview.md           ← Deep-dive: attestation flows, cert chains
├── labs/
│   └── README.md                 ← Lab index with navigation table
├── docker-compose/               ← 🐳 Track A
│   ├── docker-compose.yml        ← One file runs everything
│   ├── spire/                    ← SPIRE Server + Agent config
│   ├── apps/
│   │   ├── frontend/             ← Node.js mTLS client
│   │   └── backend/              ← Node.js mTLS server (verifies SPIFFE ID)
│   └── README.md                 ← 8 hands-on labs
└── kind/                         ← ☸️ Track B
    ├── setup.sh                  ← Creates cluster + deploys SPIRE (macOS/Linux/WSL2)
    ├── setup.ps1                 ← Creates cluster + deploys SPIRE (Windows PowerShell)
    ├── teardown.sh               ← Deletes kind clusters (macOS/Linux/WSL2)
    ├── teardown.ps1              ← Deletes kind clusters (Windows PowerShell)
    ├── kind-config.yaml          ← 3-node cluster config
    ├── spire/k8s/                ← All Kubernetes manifests
    ├── advanced/
    │   ├── disk-ca/              ← Custom root CA
    │   ├── two-cluster/          ← SPIFFE federation
    │   └── envoy/                ← Transparent mTLS with Envoy
    └── README.md                 ← 7 hands-on labs
```

---

## 📚 Learning Path

```
START
  |
  v
Read concepts (10 min)
  docs/concepts.md
  |
  +--- Track A: Docker Compose ---------------------+
  |    docker-compose/README.md                     |
  |      Lab 1: Your first SVID                     |
  |      Lab 2: mTLS call between services          |
  |      Lab 3: Inspect the X.509 certificate       |
  |      Lab 4: Verify the trust chain              |
  |      Lab 5: Zero trust - no SVID = no access    |
  |      Lab 6: Watch automatic SVID rotation       |
  |      Lab 7: Register a new service dynamically  |
  |      Lab 8: Explore SPIRE Server state          |
  |                                                 |
  +--- Track B: kind/Kubernetes --------------------+
       kind/README.md
         Lab 1: Explore the cluster
         Lab 2: Node attestation (k8s_psat deep dive)
         Lab 3: Workload attestation
         Lab 4: ClusterSPIFFEID - automatic registration
         Lab 5: [Advanced] Custom disk-based root CA
         Lab 6: [Advanced] Two-cluster SPIFFE federation
         Lab 7: [Advanced] Envoy transparent mTLS
              |
             DONE - Ready for cloud!
             github.com/jeevanbisht/SPIFFEBasics
```

---

## 🛠️ Makefile Shortcuts

```bash
make up          # Start Track A (docker compose up -d --build)
make down        # Stop Track A
make demo        # Run the end-to-end demo
make logs        # Follow all container logs
make status      # Show service health
make inspect-cert  # Print the SVID certificate details
make kind-up     # Set up Track B (kind cluster + SPIRE)
make kind-down   # Tear down Track B
```

---

## 🔗 Next Steps After This Tutorial

| Resource | What You'll Get |
|----------|----------------|
| [SPIFFEBasics](https://github.com/jeevanbisht/SPIFFEBasics) | AKS deployment, Azure Key Vault CA, OIDC federation |
| [spiffe.io/docs](https://spiffe.io/docs/latest/) | Official SPIFFE specification |
| [github.com/spiffe/spire](https://github.com/spiffe/spire) | SPIRE source code and examples |
| [github.com/spiffe/spire-tutorials](https://github.com/spiffe/spire-tutorials) | Official SPIRE tutorials |
| [CNCF SPIFFE/SPIRE](https://www.cncf.io/projects/spiffe-spire/) | Project governance and roadmap |

---

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## 📄 License

MIT — see [LICENSE](LICENSE).
