# SPIFFE/SPIRE Hands-On Lab — Docker Compose

> **Learn SPIFFE identity and mTLS by doing.**
> No Kubernetes. No cloud. Just Docker Desktop on your laptop.

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

> **Windows users:** The commands below use bash syntax. On Windows CMD or
> PowerShell, remove `#` comment lines, join `\` continuation lines into a
> single line, and remove the `\`. For example:
> ```bash
> # bash (Mac/Linux):
> docker compose exec frontend sh -c \
>   'openssl x509 -in /tmp/svid.0.pem -text -noout | grep -A1 "Subject Alternative Name"'
>
> # Windows CMD or PowerShell (single line, no backslash):
> docker compose exec frontend sh -c "openssl x509 -in /tmp/svid.0.pem -text -noout | grep -A1 'Subject Alternative Name'"
> ```

---

## Quick Start

```bash
cd docker-compose/

# Start everything (first run downloads images, ~2 minutes)
docker compose up -d --build

# Wait for all services to become healthy (~60 seconds)
# Check with:
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

```bash
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

```bash
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

Try the full demo endpoint to see both identities side by side:
```bash
curl -s http://localhost:3000/demo
```

---

## Lab 3: Inspect the Certificate with OpenSSL

**Concept:** A SPIFFE SVID is a standard X.509 certificate. The SPIFFE ID
lives in the **Subject Alternative Name (SAN)** URI field. Let's examine it
with `openssl` — the same tool you'd use for any TLS certificate.

```bash
# Step 1 — Fetch the SVID from the SPIRE Agent and write PEM files
docker compose exec frontend node spiffe-workload-api/fetch-svid.js /tmp
```

Output:
```
SPIFFE ID : spiffe://example.org/service/frontend
Certificate: /tmp/svid.0.pem
Private key: /tmp/svid.key.pem
CA bundle  : /tmp/bundle.0.pem
```

```bash
# Step 2 — Find the SPIFFE ID in the certificate's SAN field
docker compose exec frontend sh -c \
  'openssl x509 -in /tmp/svid.0.pem -text -noout | grep -A1 "Subject Alternative Name"'
```

Expected:
```
X509v3 Subject Alternative Name:
    URI:spiffe://example.org/service/frontend   ← The SPIFFE ID!
```

```bash
# Step 3 — Check the validity window (1-hour TTL)
docker compose exec frontend sh -c \
  'openssl x509 -in /tmp/svid.0.pem -text -noout | grep -E "Not Before|Not After"'
```

```bash
# Step 4 — See all certificate details
docker compose exec frontend \
  openssl x509 -in /tmp/svid.0.pem -text -noout
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

```bash
# Verify the frontend's SVID was signed by SPIRE's CA
docker compose exec frontend \
  openssl verify -CAfile /tmp/bundle.0.pem /tmp/svid.0.pem
```

Expected:
```
/tmp/svid.0.pem: OK
```

```bash
# Inspect the CA certificate itself
docker compose exec frontend sh -c \
  'openssl x509 -in /tmp/bundle.0.pem -text -noout | grep -E "Subject:|Issuer:|CA:"'
```

**What this proves:**
- SPIRE signed the frontend's certificate with its CA key
- Any service that has the trust bundle can verify the frontend's identity
- **No shared secrets** — trust is established through the certificate chain, not passwords

> **Run Lab 3 first** — it writes the PEM files that this lab uses.

---

## Lab 5: Zero Trust — What Happens Without a Valid Identity?

**Concept:** In a zero-trust architecture, **every connection must be
authenticated**. No valid SVID = no access. Let's prove it.

```bash
# The backend's health endpoint works (plain HTTP, no mTLS required)
docker compose exec backend wget -qO- http://localhost:8444/health
# → {"status":"ok"}

# But the protected /orders endpoint requires mTLS with a valid SPIFFE SVID.
# Try calling it without presenting any certificate:
docker compose exec frontend sh -c \
  'wget --timeout=3 -qO- --no-check-certificate https://backend:8443/orders 2>&1; echo "Exit: $?"'
```

The call is **rejected**. The backend requires a client certificate issued by
SPIRE's CA with a valid SPIFFE ID.

```bash
# Try with openssl s_client — connect but don't present a client cert:
docker compose exec frontend sh -c \
  'echo | openssl s_client -connect backend:8443 2>&1 | grep -E "alert|error|Verify"'
# The TLS handshake fails — the server demands a client certificate

# Now try via the frontend (which has a valid SVID) — it works:
curl -s http://localhost:3000/orders | head -1
```

**The lesson:** Without a SPIFFE identity, you can't talk to protected
services. No firewall rules, no VPN, no shared passwords — just cryptographic
proof of identity.

---

## Lab 6: Watch Certificate Rotation

**Concept:** SPIRE automatically **rotates certificates** before they expire.
Services never have to restart — they get fresh certs transparently.

```bash
# Fetch the SVID and note the serial number + expiry
docker compose exec frontend node spiffe-workload-api/fetch-svid.js /tmp
docker compose exec frontend \
  openssl x509 -in /tmp/svid.0.pem -noout -serial -dates
```

Note the serial number and `notAfter` time.

```bash
# In a second terminal, watch the agent logs for rotation events:
# On Linux/Mac:
docker compose logs -f spire-agent 2>&1 | grep -i "svid\|rotat\|renew"
# On Windows (PowerShell):
docker compose logs -f spire-agent 2>&1 | Select-String -Pattern "svid|rotat|renew"
```

After ~30 minutes (50% of the 1-hour TTL), SPIRE proactively rotates the cert.
Re-run the fetch command — the serial number changes, but the SPIFFE ID stays
the same.

```bash
# After rotation, fetch again:
docker compose exec frontend node spiffe-workload-api/fetch-svid.js /tmp
docker compose exec frontend \
  openssl x509 -in /tmp/svid.0.pem -noout -serial -dates
