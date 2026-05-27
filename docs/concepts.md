# SPIFFE & SPIRE — Core Concepts (No Cloud Required)

This document explains every concept you need before running the labs.
Read this once, then keep it open as a reference.

> 🗺️ **Visual learner?** See the [Key Use Cases → Lab Mapping](./spiffe-use-cases.html) for an interactive diagram of what each lab covers.

---

## The One-Sentence Summary

> SPIFFE/SPIRE gives every workload a **cryptographic identity** — automatically issued, auto-rotating, and verifiable without passwords or shared secrets.

---

## The Problem in Plain English

Imagine two services: **OrderService** and **PaymentService**.

PaymentService needs to know: *"Is this really OrderService calling me, or an attacker?"*

❌ **Bad answers people use today:**
- Share a password (`PAYMENT_API_KEY=abc123`) — stored in env vars, leaked in logs, never rotated
- Trust the IP (`if source_ip == 10.0.0.5: allow`) — any pod on that node wins
- Long-lived TLS cert — expires in 1 year, rotation is painful, often skipped

✅ **SPIFFE answer:**
- Every workload gets a TLS certificate (SVID) automatically
- The certificate expires in **1 hour** and is replaced automatically
- Both services present their certificate → mutual TLS → cryptographic proof
- No passwords, no IPs, no humans involved

---

## The Cast of Characters

```
┌─────────────────────────────────────────────────────────┐
│                   Your Infrastructure                    │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │              SPIRE SERVER                        │   │
│  │  • The Certificate Authority (CA)               │   │
│  │  • Knows "who gets which identity" (registry)   │   │
│  │  • Signs SVIDs                                  │   │
│  │  • One per environment (or HA cluster)          │   │
│  └────────────────────┬────────────────────────────┘   │
│                       │ mTLS                            │
│           ┌───────────┼───────────┐                    │
│           │           │           │                    │
│  ┌────────▼───┐ ┌─────▼──────┐ ┌─▼──────────┐        │
│  │SPIRE AGENT │ │SPIRE AGENT │ │SPIRE AGENT │        │
│  │ (node 1)  │ │ (node 2)  │ │ (node 3)  │        │
│  │           │ │           │ │           │        │
│  │ • 1 per   │ │ • Attests │ │ • Serves  │        │
│  │   node    │ │   node    │ │   Workload│        │
│  │ • Issues  │ │ • Issues  │ │   API     │        │
│  │   SVIDs   │ │   SVIDs   │ │ (socket)  │        │
│  └─────┬─────┘ └─────┬─────┘ └─────┬─────┘        │
│        │ Unix socket  │             │              │
│  ┌─────▼──┐     ┌────▼───┐   ┌─────▼──┐           │
│  │  App A │     │  App B │   │  App C │           │
│  │(OrderS)│     │(PaymtS)│   │  (DB)  │           │
│  └────────┘     └────────┘   └────────┘           │
└─────────────────────────────────────────────────────────┘
```

---

## Key Terms (Plain English)

### SPIFFE ID
A URI that names a workload. Like a username, but for services.

```
spiffe://example.org/ns/payments/sa/order-service
         └────────┘  └──────────────────────────┘
         trust domain        workload path
         (your org's         (you define this)
          boundary)
```

Rules:
- Always starts with `spiffe://`
- Trust domain = your security boundary (like a DNS domain)
- Path = whatever makes sense for your workloads
- **No IP addresses** — identity is about *what* you are, not *where*

### SVID — SPIFFE Verifiable Identity Document
The actual credential. Two types:

**X.509-SVID** — a TLS certificate:
```
Certificate:
  Subject: (intentionally empty)
  SAN URI: spiffe://example.org/service/order-svc  ← identity here
  Valid: 2024-01-15 10:00 → 11:00 UTC              ← 1 hour!
  Signed by: SPIRE CA
```
Use this for: **mTLS between services**

**JWT-SVID** — a JSON Web Token:
```json
{
  "sub": "spiffe://example.org/service/order-svc",
  "aud": ["payment-service"],
  "exp": 1705312200
}
```
Use this for: **HTTP Authorization headers**

### Trust Domain
The family of identities. All SVIDs from the same SPIRE Server share a trust domain.

Think of it like a company domain: `acme.com` is the trust domain, and all services at Acme have `spiffe://acme.com/...` identities.

### Trust Bundle
The CA certificate(s) for a trust domain. Workloads use this to verify other workloads' SVIDs.

When service A gets a cert from service B, A checks: "Is B's cert signed by the CA in my trust bundle?" If yes → trusted.

### Node Attestation
How SPIRE Agent proves to SPIRE Server: *"I am running on a legitimate node in this cluster."*

In Docker (this tutorial's Track A): uses a **join token** (pre-shared, one-time)
In Kubernetes (Track B): uses a **projected service account token** (k8s_psat)
In production cloud: uses the cloud provider's attestation (Azure MSI, AWS IID)

### Workload Attestation
How SPIRE Agent figures out: *"Which process is asking for an SVID, and what identity should it get?"*

The agent reads the caller's OS metadata (PID → cgroup → container ID → pod metadata) and matches it against **registration entries**.

### Registration Entry
A rule in SPIRE Server's registry:

```
IF workload has:
  selector: docker:label:app=order-service
THEN issue SVID:
  spiffe://example.org/service/order-service
  TTL: 3600s
```

---

## The Complete Flow (Every Time Your App Starts)

```
1. Your app process starts

2. App connects to SPIRE Agent's Unix socket
   (/run/spire/sockets/agent.sock)

3. Agent sees the connection and gets the caller's PID

4. Agent reads process metadata:
   - In Docker: container labels, image name
   - In K8s: namespace, service account, pod labels

5. Agent looks up matching registration entry in SPIRE Server

6. SPIRE Server signs an SVID for that workload's SPIFFE ID

7. Agent returns to your app:
   - The X.509 certificate (SVID)
   - The private key
   - The trust bundle (to verify others)

8. Your app uses these for mTLS
   (or your framework does it transparently)

9. At 50% of TTL: Agent proactively gets a new SVID
   (default: new cert every 30 min, cert valid 1 hour)

10. Repeat forever — zero human involvement
```

---

## What SPIFFE is NOT

- ❌ Not an authorization system (it proves WHO you are, not WHAT you can do)
- ❌ Not a secret manager (use Vault/Key Vault for secrets)
- ❌ Not a service mesh (Istio/Linkerd use SPIFFE internally)
- ❌ Not a replacement for network security (defense in depth — use both)

---

## Ready? Pick your track:

- 🐳 **[Docker Compose → docker-compose/README.md](../docker-compose/README.md)**
- ☸️ **[kind/Kubernetes → kind/README.md](../kind/README.md)**
