# Scaling in a Data Node group

Removing Data Node pods is not a `replicas` change. It is a replica check, then a drain, then a `replicas`
change. OpenSearch will not move shards off a node just because Kubernetes is about to delete the pod, and
the StatefulSet will not wait for it.

This guide covers scaling the primary `datanode` group in, but the same steps apply to any group in
`datanode.extraNodeGroups`.

## First, check what you are actually removing

One clarification about the setup this was written against. The primary group in the deployed release is
not roleless:

```yaml
datanode:
  roles: [cluster_manager, data]
  replicas: 3
```

`roles: []` in `values.yaml` is the packaged default, but the live release overrides it. That matters,
because both of those roles change the procedure. `data` means the nodes hold shards you have to drain.
`cluster_manager` means they vote in the manager election, so you also have to touch the voting
configuration. Confirm what you have before you start:

```sh
helm get values graylog -n graylog-helm -o yaml
./osq.sh '/_cat/nodes?v&h=name,node.role,master'
```

A `node.role` of `dm` is data plus cluster_manager. Plain `d` is a data-only group, and you can skip the
voting exclusion step for it.

## Step 0: every index needs a replica

This is a prerequisite, not a nice-to-have, and it is the step that decides whether the rest of this
procedure is recoverable.

This cluster originally ran every Graylog index at `rep 0`:

```
index                          health pri rep docs.count store.size
first-index_0                  green    1   0     561063    218.4mb
graylog_0                      green    1   0     227974      65.7mb
gl-system-events_0             green    1   0          3     43.6kb
gl-failures_0                  green    1   0          0        208b
gl-events_0                    green    1   0          0        208b
investigation_event_index_0    green    1   0          0        208b
investigation_message_index_0  green    1   0          0        208b
```

`rep 0` means each primary is the only copy. Three of them sat on the group being removed, so a mistake
anywhere in the drain would have destroyed 561,000 documents with nothing to rebuild from. Note that the
cluster reported `green` throughout. Green with `rep 0` only means every primary is assigned. It says
nothing about surviving the loss of a node, which is exactly the thing you are about to do on purpose.

### What was done

Set the replica count on the existing indices:

```sh
./osq.sh -X PUT -d '{"index":{"number_of_replicas":1}}' \
  '/first-index_0,graylog_0,gl-events_0,gl-failures_0,gl-system-events_0,investigation_event_index_0,investigation_message_index_0/_settings?pretty'
```

List the indices explicitly. A wildcard like `/*/_settings` also catches `.opendistro_security` and
`.plugins-ml-config`, which run on `auto_expand_replicas` (that is why they report `rep 6`), and pinning a
fixed count on them fights the plugin that manages them.

Result, verified green with every shard doubled:

```
index                          health pri rep docs.count store.size
first-index_0                  green    1   1     735496     483.5mb
graylog_0                      green    1   1     402464     238.4mb
gl-system-events_0             green    1   1          3     87.3kb
gl-failures_0                  green    1   1          0       416b
gl-events_0                    green    1   1          0       416b
investigation_event_index_0    green    1   1          0       416b
investigation_message_index_0  green    1   1          0       416b
```

### Two follow-ups that are not optional

The `_settings` call above only fixes the indices that exist right now. It does not survive rotation.

- **Each existing index set.** Under *System / Indices*, select the set and set *Index replicas* to `1`.
  There are seven sets to walk through. Skip this and the next rotated index comes back at `rep 0`, which
  is a problem you will not notice for weeks.
- **New index sets.** Set the chart-level default so future sets inherit it:

  ```yaml
  graylog:
    config:
      elasticsearch_replicas: 1
  ```

  This supplies the default at creation time. It does nothing to sets that already exist.

Replicas are not free. One replica doubles storage, and `datanode.persistence.data.size` is 8Gi per node
here. Size the volumes for N+1 copies before the cluster carries real retention.

## What replicas change about the rest of this

The steps below are the same either way. What changes is the cost of getting one wrong.

The drain in step 2 is no longer a one-way door. At `rep 0` it was the single thing standing between you
and permanent loss. At `rep 1` a missed shard costs you a recovery, not your data. Deleting the PVCs in
step 5 becomes reversible for the same reason, since the surviving copies live on the remaining nodes.

`datanode.persistence.retentionPolicy.whenScaled: Delete` also becomes defensible. The chart gates it on
exactly this condition (`values.yaml:704`): *"Only set whenScaled=Delete if your indexes carry replicas and
the cluster is green before you scale."* You now meet both halves. I would still leave it at `Retain` and
delete the claims by hand after verifying, but that is caution rather than necessity.

> [!IMPORTANT]
> Replicas do not let you skip the drain. Scaling 3 to 0 removes three nodes in sequence, and the
> StatefulSet does not wait for OpenSearch to finish re-replicating between pods. One replica survives
> losing one node at a time, not three in a row at StatefulSet speed.

## Procedure

### 1. Exclude the group from shard allocation

