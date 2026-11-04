# Load testing the chart

Sustained ingest through a Graylog Forwarder into an index set of its own, so a chart change can
be measured against something other than an idle cluster.

Everything below ran against Graylog 7.1.9 in the `graylog-helm` namespace on `glc-central-dev`.
The API shapes are the ones that instance accepted rather than the ones I expected, and three of
them differed enough to cost an afternoon each.

The load test scripts have a README that is the manual for the
flags. This document covers what the exercise taught about Graylog and the chart, which outlives
any particular script.

## Prerequisites

Each of these fails late and confusingly when it is missing.

| | Why |
| --- | --- |
| Graylog Enterprise license | Forwarders and archiving are both licensed plugins. Without one their endpoints return 404 and every failure reads as a bad URL. |
| A Graylog API token | Sent as the basic-auth username, with the literal string `token` as the password. Keep it in a `chmod 600` file. |
| A forwarder token | A different thing entirely. System > Forwarders > add a forwarder. |
| The server-side Forwarder input, bound and `RUNNING` | Opens gRPC 13301 and 13302. Until it exists every forwarder reports `Code=<UNAVAILABLE>`, which looks exactly like a broken Ingress. See [forwarder-gelf-tcp-input.md](../forwarder-gelf-tcp-input.md). |
| `graylog.config.forwarder` enabled, ingest hostname resolving | The forwarder connects to `ingest-<host>`, not the web hostname. |
| An archive backend, with `backend_id` set in cluster config | No Helm value covers this. It is MongoDB state created through leader-only endpoints. See [archive-testing.md](archive-testing.md). |
| Prometheus reachable, for volume targeting | The chart's metrics exporter must be scraped. Port-forward it to 9090. |
| `kubectl`, `curl`, `jq`, and `yq` v4 | The mikefarah `yq`, not the Python one. They take different syntax. |
| Cluster headroom | 8000 msg/s rotates indices and fills disk faster than anyone expects. Check the DataNode PVCs first. |

Check the archive backend twice. An index set will happily carry archive retention pointing at no
backend at all, and it looks correct until the first rotation quietly archives nothing.

## What gets built

```
loadtest-sender (Deployment)          namespace: graylog-loadtest
    │ GELF/TCP 5555
    ▼
graylog-forwarder (Deployment + PVC)  namespace: graylog-loadtest
    │ gRPC 13301/13302, via ingest-<host>, TLS at the ALB
    ▼
Graylog                               namespace: graylog-helm
    │ stream rule: source == loadtest-1
    ▼
loadtest stream ──▶ loadtest index set ──▶ archive retention ──▶ S3
```

Seven objects across three places:

| Object | Where | Created by |
| --- | --- | --- |
| Index set `loadtest`, archive retention | MongoDB | `loadtest-api.sh` |
| Stream `loadtest` and its rule, started | MongoDB | `loadtest-api.sh` |
| Input profile and forwarder input, GELF TCP 5555 | MongoDB | `create-forwarder-input.sh` |
| Forwarder registered on node id `loadtest-1` | MongoDB | `create-forwarder-input.sh` |
| Namespace `graylog-loadtest` | cluster | `loadtest-up.sh` |
| Forwarder Deployment, Service, PVC, Secret | cluster | `k8s-run-forwarder.sh` |
| Sender Deployment producing continuous load | cluster | `k8s-send-to-forwarder.sh -L` |

Only the first two rows were new work. The forwarder half already existed in
the forwarder tool and needed nothing.

## Running it

A scenario file is the reproducible path, and the one to prefer:

```sh
cd <path to the loadtest tool>
cp profiles/example.yaml profiles/dev.yaml && chmod 600 profiles/dev.yaml   # once

./loadtest-scenario.sh show scenarios/archive.yaml --profile dev   # resolve everything, run nothing
./loadtest-scenario.sh up   scenarios/archive.yaml --profile dev
```

A profile holds the URL, namespace, kube context and both tokens. `profiles/` is
gitignored, so credentials stay out of anything committed and one scenario can run
against several environments. Exporting `GL_TOKEN` and `FWD_TOKEN` still works and
takes precedence.

`show` prints every resolved value and the exact commands before touching anything, which matters
because an unset key silently takes its default rather than erroring.

Running it by hand takes four commands in an order that cannot change, since nothing binds a port
until every server-side object exists:

```sh
./loadtest-api.sh https://helm.dev.graylog.cloud "$GL_TOKEN" -A
../forwarder/create-forwarder-input.sh https://helm.dev.graylog.cloud "$GL_TOKEN" \
  -n loadtest -t gelf-tcp -p 5555 -N loadtest-1
../forwarder/k8s-run-forwarder.sh graylog-loadtest \
  -H ingest-helm.dev.graylog.cloud -T "$FWD_TOKEN" -N loadtest-1 -p 5555 -t loadtest -x
../forwarder/k8s-send-to-forwarder.sh graylog-loadtest -L -- -r 8000 -w 16 -s loadtest-1
```

