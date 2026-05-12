#!/usr/bin/env bash
# check-prereqs.sh — verify all requirements for the standalone tutorial
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS="✅"; FAIL="❌"; WARN="⚠️ "
errors=0; warnings=0

chk() {
  local cmd=$1 hint=$2 required=${3:-true}
  if command -v "${cmd}" &>/dev/null; then
    local v; v=$(${cmd} --version 2>/dev/null | head -1 || ${cmd} version 2>/dev/null | head -1 || echo "found")
    echo -e "${PASS} ${GREEN}${cmd}${NC}: ${v}"
  elif [ "${required}" = "true" ]; then
    echo -e "${FAIL} ${RED}${cmd}${NC} not found — ${hint}"
    ((errors++)) || true
  else
    echo -e "${WARN} ${YELLOW}${cmd}${NC} not found (optional for Track B) — ${hint}"
    ((warnings++)) || true
  fi
}

echo -e "${BLUE}Required (both tracks):${NC}"
if command -v docker &>/dev/null; then
  if docker info &>/dev/null 2>&1; then
    echo -e "${PASS} ${GREEN}docker${NC}: $(docker --version) — running ✅"
  else
    echo -e "${FAIL} ${RED}Docker not running${NC} — start Docker Desktop"
    ((errors++)) || true
  fi
else
  echo -e "${FAIL} ${RED}docker not found${NC} — https://docker.com"
  ((errors++)) || true
fi

if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
  echo -e "${PASS} ${GREEN}docker compose${NC}: $(docker compose version)"
else
  echo -e "${FAIL} ${RED}docker compose not found${NC} — update Docker Desktop"
  ((errors++)) || true
fi

echo ""
echo -e "${BLUE}Required for Track B (kind/Kubernetes):${NC}"
chk "kind"    "https://kind.sigs.k8s.io/docs/user/quick-start/" false
chk "kubectl" "https://kubernetes.io/docs/tasks/tools/"          false

echo ""
echo -e "${BLUE}Optional but useful:${NC}"
chk "openssl" "brew install openssl / apt install openssl" false
chk "python3" "https://python.org" false

# Docker resources check
echo ""
echo -e "${BLUE}Docker resources:${NC}"
DOCKER_MEM=$(docker info 2>/dev/null | grep "Total Memory" | awk '{print $3, $4}' || echo "unknown")
echo "   Memory available to Docker: ${DOCKER_MEM}"
echo "   (Recommend 4GB+ for Track A, 8GB+ for Track B)"

echo ""
if [ "${errors}" -eq 0 ]; then
  echo -e "${PASS} ${GREEN}All required tools found!${NC}"
  echo ""
  echo -e "Start Track A: ${BLUE}cd docker-compose && docker compose up -d --build${NC}"
  echo -e "Start Track B: ${BLUE}cd kind && ./setup.sh${NC}"
else
  echo -e "${FAIL} ${RED}${errors} required tool(s) missing.${NC}"
  exit 1
fi
