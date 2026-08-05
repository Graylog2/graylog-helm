# Graylog Helm
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/graylog2)](https://artifacthub.io/packages/search?repo=graylog2)
[![License](https://img.shields.io/github/license/graylog2/graylog-helm)](https://github.com/graylog2/graylog-helm/blob/master/LICENSE)
![Tests](https://github.com/graylog2/graylog-helm/actions/workflows/lint-and-test.yaml/badge.svg)
[![Contributing](https://img.shields.io/badge/contributions-welcome-green.svg)](https://github.com/graylog2/graylog-helm/blob/master/CONTRIBUTING.md)

Official Helm chart for Graylog.

## Table of Contents
* [Requirements](#requirements)
  * [External Dependencies](#external-dependencies)
* [Installation](#installation)
  * [Installing on Kubernetes](#installing-on-kubernetes) 
  * [Installing on AWS EKS](#installing-on-aws-eks)
* [Post-installation](#post-installation)
  * [Set root Graylog password](#set-root-graylog-password)
  * [Reset a lost root password](#reset-a-lost-root-password)
  * [Set external access](#set-external-access)
* [Usage](#usage)
  * [Scale Graylog](#scale-graylog)
  * [Message Journal Lifecycle](#message-journal-lifecycle)
  * [Scale DataNode](#scale-datanode)
  * [Data Node Replicas and Data Redundancy](#data-node-replicas-and-data-redundancy)
  * [High Availability Defaults](#high-availability-defaults)
  * [Scale MongoDB](#scale-mongodb)
  * [MongoDB Topology](#mongodb-topology)
  * [Modify Graylog `server.conf` parameters](#modify-graylog-serverconf-parameters)
  * [Customize deployed Kubernetes resources](#customize-deployed-kubernetes-resources)
  * [Add inputs](#add-inputs)
  * [Enable TLS](#enable-tls)
* [Using External Resources](#using-external-resources)
  * [Managing Secrets Externally](#managing-secrets-externally)
  * [Bring Your Own MongoDB](#bring-your-own-mongodb)
  * [Bring Your Own OpenSearch](#bring-your-own-opensearch)
* [Hardened Environments](#hardened-environments)
* [Maintenance](#maintenance)
  * [Back Up and Restore MongoDB](#back-up-and-restore-mongodb)
* [Uninstall](#uninstall)
  * [Removing everything](#removing-everything)
* [Debugging](#debugging)
* [Logging](#logging)
* [Graylog Helm Chart Values Reference](#graylog-helm-chart-values-reference)

# Requirements
- Kubernetes **v1.32+**
- Helm **v3.0+**
- MongoDB Controllers for Kubernetes Operator **v1.6.1** (required unless a [user-provided MongoDB](#bring-your-own-mongodb) is supplied)

## Prerequisites

### Data Node

#### Kernel Parameter: vm.max_map_count

The Data Node component embeds OpenSearch, which requires the kernel parameter `vm.max_map_count` to be set to at least **262144**. 
Most cloud-managed Kubernetes clusters (EKS, GKE, AKS) default to **65530**, which will cause the Data Node to fail at startup.

**Check the current value on your cluster nodes:**
```sh
sysctl vm.max_map_count
```

**If the value is less than 262144, you have two options:**

**Option 1: Manual cluster-wide fix (recommended for existing clusters)**
```sh
# Run on each node (or via a DaemonSet)
sudo sysctl -w vm.max_map_count=262144

# Make it permanent
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

**Option 2: Automatic fix via Helm (opt-in)**
Enable the `sysctlInit` container when installing. This runs a privileged init container once during pod startup to set the kernel parameter.

**Values file approach (recommended):**
```yaml
# values.yaml
datanode:
  sysctlInit:
    enabled: true
    vmMaxMapCount: 262144  # optional, defaults to 262144
```

Then install: `helm install graylog graylog/graylog -n graylog --create-namespace -f values.yaml`

This runs a one-time privileged init container on each Data Node pod to adjust the kernel parameter. The container runs only during startup and does not affect the main application container.


The default value is **262144** (the minimum required by OpenSearch). The value must be at least 262144.
> [!NOTE]
> This does not retroactively fix nodes that already exist in your cluster; existing nodes must be updated manually.


## External Dependencies

This Helm chart is designed as a turnkey solution for quick demos and proofs of concept,
as well as streamlined production-grade setups through external dependencies.
These dependencies are not bundled with the chart and must be installed separately.

> [!WARNING]
> We do not provide support for any of these optional dependencies.
> Please refer to their respective documentation for installation, usage, and troubleshooting.

### MongoDB Operator

The official [MongoDB Controllers for Kubernetes (MCK) Operator](https://www.mongodb.com/docs/kubernetes/current/)
is the recommended method for provisioning the MongoDB replica sets required for running Graylog in production. 
This decoupled approach provides greater flexibility, improved lifecycle management, operational consistency, and 
overall production readiness.

You may also choose to [bring your own MongoDB](#bring-your-own-mongodb), but for ease of deployment as well as
improved reliability the MCK Operator remains the preferred way to deploy MongoDB and is therefore enabled by default.

### OpenSearch

The chart deploys the Graylog **Data Node** by default, which manages its own embedded OpenSearch, so no external
search backend is required. If you would rather run OpenSearch yourself — for example with the
[OpenSearch Kubernetes Operator](https://github.com/opensearch-project/opensearch-k8s-operator) — you can
[bring your own OpenSearch](#bring-your-own-opensearch) instead. The cluster must run a Graylog-supported OpenSearch
version (**2.x, up to 2.19.x** for Graylog 7.x; **3.0+ is not supported**).

### Ingress Controller

By default, the chart exposes a Kubernetes service.
However, we also recommend using an **Ingress Controller** for better management of external traffic.
If you set `ingress.enabled` to `true`, the chart will provision an Ingress resource for you.

You can use any ingress controller (e.g., NGINX, HAProxy), but make sure it's installed in your cluster beforehand.

### cert-manager

You can always [bring your own certificates](#bring-your-own-certificate-ingress-controller-recommended),
but using `cert-manager` can simplify TLS setup and certificate renewal considerably.

Make sure you have [Ingress Controller](#ingress-controller) installed, and that `ingress.enabled` is set to `true`.
Then, configure `ingress.web.tls` and `ingress.config.issuer` with the name of an existing Issuer resource,
and let `cert-manager` do the rest!

# Installation
## Pre Installation

1. If Argo CD or Flux manages this release, create the Graylog `Secret` before you install the
   chart. Then set `global.existingSecretName` to the name of that Secret. Make sure that the
   Secret contains every required key in the [Graylog Secrets](../../docs/graylog-secrets.md)
   guide. The optional keys in that guide are only necessary for the features that use them.
2. An external Secret requires an external MongoDB. Set `mongodb.communityResource.enabled=false`
   and put the connection string in `GRAYLOG_MONGODB_URI`. The chart refuses to render an external
   Secret together with the bundled MongoDB. See
   [examples/values-existing-secret-external-mongodb.yaml](../../examples/values-existing-secret-external-mongodb.yaml)
   for a complete example.

> [!CAUTION]
> Chart-generated credentials can change after the first deployment when a GitOps controller
> renders the chart. An externally managed Secret prevents this change.

## Installing on Kubernetes

### Install the official MongoDB Kubernetes Operator using Helm
```sh
helm upgrade --install mongodb-kubernetes-operator mongodb-kubernetes \
  --repo https://mongodb.github.io/helm-charts --version "1.6.1" \
  --set operator.watchNamespace="*" --reuse-values \
  --namespace operators --create-namespace
```

### Install the official Graylog Helm chart
```sh
# add the repo
helm repo add graylog https://graylog2.github.io/graylog-helm
helm repo update
```

```sh
# install the chart
helm install graylog graylog/graylog -n graylog --create-namespace
```

That's it!

## Installing on AWS EKS

When installing this chart on an existing Amazon Elastic Kubernetes Service (EKS) cluster on AWS, you must enable the
[Amazon EBS CSI Driver add-on](https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html#adding-ebs-csi-eks-add-on)
in your cluster to provision persistent volumes. The Amazon EBS CSI plugin requires Identity and Access Management (IAM) 
permissions to make calls to AWS APIs on your behalf, so be sure to
[create the corresponding IAM role](https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html), or attach the
`AmazonEBSCSIDriverPolicy` to your existing role.

### Install the official MongoDB Kubernetes Operator using Helm
```sh
helm upgrade --install mongodb-kubernetes-operator mongodb-kubernetes \
  --repo https://mongodb.github.io/helm-charts --version "1.6.1" \
  --set operator.watchNamespace="*" --reuse-values \
  --namespace operators --create-namespace
```

### Install the official Graylog Helm chart

When deploying to Amazon EKS, use the `--set provider=aws` option to enable AWS-specific configurations:

```sh
# add the repo
helm repo add graylog https://graylog2.github.io/graylog-helm
helm repo update

# install the chart
helm install graylog graylog/graylog --namespace graylog --create-namespace --set provider=aws
```

When this option is set, the chart configures a custom `gp3` StorageClass optimized for Amazon EBS volumes, 
and applies it to all PVCs managed by this chart.

Alternatively, you may also specify another existing StorageClass (e.g., `gp2`), if available in your cluster:

```sh
helm install graylog graylog/graylog --namespace graylog --create-namespace --set provider=aws --set global.storageClass=gp2
```

> [!NOTE]
> For EKS clusters version 1.30 and later, Amazon EKS no longer includes the "default" annotation on the `gp2` 
> StorageClass resource for newly created clusters. It may still be present in the cluster, but it's not marked as 
> the default storage class anymore.
> 
> The `gp3` volume type is recommended for most Amazon EBS workloads because it offers better performance and 
> cost efficiency than `gp2`, as well as independent scaling of IOPS and throughput, and higher performance limits.

# Post-Installation

## Set root Graylog password
Graylog is installed with a random password by default. It is stored in the release's
backup Secret, which survives upgrades and uninstalls, and can be printed at any time:

```sh
kubectl get secret graylog-backup-secret --namespace graylog -o jsonpath="{.data.graylog-root-password}" | base64 -d
```

If you set `graylog.config.rootPassword` (or use `global.existingSecretName`), the
chart stores only the SHA-256 hash of the password and you are responsible for keeping
the plaintext. We recommend setting a persistent password once all pods achieve the
`RUNNING` state using the following command:

```sh
echo "Enter your new password and press return:" && read -s pass
helm upgrade graylog graylog/graylog --namespace graylog --reuse-values --set "graylog.config.rootPassword=$pass"; unset pass
```

## Reset a lost root password

If the password is lost and you cannot set a new one through Helm (for example when
your values are managed by GitOps), patch the new password's SHA-256 into both
Secrets and restart Graylog:

```sh
PASS="your-new-password"
SHA=$(printf '%s' "$PASS" | sha256sum | awk '{print $1}')
SHA64=$(printf '%s' "$SHA" | base64 -w0)
kubectl patch secret graylog-secrets --namespace graylog -p "{\"data\":{\"GRAYLOG_ROOT_PASSWORD_SHA2\":\"$SHA64\"}}"
kubectl patch secret graylog-backup-secret --namespace graylog -p "{\"data\":{\"graylog-root-password-sha2\":\"$SHA64\"}}"
kubectl rollout restart statefulset graylog --namespace graylog
```

Do not delete the Secrets to force a reset. The backup Secret also holds the
password pepper (`graylog-secret`), and losing that invalidates every stored
user credential.

## Set external access

There are a number of ways to enable external access to the Graylog application. We recommend using an 
[Ingress Controller](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/) 
to provide external access both to the Graylog UI and the Graylog API, as well as any configured inputs.

Once an Ingress Controller has been installed and configured, run the following command to provision the appropriate
[Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) resource:

```sh
helm upgrade graylog graylog/graylog -n graylog --set ingress.enabled="true" --set ingress.web.enabled="true" --reuse-values
```

### Alternative: LoadBalancer Service
Alternatively, external access can be configured directly through the provided service without the need for any 
pre-existing dependencies.

```sh
helm upgrade graylog graylog/graylog -n graylog --set graylog.service.type="LoadBalancer" --reuse-values
```

### Override the public URI
The chart gives Graylog a public URI in `GRAYLOG_HTTP_EXTERNAL_URI`. Browsers and API clients use this URI.
The chart reads it from the Ingress hostname or from the LoadBalancer Service address.

These two sources are not always correct. The public URI differs from them in these cases:

- Graylog is behind a path prefix, such as `https://example.com/graylog/`.
- An external proxy or CDN answers on a different name.
- TLS ends outside the cluster, so the public scheme is `https` but the Ingress has no TLS.
- The Ingress has more than one hostname, and the first one is not the public one.

In these cases, set the URI directly:

```sh
helm upgrade graylog graylog/graylog -n graylog --set graylog.config.network.externalUri="https://logs.example.com/graylog" --reuse-values
```

This value comes before the Ingress hostnames and the LoadBalancer Service address.
Only `graylog.config.tls.cn` comes before this value, and only when `graylog.config.tls.enabled` is `true`.

Use the full URI form in all four cases. A bare hostname becomes `<scheme>://<hostname>:<port>/`.
The chart takes this scheme from `graylog.config.tls.enabled` and this port from `graylog.service.ports.app`.
Both values describe the connection to the pod, not the public endpoint.
A bare hostname is therefore not correct behind an Ingress, a proxy, a CDN, or external TLS.

### Temporary access: Port Forwarding
Finally, if you wish to enable external access _temporarily_, you can always use port forwarding:

```sh
kubectl port-forward service/graylog-svc 9000:9000 -n graylog
```

# Usage

## Scale Graylog
```sh
# scaling out: add more Graylog nodes to your cluster
helm upgrade graylog graylog/graylog -n graylog --set graylog.replicas=3 --reuse-values
```

Scaling **out** is safe and needs no procedure. Scaling **in** can lose buffered
messages — read [Message Journal Lifecycle](#message-journal-lifecycle) before you
do it.

```sh
# scaling in: remove Graylog nodes from your cluster
# WARNING: drain first. See "Message Journal Lifecycle" below.
helm upgrade graylog graylog/graylog -n graylog --set graylog.replicas=1 --reuse-values
```

## Message Journal Lifecycle

Each Graylog node buffers incoming messages in an on-disk journal on its own PVC,
then works them off into the indexer.

Rolling upgrades are safe with no procedure: the replacement pod keeps the ordinal,
re-binds the same PVC, and replays the journal. **Scale-in is not.** The ordinal
stops existing, so its PVC is retained but never mounted again, and anything left
unprocessed in that journal is unreachable. Graceful shutdown flushes memory buffers
*into* the journal; it never drains the journal *out*.

Before scaling in, drain the node. See
[Graylog Message Handling](../../docs/graylog-message-handling.md) for the runbook,
how to read a drain's logs, and what to do with the leftover PVC.

### Shutdown budget

`graylog.terminationGracePeriodSeconds` (default `300`) covers the preStop hook
**and** the SIGTERM after it. The Kubernetes default of 30s is not enough to flush
buffers under load.

### Automatic drain

Off by default. Holds pod termination while the journal is worked off, so a
scale-in has a chance to finish processing:

```sh
helm upgrade graylog graylog/graylog -n graylog \
  --set graylog.lifecycle.preStopDrain.enabled=true --reuse-values
```

It reads journal depth from the Prometheus exporter on localhost, so it needs no
credentials, but it does require `graylog.service.metrics.enabled` (the default).

It is best-effort. It cannot stop inputs, so on a node still receiving traffic the
journal never reaches zero and the hook gives up. It also cannot tell an upgrade
from a scale-in, so it slows both. Enable it if you routinely scale in.

> [!CAUTION]
> Do not enable the drain and reduce the replica count in one change. The preStop hook is
> part of the pod spec, so an existing pod does not get the hook until Kubernetes replaces
> it. Kubernetes deletes the highest-ordinal pod with its old spec, and that pod drains
> nothing.

Enable the drain before you scale in:

1. Set `graylog.lifecycle.preStopDrain.enabled=true` and keep the replica count unchanged.
2. Wait for every pod to carry the new spec. With the default
   `graylog.updateStrategy.type: RollingUpdate`, run
   `kubectl rollout status sts/graylog -n graylog`. With `OnDelete`, Kubernetes does not replace
   the pods for you: delete each one, highest ordinal first, and wait for its replacement to
   become ready before you delete the next.
3. Make sure that the highest-ordinal pod carries the hook. Run
   `kubectl get pod graylog-<n> -n graylog -o jsonpath='{.spec.containers[0].lifecycle.preStop}'`.
   An empty result means that the pod still runs the old spec. Do not scale in yet.
4. Reduce the replica count by one.

| Key | Description | Default |
|---|---|---|
| `enabled` | Hold termination while the journal drains. | `false` |
| `endpointPropagationDelaySeconds` | Sleep before the first sample, waiting for endpoint removal to propagate. If a load balancer targets pod IPs directly, increase this value and `graylog.terminationGracePeriodSeconds` by the same number of seconds. | `15` |
| `shutdownReserveSeconds` | Held back out of the grace period for Graylog's own shutdown. | `45` |
| `pollIntervalSeconds` | Seconds between journal-depth samples. | `2` |
| `stallPolls` | Give up after this many polls with no new low. | `10` |
| `confirmPolls` | Consecutive zero readings required before declaring success. | `3` |
| `metricsRetries` | Metrics probe retries before giving up. | `5` |
| `statusIntervalSeconds` | How often to log a progress line. | `10` |
| `feasibilityWarmupPolls` | Polls to observe before projecting whether the drain can finish at all; aborts early if it cannot. `0` disables. | `5` |

All under `graylog.lifecycle.preStopDrain`. The drain budget is
`terminationGracePeriodSeconds - endpointPropagationDelaySeconds - shutdownReserveSeconds`
(240s at defaults); the chart refuses to render if that is not positive.

### PVC retention

Both StatefulSets pin `persistentVolumeClaimRetentionPolicy` to `Retain`, so no
claim is deleted automatically. `graylog.persistence.retentionPolicy.whenScaled: Delete`
is **refused** — it would destroy a scaled-in node's journal. The Data Node permits
it, since shard data rebuilds from replicas.

> [!WARNING]
> Retention protects the claim from the StatefulSet controller, not from you.
> Deleting a retained PVC destroys the disk under most StorageClasses, including this
> chart's gp3 class. See
> [Deleting a leftover PVC](../../docs/graylog-message-handling.md#deleting-a-leftover-pvc).

## Scale DataNode
```sh
# scaling out: add more Graylog Data Nodes to your cluster
helm upgrade graylog graylog/graylog -n graylog --set datanode.replicas=5 --reuse-values
```

### Data Node Replicas and Data Redundancy

> [!IMPORTANT]
> Adding Data Nodes does not by itself make your log data redundant. Index set
> replicas control that, and they are configured in Graylog, not in this chart.

An index set with 0 replicas stores exactly one copy of each shard. If the Data
Node holding that shard is lost, the data is **permanently gone** — this is data
loss, not a temporary outage that resolves when the pod reschedules.

To survive the loss of a single Data Node, run at least 2 Data Nodes and set at
least 1 replica on every index set:

- **Per index set** — *System / Indices*, select the index set, then set
  *Index replicas* to `1` or higher. This applies to new indices; existing
  indices keep the replica count they were created with.
- **Default for new index sets** — set `elasticsearch_replicas` in
  `graylog.config`:

  ```yaml
  graylog:
    replicas: 2
    config:
      elasticsearch_replicas: 1
  ```

Each replica multiplies storage consumption, so size
`datanode.persistence.data.size` accordingly: N replicas means N+1 copies of
your data.

## High Availability Defaults

The chart applies these by default. Both are safe on single-node development
clusters and need no configuration for the common case.

- **Soft pod anti-affinity** on Graylog, Data Node and MongoDB pods, spreading
  each tier across nodes by `kubernetes.io/hostname`. It is
  `preferredDuringSchedulingIgnoredDuringExecution`, so pods still schedule when
  there aren't enough nodes to spread across. Setting `graylog.affinity` or
  `datanode.affinity` replaces the chart default entirely for that tier.
- **PodDisruptionBudgets** for Graylog (`minAvailable: 1`) and Data Node
  (`minAvailable: 2`), which keep node drains and cluster upgrades from evicting
  a whole tier at once. The Graylog PDB only renders at `replicas >= 2`. Disable
  with `graylog.podDisruptionBudget.enabled=false` /
  `datanode.podDisruptionBudget.enabled=false`.

> [!NOTE]
> A PDB makes node drains block rather than proceed destructively. On a cluster
> with too few nodes to satisfy `minAvailable`, a drain will wait instead of
> completing — this is the intended protection, not a failure.

## Scale MongoDB
```sh
# scaling out: add more MongoDB nodes to your replica set
helm upgrade graylog graylog/graylog -n graylog --set mongodb.replicas=4 --reuse-values
```

### MongoDB Topology

By default, the chart deploys MongoDB with a **production-recommended topology**: 3 data-bearing replicas with no arbiters. This configuration:
- Supports `w:majority` writes even with one replica down
- Handles rolling upgrades and maintenance gracefully
- Provides true high availability without cost overhead

**Example: Default production topology**
```yaml
mongodb:
  replicas: 3
  arbiters: 0
```

For **cost-optimized test/staging environments**, you may use the Primary-Secondary-Arbiter (PSA) topology instead. However, be aware that this topology is not recommended by MongoDB for production use:

```yaml
mongodb:
  replicas: 2
  arbiters: 1
```

> [!WARNING]
> With PSA topology, if one data-bearing replica fails, `w:majority` writes will stall until the member recovers.

## Modify Graylog `server.conf` parameters

```sh
# A few examples:

# change server tz
helm upgrade graylog graylog/graylog -n graylog --set graylog.config.timezone="America/Denver" --reuse-values

# set JVM options
helm upgrade graylog graylog/graylog -n graylog --set graylog.config.serverJavaOpts="-Xms1g -Xmx2g" --reuse-values

# redefine message journal maxAge
helm upgrade graylog graylog/graylog -n graylog --set graylog.config.messageJournal.maxAge="24h" --reuse-values

# enable CORS headers for HTTP interface
helm upgrade graylog graylog/graylog -n graylog --set-string graylog.config.network.enableCors=true --reuse-values

# enable email transport and set sender address
helm upgrade graylog graylog/graylog -n graylog --set-string graylog.config.email.enabled=true --set graylog.config.email.senderAddress="will@example.com" --reuse-values
```

## Customize deployed Kubernetes resources
```sh
# A few examples: 

# expose the Graylog application with a LoadBalancer service
helm upgrade graylog graylog/graylog -n graylog --set graylog.service.type="LoadBalancer" --reuse-values

# modify readiness probe initial delay
helm upgrade graylog graylog/graylog -n graylog --set graylog.readinessProbe.initialDelaySeconds=5 --reuse-values

# use a custom Storage Class for all resources (e.g. for AWS EKS)
helm upgrade graylog graylog/graylog -n graylog --set global.storageClass="gp2" --reuse-values
```

### Labels and annotations

Every object the chart deploys accepts custom labels and annotations. Set them
once with `global.commonLabels` / `global.commonAnnotations`, and use the
per-object values when only one resource needs them:

```yaml
# custom-metadata.yaml
global:
  commonLabels:
    cost-center: "1234"
    environment: production
  commonAnnotations:
    owner: observability-team

graylog:
  # StatefulSet, ConfigMaps and Secrets
  labels:
    tier: backend
  annotations:
    reloader.stakater.com/auto: "true"
  # Graylog pods only
  podLabels:
    tier: backend
  podAnnotations:
    prometheus.io/scrape: "true"
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-internal: "true"

datanode:
  labels:
    tier: storage

ingress:
  web:
    labels:
      tier: edge
```

> [!NOTE]
> MongoDB pods are the one exception. `mongodb.labels` / `mongodb.annotations`
> apply to the `MongoDBCommunity` object, but there is no `mongodb.podLabels` —
> the MongoDB Community operator owns the pod template of the StatefulSet it
> manages, labels it `app: <release>-mongo-rs-svc` and discards anything the
> chart puts there. Pod-level metadata for MongoDB has to come from the
> operator's own API.

Precedence, lowest to highest: `global.common*`, the per-object value, then the
chart's own identity labels (`app.kubernetes.io/*`, `helm.sh/chart`, `app`) and
its Helm hook and resource-policy annotations. Chart-owned values always win, so
custom metadata can never break release lifecycle handling.

> [!NOTE]
> Custom labels never reach a workload's `spec.selector`, which is immutable
> once created. They land on the object and on the pod template only, so labels
> can safely be added to a release that is already running — `helm upgrade` will
> not fail on a changed selector.

#### Immutable fields are deliberately left alone

Kubernetes accepts updates to only six StatefulSet `spec` fields: `replicas`,
`ordinals`, `template`, `updateStrategy`, `persistentVolumeClaimRetentionPolicy`
and `minReadySeconds`. Anything else — `selector` and `volumeClaimTemplates` in
particular — is rejected on update.

So the chart injects nothing into those fields. `global.commonLabels` and
`global.commonAnnotations` reach every object's own metadata and every pod
template, but they stop at `volumeClaimTemplates`. Were it otherwise, simply
upgrading to a chart version that added a label would fail for every existing
release, and would keep failing on each release after that, because the identity
labels include `helm.sh/chart` and `app.kubernetes.io/version`.

You can still label a volume claim explicitly with
`graylog.persistence.labels`, `datanode.persistence.data.labels`,
`datanode.persistence.nativeLibs.labels` or `mongodb.persistence.labels`. That is
safe on a fresh install. On a release that already exists it is a one-way door —
the StatefulSet has to be recreated, which `kubectl delete statefulset <name>
--cascade=orphan` does without touching the running pods or the PVCs.

This rule is enforced by `tests/selector_immutability_test.yaml`. If you add an
object or a metadata call site, extend that suite; for anything immutable use
the `graylog.claim.metadata` helper, never `graylog.metadata.labels`.

### Extra volumes, mounts and containers

Graylog and Data Node pods accept additional volumes, volume mounts, init
containers and sidecars:

```yaml
# extra-volumes.yaml
graylog:
  extraVolumes:
    - name: corporate-ca
      secret:
        secretName: corporate-ca
  extraVolumeMounts:
    - name: corporate-ca
      mountPath: /etc/ssl/corporate
      readOnly: true
  # the chart's copy-data init container can mount them too
  extraInitVolumeMounts:
    - name: corporate-ca
      mountPath: /mnt/ca
      readOnly: true
  extraInitContainers:
    - name: wait-for-mongodb
      image: busybox:1.37
      command: ["sh", "-c", "until nc -z graylog-mongo-rs-svc 27017; do sleep 2; done"]
  extraContainers:
    - name: log-shipper
      image: busybox:1.37
```

### Pod scheduling and runtime

Both workloads expose `nodeSelector`, `tolerations`, `affinity`,
`topologySpreadConstraints`, `priorityClassName`, `schedulerName`,
`runtimeClassName`, `terminationGracePeriodSeconds`, `dnsPolicy`, `dnsConfig`,
`hostAliases` and container `lifecycle` hooks:

```yaml
# scheduling.yaml
graylog:
  priorityClassName: high-priority
  terminationGracePeriodSeconds: 120
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          app: graylog-app
  lifecycle:
    preStop:
      exec:
        command: ["/bin/sh", "-c", "sleep 10"]
```

`topologySpreadConstraints` is the one to reach for in a multi-AZ cluster. The
chart's default anti-affinity is a *soft* hostname preference: it spreads pods
across nodes when it can, but it does not guarantee a spread across zones, so a
single-zone failure can still take every Data Node replica with it.

> [!IMPORTANT]
> On the Graylog workload, `lifecycle.preStop` and
> `lifecycle.preStopDrain.enabled` both define a preStop hook, and a container
> can only have one. Setting both fails the render rather than silently
> dropping either — see [Message journal lifecycle](#message-journal-lifecycle)
> for what the chart-managed drain does.

### Extra objects

Anything the chart does not model can be deployed alongside it with
`extraObjects`. Entries share the release lifecycle — installed, upgraded and
deleted with the chart — and are templated, so they can reference the release:

```yaml
# extra-objects.yaml
extraObjects:
  - apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: '{{ include "graylog.fullname" . }}-metrics'
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/instance: '{{ .Release.Name }}'
          app.kubernetes.io/component: server
      endpoints:
        - port: metrics
```

Entries may also be given as strings, which is the practical form when the
manifest itself contains Helm syntax that must survive to render time:

```yaml
extraObjects:
  - |
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: {{ include "graylog.fullname" . }}-extra
    data:
      namespace: {{ .Release.Namespace }}
```

`global.commonLabels` and `global.commonAnnotations` are merged into every extra
object; anything set on the object itself wins.

## Add inputs

First, define your inputs in a small YAML file like this one:

```yaml
graylog:
  inputs:
    - name: my-gelf-input
      port: 12201
      targetPort: 12201
      protocol: TCP
    - name: http1
      port: 8080
      targetPort: 8080
      protocol: TCP
```

Then, save it as `inputs.yaml`

Finally, upgrade your installation like so:
```sh
helm upgrade graylog graylog/graylog -n graylog -f inputs.yaml --reuse-values
```

The inputs should now be exposed. Make sure to complete their configuration through the Graylog UI.

## Enable TLS

Before you can enable TLS, you must associate a DNS name with your Graylog installation.
More specifically, your domain should point to the IP address/hostname associated with the service used for [External Access](#set-external-access).
You may retrieve this information like this:

```sh
kubectl get svc $SERVICE_NAME -n graylog
# look for the EXTERNAL-IP field
```

With `SERVICE_NAME` being equal to the name of the service exposed by your ingress controller, if you're using one, or
`graylog-svc` otherwise.

Depending on your setup, TLS can be enabled in three different ways:

### Option 1: Bring Your Own Certificate with Ingress Controller (recommended)

If you already have a TLS certificate-key pair, you can create a Kubernetes secret to store them:
```sh
kubectl create secret tls my-cert --cert=public.pem --key=private.key -n graylog
```

Enable TLS termination at the Ingress entrypoint for your Graylog installation, by referencing the Kubernetes secret:

```yaml
# ingress-with-tls.yaml
ingress:
  enabled: true
  web:
    enabled: true
    hosts:
      - host: graylog.hostname.example  # must match the one under 'tls'
        paths:
          - path: /
            pathType: ImplementationSpecific
    tls:
      - secretName: my-cert             # <--- reference your secret name here!
        hosts:
          - graylog.hostname.example    # must match the one under 'hosts'
```

```sh
helm upgrade graylog graylog/graylog -n graylog --reuse-values -f ingress-with-tls.yaml
```

### Option 2: Auto-issued certificates using cert-manager

> [!NOTE]
> TLS certificates issued by cert-manager are to be used in conjunction with Ingress.
> Please make sure you already have an Ingress Controller running in your cluster before proceeding.

This option allows you to enable TLS for your Graylog installation from well-known CAs,
without having to provision a TLS certificate yourself.

```yaml
# ingress-with-tls.yaml
ingress:
  enabled: true
  web:
    enabled: true
    hosts:
      - host: graylog.hostname.example  # must match the one under 'tls'
        paths:
          - path: /
            pathType: ImplementationSpecific
    tls:
      - secretName: my-autoissued-cert  # cert-manager will mount the TLS certificate issued as a secret with this name
        hosts:
          - graylog.hostname.example    # this will end up in the certificate subjectAltName. Must match the one under 'hosts'
```

```sh
helm upgrade graylog graylog/graylog -n graylog --reuse-values -f ingress-with-tls.yaml --set ingress.config.tls.issuer.existingName='<name of your existing issuer resource>'
```

> [!NOTE]
> An Issuer or ClusterIssuer resource is required for cert-manager to issue TLS certificates automatically.
> Please refer to [cert-manager docs](https://cert-manager.io/docs/) for instructions.

For convenience, this chart includes an optional built-in feature to automatically create a Let's Encrypt `Issuer` 
resource for `cert-manager`. Since issuers are typically managed by cluster administrators, this is disabled by default. 
If you prefer the Graylog chart to handle this specific issuer creation, you may enable it by setting 
`ingress.config.tls.issuer.managed.enabled=true`.

### Option 3: Bring Your Own Certificate with Graylog Native TLS

> [!IMPORTANT]
> Native TLS requires one additional SAN in your certificate: `DNS:*.graylog-svc.graylog.svc.cluster.local`
> Please, make sure your certificate includes this SAN. Otherwise, please reissue the certificate including the additional SAN.
> If your CA won't (re)issue a certificate with this SAN, please consider TLS termination at the [Ingress Controller](#ingress-controller) as an alternative.

If you already have a TLS certificate-key pair, you can create a Kubernetes secret to store them:
```sh
kubectl create secret tls my-cert --cert=public.pem --key=private.key -n graylog
```

Enable TLS for your Graylog nodes, referencing the Kubernetes secret:
```sh
helm upgrade graylog graylog/graylog -n graylog --reuse-values --set graylog.config.tls.enabled=true --set graylog.config.tls.secretName="my-cert" --set graylog.config.tls.updateKeyStore=true
```
The default set of trusted Certificate Authorities bundled in the Java Runtime for Java 17 is aligned with major,
well-known public root CAs. Make sure to set `graylog.config.tls.updateKeyStore` to `true` if you are using a
self-signed certificate, or if you think the CA that signed your certificate might not be among this default set.

## Enable Geolocation
```sh
helm upgrade graylog graylog/graylog -n graylog --reuse-values --set graylog.config.geolocation.enabled=true --set graylog.config.geolocation.maxmindGeoIp.enabled=true --set graylog.config.geolocation.maxmindGeoIp.accountId="<YOUR-MAXMIND-ACCOUNT-ID-HERE>" --set graylog.config.geolocation.maxmindGeoIp.licenseKey="<YOUR-MAXMIND-LICENSE-KEY-HERE>"
```

Use the following paths when enabling the Geo-location processor in the Graylog web UI:

- Path to the city database: `/usr/share/graylog/data/geolocation/GeoLite2-City.mmdb`
- Path to the ASN database: `/usr/share/graylog/data/geolocation/GeoLite2-ASN.mmdb`

# Using External Resources

## Managing Secrets Externally

By default, this chart manages application secrets (including MongoDB credentials) through Helm.
If you already manage secrets using an external system, you can disable Helm-managed secrets and point the chart to your existing resources.

```sh
helm upgrade -i graylog graylog/graylog -n graylog --reuse-values --set global.existingSecretName="<your secret name>"
```

> [!IMPORTANT]
> As a result of setting a global secret override, all Graylog and Mongo secrets are assumed to be managed externally.
> Accordingly, any of the following configuration values will be ignored:
> - `graylog.config.rootPassword`
> - `graylog.config.rootUsername`
> - `graylog.config.customSecretPepper`
> - `graylog.config.tls.keyPassword`

The required keys, and how to build the secret, are documented in
[Graylog Secrets](../../docs/graylog-secrets.md).

## Bring Your Own MongoDB

By default, this chart deploys a MongoDB replica set using a custom resource template, which is rendered when 
`mongodb.communityResource.enabled` is set to `true` (the default setting). The
[MongoDB Controllers for Kubernetes Operator](https://github.com/mongodb/mongodb-kubernetes) then manages the
corresponding pods.

If you prefer to use your own MongoDB instance, you can disable the custom MongoDB resource and configure the chart to
connect to your external database:
```sh
helm upgrade --install graylog graylog/graylog --namespace graylog --reuse-values \
  --set mongodb.communityResource.enabled=false \
  --set graylog.config.mongodb.customUri="mongodb[+srv]://<username>:<password>@<hostname>:<port>[,<i-th hostname>:<i-th port>]/<db name>"
```

**Alternatively**, the MongoDB URI can also be provided as part of an externally-managed secret:

```sh
helm upgrade --install graylog graylog/graylog --namespace graylog --reuse-values \
  --set mongodb.communityResource.enabled=false \
  --set global.existingSecretName="<your secret name>"
```

## Bring Your Own OpenSearch

By default, this chart deploys the **Graylog Data Node**, which manages an embedded OpenSearch for you. If you already
run — or prefer to manage separately — an OpenSearch cluster, you can disable the Data Node and point Graylog directly
at that cluster instead.

Your cluster must run a version Graylog supports (see the
[compatibility matrix](https://go2docs.graylog.org/current/downloading_and_installing_graylog/compatibility_matrix.htm)):
for Graylog 7.x that is OpenSearch **2.x, up to 2.19.x**. **OpenSearch 3.0+ is not supported.** Graylog manages its own
indices, so the cluster should be configured with `action.auto_create_index: false`. MongoDB is still required, either
bundled or [your own](#bring-your-own-mongodb).

```yaml
# disable the bundled Data Node...
datanode:
  enabled: false

# ...and point Graylog at your own OpenSearch cluster instead
opensearch:
  enabled: true
  hosts:
    - https://opensearch.my-namespace.svc.cluster.local:9200
  auth:
    existingSecret: my-opensearch-credentials
    usernameKey: username
    passwordKey: password
  tls:
    enabled: true
    caSecret: my-opensearch-ca
    caKey: ca.crt
```

The chart assembles `GRAYLOG_ELASTICSEARCH_HOSTS` (with the credentials injected into each host URI) into a dedicated
`<release>-graylog-opensearch` secret, and imports the CA from `opensearch.tls.caSecret` into Graylog's Java truststore
so the HTTPS endpoint is trusted. Because the connection lives in its own secret, this works whether or not you also
[manage secrets externally](#managing-secrets-externally).

`datanode.enabled` and `opensearch.enabled` are mutually exclusive: enabling both, enabling neither, or enabling
OpenSearch without any `hosts` is rejected at render time. All `datanode.*` values are ignored in this mode.

> [!IMPORTANT]
> `opensearch.auth.existingSecret` is resolved with Helm's `lookup`, so the secret must already exist in the release
> namespace when you install or upgrade. It cannot be read during `helm template` or `--dry-run` — including GitOps
> rendering — where the resulting host URIs will not contain credentials.

See the [Bring Your Own OpenSearch guide](../../docs/bring-your-own-opensearch.md) for credential and CA handling,
certificate rotation, and caveats.

# Hardened Environments

All workloads run with tightened pod and container security contexts by default (non-root where possible, dropped
capabilities, and `seccompProfile: RuntimeDefault`). The Graylog application is compliant with the Kubernetes
[`restricted` Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/).

Two components cannot yet meet `restricted` and need an exemption if you enforce it:

- **DataNode** must currently start as root to prepare its data directory before dropping privileges to a non-root
  user. We are working on updating the entrypoint upstream to remove this requirement; until then, the DataNode
  requires the `baseline` level (not `restricted`) or a namespace exemption.
- **MongoDB**, when provisioned by the MCK operator, runs pods that are not `restricted`-compliant. Either exempt
  them, or [bring your own MongoDB](#bring-your-own-mongodb) for hardened environments.

If you enforce [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/), set the
namespace to `baseline` rather than `restricted`, or apply the exemptions above.

# Maintenance

## Back Up and Restore MongoDB

See [the included guide](../../docs/mongodb-backup-restore.md) if you need to take a manual `mongodump` backup of 
Graylog's MongoDB database and restore it with `mongorestore`.

# Uninstall

> [!WARNING]
> A scale-in to zero replicas stops every Graylog pod. The StatefulSet does not set
> `podManagementPolicy`, so Kubernetes deletes the pods one at a time, from the highest ordinal
> down. The automatic drain is off by default, so unprocessed messages stay in the journal on
> volumes that Helm does not delete.
>
> If the release still receives traffic, stop the inputs first. Then drain each pod. See
> [Scaling in safely](../../docs/graylog-message-handling.md#scaling-in-safely).

```sh
# optional: scale Graylog down to zero, after the journals are drained
kubectl scale sts graylog -n graylog --replicas 0  && kubectl wait --for=delete pod graylog-0 -n graylog

# remove chart
helm uninstall graylog -n graylog
```

## Removing Everything
```sh
# CAUTION: this will delete ALL your data!
kubectl delete pvc,secret -n graylog --all
```

# Debugging
Get a YAML output of the values being submitted.
```bash
helm template graylog graylog -f your-custom-values.yaml | yq
```

# Logging
```sh
# Graylog app logs
stern statefulset/graylog -n graylog
# DataNode logs
stern statefulset/graylog-datanode -n graylog
```

---

# Graylog Helm Chart Values Reference

| Key Path           | Description                                                      | Default |
|--------------------|------------------------------------------------------------------|---------|
| `provider`         | Kubernetes provider (optional).                                  | `""`    |
| `version`          | Override Graylog and Graylog Data Node version (optional).       | `""`    |
| `nameOverride`     | Override the `app.kubernetes.io/name` label value (optional).    | `""`    |
| `fullnameOverride` | Override the fully qualified name of the application (optional). | `""`    |
| `extraObjects`     | Arbitrary manifests rendered with the release; each entry is templated. | `[]` |

## Global
These values affect Graylog, DataNode, and MongoDB.

| Key Path                    | Description                                 | Default |
|-----------------------------|---------------------------------------------|---------|
| `global.existingSecretName` | Reference to an existing Kubernetes secret. | `""`    |
| `global.imagePullSecrets`   | Image pull secrets for private registries.  | `[]`    |
| `global.storageClass`       | Storage class to use for PVCs.              | `""`    |
| `global.commonLabels`       | Labels added to every object deployed by this chart.      | `{}` |
| `global.commonAnnotations`  | Annotations added to every object deployed by this chart. | `{}` |

> [!NOTE]
> `global.commonLabels` and `global.commonAnnotations` are applied to *every*
> object the chart renders. The chart's own identity labels
> (`app.kubernetes.io/*`, `helm.sh/chart`, `app`) and its Helm hook/resource-policy
> annotations always win, so they cannot be overwritten by accident. Per-object
> `labels`/`annotations` values (e.g. `graylog.service.annotations`) take
> precedence over the global ones.


## Graylog application

| Key Path                                                              | Description                                                 | Default                         |
|-----------------------------------------------------------------------|-------------------------------------------------------------|---------------------------------|
| `graylog.enabled`                                                     | Enable the Graylog server.                                  | `true`                          |
| `graylog.enterprise`                                                  | Enable enterprise features.                                 | `true`                          |
| `graylog.replicas`                                                    | Number of Graylog server replicas.                          | `2`                             |
| `graylog.service.nameOverride`                                        | Override for service name.                                  | `""`                            |
| `graylog.service.type`                                                | Kubernetes service type.                                    | `ClusterIP`                     |
| `graylog.service.annotations`                                         | Annotations for the Graylog Service.                        | `{}`                            |
| `graylog.service.labels`                                              | Labels for the Graylog Service.                             | `{}`                            |
| `graylog.service.ports.app`                                           | Graylog web UI port.                                        | `9000`                          |
| `graylog.service.ports.metrics`                                       | Metrics endpoint port.                                      | `9833`                          |
| `graylog.service.metrics.enabled`                                     | Enable metrics collection.                                  | `true`                          |
| `graylog.inputs`                                                      | List of inputs to configure.                                | See below                       |
| `graylog.plugins`                                                     | List of plugins to configure.                               | See below                       |
| `graylog.env`                                                         | Custom environment variables.                               | `{}`                            |
| `graylog.config.rootUsername`                                         | Root admin username.                                        | `"admin"`                       |
| `graylog.config.rootPassword`                                         | Root admin password.                                        | `""`                            |
| `graylog.config.customSecretPepper`                                   | Internal hashing pepper (randomized when empty).            | `""`                            |
| `graylog.config.timezone`                                             | Timezone for the Graylog server.                            | `"UTC"`                         |
| `graylog.config.selfSignedStartup`                                    | Use self-signed certs on startup.                           | `"true"`                        |
| `graylog.config.serverJavaOpts`                                       | Java options for server.                                    | `"-Xms1g -Xmx1g"`               |
| `graylog.config.extraServerJavaOpts`                                  | Additional Java options for server.                         | `[]`                            |
| `graylog.config.leaderElectionMode`                                   | Mode for leader election.                                   | `"automatic"`                   |
| `graylog.config.contentPacksAutoInstall`                              | Auto-install content packs.                                 | `"true"`                        |
| `graylog.config.isCloud`                                              | Indicates if deployment is on cloud.                        | `"false"`                       |
| `graylog.config.tls.enabled`                                          | Enable TLS for Graylog.                                     | `false`                         |
| `graylog.config.tls.secretName`                                       | Name of the TLS secret.                                     | `""`                            |
| `graylog.config.tls.keyPassword`                                      | Password for the TLS key.                                   | `""`                            |
| `graylog.config.tls.updateKeyStore`                                   | Update Java keystore with TLS cert.                         | `true`                          |
| `graylog.config.tls.keyStorePass`                                     | Password for the Java keystore.                             | `"changeit"`                    |
| `graylog.config.mongodb.customUri`                                    | Custom MongoDB connection URI.                              | `""`                            |
| `graylog.config.mongodb.maxConnections`                               | Max MongoDB connections.                                    | `"1000"`                        |
| `graylog.config.mongodb.versionProbeAttempts`                         | MongoDB version probe attempts.                             | `"0"`                           |
| `graylog.config.messageJournal.enabled`                               | Enable message journal. Requires durable storage — the chart refuses to render this with `persistence.enabled=false` and no `existingClaim`, since the journal would be an `emptyDir`. A string, so disabling needs `--set-string`. | `"true"` |
| `graylog.config.messageJournal.maxSize`                                | On-disk journal cap. Must stay under 90% of `graylog.persistence.size`; the chart refuses to render otherwise. Binary suffixes — `5gb` is 5×1024³. | `"5gb"` |
| `graylog.config.messageJournal.flushAge`                              | Journal flush age.                                          | `"1m"`                          |
| `graylog.config.messageJournal.flushInterval`                         | Journal flush interval.                                     | `"1000000"`                     |
| `graylog.config.messageJournal.maxAge`                                | Max journal age.                                            | `"12h"`                         |
| `graylog.config.messageJournal.segmentAge`                            | Journal segment age.                                        | `"1h"`                          |
| `graylog.config.messageJournal.segmentSize`                           | Journal segment size.                                       | `"100mb"`                       |
| `graylog.config.network.connectTimeout`                               | Network connect timeout.                                    | `"5s"`                          |
| `graylog.config.network.enableCors`                                   | Enable CORS.                                                | `"false"`                       |
| `graylog.config.network.enableGzip`                                   | Enable Gzip compression.                                    | `"true"`                        |
| `graylog.config.network.maxHeaderSize`                                | Max header size.                                            | `"8192"`                        |
| `graylog.config.network.readTimeout`                                  | Network read timeout.                                       | `"10s"`                         |
| `graylog.config.network.threadPoolSize`                               | Network thread pool size.                                   | `"64"`                          |
| `graylog.config.network.externalUri`                                  | Public URI of the Graylog web interface. Comes before the Ingress hostnames and the LoadBalancer Service address, so upgrades do not restart the pods when the load balancer address changes. Give a full URI. A bare hostname gets the chart scheme and the app port. | `""`                            |
| `graylog.config.performance.asyncEventbusProcessors`                  | Async event bus processors.                                 | `"2"`                           |
| `graylog.config.performance.autoRestartInputs`                        | Automatically restart inputs.                               | `"false"`                       |
| `graylog.config.performance.inputBufferProcessors`                    | Input buffer processors.                                    | `"2"`                           |
| `graylog.config.performance.inputBufferRingSize`                      | Input buffer ring size.                                     | `"65536"`                       |
| `graylog.config.performance.inputBufferWaitStrategy`                  | Input buffer wait strategy.                                 | `"blocking"`                    |
| `graylog.config.performance.jobSchedulerConcurrencyLimits`            | Scheduler concurrency limits.                               | `""`                            |
| `graylog.config.performance.outputBatchSize`                          | Output batch size.                                          | `"500"`                         |
| `graylog.config.performance.outputFaultCountThreshold`                | Output fault threshold.                                     | `"5"`                           |
| `graylog.config.performance.outputFaultPenaltySeconds`                | Output fault penalty seconds.                               | `"30"`                          |
| `graylog.config.performance.outputFlushInterval`                      | Output flush interval.                                      | `"1"`                           |
| `graylog.config.performance.outputBufferProcessorThreadsCorePoolSize` | Output processor thread pool size.                          | `"3"`                           |
| `graylog.config.performance.outputBufferProcessors`                   | Output buffer processors.                                   | `""`                            |
| `graylog.config.performance.processBufferProcessors`                  | Process buffer processors.                                  | `""`                            |
| `graylog.config.email.enabled`                                        | Enable email notifications.                                 | `"false"`                       |
| `graylog.config.email.senderAddress`                                  | Email sender address.                                       | `"graylog@example.com"`         |
| `graylog.config.email.hostname`                                       | SMTP hostname.                                              | `"mail.example.com"`            |
| `graylog.config.email.port`                                           | SMTP port.                                                  | `"587"`                         |
| `graylog.config.email.socketConnectionTimeout`                        | SMTP socket connect timeout.                                | `"10s"`                         |
| `graylog.config.email.socketTimeout`                                  | SMTP socket timeout.                                        | `"10s"`                         |
| `graylog.config.email.useAuth`                                        | Use SMTP authentication.                                    | `"true"`                        |
| `graylog.config.email.useSsl`                                         | Use SSL for SMTP.                                           | `"false"`                       |
| `graylog.config.email.useTls`                                         | Use TLS for SMTP.                                           | `"true"`                        |
| `graylog.config.email.webInterfaceUrl`                                | Web interface URL for email links.                          | `"https://graylog.example.com"` |
| `graylog.config.plugins.enabled`                                      | Enable Graylog plugin system.                               | `false`                         |
| `graylog.config.geolocation.enabled`                                  | Enable the Geolocation Processor.                           | `false`                         |
| `graylog.config.geolocation.maxmindGeoIp.enabled`                     | Enable the MaxMind GeoIP update CronJob.                    | `true`                          |
| `graylog.config.geolocation.maxmindGeoIp.accountId`                   | MaxMind Account ID.                                         |                                 |
| `graylog.config.geolocation.maxmindGeoIp.licenseKey`                  | MaxMind License Key.                                        |                                 |
| `graylog.config.geolocation.maxmindGeoIp.cronSchedule`                | Cron schedule expression.                                   | `"0 0 * * *"`                   |
| `graylog.config.geolocation.maxmindGeoIp.postInstallRun`              | Enable post-installation helm hook Job.                     | `true`                          |
| `graylog.config.geolocation.mmdbSources.city.url`                     | GeoLite2-City.mmdb URL (only for initial asset fetch).      |                                 |
| `graylog.config.geolocation.mmdbSources.city.checksum`                | GeoLite2-City.mmdb checksum (only for initial asset fetch). |                                 |
| `graylog.config.geolocation.mmdbSources.asn.url`                      | GeoLite2-ASN.mmdb URL (only for initial asset fetch).       |                                 |
| `graylog.config.geolocation.mmdbSources.asn.checksum`                 | GeoLite2-ASN.mmdb checksum (only for initial asset fetch).  |                                 |
| `graylog.config.init.assetFetch.enabled`                              | Enable asset fetch init.                                    | `false`                         |
| `graylog.config.init.assetFetch.skipChecksum`                         | Skip checksum validation for assets.                        | `false`                         |
| `graylog.config.init.assetFetch.allowHttp`                            | Allow HTTP fetch for assets.                                | `false`                         |
| `graylog.config.init.assetFetch.plugins.enabled`                      | Enable plugin asset fetch.                                  | `false`                         |
| `graylog.config.init.assetFetch.plugins.baseUrl`                      | Base URL for plugin assets.                                 | `""`                            |
| `graylog.config.init.assetFetch.geolocation.enabled`                  | Enable geolocation asset fetch.                             | `false`                         |
| `graylog.config.init.assetFetch.geolocation.baseUrl`                  | Base URL for geolocation assets.                            | `""`                            |
| `graylog.image.repository`                                            | Image repository for Graylog.                               | `""`                            |
| `graylog.image.tag`                                                   | Image tag for Graylog.                                      | `""`                            |
| `graylog.image.imagePullPolicy`                                       | Pull policy for Graylog image.                              | `IfNotPresent`                  |
| `graylog.image.imagePullSecrets`                                      | Pull secrets for image.                                     | `[]`                            |
| `graylog.updateStrategy.type`                                         | Pod update strategy for StatefulSet.                        | `"RollingUpdate"`               |
| `graylog.updateStrategy.rollingUpdate.maxUnavailable`                 | Max unavailable pods during an update. Honored only where the `MaxUnavailableStatefulSet` feature gate is enabled, silently dropped otherwise. | `1`                             |
| `graylog.updateStrategy.rollingUpdate.partition`                      | Pods that will remain unaffected by the update.             | `""`                            |
| `graylog.resources.limits.cpu`                                        | CPU limit for the Graylog pod.                              | `"2"`                           |
| `graylog.resources.limits.memory`                                     | Memory limit for the Graylog pod.                           | `"2Gi"`                         |
| `graylog.resources.requests.cpu`                                      | CPU request for the Graylog pod.                            | `"1"`                           |
| `graylog.resources.requests.memory`                                   | Memory request for the Graylog pod.                         | `"1Gi"`                         |
| `graylog.persistence.enabled`                                         | Enable persistent storage.                                  | `true`                          |
| `graylog.persistence.storageClass`                                    | Storage class for the persistent volume.                    | `""`                            |
| `graylog.persistence.volumeNameOverride`                              | Override name of the persistent volume.                     | `""`                            |
| `graylog.persistence.existingClaim`                                   | Use an existing PVC.                                        | `""`                            |
| `graylog.persistence.accessModes`                                     | Access modes for the persistent volume.                     | `[]`                            |
| `graylog.persistence.size`                                            | Size of the persistent volume.                              | `""`                            |
| `graylog.persistence.annotations`                                     | Annotations for the persistent volume claim.                | `{}`                            |
| `graylog.persistence.labels`                                          | Labels for the persistent volume claim.                     | `{}`                            |
| `graylog.livenessProbe.enabled`                                       | Enable liveness probe.                                      | `true`                          |
| `graylog.livenessProbe.initialDelaySeconds`                           | Initial delay for liveness probe.                           | `60`                            |
| `graylog.livenessProbe.periodSeconds`                                 | Period between liveness probe checks.                       | `10`                            |
| `graylog.livenessProbe.timeoutSeconds`                                | Timeout for the liveness probe.                             | `5`                             |
| `graylog.livenessProbe.failureThreshold`                              | Failure threshold for the liveness probe.                   | `6`                             |
| `graylog.livenessProbe.successThreshold`                              | Success threshold for the liveness probe.                   | `1`                             |
| `graylog.readinessProbe.enabled`                                      | Enable readiness probe.                                     | `true`                          |
| `graylog.readinessProbe.initialDelaySeconds`                          | Initial delay for readiness probe.                          | `30`                            |
| `graylog.readinessProbe.periodSeconds`                                | Period between readiness probe checks.                      | `10`                            |
| `graylog.readinessProbe.timeoutSeconds`                               | Timeout for the readiness probe.                            | `5`                             |
| `graylog.readinessProbe.failureThreshold`                             | Failure threshold for the readiness probe.                  | `6`                             |
| `graylog.readinessProbe.successThreshold`                             | Success threshold for the readiness probe.                  | `1`                             |
| `graylog.terminationGracePeriodSeconds`                               | Shutdown budget before SIGKILL. Covers the preStop hook and Graylog's own graceful shutdown. | `300`  |
| `graylog.lifecycle.postStart`                                         | Your own postStart hook on the graylog-app container.       | `{}`                            |
| `graylog.lifecycle.preStop`                                           | Your own preStop hook. Mutually exclusive with `preStopDrain.enabled`. | `{}`                  |
| `graylog.lifecycle.preStopDrain.enabled`                              | Hold termination while the journal drains. See [Message Journal Lifecycle](#message-journal-lifecycle). | `false` |
| `graylog.lifecycle.preStopDrain.endpointPropagationDelaySeconds`      | Wait for EndpointSlice removal to reach kube-proxy before sampling. | `15`                     |
| `graylog.lifecycle.preStopDrain.pollIntervalSeconds`                  | Seconds between journal-depth samples.                      | `2`                             |
| `graylog.lifecycle.preStopDrain.shutdownReserveSeconds`               | Seconds reserved out of the grace period for Graylog's own shutdown. | `45`                   |
| `graylog.lifecycle.preStopDrain.stallPolls`                           | Give up after this many polls with no decrease in journal depth. | `10`                       |
| `graylog.lifecycle.preStopDrain.statusIntervalSeconds`                | How often to log a progress line during the drain.          | `10`                            |
| `graylog.lifecycle.preStopDrain.confirmPolls`                          | Consecutive zero readings required before declaring the journal drained. | `3`                |
| `graylog.lifecycle.preStopDrain.metricsRetries`                        | Retries for the metrics probe before giving up.              | `5`                             |
| `graylog.lifecycle.preStopDrain.feasibilityWarmupPolls`                | Polls observed before projecting whether the drain can finish; aborts early if it cannot. `0` disables. | `5` |
| `graylog.persistence.retentionPolicy.whenDeleted`                      | PVC fate when the StatefulSet is deleted.                   | `Retain`                        |
| `graylog.persistence.retentionPolicy.whenScaled`                       | PVC fate when scaled in. `Delete` is refused — it destroys a scaled-in node's journal. | `Retain` |
| `graylog.podDisruptionBudget.enabled`                                 | Enable PodDisruptionBudget.                                 | `false`                         |
| `graylog.podDisruptionBudget.minAvailable`                            | Minimum available pods during disruption.                   | `1`                             |
| `graylog.podDisruptionBudget.annotations`                             | Annotations for the PodDisruptionBudget.                    | `{}`                            |
| `graylog.podDisruptionBudget.labels`                                  | Labels for the PodDisruptionBudget.                         | `{}`                            |
| `graylog.annotations`                                                 | Annotations for the Graylog StatefulSet, ConfigMaps and Secrets. | `{}`                       |
| `graylog.labels`                                                      | Labels for the Graylog StatefulSet, ConfigMaps and Secrets.      | `{}`                       |
| `graylog.podAnnotations`                                              | Additional pod annotations.                                 | `{}`                            |
| `graylog.podLabels`                                                   | Additional pod labels.                                      | `{}`                            |
| `graylog.nodeSelector`                                                | Node selector for scheduling.                               | `{}`                            |
| `graylog.tolerations`                                                 | Tolerations for scheduling.                                 | `[]`                            |
| `graylog.affinity`                                                    | Affinity rules for scheduling.                              | `{}`                            |
| `graylog.topologySpreadConstraints`                                   | Topology spread constraints for the pods.                   | `[]`                            |
| `graylog.priorityClassName`                                           | PriorityClass for the pods.                                 | `""`                            |
| `graylog.schedulerName`                                               | Custom scheduler for the pods.                              | `""`                            |
| `graylog.runtimeClassName`                                            | RuntimeClass for the pods.                                  | `""`                            |
| `graylog.terminationGracePeriodSeconds`                               | Grace period before pods are force-killed.                  | `nil`                           |
| `graylog.dnsPolicy`                                                   | Pod DNS policy.                                             | `ClusterFirst`                  |
| `graylog.dnsConfig`                                                   | Pod DNS configuration.                                      | `{}`                            |
| `graylog.hostAliases`                                                 | Additional `/etc/hosts` entries for the pods.               | `[]`                            |
| `graylog.lifecycle`                                                   | Lifecycle hooks for the `graylog-app` container.            | `{}`                            |
| `graylog.extraEnv`                                                    | Custom EnvVar environment variables.                        | `[]`                            |
| `graylog.extraVolumes`                                                | Additional volumes for the Graylog pods.                    | `[]`                            |
| `graylog.extraVolumeMounts`                                           | Additional volume mounts for the `graylog-app` container.   | `[]`                            |
| `graylog.extraInitVolumeMounts`                                       | Additional volume mounts for the `copy-data` init container. | `[]`                           |
| `graylog.extraInitContainers`                                         | Additional init containers.                                 | `[]`                            |
| `graylog.extraContainers`                                             | Additional sidecar containers.                              | `[]`                            |


### Graylog inputs

| Key Path                       | Description                       | Example            |
|--------------------------------|-----------------------------------|--------------------|
| `graylog.inputs[i].name`       | Name to identify this input.      | `input-gelf`       |
| `graylog.inputs[i].port`       | Port exposed for this input.      | `12201`            |
| `graylog.inputs[i].targetPort` | Target container port (optional). | `12201`            |
| `graylog.inputs[i].protocol`   | Protocol used for this input.     | `TCP`              |

### Graylog plugins

| Key Path                           | Description                            | Example                                                            |
|------------------------------------|----------------------------------------|--------------------------------------------------------------------|
| `graylog.plugins[i].name`          | Name to identify this plugin.          | `graylog-plugin-slack`                                             |
| `graylog.plugins[i].image`         | Image containing the JAR to be copied. | `myrepo/graylog-plugin-slack:1.2.3`                                |
| `graylog.plugins[i].existingClaim` | Existing PVC with JAR to be copied.    | `myotherapp-pvc-0`                                                 |
| `graylog.plugins[i].url`           | URL of JAR to be retrieved.            | `https://myurl/plugins/graylog-plugin-slack.jar`                   |
| `graylog.plugins[i].checksum`      | Checksum of JAR file.                  | `13550350a8681c84c861aac2e5b440161c2b33a3e4f302ac680ca5b686de48de` |

### Graylog environment variables

| Key Path           | Description                                                                                                                                                                                | Example                                                                                                                                                          |
|--------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `graylog.env`      | Simple key/value environment variables                                                                                                                                                     | `graylog.env.FOO=BAR`, `graylog.env.HELLO=123`                                                                                                                   |
| `graylog.extraEnv` | [EnvVar spec](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#environment-variables)-compliant environment variables (valueFrom, configMaps, secrets, etc.) | <pre><code>extraEnv:&#10;  - name: MADE_UP_PASSWORD&#10;    valueFrom:&#10;      secretKeyRef:&#10;        name: mysecret&#10;        key: password</code></pre> |

## DataNode

| Key Path                                               | Description                                     | Default           |
|--------------------------------------------------------|-------------------------------------------------|-------------------|
| `datanode.enabled`                                     | Enable Graylog datanode.                        | `true`            |
| `datanode.replicas`                                    | Number of datanode replicas.                    | `3`               |
| `datanode.service.annotations`                         | Annotations for the Data Node Service.          | `{}`              |
| `datanode.service.labels`                              | Labels for the Data Node Service.               | `{}`              |
| `datanode.service.ports.api`                           | API communication port.                         | `8999`            |
| `datanode.service.ports.data`                          | Data communication port.                        | `9200`            |
| `datanode.service.ports.config`                        | Configuration communication port.               | `9300`            |
| `datanode.env`                                         | Custom environment variables.                   | `{}`              |
| `datanode.config.nodeIdFile`                           | Path to datanode ID file.                       | `""`              |
| `datanode.config.opensearchHeap`                       | OpenSearch heap size.                           | `"2g"`            |
| `datanode.config.javaOpts`                             | Java options for datanode.                      | `"-Xms1g -Xmx1g"` |
| `datanode.config.skipPreflightChecks`                  | Skip startup checks.                            | `"false"`         |
| `datanode.config.nodeSearchCacheSize`                  | Size of search cache.                           | `"10gb"`          |
| `datanode.config.s3ClientDefaultSecretKey`             | Default S3 client secret key.                   | `""`              |
| `datanode.config.s3ClientDefaultAccessKey`             | Default S3 client access key.                   | `""`              |
| `datanode.config.s3ClientDefaultEndpoint`              | Default S3 client endpoint.                     | `""`              |
| `datanode.config.s3ClientDefaultRegion`                | Default S3 client region.                       | `"us-east-2"`     |
| `datanode.config.s3ClientDefaultProtocol`              | Default S3 client protocol.                     | `"http"`          |
| `datanode.config.s3ClientDefaultPathStyleAccess`       | Enable path-style access for S3 client.         | `"true"`          |
| `datanode.image.repository`                            | Datanode image repository.                      | `""`              |
| `datanode.image.tag`                                   | Datanode image tag.                             | `""`              |
| `datanode.image.imagePullPolicy`                       | Image pull policy.                              | `IfNotPresent`    |
| `datanode.image.imagePullSecrets`                      | Image pull secrets.                             | `[]`              |
| `datanode.updateStrategy.type`                         | Pod update strategy for StatefulSet.            | `"RollingUpdate"` |
| `datanode.updateStrategy.rollingUpdate.maxUnavailable` | Max unavailable pods during an update. Honored only where the `MaxUnavailableStatefulSet` feature gate is enabled, silently dropped otherwise. | `1`               |
| `datanode.updateStrategy.rollingUpdate.partition`      | Pods that will remain unaffected by the update. | `""`              |
| `datanode.resources.limits.cpu`                        | CPU limit for the datanode pod.                 | `"1"`             |
| `datanode.resources.limits.memory`                     | Memory limit for the datanode pod.              | `"5Gi"`           |
| `datanode.resources.requests.cpu`                      | CPU request for the datanode pod.               | `"500m"`          |
| `datanode.resources.requests.memory`                   | Memory request for the datanode pod.            | `"3.5Gi"`         |
| `datanode.persistence.retentionPolicy.whenDeleted`     | PVC fate when the StatefulSet is deleted.       | `Retain`          |
| `datanode.persistence.retentionPolicy.whenScaled`      | PVC fate when scaled in. `Delete` is permitted here (shard data rebuilds from replicas), unlike on the Graylog StatefulSet. | `Retain` |
| `datanode.persistence.data.enabled`                    | Enable persistent volume for data.              | `true`            |
| `datanode.persistence.data.storageClass`               | Storage class for data PVC.                     | `""`              |
| `datanode.persistence.data.mountPath`                  | Mount path for data volume.                     | `""`              |
| `datanode.persistence.data.accessModes`                | Access modes for data PVC.                      | `[]`              |
| `datanode.persistence.data.size`                       | Size of the data volume.                        | `"8Gi"`           |
| `datanode.persistence.data.annotations`                | Annotations for the data PVC (globals do not apply). | `{}`         |
| `datanode.persistence.data.labels`                     | Labels for the data PVC (globals do not apply). | `{}`              |
| `datanode.persistence.nativeLibs.enabled`              | Enable persistence for native libraries.        | `false`           |
| `datanode.persistence.nativeLibs.storageClass`         | Storage class for native libs PVC.              | `""`              |
| `datanode.persistence.nativeLibs.mountPath`            | Mount path for native libs volume.              | `""`              |
| `datanode.persistence.nativeLibs.accessModes`          | Access modes for native libs PVC.               | `[]`              |
| `datanode.persistence.nativeLibs.size`                 | Size of the native libs volume.                 | `"2Gi"`           |
| `datanode.persistence.nativeLibs.annotations`          | Annotations for native libs PVC.                | `{}`              |
| `datanode.persistence.nativeLibs.labels`               | Labels for native libs PVC.                     | `{}`              |
| `datanode.livenessProbe.enabled`                       | Enable liveness probe.                          | `true`            |
| `datanode.livenessProbe.initialDelaySeconds`           | Initial delay for liveness probe.               | `30`              |
| `datanode.livenessProbe.periodSeconds`                 | Period between liveness probe checks.           | `10`              |
| `datanode.livenessProbe.timeoutSeconds`                | Timeout for the liveness probe.                 | `5`               |
| `datanode.livenessProbe.failureThreshold`              | Failure threshold for the liveness probe.       | `6`               |
| `datanode.livenessProbe.successThreshold`              | Success threshold for the liveness probe.       | `1`               |
| `datanode.readinessProbe.enabled`                      | Enable readiness probe.                         | `true`            |
| `datanode.readinessProbe.initialDelaySeconds`          | Initial delay for readiness probe.              | `10`              |
| `datanode.readinessProbe.periodSeconds`                | Period between readiness probe checks.          | `10`              |
| `datanode.readinessProbe.timeoutSeconds`               | Timeout for the readiness probe.                | `5`               |
| `datanode.readinessProbe.failureThreshold`             | Failure threshold for the readiness probe.      | `6`               |
| `datanode.readinessProbe.successThreshold`             | Success threshold for the readiness probe.      | `1`               |
| `datanode.podDisruptionBudget.enabled`                 | Enable PodDisruptionBudget.                     | `false`           |
| `datanode.podDisruptionBudget.minAvailable`            | Minimum available pods during disruption.       | `2`               |
| `datanode.podDisruptionBudget.annotations`             | Annotations for the PodDisruptionBudget.        | `{}`              |
| `datanode.podDisruptionBudget.labels`                  | Labels for the PodDisruptionBudget.             | `{}`              |
| `datanode.annotations`                                 | Annotations for the Data Node StatefulSet, ConfigMap and Secret. | `{}` |
| `datanode.labels`                                      | Labels for the Data Node StatefulSet, ConfigMap and Secret.      | `{}` |
| `datanode.podAnnotations`                              | Additional pod annotations.                     | `{}`              |
| `datanode.podLabels`                                   | Additional pod labels.                          | `{}`              |
| `datanode.nodeSelector`                                | Node selector for scheduling datanode pods.     | `{}`              |
| `datanode.tolerations`                                 | Tolerations for scheduling.                     | `[]`              |
| `datanode.affinity`                                    | Affinity rules for scheduling.                  | `{}`              |
| `datanode.topologySpreadConstraints`                   | Topology spread constraints for the pods.       | `[]`              |
| `datanode.priorityClassName`                           | PriorityClass for the pods.                     | `""`              |
| `datanode.schedulerName`                               | Custom scheduler for the pods.                  | `""`              |
| `datanode.runtimeClassName`                            | RuntimeClass for the pods.                      | `""`              |
| `datanode.terminationGracePeriodSeconds`               | Grace period before pods are force-killed.      | `nil`             |
| `datanode.dnsPolicy`                                   | Pod DNS policy.                                 | `ClusterFirst`    |
| `datanode.dnsConfig`                                   | Pod DNS configuration.                          | `{}`              |
| `datanode.hostAliases`                                 | Additional `/etc/hosts` entries for the pods.   | `[]`              |
| `datanode.lifecycle`                                   | Lifecycle hooks for the `graylog-datanode` container. | `{}`        |
| `datanode.extraEnv`                                    | Custom EnvVar environment variables.            | `[]`              |
| `datanode.extraVolumes`                                | Additional volumes for the Data Node pods.      | `[]`              |
| `datanode.extraVolumeMounts`                           | Additional volume mounts for the `graylog-datanode` container. | `[]` |
| `datanode.extraInitContainers`                         | Additional init containers.                     | `[]`              |
| `datanode.extraContainers`                             | Additional sidecar containers.                  | `[]`              |


## OpenSearch
Connect Graylog to an external, self-managed OpenSearch cluster instead of the bundled Data Node.
Mutually exclusive with `datanode.enabled`. See [Bring Your Own OpenSearch](#bring-your-own-opensearch).

| Key Path                         | Description                                                                                             | Default      |
|----------------------------------|---------------------------------------------------------------------------------------------------------|--------------|
| `opensearch.enabled`             | Enable external OpenSearch mode. Requires `datanode.enabled=false`.                                     | `false`      |
| `opensearch.hosts`               | OpenSearch node REST URIs (scheme, host and port), without credentials.                                 | `[]`         |
| `opensearch.auth.existingSecret` | Secret holding the OpenSearch username and password, read at install/upgrade time.                      | `""`         |
| `opensearch.auth.usernameKey`    | Key within `existingSecret` holding the username.                                                       | `"username"` |
| `opensearch.auth.passwordKey`    | Key within `existingSecret` holding the password.                                                       | `"password"` |
| `opensearch.auth.username`       | Inline username. Takes precedence over `existingSecret`; intended for development and testing.          | `""`         |
| `opensearch.auth.password`       | Inline password. Takes precedence over `existingSecret`; intended for development and testing.          | `""`         |
| `opensearch.tls.enabled`         | Whether the OpenSearch HTTP layer uses TLS. Set to `false` for plaintext (`http://`) hosts.             | `true`       |
| `opensearch.tls.caSecret`        | Secret containing the CA certificate for the OpenSearch HTTP layer, imported into Graylog's truststore. | `""`         |
| `opensearch.tls.caKey`           | Key within `caSecret` holding the CA certificate.                                                       | `"ca.crt"`   |


## Service Account

| Key Path                      | Description                                             | Default |
|-------------------------------|---------------------------------------------------------|---------|
| `serviceAccount.create`       | Create a new service account.                           | `true`  |
| `serviceAccount.automount`    | Automount service account token.                        | `true`  |
| `serviceAccount.annotations`  | Annotations for service account.                        | `{}`    |
| `serviceAccount.labels`       | Labels for service account.                             | `{}`    |
| `serviceAccount.nameOverride` | Override name of service account.                       | `""`    |
| `serviceAccount.role.create`  | Create a new role to bind to this service account.      | `false` |
| `serviceAccount.role.rules`   | Rules for the new role to bind to this service account. | `[]`    |
| `serviceAccount.role.annotations` | Annotations for the Role and RoleBinding.           | `{}`    |
| `serviceAccount.role.labels`  | Labels for the Role and RoleBinding.                    | `{}`    |


## Ingress

| Key Path                                        | Description                                      | Default |
|-------------------------------------------------|--------------------------------------------------|---------|
| `ingress.enabled`                               | Enable ingress resources.                        | `false` |
| `ingress.config.defaultBackend.enabled`         | Enable default backend for ingress.              | `true`  |
| `ingress.config.tls.clusterIssuer.existingName` | Name of existing ClusterIssuer for TLS.          | `""`    |
| `ingress.config.tls.issuer.existingName`        | Name of existing Issuer for TLS.                 | `""`    |
| `ingress.config.tls.issuer.annotations`         | Annotations for the chart-managed Issuer.        | `{}`    |
| `ingress.config.tls.issuer.labels`              | Labels for the chart-managed Issuer.             | `{}`    |
| `ingress.config.tls.issuer.managed.enabled`     | Enable auto-issuing of TLS certificates.         | `false` |
| `ingress.config.tls.issuer.managed.staging`     | Use staging environment for auto-issued certs.   | `true`  |

### Web Ingress

| Key Path                                 | Description                        | Default                  |
|------------------------------------------|------------------------------------|--------------------------|
| `ingress.web.enabled`                    | Enable ingress for Graylog Web.    | `false`                  |
| `ingress.web.className`                  | Ingress class name.                | `""`                     |
| `ingress.web.annotations`                | Annotations for ingress resource.  | `{}`                     |
| `ingress.web.labels`                     | Labels for ingress resource.       | `{}`                     |
| `ingress.web.hosts[0].host`              | Hostname for ingress (optional).   | `""`                     |
| `ingress.web.hosts[0].paths[0].path`     | Path for routing.                  | `/`                      |
| `ingress.web.hosts[0].paths[0].pathType` | Path matching type.                | `ImplementationSpecific` |
| `ingress.web.tls`                        | TLS configuration.                 | `[]`                     |

### Forwarder Ingress

A [Graylog Forwarder](https://go2docs.graylog.org/current/getting_in_log_data/forwarder.html) requires **both**
gRPC channels to be reachable: the message channel (port `13301`) it ships log data on, and the configuration
channel (port `13302`) it polls for configuration updates. Because the two channels listen on different ports
and an Ingress routes on host/path rather than listener port, each channel is rendered as its own Ingress
resource — `<release>-forwarder-message-channel` and `<release>-forwarder-config-channel`.

Setting `ingress.forwarder.enabled: true` enables both channels; disable one with
`ingress.forwarder.<channel>.enabled: false`.

The Forwarder is an enterprise feature and requires a valid license.

The Ingress only exposes the ports — it cannot make Graylog listen on them. A **Forwarder input** must
exist for that: an input of type **Forwarder**
(`org.graylog.plugins.forwarder.input.ForwarderServiceInput`) created under **System > Inputs**. Graylog
Cloud provisions it automatically; self-managed deployments must create it. Registering a forwarder
under **System > Forwarders** is *not* sufficient — and neither is any chart setting. Until the input
exists, `13301`/`13302` stay closed, forwarders fail with `Code=<UNAVAILABLE>`, and load balancer
targets remain unhealthy. Once it exists, Graylog binds the ports on every node.

The listener is configured by attributes **on that input**, not through `server.conf` or this chart:

| Input attribute | Default |
|---|---|
| `forwarder_bind_address` | `0.0.0.0` |
| `forwarder_message_transmission_port` | `13301` |
| `forwarder_configuration_port` | `13302` |
| `forwarder_grpc_enable_tls` | `true` |

> [!IMPORTANT]
> `forwarder_grpc_enable_tls` defaults to **true** on the input. When a load balancer terminates TLS and
> speaks cleartext HTTP/2 to Graylog — as in the ALB example above — it must be set to **false**, or the
> targets never become healthy. Set TLS on the *forwarder agent* instead, since it connects to the load
> balancer's certificate.

| Key Path                                                      | Description                                     | Default                  |
|---------------------------------------------------------------|-------------------------------------------------|--------------------------|
| `ingress.forwarder.enabled`                                   | Enable ingress for Graylog Forwarder ingest.    | `false`                  |
| `ingress.forwarder.messageChannel.enabled`                    | Expose the message channel (port `13301`).      | `true`                   |
| `ingress.forwarder.messageChannel.className`                  | Ingress class name.                             | `""`                     |
| `ingress.forwarder.messageChannel.annotations`                | Annotations for ingress resource.               | `{}`                     |
| `ingress.forwarder.messageChannel.labels`                     | Labels for ingress resource.                    | `{}`                     |
| `ingress.forwarder.messageChannel.hosts[0].host`              | Hostname for ingress (optional).                | `""`                     |
| `ingress.forwarder.messageChannel.hosts[0].paths[0].path`     | Path for routing.                               | `/`                      |
| `ingress.forwarder.messageChannel.hosts[0].paths[0].pathType` | Path matching type.                             | `ImplementationSpecific` |
| `ingress.forwarder.messageChannel.tls`                        | TLS configuration.                              | `[]`                     |
| `ingress.forwarder.configChannel.enabled`                     | Expose the configuration channel (port `13302`).| `true`                   |
| `ingress.forwarder.configChannel.className`                   | Ingress class name.                             | `""`                     |
| `ingress.forwarder.configChannel.annotations`                 | Annotations for ingress resource.               | `{}`                     |
| `ingress.forwarder.configChannel.labels`                      | Labels for ingress resource.                    | `{}`                     |
| `ingress.forwarder.configChannel.hosts[0].host`               | Hostname for ingress (optional).                | `""`                     |
| `ingress.forwarder.configChannel.hosts[0].paths[0].path`      | Path for routing.                               | `/`                      |
| `ingress.forwarder.configChannel.hosts[0].paths[0].pathType`  | Path matching type.                             | `ImplementationSpecific` |
| `ingress.forwarder.configChannel.tls`                         | TLS configuration.                              | `[]`                     |

See [`examples/forwarder-ingress.yaml`](../../examples/forwarder-ingress.yaml) for a worked AWS ALB
configuration.

## MongoDB
MongoDB Community Resource configuration.
Requires the MCK Operator: https://github.com/mongodb/mongodb-kubernetes/tree/master/docs/mongodbcommunity

| Key Path                              | Description                                                 | Default                                                                                                                                                                                                                |
|---------------------------------------|-------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `mongodb.communityResource.enabled`   | Enables creation of the `MongoDBCommunity` custom resource. | `true`                                                                                                                                                                                                                 |
| `mongodb.version`                     | MongoDB server version for the replica set.                 | `"7.0.25"`                                                                                                                                                                                                             |
| `mongodb.replicas`                    | Number of data-bearing replica set members.                 | `2`                                                                                                                                                                                                                    |
| `mongodb.arbiters`                    | Number of arbiter nodes to deploy.                          | `1`                                                                                                                                                                                                                    |
| `mongodb.annotations`                 | Annotations for the `MongoDBCommunity` object.              | `{}`                                                                                                                                                                                                                   |
| `mongodb.labels`                      | Labels for the `MongoDBCommunity` object.                   | `{}`                                                                                                                                                                                                                   |
| `mongodb.persistence.storageClass`    | StorageClass to use for persistent volumes.                 | `""`                                                                                                                                                                                                                   |
| `mongodb.persistence.size.data`       | Persistent volume size for data storage.                    | `"10G"`                                                                                                                                                                                                                |
| `mongodb.persistence.size.logs`       | Persistent volume size for MongoDB logs.                    | `"2G"`                                                                                                                                                                                                                 |
| `mongodb.persistence.annotations`     | Annotations for the MongoDB volume claim templates.         | `{}`                                                                                                                                                                                                                   |
| `mongodb.persistence.labels`          | Labels for the MongoDB volume claim templates.              | `{}`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.create`       | Create a new service account for MongoDB workloads.         | `true`                                                                                                                                                                                                                 |
| `mongodb.serviceAccount.automount`    | Automount service account token.                            | `true`                                                                                                                                                                                                                 |
| `mongodb.serviceAccount.annotations`  | Annotations for service account.                            | `{}`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.labels`       | Labels for service account.                                 | `{}`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.nameOverride` | Override name of service account.                           | `""`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.role.create`  | Create a new role to bind to this service account.          | `true`                                                                                                                                                                                                                 |
| `mongodb.serviceAccount.role.annotations` | Annotations for the Role and RoleBinding.               | `{}`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.role.labels`  | Labels for the Role and RoleBinding.                        | `{}`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.role.rules`   | Rules for the new role to bind to this service account.     | <pre><code>rules:&#10;  - apiGroups: [ "" ]&#10;    resources: [ "secrets" ]&#10;    verbs: [ "get" ]&#10;  - apiGroups: [ "" ]&#10;    resources: [ "pods" ]&#10;    verbs: [ "get", "patch", "delete" ]</code></pre> |
