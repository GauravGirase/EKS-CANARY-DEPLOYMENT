#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()    { echo -e "\n${CYAN}==> $1${NC}"; }

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║     Canary Demo - Full Setup                 ║"
echo "║     myapp v1 (stable) + v2 (buggy)           ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Prerequisites check ────────────────────────────────────────────────────────
step "Checking prerequisites"

check_cmd() {
  if command -v "$1" &>/dev/null; then
    success "$1 found"
  else
    error "$1 not found. Please install it first."
  fi
}

check_cmd kubectl
check_cmd docker
check_cmd helm

# Check cluster is reachable
kubectl cluster-info &>/dev/null || error "Cannot reach Kubernetes cluster. Is it running?"
success "Kubernetes cluster reachable"

# ── Build Docker images ────────────────────────────────────────────────────────
step "Building Docker images"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

info "Building myapp:v1 (stable - healthy)"
docker build -t myapp:v1 "$PROJECT_DIR/app-v1/" --quiet
success "myapp:v1 built"

info "Building myapp:v2-buggy (canary - intentionally broken)"
docker build -t myapp:v2-buggy "$PROJECT_DIR/app-v2/" --quiet
success "myapp:v2-buggy built"

# If using kind or minikube, load images into cluster
if kubectl get nodes | grep -q "kind"; then
  info "Detected kind cluster - loading images"
  kind load docker-image myapp:v1 myapp:v2-buggy 2>/dev/null || true
  success "Images loaded into kind"
fi

if command -v minikube &>/dev/null && minikube status &>/dev/null 2>&1; then
  info "Detected minikube - loading images"
  minikube image load myapp:v1
  minikube image load myapp:v2-buggy
  success "Images loaded into minikube"
fi

# ── Install Nginx Ingress Controller ──────────────────────────────────────────
step "Installing Nginx Ingress Controller"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update &>/dev/null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=1 \
  --wait --timeout=120s
success "Nginx Ingress installed"

# ── Install Argo Rollouts ──────────────────────────────────────────────────────
step "Installing Argo Rollouts"

kubectl create namespace argo-rollouts 2>/dev/null || true
kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

info "Waiting for Argo Rollouts controller..."
kubectl rollout status deployment/argo-rollouts -n argo-rollouts --timeout=120s
success "Argo Rollouts installed"

# Install kubectl plugin
if ! command -v kubectl-argo-rollouts &>/dev/null; then
  warn "kubectl argo rollouts plugin not found"
  info "Install it from: https://github.com/argoproj/argo-rollouts/releases"
  info "Or: brew install argoproj/tap/kubectl-argo-rollouts"
fi

# ── Install Prometheus ─────────────────────────────────────────────────────────
step "Installing Prometheus"

kubectl apply -f "$PROJECT_DIR/k8s/monitoring/prometheus.yaml"
info "Waiting for Prometheus..."
kubectl rollout status deployment/prometheus-server -n monitoring --timeout=120s
success "Prometheus installed"

# ── Deploy app and canary resources ───────────────────────────────────────────
step "Deploying application"

kubectl apply -f "$PROJECT_DIR/k8s/base/services.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/analysis/analysis-templates.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/canary/rollout.yaml"

info "Waiting for initial rollout (v1)..."
sleep 10
kubectl argo rollouts status myapp -n canary-demo --timeout=120s 2>/dev/null || \
  kubectl rollout status deployment/myapp -n canary-demo --timeout=120s 2>/dev/null || true

success "Application deployed!"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║              Setup Complete!                         ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Watch rollout live:"
echo "     kubectl argo rollouts get rollout myapp -n canary-demo --watch"
echo ""
echo "  2. Trigger canary (deploys buggy v2):"
echo "     ./scripts/trigger-canary.sh"
echo ""
echo "  3. Send test traffic:"
echo "     ./scripts/load-test.sh"
echo ""
echo "  4. Watch auto-rollback happen in real time"
echo ""
echo "  5. Manual rollback anytime:"
echo "     ./scripts/rollback.sh"
echo ""