# Serial number changed, SPIFFE ID unchanged — seamless rotation!
```

**Key takeaway:** No human intervention, no downtime, no secret distribution.
SPIRE handles the entire lifecycle.

---

## Lab 7: Register a New Service

**Concept:** Before a workload can get an identity, an admin must create a
**registration entry** that maps a selector (how to identify the process) to a
SPIFFE ID.

```bash
# List current entries — you'll see frontend and backend
docker compose run --rm spire-bootstrap sh -c \
  '/opt/spire/bin/spire-server entry show \
    -socketPath /tmp/spire-server/private/api.sock'

# Register a new "inventory" service
docker compose run --rm spire-bootstrap sh -c '
  AGENT_ID=$(/opt/spire/bin/spire-server agent list \
    -socketPath /tmp/spire-server/private/api.sock 2>/dev/null \
    | grep "SPIFFE ID" | head -1 | awk "{print \$NF}")
  /opt/spire/bin/spire-server entry create \
    -socketPath /tmp/spire-server/private/api.sock \
    -parentID "$AGENT_ID" \
    -spiffeID "spiffe://example.org/service/inventory" \
    -selector "unix:uid:10003" \
    -ttl 3600'

# Verify it was created
docker compose run --rm spire-bootstrap sh -c \
  '/opt/spire/bin/spire-server entry show \
    -socketPath /tmp/spire-server/private/api.sock | grep -A5 inventory'
```

**What this teaches:**
- Registration entries are the **authorization policy** — they decide who gets which identity
- The `unix:uid` selector tells SPIRE: "any process running as UID 10003 gets this SPIFFE ID"
- In production, you'd use Kubernetes selectors (`k8s:pod-label:app=inventory`) instead

---

## Lab 8: Explore SPIRE Server State with OpenSSL

**Concept:** SPIRE Server is the brain — it holds the CA keys, the trust
bundle, registration entries, and attested agent records. Let's explore.

```bash
# 1. Show all registered workload entries (who can get which identity)
docker compose run --rm spire-bootstrap sh -c \
  '/opt/spire/bin/spire-server entry show \
    -socketPath /tmp/spire-server/private/api.sock'

# 2. Show attested agents (nodes that have joined the trust domain)
docker compose run --rm spire-bootstrap sh -c \
  '/opt/spire/bin/spire-server agent list \
    -socketPath /tmp/spire-server/private/api.sock'

# 3. Export the trust bundle (CA certificate) as PEM
docker compose run --rm spire-bootstrap sh -c \
  '/opt/spire/bin/spire-server bundle show \
    -socketPath /tmp/spire-server/private/api.sock \
    -format spiffe' > /tmp/trust-bundle.json 2>/dev/null
```

Now compare the frontend's SVID against the backend's — they're both issued by
the same CA but have different SPIFFE IDs:

```bash
# Fetch the backend's SVID too
docker compose exec backend node spiffe-workload-api/fetch-svid.js /tmp

# Compare the two SVIDs side by side
echo "=== Frontend ==="
docker compose exec frontend \
  openssl x509 -in /tmp/svid.0.pem -noout -subject -issuer -serial \
    -ext subjectAltName

echo ""
echo "=== Backend ==="
docker compose exec backend \
  openssl x509 -in /tmp/svid.0.pem -noout -subject -issuer -serial \
    -ext subjectAltName
```

**What you'll see:**
- Same **Issuer** (SPIRE's CA) — both certs come from the same trust domain
- Same **Subject** (`O=SPIRE`) — SPIRE issues all SVIDs
- Different **Serial** numbers — each cert is unique
- Different **SAN URIs** — `service/frontend` vs `service/backend`

---

## Cleanup

```bash
docker compose down -v   # Stop containers and delete volumes (CA keys, DB)
docker compose down      # Stop containers, keep volumes (preserves CA state)
```

---

## 🔧 Troubleshooting

### Services won't start
```bash
# Check all container states
docker compose ps -a

# View specific service logs
docker compose logs spire-server
docker compose logs spire-agent
docker compose logs spire-bootstrap
docker compose logs spire-init
```

### "PERMISSION_DENIED: no identity issued" from frontend/backend
The workload entries may not be registered yet (bootstrap takes a few seconds
after the agent is healthy). Wait ~10 seconds and check:
```bash
docker compose logs spire-bootstrap
# Look for "Bootstrap Complete" — if missing, bootstrap may still be running
```

### Frontend or backend keeps restarting
If you did a partial restart (`docker compose restart`), the agent gets a new
join token and old registration entries become stale. Always do a full restart:
```bash
docker compose down -v
docker compose up -d --build
```

### Frontend returns 502 (can't reach backend)
Check that backend is healthy and has its SVID:
```bash
# On Linux/Mac:
docker compose logs backend | grep -E "SVID|mTLS|error"
# On Windows (PowerShell):
docker compose logs backend 2>&1 | Select-String -Pattern "SVID|mTLS|error"
```

### "SSL routines: no certificate" when calling backend directly
This is expected! The backend enforces mTLS. You must go through the frontend (which has a valid SVID), or present a valid SVID yourself. This is the point of Lab 5.

### Port 3000 already in use
```bash
docker compose down -v   # Stop and remove volumes
# Then change the port mapping in docker-compose.yml: "3001:3000"
```

### Docker socket permission denied (on Linux)
```bash
sudo usermod -aG docker $USER
# Log out and back in, then retry
```

---

## ▶️ Next: [Track B — kind/Kubernetes](../kind/README.md)
