# Bring Your Own Mongo
Graylog Helm supports bringing your own Mongo, the only requirement is that it fits within our
[compatability matrix](https://go2docs.graylog.org/current/downloading_and_installing_graylog/compatibility_matrix.htm).
## Steps
### Graylog Secret
If you want to bring your mongo you will also have to create your own set of secrets for Graylog.
Create a secret with the required keys listed in [Graylog Secrets](graylog-secrets.md#required-keys). [examples/graylog-secret.yaml](https://github.com/Graylog2/graylog-helm/blob/main/examples/graylog-secret.yaml) shows the full shape. That example uses `stringData`, so you supply plain text values and Kubernetes encodes them for you.
This file can be named anything you would like, but it needs to be mentioned in your values.yaml.
### Values File
In your values file you will want your configuration to include at least the following.
```yaml
global:
  existingSecretName: "my-new-graylog-secret"
mongodb:
  communityResource:
    enabled: false
```
