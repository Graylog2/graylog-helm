# Safe Datanode Rollouts

To keep OpenSearch healthy and responding, every index must always have at least one replica available. Running StatefulSets in Kubernetes can make this difficult.

## The Problem and Its Solutions
### The Problem
 - When scaling down the number of Datanodes that have the `data` role, you need to drain the OpenSearch shards off those nodes so that they are still accessible.
 - Datanode needs to know about all other members in the OpenSearch cluster. This is done by concatenating all Datanode addresses in the `GRAYLOG_DATANODE_OPENSEARCH_DISCOVERY_SEED_HOSTS` environment variable in every Datanode pod. This means that any scale operation that involves Datanode, up or down, requires every Datanode pod to roll. With multiple StatefulSets for Datanode, you need to control the rollout manually. If you don't, multiple Datanode node groups roll simultaneously, causing cluster instability.
 - A configuration change to Datanode causes the same issue when you use more than one Datanode group: multiple StatefulSets roll at once.

### The Solution
 - Follow the [🧰 Before you begin](#-before-you-begin) section for recommendations on how to initially set up your Graylog Helm custom values YAML for best practices.
 - Manage the rolling update through partitions, to freeze updates to Datanode StatefulSets so you can roll them one at a time.
 - When scaling down replicas that hold data, drain the Datanode node manually, then remove it from the cluster.

See [🔄 When Datanode Has to Roll](#-when-datanode-has-to-roll) to determine which run books you may need for your use case.

See [Running OpenSearch API calls against Data Node](datanode-opensearch-api.md) for a guide on how to talk to OpenSearch.

## 📑 Contents

- [🧰  Before you begin](#-before-you-begin)
  - [🔒  Values You Can't Change](#-values-you-cant-change)
- [🥷  Operational Recommendations](#-operational-recommendations)
  - [🔄  When Datanode Has to Roll](#-when-datanode-has-to-roll)
- [📘  Rollout Run Books](#-rollout-run-books)
  - [🚀  Update and scale up](run-books/update-and-scale-up.md)
  - [🔻  Run Book: Scaling Down Datanode](run-books/scaling-down-datanode.md)
    - [Removing a whole node group](run-books/scaling-down-datanode.md#removing-a-whole-node-group)
  - [🤝  Shared Runbook Steps](run-books/shared-runbook-steps.md)
    - [Preflight](run-books/shared-runbook-steps.md#preflight)
    - [Verification](run-books/shared-runbook-steps.md#verification)
- [💡  Other Considerations](#-other-considerations)
  - [🧹  Deleting Orphaned Volumes](#-deleting-orphaned-volumes)
<!-- - [🚧  Common issues](#-common-issues) -->


## 🧰 Before you begin

Below is an example of best practice settings to consider before you first deploy the Graylog Helm chart, especially for production environments running at a large scale.

```yaml
graylog:
  config:
    # Default is 0. With no replica, restarting the one node that holds a
    # shard makes that shard unavailable. This sets the default for new index
    # sets only. Change existing ones under System / Indices, and check the
    # rep column of GET /_cat/indices until every data index shows 1 or more.
    elasticsearch_replicas: 1
  
  # If the cluster goes red, Graylog starts journalling messages to disk. In
  # this situation you want sufficient disk for Graylog to handle momentary
  # lapses in OpenSearch availability.
  persistence:
    enabled: true
    retentionPolicy:
      whenDeleted: Retain
      whenScaled: Retain
    size: 50Gi

datanode:
  # A replica cannot live on the same node as its primary. With one data node
  # the cluster stays yellow and the replica protects nothing. Use 3 or more.
  replicas: 3

  persistence:
    data:
      # A replica doubles the storage an index uses. Size for it, because a
      # node that runs out of disk cannot take shards during a rollout.
      size: "8Gi"

  reloader:
    # Keep false so config changes never restart groups on their own.
    autoReload: false

  updateStrategy:
    rollingUpdate:
      # Leave unset, here and under every extraNodeGroups entry. See the note below.
      # partition:
```

> [!WARNING]
> Never set `updateStrategy.rollingUpdate.partition` in your values. The run books freeze and release
> groups by patching it with `kubectl`, and Helm leaves a field alone only while your values never set it.
> If you set it, Helm resets your patch on every upgrade. If you set it and later remove it, Helm clears
> the field, and every frozen pod restarts at once.

> [!NOTE]
> See [🔒 Values You Can't Change](#-values-you-cant-change). Many StatefulSet fields cannot be changed after they are created.


See [Data Node Roles & Node Groups](datanode-node-roles.md) for how node groups and roles are defined.

See [Running OpenSearch API calls against Data Node](datanode-opensearch-api.md) for how to reach the OpenSearch API.

### 🔒 Values You Can't Change

Kubernetes only lets you edit `replicas`, `ordinals`, `template`, `updateStrategy`, `revisionHistoryLimit`,
`persistentVolumeClaimRetentionPolicy` and `minReadySeconds` on an existing StatefulSet. Change any other
field and the API server rejects the whole update, with `updates to statefulset spec for fields other than
... are forbidden`. Nothing restarts, but Helm can fail partway and leave the release in a `failed` state.

These values render into the immutable fields. Each one applies to the default group and to every entry
under `datanode.extraNodeGroups`, including a value a group inherits from the top of `datanode`.

| Values key | Immutable field | Notes |
|---|---|---|
| `datanode.persistence.data` | `volumeClaimTemplates` | Every key except `mountPath`: `enabled`, `size`, `storageClass`, `accessModes`, `labels`, `annotations`. |
| `datanode.persistence.nativeLibs` | `volumeClaimTemplates` | Same keys as `data`. Turning it on or off adds or removes a template. |
| `global.storageClass` | `volumeClaimTemplates` | A group with no `storageClass` of its own inherits it. |
| `datanode.podManagementPolicy` | `podManagementPolicy` | |
| `nameOverride` | `selector`, `serviceName` | Also changes the pod labels and the service name. |
| `fullnameOverride` | `serviceName` | Also renames every StatefulSet. |
| the Helm release name | `selector`, `serviceName` | Renaming a release means installing a new one. |
| a key under `datanode.extraNodeGroups` | the StatefulSet name | A renamed key is a new group. The old one is removed. |
| the first or last entry under `datanode.extraNodeGroups` | `selector` | The default group carries a `graylog-datanode-group` label on its selector only while at least one extra group exists. Adding the first group or removing the last one changes it. See [Common issues](#-common-issues). |

`datanode.persistence.retentionPolicy` is not on the list. It can change at any time.

The dry-run in [Preflight](run-books/shared.md#preflight) catches most of these before anything moves.
It misses the `extraNodeGroups` selector change, so watch for that one yourself. If you
need one of them, the StatefulSet has to be recreated. Delete it with `--cascade=orphan`, which leaves the
pods and claims running, then upgrade so Helm creates it again with the new fields. The existing claims
keep their old size and storage class, because a template only applies to claims it creates. Resize or
migrate them yourself.

## 🥷 Operational Recommendations
 - **Shard Redundancy:** Every index that holds data needs at least one replica. See [🧰 Before you begin](#-before-you-begin).
 - **Start only from Green:** Avoid scaling or Datanode updates whenever the OpenSearch cluster is not green.
 - **One Pod at a Time:** Avoid rolling more than one Datanode pod at a time across the different StatefulSets.
 - **Limit Change:** Keeping your changes small between `helm upgrade` operations limits the blast radius and helps you catch problems early.
 - **Stop on Red:** Do not restart anything else until it is back to yellow or green.

### 🔄 When Datanode Has to Roll

TLDR: Whenever a change touches the `datanode.*` portion of the values, a cluster roll should be expected, outide of replcia counts.

A Data Node pod restarts when its StatefulSet pod template changes. Replica counts and the update strategy do not count.

- A new chart version, or `version` and `datanode.image.*`. The image tag defaults to the chart's
  `appVersion`.
- Anything under `datanode.*` that renders into the pod, such as resources, scheduling, probes, env,
  sidecars, init containers, extra volumes and pod labels or annotations.
- `datanode.config.*` and `datanode.roles`. They render into the ConfigMap, and the pod template carries
  its checksum.
- Any change to the chart-managed Secret, because the pod template carries its checksum. Graylog-only
  values count too, for example `graylog.config.rootUsername`, `graylog.config.rootPassword`, the MongoDB
  URI or the TLS key password.

## 📘 Rollout Run Books

Every run book starts with [Preflight](run-books/shared.md#preflight) and ends with [Verification](run-books/shared.md#verification).
Read the diff in Preflight, pick the run book that matches it, and follow that run book end to end.

| Run book | Use it when |
|---|---|
| [🚀 Update and scale up](run-books/update-and-scale-up.md) | The upgrade rolls every group, for example a chart or app version, a change to `datanode.*`, or a scale up. |
| [🔻 Scaling Down Datanode](run-books/scaling-down-datanode.md) | The upgrade leaves a group with fewer pods. It also covers [removing a whole node group](run-books/scaling-down-datanode.md#removing-a-whole-node-group). |

<!-- | [🎯 Change to some node groups](run-books/some-node-groups.md) | The upgrade rolls only the groups you edited, and `checksum/config` does not change. | -->

The steps every run book shares are in [🤝 Shared steps](run-books/shared.md).

## 💡 Other Considerations
### 🧹 Deleting Orphaned Volumes

`datanode.persistence.retentionPolicy.whenScaled` defaults to `Retain`, so the PVCs outlive the pods and
keep costing storage. Leave it on `Retain` and delete the claims by hand. Deleting a PVC cannot be
undone, and depending on the storage class it destroys the disk.

```sh
kubectl get pvc -n <namespace> | grep '<sts>-[<ordinals>]'
```

The claims are named `data-<sts>-<ordinal>`, plus `native-libs-<sts>-<ordinal>` when that volume is on.
Delete a claim only when all of these are true.

- The pod is gone, so nothing mounts the claim.
- The node no longer appears in `GET /_cat/nodes`.
- The cluster is `green` with `unassigned_shards` at 0, after the upgrade and after you cleared the
  exclusions.
- Every data index has `rep` of 1 or more, so its shards live on the nodes that stayed.

If you will scale back up, delete the claims first. The StatefulSet creates a new empty claim for every
pod it starts, so a returning pod begins clean and the cluster fills it with shards again. A kept claim
remounts old data from before the drain. A node that died mid-recovery can leave a partial shard on its
claim, and the pod then crashes on start with `Failed to open index for read`.

```sh
kubectl delete pvc <claim> -n <namespace>
```
<!-- 
## 🚧 Common issues

Problems that came up while running these run books.

- Do not freeze a group that goes to 0. It has no pod to release, so its partition would stay at the old
  count. Later template changes then skip every ordinal below that count, and nothing tells you. If you
  froze one, set the partition back to 0, as
  [step 7 of Scaling Down Datanode](run-books/scaling-down-datanode.md#removing-nodes-step-7) describes.
- A port-forward can drop while its pod is healthy. `kubectl` prints `error: lost connection to pod`, and
  every API call after that returns nothing. A blank or failed health check is not green. Reconnect,
  repeat the health check, and go on only when it reads `green`. If you script a rollout, make it stop on
  an empty response.
- The dry-run rejects a StatefulSet with `updates to statefulset spec for fields other than ... are
  forbidden`. See [🔒 Values You Can't Change](#-values-you-cant-change) for the values
  that cause it. If the StatefulSet has no replicas and no claims, for example a default group scaled to 0
  whose volumes you already deleted, delete the StatefulSet and run the dry-run again. Nothing runs in it and
  nothing is stored, so the delete loses nothing, and the next `helm upgrade` creates it again from your
  values with the new fields.

  ```sh
  kubectl get statefulset <sts> -n <namespace> -o jsonpath='{.spec.replicas}'
  kubectl get pvc -n <namespace> | grep '<sts>'
  kubectl delete statefulset <sts> -n <namespace>
  ```

  The first command must print 0 and the second must print nothing. If either does not, do not use this
  fix. Delete with `--cascade=orphan` instead, as described in the section linked above, and expect
  the existing claims to keep their old size. For a group that still runs pods, the simpler fix is to put the
  value back to what the live StatefulSet has.
- `helm upgrade` fails with the same `updates to statefulset spec ... are forbidden` error right after you
  remove the last entry from `datanode.extraNodeGroups`, and the dry-run passed. The default group's
  selector loses its `graylog-datanode-group` label when no extra group is left, and the dry-run does not
  notice, because it only adds keys to the live selector and never removes one. Nothing restarts. The
  default group still runs pods, so recreate its StatefulSet with `--cascade=orphan`, then upgrade. The new
  StatefulSet adopts the running pods and keeps their claims.

  ```sh
  kubectl delete statefulset <default-sts> -n <namespace> --cascade=orphan
  kubectl get pods,pvc -n <namespace> | grep '<default-sts>'
  ```

  Confirm all pods and claims are still listed before you upgrade. The upgrade only restarts pods if the pod
  template changed too, so pick the run book for that change.

  Adding the first extra group is the same fix with one more step. The new selector requires the
  `graylog-datanode-group: default` label, and pods created before it do not have it. A StatefulSet does
  not adopt a pod its selector does not match, so that pod keeps running with no owner. Label every pod
  first, then delete the StatefulSet.

  ```sh
  kubectl label pod <default-sts>-0 <default-sts>-1 graylog-datanode-group=default -n <namespace>
  ```

  A pod you are about to remove needs the label too. Without it the new StatefulSet cannot scale it down,
  so you must delete it by hand.
- A `helm upgrade` fails on one StatefulSet after it already changed others. Helm applies resources in
  order and does not roll the earlier ones back, so the release shows `failed` but anything created before
  the error is live. When an upgrade that adds a group fails on the default group, the new group's
  StatefulSet and pods already exist. Fix the cause and run the upgrade again. Check `helm history` to see
  which revision failed, and do not start a run book from a `failed` release.
- You scaled a group down earlier and now scale it back up, and the returning pods are refused shards, have
  no vote, or crash on start. Three leftovers from the removal cause it.

  - The allocation and voting exclusions still list the old pod names. They go by name, so clear them before
    the upgrade, as [step 8 of Scaling Down Datanode](run-books/scaling-down-datanode.md#removing-nodes-step-8) describes.
  - The retained claims hold old data, and a node that died mid-recovery can leave a partial shard that
    crashes the pod on start. Delete the claims for the returning ordinals first. The StatefulSet creates
    new empty claims when the pods start. See
    [Deleting Orphaned Volumes](#-deleting-orphaned-volumes).
  - A group that is still frozen from the removal keeps its old template. Freeze it at its current count
    for the scale up, and release it once, so it restarts one time instead of two.
- A pod crash-loops after the upgrade and the roll stops there. Data Node checks its settings at startup and
  exits on a value it rejects. The StatefulSet replaces pods one at a time and will not move to the next
  until the new pod is ready, so the other pods keep running the old settings. The crashed node is out of
  the cluster until you fix it. Read the reason with `kubectl logs <pod> --previous`. Two that came up:

  | Value | Rejected | Log line |
  |---|---|---|
  | `datanode.opensearchHeap` | `2560mb`, it takes `m` or `g` | `Invalid heap size configuration` |
  | `datanode.nodeSearchCacheSize` | `2560m`, it takes `mb` or `gb` | `Unexpected value ... of node_search_cache_size` |

  The two settings use different suffixes. Data Node reports one bad value per start, so check the log again
  after each fix. Correct the values and run `helm upgrade` again. Helm replaces the crashed pod with the
  fixed template, and the roll carries on. Do not delete the healthy pods to speed it up.
- You deleted a StatefulSet that still had pods, for example with `kubectl delete statefulset <sts>`. Every
  pod in it stops at once, with no drain. A group with only `cluster_manager` nodes held no shards, so the
  cluster stayed green and elected a new manager, because six other manager-eligible nodes remained. A
  group with the `data` role would take its shards offline. Scale the group to 0 first, with
  [Scaling Down Datanode](run-books/scaling-down-datanode.md), and delete the StatefulSet only when no pod runs in it. -->