Node names in OpenSearch are the full pod FQDNs. Take the whole group in one call so OpenSearch can plan
the relocations together:

```sh
./osq.sh -X PUT -d '{
  "persistent": {
    "cluster.routing.allocation.exclude._name":
      "graylog-datanode-0.graylog-datanode-svc.graylog-helm.svc.cluster.local,graylog-datanode-1.graylog-datanode-svc.graylog-helm.svc.cluster.local,graylog-datanode-2.graylog-datanode-svc.graylog-helm.svc.cluster.local"
  }
}' '/_cluster/settings?pretty'
```

Use `persistent` rather than `transient`. A transient setting is lost if the cluster manager restarts
mid-drain, which silently un-drains the nodes and leaves you thinking the drain finished.

### 2. Wait for the drain

```sh
./osq.sh '/_cat/allocation?v&h=node,shards,disk.indices'
```

Watch the three nodes fall to `0` shards. Poll it, do not guess. A few hundred megabytes over an in-cluster
network is fast, but a real install with terabytes takes hours, and `relocating_shards` in
`/_cluster/health` is the number to watch there.

Check that the remaining nodes can hold what moves. After this scale-in, 4 data nodes carry what 7 carry
now. At roughly 725mb across all copies against 8Gi per volume there is plenty of room, but redo that
arithmetic for your own cluster.

If a shard refuses to move, ask why instead of forcing it:

```sh
./osq.sh -X POST -d '{}' '/_cluster/allocation/explain?pretty'
```

The usual answer is that no remaining node has room, or that the destination would violate an allocation
filter. Both are real problems, not things to override.

> [!WARNING]
> Do not continue until those nodes report `0` shards. With replicas in place this is recoverable, but
> recovering means re-replicating everything under load, so it is still worth getting right the first time.

### 3. Exclude the group from the voting configuration

Skip this for a data-only group. For `cluster_manager` nodes, removing three of six manager-eligible nodes
without telling OpenSearch first can leave the cluster unable to elect a manager:

```sh
./osq.sh -X POST '/_cluster/voting_config_exclusions?node_names=graylog-datanode-0.graylog-datanode-svc.graylog-helm.svc.cluster.local,graylog-datanode-1.graylog-datanode-svc.graylog-helm.svc.cluster.local,graylog-datanode-2.graylog-datanode-svc.graylog-helm.svc.cluster.local'
```

Then confirm the surviving managers hold the quorum:

```sh
./osq.sh '/_cluster/state/metadata?filter_path=metadata.cluster_coordination&pretty'
```

The three dedicated `graylog-datanode-cluster-manager-*` nodes take over. Going from six eligible managers
to three is fine. Going to two would not be, so check the arithmetic for your own layout before you run
this.

### 4. Scale the group

Set the replica count in your values file and upgrade:

```yaml
datanode:
  replicas: 0
```

```sh
helm upgrade graylog graylog/graylog -n graylog-helm -f your-values.yaml
```

`replicas: 0` renders cleanly. The role guardrails in [Data Node roles and node groups](datanode-node-roles.md)
check which groups *declare* `cluster_manager`, not how many pods they run, and the `cluster-manager` extra
group satisfies that check on its own.

Edit the values file rather than running `kubectl scale`. A later `helm upgrade` would put the pods back
and undo the whole thing.

### 5. Clean up the volumes

`datanode.persistence.retentionPolicy.whenScaled` defaults to `Retain`, so the PVCs outlive the pods:

```sh
kubectl get pvc -n graylog-helm | grep 'data-graylog-datanode-[0-9]'
```

Three 8Gi gp3 volumes keep billing until you remove them. Delete them once the drain is confirmed and the
cluster is green:

```sh
kubectl delete pvc data-graylog-datanode-0 data-graylog-datanode-1 data-graylog-datanode-2 -n graylog-helm
```

### 6. Clear the exclusions

Leaving these in place means any future node that lands on those names is silently refused shards:

```sh
./osq.sh -X PUT -d '{"persistent":{"cluster.routing.allocation.exclude._name":null}}' '/_cluster/settings?pretty'
./osq.sh -X DELETE '/_cluster/voting_config_exclusions'
```

## Rolling back

Before step 5, recovery is reversing the order. Restore `replicas: 3`, upgrade, and clear the exclusions
from step 6. The pods remount the same PVCs and the shards come back.

After step 5 the volumes are gone, but with replicas in place the data is not. The cluster re-replicates
onto whatever nodes remain. Confirm with `/_cluster/health` that `unassigned_shards` is `0` before you call
it done.

## Verifying

```sh
./osq.sh '/_cluster/health?pretty'
./osq.sh '/_cat/indices?v&s=index&h=index,health,pri,rep,docs.count,store.size&expand_wildcards=all'
./osq.sh '/_cat/allocation?v&h=node,shards,disk.indices'
```

`expand_wildcards=all` matters on the second one. Without it you miss the hidden and system indices.
