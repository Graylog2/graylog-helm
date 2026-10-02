# 🎯 Run Book: Change to some node groups

Part of [Safe Datanode Rollouts](../datanode-safe-updates.md).

> [!WARNING]
> This run book is a work in progress. Its steps are commented out until they are reviewed and tested live
> again. Until then, use [🚀 Update and scale up](update-and-scale-up.md). It is safe for any change, even
> one that only touches some groups, because it freezes and releases every group.

<!--
## Description
Use this run book when the upgrade restarts the pods of only some groups.

 - A pod setting that a group sets for itself under `datanode.extraNodeGroups.<name>`, such as `resources` or
   `podAnnotations`. Only that group gets a new pod template.
 - A change to `datanode.*` that every other group overrides. A group inherits everything it does not set, so
   one group that does not override the value rolls too.

Do not use it in these cases.

 - The diff changes `checksum/config`. A group's `config.*` and `roles` render into a ConfigMap, and one
   checksum covers every group's ConfigMap. Editing `config.nodeSearchCacheSize` on one group changed the
   checksum on all of them. Use [🚀 Update and scale up](update-and-scale-up.md).
 - You add or remove pods or groups. Use the same run book for an addition, and
   [🔻 Run Book: Scaling Down Datanode](scaling-down-datanode.md) for a removal.

A group whose template does not change never restarts, so you do not freeze it. Point your port-forward at
one of its pods and it stays up for the whole run.

## Steps Overview

1. [Preflight](#some-groups-step-1). Diff the render, check the cluster, dry-run.
2. [Freeze the node groups that change](#some-groups-step-2). Set each partition to its replica count so the new template applies to no pod.
3. [Upgrade](#some-groups-step-3). Helm writes the new template, and no pod restarts yet.
4. [Release one group at a time](#some-groups-step-4), `cluster_manager` and `data` groups first. Lower the partition one ordinal at a time, highest first, and wait for green after each pod.
5. [Verification](#some-groups-step-5). Verify the cluster and the StatefulSets.

## Run Book Steps
<a id="some-groups-step-1"></a>
**<ins>1. Preflight.</ins>** Run all three steps in [Preflight](shared.md#preflight).

For this run book, expect only the StatefulSets of the groups you edited to differ. `replicas` and
`checksum/config` should not change on any group. If another StatefulSet differs, or the checksum changes,
stop. Either fix the values, or use [🚀 Update and scale up](update-and-scale-up.md).
Write down which groups differ, because those are the only groups you freeze and release. See
[Step 1 example](#step-1-read-the-diff) for what a one group change looks like.

<a id="some-groups-step-2"></a>
**<ins>2. Freeze the Datanode node groups that change.</ins>**

Set the partition to the replica count that is live now, so the new template applies to no pod yet. Read it
before you upgrade. Freeze only the groups the diff showed. Leave every other group alone. The primary group
is `<release>-datanode` and each extra group is `<release>-datanode-<name>`.

```sh
kubectl get statefulset <sts> -o jsonpath='{.spec.replicas}'
kubectl patch statefulset <sts> --type merge \
  -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":<replicas>}}}}'
```

<a id="some-groups-step-3"></a>
**<ins>3. Upgrade.</ins>**

```sh
helm upgrade graylog graylog/graylog -n <namespace> -f <your custom values>.yaml
```

Do not set `updateStrategy.rollingUpdate.partition` in your values. The chart renders it only when it is
non-zero, which is why Helm leaves the frozen value alone.

Run `kubectl get pods` before you go on. No Data Node pod should have restarted. Groups you did not freeze
had no change, so they keep their pods.

<a id="some-groups-step-4"></a>
**<ins>4. Release one group at a time.</ins>**

Release only the groups you froze. Follow [step 4 of Update and scale up](update-and-scale-up.md#every-group-step-4)
for each one. Start with the groups that have the `cluster_manager` or `data` role, finish a group before
the next, and go highest ordinal first inside it.

```sh
kubectl patch statefulset <sts> --type merge \
  -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":<ordinal>}}}}'
kubectl rollout status statefulset/<sts>
GET /_cluster/health
```

Continue only when `status` is `green` and `relocating_shards` and `unassigned_shards` are 0.

> [!NOTE]
> Point your port-forward at a pod in a group you did not freeze. It never restarts, so the forward does
> not drop and you never have to move it. If every group changes, you want the every-group run book.

<a id="some-groups-step-5"></a>
**<ins>5. Verification.</ins>** Run [Verification](shared.md#verification).

The groups you did not change must show the same current and update revision as before, and their pods
must not have restarted.

## Examples

> [!NOTE]
> These examples are made up. Your release, namespace and group names will differ.

### Step 1 read the diff

Say you set `podAnnotations` on the `search` group only. `helm diff` shows one changed line, in the
`graylog-datanode-search` StatefulSet. No other StatefulSet appears, and `checksum/config` does not move.

```diff
         karpenter.sh/do-not-disrupt: "true"
---
         karpenter.sh/do-not-disrupt: "false"
```

Only `graylog-datanode-search` needs a freeze and a release. Its role is `search`, so it holds no shards.
-->
