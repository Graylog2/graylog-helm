# Bring Your Own OpenSearch

By default this chart deploys the **Graylog Data Node**, which manages an embedded OpenSearch for
you. If you already run (or want to manage separately) an OpenSearch cluster — for example one
provisioned by the [OpenSearch Kubernetes Operator](https://github.com/opensearch-project/opensearch-k8s-operator)
— you can instead point Graylog directly at it.

## Requirements

- **OpenSearch version:** must fit the Graylog
  [compatibility matrix](https://go2docs.graylog.org/current/downloading_and_installing_graylog/compatibility_matrix.htm).
  For Graylog 7.x this means OpenSearch **2.x, up to 2.19.x**. **OpenSearch 3.0+ is not supported.**
- **Backend setting:** Graylog manages its own indices, so the OpenSearch cluster should be
  configured with `action.auto_create_index: false`.
  > Note: with auto-create disabled, the OpenSearch security plugin's audit log cannot create its
  > daily index. Either disable audit logging (`plugins.security.audit.type: noop`) or send it to
  > the logs (`log4j`).
- **MongoDB:** Graylog still requires MongoDB. Keep the bundled community resource
  (`mongodb.communityResource.enabled: true`) or [bring your own](bring-your-own-mongo.md).
- **Same namespace:** install the chart into the namespace where the OpenSearch credential and CA
  secrets live, so the Graylog pods can read/mount them.

## Configuration

Disable the Data Node and enable the `opensearch` block:

```yaml
datanode:
  enabled: false

opensearch:
  enabled: true
  # OpenSearch node REST URIs (no credentials here — they are added from `auth`).
  hosts:
    - https://my-opensearch.my-namespace.svc.cluster.local:9200
  auth:
    # Read credentials from an existing secret (e.g. the operator's admin credentials secret).
    existingSecret: my-opensearch-admin-credentials
    usernameKey: username
    passwordKey: password
    # ...or inline (takes precedence; dev/test only):
    # username: admin
    # password: change-me
  tls:
    enabled: true
    # Secret + key holding the CA that signed the OpenSearch HTTP layer.
    # The operator stores this in "<cluster-name>-ca".
    caSecret: my-opensearch-ca
    caKey: ca.crt
```

The chart assembles `GRAYLOG_ELASTICSEARCH_HOSTS` (with credentials injected into each URI) into a
dedicated secret (`<release>-graylog-opensearch`) that is wired into the Graylog pods, imports
`caSecret`'s CA certificate into Graylog's Java truststore so it trusts the HTTPS endpoint, and sets
`GRAYLOG_SELFSIGNED_STARTUP=false` so Graylog uses the external indexer instead of Data Node discovery.

This works the same whether or not you also set `global.existingSecretName` — the OpenSearch
connection lives in its own secret, so bringing your own Graylog secret does not suppress it.

Setting `datanode.enabled` and `opensearch.enabled` both `true` (or both `false`) is rejected at
render time with a clear error.

### Credentials

- **`existingSecret`** is resolved at template/install time with `helm`'s `lookup`. The secret must
  already exist in the release namespace when you install/upgrade. (`helm template`/`--dry-run` can't
  read it, so the rendered value will lack credentials there — that's expected.)
- **Inline `username`/`password`** always take precedence and are useful for quick tests.
- Passwords containing URI-reserved characters (`@ : / ?`) should be URL-encoded.

### TLS / CA trust

When `opensearch.tls.enabled: true` and `opensearch.tls.caSecret` is set, an init container imports
the CA into `/usr/share/graylog/data/cacerts/graylog.jks` (alias `byo-opensearch-ca`) and Graylog is
started with that truststore. The CA is re-imported on pod restart, so a rotated CA is picked up by
restarting the Graylog pods.

Set `opensearch.tls.enabled: false` only if the OpenSearch HTTP layer is plaintext (`http://` hosts).
Leave `caSecret` empty if the CA is already trusted by the JVM's default truststore (e.g. a public CA).

## Caveats

- **CA rotation** requires a Graylog pod restart (the truststore is built at pod init).
- **Operator single-node clusters** can deadlock on the bootstrap→node handoff; use at least 3
  cluster-manager-eligible replicas.
