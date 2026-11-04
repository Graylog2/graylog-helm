# Values reference

Every chart value with its description and default. The defaults come from [values.yaml](values.yaml). Back to the [README](README.md).


| Key Path           | Description                                                      | Default |
|--------------------|------------------------------------------------------------------|---------|
| `provider`         | Kubernetes provider (optional).                                  | `""`    |
| `version`          | Override Graylog and Graylog Data Node version (optional).       | `""`    |
| `nameOverride`     | Override the `app.kubernetes.io/name` label value (optional).    | `""`    |
| `fullnameOverride` | Override the fully qualified name of the application (optional). | `""`    |
| `extraObjects`     | Arbitrary manifests rendered with the release; each entry is templated. | `[]` |

## Global
These values affect Graylog, DataNode, and MongoDB.

| Key Path                    | Description                                 | Default |
|-----------------------------|---------------------------------------------|---------|
| `global.existingSecretName` | Reference to an existing Kubernetes secret. | `""`    |
| `global.imagePullSecrets`   | Image pull secrets for private registries.  | `[]`    |
| `global.storageClass`       | Storage class to use for PVCs.              | `""`    |
| `global.commonLabels`       | Labels added to every object deployed by this chart.      | `{}` |
| `global.commonAnnotations`  | Annotations added to every object deployed by this chart. | `{}` |
| `global.s3.existingSecret`  | Secret holding the S3 credentials shared by the Data Node snapshot repository and Graylog archiving. Mutually exclusive with the inline pair below. | `""` |
| `global.s3.accessKeyKey`    | Key in that Secret holding the access key.  | `"AWS_ACCESS_KEY_ID"` |
| `global.s3.secretKeyKey`    | Key in that Secret holding the secret key.  | `"AWS_SECRET_ACCESS_KEY"` |
| `global.s3.accessKey`       | Inline S3 access key. Dev/test only.        | `""`    |
| `global.s3.secretKey`       | Inline S3 secret key. Dev/test only.        | `""`    |

> [!NOTE]
> `global.commonLabels` and `global.commonAnnotations` are applied to *every*
> object the chart renders. The chart's own identity labels
> (`app.kubernetes.io/*`, `helm.sh/chart`, `app`) and its Helm hook/resource-policy
> annotations always win, so they cannot be overwritten by accident. Per-object
> `labels`/`annotations` values (e.g. `graylog.service.annotations`) take
> precedence over the global ones.


## Graylog application

