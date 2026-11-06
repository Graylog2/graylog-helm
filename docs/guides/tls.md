# Enable TLS

Before you can enable TLS, you must associate a DNS name with your Graylog installation.
More specifically, your domain should point to the IP address/hostname associated with the service used for [External Access](../../charts/graylog/README.md#set-external-access).
You may retrieve this information like this:

```sh
kubectl get svc $SERVICE_NAME -n graylog
# look for the EXTERNAL-IP field
```

With `SERVICE_NAME` being equal to the name of the service exposed by your ingress controller, if you're using one, or
`graylog-svc` otherwise.

Depending on your setup, TLS can be enabled in three different ways:

## Option 1: Bring your own certificate with an Ingress controller (recommended)

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
helm upgrade graylog graylog/graylog -n graylog --reuse-values -f ingress-with-tls.yaml
```

## Option 2: Auto-issued certificates using cert-manager

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
helm upgrade graylog graylog/graylog -n graylog --reuse-values -f ingress-with-tls.yaml --set ingress.config.tls.issuer.existingName='<name of your existing issuer resource>'
```

> [!NOTE]
> An Issuer or ClusterIssuer resource is required for cert-manager to issue TLS certificates automatically.
> Please refer to [cert-manager docs](https://cert-manager.io/docs/) for instructions.

For convenience, this chart includes an optional built-in feature to automatically create a Let's Encrypt `Issuer` 
resource for `cert-manager`. Since issuers are typically managed by cluster administrators, this is disabled by default. 
If you prefer the Graylog chart to handle this specific issuer creation, you may enable it by setting 
`ingress.config.tls.issuer.managed.enabled=true`.

## Option 3: Bring your own certificate with Graylog native TLS

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
helm upgrade graylog graylog/graylog -n graylog --reuse-values --set graylog.config.tls.enabled=true --set graylog.config.tls.secretName="my-cert" --set graylog.config.tls.updateKeyStore=true
```
The default set of trusted Certificate Authorities bundled in the Java runtime matches the major,
well-known public root CAs. Make sure to set `graylog.config.tls.updateKeyStore` to `true` if you are using a
self-signed certificate, or if you think the CA that signed your certificate might not be among this default set.


## Ingress controller

By default, the chart exposes a Kubernetes service. An Ingress controller gives you better control of external
traffic. Set `ingress.enabled` to `true` and the chart creates the Ingress resource. Any controller works (NGINX,
HAProxy and others), but it must be installed in the cluster first. See
[Set external access](../../charts/graylog/README.md#set-external-access).


## cert-manager

You can [bring your own certificates](#option-1-bring-your-own-certificate-with-an-ingress-controller-recommended),
but `cert-manager` simplifies TLS setup and certificate renewal.

Install an [Ingress controller](#ingress-controller) first, and set `ingress.enabled` to `true`.
Then set `ingress.web.tls` and `ingress.config.tls.issuer.existingName` to the name of an existing Issuer
resource. See [Option 2](#option-2-auto-issued-certificates-using-cert-manager) for the full values.
