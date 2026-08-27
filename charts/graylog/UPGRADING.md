# Upgrading the Graylog Helm chart

## 1.0.0 to 2.0.0

2.0.0 changes defaults, removes values and tightens pod security. Read this
before you run `helm upgrade`. Two of the changes stop the upgrade outright, and
several more change how a running deployment behaves without any action on your
part.

Work through the three sections in order. The first lists what you must change
before upgrading, the second what to plan capacity for, and the third what
changes on its own.

### Change these before you upgrade

**`imagePullSecrets` takes objects, not strings.** `global.imagePullSecrets` and
the per-image lists under `graylog.image` and `datanode.image` now expect
`LocalObjectReference` entries. Schema validation rejects the old form, so the
upgrade fails fast.

```yaml
# 1.0.0
global:
  imagePullSecrets:
    - my-registry-secret

# 2.0.0
global:
  imagePullSecrets:
    - name: my-registry-secret
```

**The native-libs volume claim template is renamed.** This one only affects you
if you set `datanode.persistence.nativeLibs.enabled=true`. The template goes from
`nativeLibs` to `native-libs`, and Kubernetes treats `volumeClaimTemplates` as
immutable, so it rejects the upgrade. Delete the StatefulSet first and keep the
pods running while you do it:

```sh
kubectl delete statefulset <release>-graylog-datanode --cascade=orphan
helm upgrade <release> graylog/graylog --version 2.0.0
```

The old `nativeLibs-*` PVCs are left behind. Nothing mounts them after the
upgrade, so delete them once you have confirmed the new pods are healthy.

**The forwarder ingress splits into two channels.** `ingress.forwarder` no longer
takes `className`, `annotations`, `hosts` and `tls` directly. Each of the two gRPC
channels now carries its own block, so this needs rewriting rather than renaming:

```yaml
# 2.0.0
ingress:
  forwarder:
    enabled: true
    messageChannel:
      className: alb
      hosts:
        - host: forwarder.example.com
          paths:
            - path: /
              pathType: ImplementationSpecific
    configChannel:
      className: alb
      hosts:
        - host: forwarder.example.com
          paths:
            - path: /
              pathType: ImplementationSpecific
```

**The MaxMind schedule moves.** `graylog.config.geolocation.maxmindGeoIp.cronSchedule`
becomes `graylog.config.geolocation.sidecar.schedule`, because the database update
runs as a sidecar on the Graylog pod instead of a CronJob.
`maxmindGeoIp.postInstallRun` is gone with no replacement.

**These values no longer exist.** The schema does not reject unknown keys, so a
values file that still sets any of them installs cleanly and the setting does
nothing. Grep your values files for each one:

| Removed value | Notes |
|---|---|
| `datanode.persistence.enabled` | never wired to anything |
| `datanode.persistence.data.existingClaim` | never wired to anything |
| `datanode.persistence.data.selector` | never wired to anything |
| `datanode.persistence.data.dataSource` | never wired to anything |
| `datanode.persistence.nativeLibs.existingClaim` | never wired to anything |
| `datanode.persistence.nativeLibs.selector` | never wired to anything |
| `graylog.persistence.mountPath` | never wired to anything |
| `graylog.persistence.selector` | never wired to anything |
| `graylog.livenessProbe.successThreshold` | Kubernetes only accepts 1 for liveness probes |
| `datanode.livenessProbe.successThreshold` | Kubernetes only accepts 1 for liveness probes |

### Plan capacity for these

**MongoDB changes topology.** The default replica set is now 3 data-bearing
members with no arbiter, replacing 2 members plus 1 arbiter. Upgrading on the
defaults adds a member and drops the arbiter, so budget for a third data volume.
To keep the old shape, set `mongodb.replicas: 2` and `mongodb.arbiters: 1`.

**MongoDB pods are sized by the chart.** Nothing could override the operator's
injected defaults before. A pod now reserves 300m CPU and 1152Mi instead of 1000m
and 800M, and the upgrade rolls the replica set. `mongodb.resources`,
`mongodb.agentResources` and `mongodb.initResources` control this. Helm
deep-merges them, so setting only `requests` keeps the chart's `limits`, and only
`null` drops a block.

**PodDisruptionBudgets are on by default** for both graylog and datanode. With a
single replica the budget cannot be satisfied, so node drains block. Either run
more than one replica or set `graylog.podDisruptionBudget.enabled: false` and the
datanode equivalent.

### These change on their own

**Graylog moves from 7.0 to 7.1.8.** `appVersion` is now 7.1.8, and
`graylog.image.tag` and `datanode.image.tag` both default to `appVersion`. The
upgrade therefore moves the running images unless you pin both tags. Check the
Graylog release notes for 7.1 before upgrading a production cluster.

**Pods run under a restricted security context.** `runAsNonRoot: true`,
`seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`, and all
capabilities dropped except `NET_BIND_SERVICE` on graylog and the file-ownership
set on datanode. A custom image that runs as root or needs other capabilities
will not start.

**Both StatefulSets get a startupProbe**, which allows 330 seconds before the
kubelet restarts the container. A deployment that takes longer to start restarts
in a loop, so raise `startupProbe.failureThreshold` if your cluster is slower
than that.

**Graylog shutdown takes up to five minutes.** `terminationGracePeriodSeconds` is
300 and a preStop hook drains the journal first. Pod deletion, node drains and
rolling upgrades all pay this cost per pod. It protects buffered messages, so
lower it only where the journal holds nothing worth keeping.

**An explicit `externalUri` now wins.** `graylog.config.network.externalUri` takes
precedence over the LoadBalancer Service lookup, and a bare hostname gets the
scheme and app port appended. If you set both a LoadBalancer service and
`externalUri`, the advertised `http_external_uri` changes.

**The init script ConfigMap is renamed** from the fixed `init-script-cm` to
`<release>-graylog-init-cm`, so two releases can share a namespace. Anything
referencing the old name breaks.

**The generated root password is no longer printed.** It goes to the backup
Secret instead of `NOTES.txt`. Read it with:

```sh
kubectl get secret <release>-graylog-generated -o jsonpath='{.data.GRAYLOG_ROOT_PASSWORD}' | base64 -d
```

### Running the upgrade

Take a MongoDB backup first. See [mongodb-backup-restore.md](../../docs/mongodb-backup-restore.md).

```sh
helm repo update graylog

# Render first and read the diff
helm template <release> graylog/graylog --version 2.0.0 -f my-values.yaml > new.yaml

helm upgrade <release> graylog/graylog --version 2.0.0 -f my-values.yaml
```

Do not use `--reuse-values` for this upgrade. It carries forward values that
2.0.0 has removed or restructured, and it skips the new defaults you want. Pass
your values file explicitly.
