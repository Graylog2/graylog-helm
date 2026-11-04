# Health, metrics and availability

## High availability defaults

The chart applies these by default. Both are safe on single-node development
clusters and need no configuration for the common case.

- **Soft pod anti-affinity** on Graylog, Data Node and MongoDB pods, spreading
  each tier across nodes by `kubernetes.io/hostname`. It is
  `preferredDuringSchedulingIgnoredDuringExecution`, so pods still schedule when
  there aren't enough nodes to spread across. Setting `graylog.affinity` or
  `datanode.affinity` replaces the chart default entirely for that tier.
- **PodDisruptionBudgets** for Graylog (`minAvailable: 1`) and Data Node
  (`minAvailable: 2`), which keep node drains and cluster upgrades from evicting
  a whole tier at once. The Graylog PDB only renders at `replicas >= 2`. Disable
  with `graylog.podDisruptionBudget.enabled=false` /
  `datanode.podDisruptionBudget.enabled=false`. With `datanode.extraNodeGroups`,
  the chart renders one PDB per group by default; set
  `datanode.podDisruptionBudget.consolidated=true` for a single PDB spanning the
  primary group and every extra group instead. Either PDB can use
  `podDisruptionBudget.maxUnavailable` instead of `minAvailable`. Set one or the
  other, since Kubernetes rejects a PDB with both.
- **Reloader opt-out** on every Data Node ConfigMap/Secret
  (`datanode.reloader.autoReload: false`), so [Stakater
  Reloader](https://github.com/stakater/Reloader), if installed cluster-wide, does not
  auto-restart Data Node groups on config changes. With multiple node groups, Reloader
  restarts each group's StatefulSet independently, which can roll two groups at once. A
  PDB does not prevent this, since it only applies to the Eviction API, not a StatefulSet
  controller replacing its own pod. See the [node groups
  guide](../datanode/datanode-node-roles.md).

> [!NOTE]
> A PDB makes node drains block rather than proceed destructively. On a cluster
> with too few nodes to satisfy `minAvailable`, a drain will wait instead of
> completing. This is the intended protection, not a failure.


## Prometheus metrics

Graylog ships a Prometheus exporter. The chart enables it by default
(`graylog.service.metrics.enabled`), but Graylog binds it to `127.0.0.1:9833`, so out of
the box it is reachable only from inside the pod, which is all
[`preStopDrain`](../graylog-message-handling.md#automatic-drain-on-shutdown) needs.

To scrape it, set `expose`. That binds the exporter to `0.0.0.0` and publishes the
`metrics` port on the Service:

```yaml
graylog:
  service:
    metrics:
      enabled: true
      expose: true
```

> [!WARNING]
> The exporter is **unauthenticated**. Once exposed, anything that can reach the pod can
> read it. Restrict access with a NetworkPolicy, and leave `expose` off if you are not
> scraping.

With the Prometheus Operator installed, the chart can create the ServiceMonitor too. Most
Operator installs select ServiceMonitors by label, so set whatever yours requires:

```yaml
graylog:
  service:
    metrics:
      expose: true
  serviceMonitor:
    enabled: true
    interval: 30s
    labels:
      release: kube-prometheus-stack
```

The chart fails the render if `serviceMonitor.enabled` is set without `metrics.expose`,
rather than creating a ServiceMonitor whose every scrape would be refused.

Changing `graylog.service.ports.metrics` moves the exporter, the container port, the
Service port and the drain's metrics URL together.


## Health probes

The readiness probe is a StatefulSet's only rollout throttle. Nothing else paces
a rolling update, so a probe that goes green before the application can serve
lets the rollout move on anyway. So each default below checks that the pod can
serve, not that a port is open.

| Tier | Startup / Readiness | Liveness |
|---|---|---|
| Graylog | `GET /api/system/lbstatus` | TCP connect on the app port |
| Data Node | TCP connect on the OpenSearch port (`9200`) | TCP connect on the Data Node API port (`8999`) |

### Graylog

Readiness uses `/api/system/lbstatus`, Graylog's own unauthenticated
load-balancer status endpoint, which returns `200 ALIVE` or `503 DEAD`. A TCP
connect goes green the moment Jetty binds the port, before the node has rejoined
the cluster, restarted its inputs or worked through journal recovery.

Liveness stays a TCP connect on purpose. `DEAD` means "stop sending me traffic",
which is what graceful shutdown and a manual drain both set. Liveness on
`lbstatus` would have kubelet kill a healthy pod that is draining or parked for
maintenance.

That split is what makes draining work. Setting `lb_status` to `dead` takes a pod
out of the Service endpoints on its own, without deleting it:

```sh
# take a pod out of rotation; readiness drops it from endpoints within ~1 minute
kubectl exec -n graylog graylog-0 -- curl -su "admin:$PASS" -H 'X-Requested-By: cli' \
  -X PUT http://localhost:9000/api/system/lbstatus/override/dead
```

> [!IMPORTANT]
> Address the pod, not the Service. Once readiness drops the pod, the Service no
> longer routes to it, so a request sent to the Service cannot reach it to put it
> back. `kubectl exec` into the pod as above, or use its DNS name, IP or
> `kubectl port-forward`, to set it back to `alive`.

### Data Node

Readiness watches the OpenSearch HTTP port rather than the Data Node API port.
The Data Node binds its own REST API roughly 30 seconds before it starts
OpenSearch on an idle single-node cluster, and the gap grows when there are
shards to recover. A probe on `8999` reports `Ready` while OpenSearch is still
down, and a rolling update would take down the next Data Node on the strength of
that.

> [!NOTE]
> Data Node readiness proves OpenSearch is listening. It cannot gate on shard
> recovery or cluster-green. Both Data Node ports serve HTTPS with
> authentication and the image ships no HTTP client, so there is no
> unauthenticated health endpoint to probe. Check cluster health yourself
> between Data Node restarts.

### Startup probes

Startup probes on both tiers hold liveness and readiness off until the process
has booted, so a first-node MongoDB migration or a large journal replay cannot
trip the liveness budget. `failureThreshold x periodSeconds` is the whole boot
budget, 5 minutes by default. Raise that rather than loosening liveness.

### Custom probe handlers

Every probe accepts its own handler (`httpGet`, `tcpSocket`, `exec`, `grpc`) in
standard Kubernetes syntax, which replaces the chart default for that probe:

```yaml
datanode:
  readinessProbe:
    httpGet:
      path: /_cluster/health
      port: 9200
      scheme: HTTPS
```
