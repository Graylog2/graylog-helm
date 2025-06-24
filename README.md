# Graylog Helm
A helm chart for Graylog.

## Not For External Use
This chart is still in development. We should not distribute this chart or any part of this repository externally until we've cleaned up the git history and recieved approval for external distribution.
This chart is still under development and does not have locked in api contracts yet.


## TL;DR
```sh
# Clone this repo
git clone git@github.com:Graylog2/graylog-helm.git
# Install the chart
helm install graylog ./graylog -n graylog --create-namespace
```

## Install from repository
```sh
helm install graylog graylog/graylog -n graylog --create-namespace
```

## Upgrades
```sh
helm repo update
helm upgrade graylog graylog/graylog -n graylog --reuse-values
```

### Uninstall
```sh
helm uninstall graylog -n graylog
```

## Requirements
 - Kubernetes v1.32

### Debugging
Get a yaml output of the values being submitted.
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
kubectl delete $(kubectl get pvc -o name -n graylog) -n graylog
```
