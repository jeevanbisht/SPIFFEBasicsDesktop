# Track A — Docker Compose

> **No Kubernetes. No cloud. Just Docker Desktop.**
> Everything runs on your laptop in under 2 minutes.

---

## ⚡ Start

```bash
cd docker-compose/

# Build images and start all services
docker compose up -d --build

# Watch everything come up (~60 seconds)
docker compose logs -f

# Once you see "Bootstrap Complete", you're ready:
curl http://localhost:3000/demo
```

---

## What's Running

```
docker compose ps

NAME              STATUS
spire-server      healthy   ← CA + registry for the trust domain
spire-agent       healthy   ← Issues SVIDs to workloads on this "node"
spire-bootstrap   exited 0  ← Created registration entries, done its job
frontend          healthy   ← Has SPIFFE ID, calls backend over mTLS
backend           healthy   ← Has SPIFFE ID, enforces mTLS + SPIFFE auth
```

---

## Lab 1: See Your First SVID

```bash
# Ask the frontend what its cryptographic identity is
curl -s http://localhost:3000/my-identity | python3 -m json.tool
```

Expected output:
```json
{
  "spiffeId": "spiffe://example.org/service/frontend",
  "expiresAt": "2024-01-15T11:00:00.000Z",
  "trustDomain": "example.org",
  "message": "👆 My cryptographic identity — no passwords needed!"
}
```

The frontend has a real X.509 certificate with SPIFFE ID in its SAN field — issued by SPIRE, valid for 1 hour, auto-rotating.

---

## Lab 2: Call the Backend Over mTLS

```bash
# Frontend calls backend — both sides present SPIFFE SVIDs
curl -s http://localhost:3000/orders | python3 -m json.tool
```

Expected output:
```json
{
  "calledBy": "spiffe://example.org/service/frontend",
  "servedBy": "spiffe://example.org/service/backend",
  "orders": [...],
  "note": "🔒 This response was served over mTLS — both sides presented SPIFFE SVIDs"
}
```

Both `calledBy` and `servedBy` are SPIFFE IDs — **zero passwords, zero API keys.**

---

## Lab 3: Inspect the Actual Certificate

```bash
# Exec into the frontend container
docker compose exec frontend sh

# Fetch and write the X.509-SVID to a file
/opt/spire/bin/spire-agent api fetch x509 \
  -socketPath /run/spire/sockets/agent.sock \
  -write /tmp/ 2>/dev/null

# Inspect the certificate
openssl x509 -in /tmp/svid.0.pem -text -noout | grep -A3 "Subject Alternative Name"
```

Expected:
```
X509v3 Subject Alternative Name:
    URI:spiffe://example.org/service/frontend   ← The SPIFFE ID!
```

```bash
# Check the 1-hour validity window
openssl x509 -in /tmp/svid.0.pem -text -noout | grep -E "Not Before|Not After"

# Verify it chains to SPIRE's CA (trust bundle)
openssl verify -CAfile /tmp/bundle.0.pem /tmp/svid.0.pem
# Expected: /tmp/svid.0.pem: OK
```

---

## Lab 4: Decode a JWT-SVID

```bash
# Still inside the frontend container — fetch a JWT-SVID
JWT=$(/opt/spire/bin/spire-agent api fetch jwt \
  -socketPath /run/spire/sockets/agent.sock \
  -audience "backend-service" \
  -format json 2>/dev/null | python3 -c "
import json,sys
data=json.load(sys.stdin)
print(data['svids'][0]['svid'])
")

echo "Raw JWT (3 parts separated by dots):"
echo $JWT

# Decode the payload (middle section)
echo ""
echo "Decoded payload:"
echo $JWT | cut -d'.' -f2 | python3 -c "
import sys,base64,json
data = sys.stdin.read().strip()
# Add padding
data += '=' * (4 - len(data) % 4)
decoded = base64.urlsafe_b64decode(data)
print(json.dumps(json.loads(decoded), indent=2))
"
```

Expected output:
```json
{
  "sub": "spiffe://example.org/service/frontend",
  "aud": ["backend-service"],
  "exp": 1705316400,
  "iat": 1705316100,
  "iss": "https://..."
}
```

Note the 5-minute expiry — JWT-SVIDs are much shorter-lived than X.509-SVIDs.

---

## Lab 5: Break It — What Happens Without a Valid SVID?

Try to call the backend directly (bypassing frontend's mTLS):

```bash
# Try to call backend HTTPS directly with no cert — should fail
curl -k https://localhost:8443/orders
# Error: SSL routines: no certificate

# Try with a self-signed cert — should also fail
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
  -keyout /tmp/fake.key -out /tmp/fake.pem \
  -days 1 -nodes -subj "/CN=fake-service"

curl -k --cert /tmp/fake.pem --key /tmp/fake.key https://localhost:8443/orders
# Error: 401 — No SPIFFE ID in client certificate
```

The backend **enforces mTLS and validates the SPIFFE ID** — any connection without a valid SVID is rejected.

---

## Lab 6: Watch SVID Rotation

```bash
# Open two terminals

# Terminal 1 — watch the frontend's SVID expiry
docker compose exec frontend sh -c '
while true; do
  /opt/spire/bin/spire-agent api fetch x509 \
    -socketPath /run/spire/sockets/agent.sock 2>&1 | grep -E "SPIFFE|Valid Until"
  sleep 10
done'

# Terminal 2 — watch SPIRE Agent logs for rotation events
docker compose logs -f spire-agent | grep -i "svid\|rotat\|renew"
```

At 30 minutes, you'll see the agent proactively fetch a new SVID (50% of 1-hour TTL). The certificate fingerprint changes, but the SPIFFE ID stays the same.

---

## Lab 7: Add a New Service

Register a third service (`inventory`) and see it get an SVID:

```bash
# Get the agent's SPIFFE ID
AGENT_PATH=$(docker compose exec spire-server \
  /opt/spire/bin/spire-server agent list -format json \
  2>/dev/null | python3 -c "
import json,sys
agents=json.load(sys.stdin)
print(agents[0]['id']['path'])")

# Create a registration entry for inventory
docker compose exec spire-server \
  /opt/spire/bin/spire-server entry create \
    -parentID "spiffe://example.org${AGENT_PATH}" \
    -spiffeID "spiffe://example.org/service/inventory" \
    -selector "docker:label:spiffe.io/service:inventory" \
    -ttl 3600

# Verify it was created
docker compose exec spire-server \
  /opt/spire/bin/spire-server entry show | grep inventory
```

---

## Lab 8: Explore SPIRE Server State

```bash
# Trust bundle — the CA certificate for the trust domain
docker compose exec spire-server \
  /opt/spire/bin/spire-server bundle show

# All registered workload entries
docker compose exec spire-server \
  /opt/spire/bin/spire-server entry show

# Attested nodes (the agent)
docker compose exec spire-server \
  /opt/spire/bin/spire-server agent list
```

---

## Cleanup

```bash
docker compose down -v   # Stop containers and delete volumes (CA keys, DB)
docker compose down      # Stop containers, keep volumes (preserves CA state)
```

---

## ▶️ Next: [Track B — kind/Kubernetes](../kind/README.md)
