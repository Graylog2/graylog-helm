# Bring your own OpenSearch

By default the chart deploys the Graylog [Data Node](https://go2docs.graylog.org/current/downloading_and_installing_graylog/install_graylog_data_node.htm), which manages OpenSearch for you. If you already run an OpenSearch cluster, or want to manage it separately, you can point Graylog at it instead. The [OpenSearch Kubernetes Operator](https://github.com/opensearch-project/opensearch-k8s-operator) is one way to run that cluster.

## Requirements

- An OpenSearch version in the Graylog [compatibility matrix](https://go2docs.graylog.org/current/downloading_and_installing_graylog/compatibility_matrix.htm). For Graylog 7.1 that is 2.x, up to 2.19.x. OpenSearch 3.0+ is not supported on that line.
- `action.auto_create_index: false` on the cluster, because Graylog manages its own indices. With auto-create off, the OpenSearch security plugin's audit log cannot create its daily index. Set `plugins.security.audit.type` to `noop` to disable audit logging, or to `log4j` to send it to the logs.
- MongoDB. Graylog still needs it. Keep the chart's MongoDB (`mongodb.communityResource.enabled: true`) or [bring your own](bring-your-own-mongo.md).
- The chart installed in the namespace that holds the OpenSearch credential and CA Secrets, so the Graylog pods can read and mount them.

## Configuration

Disable the Data Node and enable the `opensearch` block: ([full example](../examples/values/values-example-byo-opensearch.yaml)):

```yaml
datanode:
  enabled: false

opensearch:
  enabled: true
  # OpenSearch node REST URIs. Leave credentials out, the chart adds them from `auth`.
  hosts:
    - https://my-opensearch.my-namespace.svc.cluster.local:9200
  auth:
    # Read credentials from an existing Secret, such as the operator's admin credentials Secret.
    existingSecret: my-opensearch-admin-credentials
    usernameKey: username
    passwordKey: password
    # Or set them inline. These take precedence. Dev and test only.
    # username: admin
    # password: change-me
  tls:
    enabled: true
    # Secret and key holding the CA that signed the OpenSearch HTTP layer.
    # The operator stores it in "<cluster-name>-ca".
    caSecret: my-opensearch-ca
    caKey: ca.crt
```

The chart does four things with this:

- Builds `GRAYLOG_ELASTICSEARCH_HOSTS`, with credentials added to each URI, into its own Secret named `<release>-graylog-opensearch`, and wires that Secret into the Graylog pods.
- Imports the CA from `caSecret` into Graylog's Java truststore, so Graylog trusts the HTTPS endpoint.
- Sets `GRAYLOG_SELFSIGNED_STARTUP=false`, so Graylog uses the external cluster instead of Data Node discovery.
- Keeps the connection in that separate Secret, so it works with or without `global.existingSecretName`.

The chart rejects a render where `datanode.enabled` and `opensearch.enabled` are both `true` or both `false`. It also rejects `opensearch.enabled` with no `hosts`.

With `datanode.enabled: false`, the chart ignores every other `datanode.*` value.

### Credentials

- `existingSecret` is read with Helm's `lookup`, so the Secret must already exist in the release namespace when you install or upgrade. `helm template` and `--dry-run` cannot read it, and the rendered host URIs lack credentials there. That is expected, and it includes GitOps rendering.
- Inline `username` and `password` take precedence over `existingSecret`.
- The chart URL-encodes the username and password when it builds the URIs. Do not encode them yourself.

### TLS and CA trust

When `opensearch.tls.enabled` is `true` and `opensearch.tls.caSecret` is set, an init container imports the CA into `/usr/share/graylog/data/cacerts/graylog.jks` under the alias `byo-opensearch-ca`, and Graylog starts with that truststore.

Set `opensearch.tls.enabled: false` only if the HTTP layer is plaintext (`http://` hosts). Leave `caSecret` empty if the JVM's default truststore already trusts the CA, as it does for a public CA.

## Caveats

- The init container builds the truststore at pod start. After a CA rotation, restart the Graylog pods to pick up the new CA.
- Single-node clusters from the operator can deadlock on the handoff from bootstrap to normal nodes. Use at least 3 cluster-manager-eligible replicas.
