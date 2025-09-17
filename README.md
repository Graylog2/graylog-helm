# Graylog Helm
![Tests](https://github.com/graylog2/graylog-helm/actions/workflows/lint-and-test.yaml/badge.svg)

Official helm chart for Graylog.

## Not For External Use
This chart is still in development. We should not distribute this chart or any part of this repository externally until we've cleaned up the git history and recieved approval for external distribution.
This chart is still under development and does not have locked in api contracts yet.


## Table of Contents
* [Requirements](#requirements)
  * [Optional Dependencies](#optional-dependencies)
* [Installation](#installation)
* [Post-installation](#post-installation)
  * [Set root Graylog password](#set-root-graylog-password)
  * [Set external access](#set-external-access)
* [Usage](#usage)
  * [Scale Graylog](#scale-graylog)
  * [Scale DataNode](#scale-datanode)
  * [Scale MongoDB](#scale-mongodb)
  * [Modify Graylog `server.conf` parameters](#modify-graylog-serverconf-parameters)
  * [Customize deployed Kubernetes resources](#customize-deployed-kubernetes-resources)
  * [Add inputs](#add-inputs)
  * [Enable TLS](#enable-tls)
* [Using External Resources](#using-external-resources)
  * [Managing Secrets Externally](#managing-secrets-externally)
  * [Bring Your Own MongoDB](#bring-your-own-mongodb)
* [Uninstall](#uninstall)
  * [Removing everything](#removing-everything)
* [Debugging](#debugging)
* [Logging](#logging)
* [Graylog Helm Chart Values Reference](#graylog-helm-chart-values-reference)

# Requirements
- Kubernetes v1.32

## Optional Dependencies

This Helm chart is designed as a turnkey solution for quick demos and proofs of concept,
as well as streamlined production-grade setups through optional dependencies.
These dependencies are not bundled with the chart and must be installed separately.

> [!WARNING]
> We do not provide support for any of these optional dependencies.
> Please refer to their respective documentation for installation, usage, and troubleshooting.

### Ingress Controller

By default, the chart exposes a Kubernetes service.
However, we also recommend using an **Ingress Controller** for better management of external traffic.
If you set `ingress.enabled` to `true`, the chart will provision an Ingress resource for you.

You can use any ingress controller (e.g., NGINX, HAProxy), but make sure it's installed in your cluster beforehand.

### cert-manager

You can always [bring your own certificates](#bring-your-own-certificate-ingress-controller-recommended),
but using `cert-manager` can simplify TLS setup and certificate renewal considerably.

Make sure you have [Ingress Controller](#ingress-controller) installed, and that `ingress.enabled` is set to `true`.
Then, configure `ingress.tls` and `ingress.config.issuer` with the name of an existing Issuer resource,
and let `cert-manager` do the rest!

<!--
For convenience, this chart also provides an optional built-in feature to automatically create a Let's Encrypt issuer
for `cert-manager`. This feature is disabled by default, since issuers are typically managed directly by cluster
administrators. However, if you don't want to manage the issuer yourself, just set `managed.issuer=true` and
we'll provision one automatically for you.
-->
<!--
#### MongoDB Operator

By default, this chart includes the Bitnami MongoDB sub-chart for simplicity and ease of use as it provides a
zero-config, self-contained database setup. However, note that:

- Bitnami’s free MongoDB containers are being deprecated.
- The official MongoDB team recommends using the MongoDB Kubernetes Operator for production environments

Thus, our chart also works with the **MongoDB Operator**, via a custom resource template rendered when the mongo
subchart is disabled by setting `mongo.enabled = false`.

> [!IMPORTANT]
> The MongoDB operator must be installed and running in your cluster before disabling the subchart.

This decoupled approach provides greater flexibility, lifecycle control, and production-readiness.
-->

<!--
### Install
```sh
helm install graylog graylog/graylog -n graylog --create-namespace
```

### Upgrades
```sh
helm upgrade graylog graylog/graylog -n graylog --reuse-values
```
-->

# Installation

## Clone this repo
```sh
# clone repo
git clone git@github.com:Graylog2/graylog-helm.git

# cd into the newly created graylog-helm directory
cd graylog-helm
```

## Install local chart
```sh
helm install graylog ./graylog --namespace graylog --create-namespace
```

🏁 That's it!

# Post Installation

## Set Root Graylog Password
Graylog is installed with a simple password by default. This **MUST be changed** once all pods achieve the `RUNNING` state using 
the following command:

```sh
echo "Enter your new password and press return:" && read -s pass
helm upgrade graylog ./graylog --namespace graylog --reuse-values --set "graylog.config.rootPassword=$pass"; unset pass
```

## Set External Access

There are a number of ways to enable external access to the Graylog application. We recommend using an 
[Ingress Controller](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/) 
to provide external access both the Graylog UI and the Graylog API, as well as any configured inputs.

Once an Ingress Controller has been installed and configured, run the following command to provision the appropriate
[Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) resource:

```sh
helm upgrade graylog ./graylog -n graylog --set ingress.web.enabled="true" --reuse-values
```

### Alternative: LoadBalancer Service
Alternatively, external access can be configured directly through the provided service without the need for any 
pre-existing dependencies.

```sh
helm upgrade graylog ./graylog -n graylog --set graylog.custom.service.type="LoadBalancer" --reuse-values
```

### Temporary access: Port Forwarding
Finally, if you wish to enable external access _temporarily_, you can always use port forwarding:

```sh
kubectl port-forward service/graylog-svc 9000:9000 -n graylog
```

# Usage

## Scale Graylog
```sh
# scaling out: add more Graylog nodes to your cluster
helm upgrade graylog ./graylog -n graylog --set graylog.replicas=3 --reuse-values

# scaling in: remove Graylog nodes from your cluster
helm upgrade graylog ./graylog -n graylog --set graylog.replicas=1 --reuse-values
```

## Scale DataNode
```sh
# scaling out: add more Graylog Data Nodes to your cluster
helm upgrade graylog ./graylog -n graylog --set datanode.replicas=5 --reuse-values
```

## Scale MongoDB
```sh
# scaling out: add more MongoDB nodes to your replicaset
helm upgrade graylog ./graylog -n graylog --set mongodb.replicaCount=4 --reuse-values
```

## Modify Graylog `server.conf` parameters

```sh
# A few examples:

# change server tz
helm upgrade graylog ./graylog -n graylog --set graylog.config.timezone="America/Denver" --reuse-values

# set JVM options
helm upgrade graylog ./graylog -n graylog --set graylog.config.serverJavaOpts="-Xms2g -Xmx1g" --reuse-values

# redefine message journal maxAge
helm upgrade graylog ./graylog -n graylog --set graylog.config.messageJournal.maxAge="24h" --reuse-values

# enable CORS headers for HTTP interface
helm upgrade graylog ./graylog -n graylog --set graylog.config.network.enableCors=true --reuse-values

# enable email transport and set sender address
helm upgrade graylog ./graylog -n graylog --set graylog.config.email.enabled=true --set graylog.config.email.senderAddress="will@example.com" --reuse-values
```

## Customize deployed Kubernetes resources
```sh
# A few examples: 

# expose the Graylog application with a LoadBalancer service
helm upgrade graylog ./graylog -n graylog --set graylog.custom.service.type="LoadBalancer" --reuse-values

# modify readiness probe initial delay
helm upgrade graylog ./graylog -n graylog --set graylog.custom.readinessProbe.initialDelaySeconds=5 --reuse-values

# use a custom Storage Class for all resources (e.g. for AWS EKS)
helm upgrade graylog ./graylog -n graylog --set global.defaultStorageClass="gp2" --reuse-values
```

## Add inputs

First, define your inputs in a small YAML file like this one:

```yaml
graylog:
  inputs:
    - name: my-gelf-input
      port: 12201
      targetPort: 12201
      protocol: TCP
    - name: http1
      port: 8080
      targetPort: 8080
      protocol: TCP
```

Then, save it as `inputs.yaml`

Finally, upgrade your installation like so:
```sh
helm upgrade graylog ./graylog -n graylog -f inputs.yaml --reuse-values
```

The inputs should now be exposed. Make sure to complete their configuration through the Graylog UI.

## Enable TLS

Before you can enable TLS, you must associate a DNS name with your Graylog installation.
More specifically, your domain should point to the IP address/hostname associated the service used for [External Acess](#set-external-access).
You may retrieve this information like this:

```sh
kubectl get svc $SERVICE_NAME -n graylog
# look for the EXTERNAL-IP field
```

With `SERVICE_NAME` being equal to the name of the service exposed by your ingress controller, if you're using one, or
`graylog-svc` otherwise.

Depending on your setup, TLS can be enabled in three different ways:

### Option 1: Bring Your Own Certificate with Ingress Controller (recommended)

If you already have a TLS certificate-key pair, you can create a Kubernetes secret to store them:
```sh
kubectl create secret tls my-cert --cert=public.pem --key=private.key -n graylog
```

Enable TLS termination at the Ingress entrypoint for your Graylog installation, by referencing the Kubernetes secret:

```yaml
# ingress-with-tls.yaml
ingress:
  web:
    enabled: true
    hosts:
      - host: graylog.hostname.example  # must match the one under 'tls'
        paths:
          - path: /
            pathType: ImplementationSpecific
    tls:
      - secretName: my-cert             # <--- reference your secret name here!
        hosts:
          - graylog.hostname.example    # must match the one under 'hosts'
```

```sh
helm upgrade graylog ./graylog -n graylog --reuse-values -f ingress-with-tls.yaml
```

### Option 2: Auto-issued certificates using cert-manager

> [!NOTE]
> An Issuer or ClusterIssuer resource is required for cert-manager to issue TLS certificates automatically.
> Please refer to [cert-manager docs](https://cert-manager.io/docs/) for instructions.

> [!NOTE]
> TLS certificates issued by cert-manager are to be used in conjunction with Ingress.
> Please make sure you already have an Ingress Controller running in your cluster before proceeding.

This option allows you to enable TLS for your Graylog installation from well known CAs,
without having to provision a TLS certificate yourself.

```yaml
# ingress-with-tls.yaml
ingress:
  web:
    enabled: true
    hosts:
      - host: graylog.hostname.example  # must match the one under 'tls'
        paths:
          - path: /
            pathType: ImplementationSpecific
    tls:
      - secretName: my-autoissued-cert  # cert-manager will mount the TLS certificate issued as a secret with this name
        hosts:
          - graylog.hostname.example    # this will end up in the certificate subjectAltName. Must match the one under 'hosts'
```

```sh
helm upgrade graylog ./graylog -n graylog --reuse-values -f ingress-with-tls.yaml --set ingress.config.tls.issuer.existingName='<name of your existing issuer resource>'
```

### Option 3: Bring Your Own Certificate with Graylog Native TLS

> [!IMPORTANT]
> Native TLS requires one additional SAN in your certificate: `DNS:*.graylog-svc.graylog.svc.cluster.local`
> Please, make sure your certificate includes this SAN. Otherwise, please reissue the certificate including the additional SAN.
> If your CA won't (re)issue a certificate with this SAN, please consider TLS termination at the [Ingress Controller](#ingress-controller) as an alternative.

If you already have a TLS certificate-key pair, you can create a Kubernetes secret to store them:
```sh
kubectl create secret tls my-cert --cert=public.pem --key=private.key -n graylog
```

Enable TLS for your Graylog nodes, referencing the Kubernetes secret:
```sh
helm upgrade graylog ./graylog -n graylog --reuse-values --set graylog.config.tls.enabled=true --set  graylog.config.tls.secretName="my-cert" --set graylog.config.tls.updateKeyStore=true
```
The default set of trusted Certificate Authorities bundled in the Java Runtime for Java 17 is aligned with major,
well-known public root CAs. Make sure to set `graylog.config.tls.updateKeyStore` to `true` if you are using a
self-signed certificate, or if you think the CA that signed your certificate might not be among this default set.

## Enable Geolocation
```sh
helm upgrade graylog ./graylog -n graylog --reuse-values --set graylog.config.geolocation.enabled=true --set graylog.config.geolocation.maxmindGeoIp.enabled=true --set graylog.config.geolocation.maxmindGeoIp.accountId="<YOUR-MAXMIND-ACCOUNT-ID-HERE>" --set graylog.config.geolocation.maxmindGeoIp.licenseKey="<YOUR-MAXMIND-LICENSE-KEY-HERE>"
```

Use the following paths when enabling the Geo-location processor in the Graylog web UI:

- Path to the city database: `/usr/share/graylog/data/geolocation/GeoLite2-City.mmdb`
- Path to the ASN database: `/usr/share/graylog/data/geolocation/GeoLite2-ASN.mmdb`

# Using External Resources

## Managing Secrets Externally

By default, this chart manages application secrets (including MongoDB credentials) through Helm.
If you already manage secrets using an external system, you can disable Helm-managed secrets and point the chart to your existing resources.

```sh
helm upgrade -i graylog ./graylog -n graylog --reuse-values --set global.existingSecretName="<your secret name>"
```

> [!IMPORTANT]
> As a result of setting a global secret override, all Graylog and Mongo secrets are assumed to be managed externally.
> Accordingly, any of the following configuration values will be ignored:
> - `graylog.config.rootPassword`
> - `graylog.config.rootUsername`
> - `graylog.config.secretPepper`
> - `graylog.config.tls.keyPassword`

## Bring Your Own MongoDB

By default, this chart deploys a MongoDB replicaset using [the Bitnami MongoDB chart](https://artifacthub.io/packages/helm/bitnami/mongodb) as a dependency.
If you prefer to use your own MongoDB instance, you can disable the bundled MongoDB and configure the chart to connect to your external database:

```sh
helm upgrade --install graylog ./graylog --namespace graylog --reuse-values \
  --set mongodb.subchart.enabled=false \
  --set graylog.config.mongodb.customUri="mongodb[+srv]://<username>:<password>@<hostname>:<port>[,<i-th hostname>:<i-th port>]/<db name>"
```

**Alternatively**, the MongoDB URI can also be provided as part of an externally-managed secret:

```sh
helm upgrade --install graylog ./graylog --namespace graylog --reuse-values \
  --set mongodb.subchart.enabled=false \
  --set global.existingSecretName="<your secret name>"
```

# Uninstall
```sh
# optional: scale Graylog down to zero
kubectl scale sts graylog -n graylog --replicas 0  && kubectl wait --for=delete pod graylog-0 -n graylog

# remove chart
helm uninstall graylog -n graylog
```

## Removing Everything
```sh
# CAUTION: this will delete ALL your data!
kubectl delete $(kubectl get pvc -o name -n graylog; kubectl get secret -o name -n graylog) -n graylog
```

# Debugging
Get a YAML output of the values being submitted.
```bash
helm template graylog graylog -f graylog/values-glc.yaml | yq
```

# Logging
```
# Graylog app logs
stern statefulset/graylog-app -n graylog-helm-dev-1
# DataNode logs
stern statefulset/graylog-datanode -n graylog-helm-dev-1
```

---

# Graylog Helm Chart Values Reference
| Key Path           | Description                                           | Default   |
| ------------------ |-------------------------------------------------------| --------- |
| `nameOverride`     | Override the `app.kubernetes.io/name` label value.    | `""`      |
| `fullnameOverride` | Override the fully qualified name of the application. | `""`      |

## Global
These values affect Graylog, DataNode, and MongoDB

| Key Path                     | Description                                 | Default |
|------------------------------|---------------------------------------------|---------|
| `global.existingSecretName`  | Reference to an existing Kubernetes secret. | `""`    |
| `global.imagePullSecrets`    | Image pull secrets for private registries.  | `[]`    |
| `global.defaultStorageClass` | Default storage class for PVCs.             | `""`    |


## Graylog application
| Key Path                                                              | Description                                                | Default                         |
|-----------------------------------------------------------------------|------------------------------------------------------------|---------------------------------|
| `graylog.enabled`                                                     | Enable the Graylog server.                                 | `true`                          |
| `graylog.enterprise`                                                  | Enable enterprise features.                                | `true`                          |
| `graylog.replicas`                                                    | Number of Graylog server replicas.                         | `2`                             |
| `graylog.inputs`                                                      | List of inputs to configure.                               | See below                       |
| `graylog.plugins`                                                     | List of plugins to configure.                              | See below                       |
| `graylog.config.rootUsername`                                         | Root admin username.                                       | `"admin"`                       |
| `graylog.config.rootPassword`                                         | Root admin password.                                       | `""`                            |
| `graylog.config.timezone`                                             | Timezone for the Graylog server.                           | `"UTC"`                         |
| `graylog.config.selfSignedStartup`                                    | Use self-signed certs on startup.                          | `"true"`                        |
| `graylog.config.serverJavaOpts`                                       | Java options for server.                                   | `"-Xms1g -Xmx1g"`               |
| `graylog.config.leaderElectionMode`                                   | Mode for leader election.                                  | `"automatic"`                   |
| `graylog.config.contentPacksAutoInstall`                              | Auto-install content packs.                                | `"true"`                        |
| `graylog.config.isCloud`                                              | Indicates if deployment is on cloud.                       | `"false"`                       |
| `graylog.config.mongodb.maxConnections`                               | Max MongoDB connections.                                   | `"1000"`                        |
| `graylog.config.mongodb.versionProbeAttempts`                         | MongoDB version probe attempts.                            | `"0"`                           |
| `graylog.config.messageJournal.enabled`                               | Enable message journal.                                    | `"true"`                        |
| `graylog.config.messageJournal.flushAge`                              | Journal flush age.                                         | `"1m"`                          |
| `graylog.config.messageJournal.flushInterval`                         | Journal flush interval.                                    | `"1000000"`                     |
| `graylog.config.messageJournal.maxAge`                                | Max journal age.                                           | `"12h"`                         |
| `graylog.config.messageJournal.segmentAge`                            | Journal segment age.                                       | `"1h"`                          |
| `graylog.config.messageJournal.segmentSize`                           | Journal segment size.                                      | `"100mb"`                       |
| `graylog.config.network.connectTimeout`                               | Network connect timeout.                                   | `"5s"`                          |
| `graylog.config.network.enableCors`                                   | Enable CORS.                                               | `"false"`                       |
| `graylog.config.network.enableGzip`                                   | Enable Gzip compression.                                   | `"true"`                        |
| `graylog.config.network.maxHeaderSize`                                | Max header size.                                           | `"8192"`                        |
| `graylog.config.network.readTimeout`                                  | Network read timeout.                                      | `"10s"`                         |
| `graylog.config.network.threadPoolSize`                               | Network thread pool size.                                  | `"64"`                          |
| `graylog.config.performance.asyncEventbusProcessors`                  | Async event bus processors.                                | `"2"`                           |
| `graylog.config.performance.autoRestartInputs`                        | Automatically restart inputs.                              | `"false"`                       |
| `graylog.config.performance.inputBufferProcessors`                    | Input buffer processors.                                   | `"2"`                           |
| `graylog.config.performance.inputBufferRingSize`                      | Input buffer ring size.                                    | `"65536"`                       |
| `graylog.config.performance.inputBufferWaitStrategy`                  | Input buffer wait strategy.                                | `"blocking"`                    |
| `graylog.config.performance.jobSchedulerConcurrencyLimits`            | Scheduler concurrency limits.                              | `""`                            |
| `graylog.config.performance.outputBatchSize`                          | Output batch size.                                         | `"500"`                         |
| `graylog.config.performance.outputFaultCountThreshold`                | Output fault threshold.                                    | `"5"`                           |
| `graylog.config.performance.outputFaultPenaltySeconds`                | Output fault penalty seconds.                              | `"30"`                          |
| `graylog.config.performance.outputFlushInterval`                      | Output flush interval.                                     | `"1"`                           |
| `graylog.config.performance.outputBufferProcessorThreadsCorePoolSize` | Output processor thread pool size.                         | `"3"`                           |
| `graylog.config.performance.outputBufferProcessors`                   | Output buffer processors.                                  | `""`                            |
| `graylog.config.performance.processBufferProcessors`                  | Process buffer processors.                                 | `""`                            |
| `graylog.config.email.enabled`                                        | Enable email notifications.                                | `"false"`                       |
| `graylog.config.email.senderAddress`                                  | Email sender address.                                      | `"graylog@example.com"`         |
| `graylog.config.email.hostname`                                       | SMTP hostname.                                             | `"mail.example.com"`            |
| `graylog.config.email.port`                                           | SMTP port.                                                 | `"587"`                         |
| `graylog.config.email.socketConnectionTimeout`                        | SMTP socket connect timeout.                               | `"10s"`                         |
| `graylog.config.email.socketTimeout`                                  | SMTP socket timeout.                                       | `"10s"`                         |
| `graylog.config.email.useAuth`                                        | Use SMTP authentication.                                   | `"true"`                        |
| `graylog.config.email.useSsl`                                         | Use SSL for SMTP.                                          | `"false"`                       |
| `graylog.config.email.useTls`                                         | Use TLS for SMTP.                                          | `"true"`                        |
| `graylog.config.email.webInterfaceUrl`                                | Web interface URL for email links.                         | `"https://graylog.example.com"` |
| `graylog.config.plugins.enabled`                                      | Enable Graylog plugin system.                              | `"false"`                       |
| `graylog.geoloction.enabled`                                          | Enable the Geolocation Processor                           | `false`                         |
| `graylog.geoloction.maxmindGeoIp.enabled`                             | Enable the MaxMind GeoIP update CronJob                    | `true`                          |
| `graylog.geoloction.maxmindGeoIp.accountId`                           | MaxMind Account ID                                         |                                 |
| `graylog.geoloction.maxmindGeoIp.licenseKey`                          | MaxMind License Key                                        |                                 |
| `graylog.geoloction.maxmindGeoIp.cronSchedule`                        | Cron schedule expression                                   | `"0 0 * * *"`                   |    
| `graylog.geoloction.maxmindGeoIp.postInstallRun`                      | Enable post-installation helm hook Job                     | `true`                          |
| `graylog.geoloction.mmdbSources.city.url`                             | GeoLite2-City.mmdb URL (only for initial asset fetch)      |                                 |         
| `graylog.geoloction.mmdbSources.city.checksum`                        | GeoLite2-City.mmdb checksum (only for initial asset fetch) |                                 |         
| `graylog.geoloction.mmdbSources.asn.url`                              | GeoLite2-ASN.mmdb URL (only for initial asset fetch)       |                                 |         
| `graylog.geoloction.mmdbSources.asn.checksum`                         | GeoLite2-ASN.mmdb checksum (only for initial asset fetch)  |                                 |
| `graylog.config.init.assetFetch.enabled`                              | Enable asset fetch init.                                   | `"false"`                       |
| `graylog.config.init.assetFetch.skipChecksum`                         | Skip checksum validation for assets.                       | `"false"`                       |
| `graylog.config.init.assetFetch.allowHttp`                            | Allow HTTP fetch for assets.                               | `"false"`                       |
| `graylog.config.init.assetFetch.plugins.enabled`                      | Enable plugin asset fetch.                                 | `"false"`                       |
| `graylog.config.init.assetFetch.plugins.baseUrl`                      | Base URL for plugin assets.                                | `""`                            |
| `graylog.config.init.geolocation.enabled`                             | Enable geolocation asset fetch.                            | `"false"`                       |
| `graylog.config.init.geolocation.baseUrl`                             | Base URL for geolocation assets.                           | `""`                            |
| `graylog.custom.podAnnotations`                                       | Additional pod annotations.                                | `{}`                            |
| `graylog.custom.nodeSelector`                                         | Node selector for scheduling.                              | `{}`                            |
| `graylog.custom.env`                                                  | Custom environment variables                               | `[]`                            |
| `graylog.custom.extraEnv`                                             | Custom EnvVar environment variables                        | `[]`                            |
| `graylog.custom.inputs.enabled`                                       | Enable Graylog inputs.                                     | `true`                          |
| `graylog.custom.metrics.enabled`                                      | Enable metrics collection.                                 | `true`                          |
| `graylog.custom.image.repository`                                     | Image repository for Graylog.                              | `""`                            |
| `graylog.custom.image.tag`                                            | Image tag for Graylog.                                     | `""`                            |
| `graylog.custom.image.imagePullPolicy`                                | Pull policy for Graylog image.                             | `IfNotPresent`                  |
| `graylog.custom.image.imagePullSecrets`                               | Pull secrets for image.                                    | `[]`                            |
| `graylog.custom.updateStrategy.type`                                  | Pod update strategy for StatefulSet.                       | `"RollingUpdate"`               |
| `graylog.custom.updateStrategy.rollingUpdate.maxUnavailable`          | Max unavailable pods during an update.                     | `1`                             |
| `graylog.custom.updateStrategy.rollingUpdate.partition`               | Pods that will remain unaffected by the update.            | `""`                            |
| `graylog.custom.service.nameOverride`                                 | Override for service name.                                 | `""`                            |
| `graylog.custom.service.type`                                         | Kubernetes service type.                                   | `ClusterIP`                     |
| `graylog.custom.service.ports.app`                                    | Graylog web UI port.                                       | `9000`                          |
| `graylog.custom.service.ports.metrics`                                | Metrics endpoint port.                                     | `9833`                          |

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
| Key Path                | Descriptions                                                                                                                                                                                   | Example                                                                                                                                                          |
|-------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `graylog.custom.env`    | Simple key/value environment variables                                                                                                                                                         | `["FOO=BAR", "HELLO=123"]`                                                                                                                                       |
| `graylog.custom.EnvVar` | [EnvVar spec](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#environment-variables)-compliant environment variables<br/>(valueFrom, configMaps, secrets, etc.) | <pre><code>extraEnv:<br/>  - name: MADE_UP_PASSWORD<br/>    valueFrom:<br/>      secretKeyRef:<br/>        name: mysecret<br/>        key: password</code></pre> |

## Datanode
| Key Path                                                      | Description                                     | Default           |
|---------------------------------------------------------------|-------------------------------------------------|-------------------|
| `datanode.enabled`                                            | Enable Graylog datanode.                        | `true`            |
| `datanode.replicas`                                           | Number of datanode replicas.                    | `3`               |
| `datanode.config.nodeIdFile`                                  | Path to datanode ID file.                       | `""`              |
| `datanode.config.opensearchHeap`                              | OpenSearch heap size.                           | `"2g"`            |
| `datanode.config.javaOpts`                                    | Java options for datanode.                      | `"-Xms1g -Xmx1g"` |
| `datanode.config.skipPreflightChecks`                         | Skip startup checks.                            | `"false"`         |
| `datanode.config.nodeSearchCacheSize`                         | Size of search cache.                           | `"10gb"`          |
| `datanode.custom.podAnnotations`                              | Additional pod annotations.                     | `{}`              |
| `datanode.custom.nodeSelector`                                | Node selector for datanode.                     | `{}`              |
| `datanode.custom.image.repository`                            | Datanode image repository.                      | `""`              |
| `datanode.custom.image.tag`                                   | Datanode image tag.                             | `""`              |
| `datanode.custom.image.imagePullPolicy`                       | Image pull policy.                              | `IfNotPresent`    |
| `datanode.custom.image.imagePullSecrets`                      | Image pull secrets.                             | `[]`              |
| `datanode.custom.updateStrategy.type`                         | Pod update strategy for StatefulSet.            | `"RollingUpdate"` |
| `datanode.custom.updateStrategy.rollingUpdate.maxUnavailable` | Max unavailable pods during an update.          | `1`               |
| `datanode.custom.updateStrategy.rollingUpdate.partition`      | Pods that will remain unaffected by the update. | `""`              |
| `datanode.custom.service.ports.api`                           | API communication port.                         | `8999`            |
| `datanode.custom.service.ports.data`                          | Data communication port.                        | `9200`            |
| `datanode.custom.service.ports.config`                        | Configuration communication port.               | `9300`            |


## Service Account
| Key Path                      | Description                       | Default |
| ----------------------------- | --------------------------------- | ------- |
| `serviceAccount.create`       | Create a new service account.     | `true`  |
| `serviceAccount.automount`    | Automount service account token.  | `true`  |
| `serviceAccount.annotations`  | Annotations for service account.  | `{}`    |
| `serviceAccount.nameOverride` | Override name of service account. | `""`    |


## Ingress

### Web Ingress
| Key Path                                 | Description                        | Default                  |
|------------------------------------------|------------------------------------| ------------------------ |
| `ingress.web.enabled`                    | Enable ingress for Graylog Web.    | `false`                  |
| `ingress.web.className`                  | Ingress class name.                | `""`                     |
| `ingress.web.annotations`                | Annotations for ingress resource.  | `{}`                     |
| `ingress.web.hosts[0].host`              | Hostname for ingress.              | `chart-example.local`    |
| `ingress.web.hosts[0].paths[0].path`     | Path for routing.                  | `/`                      |
| `ingress.web.hosts[0].paths[0].pathType` | Path matching type.                | `ImplementationSpecific` |
| `ingress.web.tls`                        | TLS configuration.                 | `[]`                     |

### Forwarder Ingress
| Key Path                                       | Description                           | Default                  |
|------------------------------------------------|---------------------------------------|--------------------------|
| `ingress.forwarder.enabled`                    | Enable ingress for Graylog Forwarder. | `false`                  |
| `ingress.forwarder.className`                  | Ingress class name.                   | `""`                     |
| `ingress.forwarder.annotations`                | Annotations for ingress resource.     | `{}`                     |
| `ingress.forwarder.hosts[0].host`              | Hostname for ingress.                 | `chart-example.local`    |
| `ingress.forwarder.hosts[0].paths[0].path`     | Path for routing.                     | `/`                      |
| `ingress.forwarder.hosts[0].paths[0].pathType` | Path matching type.                   | `ImplementationSpecific` |
| `ingress.forwarder.tls`                        | TLS configuration.                    | `[]`                     |