`loadtest-up.sh` wraps exactly those four and adds nothing else.

One namespace runs one scenario. The forwarder Deployment, its PVC and the single
node id in that PVC are all one-per-namespace, so bringing up a second scenario
repoints the pod and the first forwarder goes `DISCONNECTED`. Its registration,
stream and index set are untouched and it returns when you bring it back up.
Running two at once means giving each its own `forwarder.namespace`.

One value, the source tag `<name>-1`, ties the whole thing together. The generator stamps it on
every message, the stream rule matches it, the arrival check counts it, and the forwarder uses it
as its node id. Break it in one place and ingest keeps working while the index set stays empty,
which is the most confusing way this can fail.

## What Graylog does that its docs do not say

Five behaviours cost real time, and none of them announce themselves.

**Stream creation needs an `entity` wrapper.** Posting the stream body directly, the way every
older example shows, returns `RequestError: entity cannot be null` with a `reference_path` of
`CreateEntityRequest` and no hint that a wrapper is what it wants.

**`use_legacy_rotation: true` is mandatory for a size-based strategy, and this is the subtlest one
here.** 7.1.9 still offers `SizeBasedRotationStrategy`. It accepts it, stores it, and shows it back
in the API response. Then it ignores it, because `data_tiering` governs whenever
`use_legacy_rotation` is false. Setting the flag nulls `data_tiering` out, which is what makes the
strategy take effect. `loadtest-check.sh` reports `data tiering is in effect` when this has
happened.

**Data tiering cannot cycle faster than whole days.** Probed directly:

```
PT1H  400  Lifetime setting index_lifetime_min <PT1H> can only be a multiple of days
PT6H  400  ... can only be a multiple of days
P1D   200  accepted
```

So legacy rotation is not a compromise for a load test, it is the only option that cycles in
minutes. Anyone suggesting a switch to data tiering for *faster* cycling has it backwards. Tiering
is the right answer for hot/warm and for `archive_before_deletion`, and the wrong one for a test
that needs four rotations inside a coffee break.

**A stream is created paused.** It reads back `disabled: true` and routes nothing while looking
entirely healthy. `POST /streams/<id>/resume` returns 204 and fixes it.

**An index set referenced by a stream cannot be deleted**, and Graylog reports that as
`404 "Couldn't delete index set with ID <...>"` which never mentions the stream. Deletion is also
asynchronous, so a 204 is not proof. Delete the stream first, then poll until the index set is
actually gone.

Two smaller ones. Index prefixes cannot overlap in either direction, and the rejection
(`Index prefix 'ltprob' would conflict with existing index set prefix 'ltprobe'`) names both but
reads like a duplicate-title error. And document counts come from `.all.indices[]` with
`primary_shards`, not `all_shards`, or replicas double the number.

## Building the index set

Copy the default index set and change five fields. Do not write the payload from scratch: an index
set POST wants a dozen required fields and the set of them moves between versions, so a literal
body is a version trap.

```sh
DEFAULT=$(api GET "/system/indices/index_sets?limit=50" | jq '.index_sets[]|select(.default)')

api POST /system/indices/index_sets -d "$(printf '%s' "$DEFAULT" | jq \
  --arg n "$NAME" --arg p "$PREFIX" --argjson z "$ROTATE_BYTES" '
    del(.id, .default, .can_be_default, .creation_date)
    | .title = $n
    | .index_prefix = $p
    | .use_legacy_rotation = true
    | .rotation_strategy_class = "org.graylog2.indexer.rotation.strategies.SizeBasedRotationStrategy"
    | .rotation_strategy = {
        type: "org.graylog2.indexer.rotation.strategies.SizeBasedRotationStrategyConfig",
        max_size: $z
      }')"
```

Size-based rotation is deliberate. The 7.x default of time-based-size-optimizing is right in
production and wrong here, because a load test needs indices to go cold on a schedule the test
controls. At 8000 msg/s, stored documents run about 0.28 KB each, so a 512MiB index fills in
roughly four minutes.

The copy also resets retention to plain deletion before `-A` opts back in. A licensed instance
usually has archive retention on its default index set already, and inheriting that would make the
flag decorative.

Replicas default to 1, against the chart's test default of 0. At `rep 0` a DataNode restart
mid-run loses the only copy, and archives cannot save data the cluster already lost. See
[datanode-scale-in.md](../graylog/datanode-scale-in.md).

## Targeting volume instead of message rate

Capacity questions arrive as GB/day, not msg/s, and the two do not convert cleanly.

Measured on 7.1.9: about 625 msg/s of 220-byte GELF puts roughly 11 GB/day on the wire and
produces roughly 22 GB/day of `gl_traffic_input`. Graylog counts the decoded message with its added
fields, not the bytes the sender wrote, and the ratio shifts with message shape. So
`loadtest-target.sh` calibrates against the running system and solves for the rate rather than
computing one.

```sh
./loadtest-target.sh -d          # what is it doing now
./loadtest-target.sh -g 25 -b    # aim for 25 GB/day, measuring the floor first
```

