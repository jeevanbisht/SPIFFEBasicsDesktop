#!/usr/bin/env node
// fetch-svid.js — Fetch X.509-SVID from SPIRE Agent and write PEM files
// Usage: node fetch-svid.js [output-dir]
//   Writes: svid.0.pem, svid.key.pem, bundle.0.pem
'use strict';

const grpc = require('@grpc/grpc-js');
const protoLoader = require('@grpc/proto-loader');
const fs = require('fs');
const path = require('path');

const PROTO_PATH = path.join(__dirname, 'proto', 'workload.proto');
const SOCKET = process.env.SPIFFE_ENDPOINT_SOCKET || 'unix:///run/spire/sockets/agent.sock';
const OUT_DIR = process.argv[2] || '/tmp';

const packageDef = protoLoader.loadSync(PROTO_PATH, {
  keepCase: false, longs: String, enums: String, defaults: true, oneofs: true
});
const proto = grpc.loadPackageDefinition(packageDef);

function derToPem(buf, type) {
  const b64 = Buffer.from(buf).toString('base64');
  return `-----BEGIN ${type}-----\n${b64.match(/.{1,64}/g).join('\n')}\n-----END ${type}-----\n`;
}

function splitDer(buf) {
  const certs = [];
  let offset = 0;
  while (offset < buf.length) {
    if (buf[offset] !== 0x30) break;
    let lenOffset = offset + 1, len;
    if (buf[lenOffset] < 0x80) {
      len = buf[lenOffset]; lenOffset++;
    } else {
      const numBytes = buf[lenOffset] & 0x7f; len = 0;
      for (let i = 0; i < numBytes; i++) len = (len << 8) | buf[lenOffset + 1 + i];
      lenOffset += 1 + numBytes;
    }
    const total = lenOffset - offset + len;
    certs.push(buf.slice(offset, offset + total));
    offset += total;
  }
  return certs;
}

const client = new proto.SpiffeWorkloadAPI(SOCKET, grpc.credentials.createInsecure());
const metadata = new grpc.Metadata();
metadata.set('workload.spiffe.io', 'true');

const stream = client.fetchX509Svid({}, metadata);
stream.on('data', (response) => {
  const svid = response.svids[0];
  console.log(`SPIFFE ID : ${svid.spiffeId}`);

  const certs = splitDer(Buffer.from(svid.x509Svid));
  certs.forEach((d, i) => {
    const f = path.join(OUT_DIR, `svid.${i}.pem`);
    fs.writeFileSync(f, derToPem(d, 'CERTIFICATE'));
    console.log(`Certificate: ${f}`);
  });

  const keyFile = path.join(OUT_DIR, 'svid.key.pem');
  fs.writeFileSync(keyFile, derToPem(Buffer.from(svid.x509SvidKey), 'PRIVATE KEY'));
  console.log(`Private key: ${keyFile}`);

  const bundleCerts = splitDer(Buffer.from(svid.bundle));
  bundleCerts.forEach((d, i) => {
    const f = path.join(OUT_DIR, `bundle.${i}.pem`);
    fs.writeFileSync(f, derToPem(d, 'CERTIFICATE'));
    console.log(`CA bundle  : ${f}`);
  });

  process.exit(0);
});

stream.on('error', (err) => {
  console.error('Error:', err.message);
  process.exit(1);
});

setTimeout(() => { console.error('Timeout waiting for SVID'); process.exit(1); }, 10000);
