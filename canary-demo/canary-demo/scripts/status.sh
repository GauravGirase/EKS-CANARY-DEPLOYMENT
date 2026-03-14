#!/bin/bash
# status.sh — Real-time dashboard of the canary deployment

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

NAMESPACE="canary-demo"
INTERVAL="${1:-5}"  # refresh every N seconds

clear_screen() { printf '\033[2J\033[H'; }

while true; do
  clear_screen

  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}${BOLD}║     Canary Deployment Monitor                            ║${NC}"
  echo -e "${CYAN}${BOLD}║     $(date '+%Y-%m-%d %H:%M:%S')  (refresh: ${INTERVAL}s)         ║${NC}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  # ── Rollout Status ──────────────────────────────────────────────
  echo -e "${BOLD}── Rollout Status ─────────────────────────────────────────${NC}"
  kubectl argo rollouts get rollout myapp -n $NAMESPACE 2>/dev/null || \
    kubectl get deployment myapp -n $NAMESPACE 2>/dev/null
  echo ""

  # ── Pod Status ─────────────────────────────────────────────────
  echo -e "${BOLD}── Pods ────────────────────────────────────────────────────${NC}"
  kubectl get pods -n $NAMESPACE -l app=myapp \
    -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready,IMAGE:.spec.containers[0].image,AGE:.metadata.creationTimestamp' \
    2>/dev/null
  echo ""

  # ── Analysis Runs ──────────────────────────────────────────────
  echo -e "${BOLD}── Analysis Runs ───────────────────────────────────────────${NC}"
  kubectl get analysisrun -n $NAMESPACE 2>/dev/null || echo "  No analysis runs yet"
  echo ""

  # ── Ingress Weights ────────────────────────────────────────────
  echo -e "${BOLD}── Traffic Split (Ingress weights) ─────────────────────────${NC}"
  CANARY_WEIGHT=$(kubectl get ingress myapp-canary-ingress -n $NAMESPACE \
    -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/canary-weight}' \
    2>/dev/null || echo "0")
  STABLE_WEIGHT=$((100 - ${CANARY_WEIGHT:-0}))

  # Visual weight bar
  filled_stable=$((STABLE_WEIGHT / 5))
  filled_canary=$((${CANARY_WEIGHT:-0} / 5))

  printf "  Stable (v1): [${GREEN}"
  printf '%0.s█' $(seq 1 $filled_stable 2>/dev/null || echo "")
  printf "${NC}"
  printf '%0.s░' $(seq 1 $((20 - filled_stable)) 2>/dev/null || echo "")
  printf "] ${GREEN}${STABLE_WEIGHT}%%${NC}\n"

  printf "  Canary (v2): [${YELLOW}"
  printf '%0.s█' $(seq 1 ${filled_canary:-0} 2>/dev/null || echo "")
  printf "${NC}"
  printf '%0.s░' $(seq 1 $((20 - ${filled_canary:-0})) 2>/dev/null || echo "")
  printf "] ${YELLOW}${CANARY_WEIGHT:-0}%%${NC}\n"
  echo ""

  # ── Events ─────────────────────────────────────────────────────
  echo -e "${BOLD}── Recent Events ───────────────────────────────────────────${NC}"
  kubectl get events -n $NAMESPACE \
    --sort-by='.lastTimestamp' \
    --field-selector type=Warning 2>/dev/null | tail -5 || echo "  No warnings"
  echo ""

  echo -e "  ${BLUE}Commands:${NC}"
  echo "  Trigger canary:  ./scripts/trigger-canary.sh"
  echo "  Send traffic:    ./scripts/load-test.sh"
  echo "  Manual rollback: ./scripts/rollback.sh"
  echo "  Promote:         kubectl argo rollouts promote myapp -n canary-demo"

  sleep $INTERVAL
done
