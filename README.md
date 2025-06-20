# Graylog Helm
A helm chart for Graylog.

## Not For External Use
This chart is still in development. We should not distribute this chart or any part of this repository externally until we've cleaned up the git history and recieved approval for external distribution.
This chart is still under development and does not have locked in api contracts yet.


## TLDR
**Installation Process**
 - Create the namespace you'll be installing Graylog into.
 - Create a secret like [examples/graylog-secret.yaml](examples/graylog-secret.yaml) in that namespace.
 - Run `helm upgrade --install my-graylog graylog -f graylog/values-my-graylog.yaml`

Uninstall
```bash
helm uninstall my-graylog
```

## Requirements
 - Kubernetes v1.32

## Development
### Mongo
All files in `/mongo` are currently for development purposes only. Use with caution!

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
```bash
kubectl delete pvc datanode-graylog-datanode-0
kubectl delete pvc datanode-graylog-datanode-1
kubectl delete pvc datanode-graylog-datanode-2
kubectl delete pvc graylog-app-journal-graylog-0
kubectl delete pvc graylog-app-journal-graylog-1
```
