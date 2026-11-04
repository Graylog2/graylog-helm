# Scale Data Nodes

```sh
# scaling out: add more Graylog Data Nodes to your cluster
helm upgrade graylog graylog/graylog -n graylog --set datanode.replicas=5 --reuse-values
```

> [!WARNING]
> Scaling Data Nodes, up or down, restarts the Data Node pods, because every pod lists all the others in its
> discovery seed hosts. Scaling down also needs the departing nodes drained first, or their shards go offline.
> Before you scale or upgrade a production cluster, follow
> [Safe Datanode Rollouts](../datanode/datanode-safe-updates.md). It covers the run books for rolling
> one pod at a time, and it matters most with multiple node groups.

## Data Node replicas and data redundancy

> [!IMPORTANT]
> Adding Data Nodes does not by itself make your log data redundant. Index set
> replicas control that, and they are configured in Graylog, not in this chart.

An index set with 0 replicas stores exactly one copy of each shard. If the Data
Node holding that shard is lost, the data is **permanently gone**. This is data
loss, not a temporary outage that resolves when the pod reschedules.

To survive the loss of a single Data Node, run at least 2 Data Nodes and set at
least 1 replica on every index set:

- **Per index set.** In *System / Indices*, select the index set, then set
  *Index replicas* to `1` or higher. This applies to new indices; existing
  indices keep the replica count they were created with.
- **Default for new index sets.** Set `elasticsearch_replicas` in
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


## Data Node pod management

`datanode.podManagementPolicy` defaults to `OrderedReady`. `Parallel` is the
established pattern for OpenSearch-style quorum clusters, where waiting for pod
N-1 to be `Ready` before starting pod N can deadlock a cluster that needs a
quorum to become healthy in the first place.

> [!WARNING]
> `podManagementPolicy` is immutable. Kubernetes forbids updates to any
> StatefulSet spec field other than `replicas`, `ordinals`, `template`,
> `updateStrategy`, `revisionHistoryLimit`,
> `persistentVolumeClaimRetentionPolicy` and `minReadySeconds`, so changing it
> on a live release makes `helm upgrade` fail. Set it on a fresh install, or
> recreate the StatefulSet to change it:
>
> ```sh
> # --cascade=orphan leaves the running pods and their PVCs in place
> kubectl delete statefulset graylog-datanode -n graylog --cascade=orphan
> helm upgrade graylog graylog/graylog -n graylog --set datanode.podManagementPolicy=Parallel
> ```
