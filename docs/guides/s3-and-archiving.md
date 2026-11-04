# S3 credentials and archiving

## S3 credentials

Two parts of a release can need S3: the Data Node's snapshot repository, and Graylog's archive
backend. Put one credential in `global.s3` and both read it.

```yaml
global:
  s3:
    existingSecret: graylog-s3
    # Override when the Secret already has key names of its own, as an
    # ExternalSecret usually does.
    accessKeyKey: access_key
    secretKeyKey: secret_key

datanode:
  config:
    # The endpoint opts the Data Node in. Without one it has no snapshot
    # repository and ignores global.s3.
    s3ClientDefaultEndpoint: "https://s3.us-east-1.amazonaws.com"
```

Only the credentials belong in `global.s3`. Endpoints and regions differ per component and stay with
the component. The endpoint is required, including on AWS.

To give one component a different credential, set it on that component instead:

```yaml
datanode:
  config:
    s3ClientDefaultExistingSecret: datanode-s3
    s3ClientDefaultAccessKeyKey: access_key
    s3ClientDefaultSecretKeyKey: secret_key
```

A component that names any credential of its own takes that block whole and ignores `global.s3`,
instead of merging the two field by field. A Secret in one place therefore never pairs with an
inline key from the other. Naming both an existing Secret and an inline key in the same block fails
the render.

`examples/graylog-s3-secret.yaml` holds the Secret itself.

The two consumers read different environment variables from the same credential, which is the work
`global.s3` does:

| Consumer | Environment | IRSA |
| --- | --- | --- |
| Data Node snapshot repository | `GRAYLOG_DATANODE_S3_CLIENT_DEFAULT_ACCESS_KEY` / `_SECRET_KEY` | Not supported |
| Graylog archive backend | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Supported, and preferred |

> [!IMPORTANT]
> Rotating the Secret restarts nothing. The pods read these as environment variables at startup, and
> the chart's config checksum does not cover a Secret it does not own. Roll them yourself:
> `kubectl rollout restart statefulset -l app=graylog-datanode`.


## Archiving to S3

The archive backend is not a chart value. It lives in MongoDB as cluster config, created through the
archive plugin API, and carries its own `aws_access_key_id` and `aws_secret_access_key`. Leave those
two fields out and it authenticates through the AWS SDK's default credential chain instead.

Use IRSA. Annotate the service account, and leave the key fields out of the backend:

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::111122223333:role/graylog-archive
```

Where IRSA is not available, `graylog.config.archive.useGlobalS3Credentials` exports `global.s3` to
the Graylog container as `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, which the same chain picks
up. Static keys then stay out of MongoDB:

```yaml
global:
  s3:
    existingSecret: graylog-s3

graylog:
  config:
    archive:
      useGlobalS3Credentials: true
```

> [!WARNING]
> Do not combine this with IRSA. The AWS SDK resolves environment variables before the web identity
> token, so these credentials override the role on the service account. Archiving then authenticates
> as the wrong principal and logs nothing about it. Hence the default of `false`.

Static keys are not the only way. The Data Node also accepts a filesystem repository, which needs
no credentials at all but does need storage every Data Node can mount, such as EFS on EKS:

```yaml
datanode:
  config:
    snapshotRepositoryExternal: true
  extraEnv:
    - name: GRAYLOG_DATANODE_PATH_REPO
      value: /var/lib/graylog-datanode/repo
  extraVolumes:
    - name: snapshot-repo
      persistentVolumeClaim:
        claimName: graylog-snapshot-repo   # ReadWriteMany
  extraVolumeMounts:
    - name: snapshot-repo
      mountPath: /var/lib/graylog-datanode/repo
```

`snapshotRepositoryExternal` only relaxes the chart's render-time guard, for repositories the chart
cannot see. The Data Node still applies its own check, so setting it without a real repository
gives you a crash loop rather than a render error.

> [!WARNING]
> **An IAM role granting the bucket does not satisfy the Data Node.** It validates its own
> configuration at startup and looks for `path_repo` or S3 credentials, so it refuses the `search`
> role with:
>
> ```
> Your configuration contains the search node role in node_roles but there is no
> snapshots repository configured.
> ```
>
> That happens before OpenSearch starts and is independent of whether the pod could reach the
> bucket. IRSA is doubly unavailable here: the `repository-s3` plugin runs under a SecurityManager
> policy granting `FilePermission "config", "read"` and network connect, so it can talk to instance
> metadata but cannot read the projected ServiceAccount token. Static keys or `path_repo`.
