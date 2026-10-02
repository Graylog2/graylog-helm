# 🚀 Run Book: Update and Scale Up

Part of [Safe Datanode Rollouts](../datanode-safe-updates.md).

## Overview

### Steps
1. [Preflight](#every-group-step-1). Diff the render, check the cluster, dry-run.
2. [Freeze every Datanode node group](#every-group-step-2). Set each partition to its replica count so the new template applies to no pod.
3. [Helm Upgrade](#every-group-step-3). Helm writes the new template, and no pod restarts yet.
4. [Release one group at a time](#every-group-step-4), `cluster_manager` and `data` groups first. Lower the partition one ordinal at a time, highest first, and wait for green after each pod.
5. [Verification](#every-group-step-5). Verify the cluster and the StatefulSets.

## 🚦 When to Use this Run Book
Use this run book when the upgrade restarts every Data Node group, or might.

 - Any change to `datanode.*` in the values that is not limited to `datanode.extraNodeGroups.*`.
 - Adding a node group. Every group gets a longer `GRAYLOG_DATANODE_OPENSEARCH_DISCOVERY_SEED_HOSTS` and
   the shared config checksum changes, so every pod rolls even though you only edited `extraNodeGroups`.
 - An upgrade to the Graylog Helm chart version.
 - An upgrade to the Graylog application version.
 - A change to a secret that Data Node uses, such as the S3 secrets. If you manage the secret outside the chart, the pods do not restart on their own, so you must roll them manually.

See [🔄 When Datanode Has to Roll](../datanode-safe-updates.md#-when-datanode-has-to-roll) for everything that restarts a pod.

### 🛑 What Not to Do
Do not use this run book to remove pods or groups. That belongs to
[🔻 Run Book: Scaling Down Datanode](scaling-down-datanode.md), which drains the departing nodes first.

Do not run a bare `helm upgrade` before you freeze the groups. Otherwise every Datanode node group restarts at once.

## Run Book Steps
<a id="every-group-step-1"></a>

**<ins>1. Preflight.</ins>** Run all three steps in [Preflight](shared.md#preflight).

For this run book, expect every Data Node StatefulSet to differ. `replicas` should not, unless you are
scaling up. When you scale up, `replicas` rises only on the group that gains pods, and every group gets a
longer `GRAYLOG_DATANODE_OPENSEARCH_DISCOVERY_SEED_HOSTS`. Do not go on if the diff shows anything else.

<a id="every-group-step-2"></a>
**<ins>2. Freeze every Datanode node group.</ins>**

Set the partition to the replica count that is live now, so the new template applies to no pod yet. Read it
before you upgrade, because the new values may change it. List the groups with
`kubectl get statefulsets -l app=graylog-datanode`. The primary group is `<release>-datanode` and each extra
group is `<release>-datanode-<name>`.

```sh
kubectl get statefulset <sts> -o jsonpath='{.spec.replicas}'
kubectl patch statefulset <sts> --type merge \
  -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":<replicas>}}}}'
```

On a scale-up, use the old count. The new pods have ordinals at or above it, so they start on the new
template. We have not tested what happens if you use the new count.

A group you are adding has no StatefulSet yet, so there is nothing to freeze. Its pods only add capacity,
so they do not turn the cluster yellow or red. Helm creates them on the new template.

<a id="every-group-step-3"></a>
**<ins>3. Helm Upgrade.</ins>**

```sh
helm upgrade graylog graylog/graylog -n <namespace> -f <your custom values>.yaml
```

Do not set `updateStrategy.rollingUpdate.partition` in your values. The chart renders it only when it is
non-zero, which is why Helm leaves the frozen value alone.

<a id="every-group-step-4"></a>
**<ins>4. Release one group at a time.</ins>**

After the upgrade every group is still frozen. Its StatefulSet has the new pod template, but the partition
keeps every pod on the old one. A partition of `N` means Kubernetes only restarts pods with an ordinal of `N`
or higher. Lowering it by one restarts exactly one pod, which is how you control the pace.

Releasing a pod is the same three actions each time.

1. Lower the partition by one, which restarts one pod on the new template.
2. Wait for that pod to be Ready.
3. Wait for the cluster to be green.

Repeat until the partition is 0. That group is released.

> [!WARNING]
> Lower the partition by one ordinal at a time. Releasing faster can make OpenSearch unstable.

**Order**

- Release the groups with the `cluster_manager` or `data` role first. Leave every other group frozen until
  those are fully released, then release the rest in any order.
- Finish a group before you lower the partition of the next.
- Inside a group, start at the highest ordinal that existed before the upgrade and work down to 0. After a
  scale-up, the new pods already run the new template, so there is nothing to release for them.

> [!NOTE]
> A group with no `roles` set has all of them, so it counts as a `cluster_manager` and `data` group. Read
> each group's roles from `datanode.roles` and `datanode.extraNodeGroups.<name>.roles`, or from the
> `node.role` column of `GET /_cat/nodes?v&h=name,node.role,master`.

**Before the first release**

After a scale-up or an added group, the cluster rebalances shards onto the new nodes. The status stays
`green` while that happens, so green alone does not tell you it is done. Before you lower the first
partition, wait until `number_of_nodes` equals the old count plus the new pods, and `relocating_shards` and
`initializing_shards` are 0, so no pod restarts while shards are moving.

```sh
GET /_cluster/health?filter_path=status,number_of_nodes,relocating_shards,initializing_shards,unassigned_shards
```

Check the node count first. A new pod can take minutes to join, for example while it is `Pending` for a
node. Until it joins, nothing is moving yet, so `relocating_shards` reads 0 and the shards start moving
after you have begun.

See [Cluster health](../datanode-opensearch-api.md#cluster-health) for the call.

New `cluster_manager` nodes need no voting step. OpenSearch adds them to the voting configuration when they
join, and keeps the voter count odd. Only removing manager nodes needs a
[voting exclusion](scaling-down-datanode.md#removing-nodes-step-4).

> [!NOTE]
> Every existing group restarts in this run book. Point your port-forward at a pod that is not about to
> restart. After a scale-up or an added group, a new pod is the safest choice, because it already has the
> new template and no step restarts it. A forward dies when its pod does, and the health check after that
> pod returns nothing.

**Release a pod**

```sh
kubectl patch statefulset <sts> --type merge \
  -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":<ordinal>}}}}'
kubectl rollout status statefulset/<sts>
GET /_cluster/health
```

- `patch` sets the partition to `<ordinal>`. Kubernetes restarts pod `<sts>-<ordinal>` and no other.
- `rollout status` waits until that pod is Ready. It ends with `partitioned roll out complete`.
- The health call is your check. Continue only when `status` is `green` and `relocating_shards` and
  `unassigned_shards` are 0. The pod keeps its identity and its volume, so its shards reopen from local disk.

Say a group with three pods, `<sts>-0` to `<sts>-2`, is frozen at partition 3. You run the three commands
three times.

| Run | Partition set to | Pod restarted |
|---|---|---|
| 1 | 2 | `<sts>-2` |
| 2 | 1 | `<sts>-1` |
| 3 | 0 | `<sts>-0` |

After run 3 the group is released. Start the next group the same way.

How the cluster behaves depends on the roles of the group you are releasing.

- A group with the `data` role holds shards. While a pod is down, the replicas it held are unassigned and the
  status goes `yellow`. A few shards may relocate once it returns. The status stays `yellow` for a short
  while after each restart, then goes `green`. How long varies with cluster size and shard count, so wait
  it out. Do not restart the next pod while the status is `yellow`.
- The default group has no `roles` set, so each of its pods is both a `data` and a `cluster_manager` node.
  Restarting one takes shards offline and can also force a cluster manager election if it was the elected
  manager. Release this group with the most care, and expect the longest waits.
- A group with only `cluster_manager`, `ingest` or `search` holds no shards. The status stayed `green`
  after every pod in those groups. You still wait for the green check, because a manager restart can
  trigger an election.

If a pod will not become ready, stop. Read its logs, fix the values, and upgrade again. Groups you have
not reached yet stay frozen, so they do not restart.

<a id="every-group-step-5"></a>
**<ins>5. Verification.</ins>** Run [Verification](shared.md#verification).

After a scale-up or an added group, the new nodes must also be in the `GET /_cat/nodes` list.
