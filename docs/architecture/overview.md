# SPIFFE/SPIRE Architecture Deep-Dive

This document explains how identity is established, issued, rotated, and trusted across the standalone tutorial tracks.

---

## 1. The Full Certificate Chain

When a workload receives an X.509-SVID, it is not just getting “a cert.” It is getting a certificate that chains back to the trust root for the SPIFFE trust domain.

```text
Workload X.509-SVID
    Subject: (usually empty or minimal)
    SAN URI: spiffe://example.org/service/frontend
    TTL: 1 hour
          │
          ▼
SPIRE signing CA
    Used by SPIRE Server to sign workload identities
          │
          ▼
Trust domain root CA
    Root of trust distributed in the trust bundle
```

In practical terms:
- The **workload SVID** identifies the specific service
- The **SPIRE signing CA** signs that SVID
- The **root CA** anchors trust for the domain
- The **trust bundle** contains the CA material that lets peers verify the chain

Verification looks conceptually like this:

```bash
openssl verify -CAfile bundle.pem svid.pem
```

In Track A, the simplest form is often a self-signed SPIRE root or a disk-backed CA chain. In Track B, the same chain is distributed into the cluster and consumed by agents and workloads.

---

## 2. Attestation Flow: Docker (`join_token`)

Track A uses `join_token` because there is no Kubernetes API server or cloud metadata service available. The token is a bootstrap mechanism that gets the agent into a trusted state.

### Step-by-step

1. SPIRE Server starts with the trust domain and CA state
2. A bootstrap process generates a short-lived join token
3. SPIRE Agent starts and presents that token to SPIRE Server
4. SPIRE Server validates the token and attests the agent
5. SPIRE Server issues an **agent SVID** to the attested agent
6. A workload connects to the agent's Workload API socket
7. SPIRE Agent runs **docker workload attestation** and collects selectors
8. SPIRE Agent asks SPIRE Server for any registration entries matching those selectors
9. SPIRE Server issues the workload SVID
10. SPIRE Agent returns the SVID and trust bundle to the workload

### ASCII flow

```text
┌─────────────────┐       ┌─────────────────┐       ┌────────────────────┐
│ SPIRE Bootstrap │       │  SPIRE Agent    │       │    SPIRE Server    │
└────────┬────────┘       └────────┬────────┘       └─────────┬──────────┘
         │                         │                          │
         │ generate join token     │                          │
         ├───────────────────────────────────────────────────►│
         │                         │                          │
         │ pass token to agent     │                          │
         ├────────────────────────►│                          │
         │                         │ present join token       │
         │                         ├─────────────────────────►│
         │                         │                          │ validate token
         │                         │                          │ attest agent
         │                         │◄─────────────────────────┤ issue agent SVID
         │                         │                          │
         │                         │ expose Workload API      │
         │                         │                          │
┌────────▼────────┐                │                          │
│    Workload     │                │                          │
└────────┬────────┘                │                          │
         │ request SVID via socket │                          │
         ├────────────────────────►│                          │
         │                         │ docker attestation       │
         │                         │ selectors: label/image   │
         │                         ├─────────────────────────►│
         │                         │                          │ match registration entry
         │                         │◄─────────────────────────┤ issue workload SVID
         │◄────────────────────────┤                          │
         │ gets cert + key + bundle│                          │
```

### Why it works well for standalone labs

- No dependency on cloud identity systems
- Easy to bootstrap on a laptop
- Makes the agent/server trust relationship visible to learners

### Security caveat

`join_token` is a bootstrap secret. It should be short-lived, tightly scoped, and never treated as a permanent identity mechanism.

---

## 3. Attestation Flow: Kubernetes (`k8s_psat`)

Track B uses `k8s_psat` (Kubernetes Projected Service Account Token), which ties node attestation to Kubernetes-issued identity material.

### Step-by-step

1. The kubelet mounts a **projected service account token** into each SPIRE Agent pod
2. The token is audience-scoped for SPIRE Server
3. SPIRE Agent sends the token to SPIRE Server during node attestation
4. SPIRE Server calls the Kubernetes **TokenReview API**
5. Kubernetes validates the token signature, audience, and expiry
6. SPIRE Server extracts node / pod context from the validated token
7. SPIRE Server attests the agent and issues an **agent SVID**
8. Workloads later connect to that agent and request SVIDs
9. SPIRE Agent performs **k8s workload attestation** using pod metadata
10. Matching registration entries result in workload SVID issuance

### ASCII flow

```text
┌─────────────┐     projected SA token      ┌──────────────┐
│   kubelet   │────────────────────────────►│ SPIRE Agent  │
└──────┬──────┘                             └──────┬───────┘
       │                                          │
       │                                          │ present token
       │                                          ├──────────────────────► ┌──────────────┐
       │                                          │                        │ SPIRE Server │
       │                                          │                        └──────┬───────┘
       │                                          │                               │
       │                                          │                               │ TokenReview API
       │                                          │                               ├────────────────────► ┌────────────────────┐
       │                                          │                               │                     │ Kubernetes API     │
       │                                          │                               │                     │ authentication.k8s │
       │                                          │                               │ ◄───────────────────┤ token validated     │
       │                                          │◄──────────────────────────────┤ attest agent        └────────────────────┘
       │                                          │  issue agent SVID             │
       │                                          │                               │
┌──────▼──────┐                                   │                               │
│  Workload   │ request SVID via Workload API     │                               │
└──────┬──────┘──────────────────────────────────►│                               │
       │                                          │ k8s workload attestation      │
       │                                          │ selectors: ns/sa/pod labels   │
       │                                          ├──────────────────────────────►│
       │                                          │◄──────────────────────────────┤ issue workload SVID
       │◄─────────────────────────────────────────┤                               │
       │      gets SVID + trust bundle            │                               │
```

