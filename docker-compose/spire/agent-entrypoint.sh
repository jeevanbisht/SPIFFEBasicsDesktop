#!/bin/sh
# agent-entrypoint.sh — Waits for a join token, then starts the SPIRE Agent
set -e

echo "[agent-entrypoint] Waiting for join token..."
while [ ! -f /opt/spire/tokens/join-token ]; do
  sleep 1
done

TOKEN=$(cat /opt/spire/tokens/join-token)
echo "[agent-entrypoint] Got join token, starting agent..."
exec /opt/spire/bin/spire-agent run \
    -config /opt/spire/conf/agent/agent.conf \
    -joinToken "$TOKEN"
