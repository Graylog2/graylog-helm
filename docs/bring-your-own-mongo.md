# Bring your own MongoDB

By default the chart creates a MongoDB replica set through the MongoDB Controllers for Kubernetes (MCK) operator. To use a MongoDB you run yourself, turn that off and give Graylog the connection string. You do not need the operator in this case.

The MongoDB version must be in the [compatibility matrix](https://go2docs.graylog.org/current/downloading_and_installing_graylog/compatibility_matrix.htm). The connection string must include credentials, as in `mongodb://<username>:<password>@<host>:<port>/<database>`. `mongodb+srv://` and several hosts are fine. The chart refuses to render a URI without credentials.

Pick one of two ways to supply the connection string.

## Set the connection string in values

The chart stores the URI in the Graylog Secret it manages:

```yaml
mongodb:
  communityResource:
    enabled: false
graylog:
  config:
    mongodb:
      customUri: "mongodb://graylog:<password>@mongo-0.example.com:27017,mongo-1.example.com:27017/graylog"
```

The password then sits in your values file and in the Helm release. Use the next option if that is a problem, or if a GitOps controller renders the chart.

## Keep the connection string in your own Secret

With `global.existingSecretName` the chart creates no Secret, so you supply one. Create a Secret with the keys listed in [Graylog Secrets](graylog-secrets.md#required-keys). Put the connection string in `GRAYLOG_MONGODB_URI`. [examples/graylog-secret.yaml](../examples/graylog-secret.yaml) shows the full shape. It uses `stringData`, so you supply plain text and Kubernetes encodes it.

Name the Secret in your values file and turn off the chart-managed MongoDB:

```yaml
global:
  existingSecretName: "my-new-graylog-secret"
mongodb:
  communityResource:
    enabled: false
```

The chart refuses to render `global.existingSecretName` with `mongodb.communityResource.enabled=true`. For a complete values file, see [examples/values-existing-secret-external-mongodb.yaml](../examples/values-existing-secret-external-mongodb.yaml).
