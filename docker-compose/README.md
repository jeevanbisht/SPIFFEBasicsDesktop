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
docker compose ps -a

NAME              STATUS
spire-server      healthy   ← CA + registry for the trust domain
spire-init        exited 0  ← Generated join token for the agent, done
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

The app containers don't have `spire-agent` CLI, so we use Node.js to fetch
the SVID via the Workload API and write PEM files that `openssl` can read.

```bash
# Step 1 — Install openssl in the frontend container (temporary, lost on restart)
docker exec -u root docker-compose-frontend-1 apk add --no-cache openssl

# Step 2 — Fetch the SVID and write PEM files to /tmp/
docker compose exec frontend node -e "
const grpc=require('@grpc/grpc-js'), pl=require('@grpc/proto-loader'), fs=require('fs');
const p=pl.loadSync('/app/spiffe-workload-api/proto/workload.proto',
  {keepCase:false,longs:String,enums:String,defaults:true,oneofs:true});
const d=grpc.loadPackageDefinition(p);
const c=new d.SpiffeWorkloadAPI('unix:///run/spire/sockets/agent.sock',grpc.credentials.createInsecure());
const m=new grpc.Metadata(); m.set('workload.spiffe.io','true');
function derToPem(buf,t){const b=Buffer.from(buf).toString('base64');
  return '-----BEGIN '+t+'-----\n'+b.match(/.{1,64}/g).join('\n')+'\n-----END '+t+'-----\n'}
function splitDer(buf){const c=[];let o=0;while(o<buf.length){if(buf[o]!==0x30)break;
  let lo=o+1,l;if(buf[lo]<128){l=buf[lo];lo++}else{const n=buf[lo]&127;l=0;
  for(let i=0;i<n;i++)l=(l<<8)|buf[lo+1+i];lo+=1+n}c.push(buf.slice(o,o+(lo-o+l)));
  o+=lo-o+l}return c}
const s=c.fetchX509Svid({},m);
s.on('data',r=>{const v=r.svids[0];
  splitDer(Buffer.from(v.x509Svid)).forEach((d,i)=>fs.writeFileSync('/tmp/svid.'+i+'.pem',derToPem(d,'CERTIFICATE')));
  fs.writeFileSync('/tmp/svid.key.pem',derToPem(Buffer.from(v.x509SvidKey),'PRIVATE KEY'));
  splitDer(Buffer.from(v.bundle)).forEach((d,i)=>fs.writeFileSync('/tmp/bundle.'+i+'.pem',derToPem(d,'CERTIFICATE')));
  console.log('Wrote certs to /tmp/'); process.exit(0)});
s.on('error',e=>{console.error(e.message);process.exit(1)});
setTimeout(()=>process.exit(1),5000);
"

# Step 3 — Inspect the certificate
docker compose exec frontend openssl x509 -in /tmp/svid.0.pem -text -noout \
  | grep -A3 "Subject Alternative Name"
```

Expected:
```
X509v3 Subject Alternative Name:
    URI:spiffe://example.org/service/frontend   ← The SPIFFE ID!
```

```bash
# Check the 1-hour validity window
docker compose exec frontend openssl x509 -in /tmp/svid.0.pem -text -noout \
  | grep -E "Not Before|Not After"

# Verify it chains to SPIRE's CA (trust bundle)
docker compose exec frontend openssl verify -CAfile /tmp/bundle.0.pem /tmp/svid.0.pem
# Expected: /tmp/svid.0.pem: OK
```

---

## Lab 4: Decode a JWT-SVID

The SPIRE Workload API also issues JWT-SVIDs. We fetch one using gRPC from Node.js:

```bash
docker compose exec frontend node -e "
const grpc=require('@grpc/grpc-js'), pl=require('@grpc/proto-loader');
// The JWT-SVID API uses FetchJWTSVID — but in this demo the agent only
// exposes X.509-SVIDs via the streaming API. Instead, let's inspect the
// X.509 SVID's SPIFFE claims which serve the same purpose:
const crypto=require('crypto'), fs=require('fs');
try {
  const pem = fs.readFileSync('/tmp/svid.0.pem','utf8');
  const cert = new crypto.X509Certificate(pem);
  console.log(JSON.stringify({
    spiffeId: cert.subjectAltName,
    subject: cert.subject,
    issuer: cert.issuer,
    validFrom: cert.validFrom,
    validTo: cert.validTo,
    keyUsage: cert.keyUsage,
    serialNumber: cert.serialNumber,
    note: 'X.509-SVID — identity encoded in SAN URI, auto-rotated by SPIRE'
  }, null, 2));
} catch(e) { console.error('Run Lab 3 first to write cert files'); }
"
```

> **Note:** JWT-SVIDs require the `FetchJWTSVID` RPC which uses a different
> proto definition. For this desktop demo, X.509-SVIDs are the primary
> identity mechanism — they enable mTLS between frontend and backend.

---

## Lab 5: Break It — What Happens Without a Valid SVID?

