#!/bin/bash
# rollback.sh — Manual rollback options

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

NAMESPACE="canary-demo"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Manual Rollback Options                  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}[INFO]${NC} Current rollout state:"
kubectl argo rollouts get rollout myapp -n $NAMESPACE 2>/dev/null
echo ""

echo "Choose rollback method:"
echo ""
echo "  1) Abort canary immediately (fastest - zero downtime)"
echo "     → Cuts traffic back to stable v1, canary pods stay up for inspection"
echo ""
echo "  2) Undo rollout (go to previous revision)"
echo "     → Full rollback, scales down canary"
echo ""
echo "  3) Rollback to specific revision"
echo "     → Choose exactly which version to restore"
echo ""
echo "  4) Emergency: delete canary pods NOW"
echo "     → Nuclear option - use only if above methods fail"
echo ""
read -p "Enter choice [1-4]: " choice

case $choice in
  1)
    echo ""
    echo -e "${YELLOW}[ACTION]${NC} Aborting canary rollout..."
    kubectl argo rollouts abort myapp -n $NAMESPACE
    echo ""
    echo -e "${GREEN}[OK]${NC} Canary aborted!"
    echo "  - Traffic immediately shifted back to stable (v1)"
    echo "  - Canary pods still running (inspect logs with kubectl logs)"
    echo "  - To fully clean up, run option 2"
    ;;

  2)
    echo ""
    echo -e "${YELLOW}[ACTION]${NC} Undoing rollout (reverting to previous stable)..."
    kubectl argo rollouts undo myapp -n $NAMESPACE
    echo ""
    echo -e "${GREEN}[OK]${NC} Rollout undone!"
    echo "  - Previous stable ReplicaSet scaling back up"
    echo "  - Canary pods scaling down"
    ;;

  3)
    echo ""
    echo -e "${BLUE}[INFO]${NC} Rollout history:"
    kubectl argo rollouts history rollout myapp -n $NAMESPACE
    echo ""
    read -p "Enter revision number to rollback to: " rev
    kubectl argo rollouts undo myapp -n $NAMESPACE --to-revision=$rev
    echo -e "${GREEN}[OK]${NC} Rolling back to revision $rev"
    ;;

  4)
    echo ""
    echo -e "${RED}[WARN]${NC} Emergency pod deletion!"
    read -p "Are you sure? This may cause brief downtime. [yes/no]: " confirm
    if [[ "$confirm" == "yes" ]]; then
      # Scale canary to 0 directly
      CANARY_RS=$(kubectl get replicaset -n $NAMESPACE \
        -l app=myapp \
        --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null)

      if [[ -n "$CANARY_RS" ]]; then
        kubectl scale replicaset $CANARY_RS --replicas=0 -n $NAMESPACE
        echo -e "${GREEN}[OK]${NC} Canary ReplicaSet $CANARY_RS scaled to 0"
      fi

      # Patch service to stable only
      kubectl patch service myapp-canary-svc -n $NAMESPACE \
        -p '{"spec":{"selector":{"app":"myapp","rollouts-pod-template-hash":"stable"}}}' \
        2>/dev/null || true
    fi
    ;;

  *)
    echo -e "${RED}Invalid choice${NC}"
    exit 1
    ;;
esac

echo ""
echo -e "${CYAN}Watch recovery:${NC}"
echo "  kubectl argo rollouts get rollout myapp -n $NAMESPACE --watch"
