# API token Job

The chart can create a Graylog service user and an API token for it, then store the token in a Kubernetes
Secret. Runbooks, scripts and other tools read the Secret instead of someone copying a token out of the UI.

It is off by default.

## Enable it

```yaml
graylog:
  apiToken:
    enabled: true
    roles:
      - Reader
```

`roles` defaults to `Reader`, which is read-only. Graylog refuses the Admin role for service accounts, so the
chart fails the render if you list it. Pick a role that allows every endpoint your consumers call.

Install or upgrade as usual. Helm waits for the Job. A cold install can take 5 to 10 minutes before Graylog
answers, because Graylog waits on the Data Nodes, and Helm's default `--timeout` is 5m. Pass a longer one on a
first install:

```sh
helm upgrade --install graylog charts/graylog -n graylog -f values.yaml --timeout 15m
```

Upgrading a release that was installed before `graylog.apiToken` existed with `--reuse-values` fails when you enable
the token. Helm reuses the old values, which lack the chart's defaults for this block, and the render stops with a
message saying so. Use `--reset-then-reuse-values`, or pass your values with `-f`.

## How it works

A post-install and post-upgrade hook Job runs these steps.

1. Waits up to `waitSeconds` for Graylog to answer on its in-cluster Service.
2. Reads the token Secret. If the token in it still authenticates, the Job exits.
3. Signs in as root and creates the service user if it is missing.
4. Mints a new token and writes it to the Secret.
5. Revokes older tokens with the same name, only after the Secret write succeeds.

Graylog shows a token once, so the Job writes the Secret itself. Helm does not own it. The Secret and the
service user both survive `helm uninstall`.

Passwords and tokens never appear on a command line. The scripts hand curl its credentials in a config file under a
private directory in `/tmp`, an in-memory volume, and send request bodies through stdin.

