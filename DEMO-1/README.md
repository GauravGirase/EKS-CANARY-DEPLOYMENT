A Canary Deployment gradually shifts traffic from a stable version of your app to a new version so you can detect problems before fully releasing it.
With Kubernetes, Argo CD, and Argo Rollouts, you can automate this process with traffic weighting and pauses.

## Architecture of Canary with Argo Rollouts
### Instead of a normal Kubernetes Deployment, Argo Rollouts uses a Rollout resource.
**Flow:**
```bash
            User Traffic
                |
            Kubernetes Service
                |
            Argo Rollout Controller
                |
        --------------------
        |                  |               
        Stable Pods   Canary Pods
        (stable img)  (new img)
```
**Traffic is gradually shifted like:**
```bash
10% -> Canary
90% -> Stable

50% -> Canary
50% -> Stable

100% -> Canary (if healthy)
```
**Note:**If errors occur → rollback automatically.
## Install Argo Rollouts
```bash
kubectl create namespace argo-rollouts

kubectl apply -n argo-rollouts -f \
https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```
### Install CLI:
```bash
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
```
**Verify:**
```bash
kubectl argo rollouts version
```
## Folder Structure
```bash
canary-demo/
 ├── rollout.yaml
 ├── service.yaml
 └── namespace.yaml
```
## Create Namespace
```bash
apiVersion: v1
kind: Namespace
metadata:
  name: canary-demo
```
## Create Kubernetes Service
```bash
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
## Create Rollout Resource (Canary Strategy)
**Replace images with your stable and buggy image.**
```bash
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: canary-demo
  namespace: canary-demo
spec:
  replicas: 5

  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause: {duration: 30s}

      - setWeight: 50
      - pause: {duration: 30s}

      - setWeight: 80
      - pause: {duration: 30s}

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
        image: myrepo/stable-app:v1
        ports:
        - containerPort: 8080
```
## Deploy the Stable Version
```bash
kubectl apply -f namespace.yaml
kubectl apply -f service.yaml
kubectl apply -f rollout.yaml
```
### Check status:
```bash
kubectl argo rollouts get rollout canary-demo -n canary-demo
```
## Deploy the Buggy Version (Start Canary)
**Update image:**
```bash
kubectl argo rollouts set image canary-demo \
canary-demo=myrepo/buggy-app:v2 \
-n canary-demo
```
**Traffic shift:**
```bash
20% -> buggy
80% -> stable

50% -> buggy
50% -> stable
```
### Watch Canary Progress
```bash
kubectl argo rollouts get rollout canary-demo -n canary-demo --watch
```
**output:**
```bash
STEP  SET-WEIGHT  PODS
1     20%         1 canary / 4 stable
2     50%         3 canary / 2 stable
3     80%         4 canary / 1 stable
```

## Manual Promotion
If everything is healthy:
```bash
kubectl argo rollouts promote canary-demo -n canary-demo
```
## Rollback if Bug Appears
```bash
kubectl argo rollouts abort canary-demo -n canary-demo
```
System immediately switches back to stable version.

## Observe Pods
```bash
kubectl get pods -n canary-demo
```
