# Data Node Roles & Node Groups

By default, every Graylog Data Node carries all OpenSearch roles. In larger clusters
you may want to dedicate groups of Data Nodes to specific responsibilities. For example,
a dedicated `search` (warm) tier, or dedicated cluster-manager nodes.

This chart supports dedicated groups of same-role nodes through **node groups**.

## DataNode Roles

A Data Node's roles map directly to OpenSearch node roles. Valid values:

| Role                    | Responsibility                                                          |
|-------------------------|-------------------------------------------------------------------------|
| `cluster_manager`       | Cluster coordination / "control" (master-eligible).                     |
| `data`                  | Holds index shards.                                                     |
| `ingest`                | Runs ingest pipelines.                                                  |
| `remote_cluster_client` | Connects to remote clusters (cross-cluster search).                     |
| `search`                | Searchable snapshots / warm tier (requires an object store repository). |

If you leave roles unset, the Data Node uses its default set
(`cluster_manager,data,ingest,remote_cluster_client`, plus `search` is added automatically
when a snapshot repository is configured).

## Node Groups: the primary group and extra groups

- The top-level `datanode` block is the **primary node group**. `datanode.roles` sets its
  roles (empty array = the default set above). It renders the `<release>-datanode` StatefulSet.
- `datanode.extraNodeGroups` is a **map keyed by group name**. Each entry renders its own
  StatefulSet (`<release>-datanode-<name>`), ConfigMap and PodDisruptionBudget, and
  **inherits every `datanode.*` value**, overriding only what it declares.

> [!IMPORTANT]
> A group name becomes part of those object names, so it must be a **DNS-1123 label**:
> lowercase alphanumerics and `-`, starting and ending alphanumeric. Role names are not
> valid group names — `cluster_manager` is a legal *role* but an illegal *name*. Name the
> group `cluster-manager` and keep `cluster_manager` in its `roles` list. The chart rejects
> an invalid name at render time.

All groups share one headless Service for discovery, and the OpenSearch discovery seed hosts
span every group, so they form a single cluster.

### Example: hot tier + dedicated search/warm tier

```yaml
datanode:
  # Primary = hot tier
  roles: [cluster_manager, data, ingest, remote_cluster_client]
  replicas: 3
  config:
    opensearchHeap: "4g"
    # Snapshot repository required for the search role (see Data Tiering docs).
    # All three are required together, endpoint included, even on AWS S3.
    s3ClientDefaultEndpoint: "https://s3.us-east-1.amazonaws.com"
    s3ClientDefaultAccessKey: "…"
    s3ClientDefaultSecretKey: "…"
    # The remaining defaults are wrong for AWS S3 and must be overridden.
    s3ClientDefaultRegion: "us-east-1"        # default us-east-2
    s3ClientDefaultProtocol: "https"          # default http
    s3ClientDefaultPathStyleAccess: "false"   # default true
  extraNodeGroups:
    search:
      roles: [search]
      replicas: 2
      config:
        opensearchHeap: "2g"
      persistence:
        data:
          size: "500Gi"
```

### Reaching the repository without static keys

There is one way, and it is not an IAM role. The Data Node accepts a **filesystem repository**,
which needs no credentials but does need storage every Data Node can mount, such as EFS on EKS:

```yaml
datanode:
  config:
    snapshotRepositoryExternal: true
  extraEnv:
    - name: GRAYLOG_DATANODE_PATH_REPO
      value: /var/lib/graylog-datanode/repo
  extraVolumes:
    - name: snapshot-repo
      persistentVolumeClaim:
        claimName: graylog-snapshot-repo   # ReadWriteMany
  extraVolumeMounts:
    - name: snapshot-repo
      mountPath: /var/lib/graylog-datanode/repo
```

`snapshotRepositoryExternal` relaxes the chart's render-time guard and nothing else, for
repositories the chart cannot see. The Data Node still applies its own check.

> [!WARNING]
> **Granting the bucket to an IAM role does not work.** Two independent reasons, and each one is
> sufficient on its own.
>
> First, the Data Node validates its own configuration before OpenSearch starts. It looks for
> `path_repo` or S3 credentials, finds neither, and exits:
>
> ```
> Your configuration contains the search node role in node_roles but there is no
> snapshots repository configured. Please remove the role or provide path_repo or
> S3 repository credentials.
> ```
>
> Second, even past that, the `repository-s3` plugin runs under a SecurityManager whose policy
> grants `java.net.SocketPermission "*", "connect"` but only `java.io.FilePermission "config",
> "read"`. It can therefore reach instance metadata and pick up the **node's** role, but it cannot
> read the projected ServiceAccount token that IRSA depends on. The fallback is silent, so a
> repository that looks configured may quietly be using the node role.
>
> Use static keys, or a filesystem repository.

