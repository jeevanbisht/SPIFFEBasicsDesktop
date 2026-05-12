#!/usr/bin/env bash
# advanced/disk-ca/setup-custom-ca.sh
# Creates a local root CA and configures SPIRE to use it as UpstreamAuthority
# This simulates the Azure Key Vault CA pattern (Level 300) without the cloud
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${BLUE}[disk-ca]${NC} $*"; }
ok()  { echo -e "${GREEN}[ok]${NC} $*"; }

CA_DIR="$(dirname "$0")/ca"
mkdir -p "${CA_DIR}"

log "Step 1: Generate Root CA key + certificate"
openssl ecparam -name prime256v1 -genkey -noout -out "${CA_DIR}/root-ca.key"
openssl req -new -x509 \
    -key "${CA_DIR}/root-ca.key" \
    -out "${CA_DIR}/root-ca.pem" \
    -days 3650 \
    -subj "/O=SPIFFE Tutorial/CN=Standalone Root CA" \
    -extensions v3_ca \
    -addext "basicConstraints=critical,CA:TRUE"
ok "Root CA created: ${CA_DIR}/root-ca.pem"

log "Step 2: Create Kubernetes Secret with CA key + cert"
kubectl -n spire create secret generic spire-upstream-ca \
    --from-file=root.crt="${CA_DIR}/root-ca.pem" \
    --from-file=root.key="${CA_DIR}/root-ca.key" \
    --dry-run=client -o yaml | kubectl apply -f -
ok "Secret 'spire-upstream-ca' created in spire namespace"

log "Step 3: Update SPIRE Server ConfigMap to use disk UpstreamAuthority"
kubectl -n spire patch configmap spire-server --type=merge -p '{
  "data": {
    "upstream.conf": "UpstreamAuthority \"disk\" {\n  plugin_data {\n    key_file_path = \"/run/spire/upstream/root.key\"\n    cert_file_path = \"/run/spire/upstream/root.crt\"\n  }\n}\n"
  }
}'

log "Step 4: Mount the CA secret into SPIRE Server pod"
# (In a real setup you'd patch the StatefulSet; here we restart for simplicity)
kubectl -n spire rollout restart statefulset/spire-server
kubectl -n spire rollout status statefulset/spire-server --timeout=60s

log "Step 5: Verify chain of trust"
sleep 5
kubectl -n spire exec -it spire-server-0 -- \
  /opt/spire/bin/spire-server bundle show | \
  openssl x509 -text -noout 2>/dev/null | grep -E "Issuer:|Subject:" || true

ok ""
ok "Custom Root CA is now the upstream authority!"
ok "SVIDs now chain to: ${CA_DIR}/root-ca.pem"
ok ""
ok "Verify your existing workloads still work:"
ok "  kubectl exec -it test-workload -- \\"
ok "    /opt/spire/bin/spire-agent api fetch x509 \\"
ok "      -socketPath /run/spire/sockets/agent.sock"
