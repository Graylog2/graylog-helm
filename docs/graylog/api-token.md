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

`roles` must be set. Graylog refuses the Admin role for service accounts, so the chart fails the render if
you list it. Pick a role that allows every endpoint your consumers call.

Install or upgrade as usual. Helm waits for the Job, and Helm's default `--timeout` is 5m, so pass a longer
one on a first install:

```sh
helm upgrade --install graylog charts/graylog -n graylog -f values.yaml --timeout 10m
```

## How it works

A post-install and post-upgrade hook Job runs these steps.

1. Waits up to `waitSeconds` for Graylog to answer on its in-cluster Service.
2. Reads the token Secret. If the token in it still authenticates, the Job exits.
3. Signs in as root and creates the service user if it is missing.
4. Mints a new token and writes it to the Secret.
5. Revokes older tokens with the same name, only after the Secret write succeeds.

Graylog shows a token once, so the Job writes the Secret itself. Helm does not own it. The Secret and the
service user both survive `helm uninstall`.

The Job's ServiceAccount, Role and RoleBinding are hooks too and are deleted when it succeeds. The Role can
create Secrets and read or patch only the token Secret.

## Where the Job gets the root password

The chart stores only a hash of the root password, so the Job needs the plaintext from somewhere. It uses the
first of these that applies.

1. `graylog.apiToken.bootstrap.existingSecret`, read from `passwordKey`.
2. `graylog.config.rootPassword`, copied into a hook Secret that is deleted with the Job.
3. The plaintext in the chart's backup Secret, which exists only when the chart generated the password.

With `global.existingSecretName` the chart has none of these, so set `bootstrap.existingSecret` or the render
fails.

## Use the token

The Secret is named `<release fullname>-api-token` unless you set `graylog.apiToken.secretName`. It has two
keys, `token` and `username`. Send the token as the Basic auth username, with `token` as the password.

```sh
TOKEN=$(kubectl -n graylog get secret graylog-api-token -o jsonpath='{.data.token}' | base64 -d)
curl -u "$TOKEN:token" -H "Accept: application/json" https://graylog.example.com/api/system
```

## Expiry and rotation

Tokens expire after `ttl` (default `P90D`). The next `helm upgrade` finds the expired token, mints a new one
and revokes the old one. To rotate on demand, delete the Secret and run `helm upgrade`.

## Values

| Value | Default | Purpose |
| --- | --- | --- |
| `username` | `helm-automation` | Service user. Created if missing, reused if present. |
| `roles` | `[Admin]` | Roles for a new user. Must not include Admin. |
| `tokenName` | `helm` | Name the token carries in Graylog. |
| `ttl` | `P90D` | ISO-8601 token lifetime. |
| `waitSeconds` | `240` | How long the Job waits for Graylog. |
| `activeDeadlineSeconds` | `290` | Hard limit for the Job. |
| `insecureSkipVerify` | `false` | Skip certificate checks. Needed with `graylog.config.tls.enabled` when the certificate does not cover the Service name. |
| `labels`, `annotations`, `secretLabels` | `{}` | Added to the Job objects, or to the token Secret. |

Keep `waitSeconds` and `activeDeadlineSeconds` under your Helm `--timeout`.

## Limits

- Needs Graylog 6.3.12, 7.0.7, 7.1.2 or newer. Older releases let any user revoke other users' tokens
  (CVE-2026-55867).
- The Secret and service user are not removed on uninstall. Delete them yourself if you want them gone.
- The Job image needs a shell, curl, sed, grep and base64. The default is `curlimages/curl`.