### Why `k8s_psat` matters

- Uses Kubernetes as the source of truth
- Binds attestation to real cluster-issued tokens
- Avoids static bootstrap secrets for normal agent operation
- Scales cleanly across many nodes

---

## 4. SVID Lifecycle

An SVID is deliberately short-lived.

### Timeline

```text
0% TTL   -> SVID issued
50% TTL  -> SPIRE Agent proactively rotates / renews it
100% TTL -> Old SVID expires
```

### Detailed behavior

1. A workload starts and fetches an SVID from the Workload API
2. The agent caches the identity material locally
3. At about 50% of the TTL, the agent requests a fresh SVID from SPIRE Server
4. The new SVID has the **same SPIFFE ID** but a **new certificate** and often a new keypair
5. Clients using a library helper such as `X509Source` automatically pick up the new identity
6. Existing connections may continue until re-handshake, while new connections use the fresh cert

### Why rotation matters

- Limits the blast radius of compromise
- Removes the operational burden of manual certificate renewals
- Keeps identities continuously fresh without app restarts

### `X509Source` behavior

With a proper SPIFFE SDK integration, the application typically does **not** poll files or restart. `X509Source` watches the Workload API stream and updates the in-memory certificate material automatically.

---

## 5. Trust Bundle Distribution

Identity is only useful if peers can verify each other.

SPIRE distributes trust bundles from the server to agents, then to workloads.

```text
SPIRE Server
   │  authoritative bundle for trust domain
   ▼
SPIRE Agent
   │  caches bundle locally
   ▼
Workloads / proxies / SDKs
   use bundle to verify peer SVIDs
```

### What gets distributed

- The trust domain root CA or intermediate chain needed for validation
- Federated bundles from peer trust domains
- Updated bundle data when roots rotate or federation changes

### Kubernetes note: `k8sbundle` notifier

In Kubernetes-centric deployments, the `k8sbundle` notifier can project trust bundle data into cluster resources so controllers and workloads can consume the latest CA material in a cluster-native way.

### Key idea

A workload does **not** need the private key of any other workload. It only needs the trust bundle that lets it verify the peer's X.509-SVID chain.

---

## 6. mTLS Handshake

Once both workloads have SVIDs, mutual TLS becomes a standard certificate-based handshake with SPIFFE identity embedded in the URI SAN.

### Sequence diagram

```text
Frontend workload                    Backend workload
      │                                     │
      │ 1. TCP connect                      │
      ├────────────────────────────────────►│
      │                                     │
      │ 2. ClientHello                      │
      ├────────────────────────────────────►│
      │                                     │
      │ 3. ServerHello + backend X.509-SVID │
      │◄────────────────────────────────────┤
      │                                     │
      │ 4. Verify backend cert chain        │
      │    against trust bundle             │
      │ 5. Check SAN URI = expected SPIFFE  │
      │                                     │
      │ 6. Send frontend X.509-SVID         │
      ├────────────────────────────────────►│
      │                                     │
      │ 7. Backend verifies client cert     │
      │    against trust bundle             │
      │ 8. Backend checks SPIFFE ID policy  │
      │                                     │
      │ 9. Session keys established         │
      │◄───────────────────────────────────►│
      │                                     │
      │ 10. Encrypted app traffic           │
      │◄───────────────────────────────────►│
```

### What each side validates

**Client validates:**
- The backend certificate chains to a trusted bundle
- The backend certificate is not expired
- The backend SPIFFE ID matches policy

**Server validates:**
- The client certificate chains to a trusted bundle
- The client certificate is not expired
- The client SPIFFE ID is authorized

That final authorization step is where application policy comes in. A backend may accept `spiffe://example.org/service/frontend` but reject every other SPIFFE ID.

---

## 7. Why `join_token` vs `k8s_psat`

Both solve node attestation, but they are optimized for different environments.

| Dimension | `join_token` | `k8s_psat` |
|-----------|--------------|------------|
| Best fit | Local dev, single-machine labs, simple bootstrap | Kubernetes clusters |
| Proof source | One-time token from SPIRE Server | Kubernetes-projected service account token |
| External dependency | None beyond SPIRE itself | Kubernetes API / TokenReview |
| Operational complexity | Low | Moderate |
| Security strength | Good for bootstrap, weaker if mishandled | Stronger, tied to cluster-issued identity |
| Rotation model | Token used once, then agent uses SVID | Token naturally short-lived and renewable |
| Standalone tutorial usage | Track A | Track B |

### Security considerations

**Use `join_token` when:**
- You are on a laptop or test machine
- You want to teach the bootstrap flow clearly
- You do not have Kubernetes or cloud identity available

**Use `k8s_psat` when:**
- Your agents run in Kubernetes
- You want attestation backed by cluster-issued JWTs
- You want tighter audience, expiry, and control-plane validation guarantees

### Rule of thumb

- **Track A:** `join_token` is the right teaching and local-dev tool
- **Track B / production-style K8s:** `k8s_psat` is the right operational model

---

## Final Mental Model

```text
Attest the node
-> attest the workload
-> issue an SVID
-> distribute the trust bundle
-> use mTLS with SPIFFE IDs as the authenticated identity
-> rotate automatically before expiry
```

That is the core SPIFFE/SPIRE loop, whether you are running on one laptop, a kind cluster, or a cloud production platform.
