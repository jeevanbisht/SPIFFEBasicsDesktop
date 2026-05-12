// frontend/src/index.js — SPIFFE mTLS demo frontend
// Fetches an X.509-SVID from SPIRE Agent and uses it for mTLS calls to backend
'use strict';

const express = require('express');
const https   = require('https');
const fetch   = require('node-fetch');
const { X509Source } = require('@spiffe/spiffe-workload-api');

const app          = express();
const BACKEND_URL  = process.env.BACKEND_URL  || 'https://backend:8443';
const TRUST_DOMAIN = process.env.TRUST_DOMAIN || 'example.org';
const SOCKET_PATH  = process.env.SPIFFE_ENDPOINT_SOCKET || 'unix:///run/spire/sockets/agent.sock';
const PORT         = parseInt(process.env.PORT || '3000');

let source = null;  // X509Source — auto-updates when SVID rotates

// ─── Connect to SPIRE Agent ───────────────────────────────────────────────
async function connect() {
  console.log(`[frontend] Connecting to SPIRE Agent: ${SOCKET_PATH}`);

  // X509Source automatically watches for rotation and keeps SVIDs fresh
  source = await X509Source.create({ socketPath: SOCKET_PATH });

  const id = source.svids[0]?.id;
  const exp = source.svids[0]?.expiresAt;
  console.log(`[frontend] ✅ Got SVID: ${id}`);
  console.log(`[frontend]    Expires : ${exp}`);

  source.on('update', (upd) => {
    console.log(`[frontend] 🔄 SVID rotated — new expiry: ${upd.svids[0]?.expiresAt}`);
  });
}

// ─── Build mTLS HTTPS agent ───────────────────────────────────────────────
function mtlsAgent(expectedBackendId) {
  const svid   = source.svids[0];
  const bundle = source.bundles.get(TRUST_DOMAIN);

  return new https.Agent({
    // Present our certificate to the backend
    cert: svid.certificates.map(c => c.export()).join('\n'),
    key:  svid.privateKey.export({ type: 'pkcs8', format: 'pem' }),

    // Verify backend's certificate against the SPIRE trust bundle
    ca: bundle.x509Authorities.map(a => a.export()).join('\n'),

    // Custom peer verification — check SPIFFE ID, not hostname
    checkServerIdentity: (_host, cert) => {
      const san  = cert.subjectaltname || '';
      const match = san.match(/URI:spiffe:\/\/[^,]+/);
      if (!match) return new Error('Peer has no SPIFFE ID SAN');
      const peerId = match[0].replace('URI:', '');
      if (peerId !== expectedBackendId) {
        return new Error(`Wrong SPIFFE ID: got "${peerId}", expected "${expectedBackendId}"`);
      }
      console.log(`[frontend] ✅ Peer verified: ${peerId}`);
    }
  });
}

// ─── Routes ───────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.get('/my-identity', (_req, res) => {
  if (!source) return res.status(503).json({ error: 'SPIRE not ready' });
  const svid = source.svids[0];
  res.json({
    spiffeId:  svid?.id,
    expiresAt: svid?.expiresAt,
    trustDomain: TRUST_DOMAIN,
    message: '👆 My cryptographic identity — no passwords needed!'
  });
});

app.get('/orders', async (_req, res) => {
  if (!source) return res.status(503).json({ error: 'SPIRE not ready' });

  const backendSpiffeId = `spiffe://${TRUST_DOMAIN}/service/backend`;
  try {
    const agent    = mtlsAgent(backendSpiffeId);
    const response = await fetch(`${BACKEND_URL}/orders`, { agent });
    if (!response.ok) throw new Error(`Backend HTTP ${response.status}`);
    const data = await response.json();
    res.json({
      calledBy: source.svids[0]?.id,
      servedBy: data.mySpiffeId,
      orders:   data.orders,
      note: '🔒 This response was served over mTLS — both sides presented SPIFFE SVIDs'
    });
  } catch (err) {
    console.error('[frontend] Error calling backend:', err.message);
    res.status(502).json({ error: err.message });
  }
});

app.get('/demo', async (_req, res) => {
  // Full demo: show identity, then call backend
  if (!source) return res.status(503).json({ error: 'SPIRE not ready' });
  const svid = source.svids[0];
  const backendSpiffeId = `spiffe://${TRUST_DOMAIN}/service/backend`;
  let backendData = null;
  try {
    const agent    = mtlsAgent(backendSpiffeId);
    const response = await fetch(`${BACKEND_URL}/whoami`, { agent });
    backendData    = await response.json();
  } catch (e) {
    backendData = { error: e.message };
  }
  res.json({
    'my-identity': {
      spiffeId:  svid?.id,
      expiresAt: svid?.expiresAt,
    },
    'backend-identity': backendData,
    'connection-type': 'Mutual TLS (mTLS) — both sides presented SPIFFE X.509-SVIDs',
    'no-secrets-used': true
  });
});

// ─── Start ─────────────────────────────────────────────────────────────────
connect().then(() => {
  app.listen(PORT, () => console.log(`[frontend] 🚀 Listening on http://localhost:${PORT}`));
}).catch(err => {
  console.error('[frontend] Failed to start:', err.message);
  // Retry after 5s if SPIRE Agent isn't ready yet
  setTimeout(() => { connect().catch(console.error); }, 5000);
});
