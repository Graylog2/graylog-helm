# Data Node metrics exporter

The chart can run the Prometheus [elasticsearch-exporter](https://github.com/prometheus-community/elasticsearch_exporter)
against the Data Nodes' OpenSearch API. It reports cluster health, node stats, shard counts and per-index stats
on a Service that Prometheus scrapes. It is off by default.

## Requirements

The exporter has no password. It signs in with the [Data Node client certificate](client-cert.md), and a Job
issues that certificate by calling Graylog's API with a token. So the API token and the client certificate
must both be on before the exporter can start.

| Requirement | Why |
| --- | --- |
| `graylog.apiToken.enabled: true` | The Job needs a token to ask Graylog for the certificate. |
| `ca_clientcert:create` in `graylog.apiToken.permissions` | Graylog does not let a service account hold the Admin role, so the token's user needs this one permission. |
| `datanode.clientCert.enabled: true` | Issues the certificate and stores it in a Secret. |
| `datanode.exporter.enabled: true` | Runs the exporter. |

With `datanode.exporter.enabled` on and `datanode.clientCert.enabled` off, `helm install` and `helm upgrade`
fail and name the missing value. `datanode.clientCert` in turn fails without `graylog.apiToken.enabled`.

The ServiceMonitor needs the Prometheus Operator CRDs. Without them, leave `serviceMonitor.enabled` off and
point your scraper at the Service.

## Enable it

```yaml
graylog:
  apiToken:
    enabled: true
    roles:
      - Reader
    permissions:
      - ca_clientcert:create

datanode:
  clientCert:
    enabled: true
  exporter:
    enabled: true
    serviceMonitor:
      enabled: true
      labels:
        release: kube-prometheus-stack
```

Set the ServiceMonitor `labels` to match your Prometheus. Its `serviceMonitorSelector` shows which label it
selects on.

On a first install, pass a `--timeout` longer than the Jobs need, for example `--timeout 15m`. The exporter pod
waits in `ContainerCreating` until the client certificate Job writes the Secret, then starts by itself.

## What the chart creates

- A Deployment named `<release>-datanode-exporter`, with one replica.
- A Service with the same name, on port 9114.
- A ServiceMonitor with the same name, when `serviceMonitor.enabled` is true.

The Deployment mounts the certificate Secret read-only and connects to the first Data Node pod of the primary
group with `--es.all`, so one exporter reports every node. The ServiceMonitor sets the `instance` label to
`<release>-datanode`. The series describe the cluster, not the exporter pod, so the pod's address would
mislead.

## Check that it works

```sh
kubectl -n <namespace> get pods -l app.kubernetes.io/component=datanode-exporter
kubectl -n <namespace> port-forward svc/<release>-datanode-exporter 9114:9114
curl -s localhost:9114/metrics | grep -E 'clusterinfo_up|cluster_health_status'
```

A working exporter returns `elasticsearch_clusterinfo_up 1`, and `elasticsearch_cluster_health_status` is 1
for the cluster's current color.

The pod's probes only prove the exporter process answers. They stay green when OpenSearch rejects the
certificate, and the only sign is `HTTP Request failed with code 403` in the logs. Alert on
`elasticsearch_clusterinfo_up == 0`.

Series worth graphing:

| Metric | Meaning |
| --- | --- |
| `elasticsearch_clusterinfo_up` | 1 when the exporter reaches OpenSearch with its certificate. |
| `elasticsearch_cluster_health_status` | One series per color. The current color is 1. |
| `elasticsearch_cluster_health_number_of_nodes` | Nodes in the cluster. |
| `elasticsearch_cluster_health_unassigned_shards` | Shards with no node. |
| `elasticsearch_indices_docs`, `elasticsearch_indices_store_size_bytes` | Per node, with a `name` label. |

## Certificate renewal

The certificate lasts 30 days. The client certificate Job reissues it only during a `helm upgrade` inside the
last `datanode.clientCert.renewBeforeDays` days. If you do not upgrade for 30 days, the certificate expires
and `elasticsearch_clusterinfo_up` drops to 0.

The exporter reads the certificate once, at startup, so it needs a restart after a reissue. The chart adds
`secret.reloader.stakater.com/reload` to the Deployment, and [Stakater Reloader](https://github.com/stakater/Reloader)
restarts the pod when that Secret changes. If your cluster has no Reloader, restart it yourself after an
upgrade that reissued the certificate.

```sh
kubectl -n <namespace> rollout restart deployment/<release>-datanode-exporter
```

Set `datanode.exporter.reloader.enabled: false` to remove the annotation.

## Limits

- The exporter talks to one pod, the first Data Node of the primary group. A node certificate names only its
  own pod, so the exporter cannot go through the headless Service. While that pod is down you get no metrics.
- The default role is read-only. If you set `datanode.clientCert.roleDefinition`, keep `cluster_monitor`,
  `indices_monitor` and `indices:admin/aliases/get`. Drop one and the matching calls return 403.
- `indices` is the most expensive collector. On a cluster with thousands of indices, set
  `datanode.exporter.indices: false`.

## Values

Every value sits under `datanode.exporter`.

| Value | Default | Purpose |
| --- | --- | --- |
| `enabled` | `false` | Run the exporter. Needs `datanode.clientCert.enabled`. |
| `image.repository`, `image.tag`, `image.pullPolicy` | `quay.io/prometheuscommunity/elasticsearch-exporter`, `v1.11.0`, `IfNotPresent` | Exporter image. |
| `image.imagePullSecrets` | `[]` | Overrides `global.imagePullSecrets` for this image. |
| `all` | `true` | Report every node, not only the one it connects to. |
| `indices` | `true` | Per-index series. |
| `shards` | `false` | Per-shard series. There are a lot of them. |
| `extraArgs` | `[]` | Extra exporter flags, for example `--es.timeout=10s`. |
| `reloader.enabled` | `true` | Add the Reloader annotation for the certificate Secret. |
| `replicas` | `1` | Deployment replicas. |
| `service.type`, `service.port` | `ClusterIP`, `9114` | Service settings. |
| `resources` | 10m CPU and 32Mi request, 200m CPU and 128Mi limit | Container resources. |
| `podSecurityContext`, `containerSecurityContext` | Restricted, read-only root filesystem | Security contexts. |
| `nodeSelector`, `tolerations`, `affinity`, `topologySpreadConstraints`, `priorityClassName` | empty | Scheduling. |
| `extraEnv` | `[]` | Environment variables in full EnvVar syntax. |
| `labels`, `annotations` | `{}` | Added to the Deployment. |
| `podLabels`, `podAnnotations` | `{}` | Added to the pod. |
| `service.labels`, `service.annotations` | `{}` | Added to the Service. |
| `serviceMonitor.enabled` | `false` | Create the ServiceMonitor. |
| `serviceMonitor.interval`, `scrapeTimeout`, `path` | `30s`, `10s`, `/metrics` | Scrape settings. |
| `serviceMonitor.labels`, `annotations` | `{}` | Added to the ServiceMonitor. Match your Prometheus selector. |
| `serviceMonitor.relabelings`, `metricRelabelings` | `[]` | Passed through. The `instance` relabeling always comes first. |
| `serviceMonitor.honorLabels` | `false` | Keep metric labels that collide with the ones Prometheus adds. |
| `serviceMonitor.namespaceSelector` | release namespace | Where Prometheus looks for the Service. |
