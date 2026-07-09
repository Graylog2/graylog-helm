# Back Up and Restore MongoDB

This guide walks through taking a manual logical backup of Graylog's MongoDB
database with [`mongodump`](https://www.mongodb.com/docs/database-tools/mongodump/)
and restoring it with [`mongorestore`](https://www.mongodb.com/docs/database-tools/mongorestore/).
It applies to the MongoDB replica set deployed by this chart (the default
[MongoDB Community](https://www.mongodb.com/docs/kubernetes/current/) resource).

> **Note:** These commands assume a release named `graylog` in the `graylog`
> namespace. Adjust the release name, namespace, and secret name to match your
> deployment. The connection-string secret is named
> `<release>-mongo-rs-admin-admin`.

## Prerequisites

- `kubectl` access to the cluster and namespace where Graylog is installed.
- `jq` installed locally (used to decode the connection secret).
- Enough disk space for the dump, both inside the temporary pod and optionally
  on your local machine (only if you need to copy it out).

## Back up

1. Build an admin connection URI from the secret the MongoDB operator generates.
   This decodes the standard connection string and rewrites it to authenticate
   against the `admin` database while targeting the `graylog` database:

   ```sh
   MONGO_ADMIN_URI=$(kubectl get secret graylog-mongo-rs-admin-admin -n graylog -o jsonpath='{.data}' \
     | jq -r '.["connectionString.standard"] | @base64d' \
     | sed 's/admin\?/graylog\?authSource=admin\&/g')
   ```

2. Launch a throwaway pod with the MongoDB shell/tools image, passing the URI in
   as an environment variable, and drop into a shell:

   ```sh
   kubectl run -i -t mongosh --image=alpine/mongosh -n graylog \
     -e URI="$MONGO_ADMIN_URI" --restart=Never -- ash
   ```

3. From inside the pod, dump the database to a local directory in the pod:

   ```sh
   mongodump --uri "$URI" --out ./mongo-backup
   ```

### (Optional) Copy the backup to your local machine

Run this from your local machine while the `mongosh` pod is still running:

```sh
kubectl exec mongosh -n graylog -- tar cf - /mongo-backup | tar xf - -C .
```

## Restore

Restoring requires an admin connection URI for the **target** deployment
(`$NEW_MONGO_ADMIN_URI`). Build it the same way as the backup URI in step 1,
using the target cluster's secret.

If the backup directory only exists on your local machine, copy it back into the
pod first (the reverse of the copy-out step):

```sh
tar cf - ./mongo-backup | kubectl exec -i mongosh -n graylog -- tar xf - -C /mongo-backup
```

Then, from inside the `mongosh` pod, restore the `graylog` database:

```sh
mongorestore --uri "$NEW_MONGO_ADMIN_URI" mongo-backup/graylog
```

## Clean up

Delete the temporary pod when you are done:

```sh
kubectl delete pod mongosh -n graylog
```
