#!/bin/bash
# load-test.sh
# Sends continuous traffic and shows real-time success/error rates

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

NAMESPACE="canary-demo"
ENDPOINT="${1:-http://myapp.local/api/data}"
REQUESTS_PER_BATCH=20
SLEEP_BETWEEN=2

# Auto-detect endpoint if using port-forward or minikube
if [[ "$ENDPOINT" == "http://myapp.local/api/data" ]]; then
  # Try to get the ingress IP
  INGRESS_IP=$(kubectl get ingress myapp-stable-ingress -n $NAMESPACE \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

  if [[ -z "$INGRESS_IP" ]]; then
    echo -e "${YELLOW}[WARN]${NC} No ingress IP found. Using port-forward instead."
    echo -e "${BLUE}[INFO]${NC} Starting port-forward to stable service..."

    # Kill any existing port-forward
    pkill -f "port-forward.*myapp" 2>/dev/null || true
    sleep 1

    kubectl port-forward svc/myapp-stable-svc 8080:80 -n $NAMESPACE &>/dev/null &
    PF_PID=$!
    sleep 2
    ENDPOINT="http://localhost:8080/api/data"
    echo -e "${GREEN}[OK]${NC} Port-forward started (PID: $PF_PID)"
  else
    echo -e "${GREEN}[OK]${NC} Using ingress IP: $INGRESS_IP"
    ENDPOINT="http://$INGRESS_IP/api/data"
  fi
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Load Test Running                        ║${NC}"
echo -e "${CYAN}║     Endpoint: $ENDPOINT${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "  Ctrl+C to stop"
echo ""

total=0
success_count=0
error_count=0
batch=0

printf "%-8s %-10s %-10s %-10s %-12s\n" "Batch" "Success" "Errors" "Total" "Error Rate"
printf "%-8s %-10s %-10s %-10s %-12s\n" "-----" "-------" "------" "-----" "----------"

while true; do
  batch=$((batch + 1))
  batch_success=0
  batch_errors=0

  for i in $(seq 1 $REQUESTS_PER_BATCH); do
    # Make request and capture HTTP status code
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      --connect-timeout 2 \
      --max-time 3 \
      "$ENDPOINT" 2>/dev/null)

    if [[ "$STATUS" == "200" ]]; then
      batch_success=$((batch_success + 1))
      success_count=$((success_count + 1))
    else
      batch_errors=$((batch_errors + 1))
      error_count=$((error_count + 1))
    fi
    total=$((total + 1))
  done

  # Calculate error rate
  if [[ $total -gt 0 ]]; then
    error_rate=$(echo "scale=1; $error_count * 100 / $total" | bc 2>/dev/null || \
      awk "BEGIN {printf \"%.1f\", $error_count * 100 / $total}")
  else
    error_rate=0
  fi

  # Color code the error rate
  if (( $(echo "$error_rate > 10" | bc -l 2>/dev/null || \
    awk "BEGIN {print ($error_rate > 10) ? 1 : 0}") )); then
    rate_color=$RED
  elif (( $(echo "$error_rate > 3" | bc -l 2>/dev/null || \
    awk "BEGIN {print ($error_rate > 3) ? 1 : 0}") )); then
    rate_color=$YELLOW
  else
    rate_color=$GREEN
  fi

  printf "%-8s ${GREEN}%-10s${NC} ${RED}%-10s${NC} %-10s ${rate_color}%-12s${NC}\n" \
    "$batch" \
    "$batch_success/$REQUESTS_PER_BATCH" \
    "$batch_errors/$REQUESTS_PER_BATCH" \
    "$total" \
    "${error_rate}%"

  sleep $SLEEP_BETWEEN
done
