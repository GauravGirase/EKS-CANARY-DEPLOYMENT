#!/bin/bash
# local-test.sh
# Quick local test WITHOUT a full k8s cluster
# Tests v1 and v2 directly with Docker to see the difference

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Local Docker Test (no k8s needed)        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Build images
echo -e "${BLUE}[1/4]${NC} Building images..."
docker build -t myapp:v1 "$PROJECT_DIR/app-v1/" -q
docker build -t myapp:v2-buggy "$PROJECT_DIR/app-v2/" -q
echo -e "${GREEN}[OK]${NC} Images built"

# Stop any running containers
docker rm -f myapp-v1-test myapp-v2-test 2>/dev/null || true

# Start v1
echo -e "${BLUE}[2/4]${NC} Starting v1 on port 8081..."
docker run -d --name myapp-v1-test -p 8081:8080 myapp:v1 > /dev/null
sleep 2

# Start v2-buggy
echo -e "${BLUE}[3/4]${NC} Starting v2-buggy on port 8082..."
docker run -d --name myapp-v2-test -p 8082:8080 myapp:v2-buggy > /dev/null
sleep 2

echo ""
echo -e "${BLUE}[4/4]${NC} Testing both versions (10 requests each)..."
echo ""

# Test v1
echo -e "${GREEN}── v1 (stable) on :8081 ─────────────────────────────${NC}"
v1_success=0; v1_errors=0
for i in $(seq 1 10); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://localhost:8081/api/data)
  if [[ "$STATUS" == "200" ]]; then
    echo -e "  Request $i: ${GREEN}200 OK${NC}"
    v1_success=$((v1_success + 1))
  else
    echo -e "  Request $i: ${RED}$STATUS ERROR${NC}"
    v1_errors=$((v1_errors + 1))
  fi
done
echo -e "  Result: ${GREEN}$v1_success/10 success${NC}, ${RED}$v1_errors/10 errors${NC}"

echo ""

# Test v2-buggy
echo -e "${RED}── v2-buggy (canary) on :8082 ───────────────────────${NC}"
v2_success=0; v2_errors=0
for i in $(seq 1 10); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost:8082/api/data)
  if [[ "$STATUS" == "200" ]]; then
    echo -e "  Request $i: ${GREEN}200 OK${NC}"
    v2_success=$((v2_success + 1))
  else
    echo -e "  Request $i: ${RED}$STATUS ERROR${NC}"
    v2_errors=$((v2_errors + 1))
  fi
done
echo -e "  Result: ${GREEN}$v2_success/10 success${NC}, ${RED}$v2_errors/10 errors${NC}"

echo ""
echo -e "${YELLOW}──────────────────────────────────────────────────────${NC}"
echo -e "  v1 error rate: $(echo "scale=0; $v1_errors * 100 / 10" | bc)%  (should be ~0%)"
echo -e "  v2 error rate: $(echo "scale=0; $v2_errors * 100 / 10" | bc)%  (should be ~60%)"
echo ""
echo -e "  This is exactly what AnalysisTemplate catches in production."
echo -e "  When v2 is routed even 10% of traffic, error rate spikes"
echo -e "  above the 5% threshold → auto-rollback triggered."
echo ""

# Check response payloads
echo -e "${BLUE}── Response payloads ───────────────────────────────────${NC}"
echo -e "  v1: $(curl -s http://localhost:8081/ 2>/dev/null)"
echo -e "  v2: $(curl -s http://localhost:8082/ 2>/dev/null)"
echo ""

# Cleanup
echo -e "${BLUE}Cleaning up containers...${NC}"
docker rm -f myapp-v1-test myapp-v2-test > /dev/null
echo -e "${GREEN}Done!${NC}"
