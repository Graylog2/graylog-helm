# Graylog Helm
A helm chart for Graylog

## TLDR
Install
```bash
helm upgrade --install my-graylog graylog -f graylog/values-my-graylog.yaml
```
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
