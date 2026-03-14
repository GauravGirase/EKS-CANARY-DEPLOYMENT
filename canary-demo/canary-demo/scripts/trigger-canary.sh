#!/bin/bash
# trigger-canary.sh
# Updates the rollout image to v2-buggy, starting the canary process

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Triggering Canary Deployment             ║${NC}"
echo -e "${CYAN}║     Updating: v1 → v2-buggy (60% error rate)║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}[INFO]${NC} Current rollout status:"
kubectl argo rollouts get rollout myapp -n canary-demo 2>/dev/null || \
  kubectl get deployment myapp -n canary-demo

echo ""
echo -e "${YELLOW}[WARN]${NC} v2-buggy has an intentional 60% error rate."
echo -e "${YELLOW}[WARN]${NC} The AnalysisTemplate will detect this and auto-rollback."
echo ""
read -p "Press ENTER to start canary deployment..."

# Update the rollout image to v2-buggy
echo ""
echo -e "${BLUE}[INFO]${NC} Setting image to myapp:v2-buggy..."
kubectl argo rollouts set image myapp myapp=myapp:v2-buggy -n canary-demo

echo ""
echo -e "${GREEN}[OK]${NC} Canary triggered! Argo Rollouts is now:"
echo "  1. Deploying v2-buggy pods"
echo "  2. Shifting 10% traffic to canary"
echo "  3. Running AnalysisTemplates (success-rate + latency)"
echo "  4. Will auto-rollback when error rate > 5% for 3 consecutive checks"
echo ""
echo -e "${CYAN}Watch it live:${NC}"
echo "  kubectl argo rollouts get rollout myapp -n canary-demo --watch"
echo ""
echo -e "${CYAN}In a separate terminal, send traffic:${NC}"
echo "  ./scripts/load-test.sh"
