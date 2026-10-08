# Running OpenSearch API calls against Data Node

The safe update run books ask you to send requests to OpenSearch, for example to check health or drain a
node. Data Node does not expose that API outside the cluster, it uses a self-signed certificate, and it
rejects requests without credentials. You need `kubectl`, `curl` and `openssl`.

## 1. Open a `port-forward`

Forward to one ready Data Node pod that has the `cluster_manager` role, and leave the command running in
its own terminal. Pick a pod outside the group you are restarting, because a forward dies when its pod
does.

Find the roles with `kubectl get pods`, or from the `node.role` column of `_cat/nodes` once you are
connected. An `m` in that column is `cluster_manager`. The default roles include it. If you run dedicated
cluster manager nodes, forward to one of those.

```sh
kubectl port-forward pod/<datanode-pod> 9200:9200 -n <namespace>
```

## 2. Sign a token

Data Node accepts a JWT signed with HS256 using the chart's password secret. The secret is
`GRAYLOG_PASSWORD_SECRET` in the `graylog-secrets` Secret for a release named `graylog`. If you set
`global.existingSecretName`, read it from that Secret instead.

```sh
SECRET=$(kubectl get secret graylog-secrets -n <namespace> \
  -o jsonpath='{.data.GRAYLOG_PASSWORD_SECRET}' | base64 -d)

b64() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
NOW=$(date +%s)
H=$(printf '{"alg":"HS256","typ":"JWT"}' | b64)
P=$(printf '{"sub":"admin","os_roles":["admin"],"iat":%s,"exp":%s}' "$NOW" "$((NOW+3600))" | b64)
S=$(printf '%s.%s' "$H" "$P" | openssl dgst -sha256 -hmac "$SECRET" -binary | b64)
TOKEN="$H.$P.$S"
```

The token lasts an hour. When requests start returning 401, run the block again.

Treat the secret and the token as admin credentials. Do not paste them into tickets or chat.

## 3. Send requests

This small function adds the token and the JSON header.

```sh
os() { local m=$1 p=$2; shift 2
  curl -sk -X "$m" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
    "https://localhost:9200$p" "$@"; }
```

Every call in the run books maps straight onto it. Quote any path that contains `?` or `&`.

```sh
os GET '/_cluster/health?pretty'
os GET '/_cat/allocation?v&h=node,shards'
os PUT /_cluster/settings -d '{"persistent":{"cluster.routing.allocation.exclude._name":"<node-1>,<node-2>"}}'
os POST '/_cluster/voting_config_exclusions?node_names=<node-1>'
os DELETE /_cluster/voting_config_exclusions
```

`-k` skips certificate checks, which is needed because the certificate is self-signed and does not match
`localhost`.

## When it fails

| Result | Cause |
|---|---|
| `401` | Wrong secret, an expired token, or a token with a trailing character. Sign a new one. |
| Connection refused or empty reply | The port-forward stopped, often because its pod restarted. Start it again on another pod. |
| `acknowledged: true` from a PUT | It worked. Read the setting back with `os GET '/_cluster/settings?flat_settings=true'`. |

## Useful commands

Each command uses the `os` function from [Send requests](#3-send-requests).

### Cluster health

```sh
os GET '/_cluster/health?filter_path=status,number_of_nodes,relocating_shards,initializing_shards,unassigned_shards&pretty'
```

`status` is `green`, `yellow` or `red`. After a scale up or a drain, green is not enough. Wait until
`relocating_shards` and `initializing_shards` are 0 as well, so nothing is moving. An empty reply is not
green. The port-forward dropped, so reconnect and ask again.

### Nodes

```sh
os GET '/_cat/nodes?v&h=name,node.role,master'
```

Node names are the pod FQDNs. Copy them from here into exclusion calls. In `node.role`, `d` is data, `m` is
`cluster_manager`, `i` is ingest, `s` is search and `r` is remote cluster client. A `*` in `master` marks the
elected cluster manager.

### Indices

```sh
os GET '/_cat/indices?v&h=index,health,pri,rep&expand_wildcards=all'
```

Every index that holds data needs a `rep` of 1 or more. To list only the ones that do not have one:

```sh
os GET '/_cat/indices?h=index,rep&expand_wildcards=all' | awk '$2==0'
```

No output means every index has a replica. The `.opendistro_security` index shows a high `rep`, because
OpenSearch copies it to every data node. That is normal.

### Shards and disk per node

```sh
os GET '/_cat/allocation?v&h=node,shards,disk.indices,disk.used,disk.avail,disk.percent&s=node'
```

Use it to watch a drain empty a node, and to check that the nodes that stay have the disk for the shards
that move.

### Why a shard is not assigned

```sh
os POST '/_cluster/allocation/explain?pretty' -d '{}'
```

With no body fields it explains the first unassigned shard it finds. A drain that stalls usually
reports that the remaining nodes have no disk.

### Exclusions and voting

```sh
os GET '/_cluster/settings?flat_settings=true'
os GET '/_cluster/state/metadata?filter_path=metadata.cluster_coordination&pretty'
```

The first shows any allocation exclusion. The second shows the voting configuration and its
`voting_config_exclusions`. Read both after you set or clear an exclusion.