The Job's ServiceAccount, Role and RoleBinding are hooks too and are deleted when it succeeds. The Role can
create Secrets and read or patch only the token Secret. A failed run does not delete them, see
[After a failed run](#after-a-failed-run). The renewal CronJob and its own ServiceAccount and
Role are not hooks. That Role can only read and patch the token Secret.

## Where the Job gets the root password

The chart stores only a hash of the root password, so the Job needs the plaintext from somewhere. It uses the
first of these that applies.

1. `graylog.apiToken.bootstrap.existingSecret`, read from `passwordKey`.
2. `graylog.config.rootPassword`, copied into a hook Secret that is deleted with the Job.
3. The plaintext in the chart's backup Secret, which exists only when the chart generated the password.

With `global.existingSecretName` the chart has none of these, so set `bootstrap.existingSecret` or the render
fails.

## Use the token

The Secret is named `<release fullname>-api-token` unless you set `graylog.apiToken.secretName`. It has three
keys, `token`, `username` and `userid`. Send the token as the Basic auth username, with `token` as the password.
The renewal CronJob reads `userid`, because a service user cannot look up its own id.

```sh
TOKEN=$(kubectl -n graylog get secret graylog-api-token -o jsonpath='{.data.token}' | base64 -d)
curl -u "$TOKEN:token" -H "Accept: application/json" https://graylog.example.com/api/system
```

## Expiry and renewal

Tokens expire after `ttl` (default `P90D`). A CronJob renews the token before that happens, so a cluster that
nobody upgrades for months keeps a working token. It is on by default and runs daily at 03:17.

Each run does this. During the first minutes of an install the Secret does not exist yet, because the hook Job is
still waiting for Graylog. Runs in that window log it and exit without failing.

1. Reads the token from the Secret and signs in with it. There is no root password involved.
2. Lists the service user's tokens and reads the expiry of the one named `tokenName`.
3. Exits if more than `renew.before` (default `P14D`) remains.
4. Otherwise mints a new token with the old one and writes it to the Secret.
5. Deletes the old token only after the Secret write succeeds. If the write fails, it deletes the new token
   instead, so nothing is left orphaned.

Consumers that read the Secret on every request pick up the new token on their own. A pod that took the token
from an environment variable keeps the old one until it restarts, and the old token stops working the moment
it is deleted. Mount the Secret as a file, or restart the pod when the Secret changes.

`before` uses the same ISO-8601 durations as `ttl`, and as the token settings in the Graylog UI. Days, hours,
minutes and seconds work (`P14D`, `PT36H`, `P1DT12H`). It must be shorter than `ttl`, and the schedule must fire
more often than `before`. The render fails when `ttl` is also in days, hours, minutes or seconds and `before` is
not smaller.

### What the user needs

Renewal needs the service user to list, create and remove its own tokens. Graylog gives a normal user those
rights, but not a service account, so the chart grants them when it creates the user:

```
users:tokencreate,tokenlist,tokenremove:<username>
```

Keep that comma form if you grant it yourself. Graylog removes the plain `users:tokenlist:<name>` and
`users:tokenremove:<name>` strings from a service account when it saves them, so granting the three separately
lets the user mint a token but not see its expiry or delete the old one.

A user created before renewal existed, or one you created yourself, does not have the permission. Add it in
_System > Users and Teams_ or through the API. Until then the CronJob fails with a message that names the
permission.

A token that holds this permission can mint further tokens for its own user, which is how renewal works.
Someone who steals the token can do the same until you delete the user's tokens. Keep the Secret's access
narrow, and delete the user to cut it off.

### When renewal cannot help

A token that has already expired, or was revoked, cannot mint its own replacement. The CronJob logs that the
token no longer authenticates and fails. Run `helm upgrade`. The hook Job signs in as root and mints a new
token. To rotate on demand, delete the Secret and run `helm upgrade`.

Turn renewal off with `graylog.apiToken.renew.enabled=false`. The token then expires on its `ttl` unless you
upgrade before it does.

Failed runs show up as failed Jobs. `kubectl logs job/<name>` shows why, and `failedJobsHistoryLimit` (default
3) controls how many are kept. Alert on failed Jobs with kube-state-metrics if you want to hear about it before
the token expires.

## After a failed run

Helm deletes the failed Job and its logs. It does not delete the Job's ServiceAccount, Role and RoleBinding, or the
bootstrap Secret that holds the root password when you set `graylog.config.rootPassword`. Helm applies
`hook-failed` to the hook that failed and runs `hook-succeeded` for the others only after the whole phase finishes.
The next successful `helm upgrade` replaces them. To remove them sooner, or after you uninstall, run this with your
release's fullname:

```sh
kubectl -n graylog delete serviceaccount,role,rolebinding graylog-api-token
kubectl -n graylog delete secret graylog-api-token-bootstrap --ignore-not-found
```

Fullnames longer than 36 characters are cut to 36 in these names, so `kubectl -n graylog get role` shows the real one.
The bootstrap Secret exists only when you set `graylog.config.rootPassword`.

## Monitoring example

`examples/values/values-example-extra-objects.yaml` runs a json_exporter that reads cluster health with this
token. It turns on `graylog.apiToken`, with the default `Reader` role, and mounts the `<release fullname>-api-token`
Secret, with the `token` key as the Basic auth username and the literal password `token`. Nothing needs to exist
before the install.

For Data Node metrics, use the [Data Node exporter](../datanode/exporter.md) instead. It reports cluster health
with a client certificate, and the example dashboard reads its series.

## Values

All keys sit under `graylog.apiToken`.

| Value | Default | Purpose |
| --- | --- | --- |
| `enabled` | `false` | Create the service user, token and Secret. |
| `secretName` | `""` | Secret that receives the token. Empty uses `<release fullname>-api-token`. |
| `username` | `helm-automation` | Service user. Created if missing, reused if present. |
| `roles` | `[Reader]` | Roles for a new user. Must not include Admin. |
| `permissions` | `[]` | Extra permissions for a new user, such as `ca_clientcert:create`. The renewal grant is added to these. An existing user is not changed. |
| `tokenName` | `helm` | Name the token carries in Graylog. |
| `ttl` | `P90D` | ISO-8601 token lifetime. The schema rejects anything else. |
| `bootstrap.existingSecret` | `""` | Secret holding the root password. Required with `global.existingSecretName`. |
| `bootstrap.passwordKey` | `GRAYLOG_ROOT_PASSWORD` | Key in that Secret. |
| `tls.caSecret.name` | `""` | Secret holding the CA that signed Graylog's certificate, for `graylog.config.tls.enabled`. The Job and the CronJob mount it and verify against it. The certificate has to cover `<service>.<namespace>.svc.cluster.local`. |
| `tls.caSecret.key` | `ca.crt` | Key in that Secret that holds the CA certificate. |
| `insecureSkipVerify` | `false` | Skip certificate checks. Prefer `tls.caSecret`. Setting both fails the render. |
| `waitSeconds` | `720` | How long the Job waits for Graylog. |
| `activeDeadlineSeconds` | `780` | Hard limit for the Job. |
| `backoffLimit` | `3` | Job retries. |
| `image.repository`, `image.tag`, `image.imagePullPolicy` | `curlimages/curl`, `8.17.0`, `IfNotPresent` | Image for the Job and the CronJob. |
| `image.imagePullSecrets` | `[]` | Overrides `global.imagePullSecrets` for this image. |
| `resources` | `{}` | Job container resources. |
| `serviceAccount.automount` | `true` | `automountServiceAccountToken` for both ServiceAccounts and pods. Both call the Kubernetes API with that token, so `false` breaks them unless your cluster provides one another way. |
| `podSecurityContext` | non-root, UID 100, `RuntimeDefault` seccomp | Pod security context for the Job and the CronJob. Keys merge over the defaults. |
| `containerSecurityContext` | no escalation, read-only root, drop `ALL` | Container security context for both. |
| `nodeSelector`, `tolerations`, `affinity`, `priorityClassName` | empty | Scheduling for both. |
| `extraEnv` | `[]` | Extra environment variables for both, in full `EnvVar` syntax. |
| `labels`, `annotations` | `{}` | Added to the Job, its pod and its RBAC objects. |
| `secretLabels`, `secretAnnotations` | `{}` | Added to the token Secret when the Job creates it. An existing Secret keeps what it has. |
| `renew.enabled` | `true` | Run the renewal CronJob. |
| `renew.schedule` | `17 3 * * *` | Cron expression. |
| `renew.before` | `P14D` | Renew when this much time or less remains, as an ISO-8601 duration. Must be shorter than `ttl`. |
| `renew.backoffLimit`, `renew.activeDeadlineSeconds` | `2`, `300` | Retries and time limit for one run. |
| `renew.startingDeadlineSeconds` | `3600` | How late a missed run may still start. |
| `renew.successfulJobsHistoryLimit`, `renew.failedJobsHistoryLimit` | `1`, `3` | Finished Jobs kept. |
| `renew.resources` | `{}` | Renewal container resources. |
| `renew.labels`, `renew.annotations` | `{}` | Added to the CronJob, its pod and its RBAC objects, on top of the API token ones. |

Keep `waitSeconds` and `activeDeadlineSeconds` under your Helm `--timeout`.

## Limits

- Needs Graylog 6.3.12, 7.0.7, 7.1.2 or newer. Older releases let any user revoke other users' tokens
  (CVE-2026-55867).
- A failed run removes only the Job, and its logs go with it. Helm's error names the failed hook. To read the logs,
  follow them while the Job runs with `kubectl logs -f job/<release>-api-token`. The other objects stay, see
  [After a failed run](#after-a-failed-run).
- The Secret and service user are not removed on uninstall. Delete them yourself if you want them gone.
- The Job image needs a shell, curl, sed, grep and base64. The default is `curlimages/curl`.
