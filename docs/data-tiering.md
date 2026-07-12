# Data Tiering (Warm Tier)

Graylog [data tiering](https://go2docs.graylog.org/current/setting_up_graylog/data_tiering.htm) moves older
index data into a lower-cost **warm tier** backed by S3-compatible object storage, where it is kept as
*searchable snapshots*. That way data stays queryable without living on hot storage.

This guide covers the chart-side configuration: pointing the DataNode S3 client at a bucket. Creating the
warm-tier repository and enabling the warm tier on an index set is done afterward in the Graylog web UI (see
[Create a Warm Tier on Data Node](https://go2docs.graylog.org/current/setting_up_graylog/create_warm_tier_on_data_node.htm)).

> [!NOTE]
> Data tiering is a **Graylog Enterprise** feature and requires an Enterprise license (add it in the Graylog web
> UI under *System > Licenses*).

## How the chart fits in

The chart configures the Data Node S3 client through the `datanode.config.s3ClientDefault*` values. These map
directly to the Data Node's `s3_client_default_*` settings and are written into the searchable-snapshot
repository configuration.

| Value | Purpose | Default |
| --- | --- | --- |
| `s3ClientDefaultEndpoint` | S3 endpoint, host or `host:port`, no scheme | `""` |
| `s3ClientDefaultRegion` | S3 region | `"us-east-2"` |
| `s3ClientDefaultProtocol` | `http` or `https` | `"http"` |
| `s3ClientDefaultPathStyleAccess` | Path-style (`true`) vs virtual-hosted (`false`) addressing | `"true"` |
| `s3ClientDefaultAccessKey` | Access key (stored in a Secret) | `""` |
| `s3ClientDefaultSecretKey` | Secret key (stored in a Secret) | `""` |
| `nodeSearchCacheSize` | On-disk cache for warm-tier data on the Data Node data volume | `"10gb"` |

> [!IMPORTANT]
> `s3ClientDefaultEndpoint`, `s3ClientDefaultAccessKey`, and `s3ClientDefaultSecretKey` must all be set together.
> Setting only some of them fails template rendering by design.

> [!IMPORTANT]
> `nodeSearchCacheSize` reserves space on the Data Node **data volume** (disk, not memory), *not* RAM. It must fit
> within `datanode.persistence.data.size` alongside hot index data, or the Data Node fails preflight with
> `not enough usable space for the node search cache` and crash-loops. Keep the data volume comfortably larger
> than the cache (the chart default pairs a `10gb` cache with a `20Gi` data volume).

> [!NOTE]
> The default `s3ClientDefaultProtocol: "http"` + `s3ClientDefaultPathStyleAccess: "true"` suit S3-compatible
> stores such as MinIO. **Real AWS S3 requires overrides** (see below).

## Option A — Amazon S3

Create a bucket and an IAM user with read/write access to it, then configure the chart. For AWS you must set
`s3ClientDefaultProtocol: "https"` and `s3ClientDefaultPathStyleAccess: "false"` (AWS uses virtual-hosted-style
addressing).

```yaml
datanode:
  config:
    s3ClientDefaultEndpoint: "s3.us-east-1.amazonaws.com"   # host only, no scheme
    s3ClientDefaultRegion: "us-east-1"                      # must match the bucket region
    s3ClientDefaultProtocol: "https"
    s3ClientDefaultPathStyleAccess: "false"
    s3ClientDefaultAccessKey: "<access-key>"
    s3ClientDefaultSecretKey: "<secret-key>"
```

A minimal least-privilege IAM policy for the bucket:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads", "s3:ListBucketVersions"],
      "Resource": "arn:aws:s3:::<bucket>"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"],
      "Resource": "arn:aws:s3:::<bucket>/*"
    }
  ]
}
```

## Option B — MinIO (S3-compatible)

Deploy MinIO in the cluster (e.g. via the [MinIO Helm chart](https://github.com/minio/minio/tree/master/helm/minio))
and create a bucket. Keep `http` and path-style access, and point the endpoint at the MinIO service:

```yaml
datanode:
  config:
    s3ClientDefaultEndpoint: "minio:9000"      # <service>.<namespace>:<port>, no scheme
    s3ClientDefaultRegion: "us-east-1"
    s3ClientDefaultProtocol: "http"            # default
    s3ClientDefaultPathStyleAccess: "true"     # default
    s3ClientDefaultAccessKey: "<minio-access-key>"
    s3ClientDefaultSecretKey: "<minio-secret-key>"
```

## Enable the warm tier

After the Data Node restarts with the S3 configuration, finish the setup in the Graylog web UI:

1. Go to *System > Indices* and edit an index set.
2. Under *Rotation and Retention*, select *Data Tiering* and create a warm storage repository (type **Amazon S3**),
   giving it a name, your bucket, and a base path.
3. Enable the warm tier and choose the repository.

Full instructions: [Create a Warm Tier on Data Node](https://go2docs.graylog.org/current/setting_up_graylog/create_warm_tier_on_data_node.htm).

> [!TIP]
> When entering the repository **base path**, avoid a trailing slash (use `snapshots`, not `snapshots/`). A trailing
> slash produces double-slash object keys; some S3-compatible stores (e.g. MinIO) reject this with `Object name contains 
> unsupported characters`.

## Verify

- Confirm the Data Node picked up the S3 configuration:

  ```sh
  kubectl -n graylog logs <datanode-pod> | grep "S3 repository configured"
  ```

- In the web UI, the warm storage repository should show as ready after creation. Once an index rolls over to the
  warm tier, snapshot objects appear under the base path in your bucket, and the index shows a `warm` badge while
  remaining searchable.