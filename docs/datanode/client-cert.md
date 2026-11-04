# Data Node client certificate

The chart can issue a client certificate for the Data Node's OpenSearch API and store it in a Kubernetes
Secret. A tool in the cluster, such as a Prometheus exporter, uses it to call port 9200 with no password.

It is off by default and needs the [API token Job](../graylog/api-token.md).

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
```

Graylog does not let a service account hold the Admin role, so the token's user needs `ca_clientcert:create`
as an extra permission. `graylog.apiToken.permissions` grants it when the Job creates the user. A user that
already exists keeps its permissions, so add it yourself in that case.

Pass a `--timeout` longer than the two Jobs need on a first install, for example `--timeout 15m`.

## How it works

A post-install and post-upgrade hook Job runs after the API token Job.

1. Waits for Graylog and the Data Node.
2. Reads the Secret. If its certificate is valid for more than `renewBeforeDays`, the Job exits.
3. Creates the OpenSearch role and an empty role mapping on the Data Node if they are missing. Graylog's
   API cannot do this, and it refuses to issue a certificate for a role with no mapping. The Job signs a
   short-lived JWT with the chart's password secret to call the security API.
4. Asks Graylog for a certificate with `POST /api/ca/clientcert`.
5. Decrypts the private key and writes `ca.crt`, `tls.crt` and `tls.key` to the Secret.

An existing role or mapping is never overwritten. Edit one yourself with a PUT on the security API.

The Secret is named `<release fullname>-datanode-client-cert` unless you set `datanode.clientCert.secretName`.
Helm does not own it, so it survives `helm uninstall`.

## Use the certificate

The default role is read-only. It has `cluster_monitor` plus `indices_monitor` and
`indices:admin/aliases/get` on every index. It cannot search or change anything.

```sh
curl --cert tls.crt --key tls.key --cacert ca.crt \
  https://graylog-datanode-0.graylog-datanode-svc.graylog.svc.cluster.local:9200/_cluster/health
```

Set `datanode.clientCert.roleDefinition` for different permissions. The certificate carries no role.
OpenSearch looks up the CN in the role mapping.

The key is stored decrypted, so anyone who can read the Secret can act as that role. Restrict access to it.

## Limits

- A client verifies a Data Node by its full pod name only. No form of the headless Service name matches the
  certificate, so point the client at a pod address.
- Reissuing does not revoke the old certificate. Revoking a hand-made role returns a 500, so old certificates
  age out. A reissue happens on the next `helm upgrade` inside the `renewBeforeDays` window.
- On the first run the Job has no CA to check the Data Node against, so it skips verification for its calls
  to the security API inside the cluster. Later runs verify against the CA in the Secret.
- The Job image needs sh, curl, openssl, sed, grep and base64. The default is the Graylog image.

## Values

| Value | Default | Purpose |
| --- | --- | --- |
| `principal` | `graylog-client` | Certificate CN, the OpenSearch user. |
| `role` | `graylog_metrics_reader` | Role and mapping the principal joins. |
| `roleDefinition` | read-only stats | Role the Job creates if missing. |
| `lifetime` | `P30D` | ISO-8601 certificate lifetime. |
| `renewBeforeDays` | `10` | Reissue on upgrade inside this window. |
| `waitSeconds` | `240` | How long the Job waits for Graylog and the Data Node. |
| `image.repository`, `image.tag` | Graylog image | Job image. |
| `labels`, `annotations`, `secretLabels` | `{}` | Added to the Job objects, or to the certificate Secret. |
