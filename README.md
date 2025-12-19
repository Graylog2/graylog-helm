# Graylog Helm
![Tests](https://github.com/graylog2/graylog-helm/actions/workflows/lint-and-test.yaml/badge.svg)

Official Helm chart for Graylog.

## Table of Contents
* [Requirements](#requirements)
  * [External Dependencies](#external-dependencies)
* [Installation](#installation)
  * [Installing on Kubernetes](#installing-on-kubernetes) 
  * [Installing on AWS EKS](#installing-on-aws-eks)
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
- Kubernetes **v1.32+**
- Helm **v3.0+**
- MongoDB Controllers for Kubernetes Operator **v1.6.1** (required unless a [user-provided MongoDB](#bring-your-own-mongodb) is supplied)

## External Dependencies

This Helm chart is designed as a turnkey solution for quick demos and proofs of concept,
as well as streamlined production-grade setups through external dependencies.
These dependencies are not bundled with the chart and must be installed separately.

> [!WARNING]
> We do not provide support for any of these optional dependencies.
> Please refer to their respective documentation for installation, usage, and troubleshooting.

### MongoDB Operator

The official [MongoDB Controllers for Kubernetes (MCK) Operator](https://www.mongodb.com/docs/kubernetes/current/)
is the recommended method for provisioning the MongoDB replica sets required for running Graylog in production. 
This decoupled approach provides greater flexibility, improved lifecycle management, operational consistency, and 
overall production readiness.

You may also choose to [bring your own MongoDB](#bring-your-own-mongodb), but for ease of deployment as well as
improved reliability the MCK Operator remains the preferred way to deploy MongoDB and is therefore enabled by default.

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

## Installing on Kubernetes

### Clone this repo
```sh
# clone repo
git clone git@github.com:Graylog2/graylog-helm.git

# cd into the newly created graylog-helm directory
cd graylog-helm
```

### Install the official MongoDB Kubernetes Operator using Helm
```sh
helm upgrade --install mongodb-kubernetes-operator mongodb-kubernetes \
  --repo https://mongodb.github.io/helm-charts --version "1.6.1" \
  --set operator.watchNamespace="*" --reuse-values \
  --namespace operators --create-namespace
```

### Install the official Graylog Helm chart
```sh
helm install graylog ./graylog --namespace graylog --create-namespace
```

That's it!

## Installing on AWS EKS

When installing this chart on an existing Amazon Elastic Kubernetes Service (EKS) cluster on AWS, you must enable the
[Amazon EBS CSI Driver add-on](https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html#adding-ebs-csi-eks-add-on)
in your cluster to provision persistent volumes. The Amazon EBS CSI plugin requires Identity and Access Management (IAM) 
permissions to make calls to AWS APIs on your behalf, so be sure to
[create the corresponding IAM role](https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html), or attach the
`AmazonEBSCSIDriverPolicy` to your existing role.

### Clone this repo
```sh
# clone repo
git clone git@github.com:Graylog2/graylog-helm.git

# cd into the newly created graylog-helm directory
cd graylog-helm
```

### Install the official MongoDB Kubernetes Operator using Helm
```sh
helm upgrade --install mongodb-kubernetes-operator mongodb-kubernetes \
  --repo https://mongodb.github.io/helm-charts --version "1.6.1" \
  --set operator.watchNamespace="*" --reuse-values \
  --namespace operators --create-namespace
```

When deploying to Amazon EKS, use the `--set provider=aws` option to enable AWS-specific configurations:

```sh
helm install graylog ./graylog --namespace graylog --create-namespace --set provider=aws
```

When this option is set, the chart configures a custom `gp3` StorageClass optimized for Amazon EBS volumes, 
and applies it to all PVCs managed by this chart.

Alternatively, you may also specify another existing StorageClass (e.g., `gp2`), if available in your cluster:

```sh
helm install graylog ./graylog --namespace graylog --create-namespace --set provider=aws --set global.storageClass=gp2
```

> [!NOTE]
> For EKS clusters version 1.30 and later, Amazon EKS no longer includes the "default" annotation on the `gp2` 
> StorageClass resource for newly created clusters. It may still be present in the cluster, but it's not marked as 
> the default storage class anymore.
> 
> The `gp3` volume type is recommended for most Amazon EBS workloads because it offers better performance and 
> cost efficiency than `gp2`, as well as independent scaling of IOPS and throughput, and higher performance limits.

# Post-Installation

## Set root Graylog password
Graylog is installed with a random password by default. We recommend setting a persistent password once all pods achieve the `RUNNING` state using 
the following command:

```sh
echo "Enter your new password and press return:" && read -s pass
helm upgrade graylog ./graylog --namespace graylog --reuse-values --set "graylog.config.rootPassword=$pass"; unset pass
```

## Set external access

There are a number of ways to enable external access to the Graylog application. We recommend using an 
[Ingress Controller](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/) 
to provide external access both to the Graylog UI and the Graylog API, as well as any configured inputs.

Once an Ingress Controller has been installed and configured, run the following command to provision the appropriate
[Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) resource:

```sh
helm upgrade graylog ./graylog -n graylog --set ingress.web.enabled="true" --reuse-values
```

### Alternative: LoadBalancer Service
Alternatively, external access can be configured directly through the provided service without the need for any 
pre-existing dependencies.

```sh
helm upgrade graylog ./graylog -n graylog --set graylog.service.type="LoadBalancer" --reuse-values
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
# scaling out: add more MongoDB nodes to your replica set
helm upgrade graylog ./graylog -n graylog --set mongodb.replicas=4 --reuse-values
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
helm upgrade graylog ./graylog -n graylog --set graylog.service.type="LoadBalancer" --reuse-values

# modify readiness probe initial delay
helm upgrade graylog ./graylog -n graylog --set graylog.readinessProbe.initialDelaySeconds=5 --reuse-values

# use a custom Storage Class for all resources (e.g. for AWS EKS)
helm upgrade graylog ./graylog -n graylog --set global.storageClass="gp2" --reuse-values
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
More specifically, your domain should point to the IP address/hostname associated with the service used for [External Access](#set-external-access).
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
  enabled: true
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
> TLS certificates issued by cert-manager are to be used in conjunction with Ingress.
> Please make sure you already have an Ingress Controller running in your cluster before proceeding.

This option allows you to enable TLS for your Graylog installation from well-known CAs,
without having to provision a TLS certificate yourself.

```yaml
# ingress-with-tls.yaml
ingress:
  enabled: true
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

> [!NOTE]
> An Issuer or ClusterIssuer resource is required for cert-manager to issue TLS certificates automatically.
> Please refer to [cert-manager docs](https://cert-manager.io/docs/) for instructions.

For convenience, this chart includes an optional built-in feature to automatically create a Let's Encrypt `Issuer` 
resource for `cert-manager`. Since issuers are typically managed by cluster administrators, this is disabled by default. 
If you prefer the Graylog chart to handle this specific issuer creation, you may enable it by setting 
`ingress.config.tls.issuer.managed.enabled=true`.

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
helm upgrade graylog ./graylog -n graylog --reuse-values --set graylog.config.tls.enabled=true --set graylog.config.tls.secretName="my-cert" --set graylog.config.tls.updateKeyStore=true
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
> - `graylog.config.customSecretPepper`
> - `graylog.config.tls.keyPassword`

## Bring Your Own MongoDB

By default, this chart deploys a MongoDB replica set using a custom resource template, which is rendered when 
`mongodb.communityResource.enabled` is set to `true` (the default setting). The
[MongoDB Controllers for Kubernetes Operator](https://github.com/mongodb/mongodb-kubernetes) then manages the
corresponding pods.

If you prefer to use your own MongoDB instance, you can disable the custom MongoDB resource and configure the chart to
connect to your external database:
```sh
helm upgrade --install graylog ./graylog --namespace graylog --reuse-values \
  --set mongodb.communityResource.enabled=false \
  --set graylog.config.mongodb.customUri="mongodb[+srv]://<username>:<password>@<hostname>:<port>[,<i-th hostname>:<i-th port>]/<db name>"
```

**Alternatively**, the MongoDB URI can also be provided as part of an externally-managed secret:

```sh
helm upgrade --install graylog ./graylog --namespace graylog --reuse-values \
  --set mongodb.communityResource.enabled=false \
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
kubectl delete pvc,secret -n graylog --all
```

# Debugging
Get a YAML output of the values being submitted.
```bash
helm template graylog graylog -f your-custom-values.yaml | yq
```

# Logging
```sh
# Graylog app logs
stern statefulset/graylog-app -n graylog
# DataNode logs
stern statefulset/graylog-datanode -n graylog
```

---

# Graylog Helm Chart Values Reference
| Key Path           | Description                                                      | Default |
|--------------------|------------------------------------------------------------------|---------|
| `provider`         | Kubernetes provider (optional).                                  | `""`    |
| `version`          | Override Graylog and Graylog Data Node version (optional).       | `""`    |
| `nameOverride`     | Override the `app.kubernetes.io/name` label value (optional).    | `""`    |
| `fullnameOverride` | Override the fully qualified name of the application (optional). | `""`    |

## Global
These values affect Graylog, DataNode, and MongoDB.

| Key Path                    | Description                                 | Default |
|-----------------------------|---------------------------------------------|---------|
| `global.existingSecretName` | Reference to an existing Kubernetes secret. | `""`    |
| `global.imagePullSecrets`   | Image pull secrets for private registries.  | `[]`    |
| `global.storageClass`       | Storage class to use for PVCs.              | `""`    |


## Graylog application
| Key Path                                                              | Description                                                 | Default                         |
|-----------------------------------------------------------------------|-------------------------------------------------------------|---------------------------------|
| `graylog.enabled`                                                     | Enable the Graylog server.                                  | `true`                          |
| `graylog.enterprise`                                                  | Enable enterprise features.                                 | `true`                          |
| `graylog.replicas`                                                    | Number of Graylog server replicas.                          | `2`                             |
| `graylog.service.nameOverride`                                        | Override for service name.                                  | `""`                            |
| `graylog.service.type`                                                | Kubernetes service type.                                    | `ClusterIP`                     |
| `graylog.service.ports.app`                                           | Graylog web UI port.                                        | `9000`                          |
| `graylog.service.ports.metrics`                                       | Metrics endpoint port.                                      | `9833`                          |
| `graylog.service.metrics.enabled`                                     | Enable metrics collection.                                  | `true`                          |
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
| `graylog.config.messageJournal.enabled`                               | Enable message journal.                                     | `"true"`                        |
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
| `graylog.config.network.externalUri`                                  | External URI for Graylog web interface.                     | `""`                            |
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
| `graylog.config.geolocation.enabled`                                  | Enable the Geolocation Processor.                           | `false`                         |
| `graylog.config.geolocation.maxmindGeoIp.enabled`                     | Enable the MaxMind GeoIP update CronJob.                    | `true`                          |
| `graylog.config.geolocation.maxmindGeoIp.accountId`                   | MaxMind Account ID.                                         |                                 |
| `graylog.config.geolocation.maxmindGeoIp.licenseKey`                  | MaxMind License Key.                                        |                                 |
| `graylog.config.geolocation.maxmindGeoIp.cronSchedule`                | Cron schedule expression.                                   | `"0 0 * * *"`                   |
| `graylog.config.geolocation.maxmindGeoIp.postInstallRun`              | Enable post-installation helm hook Job.                     | `true`                          |
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
| `graylog.updateStrategy.rollingUpdate.maxUnavailable`                 | Max unavailable pods during an update.                      | `1`                             |
| `graylog.updateStrategy.rollingUpdate.partition`                      | Pods that will remain unaffected by the update.             | `""`                            |
| `graylog.resources.limits.cpu`                                        | CPU limit for the Graylog pod.                              | `"2"`                           |
| `graylog.resources.limits.memory`                                     | Memory limit for the Graylog pod.                           | `"2Gi"`                         |
| `graylog.resources.requests.cpu`                                      | CPU request for the Graylog pod.                            | `"1"`                           |
| `graylog.resources.requests.memory`                                   | Memory request for the Graylog pod.                         | `"1Gi"`                         |
| `graylog.persistence.enabled`                                         | Enable persistent storage.                                  | `true`                          |
| `graylog.persistence.storageClass`                                    | Storage class for the persistent volume.                    | `""`                            |
| `graylog.persistence.volumeNameOverride`                              | Override name of the persistent volume.                     | `""`                            |
| `graylog.persistence.existingClaim`                                   | Use an existing PVC.                                        | `""`                            |
| `graylog.persistence.mountPath`                                       | Path where volume will be mounted.                          | `""`                            |
| `graylog.persistence.accessModes`                                     | Access modes for the persistent volume.                     | `[]`                            |
| `graylog.persistence.size`                                            | Size of the persistent volume.                              | `""`                            |
| `graylog.persistence.annotations`                                     | Annotations for the persistent volume claim.                | `{}`                            |
| `graylog.persistence.labels`                                          | Labels for the persistent volume claim.                     | `{}`                            |
| `graylog.persistence.selector`                                        | Selector for the persistent volume.                         | `{}`                            |
| `graylog.livenessProbe.enabled`                                       | Enable liveness probe.                                      | `true`                          |
| `graylog.livenessProbe.initialDelaySeconds`                           | Initial delay for liveness probe.                           | `60`                            |
| `graylog.livenessProbe.periodSeconds`                                 | Period between liveness probe checks.                       | `10`                            |
| `graylog.livenessProbe.timeoutSeconds`                                | Timeout for the liveness probe.                             | `5`                             |
| `graylog.livenessProbe.failureThreshold`                              | Failure threshold for the liveness probe.                   | `6`                             |
| `graylog.livenessProbe.successThreshold`                              | Success threshold for the liveness probe.                   | `1`                             |
| `graylog.readinessProbe.enabled`                                      | Enable readiness probe.                                     | `true`                          |
| `graylog.readinessProbe.initialDelaySeconds`                          | Initial delay for readiness probe.                          | `30`                            |
| `graylog.readinessProbe.periodSeconds`                                | Period between readiness probe checks.                      | `10`                            |
| `graylog.readinessProbe.timeoutSeconds`                               | Timeout for the readiness probe.                            | `5`                             |
| `graylog.readinessProbe.failureThreshold`                             | Failure threshold for the readiness probe.                  | `6`                             |
| `graylog.readinessProbe.successThreshold`                             | Success threshold for the readiness probe.                  | `1`                             |
| `graylog.podDisruptionBudget.enabled`                                 | Enable PodDisruptionBudget.                                 | `false`                         |
| `graylog.podDisruptionBudget.minAvailable`                            | Minimum available pods during disruption.                   | `1`                             |
| `graylog.podAnnotations`                                              | Additional pod annotations.                                 | `{}`                            |
| `graylog.nodeSelector`                                                | Node selector for scheduling.                               | `{}`                            |
| `graylog.tolerations`                                                 | Tolerations for scheduling.                                 | `[]`                            |
| `graylog.affinity`                                                    | Affinity rules for scheduling.                              | `{}`                            |
| `graylog.extraEnv`                                                    | Custom EnvVar environment variables.                        | `[]`                            |


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

## Datanode
| Key Path                                               | Description                                     | Default           |
|--------------------------------------------------------|-------------------------------------------------|-------------------|
| `datanode.enabled`                                     | Enable Graylog datanode.                        | `true`            |
| `datanode.replicas`                                    | Number of datanode replicas.                    | `3`               |
| `datanode.service.ports.api`                           | API communication port.                         | `8999`            |
| `datanode.service.ports.data`                          | Data communication port.                        | `9200`            |
| `datanode.service.ports.config`                        | Configuration communication port.               | `9300`            |
| `datanode.env`                                         | Custom environment variables.                   | `{}`              |
| `datanode.config.nodeIdFile`                           | Path to datanode ID file.                       | `""`              |
| `datanode.config.opensearchHeap`                       | OpenSearch heap size.                           | `"2g"`            |
| `datanode.config.javaOpts`                             | Java options for datanode.                      | `"-Xms1g -Xmx1g"` |
| `datanode.config.skipPreflightChecks`                  | Skip startup checks.                            | `"false"`         |
| `datanode.config.nodeSearchCacheSize`                  | Size of search cache.                           | `"10gb"`          |
| `datanode.config.s3ClientDefaultSecretKey`             | Default S3 client secret key.                   | `""`              |
| `datanode.config.s3ClientDefaultAccessKey`             | Default S3 client access key.                   | `""`              |
| `datanode.config.s3ClientDefaultEndpoint`              | Default S3 client endpoint.                     | `""`              |
| `datanode.config.s3ClientDefaultRegion`                | Default S3 client region.                       | `"us-east-2"`     |
| `datanode.config.s3ClientDefaultProtocol`              | Default S3 client protocol.                     | `"http"`          |
| `datanode.config.s3ClientDefaultPathStyleAccess`       | Enable path-style access for S3 client.         | `"true"`          |
| `datanode.image.repository`                            | Datanode image repository.                      | `""`              |
| `datanode.image.tag`                                   | Datanode image tag.                             | `""`              |
| `datanode.image.imagePullPolicy`                       | Image pull policy.                              | `IfNotPresent`    |
| `datanode.image.imagePullSecrets`                      | Image pull secrets.                             | `[]`              |
| `datanode.updateStrategy.type`                         | Pod update strategy for StatefulSet.            | `"RollingUpdate"` |
| `datanode.updateStrategy.rollingUpdate.maxUnavailable` | Max unavailable pods during an update.          | `1`               |
| `datanode.updateStrategy.rollingUpdate.partition`      | Pods that will remain unaffected by the update. | `""`              |
| `datanode.resources.limits.cpu`                        | CPU limit for the datanode pod.                 | `"1"`             |
| `datanode.resources.limits.memory`                     | Memory limit for the datanode pod.              | `"5Gi"`           |
| `datanode.resources.requests.cpu`                      | CPU request for the datanode pod.               | `"500m"`          |
| `datanode.resources.requests.memory`                   | Memory request for the datanode pod.            | `"3.5Gi"`         |
| `datanode.persistence.enabled`                         | Enable persistence.                             | `true`            |
| `datanode.persistence.data.enabled`                    | Enable persistent volume for data.              | `true`            |
| `datanode.persistence.data.storageClass`               | Storage class for data PVC.                     | `""`              |
| `datanode.persistence.data.existingClaim`              | Use existing PVC for data.                      | `""`              |
| `datanode.persistence.data.mountPath`                  | Mount path for data volume.                     | `""`              |
| `datanode.persistence.data.accessModes`                | Access modes for data PVC.                      | `[]`              |
| `datanode.persistence.data.size`                       | Size of the data volume.                        | `"8Gi"`           |
| `datanode.persistence.data.annotations`                | Annotations for data PVC.                       | `{}`              |
| `datanode.persistence.data.labels`                     | Labels for data PVC.                            | `{}`              |
| `datanode.persistence.data.selector`                   | Selector for data PVC.                          | `{}`              |
| `datanode.persistence.data.dataSource`                 | Data source for data PVC.                       | `{}`              |
| `datanode.persistence.nativeLibs.enabled`              | Enable persistence for native libraries.        | `false`           |
| `datanode.persistence.nativeLibs.storageClass`         | Storage class for native libs PVC.              | `""`              |
| `datanode.persistence.nativeLibs.existingClaim`        | Use existing PVC for native libs.               | `""`              |
| `datanode.persistence.nativeLibs.mountPath`            | Mount path for native libs volume.              | `""`              |
| `datanode.persistence.nativeLibs.accessModes`          | Access modes for native libs PVC.               | `[]`              |
| `datanode.persistence.nativeLibs.size`                 | Size of the native libs volume.                 | `"2Gi"`           |
| `datanode.persistence.nativeLibs.annotations`          | Annotations for native libs PVC.                | `{}`              |
| `datanode.persistence.nativeLibs.labels`               | Labels for native libs PVC.                     | `{}`              |
| `datanode.persistence.nativeLibs.selector`             | Selector for native libs PVC.                   | `{}`              |
| `datanode.livenessProbe.enabled`                       | Enable liveness probe.                          | `true`            |
| `datanode.livenessProbe.initialDelaySeconds`           | Initial delay for liveness probe.               | `30`              |
| `datanode.livenessProbe.periodSeconds`                 | Period between liveness probe checks.           | `10`              |
| `datanode.livenessProbe.timeoutSeconds`                | Timeout for the liveness probe.                 | `5`               |
| `datanode.livenessProbe.failureThreshold`              | Failure threshold for the liveness probe.       | `6`               |
| `datanode.livenessProbe.successThreshold`              | Success threshold for the liveness probe.       | `1`               |
| `datanode.readinessProbe.enabled`                      | Enable readiness probe.                         | `true`            |
| `datanode.readinessProbe.initialDelaySeconds`          | Initial delay for readiness probe.              | `10`              |
| `datanode.readinessProbe.periodSeconds`                | Period between readiness probe checks.          | `10`              |
| `datanode.readinessProbe.timeoutSeconds`               | Timeout for the readiness probe.                | `5`               |
| `datanode.readinessProbe.failureThreshold`             | Failure threshold for the readiness probe.      | `6`               |
| `datanode.readinessProbe.successThreshold`             | Success threshold for the readiness probe.      | `1`               |
| `datanode.podDisruptionBudget.enabled`                 | Enable PodDisruptionBudget.                     | `false`           |
| `datanode.podDisruptionBudget.minAvailable`            | Minimum available pods during disruption.       | `2`               |
| `datanode.podAnnotations`                              | Additional pod annotations.                     | `{}`              |
| `datanode.nodeSelector`                                | Node selector for scheduling datanode pods.     | `{}`              |
| `datanode.tolerations`                                 | Tolerations for scheduling.                     | `[]`              |
| `datanode.affinity`                                    | Affinity rules for scheduling.                  | `{}`              |
| `datanode.extraEnv`                                    | Custom EnvVar environment variables.            | `[]`              |


## Service Account
| Key Path                      | Description                                             | Default |
|-------------------------------|---------------------------------------------------------|---------|
| `serviceAccount.create`       | Create a new service account.                           | `true`  |
| `serviceAccount.automount`    | Automount service account token.                        | `true`  |
| `serviceAccount.annotations`  | Annotations for service account.                        | `{}`    |
| `serviceAccount.nameOverride` | Override name of service account.                       | `""`    |
| `serviceAccount.role.create`  | Create a new role to bind to this service account.      | `false` |
| `serviceAccount.role.rules`   | Rules for the new role to bind to this service account. | `[]`    |


## Ingress

| Key Path                                        | Description                                      | Default |
|-------------------------------------------------|--------------------------------------------------|---------|
| `ingress.enabled`                               | Enable ingress resources.                        | `false` |
| `ingress.config.defaultBackend.enabled`         | Enable default backend for ingress.              | `true`  |
| `ingress.config.tls.clusterIssuer.existingName` | Name of existing ClusterIssuer for TLS.          | `""`    |
| `ingress.config.tls.issuer.existingName`        | Name of existing Issuer for TLS.                 | `""`    |
| `ingress.config.tls.issuer.managed.enabled`     | Enable auto-issuing of TLS certificates.         | `false` |
| `ingress.config.tls.issuer.managed.staging`     | Use staging environment for auto-issued certs.   | `true`  |

### Web Ingress
| Key Path                                 | Description                        | Default                  |
|------------------------------------------|------------------------------------|--------------------------|
| `ingress.web.enabled`                    | Enable ingress for Graylog Web.    | `false`                  |
| `ingress.web.className`                  | Ingress class name.                | `""`                     |
| `ingress.web.annotations`                | Annotations for ingress resource.  | `{}`                     |
| `ingress.web.hosts[0].host`              | Hostname for ingress (optional).   | `""`                     |
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

## MongoDB
MongoDB Community Resource configuration.
Requires the MCK Operator: https://github.com/mongodb/mongodb-kubernetes/tree/master/docs/mongodbcommunity

| Key Path                              | Description                                                 | Default                                                                                                                                                                                                                |
|---------------------------------------|-------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `mongodb.communityResource.enabled`   | Enables creation of the `MongoDBCommunity` custom resource. | `true`                                                                                                                                                                                                                 |
| `mongodb.version`                     | MongoDB server version for the replica set.                 | `"7.0.25"`                                                                                                                                                                                                             |
| `mongodb.replicas`                    | Number of data-bearing replica set members.                 | `2`                                                                                                                                                                                                                    |
| `mongodb.arbiters`                    | Number of arbiter nodes to deploy.                          | `1`                                                                                                                                                                                                                    |
| `mongodb.persistence.storageClass`    | StorageClass to use for persistent volumes.                 | `""`                                                                                                                                                                                                                   |
| `mongodb.persistence.size.data`       | Persistent volume size for data storage.                    | `"10G"`                                                                                                                                                                                                                |
| `mongodb.persistence.size.logs`       | Persistent volume size for MongoDB logs.                    | `"2G"`                                                                                                                                                                                                                 |
| `mongodb.serviceAccount.create`       | Create a new service account for MongoDB workloads.         | `true`                                                                                                                                                                                                                 |
| `mongodb.serviceAccount.automount`    | Automount service account token.                            | `true`                                                                                                                                                                                                                 |
| `mongodb.serviceAccount.annotations`  | Annotations for service account.                            | `{}`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.nameOverride` | Override name of service account.                           | `""`                                                                                                                                                                                                                   |
| `mongodb.serviceAccount.role.create`  | Create a new role to bind to this service account.          | `true`                                                                                                                                                                                                                 |
| `mongodb.serviceAccount.role.rules`   | Rules for the new role to bind to this service account.     | <pre><code>rules:&#10;  - apiGroups: [ "" ]&#10;    resources: [ "secrets" ]&#10;    verbs: [ "get" ]&#10;  - apiGroups: [ "" ]&#10;    resources: [ "pods" ]&#10;    verbs: [ "get", "patch", "delete" ]</code></pre> |