The backend enforces mTLS — **every caller must present a valid SPIFFE SVID**.

```bash
# Try calling backend's health endpoint (plain HTTP, no mTLS) — works
docker compose exec backend sh -c \
  "wget -qO- http://localhost:8444/health"
# {"status":"ok"}

# Try calling backend's protected mTLS endpoint without a cert — fails
# (from the host, the mTLS port isn't exposed, so we test from inside the network)
docker compose exec frontend sh -c \
  "wget -qO- --no-check-certificate https://backend:8443/orders 2>&1 || echo 'REJECTED — no client certificate!'"

# The call fails because wget doesn't present a SPIFFE SVID.
# Only workloads with a valid SVID issued by SPIRE can connect.
```

This is the zero-trust model: **no valid SVID = no access.** No passwords, API keys, or IP allowlists.

---

## Lab 6: Watch SVID Rotation

```bash
# Terminal 1 — watch the frontend's SVID identity and expiry (refreshes every 10s)
docker compose exec frontend node -e "
const grpc=require('@grpc/grpc-js'), pl=require('@grpc/proto-loader'), crypto=require('crypto');
const p=pl.loadSync('/app/spiffe-workload-api/proto/workload.proto',
  {keepCase:false,longs:String,enums:String,defaults:true,oneofs:true});
const d=grpc.loadPackageDefinition(p);
const c=new d.SpiffeWorkloadAPI('unix:///run/spire/sockets/agent.sock',grpc.credentials.createInsecure());
const m=new grpc.Metadata(); m.set('workload.spiffe.io','true');
const s=c.fetchX509Svid({},m);
s.on('data',r=>{
  const v=r.svids[0];
  function splitDer(buf){const c=[];let o=0;while(o<buf.length){if(buf[o]!==0x30)break;
    let lo=o+1,l;if(buf[lo]<128){l=buf[lo];lo++}else{const n=buf[lo]&127;l=0;
    for(let i=0;i<n;i++)l=(l<<8)|buf[lo+1+i];lo+=1+n}c.push(buf.slice(o,o+(lo-o+l)));
    o+=lo-o+l}return c}
  const der=splitDer(Buffer.from(v.x509Svid))[0];
  const b=Buffer.from(der).toString('base64');
  const pem='-----BEGIN CERTIFICATE-----\n'+b.match(/.{1,64}/g).join('\n')+'\n-----END CERTIFICATE-----';
  const cert=new crypto.X509Certificate(pem);
  console.log(new Date().toISOString(),
    'SPIFFE ID:', v.spiffeId,
    '| Valid:', cert.validFrom, '->', cert.validTo,
    '| Serial:', cert.serialNumber);
});
"

# Terminal 2 — watch SPIRE Agent logs for rotation events
docker compose logs -f spire-agent | grep -i "svid\|rotat\|renew"
```

At ~30 minutes (50% of the 1-hour TTL), the agent proactively fetches a new SVID.
The serial number changes but the SPIFFE ID stays the same — seamless rotation.

---

## Lab 7: Add a New Service

Register a third service (`inventory`) and see it get an SVID.

The SPIRE Server image is minimal (no shell), so we run `spire-server` CLI
commands via the bootstrap container which has the binary and access to the
server's API socket.

```bash
# Create a registration entry for inventory (using unix:uid selector)
docker compose run --rm spire-bootstrap sh -c '
  /opt/spire/bin/spire-server entry create \
    -socketPath /tmp/spire-server/private/api.sock \
    -parentID "spiffe://example.org/spire/agent/join_token/$(
      /opt/spire/bin/spire-server agent list \
        -socketPath /tmp/spire-server/private/api.sock 2>/dev/null \
        | grep "SPIFFE ID" | head -1 | sed "s|.*join_token/||"
    )" \
    -spiffeID "spiffe://example.org/service/inventory" \
    -selector "unix:uid:10003" \
    -ttl 3600
'

# Verify it was created
docker compose run --rm spire-bootstrap sh -c '
  /opt/spire/bin/spire-server entry show \
    -socketPath /tmp/spire-server/private/api.sock \
    | grep -A5 inventory
'
```

---

## Lab 8: Explore SPIRE Server State

All `spire-server` CLI commands run via the bootstrap container (which has
the binary and the server API socket mounted).

```bash
# Trust bundle — the CA certificate for the trust domain
docker compose run --rm spire-bootstrap sh -c '
  /opt/spire/bin/spire-server bundle show \
    -socketPath /tmp/spire-server/private/api.sock'

# All registered workload entries
docker compose run --rm spire-bootstrap sh -c '
  /opt/spire/bin/spire-server entry show \
    -socketPath /tmp/spire-server/private/api.sock'

# Attested nodes (the agent)
docker compose run --rm spire-bootstrap sh -c '
  /opt/spire/bin/spire-server agent list \
    -socketPath /tmp/spire-server/private/api.sock'
```

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
docker compose logs backend | grep -E "SVID|mTLS|error"
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
