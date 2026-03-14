# Canary Deployment Demo — Full Enterprise Setup

A complete, runnable project demonstrating **canary deployments with automatic rollback** using:
- **Argo Rollouts** — canary step controller
- **Nginx Ingress** — weighted traffic splitting  
- **Prometheus** — metrics collection
- **AnalysisTemplates** — automated pass/fail gates

---

## What this project contains

```
canary-demo/
├── app-v1/                     # Stable app (0% error rate)
│   ├── main.go
│   └── Dockerfile
├── app-v2/                     # Buggy app (60% error rate) ← intentional
│   ├── main.go
│   └── Dockerfile
├── k8s/
│   ├── base/
│   │   └── services.yaml       # Services + Ingress (stable + canary)
│   ├── canary/
│   │   └── rollout.yaml        # Argo Rollout CRD with canary steps
│   ├── analysis/
│   │   └── analysis-templates.yaml  # Prometheus-based auto-rollback rules
│   └── monitoring/
│       └── prometheus.yaml     # Prometheus deployment
└── scripts/
    ├── setup.sh                # Install everything (one command)
    ├── local-test.sh           # Test without k8s (Docker only)
    ├── trigger-canary.sh       # Deploy v2-buggy as canary
    ├── load-test.sh            # Send traffic, see success/error rates
    ├── status.sh               # Live dashboard
    └── rollback.sh             # Manual rollback options
```

---

## Quick Start

### Option A: Test locally with Docker only (no k8s needed)

```bash
# Just builds both images and shows v1 vs v2 error rates
chmod +x scripts/*.sh
./scripts/local-test.sh
```

Expected output:
```
── v1 (stable) ──────────────────────────────
  Request 1: 200 OK
  ...
  Result: 10/10 success, 0/10 errors

── v2-buggy (canary) ────────────────────────
  Request 1: 500 ERROR
  Request 2: 200 OK
  Request 3: 500 ERROR
  ...
  Result: 4/10 success, 6/10 errors
```

### Option B: Full Kubernetes demo

#### Prerequisites
```bash
# Option 1: kind (recommended for local)
brew install kind
kind create cluster --name canary-demo

# Option 2: minikube
minikube start --cpus=4 --memory=8g

# Required tools
brew install helm
brew install argoproj/tap/kubectl-argo-rollouts
```

#### 1. Run setup (installs everything)
```bash
chmod +x scripts/*.sh
./scripts/setup.sh
```

This installs:
- Nginx Ingress Controller
- Argo Rollouts controller + CRDs
- Prometheus
- Deploys myapp v1 (stable)
- Creates AnalysisTemplates

#### 2. Open three terminals

**Terminal 1 — Watch rollout live:**
```bash
kubectl argo rollouts get rollout myapp -n canary-demo --watch
```

**Terminal 2 — Send traffic:**
```bash
./scripts/load-test.sh
```

**Terminal 3 — Trigger the canary:**
```bash
./scripts/trigger-canary.sh
```

---

## What happens step by step

### Phase 1: Canary triggered (0 → 10% traffic)
```
Argo Rollouts creates v2-buggy pods
Nginx Ingress weight: stable=90%, canary=10%
AnalysisRun starts querying Prometheus every 30s
```

### Phase 2: Analysis detects failures
```
Prometheus query: success_rate = ~40%  (v2 has 60% error rate)
AnalysisTemplate threshold: >= 95% required
Result: FAIL (failure 1 of 3)
```

### Phase 3: Auto-rollback (no human action needed)
```
After 3 consecutive failures:
  AnalysisRun → Failed
  Argo Rollouts detects failure
  Nginx weight: stable=100%, canary=0%
  Canary ReplicaSet scaled to 0
  Rollout status → Degraded
  Alert fires (Slack/PagerDuty)
```

---

## Canary Steps (rollout.yaml)

| Step | Traffic | Duration | Gate |
|------|---------|----------|------|
| 1 | 10% → canary | 2 min pause | — |
| 2 | 10% | — | AnalysisTemplate (success-rate + latency) |
| 3 | 30% | 2 min pause | — |
| 4 | 30% | — | AnalysisTemplate (success-rate) |
| 5 | 50% | 1 min pause | Manual approval in prod |
| 6 | 100% | — | Full promotion |

---

## AnalysisTemplate Rules

| Metric | Threshold | Failure limit | Action |
|--------|-----------|---------------|--------|
| HTTP success rate | ≥ 95% | 3 consecutive fails | Auto rollback |
| P99 latency | ≤ 500ms | 3 consecutive fails | Auto rollback |
| Error count/min | < 10 | 2 fails | Auto rollback |

---

## Manual Rollback Options

```bash
# Option 1: Abort canary mid-flight (instant, zero downtime)
kubectl argo rollouts abort myapp -n canary-demo

# Option 2: Undo to previous revision
kubectl argo rollouts undo myapp -n canary-demo

# Option 3: Rollback to specific revision
kubectl argo rollouts undo myapp -n canary-demo --to-revision=1

# Option 4: Interactive menu
./scripts/rollback.sh

# Option 5: GitOps rollback (production best practice)
git revert HEAD     # reverts image tag in GitOps repo
git push            # ArgoCD picks it up automatically
```

---

## Watch the AnalysisRun fail in real time

```bash
# See the analysis run object
kubectl get analysisrun -n canary-demo --watch

# See detailed analysis results
kubectl describe analysisrun -n canary-demo

# See Argo Rollouts events
kubectl get events -n canary-demo --sort-by='.lastTimestamp'
```

---

## Promote a healthy canary (v1 → v1 again for testing)

To test the happy path (canary succeeds and promotes):

```bash
# Deploy v1 as a "new" canary (it's healthy, will pass all gates)
kubectl argo rollouts set image myapp myapp=myapp:v1 -n canary-demo

# Watch it auto-promote through all steps
kubectl argo rollouts get rollout myapp -n canary-demo --watch
```

---

## Extend this project

- **Add Grafana**: `helm install grafana grafana/grafana -n monitoring`
- **Add Slack notifications**: Add webhook in Argo Rollouts Notification ConfigMap
- **Add ArgoCD**: `kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml -n argocd`
- **Use Istio instead of Nginx**: Change `trafficRouting.nginx` to `trafficRouting.istio` in rollout.yaml
- **Add Flagger**: Alternative to Argo Rollouts with Helm-native integration
