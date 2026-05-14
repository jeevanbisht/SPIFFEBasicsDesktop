#!/bin/sh
# bootstrap.sh — Register workload entries on SPIRE Server
# Runs once at startup via the spire-bootstrap service

set -e
SOCKET="/tmp/spire-server/private/api.sock"

echo "=== SPIRE Bootstrap ==="
echo ""

# Wait for SPIRE Server API socket to be available
echo "Waiting for SPIRE Server..."
until /opt/spire/bin/spire-server healthcheck -socketPath "$SOCKET" 2>/dev/null; do
  sleep 2
done
echo "Server is ready!"

# The agent has already attested (join token was passed by spire-init).
# Determine the agent's parent SPIFFE ID.
echo ""
echo "Looking up attested agent..."
AGENT_ID=$(/opt/spire/bin/spire-server agent list \
    -socketPath "$SOCKET" 2>/dev/null | grep "SPIFFE ID" | head -1 | awk '{print $NF}' || echo "")

if [ -z "${AGENT_ID}" ]; then
    echo "Warning: agent not found, using default parent ID"
    PARENT_ID="spiffe://example.org/agent/docker"
else
    PARENT_ID="${AGENT_ID}"
fi

echo "Agent SPIFFE ID: ${PARENT_ID}"

# Register the FRONTEND service
echo ""
echo "Registering frontend service..."
/opt/spire/bin/spire-server entry create \
    -socketPath "$SOCKET" \
    -parentID "${PARENT_ID}" \
    -spiffeID "spiffe://example.org/service/frontend" \
    -selector "unix:uid:10001" \
    -ttl 3600 \
    2>/dev/null && echo "✅ Frontend registered: spiffe://example.org/service/frontend" || \
    echo "⚠️  Frontend entry may already exist"

# Register the BACKEND service
echo ""
echo "Registering backend service..."
/opt/spire/bin/spire-server entry create \
    -socketPath "$SOCKET" \
    -parentID "${PARENT_ID}" \
    -spiffeID "spiffe://example.org/service/backend" \
    -selector "unix:uid:10002" \
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
