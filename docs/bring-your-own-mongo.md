# Bring Your Own Mogngo
Graylog Helm supports bringing your own Mongo, the only requirement is that it fits within our
[compatability matrix](https://go2docs.graylog.org/current/downloading_and_installing_graylog/compatibility_matrix.htm).
## Steps
### Graylog Secret
If you want to bring your mongo you will also have to create your own set of secrets for Graylog.
Create a secret with at least the keys specified in [examples/graylog-secret.yaml](https://github.com/Graylog2/graylog-helm/blob/main/examples/graylog-secret.yaml) but with base64 encoded variables.
This file can be named anything you would like, but it needs to be mention in your values.yaml.
### Values File
In your values file you will want your configuration to include at least the following.
```yaml
global:
  existingSecretName: "my-new-graylog-secret"
mongodb:
  subchart:
    enabled: false
```
