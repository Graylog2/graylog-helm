# Graylog Secrets

This guide explains how to configure the Kubernetes secrets required by the Graylog Helm chart. Graylog requires a Kubernetes Secret object containing credentials for authentication and backend service access. You can either let the Helm chart create this secret for you or manage it externally and reference it in your values file.

## Required Keys
`GRAYLOG_MONGODB_URI`: The full MongoDB URI, including the user, password, address, port, and database name for Graylog to use.

Example: `mongodb://admin:some-password@mongodb-1-svc.graylog-helm-1.svc.cluster.local:27017/graylog_helm_1?authSource=admin`

`GRAYLOG_ROOT_USERNAME`: The initial admin user name you will use to login.

`GRAYLOG_PASSWORD_SECRET`: The initial admin password you will use to login.

`GRAYLOG_ROOT_PASSWORD_SHA2`: The SHA256 hash of the password you set for `GRAYLOG_PASSWORD_SECRET`
```bash
$ echo -n "my-password" | sha256sum
6fa2288c361becce3e30ba4c41be7d8ba01e3580566f7acc76a7f99994474c46
```

## Optional Keys

`GRAYLOG_S3_CLIENT_DEFAULT_SECRET_KEY`: Secret key for S3 backend. Only required if using features that require S3 access via keys.

`GRAYLOG_S3_CLIENT_DEFAULT_ACCESS_KEY`: Access key for S3 backend. Only required if using features that require S3 access via keys.

## Secret Example

The following is an example of a valid Kubernetes Secret managed externally from the Graylog Helm chart.
```yaml
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: my-graylog-secret
data:
  GRAYLOG_MONGODB_URI: bW9uZ29kYjovL2FkbWluOnNvbWUtcGFzc3dvcmRAbW9uZ29kYi0xLXN2Yy5ncmF5bG9nLWhlbG0tMS5zdmMuY2x1c3Rlci5sb2NhbDoyNzAxNy9ncmF5bG9nX2hlbG1fMT9hdXRoU291cmNlPWFkbWluJnJlcGxpY2FTZXQ9bW9uZ29kYi0x
  GRAYLOG_ROOT_USERNAME: bXktZ3JheWxvZy11c2Vy
  GRAYLOG_PASSWORD_SECRET: bXktZ3JheWxvZy1wYXNzd29yZA==
  GRAYLOG_ROOT_PASSWORD_SHA2: MGFmMzhhYzUyOWU2NTMxNTJhYmM5MmNkMjY5OGI3Yjc1MTM3NjliY2M3OWRiMjIyODVhMTMxNTM0ZjQ2ZWVlYQ==
  GRAYLOG_S3_CLIENT_DEFAULT_SECRET_KEY: ""
  GRAYLOG_S3_CLIENT_DEFAULT_ACCESS_KEY: ""
```

## Setting Your Secret

In your own values file, set the name of your secret as the `global.existingSecretName` parameter.
```yaml
global:
  existingSecretName: my-graylog-secret
```

**OR** 

Alternatively, set the secret name via the Helm CLI:

```bash
helm upgrade --install some-graylog charts/graylog/ \
  --set global.existingSecretName=my-graylog-secret
```