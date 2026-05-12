// backend/src/index.js — SPIFFE mTLS demo backend
// Serves HTTPS with mTLS, verifies client SPIFFE ID on each request
'use strict';

const express = require('express');
const https   = require('https');
const { X509Source } = require('@spiffe/spiffe-workload-api');

const app          = express();
const TRUST_DOMAIN = process.env.TRUST_DOMAIN || 'example.org';
const SOCKET_PATH  = process.env.SPIFFE_ENDPOINT_SOCKET || 'unix:///run/spire/sockets/agent.sock';
const HTTPS_PORT   = parseInt(process.env.HTTPS_PORT || '8443');
const HTTP_PORT    = parseInt(process.env.HTTP_PORT  || '8444');  // health only

// Allowed callers — only the frontend can access our protected routes
const ALLOWED_IDS  = [`spiffe://${TRUST_DOMAIN}/service/frontend`];

let source = null;
let httpsServer = null;

// ─── Connect to SPIRE Agent ───────────────────────────────────────────────
async function connect() {
  console.log(`[backend] Connecting to SPIRE Agent: ${SOCKET_PATH}`);
  source = await X509Source.create({ socketPath: SOCKET_PATH });

  const id = source.svids[0]?.id;
  console.log(`[backend] ✅ Got SVID: ${id}`);

  source.on('update', (upd) => {
    console.log(`[backend] 🔄 SVID rotated, restarting TLS server...`);
    restartHttps();
  });
}

// ─── Middleware: require valid SPIFFE client cert ─────────────────────────
function requireSpiffe(allowedIds) {
  return (req, res, next) => {
    const cert = req.socket.getPeerCertificate(true);
    if (!cert || !Object.keys(cert).length) {
      return res.status(401).json({
        error: 'Client certificate required',
        hint: 'Only workloads with a SPIFFE SVID can call this endpoint'
      });
    }

    const san   = cert.subjectaltname || '';
    const match = san.match(/URI:spiffe:\/\/[^,]+/);
    if (!match) {
      return res.status(401).json({ error: 'No SPIFFE ID in client certificate' });
    }

    const clientId = match[0].replace('URI:', '');
    req.clientSpiffeId = clientId;

    if (allowedIds.length && !allowedIds.includes(clientId)) {
      console.warn(`[backend] ❌ Rejected: ${clientId}`);
      return res.status(403).json({
        error: 'Forbidden',
        clientSpiffeId: clientId,
        allowedIds
      });
    }

    console.log(`[backend] ✅ Authenticated: ${clientId}`);
    next();
  };
}

// ─── Routes ───────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.get('/whoami', requireSpiffe(ALLOWED_IDS), (req, res) => {
  res.json({
    mySpiffeId:     source.svids[0]?.id,
    clientSpiffeId: req.clientSpiffeId,
    message: 'Both of us are identified by SPIFFE — no passwords exchanged!'
  });
});

app.get('/orders', requireSpiffe(ALLOWED_IDS), (req, res) => {
  console.log(`[backend] Orders requested by: ${req.clientSpiffeId}`);
  res.json({
    mySpiffeId: source.svids[0]?.id,
    orders: [
      { id: 'ORD-001', item: 'Widget A', qty: 5,  status: 'shipped'    },
      { id: 'ORD-002', item: 'Gadget B', qty: 2,  status: 'pending'    },
      { id: 'ORD-003', item: 'Doohickey',qty: 12, status: 'processing' }
    ]
  });
});

// ─── HTTPS / mTLS Server ─────────────────────────────────────────────────
function startHttps() {
  const svid   = source.svids[0];
  const bundle = source.bundles.get(TRUST_DOMAIN);

  const tlsOpts = {
    cert: svid.certificates.map(c => c.export()).join('\n'),
    key:  svid.privateKey.export({ type: 'pkcs8', format: 'pem' }),
    ca:   bundle.x509Authorities.map(a => a.export()).join('\n'),
    requestCert:        true,   // Ask for client cert
    rejectUnauthorized: true    // Reject if no valid client cert (enforce mTLS)
  };

  httpsServer = https.createServer(tlsOpts, app);
  httpsServer.listen(HTTPS_PORT, () => {
    console.log(`[backend] 🔒 mTLS server on port ${HTTPS_PORT}`);
    console.log(`[backend]    My SPIFFE ID: ${svid?.id}`);
  });
}

function restartHttps() {
  if (httpsServer) {
    httpsServer.close(() => startHttps());
  }
}

// Plain HTTP health-check endpoint (no mTLS — for docker healthcheck)
const healthApp = express();
healthApp.get('/health', (_req, res) => res.json({ status: 'ok' }));
healthApp.listen(HTTP_PORT, () => console.log(`[backend] Health check on port ${HTTP_PORT}`));

// ─── Start ─────────────────────────────────────────────────────────────────
connect()
  .then(startHttps)
  .catch(err => {
    console.error('[backend] Failed to start:', err.message);
    setTimeout(() => connect().then(startHttps).catch(console.error), 5000);
  });
