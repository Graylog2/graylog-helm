# 🔻 Run Book: Scaling Down Datanode

Part of [Safe Datanode Rollouts](../datanode-safe-updates.md).

## Description
Use this run book when the upgrade leaves a group with fewer pods than it has now.

 - Lowering `datanode.replicas` for the default group.
 - Lowering `replicas` for a group under `datanode.extraNodeGroups`.
 - Retiring a whole group. See [Removing a whole node group](#removing-a-whole-node-group), which builds on
   this run book.

Do not use it to add pods or groups. That is a scale up, and it belongs to
[🚀 Update and scale up](update-and-scale-up.md). Kubernetes deletes a departing pod whether or
not its shards have moved, so this run book moves the shards first, through OpenSearch, and only for the
pods that are leaving.

A StatefulSet always removes its highest ordinals. Going from 6 replicas to 3 removes `<sts>-5`, `<sts>-4`
and `<sts>-3`. Those are the only nodes you exclude. Removing a whole group deletes its StatefulSet, so you
exclude every pod in it.

Scaling down is not only a `replicas` change. It also shortens
`GRAYLOG_DATANODE_OPENSEARCH_DISCOVERY_SEED_HOSTS` in every group, so every group that stays gets a new pod
template. A bare `helm upgrade` would restart them all at once. This run book freezes them first, the same
way [🚀 Update and scale up](update-and-scale-up.md) does.

Replicas do not let you skip the drain. The StatefulSet does not wait for OpenSearch to re-replicate
between pods, so one replica survives losing one node, not several in a row.

## Steps Overview

1. [Preflight](#removing-nodes-step-1). Diff the render, check the cluster, dry-run.
2. [Exclude the departing nodes from allocation](#removing-nodes-step-2)
3. [Wait for the drain](#removing-nodes-step-3)
4. [Voting exclusion](#removing-nodes-step-4), cluster manager nodes only.
5. [Freeze every Datanode node group that stays](#removing-nodes-step-5)
6. [Helm Upgrade](#removing-nodes-step-6). The departing pods go, and no pod that stays restarts yet.
7. [Release every group that stays](#removing-nodes-step-7), one group at a time.
8. [Clear the exclusions](#removing-nodes-step-8)
9. [Verification](#removing-nodes-step-9). Verify the cluster and the StatefulSets.

## Run Book Steps
<a id="removing-nodes-step-1"></a>
**<ins>1. Preflight.</ins>** 

Run all three steps in [Preflight](shared-runbook-steps.md#preflight).

For a removal, expect
every Data Node StatefulSet to differ. `replicas` drops only on the group that loses pods, and the
`GRAYLOG_DATANODE_OPENSEARCH_DISCOVERY_SEED_HOSTS` list loses the departing pods in every group. Do not go
on if the diff shows anything else. Also confirm that every data index has a `rep` of 1 or more.

Then check what the nodes that stay can hold, and what they can still elect.

- **Disk.** The shards on the departing nodes have to fit on the nodes that stay. Compare the `disk.indices`
  of the departing nodes with the `disk.avail` of the staying data nodes, using the
  [Shards and disk per node](../datanode-opensearch-api.md#shards-and-disk-per-node) call. Leave room
  beyond the sum. OpenSearch stops placing shards on a node at 85% disk use, so a drain that would push a node past that
  stalls.
- **Data nodes.** At least two nodes that stay must hold the `data` role, or a replica has nowhere to live.
- **Manager nodes.** Count the manager-eligible pods that stay, and see which pod is the elected manager. Every
  Data Node pod carries a `graylog-datanode-role-<role>` label with the value `true`, and a role such as
  `cluster_manager` is written with a dash. A group with no `roles` set carries the default roles, so it is
  manager-eligible and holds data. You need at least three to stay. See [step 4](#removing-nodes-step-4).
  The elected manager shows a `*` in the `master` column of `GET /_cat/nodes?v&h=name,node.role,master`.

  ```sh
  kubectl get pods -l graylog-datanode-role-cluster-manager=true
  kubectl get pods -l graylog-datanode-role-data=true
  ```

<a id="removing-nodes-step-2"></a>
**<ins>2. Exclude the departing Datanode node group members from data allocation.</ins>** 

These nodes are about to be decommissioned, so stop
OpenSearch from keeping any shards on them, and move their shards to the Datanode members that stay.

Node names are the pod FQDNs, for example
`<sts>-3.<service>.<namespace>.svc.cluster.local`. Copy the real names from `GET /_cat/nodes?h=name`. Take
every departing node in one call, so OpenSearch plans the moves together. See
[Step 2 example](#step-2-exclude-the-departing-nodes) for a filled in call and its response.

> [!TIP]
> Point your port-forward for the Datanode OpenSearch API at a pod that stays, in a group that is not losing
> pods. A forward to a departing pod dies when the pod does. Every group that stays restarts later in step 7,
> so you will move the forward again before you release its group. Any pod that stays will answer. While you
> release a group, point the forward at a pod outside that group. For the first group, that is a pod in a group
> you have not released yet.

```sh
PUT /_cluster/settings
{"persistent": {"cluster.routing.allocation.exclude._name": "<node-1>,<node-2>"}}
```

Use `persistent`. A transient setting is lost if the cluster manager restarts during the drain, which
un-drains the nodes without telling you.


<a id="removing-nodes-step-3"></a>

**<ins>3. Wait for the drain.</ins>** 

Do not go on until the cluster is green, `relocating_shards` and
`unassigned_shards` are 0, and the departing nodes hold exactly 0 shards. A departing node that has only the
`cluster_manager` role does not appear in the `_cat/allocation` list at all. It holds no shards, so treat a
missing node as 0.

```sh
GET /_cluster/health
GET /_cat/allocation?v&h=node,shards
```

See [Cluster health](../datanode-opensearch-api.md#cluster-health) and
[Shards and disk per node](../datanode-opensearch-api.md#shards-and-disk-per-node). How long the drain takes
varies with cluster size and how much data the departing nodes hold. If it stalls,
[the allocation explain call](../datanode-opensearch-api.md#why-a-shard-is-not-assigned) says why. Usually the
remaining nodes lack disk. Do not force it.

<a id="removing-nodes-step-4"></a>

**<ins>4. Voting exclusion, cluster manager nodes only.</ins>**

Skip this only when no departing pod is manager-eligible. Check the `graylog-datanode-role-cluster-manager`
label from step 1. A group with no `roles` set is manager-eligible, so removing pods from the default group needs
this step.

```sh
POST /_cluster/voting_config_exclusions?node_names=<node-1>,<node-2>
GET /_cluster/state/metadata?filter_path=metadata.cluster_coordination
```

If the departing nodes include the elected manager, it steps down and another node takes over. Check that
the surviving manager-eligible nodes still hold a majority. OpenSearch keeps the number of voters odd, so
six eligible nodes show five voters. That is normal.

Keep at least three manager-eligible nodes afterward. Going down to two cannot elect a manager. Three has
no spare. If two of them fail together, the cluster cannot elect a manager until one returns, so keep more
if you cannot accept that.

<a id="removing-nodes-step-5"></a>
**<ins>5. Freeze every Datanode node group that stays.</ins>** 


Set the partition to the replica count that is live now, so the new
template applies to no pod yet. Read it before you upgrade. What a group needs depends on what the upgrade does to it.

- It loses some pods. Freeze it at its old count, which is above the new `replicas`. Kubernetes still
  removes the extra pods and leaves the rest alone. Step 7 releases the pods that stay.
- It goes to 0, whether its key stays or is deleted in this upgrade. Do not freeze it. No pod in it
  survives, so there is nothing to protect, and a freeze would leave a stale partition behind.

```sh
kubectl get statefulset <sts> -o jsonpath='{.spec.replicas}'
kubectl patch statefulset <sts> --type merge \
  -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":<replicas>}}}}'
```

<a id="removing-nodes-step-6"></a>
**<ins>6. Helm Upgrade.</ins>**

```sh
helm upgrade graylog graylog/graylog -n <namespace> -f <your custom values>.yaml
```

The departing pods go and no pod that stays restarts yet. Check `kubectl get pods` before you go on.

<a id="removing-nodes-step-7"></a>
**<ins>7. Release every group that stays, one group at a time.</ins>** 

After the upgrade every group is still frozen,
including groups that lost no pods, because the shorter seed hosts list changed their template too. A group
stays on the old template until you lower its partition to 0. Releasing the groups that lost pods is not
enough.

Get the full list of groups and release every one.

```sh
kubectl get statefulsets -l app=graylog-datanode \
  -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,PARTITION:.spec.updateStrategy.rollingUpdate.partition
```

Release the groups that have the `cluster_manager` or `data` role first, and leave the others frozen until
those are fully released. A group with no `roles` set counts as both. Release the rest in any order. Finish a
group before you start the next.

For each group, work from its highest ordinal down to 0. The highest ordinal is the group's new `replicas`
minus 1. Lower the partition to that ordinal, wait for the pod, then wait for green before the next ordinal.

```sh
kubectl patch statefulset <sts> --type merge \
  -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":<ordinal>}}}}'
kubectl rollout status statefulset/<sts>
GET /_cluster/health
```

Use the [Cluster health](../datanode-opensearch-api.md#cluster-health) call and wait for `green` with
`relocating_shards` and `unassigned_shards` at 0. Point your port-forward at a pod that already has the new template. Before you release the group the
forward points at, move it to a pod in a group you have already released.

A frozen group is safe from a template roll, not from losing a node. If a pod dies while you wait, for
example when its instance is terminated, wait for green again. The pod comes back on the old template. Release
it like any other.

A group that goes to 0 has nothing to release, because step 5 left it unfrozen. If you froze it by
mistake, set its partition back to 0. A stale partition makes later template changes skip every ordinal below
it, and nothing tells you.

```sh
kubectl patch statefulset <sts> --type merge \
  -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
```

Do not go on to step 8 until every group is released. Run the first command again. Every `PARTITION` must
read `0`. A group with pods that is still at its replica count has not rolled. See
[Step 7 example](#step-7-release-every-group-that-stays) for one group worked through.

<a id="removing-nodes-step-8"></a>**<ins>8. Clear the exclusions.</ins>** 

Leave them in place and a future node with the same name is refused shards.

```sh
PUT /_cluster/settings
{"persistent": {"cluster.routing.allocation.exclude._name": null}}
DELETE /_cluster/voting_config_exclusions
```

If some of the excluded pods are still in the cluster, for example when you only lowered a group's
`replicas`, the `DELETE` waits for those nodes to leave and times out. They never leave, so add
`wait_for_removal=false`.

```sh
DELETE /_cluster/voting_config_exclusions?wait_for_removal=false
```

Read both back with the calls in [Exclusions and voting](../datanode-opensearch-api.md#exclusions-and-voting).
`GET /_cluster/settings` should show no exclusion, and the voting exclusions in the cluster state should be
an empty list.

Clear the exclusions before you scale the group back up. They go by pod name, so a returning
`<sts>-3` is refused shards and gets no vote while its name is still listed.

<a id="removing-nodes-step-9"></a>
**<ins>9. Verification.</ins>**

Run [Verification](shared-runbook-steps.md#verification).

For a removal, the departed nodes must also be gone from the `GET /_cat/nodes` list.

**Rolling back.** Before step 6, clear the exclusions and nothing has moved for good. After step 6, restore
the old `replicas` and run the upgrade again with the same freeze and release steps. A returning pod
remounts its retained volume, which holds old data from before the drain. Delete the claims first if you
want it to start clean. See
[🧹 Deleting Orphaned Volumes](../datanode-safe-updates.md#-deleting-orphaned-volumes) before you remove any claim.

## Examples

> [!NOTE]
> These examples are made up. Your release, namespace and group names will differ.

### Step 2 exclude the departing nodes

Say a release named `graylog` in the `graylog` namespace has a group called `data` with 6 pods, and you are
going down to 4. The StatefulSet is `graylog-datanode-data`, so `graylog-datanode-data-5` and
`graylog-datanode-data-4` are the pods that leave.

```sh
PUT /_cluster/settings
{
  "persistent": {
    "cluster.routing.allocation.exclude._name": "graylog-datanode-data-4.graylog-datanode-svc.graylog.svc.cluster.local,graylog-datanode-data-5.graylog-datanode-svc.graylog.svc.cluster.local"
  }
}
```

A successful call answers with the setting echoed back.

```json
{
  "acknowledged": true,
  "persistent": {
    "cluster": {
      "routing": {
        "allocation": {
          "exclude": {
            "_name": "graylog-datanode-data-4.graylog-datanode-svc.graylog.svc.cluster.local,graylog-datanode-data-5.graylog-datanode-svc.graylog.svc.cluster.local"
          }
        }
      }
    }
  },
  "transient": {}
}
```

### Step 7 release every group that stays

Carry on with the `data` group from the step 2 example, which went from 6 pods to 4. After the upgrade the
group has `graylog-datanode-data-0` to `-3`, and it is still frozen at partition 6. The highest ordinal that
exists is 3, so you start there.

```sh
kubectl patch statefulset graylog-datanode-data -n graylog --type merge \
  -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":3}}}}'
kubectl rollout status statefulset/graylog-datanode-data -n graylog
```

The pod `graylog-datanode-data-3` restarts, and the status command returns when it is Ready.

```text
Waiting for 1 pods to be ready...
partitioned roll out complete: 1 new pods have been updated...
```

Now check the cluster, and go on only when `status` is `green`.

```sh
GET /_cluster/health
```

```json
{
  "cluster_name": "datanode-cluster",
  "status": "green",
  "number_of_nodes": 13,
  "relocating_shards": 0,
  "unassigned_shards": 0
}
```

Repeat for ordinals 2, 1 and 0, each time with a green check before the next. After the last pod the
group is released.

```sh
kubectl get statefulset graylog-datanode-data -n graylog \
  -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,PARTITION:.spec.updateStrategy.rollingUpdate.partition
```

```text
NAME                   READY   PARTITION
graylog-datanode-data  4       0
```

Then release the next group, and keep going until every group in the list reads `0`. If your port-forward
points at a pod in the next group, say `graylog-datanode-ingest-0`, move the forward to a pod that is already
released first, such as `graylog-datanode-data-0`.

## Removing a whole node group

> [!NOTE]
> Tested live on the default group: steps 1 to 3, and leaving the group at `replicas: 0` in step 6. Steps 4
> and 5, and deleting the empty StatefulSet in step 6, have not been tested live yet.

**What it is.** Retiring a group, not just some of its pods. It works for an extra group under
`datanode.extraNodeGroups` and for the default group set by `datanode.*`. Either way you empty the group
first with a normal removal, then clean up what is left.

The two differ at the end. The chart always renders the default group, so you cannot remove it from your
values. You can only scale it to 0. An extra group goes away completely when you delete its key.

**Path.** Check what inherits, empty the group, delete its volumes, then remove the group or leave it at 0.

**1. Check what inherits from the group.** Every extra group copies all of `datanode.*` and overrides only
what it sets. That includes `replicas`. If you scale the default group to 0, any extra group that does not
set its own `replicas` goes to 0 with it. Read the diff in step 1 of [🔻 Scaling Down Datanode](#-run-book-scaling-down-datanode)
before you go on, and confirm only the group you mean to empty shows a lower `replicas`.

**2. Check the roles.** At least one group that stays must keep `cluster_manager`, and you should keep at
least three manager-eligible nodes. The chart refuses to render if no group declares `cluster_manager`. Do
not narrow the `roles` of a group that still holds data. OpenSearch refuses to start a node that lost the
`data` role while its volume still has shards.

**3. Scale the group to 0.** Follow every step of [🔻 Scaling Down Datanode](#-run-book-scaling-down-datanode), with every pod in
the group as a departing node. Exclude them in one call, drain them, add the voting exclusion if the group
has the `cluster_manager` role, then freeze the groups that stay, upgrade and release them. Do not freeze the
emptied group. See [step 5](#removing-nodes-step-5).

Set `replicas: 0` and keep the group. For an extra group, leave its key in place. Removing the key in the
same upgrade deletes its ConfigMap, and one checksum covers every group's ConfigMap, so it changes every
group's template. You want that roll on its own, in step 5.

If you empty the group over several upgrades, run [step 8](#removing-nodes-step-8) once the last pod is
gone. The exclusions keep the dead pod names until you clear them. Before you go on, `GET /_cluster/settings`
must show no allocation exclusion.

**4. Delete the volumes.** The pods are gone but the claims stay, because `whenScaled` defaults to
`Retain`. Follow [🧹 Deleting Orphaned Volumes](../datanode-safe-updates.md#-deleting-orphaned-volumes) for every ordinal the group had.
Deleting a claim cannot be undone.

**5. Extra group, remove the key.** Delete the group from `datanode.extraNodeGroups` and upgrade. Helm
deletes its StatefulSet, ConfigMap and PodDisruptionBudget. No pod runs in it, so nothing there restarts. The
shared config checksum changes, so every other group rolls. Follow
[🚀 Update and scale up](update-and-scale-up.md) for this upgrade, including the freeze and the
release.

**6. Default group, leave it at 0 or delete the StatefulSet.** The empty StatefulSet costs nothing, and
leaving it at `replicas: 0` is the supported end state. If you want the object gone, delete it by hand
once no pod is running.

```sh
kubectl delete statefulset <release>-datanode -n <namespace>
```

The claims are kept, because `whenDeleted` defaults to `Retain`. The next `helm upgrade` creates the
StatefulSet again, empty, because the chart renders the default group every time. Deleting it is only
tidying.

**Rolling back.** Before step 4, restore the old `replicas` and run the upgrade again with the same freeze
and release steps. The pods remount their retained volumes. After step 4 the volumes are gone, so the
group comes back empty and the cluster re-replicates onto it.
