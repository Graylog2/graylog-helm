# Graylog Helm Chart Testing Guide

This document provides a standardized process for manually testing the Graylog Helm chart.
Follow this guide when reviewing PRs or validating internal modifications.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Testing Workflow](#testing-workflow)
  - [Phase 1: Static Validation](#phase-1-static-validation)
  - [Phase 2: Fresh Installation](#phase-2-fresh-installation)
  - [Phase 3: Automated Test Suite](#phase-3-automated-test-suite)
  - [Phase 4: Functional Verification](#phase-4-functional-verification)
  - [Phase 5: Upgrade Testing](#phase-5-upgrade-testing)
  - [Phase 6: Configuration Variants](#phase-6-configuration-variants)
- [Test Scenarios](#test-scenarios)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)
- [PR Testing Checklist](#pr-testing-checklist)

---

## Prerequisites

### Required Tools

| Tool       | Minimum Version | Purpose                                |
|------------|-----------------|----------------------------------------|
| Kubernetes | 1.32+           | Target platform                        |
| Helm       | 3.0+            | Chart deployment                       |
| kubectl    | Latest          | Cluster interaction                    |
| openssl    | 3.0+            | Generating TLS certificates (optional) |
| stern      | Any             | Log aggregation (optional)             |

### Cluster Setup

For local development, we recommend MicroK8s. See [CONTRIBUTING.md](CONTRIBUTING.md#setting-up-a-microk8s-cluster) for detailed setup instructions.

**Minimum cluster resources:**
- CPU: 8 cores
- Memory: 24 GB
- Disk: 200 GB

**Required addons/features:**
- DNS resolution
- Persistent storage (hostpath-storage or equivalent)
- MetalLB (for LoadBalancer testing)

### MongoDB Operator

The MongoDB Kubernetes Operator must be installed before deploying the chart:

```sh
helm upgrade --install mongodb-kubernetes-operator mongodb-kubernetes \
  --repo https://mongodb.github.io/helm-charts --version "1.6.1" \
  --set operator.watchNamespace="*" --reuse-values \
  --namespace operators --create-namespace
```

Verify the operator is running:

```sh
kubectl get pods -n operators -l app.kubernetes.io/name=mongodb-kubernetes-operator
```

---

## Quick Start

For a rapid validation cycle:

```sh
# 1. Static validation
helm lint ./graylog && helm template graylog ./graylog --validate

# 2. Install with minimal resources
helm upgrade -i graylog ./graylog -n graylog --create-namespace \
  --set graylog.replicas=1 \
  --set datanode.replicas=1 \
  --set mongodb.replicas=1 \
  --set mongodb.arbiters=0 \
  --wait --timeout 10m

# 3. Run automated tests
helm test graylog -n graylog

# 4. Cleanup
helm uninstall graylog -n graylog
kubectl delete pvc,secret -n graylog --all
```

---

## Testing Workflow

### Phase 1: Static Validation

Static checks validate chart syntax and structure without deploying to a cluster.

#### 1.1 Lint the Chart

```sh
helm lint ./graylog
```

**Expected:** No errors, only informational messages.

#### 1.2 Template Rendering

```sh
# Render with default values
helm template graylog ./graylog --debug > /dev/null

# Render with minimal configuration
helm template graylog ./graylog --debug \
  --set graylog.replicas=1 \
  --set datanode.replicas=1 \
  --set mongodb.replicas=1 \
  --set mongodb.arbiters=0 > /dev/null
```

**Expected:** Templates render without errors.

#### 1.3 Schema Validation

```sh
helm template graylog ./graylog --validate
```

**Expected:** All resources pass Kubernetes API validation.

#### 1.4 Dry Run

```sh
helm install graylog ./graylog --dry-run --debug --create-namespace -n graylog-test
```

**Expected:** Simulated installation completes without errors.

---

### Phase 2: Fresh Installation

#### 2.1 Install the Chart

```sh
# Create namespace and install
helm upgrade -i graylog ./graylog -n graylog --create-namespace \
  --set graylog.replicas=1 \
  --set datanode.replicas=1 \
  --set graylog.service.type=LoadBalancer
```

#### 2.2 Monitor Pod Startup

```sh
# Watch pods until all are Running
kubectl get pods -n graylog -w
```

**Expected pod states (in order of startup):**

| Pod Pattern          | Expected State | Typical Startup |
|----------------------|----------------|-----------------|
| `graylog-mongo-rs-*` | Running        | 1-2 min         |
| `graylog-datanode-*` | Running        | 2-3 min         |
| `graylog`            | Running        | 3-5 min         |

#### 2.3 Verify All Resources

```sh
# List all deployed resources
helm get all graylog -n graylog

# Check resource status
kubectl get all -n graylog
kubectl get pvc -n graylog
kubectl get secrets -n graylog
```

---

### Phase 3: Automated Test Suite

The chart includes a `helm test` suite that validates core functionality.

#### 3.1 Run All Tests

```sh
helm test graylog -n graylog
```

#### 3.2 Test Suite Details

| Test                                 | What It Validates                                             |
|--------------------------------------|---------------------------------------------------------------|
| `graylog-test-api-health`            | Graylog API responds with HTTP 200 on `/api/system/lbstatus`  |
| `graylog-test-cluster-status`        | Authentication works, cluster nodes API accessible            |
| `graylog-test-datanode-registration` | Expected number of DataNodes registered                       |
| `graylog-test-mongodb`               | MongoDB replica set is healthy with a primary                 |

#### 3.3 Run Individual Tests

To debug a failing test, run it individually:

```sh
# Check test pod status
kubectl get pods -n graylog -l "helm.sh/hook=test-success"

# View logs from a specific test
kubectl logs -n graylog graylog-test-api-health
```

---

### Phase 4: Functional Verification

These manual checks validate end-to-end functionality.

#### 4.1 Access the Web UI

```sh
# Get the external IP (LoadBalancer)
kubectl get svc graylog-svc -n graylog -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}{.status.loadBalancer.ingress[0].ip}'

# Or use port-forward
kubectl port-forward svc/graylog-svc 9000:9000 -n graylog
```

Open `http://<ip-or-hostname>:9000` in your browser.

#### 4.2 Retrieve Admin Credentials

```sh
helm status graylog -n graylog | grep -A 5 "EXTERNAL ACCESS"
```

#### 4.3 Verify Cluster Health

In the Graylog UI:

1. Navigate to **System > Cluster Configuration**
2. Verify all Graylog nodes are listed and healthy
3. Verify all DataNodes are registered and connected

#### 4.4 Test Input Configuration

1. Navigate to **System > Inputs**
2. Select **GELF TCP** from the dropdown
3. Launch a new input on port `12201`
4. Verify input starts successfully

Test the input:

```sh
# Send a test message
echo '{"version":"1.1","host":"test","short_message":"Hello Graylog"}' | nc -w1 <GRAYLOG_IP> 12201
```

#### 4.5 Verify Persistence

```sh
# Delete a Graylog pod
kubectl delete pod graylog-0 -n graylog

# Wait for pod to restart
kubectl wait --for=condition=Ready pod/graylog-0 -n graylog --timeout=5m

# Verify data persisted (check inputs still exist in UI)
```

---

### Phase 5: Upgrade Testing

#### 5.1 Value Changes

```sh
# Change a configuration value
helm upgrade graylog ./graylog -n graylog --reuse-values --set graylog.config.timezone="America/New_York"

# Verify pod restarts with new config
kubectl rollout status statefulset/graylog -n graylog
```

#### 5.2 Scaling

```sh
# Scale Graylog
helm upgrade graylog ./graylog -n graylog --reuse-values --set graylog.replicas=2

# Verify new pod joins cluster
kubectl get pods -n graylog -w

# Scale DataNode
helm upgrade graylog ./graylog -n graylog --reuse-values --set datanode.replicas=3

# Verify DataNode registers (check UI or run helm test)
helm test graylog -n graylog
```

#### 5.3 Version Upgrade (if applicable)

```sh
# Upgrade Graylog version
helm upgrade graylog ./graylog -n graylog --reuse-values --set version="7.0"

# Monitor rollout
kubectl rollout status statefulset/graylog -n graylog
kubectl rollout status statefulset/graylog-datanode -n graylog
```

---

### Phase 6: Configuration Variants

Test these configurations based on what the PR modifies:

#### 6.1 Service Types

```sh
# LoadBalancer
helm upgrade graylog ./graylog -n graylog --reuse-values --set graylog.service.type=LoadBalancer

# ClusterIP (default)
helm upgrade graylog ./graylog -n graylog --reuse-values --set graylog.service.type=ClusterIP
```

#### 6.2 Ingress

```sh
# Install NGINX ingress controller (or HAProxy, Traefik, etc.)
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace

# Enable ingress
helm upgrade graylog ./graylog -n graylog --reuse-values \
  --set ingress.enabled=true --set ingress.web.enabled=true --set ingress.web.className="nginx"

# Get the external IP
kubectl get ingress graylog-web  -n graylog -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}{.status.loadBalancer.ingress[0].ip}'
```

Open `http://<ingress-svc-ip-or-hostname>/` in your browser.

#### 6.3 TLS with Ingress Controller

```sh
export CUSTOM_HOSTNAME=<your-custom-hostname>

# Generate self-signed certificate
openssl req -newkey rsa:2048 -nodes -keyout private.key -x509 -days 7 -out public.pem -subj "/CN=${CUSTOM_HOSTNAME}"

# Create secret
kubectl create secret tls test-tls --cert=public.pem --key=private.key -n graylog

cat <<EOF > ingress-with-tls.yaml
ingress:
  web:
    enabled: true
    hosts:
      - host: $CUSTOM_HOSTNAME
        paths:
          - path: /
            pathType: ImplementationSpecific
    tls:
      - secretName: test-tls
        hosts:
          - $CUSTOM_HOSTNAME
EOF

helm upgrade graylog ./graylog -n graylog --reuse-values -f ingress-with-tls.yaml
```

Open `https://$CUSTOM_HOSTNAME/` in your browser.

#### 6.4 Graylog Native TLS

```sh
export CUSTOM_HOSTNAME=<your-custom-hostname>

# Generate self-signed certificate with additional SAN
openssl req -newkey rsa:2048 -nodes -keyout private.key -x509 -days 7 -out public.pem \
  -subj "/CN=${CUSTOM_HOSTNAME}" \
  -addext "subjectAltName = DNS:*.graylog-svc.graylog.svc.cluster.local"

# Re-create secret
kubectl delete secret test-tls -n graylog
kubectl create secret tls test-tls --cert=public.pem --key=private.key -n graylog

# Disable ingress and uninstall ingress controller
helm upgrade graylog ./graylog -n graylog --reuse-values --set ingress.enabled=false
helm uninstall ingress-nginx -n ingress-nginx

# Expose app using a LoadBalancer service
helm upgrade graylog ./graylog -n graylog --reuse-values \
  --set graylog.service.type=LoadBalancer

# Enable native TLS
helm upgrade graylog ./graylog -n graylog --reuse-values \
  --set graylog.config.tls.enabled=true \
  --set graylog.config.tls.secretName=test-tls \
  --set graylog.config.tls.updateKeyStore=true
```

#### 6.5 External MongoDB

```sh
# Install external MongoDB instance
helm install mongo mongodb \
  --repo https://charts.bitnami.com/bitnami \
  --namespace mongo --create-namespace \
  --set architecture=standalone --set persistence.enabled=false \
  --set auth.enabled=true --set auth.rootUser=root --set auth.rootPassword='foobar' \
  --set auth.usernames[0]=graylog --set auth.passwords[0]='hunter2' --set auth.databases[0]=graylog

# Disable managed MongoDB, use external
helm upgrade -i graylog ./graylog -n graylog --reset-values \
  --set graylog.replicas=1 \
  --set datanode.replicas=1 \
  --set graylog.service.type=LoadBalancer \
  --set mongodb.communityResource.enabled=false \
  --set graylog.config.mongodb.customUri="mongodb://graylog:hunter2@mongo-mongodb.mongo:27017/graylog"
```

#### 6.6 Resource Limits

```sh
# Modify resources
helm upgrade -i graylog ./graylog -n graylog --reuse-values \
  --set graylog.resources.requests.memory=2Gi \
  --set graylog.resources.limits.memory=4Gi
```

---

## Test Scenarios

### Scenario Matrix

Run these scenarios based on PR scope:

| Change Type           | Required Scenarios                          |
|-----------------------|---------------------------------------------|
| Template changes      | Static validation, fresh install, helm test |
| Values changes        | Static validation, fresh install, upgrade   |
| StatefulSet changes   | Fresh install, scaling, persistence         |
| Service changes       | Service types, ingress                      |
| Secret/Config changes | Fresh install, upgrade, external secrets    |
| MongoDB changes       | Fresh install, external MongoDB             |
| New feature           | All applicable scenarios                    |

### Minimal Test (Bug fixes, docs)

```sh
helm lint ./graylog
helm template graylog ./graylog --validate
```

### Standard Test (Most PRs)

```sh
# Static + Fresh install + Automated tests
helm lint ./graylog
helm template graylog ./graylog --validate
helm upgrade -i graylog ./graylog -n graylog --create-namespace \
--set graylog.replicas=1 --set datanode.replicas=1 --wait --timeout 10m
helm test graylog -n graylog
```

### Full Test (Major changes, releases)

Run all phases in this document.

---

## Cleanup

### Uninstall Release

```sh
helm uninstall graylog -n graylog
```

### Delete Persistent Data

```sh
# Delete PVCs (WARNING: destroys all data)
kubectl delete pvc -n graylog --all

# Delete secrets
kubectl delete secret -n graylog --all
```

### Delete Namespace

```sh
kubectl delete namespace graylog
```

### Full Reset

```sh
helm uninstall graylog -n graylog 2>/dev/null || true
kubectl delete pvc -n graylog --all 2>/dev/null || true
kubectl delete secret -n graylog --all 2>/dev/null || true
kubectl delete namespace graylog 2>/dev/null || true
```

---

## Troubleshooting

### Pod Not Starting

```sh
# Check pod events
kubectl describe pod <pod-name> -n graylog

# Check logs
kubectl logs <pod-name> -n graylog --previous

# Check PVC (status should not be "Pending")
kubectl get pvc -n graylog
```

### MongoDB Issues

```sh
# Check MongoDB operator logs
kubectl logs -n operators -l app.kubernetes.io/name=mongodb-kubernetes-operator

# Check MongoDB pod logs
kubectl logs -n graylog -l app=graylog-mongo-rs-svc
```

### DataNode Not Registering

```sh
# Check DataNode logs
kubectl logs -n graylog -l app=graylog-datanode

# Verify DataNode can reach Graylog
kubectl exec -n graylog graylog-datanode-0 -- \
  curl -s http://graylog-svc:9000/api/system/lbstatus
```

### Graylog Startup Issues

```sh
# Stream Graylog logs
stern -n graylog graylog

# Check init container logs
kubectl logs graylog-0 -n graylog -c copy-data
```

### Helm Test Failures

```sh
# Get test pod logs
kubectl logs -n graylog -l "helm.sh/hook=test-success" --all-containers

# Re-run tests with fresh pods
kubectl delete pod -n graylog -l "helm.sh/hook=test-success"
helm test graylog -n graylog
```

---

## PR Testing Checklist

```markdown
## Testing Checklist

### Static Validation
- [ ] `helm lint ./graylog` passes
- [ ] `helm template graylog ./graylog --validate` passes

### Installation
- [ ] Fresh installation completes successfully
- [ ] All pods reach Running state
- [ ] `helm test graylog -n graylog` passes

### Functional (if applicable)
- [ ] Web UI accessible and login works
- [ ] DataNodes visible in System > Data Nodes
- [ ] Inputs can be created and receive data

### Upgrade (if applicable)
- [ ] Upgrade from previous release succeeds
- [ ] Scaling up/down works correctly
- [ ] Configuration changes apply correctly

### Specific to this PR
- [ ] <describe what was specifically tested>
```

---

## Additional Resources

- [CONTRIBUTING.md](CONTRIBUTING.md) - Development setup and workflow
- [README.md](README.md) - Chart usage and configuration reference
- [Helm Testing Documentation](https://helm.sh/docs/topics/chart_tests/)