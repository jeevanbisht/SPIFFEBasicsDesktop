# SPIFFE/SPIRE Hands-On Lab — Docker Compose

> **Learn SPIFFE identity and mTLS by doing.**
> No Kubernetes. No cloud. Just Docker Desktop on your laptop.
>
> Every command below is **copy-paste ready** — one command per box, no
> comment lines, no backslash continuations.

This lab walks you through the core SPIFFE concepts step by step:

| Lab | Concept | What You'll Do |
|-----|---------|----------------|
| 1 | **SPIFFE Identity** | See a workload's cryptographic identity |
| 2 | **Mutual TLS (mTLS)** | Watch two services authenticate with zero passwords |
| 3 | **X.509 Certificates** | Inspect the actual cert with `openssl` |
| 4 | **Trust Bundles** | Verify the certificate chain |
| 5 | **Zero Trust** | Try to call a service without a valid identity |
| 6 | **Automatic Rotation** | Watch SPIRE rotate certificates live |
| 7 | **Registration** | Register a new service and see it get an identity |
| 8 | **SPIRE Internals** | Explore the server's state — entries, agents, CAs |

---

## Prerequisites

- **Docker Desktop** (Windows, Mac, or Linux) — [Install](https://docs.docker.com/get-docker/)
- **curl** (included on most systems)
- That's it. Everything else runs in containers.

---

## Quick Start

Start all services (first run downloads images, ~2 minutes):

```
docker compose up -d --build
```

Wait ~60 seconds for health checks, then verify:

```
docker compose ps -a
```

You should see:
```
NAME              STATUS
spire-server      healthy   ← Certificate Authority for the trust domain
spire-init        exited 0  ← Generated a join token for the agent
spire-agent       healthy   ← Issues SVIDs to workloads on this node
spire-bootstrap   exited 0  ← Registered the frontend and backend
frontend          healthy   ← Has a SPIFFE identity, calls backend over mTLS
backend           healthy   ← Has a SPIFFE identity, enforces mTLS
```

> **Tip:** If frontend or backend show `unhealthy`, wait 15 seconds and check
> again — they retry until bootstrap registers their identities.

---

## Lab 1: See Your First SPIFFE Identity

**Concept:** Every workload gets a cryptographic identity called an **SVID**
(SPIFFE Verifiable Identity Document). No passwords, no API keys — just a
certificate automatically issued by SPIRE.

```
curl -s http://localhost:3000/my-identity
```

You'll see:
```json
{
  "spiffeId": "spiffe://example.org/service/frontend",
  "expiresAt": "2026-05-14T04:00:00.000Z",
  "trustDomain": "example.org",
  "message": "👆 My cryptographic identity — no passwords needed!"
}
```

**What just happened?**
- The frontend asked the SPIRE Agent for its identity via a Unix socket
- The agent verified the frontend's process and issued an X.509 certificate
- The certificate contains the SPIFFE ID (`spiffe://example.org/service/frontend`) in its SAN field
- It expires in 1 hour and will be automatically renewed

---

## Lab 2: Mutual TLS — Two Services Authenticate Each Other

**Concept:** In **mTLS**, both client and server present certificates.
The frontend proves who it is to the backend, and the backend proves who it is
to the frontend. Neither side needs a password.

```
curl -s http://localhost:3000/orders
```

You'll see:
```json
{
  "calledBy": "spiffe://example.org/service/frontend",
  "servedBy": "spiffe://example.org/service/backend",
  "orders": [
    { "id": "ORD-001", "item": "Widget A", "qty": 5, "status": "shipped" }
  ],
  "note": "🔒 This response was served over mTLS — both sides presented SPIFFE SVIDs"
}
```

**What just happened?**
- The frontend presented its SVID to the backend as a TLS client certificate
- The backend verified it against the SPIRE trust bundle ✅
- The backend presented its SVID back to the frontend
- The frontend verified the backend's identity ✅
- **Zero passwords or API keys were exchanged** — both sides used SPIFFE certificates

See both identities side by side:

```
curl -s http://localhost:3000/demo
```

---

## Lab 3: Inspect the Certificate with OpenSSL

**Concept:** A SPIFFE SVID is a standard X.509 certificate. The SPIFFE ID
lives in the **Subject Alternative Name (SAN)** URI field. Let's examine it
with `openssl` — the same tool you'd use for any TLS certificate.

**Step 1** — Fetch the SVID from the SPIRE Agent and write PEM files:

```
docker compose exec frontend node spiffe-workload-api/fetch-svid.js /tmp
```

Output:
```
SPIFFE ID : spiffe://example.org/service/frontend
Certificate: /tmp/svid.0.pem
Private key: /tmp/svid.key.pem
CA bundle  : /tmp/bundle.0.pem
```

**Step 2** — Find the SPIFFE ID in the certificate's SAN field:

```
docker compose exec frontend sh -c "openssl x509 -in /tmp/svid.0.pem -text -noout | grep -A1 'Subject Alternative Name'"
```

Expected:
```
X509v3 Subject Alternative Name:
    URI:spiffe://example.org/service/frontend   ← The SPIFFE ID!
```

**Step 3** — Check the validity window (1-hour TTL):

```
docker compose exec frontend sh -c "openssl x509 -in /tmp/svid.0.pem -text -noout | grep -E 'Not Before|Not After'"
```

**Step 4** — See all certificate details:

```
docker compose exec frontend openssl x509 -in /tmp/svid.0.pem -text -noout
```

**Key things to notice:**
- **Subject Alternative Name** → `URI:spiffe://...` — this is the SPIFFE ID
- **Issuer** → `SPIFFE Standalone Tutorial` — signed by SPIRE's CA
- **Key Usage** → TLS Web Server + Client Authentication — enables mTLS
- **Validity** → ~1 hour — short-lived, auto-rotated

---

## Lab 4: Verify the Trust Chain

**Concept:** SPIRE acts as a **Certificate Authority (CA)**. Every SVID chains
back to SPIRE's trust bundle. This is how services know to trust each other.

> **Run Lab 3 first** — it writes the PEM files that this lab uses.

Verify the frontend's SVID was signed by SPIRE's CA:

```
docker compose exec frontend openssl verify -CAfile /tmp/bundle.0.pem /tmp/svid.0.pem
```

Expected:
```
/tmp/svid.0.pem: OK
```

Inspect the CA certificate itself:

```
docker compose exec frontend sh -c "openssl x509 -in /tmp/bundle.0.pem -text -noout | grep -E 'Subject:|Issuer:|CA:'"
```

**What this proves:**
- SPIRE signed the frontend's certificate with its CA key
- Any service that has the trust bundle can verify the frontend's identity
- **No shared secrets** — trust is established through the certificate chain, not passwords

---

## Lab 5: Zero Trust — What Happens Without a Valid Identity?

**Concept:** In a zero-trust architecture, **every connection must be
authenticated**. No valid SVID = no access. Let's prove it.

The backend's health endpoint works (plain HTTP, no mTLS required):

```
docker compose exec backend wget -qO- http://localhost:8444/health
```

Try calling the protected `/orders` endpoint without presenting any certificate:

```
docker compose exec frontend sh -c "wget --timeout=3 -qO- --no-check-certificate https://backend:8443/orders 2>&1 || echo REJECTED"
```

The call is **rejected**. Now try with `openssl s_client` — connect without a client cert:

```
docker compose exec frontend sh -c "echo | openssl s_client -connect backend:8443 2>&1 | grep -E 'alert|error|Verify'"
```

The TLS handshake fails — the server demands a client certificate. Now try via the frontend (which has a valid SVID):

```
curl -s http://localhost:3000/orders
```

**The lesson:** Without a SPIFFE identity, you can't talk to protected
services. No firewall rules, no VPN, no shared passwords — just cryptographic
proof of identity.

---

## Lab 6: Watch Certificate Rotation

**Concept:** SPIRE automatically **rotates certificates** before they expire.
Services never have to restart — they get fresh certs transparently.

> All commands below must be run from the `docker-compose/` directory.

**Step 1** — Fetch the SVID and record the serial number + expiry:

```
docker compose exec frontend node spiffe-workload-api/fetch-svid.js /tmp
```

```
docker compose exec frontend openssl x509 -in /tmp/svid.0.pem -noout -serial -dates
```

Write down the `serial=` value and the `notAfter` time.

**Step 2** — Open a **second terminal**, `cd` into the `docker-compose/`
directory, and watch the agent logs:

```
cd docker-compose
docker compose logs -f spire-agent
```

Look for lines containing `svid`, `rotate`, or `renew` — these indicate
rotation events.

**Step 3** — Wait or force a rotation:

- **Option A — Wait:** SPIRE rotates at ~50% of the TTL (about 30 minutes
  with a 1-hour TTL). Leave the logs running and come back later.
- **Option B — Force it now:** Restart just the frontend so it re-fetches
  its SVID immediately:

```
docker compose restart frontend
```

Wait ~15 seconds for it to become healthy, then fetch again:

```
docker compose exec frontend node spiffe-workload-api/fetch-svid.js /tmp
```

```
docker compose exec frontend openssl x509 -in /tmp/svid.0.pem -noout -serial -dates
```

Compare the serial number — it changed. The SPIFFE ID is the same.

**Key takeaway:** No human intervention, no downtime, no secret distribution.
SPIRE handles the entire certificate lifecycle.

---

## Lab 7: Register a New Service

**Concept:** Before a workload can get an identity, an admin must create a
**registration entry** that maps a selector (how to identify the process) to a
SPIFFE ID.

List current entries — you'll see frontend and backend:

```
docker compose run --rm --entrypoint sh spire-bootstrap -c "/opt/spire/bin/spire-server entry show -socketPath /tmp/spire-server/private/api.sock"
```

Register a new "inventory" service. First, get the agent's SPIFFE ID:

```
docker compose run --rm --entrypoint sh spire-bootstrap -c "/opt/spire/bin/spire-server agent list -socketPath /tmp/spire-server/private/api.sock"
```

You'll see output like:
```
Found 1 attested agent(s)

SPIFFE ID         : spiffe://example.org/spire/agent/join_token/6eeefc10-3d13-43f3-8532-2039d3cb4d57
Attestation type  : join_token
Expiration time   : 2026-05-14 05:22:39 +0000 UTC
Serial number     : 215111834690286360396282484243455094291
Can re-attest     : false
```

Copy the SPIFFE ID value, then register the entry — replace
`<AGENT_SPIFFE_ID>` with the value you copied:

```
docker compose run --rm --entrypoint sh spire-bootstrap -c "/opt/spire/bin/spire-server entry create -socketPath /tmp/spire-server/private/api.sock -parentID <AGENT_SPIFFE_ID> -spiffeID spiffe://example.org/service/inventory -selector unix:uid:10003 -ttl 3600"
```

You'll see:
```
Entry ID         : 3f5e0145-1502-4794-8790-dc6ff638f446
SPIFFE ID        : spiffe://example.org/service/inventory
Parent ID        : spiffe://example.org/spire/agent/join_token/6eeefc10-3d13-43f3-8532-2039d3cb4d57
Revision         : 0
X509-SVID TTL    : 3600
JWT-SVID TTL     : default
Selector         : unix:uid:10003
```

Verify it was created:

```
docker compose run --rm --entrypoint sh spire-bootstrap -c "/opt/spire/bin/spire-server entry show -socketPath /tmp/spire-server/private/api.sock | grep -A5 inventory"
```

You'll see:
```
SPIFFE ID        : spiffe://example.org/service/inventory
Parent ID        : spiffe://example.org/spire/agent/join_token/6eeefc10-3d13-43f3-8532-2039d3cb4d57
Revision         : 0
X509-SVID TTL    : 3600
JWT-SVID TTL     : default
Selector         : unix:uid:10003
```

**What this teaches:**
- Registration entries are the **authorization policy** — they decide who gets which identity
- The `unix:uid` selector tells SPIRE: "any process running as UID 10003 gets this SPIFFE ID"
- In production, you'd use Kubernetes selectors (`k8s:pod-label:app=inventory`) instead

---

## Lab 8: Explore SPIRE Server State with OpenSSL

**Concept:** SPIRE Server is the brain — it holds the CA keys, the trust
bundle, registration entries, and attested agent records. Let's explore.

Show all registered workload entries:

```
docker compose run --rm --entrypoint sh spire-bootstrap -c "/opt/spire/bin/spire-server entry show -socketPath /tmp/spire-server/private/api.sock"
```

Show attested agents (nodes that joined the trust domain):

```
docker compose run --rm --entrypoint sh spire-bootstrap -c "/opt/spire/bin/spire-server agent list -socketPath /tmp/spire-server/private/api.sock"
```

Fetch the backend's SVID so we can compare both:

```
docker compose exec backend node spiffe-workload-api/fetch-svid.js /tmp
```

Compare the frontend's SVID:

```
docker compose exec frontend openssl x509 -in /tmp/svid.0.pem -noout -subject -issuer -serial -ext subjectAltName
```

Compare the backend's SVID:

```
docker compose exec backend openssl x509 -in /tmp/svid.0.pem -noout -subject -issuer -serial -ext subjectAltName
```

**What you'll see:**
- Same **Issuer** (SPIRE's CA) — both certs come from the same trust domain
- Same **Subject** (`O=SPIRE`) — SPIRE issues all SVIDs
- Different **Serial** numbers — each cert is unique
- Different **SAN URIs** — `service/frontend` vs `service/backend`

---

## Cleanup

Stop containers and delete volumes (CA keys, DB):

```
docker compose down -v
```

Stop containers but keep volumes (preserves CA state):

```
docker compose down
```

---

## Troubleshooting

### Services won't start

```
docker compose ps -a
```

```
docker compose logs spire-server
```

```
docker compose logs spire-agent
```

```
docker compose logs spire-bootstrap
```

### "PERMISSION_DENIED: no identity issued" from frontend/backend

The workload entries may not be registered yet (bootstrap takes a few seconds
after the agent is healthy). Wait ~10 seconds and check:

```
docker compose logs spire-bootstrap
```

Look for "Bootstrap Complete" — if missing, bootstrap may still be running.

### Frontend or backend keeps restarting

If you did a partial restart (`docker compose restart`), the agent gets a new
join token and old registration entries become stale. Always do a full restart:

```
docker compose down -v
```

```
docker compose up -d --build
```

### Frontend returns 502 (can't reach backend)

Check that backend is healthy and has its SVID:

```
docker compose logs backend
```

### "SSL routines: no certificate" when calling backend directly

This is expected! The backend enforces mTLS. You must go through the frontend
(which has a valid SVID), or present a valid SVID yourself. This is the point
of Lab 5.

### Port 3000 already in use

```
docker compose down -v
```

Then change the port mapping in `docker-compose.yml`: `"3001:3000"`

---

## Next: [Track B — kind/Kubernetes](../kind/README.md)
