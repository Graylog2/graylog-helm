# Customize deployed resources

Every object the chart deploys accepts custom metadata, and the pods accept extra volumes, containers and scheduling settings.

## Labels and annotations

Every object the chart deploys accepts custom labels and annotations. Set them
once with `global.commonLabels` / `global.commonAnnotations`, and use the
per-object values when only one resource needs them:

```yaml
# custom-metadata.yaml
global:
  commonLabels:
    cost-center: "1234"
    environment: production
  commonAnnotations:
    owner: observability-team

graylog:
  # StatefulSet, ConfigMaps and Secrets
  labels:
    tier: backend
  annotations:
    reloader.stakater.com/auto: "true"
  # Graylog pods only
  podLabels:
    tier: backend
  podAnnotations:
    prometheus.io/scrape: "true"
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-internal: "true"

datanode:
  labels:
    tier: storage

ingress:
  web:
    labels:
      tier: edge
```

> [!NOTE]
> MongoDB pods are the one exception. `mongodb.labels` / `mongodb.annotations`
> apply to the `MongoDBCommunity` object, but there is no `mongodb.podLabels`.
> The MongoDB Community operator owns the pod template of the StatefulSet it
> manages, labels it `app: <release>-mongo-rs-svc` and discards anything the
> chart puts there. Pod-level metadata for MongoDB has to come from the
> operator's own API.

Precedence, lowest to highest: `global.common*`, the per-object value, then the
chart's own identity labels (`app.kubernetes.io/*`, `helm.sh/chart`, `app`) and
its Helm hook and resource-policy annotations. Chart-owned values always win, so
custom metadata can never break release lifecycle handling.

> [!NOTE]
> Custom labels never reach a workload's `spec.selector`, which is immutable
> once created. They land on the object and on the pod template only, so labels
> can safely be added to a release that is already running, and `helm upgrade` will
> not fail on a changed selector.

### Immutable fields are deliberately left alone

Kubernetes accepts updates to only six StatefulSet `spec` fields: `replicas`,
`ordinals`, `template`, `updateStrategy`, `persistentVolumeClaimRetentionPolicy`
and `minReadySeconds`. Anything else is rejected on update, `selector` and `volumeClaimTemplates` in
particular.

So the chart injects nothing into those fields. `global.commonLabels` and
`global.commonAnnotations` reach every object's own metadata and every pod
template, but they stop at `volumeClaimTemplates`. Were it otherwise, simply
upgrading to a chart version that added a label would fail for every existing
release, and would keep failing on each release after that, because the identity
labels include `helm.sh/chart` and `app.kubernetes.io/version`.

You can still label a volume claim explicitly with
`graylog.persistence.labels`, `datanode.persistence.data.labels`,
`datanode.persistence.nativeLibs.labels` or `mongodb.persistence.labels`. That is
safe on a fresh install. On a release that already exists it is a one-way door.
The StatefulSet has to be recreated, which `kubectl delete statefulset <name>
--cascade=orphan` does without touching the running pods or the PVCs.

This rule is enforced by `tests/selector_immutability_test.yaml`. If you add an
object or a metadata call site, extend that suite; for anything immutable use
the `graylog.claim.metadata` helper, never `graylog.metadata.labels`.

## Extra volumes, mounts and containers

Graylog and Data Node pods accept additional volumes, volume mounts, init
containers and sidecars:

```yaml
# extra-volumes.yaml
graylog:
  extraVolumes:
    - name: corporate-ca
      secret:
        secretName: corporate-ca
  extraVolumeMounts:
    - name: corporate-ca
      mountPath: /etc/ssl/corporate
      readOnly: true
  # the chart's copy-data init container can mount them too
  extraInitVolumeMounts:
    - name: corporate-ca
      mountPath: /mnt/ca
      readOnly: true
  extraInitContainers:
    - name: wait-for-mongodb
      image: busybox:1.37
      command: ["sh", "-c", "until nc -z graylog-mongo-rs-svc 27017; do sleep 2; done"]
  extraContainers:
    - name: log-shipper
      image: busybox:1.37
```

## Pod scheduling and runtime

Both workloads expose `nodeSelector`, `tolerations`, `affinity`,
`topologySpreadConstraints`, `priorityClassName`, `schedulerName`,
`runtimeClassName`, `terminationGracePeriodSeconds`, `dnsPolicy`, `dnsConfig`,
`hostAliases` and container `lifecycle` hooks:

```yaml
# scheduling.yaml
graylog:
  priorityClassName: high-priority
  terminationGracePeriodSeconds: 120
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          app: graylog-app
  lifecycle:
    preStop:
      exec:
        command: ["/bin/sh", "-c", "sleep 10"]
```

`topologySpreadConstraints` is the one to reach for in a multi-AZ cluster. The
chart's default anti-affinity is a *soft* hostname preference: it spreads pods
across nodes when it can, but it does not guarantee a spread across zones, so a
single-zone failure can still take every Data Node replica with it.

> [!IMPORTANT]
> On the Graylog workload, `lifecycle.preStop` and
> `lifecycle.preStopDrain.enabled` both define a preStop hook, and a container
> can only have one. Setting both fails the render rather than silently
> dropping either. See [Message journal lifecycle](../graylog-message-handling.md#automatic-drain-on-shutdown)
> for what the chart-managed drain does.

## Extra objects

Anything the chart does not model can be deployed alongside it with
`extraObjects`. Entries share the release lifecycle, so the chart installs, upgrades and
deletes them, and they are templated, so they can reference the release:

```yaml
# extra-objects.yaml
extraObjects:
  - apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: '{{ include "graylog.fullname" . }}-metrics'
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/instance: '{{ .Release.Name }}'
          app.kubernetes.io/component: server
      endpoints:
        - port: metrics
```

Entries may also be given as strings, which is the practical form when the
manifest itself contains Helm syntax that must survive to render time:

```yaml
extraObjects:
  - |
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: {{ include "graylog.fullname" . }}-extra
    data:
      namespace: {{ .Release.Namespace }}
```

`global.commonLabels` and `global.commonAnnotations` are merged into every extra
object; anything set on the object itself wins.
