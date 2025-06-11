# Graylog Helm
A helm chart for Graylog

## TLDR
Install
 - Create the namespace you'll be installing Graylog into.
 - Create a secret like [examples/graylog-secret.yaml](examples/graylog-secret.yaml) in that namespace.
 - Run `helm upgrade --install my-graylog graylog -f graylog/values-my-graylog.yaml`

Uninstall
```bash
helm uninstall graylog
```

## Development
### Mongo
All files in mongo are currently for development purposes only. Use with caution!

## Debugging
Get a yaml output of the values being submitted.
```bash
helm template graylog graylog -f graylog/values-glc.yaml | yq
```

### Logging
```
stern statefulset/graylog-datanode
stern statefulset/graylog
```

### Remove Everything
```bash
kubectl delete pvc datanode-graylog-datanode-0
kubectl delete pvc datanode-graylog-datanode-1
kubectl delete pvc datanode-graylog-datanode-2
kubectl delete pvc graylog-app-journal-graylog-0
kubectl delete pvc graylog-app-journal-graylog-1
```
