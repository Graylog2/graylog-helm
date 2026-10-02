# 🤝 Shared Runbook Steps

Part of [Safe Datanode Rollouts](../datanode-safe-updates.md).

## Preflight
Shared steps to run before starting any of the run books.
**Steps Overview**

### Overview
1. Confirm what the upgrade changes. Diff the render against the live release, and check it against what your run book expects.
2. Check the cluster. It must be green, every pod Ready, and every data index must have a replica.
3. Dry-run against the API server. A rejected update fails here, before anything moves.

### Steps
> [!NOTE]
> Every `helm` command in the run books names `graylog/graylog`, the published chart. If you work from a clone
> of this repo, use `charts/graylog/` in its place. The clone can be newer than the
> published chart at the same version number, and a values file written for it can fail to render on the
> older one.

**1. Confirm what the upgrade changes.** Do not guess from the values you edited.

```sh
helm diff upgrade graylog graylog/graylog -n <namespace> -f values.yaml [--version <new>]
```

What the diff should show depends on the run book you are following, and each one says what to expect. Do not
go on if the diff shows something else.

If `helm diff` is not installed, render with `helm upgrade --dry-run=server` and diff that against the live
manifest. It reads the existing Secret from the cluster, so unchanged Secrets and `checksum/secret` lines stay
out of the diff. `helm template` cannot read the Secret, and its diff fills with noise you have to ignore.

```sh
helm get manifest graylog -n <namespace> > live.yaml
helm upgrade graylog graylog/graylog -n <namespace> -f values.yaml --dry-run=server \
  | awk '/^MANIFEST:/{f=1;next} /^NOTES:/{f=0} f' > new.yaml
diff live.yaml new.yaml
```

A Secret that did change shows its data in the diff. Do not paste that output anywhere.

**2. Check the cluster.**

```sh
GET /_cluster/health
GET /_cat/indices?v&h=index,health,pri,rep&expand_wildcards=all
kubectl get pods -l app=graylog-datanode
kubectl get statefulsets -l app=graylog-datanode \
  -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,PARTITION:.spec.updateStrategy.rollingUpdate.partition
```

Status must be `green` and your data indices must show `rep` of 1 or more. See
[Cluster health](../datanode-opensearch-api.md#cluster-health) and [Indices](../datanode-opensearch-api.md#indices)
for the calls, including a one-line filter that lists any index with no replica.

Every pod must be `Ready`. A pod that crash-loops never joins the cluster, so the status stays `green` and
hides it. Read `kubectl logs <pod> --previous` and `kubectl describe pod <pod>` (look for `OOMKilled`). Fix
the pod before you go on.

Every `PARTITION` should read `0`. A higher value is left over from a run that did not finish. The freeze
step of your run book sets it again for every group that stays, so you do not need to release it first. For
a group going to 0, see [Scaling Down Datanode, step 5](scaling-down-datanode.md#removing-nodes-step-5).

**3. Dry-run against the API server.** A rejected update fails here, before anything moves. Filter the
output to anything that is not a normal `configured`, `created` or `unchanged` line or a warning.

```sh
helm template graylog graylog/graylog -n <namespace> -f values.yaml \
  | kubectl apply --dry-run=server -f - 2>&1 \
  | grep -v -E '^Warning:|(configured|created|unchanged) \(server dry run\)$'
```

No output means the server accepted every change. Stop if you see a line, and fix the values before you go on.
Do not filter on `^error`. The rejection can start with `Error from server (Invalid)` or with
`The StatefulSet "<name>" is invalid`, and an `^error` filter prints nothing for the second form.

The usual cause is an edit to a value in [🔒 Values You Can't Change](../datanode-safe-updates.md#-values-you-cant-change),
such as `datanode.persistence.data.size`. The error reads `updates to statefulset spec for fields other than
... are forbidden`, and it names the StatefulSet. Remember that groups inherit from the top of `datanode`,
so one edit there can reject several StatefulSets, including a default group sitting at 0 replicas.

Use the `kubectl` command above for this step. `helm upgrade --dry-run=server` exits 0 on the same change, so
it cannot stand in for it.

Leave out the `grep` and you will see a lot of noise that does not matter. `kubectl` warns that each
resource is missing the `last-applied-configuration` annotation, because Helm created it. It also reports
every resource as `configured`, even the ones with no change, and lists the `helm test` pods as `created`.
Helm does not create those on upgrade.

## Verification
Shared steps to run at the end of any run book.
**Verify.** Check the cluster and the StatefulSets.

```sh
GET /_cluster/health
GET /_cat/nodes?v&h=name,node.role,master
GET /_cat/indices?v&h=index,health,pri,rep&expand_wildcards=all
kubectl get statefulsets -l app=graylog-datanode \
  -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,PARTITION:.spec.updateStrategy.rollingUpdate.partition,CURRENT:.status.currentRevision,UPDATE:.status.updateRevision
```

Status is `green`, every node you expect is listed, and `unassigned_shards` is 0. Every partition is 0, and
each group's current and update revisions match. A group at 0 replicas shows `<none>` under `READY`, which is
expected. Each run book says what else to look for.
