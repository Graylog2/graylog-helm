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

## Renewal

The certificate lasts `lifetime`, 30 days by default. A CronJob reissues it once less than `renewBeforeDays`
remain, so a cluster that is never upgraded keeps a working certificate. It is on by default and runs daily at
03:37.

Each run reads the Secret and exits if the certificate has more than `renewBeforeDays` left. Otherwise it asks
Graylog for a new certificate with the API token, decrypts the key and patches `ca.crt`, `tls.crt` and `tls.key`
into the Secret in one request. A failed write leaves the old certificate in place.

If the Secret is gone, for example because someone deleted it, a run issues a certificate and creates the Secret
again with the same labels. You do not need a `helm upgrade`. Trigger a run by hand to recover straight away:

```sh
kubectl -n <namespace> create job recover-cert --from=cronjob/<release fullname>-datanode-client-cert-renew
```

The CronJob is lighter than the hook Job. It never signs in as root, never reads the password secret and never
calls the Data Node. Its Role can read and patch the one certificate Secret, and it can create Secrets, because
Kubernetes cannot limit `create` to a name. It cannot read, change or delete any other Secret. It needs the
OpenSearch role and mapping to exist already, which the install hook Job creates. A run that starts before the hook
has finished fails without creating anything, because Graylog refuses a certificate for a role with no mapping.

Two things stop it.

- An expired or revoked API token cannot ask for anything. `graylog.apiToken.renew` keeps the token fresh. If it
  lapsed anyway, `helm upgrade` mints a new one and reissues the certificate.
- The role or its mapping is gone. The run fails and says so. `helm upgrade` recreates both.

A consumer that reads the certificate only at startup, such as a metrics exporter, needs a restart after each
reissue. Stakater Reloader can restart it when the Secret changes.

Set `datanode.clientCert.renew.enabled: false` to renew only on `helm upgrade`. `renewBeforeDays` must be shorter
than `lifetime`, or the render fails.

Check the last run:

```sh
kubectl -n <namespace> get cronjob,jobs | grep datanode-client-cert-renew
kubectl -n <namespace> logs job/<job name from the list above>
```

A run that has nothing to do logs the certificate's expiry and `nothing to do`. Fullnames longer than 25
characters are cut to 25 in the CronJob's name, so `kubectl get cronjob` shows the real one.

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
  age out. A reissue happens in the renewal CronJob or on the next `helm upgrade`, whichever comes first inside
  the `renewBeforeDays` window.
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
| `renewBeforeDays` | `10` | Reissue inside this window, on upgrade or in the renewal CronJob. Must be shorter than `lifetime`. |
| `waitSeconds` | `240` | How long the Job waits for Graylog and the Data Node. |
| `image.repository`, `image.tag`, `image.imagePullPolicy` | Graylog image, `IfNotPresent` | Image for the Job and the CronJob. |
| `image.imagePullSecrets` | `[]` | Overrides `global.imagePullSecrets` for this image. |
| `serviceAccount.automount` | `true` | `automountServiceAccountToken` for both. They need it to write the Secret. |
| `podSecurityContext`, `containerSecurityContext` | Restricted, UID 1100 | Security contexts for both. |
| `nodeSelector`, `tolerations`, `affinity`, `priorityClassName` | empty | Scheduling for both. |
| `extraEnv` | `[]` | Environment variables for both, in full EnvVar syntax. |
| `resources` | `{}` | Job resources. The CronJob has its own under `renew`. |
| `labels`, `annotations`, `secretLabels` | `{}` | Added to the Job objects, or to the certificate Secret. |
| `renew.enabled` | `true` | Run the renewal CronJob. |
| `renew.schedule` | `37 3 * * *` | Cron expression. It must fire more often than `renewBeforeDays`. |
| `renew.backoffLimit`, `renew.activeDeadlineSeconds` | `2`, `300` | Retries and time limit for one run. |
| `renew.startingDeadlineSeconds` | `3600` | How late a missed run may still start. |
| `renew.successfulJobsHistoryLimit`, `renew.failedJobsHistoryLimit` | `1`, `3` | Finished runs to keep. |
| `renew.resources` | `{}` | CronJob container resources. |
| `renew.labels`, `renew.annotations` | `{}` | Added to the CronJob, its pod and its RBAC objects, over the ones above. |
