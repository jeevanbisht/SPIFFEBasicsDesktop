# SPIFFE & SPIRE Glossary

A complete reference for all terminology used in this standalone tutorial series.

> Also see: [SPIFFEBasics glossary](https://github.com/jeevanbisht/SPIFFEBasics/blob/main/docs/glossary.md) for Azure-specific extensions.

---

## Core SPIFFE Concepts

### SPIFFE — Secure Production Identity Framework For Everyone
An open standard (CNCF project) that defines a universal framework for workload identity. SPIFFE is the specification; SPIRE is one implementation of that specification.

### SPIFFE ID
A URI that uniquely identifies a workload within a trust domain.

**Format:** `spiffe://<trust-domain>/<path>`

**Examples:**
```text
spiffe://example.org/service/frontend
spiffe://example.org/service/backend
spiffe://example.org/ns/demo/sa/frontend
```

Rules:
- Scheme is always `spiffe://`
- Trust domain is the authority portion
- Path identifies the workload
- Query strings and fragments are not allowed

### SVID — SPIFFE Verifiable Identity Document
The cryptographic proof of a workload's identity. An SVID can be either:

1. **X.509-SVID** — an X.509 certificate used for mTLS
2. **JWT-SVID** — a signed JWT used for bearer-style authn/authz

### X.509-SVID
A short-lived X.509 certificate whose URI SAN contains the SPIFFE ID.

**Example:**
```text
URI:spiffe://example.org/service/frontend
```

Used when workloads need to do TLS, especially mutual TLS.

### JWT-SVID
A signed JWT whose `sub` claim is the SPIFFE ID.

**Example payload:**
```json
{
  "sub": "spiffe://example.org/service/frontend",
  "aud": ["backend-service"],
  "exp": 1735689900,
  "iat": 1735689600
}
```

Used when workloads need application-layer tokens instead of TLS client certificates.

### Trust Domain
The security boundary within which SPIFFE IDs are trusted.

A trust domain has:
- A root of trust
- A trust bundle containing CA certificate(s)
- A namespace of SPIFFE IDs

In this repo the default trust domain is usually `example.org`.

### Trust Bundle
The set of CA certificates for a trust domain. Workloads use the trust bundle to verify peer SVIDs.

**Typical contents:**
- The current SPIRE signing root or intermediate chain
- Federated bundles from other trust domains (if federation is enabled)

### Workload API
A gRPC API exposed by SPIRE Agent, usually over a Unix domain socket such as `/run/spire/sockets/agent.sock`.

Workloads use it to:
- Fetch X.509-SVIDs
- Fetch JWT-SVIDs
- Fetch trust bundles
- Watch for rotation events

### Bundle Endpoint
A SPIFFE-defined HTTPS endpoint that publishes trust bundles. Federation depends on bundle endpoints so one trust domain can download and trust another domain's bundle.

### Trust Bundle Endpoint Profile
The SPIFFE spec that defines how bundles are served over HTTPS, signed, and refreshed. This is what makes federation interoperable between trust domains.

### Workload
Any running software component that needs identity: a process, container, pod, VM guest, sidecar, proxy, or daemon.

### Identity Document
A generic way to describe the proof attached to a workload. In SPIFFE, that proof is an SVID.

### Parent ID
The SPIFFE ID of the agent or upstream workload that is allowed to request an SVID for a registration entry.

**Example:**
```text
Parent ID: spiffe://example.org/spire/agent/join_token/4b3d0f7e
```

The parent-child relationship is how SPIRE constrains which agents can mint which workload identities.

---

## SPIRE Components

### SPIRE
The SPIFFE Runtime Environment. SPIRE issues, rotates, and distributes SVIDs based on attestation policy.

### SPIRE Server
The central authority in a SPIRE deployment.

Responsibilities:
- Maintains registration entries
- Attests agents
- Signs and issues SVIDs
- Publishes bundles and federation data
- Acts as or delegates to the trust domain CA

In Kubernetes it is commonly deployed as a **StatefulSet**. In Docker Compose it runs as a long-lived container with persistent data volumes.

### SPIRE Agent
Runs on each node or host where workloads need identity.

Responsibilities:
- Attests itself to SPIRE Server
- Performs workload attestation locally
- Exposes the Workload API
- Caches SVIDs and bundles
- Rotates SVIDs before expiry

In Kubernetes it is usually a **DaemonSet**. In Track A it is a standalone container representing the local node.

### Registration Entry
A policy object in SPIRE Server that says:
- which selectors must match,
- which parent is allowed,
- which SPIFFE ID to issue,
- and which TTL / DNS / admin settings apply.

**Example:**
```text
SPIFFE ID: spiffe://example.org/service/frontend
Parent ID: spiffe://example.org/spire/agent/join_token/4b3d0f7e
Selectors:
  - docker:label:spiffe.io/service:frontend
TTL: 3600
```

### Selector
An attribute produced during attestation and used to match a registration entry.

Examples:
- `docker:label:spiffe.io/service:frontend`
- `k8s:ns:demo`
- `k8s:sa:frontend`
- `unix:uid:1000`

### TTL — Time To Live
The validity period for an issued SVID. A common lab value is 3600 seconds (1 hour).

### SVID TTL
The actual lifespan of the credential. SPIRE agents normally renew at around 50% of the TTL so workloads get a fresh identity before expiry.

### X509Source
A helper object from SPIFFE SDKs that automatically watches the Workload API and reloads X.509-SVIDs and bundles as they rotate.

### JWTSource
The JWT equivalent of `X509Source`: a helper that obtains JWT-SVIDs and trust bundles from the Workload API.

---

## Attestation Concepts

### Node Attestation
The process by which a SPIRE Agent proves to SPIRE Server what node or machine it is running on.

| Attestor | Where Used | How It Works | Standalone Context |
|----------|-----------|--------------|--------------------|
| `join_token` | Dev / local labs | Server generates a one-time token; agent presents it during bootstrap | Primary Track A flow |
| `k8s_psat` | Kubernetes | Agent presents a projected service account token that the server validates via TokenReview | Primary Track B flow |
| `azure_msi` | Azure VMs | Agent proves identity with Azure Managed Identity | Mentioned for cloud progression |
| `aws_iid` | AWS EC2 | Agent uses the EC2 instance identity document | Mentioned for portability |
| `x509pop` | Any environment | Agent proves possession of a pre-existing certificate/private key | Useful in advanced bootstrap patterns |

### Workload Attestation
The process by which SPIRE Agent determines which workload is connecting to the Workload API.

| Attestor | What It Checks | Where You'll See It |
|----------|---------------|---------------------|
| `docker` | Container labels, image metadata, env / runtime info | Track A Docker Compose labs |
| `k8s` | Pod namespace, service account, pod labels, pod UID | Track B kind labs |
| `unix` | UID, GID, PID from the local process and socket credentials | Useful for non-container local processes |

### join_token
A simple node attestation method designed for bootstrap and non-cloud environments.

**How it works:**
1. SPIRE Server generates a token
2. The token is passed to the agent out-of-band
3. The agent presents it once during startup
4. The server exchanges that bootstrap proof for a permanent agent SVID

**Why it fits Track A:**
- No Kubernetes dependency
- No cloud metadata service required
- Easy to understand on a single machine

**Security note:** join tokens must be short-lived and treated as bootstrap secrets, not long-lived credentials.

### k8s_psat
`k8s_psat` stands for Kubernetes Projected Service Account Token.

It is the standard way for a SPIRE Agent pod to prove its node identity in Kubernetes.

**Deep explanation:**
1. The kubelet mounts a projected service account token into the agent pod
2. The token includes Kubernetes claims, audience, pod identity, and node context
3. The agent sends that token to SPIRE Server
4. SPIRE Server calls the Kubernetes TokenReview API
5. If Kubernetes validates the token, SPIRE Server accepts the agent as attested
6. SPIRE issues the agent an SVID such as:

```text
spiffe://example.org/spire/agent/k8s_psat/spiffe-lab/<node-uid>
```

**Why it is stronger than join_token:**
- Backed by Kubernetes signing keys
- Audience restricted
- Short-lived
- Bound to a specific pod/service account context

### TokenReview API
A Kubernetes API used by SPIRE Server during `k8s_psat` attestation. The server submits the projected token to Kubernetes and asks, “Is this token valid for this audience?”

### Projected Service Account Token
A short-lived JWT mounted into pods by Kubernetes. It replaces older long-lived service account secrets and is central to `k8s_psat`.

### Bootstrap
The initial process that gets a new agent or workload into a trusted state. In Track A, bootstrap typically means generating a join token, starting the agent, and creating registration entries.

### Re-attestation
The process of renewing or repeating node attestation if the agent reconnects or its state is lost.

---

## Deployment and PKI Concepts

### Upstream Authority
A SPIRE Server plugin that allows the server to chain its signing identity to an external CA instead of self-signing everything.

| Upstream Authority | What It Uses | Standalone Equivalent / Note |
|--------------------|--------------|------------------------------|
| `disk` | Root/intermediate CA material stored on disk | Primary advanced standalone option |
| `aws_pca` | AWS Private CA | Cloud progression example |
| `azure_keyvault` | Azure Key Vault-backed CA | Azure-specific equivalent in SPIFFEBasics |
| `vault` | HashiCorp Vault PKI | Common enterprise integration |

### Root CA
The ultimate trust anchor for the trust domain.

In this standalone repo, the simplest flows use a self-signed SPIRE root. Advanced labs may use a **disk-based CA** to simulate enterprise PKI.

### Intermediate CA
A CA certificate signed by the root CA and used by SPIRE Server to sign workload SVIDs. This keeps the root offline or less frequently used.

### Certificate Chain
The ordered chain a verifier walks when checking an X.509-SVID:

```text
Workload SVID -> SPIRE intermediate/server CA -> Root CA in trust bundle
```

### Self-Signed CA
A root certificate signed by its own private key. Common in labs, dev, and tutorial environments.

### Disk CA
A standalone-friendly upstream authority pattern where CA key material is stored locally on disk rather than in Azure Key Vault or AWS PCA.

### OIDC Discovery Provider (ODP)
A SPIRE feature that exposes JWT-SVID validation metadata through standard OpenID Connect discovery endpoints. This lets external systems verify SPIRE-issued JWTs.

### Workload Identity Federation
A pattern where cloud IAM systems trust an external OIDC provider such as SPIRE. That allows a workload to exchange its SPIFFE-derived token for a cloud access token without secrets.

### Federation
The ability for workloads in one trust domain to trust identities from another trust domain.

Typical steps:
1. Each trust domain exposes a bundle endpoint
2. Each SPIRE Server learns the peer's bundle
3. Agents and workloads receive both bundles
4. mTLS can now verify identities from both domains

### OIDC Issuer
The URL that identifies the JWT issuer. For SPIRE OIDC flows, this is the discovery provider endpoint, not the workload itself.

### Audience
The intended recipient of a JWT-SVID. A verifier should reject JWTs whose audience does not include the expected service.

---

## Related Networking and Runtime Terms

### mTLS — Mutual TLS
TLS where both client and server present certificates. SPIFFE enables mTLS without manually provisioning per-service certificates.

### TLS Handshake
The protocol exchange where peers negotiate ciphers, exchange certificates, validate trust, and establish session keys. With SPIFFE, both certificates are SVIDs.

### Envoy
A high-performance proxy often used as a sidecar. Envoy can fetch identities from SPIRE and enforce mTLS without application code handling certificates directly.

### SDS — Secret Discovery Service
An xDS API used by Envoy to fetch TLS assets dynamically. SPIRE can act as the SDS source so Envoy receives certificates and bundle updates automatically.

### Sidecar Proxy
A helper container deployed next to an application container. In SPIFFE environments, the sidecar often owns the mTLS connection while the app speaks plain HTTP locally.

### Zero Trust
A security model that assumes no network location is inherently trusted. SPIFFE supports this by basing trust on cryptographic workload identity rather than IP ranges.

---

## Kubernetes Terms in Context

### Controller Manager
In SPIRE's Kubernetes integration, the controller manager watches Kubernetes resources and creates or manages SPIRE registration data automatically.

### ClusterSPIFFEID
A Kubernetes custom resource that tells the SPIRE Controller Manager to automatically issue SPIFFE IDs to workloads matching a selector pattern.

**Example intent:**
```text
All pods in namespace demo with service account frontend
-> get spiffe://example.org/ns/demo/sa/frontend
```

### DaemonSet
A Kubernetes workload type that ensures one pod runs on each node. SPIRE Agent is usually deployed as a DaemonSet.

### StatefulSet
A Kubernetes workload type for stateful applications with stable identities and persistent storage. SPIRE Server is commonly deployed as a StatefulSet.

### Namespace
A Kubernetes scoping boundary often used in SPIFFE selectors, e.g. `k8s:ns:demo`.

### Service Account
A Kubernetes identity attached to a pod. It is heavily used in SPIRE registration and in `k8s_psat` node attestation.

### Pod UID
A unique Kubernetes-generated identifier for a pod. It can appear in selectors or attestation metadata.

### CRD — Custom Resource Definition
The Kubernetes extension mechanism used to define resources such as `ClusterSPIFFEID`.

### k8sbundle Notifier
A Kubernetes-oriented bundle delivery path used in some SPIRE setups to propagate trust bundles into cluster resources so workloads and controllers can consume updated CA material.

---

## Operational Terms

### Rotation
The process of replacing SVIDs before they expire. By default, SPIRE renews around 50% of the TTL.

### Expiry
The point at which an SVID is no longer valid. Well-behaved SPIFFE clients renew before this happens.

### Cache
SPIRE Agent stores issued SVIDs and trust bundles locally so workloads can retrieve them quickly.

### Revocation Model
SPIFFE generally relies more on short TTLs and rotation than on traditional CRLs or OCSP for workload credentials.

### Socket Path
The filesystem path where the Workload API is exposed, typically:
```text
/run/spire/sockets/agent.sock
```

### Health Check
A readiness or liveness signal for SPIRE components. Tutorials often wait for the SPIRE Server and SPIRE Agent to become healthy before running labs.

---

## Practical Example: Putting It Together

```text
Docker frontend container starts
-> docker workload attestor produces selector docker:label:spiffe.io/service:frontend
-> selector matches registration entry
-> SPIRE Agent fetches X.509-SVID from SPIRE Server
-> frontend gets spiffe://example.org/service/frontend
-> frontend calls backend with mTLS
-> backend verifies client cert using trust bundle
```

The same idea applies in Kubernetes, except the selectors usually come from `k8s:ns`, `k8s:sa`, labels, and pod identity rather than Docker labels.
