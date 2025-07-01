# Graylog Helm
Official helm chart for Graylog.

## Not For External Use
This chart is still in development. We should not distribute this chart or any part of this repository externally until we've cleaned up the git history and recieved approval for external distribution.
This chart is still under development and does not have locked in api contracts yet.

## Requirements
- Kubernetes v1.32

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

## Installation

### Clone this repo
```sh
# clone repo
git clone git@github.com:Graylog2/graylog-helm.git

# cd into the newly created graylog-helm directory
cd graylog-helm
```

### Set Root Graylog Password
```sh
read -sp "Enter your new password and press return: " pass
```

### Install local chart
```sh
helm install graylog ./graylog --namespace graylog --create-namespace --set "graylog.config.rootPassword=$pass"
```

🏁 That's it!

## Usage

### Scale Graylog
```sh
# scaling out: add more Graylog nodes to your cluster
helm upgrade graylog ./graylog -n graylog --set graylog.replicas=3 --reuse-values

# scaling in: remove Graylog nodes from your cluster
helm upgrade graylog ./graylog -n graylog --set graylog.replicas=1 --reuse-values
```

### Scale Datanode
```sh
# scaling out: add more Graylog Datanodes to your cluster
helm upgrade graylog ./graylog -n graylog --set datanode.replicas=5 --reuse-values
```

### Scale MongoDB
```sh
# scaling out: add more MongoDB nodes to your replicaset
helm upgrade graylog ./graylog -n graylog --set mongodb.replicaCount=4 --reuse-values
```

### Modify Graylog `server.conf` parameters

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

### Customize deployed Kubernetes resources
```sh
# A few examples: 

# expose the Graylog application with a LoadBalancer service
helm upgrade graylog ./graylog -n graylog --set graylog.custom.service.type="LoadBalancer" --reuse-values

# modify readiness probe initial delay
helm upgrade graylog ./graylog -n graylog --set graylog.custom.readinessProbe.initialDelaySeconds=5 --reuse-values

# use a custom Storage Class for all resources (e.g. for AWS EKS)
helm upgrade graylog ./graylog -n graylog --set global.defaultStorageClass="gp2" --reuse-values
```

### Add inputs

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

### Uninstall
```sh
# optional: scale Graylog down to zero
kubectl scale sts graylog -n graylog --replicas 0  && kubectl wait --for=delete pod graylog-0 -n graylog

# remove chart
helm uninstall graylog -n graylog
```

#### Removing Everything
```sh
# CAUTION: this will delete ALL your data!
kubectl delete $(kubectl get pvc -o name -n graylog; kubectl get secret -o name -n graylog) -n graylog
```

### Debugging
Get a YAML output of the values being submitted.
```bash
helm template graylog graylog -f graylog/values-glc.yaml | yq
```

### Logging
```
# Graylog app logs
stern statefulset/graylog-app -n graylog-helm-dev-1
# Datanode logs
stern statefulset/graylog-datanode -n graylog-helm-dev-1
```

---

## Graylog Helm Chart Values Reference
| Key Path           | Description                                           | Default   |
| ------------------ |-------------------------------------------------------| --------- |
| `nameOverride`     | Override the `app.kubernetes.io/name` label value.    | `""`      |
| `fullnameOverride` | Override the fully qualified name of the application. | `""`      |

### Global
These values affect Graylog, Datanode, and MongoDB

| Key Path                     | Description                                 | Default |
|------------------------------| ------------------------------------------- |---------|
| `global.existingSecretName`  | Reference to an existing Kubernetes secret. | `""`    |
| `global.imagePullSecrets`    | Image pull secrets for private registries.  | `[]`    |
| `global.defaultStorageClass` | Default storage class for PVCs.             | `""`    |


