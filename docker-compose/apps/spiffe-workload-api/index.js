// @spiffe/spiffe-workload-api — Node.js SPIFFE Workload API client
// Connects to a SPIRE Agent over gRPC and streams X.509-SVIDs.
'use strict';

const grpc = require('@grpc/grpc-js');
const protoLoader = require('@grpc/proto-loader');
const { EventEmitter } = require('events');
const crypto = require('crypto');
const path = require('path');

// ─── Load protobuf ──────────────────────────────────────────────────────
const PROTO_PATH = path.join(__dirname, 'proto', 'workload.proto');
const packageDef = protoLoader.loadSync(PROTO_PATH, {
  keepCase: false,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true
});
const proto = grpc.loadPackageDefinition(packageDef);

// ─── DER helpers ────────────────────────────────────────────────────────

/** Split concatenated DER-encoded certificates into individual buffers */
function splitDerCerts(buffer) {
  const certs = [];
  let offset = 0;
  while (offset < buffer.length) {
    if (buffer[offset] !== 0x30) break; // SEQUENCE tag
    let lenOffset = offset + 1;
    let len;
    if (buffer[lenOffset] < 0x80) {
      len = buffer[lenOffset];
      lenOffset += 1;
    } else {
      const numBytes = buffer[lenOffset] & 0x7f;
      len = 0;
      for (let i = 0; i < numBytes; i++) {
        len = (len << 8) | buffer[lenOffset + 1 + i];
      }
      lenOffset += 1 + numBytes;
    }
    const total = lenOffset - offset + len;
    certs.push(buffer.slice(offset, offset + total));
    offset += total;
  }
  return certs;
}

/** Convert DER bytes to PEM string */
function derToPem(der, type) {
  const b64 = Buffer.from(der).toString('base64');
  const lines = b64.match(/.{1,64}/g).join('\n');
  return `-----BEGIN ${type}-----\n${lines}\n-----END ${type}-----`;
}

// ─── Wrapper classes ────────────────────────────────────────────────────

class CertWrapper {
  constructor(derBuffer) {
    this._pem = derToPem(derBuffer, 'CERTIFICATE');
  }
  /** Returns PEM-encoded certificate */
  export() { return this._pem; }
}

class KeyWrapper {
  constructor(derBuffer) {
    this._pem = derToPem(derBuffer, 'PRIVATE KEY');
  }
  /** Returns PEM-encoded PKCS#8 private key */
  export(_options) { return this._pem; }
}

class SVID {
  constructor(raw) {
    this.id = raw.spiffeId;
    const certsDer = splitDerCerts(Buffer.from(raw.x509Svid));
    this.certificates = certsDer.map(d => new CertWrapper(d));
    this.privateKey = new KeyWrapper(Buffer.from(raw.x509SvidKey));
    try {
      const x509 = new crypto.X509Certificate(this.certificates[0].export());
      this.expiresAt = new Date(x509.validTo);
    } catch {
      this.expiresAt = null;
    }
  }
}

class TrustBundle {
  constructor(derBytes) {
    const certsDer = splitDerCerts(Buffer.from(derBytes));
    this.x509Authorities = certsDer.map(d => new CertWrapper(d));
  }
}

// ─── X509Source ─────────────────────────────────────────────────────────

class X509Source extends EventEmitter {
  constructor() {
    super();
    this.svids = [];
    this.bundles = new Map();
    this._client = null;
    this._stream = null;
  }

  /**
   * Connect to a SPIRE Agent and fetch X.509-SVIDs.
   * @param {{ socketPath: string }} opts  e.g. { socketPath: 'unix:///run/spire/sockets/agent.sock' }
   * @returns {Promise<X509Source>}
   */
  static async create({ socketPath }) {
    const source = new X509Source();

    source._client = new proto.SpiffeWorkloadAPI(
      socketPath,
      grpc.credentials.createInsecure()
    );

    await new Promise((resolve, reject) => {
      const metadata = new grpc.Metadata();
      metadata.set('workload.spiffe.io', 'true');

      source._stream = source._client.fetchX509Svid({}, metadata);

      let resolved = false;

      source._stream.on('data', (response) => {
        source._updateFromResponse(response);
        if (!resolved) {
          resolved = true;
          resolve();
        } else {
          source.emit('update', { svids: source.svids });
        }
      });

      source._stream.on('error', (err) => {
        if (!resolved) {
          resolved = true;
          reject(err);
        }
        console.error('[spiffe] Stream error:', err.message);
      });

      source._stream.on('end', () => {
        console.log('[spiffe] Stream ended');
      });
    });

    return source;
  }

  _updateFromResponse(response) {
    this.svids = (response.svids || []).map(s => new SVID(s));

    for (const s of (response.svids || [])) {
      const trustDomain = s.spiffeId.replace('spiffe://', '').split('/')[0];
      if (s.bundle && s.bundle.length > 0) {
        this.bundles.set(trustDomain, new TrustBundle(s.bundle));
      }
    }

    if (response.federatedBundles) {
      for (const [td, bundleBytes] of Object.entries(response.federatedBundles)) {
        if (bundleBytes && bundleBytes.length > 0) {
          this.bundles.set(td, new TrustBundle(bundleBytes));
        }
      }
    }
  }

  close() {
    if (this._stream) this._stream.cancel();
    if (this._client) this._client.close();
  }
}

module.exports = { X509Source };
