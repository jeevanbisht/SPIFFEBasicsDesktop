#!/bin/sh
# bootstrap.sh — Generate join token, attest agent, and register workloads
# Runs once at startup via the spire-bootstrap service

set -e
SPIRE_SERVER="spire-server:8081"

echo "=== SPIRE Bootstrap ==="
echo ""

# Wait for SPIRE Server to be fully ready
echo "Waiting for SPIRE Server..."
until /opt/spire/bin/spire-server healthcheck -registrationUDSPath "" \
    -serverAddress spire-server -serverPort 8081 2>/dev/null; do
  sleep 2
done
echo "Server is ready!"

# Generate a join token for the agent
echo ""
echo "Generating join token for SPIRE Agent..."
JOIN_TOKEN=$(/opt/spire/bin/spire-server token generate \
    -serverAddress spire-server \
    -serverPort 8081 \
    -spiffeID "spiffe://example.org/agent/docker" \
    -ttl 600 | grep "Token:" | awk '{print $2}')

echo "Join token: ${JOIN_TOKEN}"

# Write the token to a shared location the agent can read
# (In production, this would be passed via a secure mechanism)
echo "${JOIN_TOKEN}" > /tmp/join-token.txt
echo "Join token written."

# Wait for agent to attest using the token
echo ""
echo "Waiting for agent to attest..."
sleep 5

# Get the agent SPIFFE ID (needed as parent for workload entries)
AGENT_ID=$(/opt/spire/bin/spire-server agent list \
    -serverAddress spire-server \
    -serverPort 8081 \
    -format json 2>/dev/null | \
    python3 -c "import json,sys; agents=json.load(sys.stdin); print(agents[0]['id']['path'])" 2>/dev/null || echo "")

if [ -z "${AGENT_ID}" ]; then
    echo "Warning: agent not yet attested, using default parent path"
    PARENT_ID="spiffe://example.org/agent/docker"
else
    PARENT_ID="spiffe://example.org${AGENT_ID}"
fi

echo "Agent SPIFFE ID: ${PARENT_ID}"

# Register the FRONTEND service
echo ""
echo "Registering frontend service..."
/opt/spire/bin/spire-server entry create \
    -serverAddress spire-server \
    -serverPort 8081 \
    -parentID "${PARENT_ID}" \
    -spiffeID "spiffe://example.org/service/frontend" \
    -selector "docker:label:spiffe.io/service:frontend" \
    -ttl 3600 \
    2>/dev/null && echo "✅ Frontend registered: spiffe://example.org/service/frontend" || \
    echo "⚠️  Frontend entry may already exist"

# Register the BACKEND service
echo ""
echo "Registering backend service..."
/opt/spire/bin/spire-server entry create \
    -serverAddress spire-server \
    -serverPort 8081 \
    -parentID "${PARENT_ID}" \
    -spiffeID "spiffe://example.org/service/backend" \
    -selector "docker:label:spiffe.io/service:backend" \
    -ttl 3600 \
    2>/dev/null && echo "✅ Backend registered: spiffe://example.org/service/backend" || \
    echo "⚠️  Backend entry may already exist"

echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Trust domain:    spiffe://example.org"
echo "Frontend SVID:   spiffe://example.org/service/frontend"
echo "Backend SVID:    spiffe://example.org/service/backend"
echo ""
echo "Try it:"
echo "  curl http://localhost:3000/orders"
echo "  curl http://localhost:3000/my-identity"