| Key Path                                                              | Description                                                 | Default                         |
|-----------------------------------------------------------------------|-------------------------------------------------------------|---------------------------------|
| `graylog.enabled`                                                     | Enable the Graylog server.                                  | `true`                          |
| `graylog.enterprise`                                                  | Select the Enterprise image as the default repository. Ignored when `graylog.image.repository` is set. | `true`                          |
| `graylog.replicas`                                                    | Number of Graylog server replicas.                          | `2`                             |
| `graylog.service.nameOverride`                                        | Override for service name.                                  | `""`                            |
| `graylog.service.type`                                                | Kubernetes service type.                                    | `ClusterIP`                     |
| `graylog.service.annotations`                                         | Annotations for the Graylog Service.                        | `{}`                            |
| `graylog.service.labels`                                              | Labels for the Graylog Service.                             | `{}`                            |
| `graylog.service.ports.app`                                           | Graylog web UI port.                                        | `9000`                          |
| `graylog.service.ports.metrics`                                       | Metrics endpoint port.                                      | `9833`                          |
| `graylog.service.metrics.enabled`                                     | Turn on Graylog's Prometheus exporter. Binds to `127.0.0.1` unless `expose` is set. Required by `graylog.lifecycle.preStopDrain`. | `true`                          |
| `graylog.service.metrics.expose`                                      | Bind the exporter to `0.0.0.0` and publish the metrics port on the Service so Prometheus can scrape it. The exporter is **unauthenticated** once exposed. | `false`                         |
| `graylog.serviceMonitor.enabled`                                      | Create a Prometheus Operator ServiceMonitor for the exporter. Requires `graylog.service.metrics.expose`. | `false`                         |
| `graylog.serviceMonitor.interval`                                     | Scrape interval.                                            | `30s`                           |
| `graylog.serviceMonitor.scrapeTimeout`                                | Scrape timeout. Must not exceed the interval.               | `10s`                           |
| `graylog.serviceMonitor.path`                                         | Metrics path on the exporter.                               | `/metrics`                      |
| `graylog.serviceMonitor.labels`                                       | Labels added to the ServiceMonitor. Set whatever your Prometheus Operator selects on. | `{}`                            |
| `graylog.serviceMonitor.annotations`                                  | Annotations added to the ServiceMonitor.                    | `{}`                            |
| `graylog.serviceMonitor.honorLabels`                                  | Keep metric labels that collide with the ones Prometheus adds. | `false`                         |
| `graylog.serviceMonitor.relabelings`                                  | Passed through to the endpoint verbatim.                    | `[]`                            |
| `graylog.serviceMonitor.metricRelabelings`                            | Passed through to the endpoint verbatim.                    | `[]`                            |
| `graylog.serviceMonitor.namespaceSelector`                            | Defaults to the release namespace.                          | `{}`                            |
| `graylog.inputs`                                                      | List of inputs to configure.                                | See below                       |
| `graylog.plugins`                                                     | List of plugins to configure.                               | See below                       |
| `graylog.env`                                                         | Custom environment variables.                               | `{}`                            |
| `graylog.config.rootUsername`                                         | Root admin username.                                        | `"admin"`                       |
| `graylog.config.rootPassword`                                         | Root admin password.                                        | `""`                            |
| `graylog.config.customSecretPepper`                                   | Internal hashing pepper (randomized when empty).            | `""`                            |
| `graylog.config.timezone`                                             | Timezone for the Graylog server.                            | `"UTC"`                         |
| `graylog.config.selfSignedStartup`                                    | Use self-signed certs on startup.                           | `"true"`                        |
| `graylog.config.serverJavaOpts`                                       | Java options for server.                                    | `"-Xms1g -Xmx1g"`               |
| `graylog.config.extraServerJavaOpts`                                  | Additional Java options for server.                         | `[]`                            |
| `graylog.config.leaderElectionMode`                                   | Mode for leader election.                                   | `"automatic"`                   |
| `graylog.config.contentPacksAutoInstall`                              | Auto-install content packs.                                 | `"true"`                        |
| `graylog.config.isCloud`                                              | Indicates if deployment is on cloud.                        | `"false"`                       |
| `graylog.config.tls.enabled`                                          | Enable TLS for Graylog.                                     | `false`                         |
| `graylog.config.tls.secretName`                                       | Name of the TLS secret.                                     | `""`                            |
| `graylog.config.tls.keyPassword`                                      | Password for the TLS key.                                   | `""`                            |
| `graylog.config.tls.updateKeyStore`                                   | Update Java keystore with TLS cert.                         | `true`                          |
| `graylog.config.tls.keyStorePass`                                     | Password for the Java keystore.                             | `"changeit"`                    |
| `graylog.config.mongodb.customUri`                                    | Custom MongoDB connection URI.                              | `""`                            |
| `graylog.config.mongodb.maxConnections`                               | Max MongoDB connections.                                    | `"1000"`                        |
| `graylog.config.mongodb.versionProbeAttempts`                         | MongoDB version probe attempts.                             | `"0"`                           |
| `graylog.config.messageJournal.enabled`                               | Enable message journal. Requires durable storage. The chart refuses to render this with `persistence.enabled=false` and no `existingClaim`, since the journal would be an `emptyDir`. A string, so disabling needs `--set-string`. | `"true"` |
| `graylog.config.messageJournal.maxSize`                                | On-disk journal cap. Must stay under 90% of `graylog.persistence.size`; the chart refuses to render otherwise. Binary suffixes, so `5gb` is 5×1024³. | `"5gb"` |
| `graylog.config.messageJournal.flushAge`                              | Journal flush age.                                          | `"1m"`                          |
| `graylog.config.messageJournal.flushInterval`                         | Journal flush interval.                                     | `"1000000"`                     |
| `graylog.config.messageJournal.maxAge`                                | Max journal age.                                            | `"12h"`                         |
| `graylog.config.messageJournal.segmentAge`                            | Journal segment age.                                        | `"1h"`                          |
| `graylog.config.messageJournal.segmentSize`                           | Journal segment size.                                       | `"100mb"`                       |
| `graylog.config.network.connectTimeout`                               | Network connect timeout.                                    | `"5s"`                          |
| `graylog.config.network.enableCors`                                   | Enable CORS.                                                | `"false"`                       |
| `graylog.config.network.enableGzip`                                   | Enable Gzip compression.                                    | `"true"`                        |
| `graylog.config.network.maxHeaderSize`                                | Max header size.                                            | `"8192"`                        |
| `graylog.config.network.readTimeout`                                  | Network read timeout.                                       | `"10s"`                         |
| `graylog.config.network.threadPoolSize`                               | Network thread pool size.                                   | `"64"`                          |
| `graylog.config.network.externalUri`                                  | Public URI of the Graylog web interface. Comes before the Ingress hostnames and the LoadBalancer Service address, so upgrades do not restart the pods when the load balancer address changes. Give a full URI. A bare hostname gets the chart scheme and the app port. | `""`                            |
| `graylog.config.performance.asyncEventbusProcessors`                  | Async event bus processors.                                 | `"2"`                           |
| `graylog.config.performance.autoRestartInputs`                        | Automatically restart inputs.                               | `"false"`                       |
| `graylog.config.performance.inputBufferProcessors`                    | Input buffer processors.                                    | `"2"`                           |
| `graylog.config.performance.inputBufferRingSize`                      | Input buffer ring size.                                     | `"65536"`                       |
| `graylog.config.performance.inputBufferWaitStrategy`                  | Input buffer wait strategy.                                 | `"blocking"`                    |
| `graylog.config.performance.jobSchedulerConcurrencyLimits`            | Scheduler concurrency limits.                               | `""`                            |
| `graylog.config.performance.outputBatchSize`                          | Output batch size.                                          | `"500"`                         |
| `graylog.config.performance.outputFaultCountThreshold`                | Output fault threshold.                                     | `"5"`                           |
| `graylog.config.performance.outputFaultPenaltySeconds`                | Output fault penalty seconds.                               | `"30"`                          |
| `graylog.config.performance.outputFlushInterval`                      | Output flush interval.                                      | `"1"`                           |
| `graylog.config.performance.outputBufferProcessorThreadsCorePoolSize` | Output processor thread pool size.                          | `"3"`                           |
| `graylog.config.performance.outputBufferProcessors`                   | Output buffer processors.                                   | `""`                            |
| `graylog.config.performance.processBufferProcessors`                  | Process buffer processors.                                  | `""`                            |
| `graylog.config.email.enabled`                                        | Enable email notifications.                                 | `"false"`                       |
| `graylog.config.email.senderAddress`                                  | Email sender address.                                       | `"graylog@example.com"`         |
| `graylog.config.email.hostname`                                       | SMTP hostname.                                              | `"mail.example.com"`            |
| `graylog.config.email.port`                                           | SMTP port.                                                  | `"587"`                         |
| `graylog.config.email.socketConnectionTimeout`                        | SMTP socket connect timeout.                                | `"10s"`                         |
| `graylog.config.email.socketTimeout`                                  | SMTP socket timeout.                                        | `"10s"`                         |
| `graylog.config.email.useAuth`                                        | Use SMTP authentication.                                    | `"true"`                        |
| `graylog.config.email.useSsl`                                         | Use SSL for SMTP.                                           | `"false"`                       |
| `graylog.config.email.useTls`                                         | Use TLS for SMTP.                                           | `"true"`                        |
| `graylog.config.email.webInterfaceUrl`                                | Web interface URL for email links.                          | `"https://graylog.example.com"` |
| `graylog.config.plugins.enabled`                                      | Enable Graylog plugin system.                               | `false`                         |
| `graylog.config.archive.useGlobalS3Credentials`                       | Put `global.s3` on the Graylog container as `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` for archiving. Leave off when using IRSA: the AWS SDK reads environment variables before the web identity token, so this overrides the role. | `false` |
| `graylog.config.geolocation.enabled`                                  | Enable the Geolocation Processor.                           | `false`                         |
| `graylog.config.geolocation.maxmindGeoIp.enabled`                     | Wire MaxMind credentials into the chart-managed Secret.     | `true`                          |
| `graylog.config.geolocation.maxmindGeoIp.existingSecret`              | Secret with the MaxMind credentials, read by the sidecar.    | `""`                            |
| `graylog.config.geolocation.maxmindGeoIp.accountIdKey`                | Key in `existingSecret` holding the account ID.             | `GEO_IP_MAXMIND_ACCOUNT_ID`     |
| `graylog.config.geolocation.maxmindGeoIp.licenseKeyKey`               | Key in `existingSecret` holding the license key.            | `GEO_IP_MAXMIND_LICENSE_KEY`    |
| `graylog.config.geolocation.maxmindGeoIp.accountId`                   | MaxMind Account ID (inline; wins over `existingSecret`).    |                                 |
| `graylog.config.geolocation.maxmindGeoIp.licenseKey`                  | MaxMind License Key (inline; wins over `existingSecret`).   |                                 |
| `graylog.config.geolocation.maxmindGeoIp.editionIds`                  | Space-separated MaxMind database editions to download.      | `"GeoLite2-City GeoLite2-ASN"`  |
| `graylog.config.geolocation.sidecar.enabled`                          | Enable the GeoIP update sidecar container.                  | `true`                          |
| `graylog.config.geolocation.sidecar.schedule`                         | Cron schedule for GeoIP database updates.                   | `"0 0 * * *"`                   |
| `graylog.config.geolocation.sidecar.image.repository`                 | Image repository for the GeoIP updater.                     | `"maxmindinc/geoipupdate"`      |
| `graylog.config.geolocation.sidecar.image.tag`                        | Image tag for the GeoIP updater.                            | `"v7.1.1"`                       |
| `graylog.config.geolocation.sidecar.image.imagePullPolicy`            | Pull policy for the GeoIP updater image.                    | `IfNotPresent`                  |
| `graylog.config.geolocation.sidecar.image.imagePullSecrets`           | Pull secrets for the GeoIP updater image.                   | `[]`                            |
| `graylog.config.geolocation.sidecar.resources`                        | Resource requests/limits for the sidecar.                   | see `values.yaml`               |
| `graylog.config.geolocation.sidecar.securityContext`                  | Container securityContext for the sidecar (runs as root).   | see `values.yaml`               |
| `graylog.config.geolocation.mmdbSources.city.url`                     | GeoLite2-City.mmdb URL (only for initial asset fetch).      |                                 |
| `graylog.config.geolocation.mmdbSources.city.checksum`                | GeoLite2-City.mmdb checksum (only for initial asset fetch). |                                 |
| `graylog.config.geolocation.mmdbSources.asn.url`                      | GeoLite2-ASN.mmdb URL (only for initial asset fetch).       |                                 |
| `graylog.config.geolocation.mmdbSources.asn.checksum`                 | GeoLite2-ASN.mmdb checksum (only for initial asset fetch).  |                                 |
| `graylog.config.init.assetFetch.enabled`                              | Enable asset fetch init.                                    | `false`                         |
| `graylog.config.init.assetFetch.skipChecksum`                         | Skip checksum validation for assets.                        | `false`                         |
| `graylog.config.init.assetFetch.allowHttp`                            | Allow HTTP fetch for assets.                                | `false`                         |
| `graylog.config.init.assetFetch.plugins.enabled`                      | Enable plugin asset fetch.                                  | `false`                         |
| `graylog.config.init.assetFetch.plugins.baseUrl`                      | Base URL for plugin assets.                                 | `""`                            |
| `graylog.config.init.assetFetch.geolocation.enabled`                  | Enable geolocation asset fetch.                             | `false`                         |
| `graylog.config.init.assetFetch.geolocation.baseUrl`                  | Base URL for geolocation assets.                            | `""`                            |
| `graylog.image.repository`                                            | Image repository for Graylog.                               | `""`                            |
| `graylog.image.tag`                                                   | Image tag for Graylog.                                      | `""`                            |
| `graylog.image.imagePullPolicy`                                       | Pull policy for Graylog image.                              | `IfNotPresent`                  |
| `graylog.image.imagePullSecrets`                                      | Pull secrets for image.                                     | `[]`                            |
| `graylog.updateStrategy.type`                                         | Pod update strategy for StatefulSet.                        | `"RollingUpdate"`               |
| `graylog.updateStrategy.rollingUpdate.maxUnavailable`                 | Max unavailable pods during an update. Honored only where the `MaxUnavailableStatefulSet` feature gate is enabled, silently dropped otherwise. | `1`                             |
| `graylog.updateStrategy.rollingUpdate.partition`                      | Pods that will remain unaffected by the update.             | `""`                            |
| `graylog.resources.limits.cpu`                                        | CPU limit for the Graylog pod.                              | `"2"`                           |
| `graylog.resources.limits.memory`                                     | Memory limit for the Graylog pod.                           | `"2Gi"`                         |
| `graylog.resources.requests.cpu`                                      | CPU request for the Graylog pod.                            | `"1"`                           |
| `graylog.resources.requests.memory`                                   | Memory request for the Graylog pod.                         | `"1Gi"`                         |
| `graylog.persistence.enabled`                                         | Enable persistent storage.                                  | `true`                          |
| `graylog.persistence.storageClass`                                    | Storage class for the persistent volume.                    | `""`                            |
| `graylog.persistence.volumeNameOverride`                              | Override name of the persistent volume.                     | `""`                            |
| `graylog.persistence.existingClaim`                                   | Use an existing PVC.                                        | `""`                            |
| `graylog.persistence.accessModes`                                     | Access modes for the persistent volume.                     | `[]`                            |
| `graylog.persistence.size`                                            | Size of the persistent volume.                              | `""`                            |
| `graylog.persistence.annotations`                                     | Annotations for the persistent volume claim.                | `{}`                            |
| `graylog.persistence.labels`                                          | Labels for the persistent volume claim.                     | `{}`                            |
| `graylog.startupProbe.enabled`                                        | Enable startup probe. Holds liveness/readiness off until Graylog has booted. | `true`          |
| `graylog.startupProbe.initialDelaySeconds`                            | Initial delay for startup probe.                            | `30`                            |
| `graylog.startupProbe.periodSeconds`                                  | Period between startup probe checks.                        | `10`                            |
| `graylog.startupProbe.timeoutSeconds`                                 | Timeout for the startup probe.                              | `5`                             |
| `graylog.startupProbe.failureThreshold`                               | Failure threshold. x `periodSeconds` is the whole boot budget (default 5 min). | `30`         |
| `graylog.livenessProbe.enabled`                                       | Enable liveness probe.                                      | `true`                          |
| `graylog.livenessProbe.initialDelaySeconds`                           | Initial delay for liveness probe.                           | `60`                            |
| `graylog.livenessProbe.periodSeconds`                                 | Period between liveness probe checks.                       | `10`                            |
| `graylog.livenessProbe.timeoutSeconds`                                | Timeout for the liveness probe.                             | `5`                             |
| `graylog.livenessProbe.failureThreshold`                              | Failure threshold for the liveness probe.                   | `6`                             |
| `graylog.readinessProbe.enabled`                                      | Enable readiness probe.                                     | `true`                          |
| `graylog.readinessProbe.initialDelaySeconds`                          | Initial delay for readiness probe.                          | `30`                            |
| `graylog.readinessProbe.periodSeconds`                                | Period between readiness probe checks.                      | `10`                            |
| `graylog.readinessProbe.timeoutSeconds`                               | Timeout for the readiness probe.                            | `5`                             |
| `graylog.readinessProbe.failureThreshold`                             | Failure threshold for the readiness probe.                  | `6`                             |
| `graylog.readinessProbe.successThreshold`                             | Success threshold for the readiness probe.                  | `1`                             |
| `graylog.{startup,liveness,readiness}Probe.{httpGet,tcpSocket,exec,grpc}` | Custom probe handler, standard Kubernetes syntax. Replaces the chart default for that probe. | _(unset)_ |
| `graylog.terminationGracePeriodSeconds`                               | Shutdown budget before SIGKILL. Covers the preStop hook and Graylog's own graceful shutdown. | `300`  |
| `graylog.lifecycle.postStart`                                         | Your own postStart hook on the graylog-app container.       | `{}`                            |
| `graylog.lifecycle.preStop`                                           | Your own preStop hook. Mutually exclusive with `preStopDrain.enabled`. | `{}`                  |
| `graylog.lifecycle.preStopDrain.enabled`                              | Hold termination while the journal drains. See [Message journal lifecycle](../../docs/graylog-message-handling.md#automatic-drain-on-shutdown). | `false` |
| `graylog.lifecycle.preStopDrain.endpointPropagationDelaySeconds`      | Wait for EndpointSlice removal to reach kube-proxy before sampling. | `15`                     |
| `graylog.lifecycle.preStopDrain.pollIntervalSeconds`                  | Seconds between journal-depth samples.                      | `2`                             |
| `graylog.lifecycle.preStopDrain.shutdownReserveSeconds`               | Seconds reserved out of the grace period for Graylog's own shutdown. | `45`                   |
| `graylog.lifecycle.preStopDrain.stallPolls`                           | Give up after this many polls with no decrease in journal depth. | `10`                       |
| `graylog.lifecycle.preStopDrain.statusIntervalSeconds`                | How often to log a progress line during the drain.          | `10`                            |
| `graylog.lifecycle.preStopDrain.confirmPolls`                          | Consecutive zero readings required before declaring the journal drained. | `3`                |
| `graylog.lifecycle.preStopDrain.metricsRetries`                        | Retries for the metrics probe before giving up.              | `5`                             |
| `graylog.lifecycle.preStopDrain.feasibilityWarmupPolls`                | Polls observed before projecting whether the drain can finish; aborts early if it cannot. `0` disables. | `5` |
| `graylog.persistence.retentionPolicy.whenDeleted`                      | PVC fate when the StatefulSet is deleted.                   | `Retain`                        |
| `graylog.persistence.retentionPolicy.whenScaled`                       | PVC fate when scaled in. `Delete` is refused because it destroys a scaled-in node's journal. | `Retain` |
| `graylog.podDisruptionBudget.enabled`                                 | Enable PodDisruptionBudget.                                 | `false`                         |
| `graylog.podDisruptionBudget.minAvailable`                            | Minimum available pods during disruption.                   | `1`                             |
| `graylog.podDisruptionBudget.maxUnavailable`                          | Alternative to `minAvailable` (int or `"N%"`); mutually exclusive, wins over `minAvailable` when set. | `""` |
| `graylog.podDisruptionBudget.annotations`                             | Annotations for the PodDisruptionBudget.                    | `{}`                            |
| `graylog.podDisruptionBudget.labels`                                  | Labels for the PodDisruptionBudget.                         | `{}`                            |
| `graylog.annotations`                                                 | Annotations for the Graylog StatefulSet, ConfigMaps and Secrets. | `{}`                       |
| `graylog.labels`                                                      | Labels for the Graylog StatefulSet, ConfigMaps and Secrets.      | `{}`                       |
| `graylog.podAnnotations`                                              | Additional pod annotations.                                 | `{}`                            |
| `graylog.podLabels`                                                   | Additional pod labels.                                      | `{}`                            |
| `graylog.nodeSelector`                                                | Node selector for scheduling.                               | `{}`                            |
| `graylog.tolerations`                                                 | Tolerations for scheduling.                                 | `[]`                            |
| `graylog.affinity`                                                    | Affinity rules for scheduling.                              | `{}`                            |
| `graylog.topologySpreadConstraints`                                   | Topology spread constraints for the pods.                   | `[]`                            |
| `graylog.priorityClassName`                                           | PriorityClass for the pods.                                 | `""`                            |
| `graylog.schedulerName`                                               | Custom scheduler for the pods.                              | `""`                            |
| `graylog.runtimeClassName`                                            | RuntimeClass for the pods.                                  | `""`                            |
| `graylog.terminationGracePeriodSeconds`                               | Grace period before pods are force-killed.                  | `nil`                           |
| `graylog.dnsPolicy`                                                   | Pod DNS policy.                                             | `ClusterFirst`                  |
| `graylog.dnsConfig`                                                   | Pod DNS configuration.                                      | `{}`                            |
| `graylog.hostAliases`                                                 | Additional `/etc/hosts` entries for the pods.               | `[]`                            |
| `graylog.lifecycle`                                                   | Lifecycle hooks for the `graylog-app` container.            | `{}`                            |
| `graylog.extraEnv`                                                    | Custom EnvVar environment variables.                        | `[]`                            |
| `graylog.extraVolumes`                                                | Additional volumes for the Graylog pods.                    | `[]`                            |
| `graylog.extraVolumeMounts`                                           | Additional volume mounts for the `graylog-app` container.   | `[]`                            |
| `graylog.extraInitVolumeMounts`                                       | Additional volume mounts for the `copy-data` init container. | `[]`                           |
| `graylog.extraInitContainers`                                         | Additional init containers.                                 | `[]`                            |
| `graylog.extraContainers`                                             | Additional sidecar containers.                              | `[]`                            |


### Graylog inputs

| Key Path                       | Description                       | Example            |
|--------------------------------|-----------------------------------|--------------------|
| `graylog.inputs[i].name`       | Name to identify this input.      | `input-gelf`       |
| `graylog.inputs[i].port`       | Port exposed for this input.      | `12201`            |
| `graylog.inputs[i].targetPort` | Target container port (optional). | `12201`            |
| `graylog.inputs[i].protocol`   | Protocol used for this input.     | `TCP`              |

### Graylog plugins

| Key Path                           | Description                            | Example                                                            |
|------------------------------------|----------------------------------------|--------------------------------------------------------------------|
| `graylog.plugins[i].name`          | Name to identify this plugin.          | `graylog-plugin-slack`                                             |
| `graylog.plugins[i].image`         | Image containing the JAR to be copied. | `myrepo/graylog-plugin-slack:1.2.3`                                |
| `graylog.plugins[i].existingClaim` | Existing PVC with JAR to be copied.    | `myotherapp-pvc-0`                                                 |
| `graylog.plugins[i].url`           | URL of JAR to be retrieved.            | `https://myurl/plugins/graylog-plugin-slack.jar`                   |
| `graylog.plugins[i].checksum`      | Checksum of JAR file.                  | `13550350a8681c84c861aac2e5b440161c2b33a3e4f302ac680ca5b686de48de` |

### Graylog environment variables

| Key Path           | Description                                                                                                                                                                                | Example                                                                                                                                                          |
|--------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `graylog.env`      | Simple key/value environment variables                                                                                                                                                     | `graylog.env.FOO=BAR`, `graylog.env.HELLO=123`                                                                                                                   |
| `graylog.extraEnv` | [EnvVar spec](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#environment-variables)-compliant environment variables (valueFrom, configMaps, secrets, etc.) | <pre><code>extraEnv:&#10;  - name: MADE_UP_PASSWORD&#10;    valueFrom:&#10;      secretKeyRef:&#10;        name: mysecret&#10;        key: password</code></pre> |

## DataNode

| Key Path                                               | Description                                     | Default           |
|--------------------------------------------------------|-------------------------------------------------|-------------------|
| `datanode.enabled`                                     | Enable Graylog datanode.                        | `true`            |
| `datanode.replicas`                                    | Number of datanode replicas.                    | `3`               |
| `datanode.roles`                                       | OpenSearch roles for the primary node group; empty = Data Node default. [Guide](../../docs/datanode/datanode-node-roles.md). | `[]` |
| `datanode.extraNodeGroups`                             | Map of additional node groups keyed by name, each inheriting and overriding `datanode.*`. [Guide](../../docs/datanode/datanode-node-roles.md). | `{}` |
| `datanode.reloader.autoReload`                         | Allow Stakater Reloader to restart this group's pods on its own ConfigMap/Secret change. Off by default. See the node groups guide. | `false` |
| `datanode.service.annotations`                         | Annotations for the Data Node Service.          | `{}`              |
| `datanode.service.labels`                              | Labels for the Data Node Service.               | `{}`              |
| `datanode.service.ports.api`                           | API communication port.                         | `8999`            |
| `datanode.service.ports.data`                          | Data communication port.                        | `9200`            |
| `datanode.service.ports.config`                        | Configuration communication port.               | `9300`            |
| `datanode.env`                                         | Custom environment variables.                   | `{}`              |
| `datanode.serviceAccount.create`                       | Give the Data Node its own ServiceAccount instead of sharing the Graylog one. | `false` |
| `datanode.serviceAccount.automount`                    | Automount the Data Node service account token.  | `true`            |
| `datanode.serviceAccount.annotations`                  | Annotations for the Data Node service account.  | `{}`              |
| `datanode.serviceAccount.labels`                       | Labels for the Data Node service account.       | `{}`              |
| `datanode.serviceAccount.nameOverride`                 | Name of the Data Node service account, or of an existing one to use. | `""` |
| `datanode.serviceAccount.role.create`                  | Create a Role/RoleBinding for the Data Node service account. | `false` |
| `datanode.serviceAccount.role.rules`                   | Rules for that Role.                            | `[]`              |
| `datanode.serviceAccount.role.annotations`             | Annotations for the Role and RoleBinding.       | `{}`              |
| `datanode.serviceAccount.role.labels`                  | Labels for the Role and RoleBinding.            | `{}`              |
| `datanode.config.nodeIdFile`                           | Path to datanode ID file.                       | `""`              |
| `datanode.config.opensearchHeap`                       | OpenSearch heap size.                           | `"2g"`            |
| `datanode.config.javaOpts`                             | Java options for datanode.                      | `"-Xms1g -Xmx1g"` |
| `datanode.config.skipPreflightChecks`                  | Skip startup checks.                            | `"false"`         |
| `datanode.config.nodeSearchCacheSize`                  | Size of search cache.                           | `"10gb"`          |
| `datanode.config.s3ClientDefaultSecretKey`             | Default S3 client secret key.                   | `""`              |
| `datanode.config.s3ClientDefaultAccessKey`             | Default S3 client access key.                   | `""`              |
| `datanode.config.s3ClientDefaultExistingSecret`        | Existing Secret holding the S3 access key and secret key. Mutually exclusive with the two inline keys above. | `""` |
| `datanode.config.s3ClientDefaultAccessKeyKey`          | Key in that Secret holding the access key.      | `"GRAYLOG_DATANODE_S3_CLIENT_DEFAULT_ACCESS_KEY"` |
| `datanode.config.s3ClientDefaultSecretKeyKey`          | Key in that Secret holding the secret key.      | `"GRAYLOG_DATANODE_S3_CLIENT_DEFAULT_SECRET_KEY"` |
| `datanode.config.s3ClientDefaultEndpoint`              | Default S3 client endpoint.                     | `""`              |
| `datanode.config.s3ClientDefaultRegion`                | Default S3 client region.                       | `"us-east-2"`     |
| `datanode.config.s3ClientDefaultProtocol`              | Default S3 client protocol.                     | `"http"`          |
| `datanode.config.s3ClientDefaultPathStyleAccess`       | Enable path-style access for S3 client.         | `"true"`          |
| `datanode.config.snapshotRepositoryExternal`           | Declare that a snapshot repository is configured by a route the chart cannot see, such as `GRAYLOG_DATANODE_PATH_REPO` via `extraEnv`. Relaxes the render guard only; the Data Node still applies its own check. | `false` |
| `datanode.image.repository`                            | Datanode image repository.                      | `""`              |
| `datanode.image.tag`                                   | Datanode image tag.                             | `""`              |
| `datanode.image.imagePullPolicy`                       | Image pull policy.                              | `IfNotPresent`    |
| `datanode.image.imagePullSecrets`                      | Image pull secrets.                             | `[]`              |
| `datanode.updateStrategy.type`                         | Pod update strategy for StatefulSet.            | `"RollingUpdate"` |
| `datanode.updateStrategy.rollingUpdate.maxUnavailable` | Max unavailable pods during an update. Honored only where the `MaxUnavailableStatefulSet` feature gate is enabled, silently dropped otherwise. | `1`               |
| `datanode.updateStrategy.rollingUpdate.partition`      | Pods that will remain unaffected by the update. | `""`              |
| `datanode.resources.limits.cpu`                        | CPU limit for the datanode pod.                 | `"1"`             |
| `datanode.resources.limits.memory`                     | Memory limit for the datanode pod.              | `"5Gi"`           |
| `datanode.resources.requests.cpu`                      | CPU request for the datanode pod.               | `"500m"`          |
| `datanode.resources.requests.memory`                   | Memory request for the datanode pod.            | `"3.5Gi"`         |
| `datanode.persistence.retentionPolicy.whenDeleted`     | PVC fate when the StatefulSet is deleted.       | `Retain`          |
| `datanode.persistence.retentionPolicy.whenScaled`      | PVC fate when scaled in. `Delete` is permitted here (shard data rebuilds from replicas), unlike on the Graylog StatefulSet. | `Retain` |
| `datanode.persistence.data.enabled`                    | Enable persistent volume for data.              | `true`            |
| `datanode.persistence.data.storageClass`               | Storage class for data PVC.                     | `""`              |
| `datanode.persistence.data.mountPath`                  | Mount path for data volume.                     | `""`              |
| `datanode.persistence.data.accessModes`                | Access modes for data PVC.                      | `[]`              |
| `datanode.persistence.data.size`                       | Size of the data volume.                        | `"8Gi"`           |
| `datanode.persistence.data.annotations`                | Annotations for the data PVC (globals do not apply). | `{}`         |
| `datanode.persistence.data.labels`                     | Labels for the data PVC (globals do not apply). | `{}`              |
| `datanode.persistence.nativeLibs.enabled`              | Enable persistence for native libraries.        | `false`           |
| `datanode.persistence.nativeLibs.storageClass`         | Storage class for native libs PVC.              | `""`              |
| `datanode.persistence.nativeLibs.mountPath`            | Mount path for native libs volume.              | `""`              |
| `datanode.persistence.nativeLibs.accessModes`          | Access modes for native libs PVC.               | `[]`              |
| `datanode.persistence.nativeLibs.size`                 | Size of the native libs volume.                 | `"2Gi"`           |
| `datanode.persistence.nativeLibs.annotations`          | Annotations for native libs PVC.                | `{}`              |
| `datanode.persistence.nativeLibs.labels`               | Labels for native libs PVC.                     | `{}`              |
| `datanode.startupProbe.enabled`                        | Enable startup probe.                           | `true`            |
| `datanode.startupProbe.initialDelaySeconds`            | Initial delay for startup probe.                | `30`              |
| `datanode.startupProbe.periodSeconds`                  | Period between startup probe checks.            | `10`              |
| `datanode.startupProbe.timeoutSeconds`                 | Timeout for the startup probe.                  | `5`               |
| `datanode.startupProbe.failureThreshold`               | Failure threshold. x `periodSeconds` is the boot budget. | `30`     |
| `datanode.livenessProbe.enabled`                       | Enable liveness probe.                          | `true`            |
| `datanode.livenessProbe.initialDelaySeconds`           | Initial delay for liveness probe.               | `30`              |
| `datanode.livenessProbe.periodSeconds`                 | Period between liveness probe checks.           | `10`              |
| `datanode.livenessProbe.timeoutSeconds`                | Timeout for the liveness probe.                 | `5`               |
| `datanode.livenessProbe.failureThreshold`              | Failure threshold for the liveness probe.       | `6`               |
| `datanode.readinessProbe.enabled`                      | Enable readiness probe.                         | `true`            |
| `datanode.readinessProbe.initialDelaySeconds`          | Initial delay for readiness probe.              | `10`              |
| `datanode.readinessProbe.periodSeconds`                | Period between readiness probe checks.          | `10`              |
| `datanode.readinessProbe.timeoutSeconds`               | Timeout for the readiness probe.                | `5`               |
| `datanode.readinessProbe.failureThreshold`             | Failure threshold for the readiness probe.      | `6`               |
| `datanode.readinessProbe.successThreshold`             | Success threshold for the readiness probe.      | `1`               |
| `datanode.{startup,liveness,readiness}Probe.{httpGet,tcpSocket,exec,grpc}` | Custom probe handler, standard Kubernetes syntax. Replaces the chart default. | _(unset)_ |
| `datanode.sysctlInit.enabled`                          | Run a privileged init container that sets `vm.max_map_count`. See [Prerequisites](README.md#kernel-parameter-vmmax_map_count). | `false` |
| `datanode.sysctlInit.vmMaxMapCount`                    | Value to set. Must be at least 262144.          | `262144`          |
| `datanode.sysctlInit.image.repository`                 | Init container image repository.                | `busybox`         |
| `datanode.sysctlInit.image.tag`                        | Init container image tag.                       | `1.35`            |
| `datanode.podManagementPolicy`                         | `OrderedReady` or `Parallel`. Immutable once the StatefulSet exists. | `OrderedReady` |
| `datanode.podDisruptionBudget.enabled`                 | Enable PodDisruptionBudget.                     | `false`           |
| `datanode.podDisruptionBudget.minAvailable`            | Minimum available pods during disruption.       | `2`               |
| `datanode.podDisruptionBudget.maxUnavailable`          | Alternative to `minAvailable` (int or `"N%"`); mutually exclusive, wins over `minAvailable` when set. Applies per group unless `consolidated` is set. | `""` |
| `datanode.podDisruptionBudget.annotations`             | Annotations for the PodDisruptionBudget.        | `{}`              |
| `datanode.podDisruptionBudget.labels`                  | Labels for the PodDisruptionBudget.             | `{}`              |
| `datanode.podDisruptionBudget.consolidated`            | Render one PDB spanning the primary group and all `extraNodeGroups`, instead of one per group. | `false` |
| `datanode.annotations`                                 | Annotations for the Data Node StatefulSet, ConfigMap and Secret. | `{}` |
| `datanode.labels`                                      | Labels for the Data Node StatefulSet, ConfigMap and Secret.      | `{}` |
| `datanode.podAnnotations`                              | Additional pod annotations.                     | `{}`              |
| `datanode.podLabels`                                   | Additional pod labels.                          | `{}`              |
| `datanode.nodeSelector`                                | Node selector for scheduling datanode pods.     | `{}`              |
| `datanode.tolerations`                                 | Tolerations for scheduling.                     | `[]`              |
| `datanode.affinity`                                    | Affinity rules for scheduling.                  | `{}`              |
| `datanode.topologySpreadConstraints`                   | Topology spread constraints for the pods.       | `[]`              |
| `datanode.priorityClassName`                           | PriorityClass for the pods.                     | `""`              |
| `datanode.schedulerName`                               | Custom scheduler for the pods.                  | `""`              |
| `datanode.runtimeClassName`                            | RuntimeClass for the pods.                      | `""`              |
| `datanode.terminationGracePeriodSeconds`               | Grace period before pods are force-killed.      | `nil`             |
| `datanode.dnsPolicy`                                   | Pod DNS policy.                                 | `ClusterFirst`    |
| `datanode.dnsConfig`                                   | Pod DNS configuration.                          | `{}`              |
| `datanode.hostAliases`                                 | Additional `/etc/hosts` entries for the pods.   | `[]`              |
| `datanode.lifecycle`                                   | Lifecycle hooks for the `graylog-datanode` container. | `{}`        |
| `datanode.extraEnv`                                    | Custom EnvVar environment variables.            | `[]`              |
| `datanode.extraVolumes`                                | Additional volumes for the Data Node pods.      | `[]`              |
| `datanode.extraVolumeMounts`                           | Additional volume mounts for the `graylog-datanode` container. | `[]` |
| `datanode.extraInitContainers`                         | Additional init containers.                     | `[]`              |
| `datanode.extraContainers`                             | Additional sidecar containers.                  | `[]`              |


## OpenSearch
Connect Graylog to an external, self-managed OpenSearch cluster instead of the bundled Data Node.
Mutually exclusive with `datanode.enabled`. See [Bring your own OpenSearch](../../docs/bring-your-own-opensearch.md).

| Key Path                         | Description                                                                                             | Default      |
|----------------------------------|---------------------------------------------------------------------------------------------------------|--------------|
| `opensearch.enabled`             | Enable external OpenSearch mode. Requires `datanode.enabled=false`.                                     | `false`      |
| `opensearch.hosts`               | OpenSearch node REST URIs (scheme, host and port), without credentials.                                 | `[]`         |
| `opensearch.auth.existingSecret` | Secret holding the OpenSearch username and password, read at install/upgrade time.                      | `""`         |
| `opensearch.auth.usernameKey`    | Key within `existingSecret` holding the username.                                                       | `"username"` |
| `opensearch.auth.passwordKey`    | Key within `existingSecret` holding the password.                                                       | `"password"` |
| `opensearch.auth.username`       | Inline username. Takes precedence over `existingSecret`; intended for development and testing.          | `""`         |
| `opensearch.auth.password`       | Inline password. Takes precedence over `existingSecret`; intended for development and testing.          | `""`         |
| `opensearch.tls.enabled`         | Whether the OpenSearch HTTP layer uses TLS. Set to `false` for plaintext (`http://`) hosts.             | `true`       |
| `opensearch.tls.caSecret`        | Secret containing the CA certificate for the OpenSearch HTTP layer, imported into Graylog's truststore. | `""`         |
| `opensearch.tls.caKey`           | Key within `caSecret` holding the CA certificate.                                                       | `"ca.crt"`   |


## Service Account

| Key Path                      | Description                                             | Default |
|-------------------------------|---------------------------------------------------------|---------|
| `serviceAccount.create`       | Create a new service account.                           | `true`  |
| `serviceAccount.automount`    | Automount service account token.                        | `true`  |
| `serviceAccount.annotations`  | Annotations for service account.                        | `{}`    |
| `serviceAccount.labels`       | Labels for service account.                             | `{}`    |
| `serviceAccount.nameOverride` | Override name of service account.                       | `""`    |
| `serviceAccount.role.create`  | Create a new role to bind to this service account.      | `false` |
| `serviceAccount.role.rules`   | Rules for the new role to bind to this service account. | `[]`    |
| `serviceAccount.role.annotations` | Annotations for the Role and RoleBinding.           | `{}`    |
| `serviceAccount.role.labels`  | Labels for the Role and RoleBinding.                    | `{}`    |

The chart creates one service account, `<release>-sa`, and both the Graylog server and the Data
Node pods run under it. MongoDB is the exception and always has its own, `<release>-mongo-sa`.

### Giving the Data Node its own service account

Set `datanode.serviceAccount.create=true` to move the Data Node pods onto `<release>-datanode-sa`.
The fields mirror the top-level block.

```yaml
datanode:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::111122223333:role/graylog-datanode
```

Do this when the Data Node needs different cloud permissions than the Graylog server, which is the
usual reason on EKS. A pod carries exactly one IAM role, so sharing an account means sharing every
permission on it.

The default is `false`, and the Data Node keeps using the top-level account. Turning it on changes
the pod template and rolls every Data Node pod, so treat it as a planned restart rather than a
config tweak.

To point the Data Node at a service account you manage yourself, leave `create` at `false` and set
`nameOverride`:

```yaml
datanode:
  serviceAccount:
    nameOverride: my-existing-sa
```

> [!IMPORTANT]
> On EKS the IRSA webhook injects `AWS_ROLE_ARN` and the projected token when the pod is **created**.
> Annotating a service account does nothing to pods that are already running, and there is no
> warning. Restart the workload afterwards and confirm the variable is present.

> [!WARNING]
> An IRSA role on the Data Node does **not** reach its snapshot repository. As of Data Node 7.1 with
> OpenSearch 2.19, the `repository-s3` plugin reads a web identity token only through a file inside
> the OpenSearch config directory, and the Data Node regenerates that directory under a new random
> name on every start. The plugin falls back to the EC2 instance profile of the node it runs on,
> silently. Searchable snapshots still need `datanode.config.s3ClientDefaultAccessKey` and
> `s3ClientDefaultSecretKey`. This is worth knowing for its own sake: without those keys a snapshot
> repository inherits whatever the node role can reach.


## Ingress

| Key Path                                        | Description                                      | Default |
|-------------------------------------------------|--------------------------------------------------|---------|
| `ingress.enabled`                               | Enable ingress resources.                        | `false` |
| `ingress.config.defaultBackend.enabled`         | Enable default backend for ingress.              | `true`  |
| `ingress.config.tls.clusterIssuer.existingName` | Name of existing ClusterIssuer for TLS.          | `""`    |
| `ingress.config.tls.issuer.existingName`        | Name of existing Issuer for TLS.                 | `""`    |
| `ingress.config.tls.issuer.annotations`         | Annotations for the chart-managed Issuer.        | `{}`    |
| `ingress.config.tls.issuer.labels`              | Labels for the chart-managed Issuer.             | `{}`    |
| `ingress.config.tls.issuer.managed.enabled`     | Enable auto-issuing of TLS certificates.         | `false` |
| `ingress.config.tls.issuer.managed.staging`     | Use staging environment for auto-issued certs.   | `true`  |

### Web Ingress

| Key Path                                 | Description                        | Default                  |
|------------------------------------------|------------------------------------|--------------------------|
| `ingress.web.enabled`                    | Enable ingress for Graylog Web.    | `false`                  |
| `ingress.web.className`                  | Ingress class name.                | `""`                     |
| `ingress.web.annotations`                | Annotations for ingress resource.  | `{}`                     |
| `ingress.web.labels`                     | Labels for ingress resource.       | `{}`                     |
| `ingress.web.hosts[0].host`              | Hostname for ingress (optional).   | `""`                     |
| `ingress.web.hosts[0].paths[0].path`     | Path for routing.                  | `/`                      |
| `ingress.web.hosts[0].paths[0].pathType` | Path matching type.                | `ImplementationSpecific` |
| `ingress.web.tls`                        | TLS configuration.                 | `[]`                     |

### Forwarder Ingress

A [Graylog Forwarder](https://go2docs.graylog.org/current/getting_in_log_data/forwarder.html) requires **both**
gRPC channels to be reachable: the message channel (port `13301`) it ships log data on, and the configuration
channel (port `13302`) it polls for configuration updates. Because the two channels listen on different ports
and an Ingress routes on host/path rather than listener port, each channel is rendered as its own Ingress
resource, `<release>-forwarder-message-channel` and `<release>-forwarder-config-channel`.

Setting `ingress.forwarder.enabled: true` enables both channels; disable one with
`ingress.forwarder.<channel>.enabled: false`.

The Forwarder is an enterprise feature and requires a valid license.

The Ingress only exposes the ports. It cannot make Graylog listen on them. A **Forwarder input** must
exist for that: an input of type **Forwarder**
(`org.graylog.plugins.forwarder.input.ForwarderServiceInput`) created under **System > Inputs**. Graylog
Cloud provisions it automatically; self-managed deployments must create it. Registering a forwarder
under **System > Forwarders** is *not* sufficient, and neither is any chart setting. Until the input
exists, `13301`/`13302` stay closed, forwarders fail with `Code=<UNAVAILABLE>`, and load balancer
targets remain unhealthy. Once it exists, Graylog binds the ports on every node.

The listener is configured by attributes **on that input**, not through `server.conf` or this chart:

| Input attribute | Default |
|---|---|
| `forwarder_bind_address` | `0.0.0.0` |
| `forwarder_message_transmission_port` | `13301` |
| `forwarder_configuration_port` | `13302` |
| `forwarder_grpc_enable_tls` | `true` |

> [!IMPORTANT]
> `forwarder_grpc_enable_tls` defaults to **true** on the input. When a load balancer terminates TLS and
> speaks cleartext HTTP/2 to Graylog, as in the ALB example above, it must be set to **false**, or the
> targets never become healthy. Set TLS on the *forwarder agent* instead, since it connects to the load
> balancer's certificate.

| Key Path                                                      | Description                                     | Default                  |
|---------------------------------------------------------------|-------------------------------------------------|--------------------------|
| `ingress.forwarder.enabled`                                   | Enable ingress for Graylog Forwarder ingest.    | `false`                  |
| `ingress.forwarder.messageChannel.enabled`                    | Expose the message channel (port `13301`).      | `true`                   |
| `ingress.forwarder.messageChannel.className`                  | Ingress class name.                             | `""`                     |
| `ingress.forwarder.messageChannel.annotations`                | Annotations for ingress resource.               | `{}`                     |
| `ingress.forwarder.messageChannel.labels`                     | Labels for ingress resource.                    | `{}`                     |
| `ingress.forwarder.messageChannel.hosts[0].host`              | Hostname for ingress (optional).                | `""`                     |
| `ingress.forwarder.messageChannel.hosts[0].paths[0].path`     | Path for routing.                               | `/`                      |
| `ingress.forwarder.messageChannel.hosts[0].paths[0].pathType` | Path matching type.                             | `ImplementationSpecific` |
| `ingress.forwarder.messageChannel.tls`                        | TLS configuration.                              | `[]`                     |
| `ingress.forwarder.configChannel.enabled`                     | Expose the configuration channel (port `13302`).| `true`                   |
| `ingress.forwarder.configChannel.className`                   | Ingress class name.                             | `""`                     |
| `ingress.forwarder.configChannel.annotations`                 | Annotations for ingress resource.               | `{}`                     |
| `ingress.forwarder.configChannel.labels`                      | Labels for ingress resource.                    | `{}`                     |
| `ingress.forwarder.configChannel.hosts[0].host`               | Hostname for ingress (optional).                | `""`                     |
| `ingress.forwarder.configChannel.hosts[0].paths[0].path`      | Path for routing.                               | `/`                      |
| `ingress.forwarder.configChannel.hosts[0].paths[0].pathType`  | Path matching type.                             | `ImplementationSpecific` |
| `ingress.forwarder.configChannel.tls`                         | TLS configuration.                              | `[]`                     |

See [`examples/values/values-example-forwarder-ingress.yaml`](../../examples/values/values-example-forwarder-ingress.yaml) for a worked AWS ALB
configuration.

## MongoDB
MongoDB Community Resource configuration.
Requires the MCK Operator: https://github.com/mongodb/mongodb-kubernetes/tree/master/docs/mongodbcommunity

The operator creates the MongoDB containers itself and injects its own resource
defaults, which the three resource blocks below patch by container name. The
only way to size MongoDB from the chart.

The defaults are sized for a production replica set. `mongod` gets 2Gi of
headroom because WiredTiger sizes its cache from the container limit and Graylog
keeps its whole configuration in MongoDB; an idle 3-member replica set already
sits at ~340Mi. CPU goes the other way: the same replica set idles under 50m per
member, so the requests are modest and the limits leave room to burst.

`initResources` covers the two init containers the operator injects. Because a
pod reserves `max(max(initContainer), sum(containers))`, an init container
request larger than the containers' combined request becomes the pod's floor, so
these are kept deliberately small. Each only copies a binary into a shared
volume.

Overrides deep-merge, so setting only `requests` keeps the default `limits`; set
a block to `null` to drop the override and defer to the operator. For a
small-footprint install, see [`ci/ci-values.yaml`](ci/ci-values.yaml), which
shrinks all three blocks together.

| Key Path                              | Description                                                 | Default                                                                                                                                                                                                                |
|---------------------------------------|-------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `mongodb.communityResource.enabled`   | Enables creation of the `MongoDBCommunity` custom resource. | `true`                                                                                                                                                                                                                 |
| `mongodb.version`                     | MongoDB server version for the replica set.                 | `"7.0.25"`                                                                                                                                                                                                             |
| `mongodb.replicas`                    | Number of data-bearing replica set members.                 | `3`                                                                                                                                                                                                                    |
| `mongodb.arbiters`                    | Number of arbiter nodes to deploy.                          | `0`                                                                                                                                                                                                                    |
| `mongodb.annotations`                 | Annotations for the `MongoDBCommunity` object.              | `{}`                                                                                                                                                                                                                   |
| `mongodb.labels`                      | Labels for the `MongoDBCommunity` object.                   | `{}`                                                                                                                                                                                                                   |
| `mongodb.resources.limits.cpu`        | CPU limit for the `mongod` container.                       | `"2"`                                                                                                                                                                                                                  |
| `mongodb.resources.limits.memory`     | Memory limit for the `mongod` container.                    | `"2Gi"`                                                                                                                                                                                                               |
| `mongodb.resources.requests.cpu`      | CPU request for the `mongod` container.                     | `"250m"`                                                                                                                                                                                                               |
| `mongodb.resources.requests.memory`   | Memory request for the `mongod` container.                  | `"1Gi"`                                                                                                                                                                                                               |
| `mongodb.agentResources.limits.cpu`   | CPU limit for the `mongodb-agent` container.                | `"500m"`                                                                                                                                                                                                                  |
| `mongodb.agentResources.limits.memory` | Memory limit for the `mongodb-agent` container.            | `"512Mi"`                                                                                                                                                                                                               |
| `mongodb.agentResources.requests.cpu` | CPU request for the `mongodb-agent` container.              | `"50m"`                                                                                                                                                                                                               |
| `mongodb.agentResources.requests.memory` | Memory request for the `mongodb-agent` container.        | `"128Mi"`                                                                                                                                                                                                               |
| `mongodb.initResources.limits.cpu`    | CPU limit for both operator-injected init containers.       | `"500m"`                                                                                                                                                                                                                  |
| `mongodb.initResources.limits.memory` | Memory limit for both operator-injected init containers.    | `"512Mi"`                                                                                                                                                                                                               |
| `mongodb.initResources.requests.cpu`  | CPU request for both operator-injected init containers.     | `"50m"`                                                                                                                                                                                                               |
| `mongodb.initResources.requests.memory` | Memory request for both operator-injected init containers. | `"128Mi"`                                                                                                                                                                                                              |
| `mongodb.persistence.storageClass`    | StorageClass to use for persistent volumes.                 | `""`                                                                                                                                                                                                                   |
| `mongodb.persistence.size.data`       | Persistent volume size for data storage.                    | `"10G"`                                                                                                                                                                                                                |
| `mongodb.persistence.size.logs`       | Persistent volume size for MongoDB logs.                    | `"2G"`                                                                                                                                                                                                                 |
| `mongodb.persistence.annotations`     | Annotations for the MongoDB volume claim templates.         | `{}`                                                                                                                                                                                                                   |
| `mongodb.persistence.labels`          | Labels for the MongoDB volume claim templates.              | `{}`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.create`       | Create a new service account for MongoDB workloads.         | `true`                                                                                                                                                                                                                 |
| `mongodb.serviceAccount.automount`    | Automount service account token.                            | `true`                                                                                                                                                                                                                 |
| `mongodb.serviceAccount.annotations`  | Annotations for service account.                            | `{}`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.labels`       | Labels for service account.                                 | `{}`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.nameOverride` | Override name of service account.                           | `""`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.role.create`  | Create a new role to bind to this service account.          | `true`                                                                                                                                                                                                                 |
| `mongodb.serviceAccount.role.annotations` | Annotations for the Role and RoleBinding.               | `{}`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.role.labels`  | Labels for the Role and RoleBinding.                        | `{}`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.role.rules`   | Rules for the new role to bind to this service account.     | <pre><code>rules:&#10;  - apiGroups: [ "" ]&#10;    resources: [ "secrets" ]&#10;    verbs: [ "get" ]&#10;  - apiGroups: [ "" ]&#10;    resources: [ "pods" ]&#10;    verbs: [ "get", "patch", "delete" ]</code></pre> |
