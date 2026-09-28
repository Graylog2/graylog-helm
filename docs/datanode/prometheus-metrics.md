# Data Node Prometheus metrics

Data Node has no built-in metrics exporter, and Graylog doesn't document a way to scrape
it. This chart adds an `elasticsearch_exporter` sidecar as a workaround, the same one the
[Graylog community forum](https://community.graylog.org/t/datanode-prometheus-metrics/37024)
points to. Test it before you rely on it.

## Why this needs a client certificate

Data Node's OpenSearch API is HTTPS with mTLS client-certificate auth. There's no
username or password, and the chart can't generate a certificate Data Node will trust,
because Data Node runs its own internal CA.

## Setup

1. In the Graylog UI, generate a client certificate for Data Node (System → Data Nodes →
   Generate Client Certificate, or wherever your version puts it). You'll get a cert, a
   key, and the CA that signed Data Node's server certificate.

2. Create a Secret from those three files:

   ```sh
   kubectl create secret generic datanode-metrics-cert \
     --from-file=tls.crt=./client.crt \
     --from-file=tls.key=./client.key \
     --from-file=ca.crt=./ca.crt
   ```

3. Read the certificate's subject DN:

   ```sh
   openssl x509 -in client.crt -noout -subject
   ```

   Drop the `subject=` prefix openssl prints, that's just its own label. If the output is
   `subject=CN=monitor-2`, the DN is `CN=monitor-2`.

4. Set values:

   ```yaml
   datanode:
     metrics:
       enabled: true
       existingSecretName: datanode-metrics-cert
       adminDN: "CN=monitor-2"
   ```

This adds the sidecar to every Data Node pod. It authenticates to
`https://localhost:9200` with the client certificate and re-exposes the response as
plain HTTP Prometheus metrics on the `metrics` port (`9114` by default). That port isn't
authenticated, so restrict access with a NetworkPolicy if the Service is reachable from
outside the pod.

## ServiceMonitor

If you're running the Prometheus Operator:

```yaml
datanode:
  serviceMonitor:
    enabled: true
    labels:
      release: kube-prometheus-stack
```

The chart fails the render if `serviceMonitor.enabled` is set without `metrics.enabled`,
or if `metrics.enabled` is set without both `existingSecretName` and `adminDN`.

## Checking it worked

```sh
# Data Node picked up the admin_dn setting
kubectl logs <datanode-pod> | grep -i "pass-through"

# the sidecar authenticated and is scraping
kubectl logs <datanode-pod> -c opensearch-exporter

# metrics are flowing
kubectl port-forward <datanode-pod> 9114:9114
curl http://localhost:9114/metrics | head -30
```
