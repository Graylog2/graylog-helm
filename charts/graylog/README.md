# Graylog Helm

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/graylog2)](https://artifacthub.io/packages/search?repo=graylog2)
[![License](https://img.shields.io/github/license/graylog2/graylog-helm)](https://github.com/graylog2/graylog-helm/blob/main/LICENSE)
![Tests](https://github.com/graylog2/graylog-helm/actions/workflows/lint-and-test.yaml/badge.svg)
[![Contributing](https://img.shields.io/badge/contributions-welcome-green.svg)](https://github.com/graylog2/graylog-helm/blob/main/CONTRIBUTING.md)

Official Helm chart for Graylog.

## Table of Contents
* [Requirements](#requirements)
  * [Data stores](#data-stores)
  * [Prerequisites](#prerequisites)
* [Installation](#installation)
  * [Pre-installation](#pre-installation)
  * [Installing on Kubernetes](#installing-on-kubernetes)
  * [Installing on AWS EKS](#installing-on-aws-eks)
* [Post-installation](#post-installation)
  * [Set root Graylog password](#set-root-graylog-password)
  * [Reset a lost root password](#reset-a-lost-root-password)
  * [Set external access](#set-external-access)
  * [Add inputs](#add-inputs)
  * [Change Graylog settings](#change-graylog-settings)
* [Guides](#guides)
* [Hardened environments](#hardened-environments)
* [Uninstall](#uninstall)
  * [Removing everything](#removing-everything)
* [Troubleshooting](#troubleshooting)
  * [Debugging](#debugging)
  * [Logging](#logging)
* [Values reference](#values-reference)

# Requirements

- Kubernetes **v1.32+**
- Helm **v3.0+**
- A MongoDB replica set and a search backend. The chart provisions both by default, and can use your own instead. See [Data stores](#data-stores).

## Data stores

Graylog keeps its configuration in MongoDB and its log messages in a search backend. The chart supports two ways to provide each.

| Store | Default | Alternative |
|---|---|---|
| MongoDB | The chart creates a `MongoDBCommunity` resource. The [MongoDB Controllers for Kubernetes (MCK) Operator](https://www.mongodb.com/docs/kubernetes/current/) **v1.6.1** must already be installed in the cluster. | [Bring your own MongoDB](../../docs/bring-your-own-mongo.md). The operator is not needed. |
| Search backend | The chart deploys the Graylog Data Node. | [Bring your own OpenSearch](../../docs/bring-your-own-opensearch.md). Disable the Data Node. |

> [!WARNING]
> We do not provide support for the MongoDB operator, or for MongoDB or OpenSearch clusters you run yourself.
> Refer to their documentation for installation, usage, and troubleshooting.

### MongoDB

MongoDB stores Graylog's metadata and configuration, not log messages. The MCK operator is the recommended way
to run the replica set in production, so the chart uses it by default. To use an existing MongoDB instead, see
[Bring your own MongoDB](../../docs/bring-your-own-mongo.md).

### Search backend

The Graylog [Data Node](https://go2docs.graylog.org/current/downloading_and_installing_graylog/install_graylog_data_node.htm)
is Graylog's managed OpenSearch. It installs the OpenSearch version Graylog needs, handles certificates and cluster
membership, and lets you add nodes without managing OpenSearch yourself. The Graylog docs call it
[the recommended search backend](https://go2docs.graylog.org/current/planning_your_deployment/the_graylog_stack.htm).
The chart deploys it by default, so no separate OpenSearch is required.

The chart also supports a self-managed OpenSearch cluster, for example one run with the
[OpenSearch Kubernetes Operator](https://github.com/opensearch-project/opensearch-k8s-operator). See
[Bring your own OpenSearch](../../docs/bring-your-own-opensearch.md). The cluster must run an OpenSearch version your Graylog
version supports. For Graylog 7.1 that is **2.x, up to 2.19.x**, and **3.0+ is not supported**. Check the
[compatibility matrix](https://go2docs.graylog.org/current/downloading_and_installing_graylog/compatibility_matrix.htm)
for other Graylog versions.

## Prerequisites

### Data Node

Skip this if you [bring your own OpenSearch](../../docs/bring-your-own-opensearch.md).

#### Kernel parameter vm.max_map_count

The Data Node embeds OpenSearch, which needs the kernel parameter `vm.max_map_count` set to at least **262144**.
Most cloud-managed Kubernetes clusters (EKS, GKE, AKS) default to **65530**, and the Data Node then fails at startup.
Check a node:

```sh
sysctl vm.max_map_count
```

If the value is lower than 262144, fix it in one of two ways.

**Option 1: set it on the nodes (recommended for existing clusters).** Run this on each node, or from a DaemonSet:

```sh
sudo sysctl -w vm.max_map_count=262144

# make it permanent
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

**Option 2: let the chart set it.** Enable the `sysctlInit` init container. It is off by default. It runs
privileged on each Data Node pod at startup, before the main container, and sets the parameter.

```yaml
datanode:
  sysctlInit:
    enabled: true
    vmMaxMapCount: 262144  # optional, 262144 is the default and the minimum
```

> [!NOTE]
> This does not retroactively fix nodes that already exist in your cluster; existing nodes must be updated manually.

# Installation
## Pre-installation

1. If Argo CD or Flux manages this release, create the Graylog `Secret` before you install the
   chart. Then set `global.existingSecretName` to the name of that Secret. Make sure that the
   Secret contains every required key in the [Graylog Secrets](../../docs/graylog-secrets.md)
   guide. The optional keys in that guide are only necessary for the features that use them.
2. An external Secret requires an external MongoDB, see
   [Bring your own MongoDB](../../docs/bring-your-own-mongo.md). Set `mongodb.communityResource.enabled=false`
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

## Installing on AWS EKS

When installing this chart on an existing Amazon Elastic Kubernetes Service (EKS) cluster on AWS, you must enable the
[Amazon EBS CSI Driver add-on](https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html#adding-ebs-csi-eks-add-on)
in your cluster to provision persistent volumes. The Amazon EBS CSI plugin requires Identity and Access Management (IAM) 
permissions to make calls to AWS APIs on your behalf, so be sure to
[create the corresponding IAM role](https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html), or attach the
`AmazonEBSCSIDriverPolicy` to your existing role.

### Install the MongoDB Kubernetes Operator

Install the operator as described in [Installing on Kubernetes](#install-the-official-mongodb-kubernetes-operator-using-helm).

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

# Post-installation

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
Secrets and restart Graylog.

The commands patch the Secrets' `data` field, so the value is base64 here, unlike
[an externally managed Secret](../../docs/graylog-secrets.md), which uses `stringData`
and takes plain text. Keep both `printf '%s'` calls. `echo` appends a newline
and the hash would not match.

```sh
PASS="your-new-password"
# macOS: shasum -a 256 instead of sha256sum, and plain `base64` (no -w flag).
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

### Temporary access: port forwarding
Finally, if you wish to enable external access _temporarily_, you can always use port forwarding:

```sh
kubectl port-forward service/graylog-svc 9000:9000 -n graylog
```

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

Save it as `inputs.yaml`, then upgrade:
```sh
helm upgrade graylog graylog/graylog -n graylog -f inputs.yaml --reuse-values
```

The inputs should now be exposed. Make sure to complete their configuration through the Graylog UI.


## Change Graylog settings

Graylog `server.conf` options live under `graylog.config`. For example, to set the time zone:

```sh
helm upgrade graylog graylog/graylog -n graylog --set graylog.config.timezone="America/Denver" --reuse-values
```

See the [values reference](VALUES.md) for every option.

# Guides

Task-specific guides live in the repository `docs/` directory.

| Guide | Covers |
|---|---|
| [Bring your own MongoDB](../../docs/bring-your-own-mongo.md) | Use a MongoDB you run instead of the operator-managed one |
| [Bring your own OpenSearch](../../docs/bring-your-own-opensearch.md) | Use an OpenSearch cluster instead of the Data Node |
| [Graylog secrets](../../docs/graylog-secrets.md) | Required keys, and managing the Secret yourself with `global.existingSecretName` |
| [Graylog message handling](../../docs/graylog-message-handling.md) | The message journal, scaling Graylog in safely, the automatic drain, leftover PVCs |
| [Scale Data Nodes](../../docs/datanode/scaling-and-redundancy.md) | Adding and removing Data Nodes, replicas, pod management policy |
| [Safe Data Node updates](../../docs/datanode/datanode-safe-updates.md) | Rolling Data Nodes one pod at a time, with run books |
| [Data Node roles](../../docs/datanode/datanode-node-roles.md) | Dedicated node groups and OpenSearch roles |
| [Health, metrics and availability](../../docs/guides/health-and-availability.md) | Probes, Prometheus metrics, anti-affinity, PodDisruptionBudgets |
| [MongoDB topology and scaling](../../docs/guides/mongodb-topology.md) | Replica count, arbiters, scaling the replica set |
| [Customize deployed resources](../../docs/guides/customization.md) | Labels, annotations, extra volumes and containers, scheduling, `extraObjects` |
| [Enable TLS](../../docs/guides/tls.md) | Ingress TLS, cert-manager, native TLS |
| [S3 credentials and archiving](../../docs/guides/s3-and-archiving.md) | Snapshot repository credentials, archive backend, IRSA |
| [Geolocation](../../docs/GeoIP_Sidecar_Deployment_Guide.md) | MaxMind GeoIP update sidecar |
| [Back up and restore MongoDB](../../docs/mongodb-backup-restore.md) | Manual `mongodump` and `mongorestore` |

# Hardened environments

All workloads run with tightened pod and container security contexts by default (non-root where possible, dropped
capabilities, and `seccompProfile: RuntimeDefault`). The Graylog application is compliant with the Kubernetes
[`restricted` Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/).

Two components cannot yet meet `restricted` and need an exemption if you enforce it:

- **DataNode** must currently start as root to prepare its data directory before dropping privileges to a non-root
  user. We are working on updating the entrypoint upstream to remove this requirement; until then, the DataNode
  requires the `baseline` level (not `restricted`) or a namespace exemption.
- **MongoDB**, when provisioned by the MCK operator, runs pods that are not `restricted`-compliant. Either exempt
  them, or [bring your own MongoDB](../../docs/bring-your-own-mongo.md) for hardened environments.

If you enforce [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/), set the
namespace to `baseline` rather than `restricted`, or apply the exemptions above.

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

## Removing everything
```sh
# CAUTION: this will delete ALL your data!
kubectl delete pvc,secret -n graylog --all
```

# Troubleshooting

## Debugging
Render the manifests locally with your values:

```sh
helm template graylog graylog/graylog -f your-custom-values.yaml | yq
```

## Logging
```sh
# Graylog app logs
stern statefulset/graylog -n graylog
# DataNode logs
stern statefulset/graylog-datanode -n graylog
```

# Values reference

Every value, with its description and default, is in [VALUES.md](VALUES.md).