> [!IMPORTANT]
> Anything else ingesting into the same Graylog counts toward these metrics, and Graylog's built-in
> Random/FakeHttp inputs are not shy. Two of them measured **7.16 GB/day of `gl_traffic_input` with
> our sender stopped completely** (10.56 decoded, 11.66 output). A 10 GB/day target is therefore
> 72% floor, and no sender rate can reach it. Pass `-b` to measure the floor or `-B` to state it.
> Without either you are targeting the namespace total, not your load.

Read rates from Prometheus, not from `/system/cluster/traffic`. That endpoint buckets hourly, so a
short sample reads zero and looks like silence. That is exactly how an early measurement here
produced a confident and completely wrong baseline of zero.

The Prometheus on this cluster scrapes every tenant, so `namespace="graylog-helm"` is not optional.
Leave it off and you are reading somebody else's load test.

## Verification

`loadtest-check.sh` runs five checks in an order chosen so each one clears a different hop:
forwarder connected, messages arriving, landing in our indices, indices rotating, archives written.
Read down to the first check that disagrees with the one above it.

A forwarder reporting `CONNECTED` with zero arrivals points at GELF framing, where a null-delimiter
mismatch accepts every connection and parses nothing. Arrivals with an empty index set points at
the stream rule.

A TCP connect proves nothing on its own, which is the trap the forwarder tooling was built around,
and `-L` mode sends without checking arrival. Count indexed documents or you are measuring hope.

For throughput read the sender's own per-second line from `kubectl logs`, never a laptop-side run.
`kubectl port-forward` tunnels every byte through the API server and caps well below what the
generator produces, so a disappointing number through a tunnel says nothing about the chart.

## Teardown

```sh
./loadtest-down.sh graylog-loadtest                                   # pods only
./loadtest-down.sh graylog-loadtest https://... "$GL_TOKEN" -S        # and stream, forwarder
./loadtest-down.sh graylog-loadtest https://... "$GL_TOKEN" -D -N -F  # everything
```

The default removes pods and leaves every byte of data alone, so re-running lands back where you
were. The index set needs `-D`, because deleting it drops the indices the archive catalog still
points at, and a catalog entry with no index behind it is worse than leftover data.

## What goes wrong

Ordered by how much time each one costs.

**Archive retention configured, nothing archived.** Either `backend_id` is unset, or every index is
still the active write index. Graylog refuses to act on the index it is writing to and logs
`Not executing index action NONE on current write index`. Rotation has to run at least
`max_number_of_indices` times before retention does anything, so a short run proves nothing about
archiving.

**Archiving during a DataNode rollout fails halfway.** Archiving holds an OpenSearch scroll open
for minutes and a restarting data node kills it, surfacing as a `NoSuchFileException` on a segment
that points nowhere useful. Never run a chart upgrade and an archive job together. This is worth
checking before the run rather than after: an earlier attempt here wasted twenty minutes measuring
a cluster that was mid-rollout and reporting one Graylog node where three were expected.

**A control loop that can command its actuator to infinity.** The first floor-aware version of
`loadtest-target.sh` computed 3.1×10¹⁵ msg/s and applied it, because when measured traffic sat
below the stated floor the sender's computed share clamped to epsilon and dividing by it exploded.
No harm followed, since the generator is bash over one socket and tops out a few thousand msg/s
whatever `-r` says, but that was luck. It now clamps the commanded rate, limits each step to 4x,
and refuses to solve when its own contribution falls within noise of the floor.

**The forwarder crash-loops on its journal.** A journal larger than the state PVC, after filesystem
overhead, fails a disk preflight at startup. `k8s-run-forwarder.sh` defaults `-j 2gb` against a 5Gi
volume. Raising the rate is no reason to raise `-j`, but raising run length is, and `-S` has to
move with it.

**The load is faster than the cluster.** The interesting failure, and the reason to build any of
this. It shows up as journal growth rather than sender errors, so watch `watch-pod-journal.sh`
alongside the throughput line. A sender happily reporting its target rate while the journal climbs
means the bottleneck sits downstream of everything this test builds.

**Empty bash arrays under `set -u`.** macOS ships bash 3.2, where `"${arr[@]}"` on an empty array
is an error rather than nothing. It bit two scripts here and will not reproduce on a Linux CI
runner with bash 5.

## Open questions

- Whether `ArchiveRetentionStrategy` still fires under legacy rotation on 7.1.9, or whether only
  tiering's `archive_before_deletion` works now. The archive doc only ever proved manually
  triggered archiving, so the retention-driven path is untested. `scenarios/archive.yaml` is built
  to settle it in about twenty minutes and has not been run to completion.
- Whether to add an unforwarded baseline that sends straight at a server input. Without it a
  disappointing number cannot distinguish a slow chart from a slow forwarder. Worth building once
  there is a number worth explaining.
- Whether any of this belongs in CI. Probably not, since it needs a licensed instance and an S3
  bucket, but a nightly run at a fixed rate would catch performance regressions that unit tests
  cannot.
