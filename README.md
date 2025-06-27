# Graylog Helm
Official helm chart for Graylog.

## Not For External Use
This chart is still in development. We should not distribute this chart or any part of this repository externally until we've cleaned up the git history and recieved approval for external distribution.
This chart is still under development and does not have locked in api contracts yet.

## Requirements
- Kubernetes v1.32

## TL;DR
```sh
# Clone this repo
git clone git@github.com:Graylog2/graylog-helm.git

# Install the chart
helm install graylog ./graylog -n graylog --create-namespace
```

### Install from repository
```sh
helm install graylog graylog/graylog -n graylog --create-namespace
```

### Upgrades
```sh
helm repo update
helm upgrade graylog graylog/graylog -n graylog --reuse-values
```

### Uninstall
```sh
# optional: scale Graylog down to zero
kubectl scale sts graylog -n graylog --replicas 0  && kubectl wait --for=delete pod graylog-0 -n graylog
l
# remove chart
helm uninstall graylog -n graylog
```

#### Debugging
Get a YAML output of the values being submitted.
```bash
helm template graylog graylog -f graylog/values-glc.yaml | yq
```

#### Logging
```
# Graylog app logs
stern statefulset/graylog-app -n graylog-helm-dev-1
# Datanode logs
stern statefulset/graylog-datanode -n graylog-helm-dev-1
```

#### Remove Everything
```sh
# CAUTION: this will delete ALL your data!
kubectl delete $(kubectl get pvc -o name -n graylog; kubectl get secret -o name -n graylog) -n graylog
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
| Key Path                                     | Description                        | Default           |
| -------------------------------------------- |------------------------------------|-------------------|
| `graylog.enabled`                            | Enable the Graylog server.         | `true`            |
| `graylog.enterprise`                         | Enable enterprise features.        | `true`            |
| `graylog.replicas`                           | Number of Graylog server replicas. | `2`               |
| `graylog.inputs`                             | List of input configurations.      | See below         |
| `graylog.inputs[0].name`                     | Name of input for GELF messages.   | `input-gelf`      |
| `graylog.inputs[0].port`                     | Port exposed for input.            | `12201`           |
| `graylog.inputs[0].targetPort`               | Target container port.             | `12201`           |
| `graylog.inputs[0].protocol`                 | Protocol used for input.           | `TCP`             |
| `graylog.inputs[0].ingress`                  | Enable ingress for this input.     | `true`            |
| `graylog.config.rootUsername`                | Root admin username.               | `"admin"`         |
| `graylog.config.rootPassword`                | Root admin password.               | `""`              |
| `graylog.config.timezone`                    | Timezone for the Graylog server.   | `"UTC"`           |
| `graylog.config.selfSignedStartup`           | Use self-signed certs on startup.  | `"true"`          |
| `graylog.config.serverJavaOpts`              | Java options for server.           | `"-Xms1g -Xmx1g"` |
| `graylog.custom.podAnnotations`              | Additional pod annotations.        | `{}`              |
| `graylog.custom.nodeSelector`                | Node selector for scheduling.      | `{}`              |
| `graylog.custom.inputs.enabled`              | Enable Graylog inputs.             | `true`            |
| `graylog.custom.metrics.enabled`             | Enable metrics collection.         | `true`            |
| `graylog.custom.image.repository`            | Image repository for Graylog.      | `""`              |
| `graylog.custom.image.tag`                   | Image tag for Graylog.             | `""`              |
| `graylog.custom.image.imagePullPolicy`       | Pull policy for Graylog image.     | `IfNotPresent`    |
| `graylog.custom.image.imagePullSecrets`      | Pull secrets for image.            | `[]`              |
| `graylog.custom.service.nameOverride`        | Override for service name.         | `""`              |
| `graylog.custom.service.type`                | Kubernetes service type.           | `ClusterIP`       |
| `graylog.custom.service.ports.app`           | Graylog web UI port.               | `9000`            |
| `graylog.custom.service.ports.metrics`       | Metrics endpoint port.             | `9833`            |
| `graylog.custom.service.ports.inputGelfHttp` | GELF HTTP input port.              | `12201`           |


### Datanode
| Key Path                                 | Description                       | Default           |
| ---------------------------------------- | --------------------------------- |-------------------|
| `datanode.enabled`                       | Enable Graylog datanode.          | `true`            |
| `datanode.replicas`                      | Number of datanode replicas.      | `3`               |
| `datanode.config.nodeIdFile`             | Path to datanode ID file.         | `""`              |
| `datanode.config.opensearchHeap`         | OpenSearch heap size.             | `"2g"`            |
| `datanode.config.javaOpts`               | Java options for datanode.        | `"-Xms1g -Xmx1g"` |
| `datanode.config.skipPreflightChecks`    | Skip startup checks.              | `"false"`         |
| `datanode.config.nodeSearchCacheSize`    | Size of search cache.             | `"10gb"`          |
| `datanode.custom.podAnnotations`         | Additional pod annotations.       | `{}`              |
| `datanode.custom.nodeSelector`           | Node selector for datanode.       | `{}`              |
| `datanode.custom.image.repository`       | Datanode image repository.        | `""`              |
| `datanode.custom.image.tag`              | Datanode image tag.               | `""`              |
| `datanode.custom.image.imagePullPolicy`  | Image pull policy.                | `IfNotPresent`    |
| `datanode.custom.image.imagePullSecrets` | Image pull secrets.               | `[]`              |
| `datanode.custom.service.ports.api`      | API communication port.           | `8999`            |
| `datanode.custom.service.ports.data`     | Data communication port.          | `9200`            |
| `datanode.custom.service.ports.config`   | Configuration communication port. | `9300`            |


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