The `search` role only does something useful when a snapshot repository is configured. See
the [Data Tiering / warm tier](https://go2docs.graylog.org/current/setting_up_graylog/create_warm_tier_on_data_node.htm)
documentation.

## Guardrails

The chart validates role coverage:

- **Hard fail**: a group name that is not a DNS-1123 label, or that is long enough to push a
  pod name past 63 characters.
- **Hard fail**: the release will not render if no group is eligible to be a `cluster_manager` (i.e. every group sets
  explicit roles and none includes it).
- **Hard fail**: if a group declares the `search` role but no S3-compatible snapshot repository
  is configured. The Data Node refuses to start in that configuration, so rendering it would
  only produce a crash loop.
- **Warning**: if no group is eligible to hold `data`. Shown in the post-install notes.

Empty roles fall back to the default set, which includes `cluster_manager` and `data`.

## Migrating an existing installation to node groups

> [!IMPORTANT]
> Adding `extraNodeGroups` to a running installation relabels the primary StatefulSet's pod
> selector, and a StatefulSet's `spec.selector` is **immutable**. Patching it in place (a plain
> `helm upgrade`) is rejected by the API server:
> `updates to statefulset spec for fields other than 'replicas', … are forbidden`.

Recreate the primary `<release>-datanode` StatefulSet so the upgrade **creates** it (with the new selector) instead of 
patching it. Delete it *first*, then upgrade, in a single step. The StatefulSet will be absent only momentarily. Its
PersistentVolumeClaims are **retained**, so data is preserved:

```sh
kubectl delete statefulset graylog-datanode -n graylog \
  && helm upgrade graylog graylog/graylog -n graylog -f your-values.yaml
```

> [!NOTE]
> The default `kubectl delete` is a cascade delete, so the primary datanode pods are removed
> and then recreated by the new StatefulSet. Expect one brief restart of those pods (they
> remount the same `data-<release>-datanode-*` PVCs).

Adding groups while keeping the primary **data-capable** (i.e. roles not narrowed) is **safe**: the primary keeps its
volumes and cluster state, remains the cluster manager, and the new group's nodes join its cluster.

> [!WARNING]
> **Do not narrow a node's roles to drop `data` while reusing its data volume.** OpenSearch
> refuses to start a node that no longer has the `data` role but still has shard data on disk
> (`node does not have the data role but has shard data … Use 'opensearch-node repurpose'`).
> If you must repurpose a node, wipe (or `opensearch-node repurpose`) its data PVC first.
>
> Converting an existing all-role cluster into dedicated **manager-only** and data tiers
> replaces the manager quorum and moves data placement at the same time; this is effectively a
> **rebuild**, not an in-place migration. Plan it as a new cluster (fresh volumes) with
> snapshots/replicas to preserve data, rather than an upgrade.

## Coordinating a rollout across node groups

Each node group is its own StatefulSet, and each StatefulSet's controller rolls its
own pods independently. A value every group inherits - the image tag, a shared
`datanode.config` field, the seed host list above - changes all of their pod specs
at once, and every group starts replacing its own pod(s) at the same time. With N
groups, that is up to N Data Node pods down simultaneously, not one.

```yaml
datanode:
  rollout:
    orchestrated: true
```

This pins every node group's `updateStrategy` to `OnDelete`, so a group's own
StatefulSet controller never replaces a pod on its own. A `post-upgrade` Job takes
over instead: it walks every group's pods still on the previous revision as one
queue and replaces them strictly one at a time, waiting for each replacement to be
Ready before deleting the next. At most one Data Node pod is down across the whole
tier at any point in the rollout, no matter how many groups it spans.

`datanode.rollout.strategy` picks the queue order - `sequential` (default) finishes
one group before starting the next; `round-robin` interleaves one pod per group in
turn. Either way the Job runs with a ServiceAccount scoped to exactly this release's
node-group StatefulSets and pods (see `templates/auth/datanode-rollout-sa.yaml`),
never a namespace-wide `delete` on pods.

This is orthogonal to the seed-hosts narrowing above: `clusterManagers` (once
implemented) reduces how many pods actually need replacing on a given change;
`rollout.orchestrated` controls how the pods that *do* need replacing are sequenced,
regardless of how many that is.
