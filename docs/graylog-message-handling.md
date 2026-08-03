# Graylog Message Handling

How messages are buffered on disk, what happens to them when pods go away, and how
to scale in without losing any.

For the values that configure this, see
[Message Journal Lifecycle](../charts/graylog/README.md#message-journal-lifecycle).

## Contents

- [The journal](#the-journal)
  - [Sizing](#sizing)
- [Scaling in safely](#scaling-in-safely)
- [Automatic drain on shutdown](#automatic-drain-on-shutdown)
- [Reading the drain logs](#reading-the-drain-logs)
- [Deleting a leftover PVC](#deleting-a-leftover-pvc)
- [Recovering a stranded journal](#recovering-a-stranded-journal)

## The journal

Each Graylog node writes incoming messages to an on-disk journal on its own PVC,
then works them off into the indexer. Two counters matter and they are not the same
thing:

| | Means |
|---|---|
| `gl_journal_entries_uncommitted` | messages **left to process** — this is "how much is undrained" |
| `gl_journal_size` | bytes **still stored**, including already-processed segments |

Graylog does not delete a segment just because it has been processed. Segments are
kept for `graylog.config.messageJournal.maxAge` (default 12h) and reaped only once
fully committed *and* past retention. A drained node still holds hundreds of MB.
Judge a journal by `uncommitted`, never by `du`.

### Sizing

The journal cap and the data volume have to be sized together.

| Value | Default | |
|---|---|---|
| `graylog.config.messageJournal.maxSize` | `5gb` | on-disk journal cap |
| `graylog.persistence.size` | `8Gi` | the whole data volume |

> [!NOTE]
> Graylog's suffixes are binary: `5gb` is 5×1024³, which is what the exporter reports
> as `gl_journal_size_limit`. Kubernetes quantities are not the same — `8G` is 8×10⁹, `8Gi` is 8×1024³.

The journal is not alone on that volume. It shares it with the `node-id`, the JVM
truststore, content packs, and GeoIP databases, and it can briefly overshoot its cap
because reaping happens a whole segment at a time. **The chart refuses to render a
cap above 90% of the volume** and tells you both a smaller cap and a larger volume
that would fit.

Raising the cap without raising the volume is the mistake this guards against. A full
journal throttles inputs — that is its designed backpressure. A full data volume
takes the node down.

Two constraints when changing them:

- Growing a volume needs a StorageClass with `allowVolumeExpansion: true`. Shrinking
  is not supported by Kubernetes at all.
- The cap is not a reservation. A journal that has never filled uses less; see the
  `uncommitted` vs `gl_journal_size` distinction above.

The check is skipped when the chart cannot know the size — an `existingClaim`, or a
quantity it cannot parse such as `1.5Gi`. It declines rather than guessing.

### Why upgrades are safe and scale-in is not

A StatefulSet guarantees identity, not data migration.

On a rolling upgrade, `graylog-2` is replaced by a new `graylog-2` that re-binds the
same PVC, finds the same journal and the same `node-id`, and carries on. Nothing is
lost and no procedure is needed.

On scale-in the ordinal stops existing. Its PVC is retained but no pod will mount it
again. Graceful shutdown flushes in-memory buffers **into** the journal; it never
drains the journal **out** — that is the replacement pod's job, and on scale-in
there is no replacement pod.

Kubernetes has no decommission hook. A pod cannot tell whether its SIGTERM means
upgrade, drain, or removal, so drain-before-scale-in can only live in a runbook or a
preStop hook. Both are below.

## Scaling in safely

Scaling out needs no procedure. Scaling in does. Run this against the highest
ordinals first — StatefulSets terminate from the highest ordinal down.

**1. Stop the inputs.** This is the only step that guarantees the journal can reach
zero. Endpoint removal alone does not stop long-lived TCP connections, UDP senders,
or internally generated inputs.

```sh
# list inputs
curl -su "admin:$PASS" http://localhost:9000/api/system/inputs | jq '.inputs[] | {id, title}'

# stop one across the whole cluster (this is the one you want for a scale-in)
curl -su "admin:$PASS" -H 'X-Requested-By: cli' \
  -X DELETE http://localhost:9000/api/cluster/inputstates/<id>
```

Or **System > Inputs** in the UI. Requires admin auth.

> [!WARNING]
> Stop inputs via `inputstates`, never `DELETE /api/system/inputs/<id>` — that one is
> "Terminate input on this node" and removes the input definition. `inputstates` stops
> a running input and leaves it configured, so `PUT` on the same path starts it again.
> `/api/system/inputstates/<id>` is the node-scoped variant; `/api/cluster/inputstates/<id>`
> covers every node, which is what quiesces the journal.

Every state-changing Graylog API call needs an `X-Requested-By` header (any value) or
it fails with `CSRF protection header is missing`. That applies to the `lbstatus`
override below too.

**2. Take the node out of rotation.** Graylog publishes its load-balancer state at
`/api/system/lbstatus` — unauthenticated, and the body is the plain word `ALIVE`,
`THROTTLED` or `DEAD` with HTTP `200`, `429` or `503` respectively.

```sh
kubectl exec -n graylog graylog-2 -- curl -so /dev/null -w '%{http_code}\n' \
  http://localhost:9000/api/system/lbstatus
```

Force it dead before scaling (requires admin auth):

```sh
kubectl exec -n graylog graylog-2 -- curl -su "admin:$PASS" -H 'X-Requested-By: cli' \
  -X PUT http://localhost:9000/api/system/lbstatus/override/dead
```

Returns `204`. The value is case-insensitive, and `ALIVE`/`DEAD`/`THROTTLED` are the
only ones accepted. Undo it with `override/alive`; a lifecycle change also resets it.

> [!NOTE]
> The chart's readiness probe is a TCP check, so `lb_status: DEAD` does not currently
> remove the pod from Service endpoints on its own. Until the probe is HTTP-based,
> treat this step as signalling to external load balancers, and rely on step 1 to
> actually stop ingest.

**3. Watch the journal drain to zero.**

```sh
kubectl port-forward -n graylog pod/graylog-2 9833:9833
curl -s localhost:9833/metrics | grep '^gl_journal_entries_uncommitted'
```

Port-forward the **pod**, not the Service — the Service answers from an arbitrary
node. The equivalent REST call is `GET /api/system/journal`, which needs admin auth; the
metrics gauge does not. The field is **`uncommitted_journal_entries`** — not
`uncommitted_entries`. That response also carries `journal_size`,
`journal_size_limit`, `number_of_segments`, `oldest_segment`, and a `journal_config`
block echoing the effective settings, which is the quickest way to confirm a
`maxSize` change actually took.

**4. Scale down by one and wait.** Do not jump several ordinals at once.

```sh
helm upgrade graylog graylog/graylog -n graylog --set graylog.replicas=2 --reuse-values
```

To hold the rollout at a specific ordinal instead, use `updateStrategy.rollingUpdate.partition`
(note the schema types it as a string, so use `--set-string`):

```sh
helm upgrade graylog graylog/graylog -n graylog --reuse-values \
  --set-string graylog.updateStrategy.rollingUpdate.partition=2
```

**5. Verify, then repeat.** Confirm `uncommitted` is 0 on the remaining pods before
scaling in the next ordinal.

**6. Audit what was left behind.**

```sh
kubectl get pvc -n graylog       # e.g. graylog-data-graylog-2 remains
```

See [Deleting a leftover PVC](#deleting-a-leftover-pvc) before removing it.

### PVC retention

The chart pins `persistentVolumeClaimRetentionPolicy` to `Retain` on both fields for
both StatefulSets, and **refuses to render `graylog.persistence.retentionPolicy.whenScaled: Delete`**.
`Delete` would destroy the journal of every scaled-in node, silently. The Data Node
allows `Delete` because shard data rebuilds from replicas; a Graylog journal does not.

## Automatic drain on shutdown

The chart can hold pod termination while the journal is worked off:

```sh
helm upgrade graylog graylog/graylog -n graylog \
  --set graylog.lifecycle.preStopDrain.enabled=true --reuse-values
```

A `preStop` hook polls `gl_journal_entries_uncommitted` from the Prometheus exporter
on localhost and returns once the journal is empty. No credentials needed. Requires
`graylog.service.metrics.enabled` (the default); the chart refuses to render
otherwise.

Off by default: it slows every rolling upgrade, where it protects nothing.

### The budget

`terminationGracePeriodSeconds` is a hard ceiling covering the hook **and** the
SIGTERM after it. If the hook is still running when it expires the container is
SIGKILLed, Graylog never gets SIGTERM, and the in-memory buffers this feature exists
to protect are lost — worse than no hook. So:

```
drain budget = terminationGracePeriodSeconds
             - endpointPropagationDelaySeconds   # settle: wait for endpoint removal to propagate
             - shutdownReserveSeconds            # left for Graylog's own shutdown
```

Defaults: `300 - 15 - 45 = 240s`. The chart fails to render if that is not positive.

**settle** is a plain sleep before the first sample. Endpoint removal is eventually
consistent, and measuring during that window reads ingest that is about to stop —
which skews the drain rate and can trip the feasibility abort on a pod that would
have drained fine. Raise it if a load balancer targets pod IPs directly (ALB/NLB IP
mode deregisters slower than kube-proxy), and raise the grace period with it.

### What it cannot do

| Limit | Consequence |
|---|---|
| Bounded by the grace period | If the journal is still full, termination proceeds anyway. |
| Only sheds *new* connections | Long-lived TCP, UDP, and internal inputs keep writing. The journal never reaches zero and the hook gives up after `stallPolls` samples without a new low. |
| Cannot stop inputs | That needs authenticated API calls. Only the runbook above guarantees an empty journal. |
| Useless on rolling upgrades | The replacement pod replays the journal itself. The hook cannot tell an upgrade from a scale-in, so it pays the cost on both. |
| Cannot drain a blocked indexer | Nothing can be worked off and the journal only grows. The feasibility check aborts in seconds instead of stalling the rollout. |

## Reading the drain logs

The hook writes to the container's log stream. Follow it **before** terminating — a
pod's logs die with the pod, so a post-mortem `kubectl logs` finds nothing.

```sh
kubectl logs -n graylog -l app=graylog-app -c graylog-app \
  --follow --prefix --tail=0 --max-log-requests=20 | grep prestop-drain
```

Every run ends in one `RESULT:` line. That line is the whole verdict.

### RESULT: SUCCESS

```
RESULT: SUCCESS - journal fully drained (0 messages remaining) in 34s total
        (1s preflight + 15s settle + 18s draining), within the 240s budget
drained 100% of the starting backlog (18432 -> 0 messages)
```

Depth held at 0 across `confirmPolls` samples. Safe to scale in. A single zero is
never treated as drained — under live ingest the gauge touches zero while messages
are still arriving, so the streak has to hold.

### RESULT: INCOMPLETE — stalled

```
no new low in 10 polls: depth 163, best 4, still ingesting 113 msg/s
RESULT: INCOMPLETE - 163 messages still queued and no longer decreasing after 89s
the write side never stopped, so the journal cannot reach zero
if this pod is being removed by a scale-in, those 163 messages will be stranded
```

**Most common failure.** Something is still writing. Endpoint removal only sheds new
connections. Expected on a node under live load — the fix is step 1 of the runbook,
not a longer budget. `best 4` means it nearly made it.

### RESULT: INCOMPLETE — timeout

```
RESULT: INCOMPLETE - 240s timeout cutoff reached with 51200 messages still undrained
```

Depth kept falling but ran out of budget. Raise `terminationGracePeriodSeconds`, or
stop the inputs and drain manually. If this appears with a large backlog, the
feasibility check should have caught it — check whether `feasibilityWarmupPolls` is 0.

### RESULT: ABORTED — not draining

```
CRIT FEASIBILITY: journal is NOT draining - depth went 7240000 -> 7240000 over 8s
CRIT   drain rate:      0 msg/s - nothing is being worked off (ingest 1200 msg/s)
CRIT   time to clear:   never at this rate
CRIT   the indexer is refusing writes or cannot keep up; check for a read-only
       index block or a disk watermark on the indexer
```

The indexer is not accepting writes. Usually OpenSearch crossed its flood-stage
watermark and stamped `index.blocks.read_only_allow_delete: true` on the write
index. Free disk on the indexer; the block releases below the *high* watermark
(90%), not the flood stage (95%). **Disable the hook before rolling a cluster in
this state** — it still costs the warmup window per pod.

### RESULT: ABORTED — cannot finish in time

```
CRIT FEASIBILITY: drain cannot finish in the time available
CRIT   journal on disk: 5.0GiB of 5.0GiB cap (100% full)
CRIT   the journal is AT its cap - Graylog is already discarding the oldest
       segments, so messages are being lost right now
CRIT   backlog:         999727 messages awaiting processing
CRIT   drain rate:      107 msg/s measured over 2s (ingest 1200 msg/s)
CRIT   time to clear:   ~2h35m at that rate
CRIT   short by:        ~2h34m
```

Draining, but nowhere near fast enough. The hook gives up immediately rather than
holding termination to clear a couple of percent. `AT its cap` means data is being
lost right now regardless of what you do with the pod — deal with the backlog first.

### RESULT: UNKNOWN

```
RESULT: UNKNOWN - no drain attempted; journal depth was never measurable
metrics endpoint http://127.0.0.1:9833/metrics did not answer after 5 attempts
```

No drain happened; the hook could not read the gauge. Check
`graylog.service.metrics.enabled`, and whether the pod was still starting or already
unhealthy. `drain abandoned` instead of `no drain attempted` means the endpoint
answered at preflight and then stopped.

### No prestop-drain lines at all

The hook did not run. Check `graylog.lifecycle.preStopDrain.enabled`, and that you
are following logs from before termination. Kubernetes discards `preStop` stdout by
default — these lines are visible only because the hook writes to PID 1's stdout
deliberately.

## Deleting a leftover PVC

Scale-in leaves the highest ordinal's claim behind. The chart never deletes it. The
decision is yours, and it is not reversible by default.

> [!WARNING]
> Deleting the PVC is what destroys the data, and most StorageClasses use
> `reclaimPolicy: Delete` — including this chart's own gp3 class — so the underlying
> disk goes with it. The chart's retention policy protects the claim from the
> StatefulSet controller, not from you or from a GitOps prune.

Make the volume survivable first. A PV's reclaim policy is mutable, unlike a
StorageClass's:

```sh
PV=$(kubectl get pvc graylog-data-graylog-2 -n graylog -o jsonpath='{.spec.volumeName}')
kubectl patch pv "$PV" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

A PV only picks up its reclaim policy at provision time, so changing the
StorageClass later does not help existing volumes. Patch the PV.

For GitOps, `graylog.persistence.annotations` flows into the volumeClaimTemplate, so
`argocd.argoproj.io/sync-options: Prune=false` works — but volumeClaimTemplates are
effectively immutable, so annotations only land on PVCs created *after* you set
them. Adding this later does not protect the ordinal you are trying to save.

### Verifying before you delete

The drain verdict is good evidence but point-in-time, and "committed" means read out
of the journal into the pipeline — the last hop into OpenSearch happens from an
in-memory buffer during shutdown. Confirm rather than assume. Strongest first:

1. **Re-attach it.** Scale back up by one. The ordinal returns, re-binds the claim,
   and Graylog replays anything unprocessed. Watch `uncommitted` settle at 0 with
   inputs stopped, then scale in again and delete. This is both the test and the fix.

2. **Inspect it offline.** Graylog ships a journal CLI, which is the most direct
   option once the claim is mounted somewhere:

   ```sh
   # needs a config file with data_dir pointing at the mounted volume
   graylog journal show --show-segments
   ```

   `graylog journal decode <range>` reads messages back out. Avoid
   `graylog journal truncate` unless you intend to discard entries.

   `examples/inspect-orphaned-journal.yaml` mounts the claim read-only and compares
   the committed offset against the segments without needing a config file.

   ```sh
   kubectl apply -n graylog -f examples/inspect-orphaned-journal.yaml
   kubectl logs -n graylog journal-inspector -f
   kubectl delete -n graylog pod/journal-inspector
   ```

   > [!IMPORTANT]
   > This can prove messages **were** stranded, not that they were not. Graylog's
   > offset index is sparse, so records past the last index entry are invisible to any
   > offline reader. Measured on a live node: the index looked clean while the node
   > had 537 unprocessed messages. `NO EVIDENCE OF STRANDED DATA` means no evidence.

Expect the on-disk size to sawtooth — climbing, then dropping ~100MB at once as a
fully-committed segment is reaped. That is retention, not loss.

Then:

```sh
kubectl delete pvc graylog-data-graylog-2 -n graylog
```

## Recovering a stranded journal

If you scaled in without draining, the data is unreachable, not gone. Scale back up
to the original replica count. The ordinal returns, re-binds its claim, and Graylog
replays the journal.

Expect late arrivals: days-old messages entering the pipeline will hit alerts,
dashboards, and index retention. Then drain properly and scale in again.

If the PVC was already deleted but the PV was `Retain`, the PV survives as
`Released`. It is not immediately reusable — `spec.claimRef` still points at the
deleted PVC. Clear that, then bind a new PVC with `volumeName` set to the PV.