### Graylog application
| Key Path                                              | Description                                     | Default           |
|-------------------------------------------------------|-------------------------------------------------|-------------------|
| `graylog.enabled`                                     | Enable the Graylog server.                      | `true`            |
| `graylog.enterprise`                                  | Enable enterprise features.                     | `true`            |
| `graylog.replicas`                                    | Number of Graylog server replicas.              | `2`               |
| `graylog.inputs`                                      | List of input configurations.                   | See below         |
| `graylog.inputs[0].name`                              | Name of input for GELF messages.                | `input-gelf`      |
| `graylog.inputs[0].port`                              | Port exposed for input.                         | `12201`           |
| `graylog.inputs[0].targetPort`                        | Target container port.                          | `12201`           |
| `graylog.inputs[0].protocol`                          | Protocol used for input.                        | `TCP`             |
| `graylog.inputs[0].ingress`                           | Enable ingress for this input.                  | `true`            |
| `graylog.config.rootUsername`                         | Root admin username.                            | `"admin"`         |
| `graylog.config.rootPassword`                         | Root admin password.                            | `""`              |
| `graylog.config.timezone`                             | Timezone for the Graylog server.                | `"UTC"`           |
| `graylog.config.selfSignedStartup`                    | Use self-signed certs on startup.               | `"true"`          |
| `graylog.config.serverJavaOpts`                       | Java options for server.                        | `"-Xms1g -Xmx1g"` |
| `graylog.custom.podAnnotations`                       | Additional pod annotations.                     | `{}`              |
| `graylog.custom.nodeSelector`                         | Node selector for scheduling.                   | `{}`              |
| `graylog.custom.inputs.enabled`                       | Enable Graylog inputs.                          | `true`            |
| `graylog.custom.metrics.enabled`                      | Enable metrics collection.                      | `true`            |
| `graylog.custom.image.repository`                     | Image repository for Graylog.                   | `""`              |
| `graylog.custom.image.tag`                            | Image tag for Graylog.                          | `""`              |
| `graylog.custom.image.imagePullPolicy`                | Pull policy for Graylog image.                  | `IfNotPresent`    |
| `graylog.custom.image.imagePullSecrets`               | Pull secrets for image.                         | `[]`              |
| `graylog.updateStrategy.type`                         | Pod update strategy for StatefulSet.            | `"RollingUpdate"` |
| `graylog.updateStrategy.rollingUpdate.maxUnavailable` | Max unavailable pods during an update.          | `1`               |
| `graylog.updateStrategy.rollingUpdate.partition`      | Pods that will remain unaffected by the update. | `""`              |
| `graylog.custom.service.nameOverride`                 | Override for service name.                      | `""`              |
| `graylog.custom.service.type`                         | Kubernetes service type.                        | `ClusterIP`       |
| `graylog.custom.service.ports.app`                    | Graylog web UI port.                            | `9000`            |
| `graylog.custom.service.ports.metrics`                | Metrics endpoint port.                          | `9833`            |
| `graylog.custom.service.ports.inputGelfHttp`          | GELF HTTP input port.                           | `12201`           |


### Datanode
| Key Path                                               | Description                                     | Default           |
|--------------------------------------------------------|-------------------------------------------------|-------------------|
| `datanode.enabled`                                     | Enable Graylog datanode.                        | `true`            |
| `datanode.replicas`                                    | Number of datanode replicas.                    | `3`               |
| `datanode.config.nodeIdFile`                           | Path to datanode ID file.                       | `""`              |
| `datanode.config.opensearchHeap`                       | OpenSearch heap size.                           | `"2g"`            |
| `datanode.config.javaOpts`                             | Java options for datanode.                      | `"-Xms1g -Xmx1g"` |
| `datanode.config.skipPreflightChecks`                  | Skip startup checks.                            | `"false"`         |
| `datanode.config.nodeSearchCacheSize`                  | Size of search cache.                           | `"10gb"`          |
| `datanode.custom.podAnnotations`                       | Additional pod annotations.                     | `{}`              |
| `datanode.custom.nodeSelector`                         | Node selector for datanode.                     | `{}`              |
| `datanode.custom.image.repository`                     | Datanode image repository.                      | `""`              |
| `datanode.custom.image.tag`                            | Datanode image tag.                             | `""`              |
| `datanode.custom.image.imagePullPolicy`                | Image pull policy.                              | `IfNotPresent`    |
| `datanode.custom.image.imagePullSecrets`               | Image pull secrets.                             | `[]`              |
| `datanode.updateStrategy.type`                         | Pod update strategy for StatefulSet.            | `"RollingUpdate"` |
| `datanode.updateStrategy.rollingUpdate.maxUnavailable` | Max unavailable pods during an update.          | `1`               |
| `datanode.updateStrategy.rollingUpdate.partition`      | Pods that will remain unaffected by the update. | `""`              |
| `datanode.custom.service.ports.api`                    | API communication port.                         | `8999`            |
| `datanode.custom.service.ports.data`                   | Data communication port.                        | `9200`            |
| `datanode.custom.service.ports.config`                 | Configuration communication port.               | `9300`            |


### Service Account
| Key Path                      | Description                       | Default |
| ----------------------------- | --------------------------------- | ------- |
| `serviceAccount.create`       | Create a new service account.     | `true`  |
| `serviceAccount.automount`    | Automount service account token.  | `true`  |
| `serviceAccount.annotations`  | Annotations for service account.  | `{}`    |
| `serviceAccount.nameOverride` | Override name of service account. | `""`    |


### Ingress
| Key Path                             | Description                       | Default                  |
| ------------------------------------ | --------------------------------- | ------------------------ |
| `ingress.enabled`                    | Enable ingress for Graylog.       | `false`                  |
| `ingress.className`                  | Ingress class name.               | `""`                     |
| `ingress.annotations`                | Annotations for ingress resource. | `{}`                     |
| `ingress.hosts[0].host`              | Hostname for ingress.             | `chart-example.local`    |
| `ingress.hosts[0].paths[0].path`     | Path for routing.                 | `/`                      |
| `ingress.hosts[0].paths[0].pathType` | Path matching type.               | `ImplementationSpecific` |
| `ingress.tls`                        | TLS configuration.                | `[]`                     |

