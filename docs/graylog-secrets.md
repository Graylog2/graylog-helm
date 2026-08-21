# Graylog Secrets

This guide explains how to configure the Kubernetes secrets required by the Graylog Helm chart. Graylog requires a Kubernetes Secret object containing credentials for authentication and backend service access. You can either let the Helm chart create this secret for you or manage it externally and reference it in your values file.

## Required Keys
`GRAYLOG_MONGODB_URI`: The full MongoDB URI, including the user, password, address, port, and database name for Graylog to use.

Example: `mongodb://admin:some-password@mongodb-1-svc.graylog-helm-1.svc.cluster.local:27017/graylog_helm_1?authSource=admin`

`GRAYLOG_PASSWORD_SECRET`: The pepper that Graylog applies to stored user data. This value is not
a password, and you do not use it to log in. Use a minimum of 64 random characters. Keep the same
value for the life of the cluster. If this value changes, Graylog cannot read the data that it
already stored.

```sh
pwgen 96 1
```

`GRAYLOG_ROOT_PASSWORD_SHA2`: The SHA-256 hash of the admin password. This is the password that
you use to log in as `GRAYLOG_ROOT_USERNAME`. It is not the hash of `GRAYLOG_PASSWORD_SECRET`.

```sh
printf %s 'my-password' | sha256sum | cut -d ' ' -f1
```

Expected output: one 64-character lowercase hexadecimal digest.

```text
6fa2288c361becce3e30ba4c41be7d8ba01e3580566f7acc76a7f99994474c46
```

## Optional Keys

`GRAYLOG_ROOT_USERNAME`: The name of the initial admin user. Graylog uses `admin` when you do not
supply it.

> [!NOTE]
> S3 credentials do not belong in this Secret. Searchable snapshots run on the Data Node, which
> reads a separate chart-managed Secret named `<global.existingSecretName>-datanode` with the key
> names `GRAYLOG_DATANODE_S3_CLIENT_DEFAULT_ACCESS_KEY` and
> `GRAYLOG_DATANODE_S3_CLIENT_DEFAULT_SECRET_KEY`. Set them through
> `datanode.config.s3ClientDefaultAccessKey`, `datanode.config.s3ClientDefaultSecretKey`, and
> `datanode.config.s3ClientDefaultEndpoint`. A `GRAYLOG_S3_CLIENT_DEFAULT_*` key in this Secret
> reaches the Graylog server container and does not configure searchable snapshots.

> [!NOTE]
> MaxMind GeoIP credentials do not belong in this Secret either. The GeoIP update sidecar reads
> them from a Secret of its own, named by
> `graylog.config.geolocation.maxmindGeoIp.existingSecret`, with the key names
> `GEO_IP_MAXMIND_ACCOUNT_ID` and `GEO_IP_MAXMIND_LICENSE_KEY` (both overridable via
> `accountIdKey` / `licenseKeyKey`). Putting them in this Secret has no effect: with
> `global.existingSecretName` set, the sidecar never reads this Secret, and supplying the inline
> `maxmindGeoIp.accountId` / `licenseKey` values alongside an external Secret is refused at render
> time. The sidecar reads its keys with a `secretKeyRef`, so the pod does not start when one is
> absent from the GeoIP Secret. See
> [examples/graylog-geoip-secret.yaml](../examples/graylog-geoip-secret.yaml).

## Secret Example

The following is an example of a Kubernetes Secret managed externally from the Graylog Helm chart.
The example uses `stringData`, so you supply plain text and Kubernetes encodes it for you.

> [!CAUTION]
> Replace every `<...>` value before you apply this file. Keep or change `admin` as you prefer.
> Never commit real credentials.

> [!IMPORTANT]
> Because this is `stringData`, do not base64 encode the values yourself — a base64 string here is
> encoded a second time, and Graylog then reads the base64 text itself as the username, pepper or
> hash. Avoid trailing newlines for the same reason, which is why the commands above use
> `printf %s` rather than `echo`.

```yaml
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: my-graylog-secret
stringData:
  GRAYLOG_MONGODB_URI: "mongodb://<username>:<password>@<host>:27017/graylog?authSource=admin"
  GRAYLOG_ROOT_USERNAME: "admin"
  # Minimum 64 characters. Not a password. See the description above.
  GRAYLOG_PASSWORD_SECRET: "<96-character-random-string>"
  # SHA-256 hash of the admin login password: 64 lowercase hexadecimal characters.
  GRAYLOG_ROOT_PASSWORD_SHA2: "<64-character-sha256-hex-digest>"
```

That is the whole Secret. S3 and MaxMind credentials are deliberately absent — see the two notes
above for where each of those belongs.

## Setting Your Secret

> [!IMPORTANT]
> An external Secret requires an external MongoDB. The chart refuses to render
> `global.existingSecretName` together with the default `mongodb.communityResource.enabled=true`,
> and stops with `Cannot use global.existingSecretName with mongodb.communityResource.enabled=true.`
> Set `mongodb.communityResource.enabled=false` and put the MongoDB connection string in
> `GRAYLOG_MONGODB_URI`.

In your own values file, set the name of your secret as the `global.existingSecretName` parameter.
```yaml
global:
  existingSecretName: my-graylog-secret
mongodb:
  communityResource:
    enabled: false
```

**OR** 

Alternatively, set the secret name via the Helm CLI:

```bash
helm upgrade --install some-graylog charts/graylog/ \
  --set global.existingSecretName=my-graylog-secret \
  --set mongodb.communityResource.enabled=false
```

For a complete worked example, see
[examples/values-existing-secret-external-mongodb.yaml](../examples/values-existing-secret-external-mongodb.yaml).