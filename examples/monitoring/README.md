# Graylog Helm Grafana dashboard

`grafana-dashboard.json` shows pod health, message flow, journal, HTTP API, storage, memory and OpenSearch
cluster health for one Graylog Helm release. It reads Prometheus only.

## What it needs

The dashboard shows nothing for a source that is not scraped. Each row below says which values turn the source on.

| Source | Used for | How to get it |
| --- | --- | --- |
| Graylog exporter | Throughput, buffers, journal, HTTP API | `graylog.service.metrics.enabled`, `graylog.service.metrics.expose` and `graylog.serviceMonitor.enabled`. See [values-example-monitoring.yaml](../values/values-example-monitoring.yaml). |
| Data Node exporter | Cluster health and shard panels | `datanode.exporter.enabled` and `datanode.exporter.serviceMonitor.enabled`, plus the API token and client certificate it depends on. See [the exporter guide](../../docs/datanode/exporter.md). |
| kube-state-metrics | Pod readiness, restarts, resource requests and limits, PVC links | Part of kube-prometheus-stack. |
| cAdvisor and kubelet | CPU, memory, volume usage | Part of kube-prometheus-stack. |

The Prometheus Operator CRDs must be installed for the ServiceMonitors.

## Import it

The file uses Grafana's v2 dashboard schema, the one behind dynamic dashboards. Your Grafana has to read that
format. In Grafana, open Dashboards, then New, then Import, and upload the file.

## Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| Data source | none | The Prometheus that scrapes the sources above. Pick it after importing. |
| Namespace | none | The namespace of the release. Lists every namespace that has Graylog or Data Node containers. |
| Graylog job | first match | The Prometheus job for Graylog's exporter. Prometheus names it after the Graylog Service, `<release>-svc`, so it changes with the release name. |
| Kube-state-metrics job | first match | The Prometheus job for kube-state-metrics. kube-prometheus-stack uses `kube-state-metrics`. |
| Data Node role | All | Limits the Data Node resource rows to node groups with that OpenSearch role. |

If a Graylog panel is empty, check the Graylog job first. It must list a value. An empty list means Prometheus
has no Graylog series in that namespace, so check the ServiceMonitor and that `graylog.service.metrics.expose`
is on.
