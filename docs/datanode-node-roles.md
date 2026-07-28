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
    # Snapshot repository required for the search role (see Data Tiering docs)
    s3ClientDefaultEndpoint: "https://s3.us-east-1.amazonaws.com"
    s3ClientDefaultAccessKey: "…"
    s3ClientDefaultSecretKey: "…"
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

The `search` role only does something useful when a snapshot repository is configured. See
the [Data Tiering / warm tier](https://go2docs.graylog.org/current/setting_up_graylog/create_warm_tier_on_data_node.htm)
documentation.

## Guardrails

The chart validates role coverage:

- **Hard fail**: the release will not render if no group is eligible to be a `cluster_manager` (i.e. every group sets
  explicit roles and none includes it).
- **Warning**: if no group is eligible to hold `data`. Shown in the post-install notes.
- **Warning**: if a group declares the `search` role but no S3-compatible snapshot repository is configured.

Empty roles fall back to the default set, which includes `cluster_manager` and`data`.

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
