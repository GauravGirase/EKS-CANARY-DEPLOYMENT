### Below is a complete working GitOps demo showing how to run a Canary deployment with automated rollback using:

- Kubernetes
- Argo CD
- Argo Rollouts
- Prometheus (metrics analysis)
- Grafana (monitoring dashboard)

### The demo performs automatic rollback if the buggy version has high error rate.
## Architecture
```bash
                +------------------+
                |      Argo CD     |
                |   (GitOps sync)  |
                +--------+---------+
                         |
                         v
                 Git Repository
                         |
                         v
                +------------------+
                |  Argo Rollouts   |
                | Canary Controller|
                +---------+--------+
                          |
               +----------+-----------+
               |                      |
        Stable Pods             Canary Pods
        stable:v1               buggy:v2
               |
               v
           Kubernetes Service
               |
               v
              Users

Prometheus ---> metrics
     |
     v
Argo Rollouts Analysis
     |
     v
Rollback if error rate > threshold
```
## GitOps Repository Structure
```bash
├── apps
│   └── canary-demo
│       ├── rollout.yaml
│       ├── service.yaml
│       ├── analysis-template.yaml
│       └── namespace.yaml
│
├── argocd
│   └── application.yaml
│
└── monitoring
    ├── prometheus.yaml
    └── grafana.yaml
```
## Step 1: Create cluster (KIND)
```bash
kind create cluster --name argo-demo
```
## Step 2: Install Argo CD
```bash
kubectl create namespace argocd
kubectl apply -n argocd \
-f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
**Access UI:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
**Login password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
-o jsonpath="{.data.password}" | base64 -d
```
**UI:**
```bash
https://localhost:8080
```
## Step 3: Install Argo Rollouts
```bash
kubectl create namespace argo-rollouts
```
**Install controller:**
```bash
kubectl apply -n argo-rollouts -f \
https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```
**Install CLI:**
```bash
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
```
## Step 4: Install Prometheus (for metrics)
monitoring/prometheus.yaml
```bash
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus
        ports:
        - containerPort: 9090
```
**Apply:**
```bash
kubectl apply -f monitoring/prometheus.yaml
```
**Access:**
```bash
kubectl port-forward -n monitoring deploy/prometheus --address 0.0.0.0 9090:9090
```
## Step 5: Install Grafana
monitoring/grafana.yaml
```bash
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana
        ports:
        - containerPort: 3000
```
```bash
kubectl apply -f monitoring/grafana.yaml
```
```bash
kubectl port-forward -n monitoring deploy/grafana --address 0.0.0.0 3000:3000
```
**Login:**
```bash
username: admin
password: admin
```
## Step 6: canary-demo resources
```bash
# apps/canary-demo/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: canary-demo
```
```bash
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: canary-demo
  namespace: canary-demo
spec:
  selector:
    app: canary-demo
  ports:
  - port: 80
    targetPort: 8080
```
## Step 7: Analysis Template (Auto Rollback Logic)
```bash
# apps/canary-demo/nalysis-template.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: error-rate-check
  namespace: canary-demo

spec:
  metrics:
  - name: error-rate
    interval: 30s
    successCondition: result < 0.05
    failureLimit: 3

    provider:
      prometheus:
        address: http://prometheus.monitoring:9090

        query: |
          rate(http_requests_total{status="500"}[1m])
```
**Note:** Meaning- If error rate > 5% → rollback

## Step 8: Rollout Canary Deployment (Note: No need to apply manually , argoCD applicatio will perform sync)
```bash
#apps/canary-demo/rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: canary-demo
  namespace: canary-demo

spec:
  replicas: 5

  strategy:
    canary:

      analysis:
        templates:
        - templateName: error-rate-check

      steps:
      - setWeight: 20
      - pause: {duration: 60s}

      - setWeight: 50
      - pause: {duration: 60s}

      - setWeight: 80
      - pause: {duration: 60s}

  selector:
    matchLabels:
      app: canary-demo

  template:
    metadata:
      labels:
        app: canary-demo

    spec:
      containers:
      - name: canary-demo
        image: gauravgirase/canary:v1.0.0
        ports:
        - containerPort: 8080
```
## Step 9: ArgoCD Application
```bash
# argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application

metadata:
  name: canary-demo
  namespace: argocd

spec:
  project: default

  source:
    repoURL: https://github.com/GauravGirase/EKS-CANARY-DEPLOYMENT.git
    targetRevision: HEAD
    path: DEMO-2/apps/canary-demo

  destination:
    server: https://kubernetes.default.svc
    namespace: canary-demo

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```
```bash
kubectl apply -f argocd/application.yaml
```
## Check ArgoCD UI (Add Snapshot)

**Wait for few seconds**
```bash
kubectl get pods -n canary-demo
```

## Step 10 : Trigger Canary Deployment
**Update image:**
```bash
image: gauravgirase/canary-buggy:v1.0.0
```
**ArgoCD syncs → Argo Rollouts starts canary.**
## Step 11: Watch Rollout
```bash
kubectl argo rollouts get rollout canary-demo -n canary-demo --watch
```
### Debug Commands
```bash
kubectl get pods -n canary-demo
kubectl argo rollouts get rollout canary-demo -n canary-demo
kubectl argo rollouts promote canary-demo -n canary-demo
kubectl argo rollouts abort canary-demo -n canary-demo
curl -i http://canary-demo.canary-demo.svc.cluster.local:80/api/data
curl -i http://canary-demo.canary-demo.svc.cluster.local:80/metrics
while true; do curl -s http://canary-demo.canary-demo.svc.cluster.local/api/data; sleep 0.2; done
kubectl exec -it -n monitoring prometheus-ff7885458-cf64r -- cat /etc/prometheus/prometheus.yml

# Analysis
kubectl get analysisrun -n canary-demo
kubectl describe analysisrun <analysisrun-name> -n canary-demo

```
## Step 12: Grafana Dashboard
In Grafana, Add Prometheus datasource:
```bash
http://prometheus.monitoring:9090
# query for error rate
rate(http_requests_total{status="500"}[1m])
``

10.244.0.28