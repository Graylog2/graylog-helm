# GeoIP Sidecar Deployment Guide

This guide covers deploying Graylog with the new GeoIP sidecar container for automatic MaxMind database updates.

## Overview

The GeoIP sidecar is a lightweight container that runs alongside Graylog and automatically updates MaxMind GeoIP databases on a configurable schedule. It replaces the previous Kubernetes CronJob approach, eliminating RWO volume multi-attach errors on multi-node clusters.

## Prerequisites

- MaxMind account ID and license key (from [MaxMind website](https://www.maxmind.com/))
- Graylog Helm chart v1.0.0 or later
- Kubernetes 1.21+

## Quick Start

### 1. Deploy with Chart-Managed Credentials

```bash
helm install graylog charts/graylog \
  --set graylog.config.geolocation.enabled=true \
  --set graylog.config.geolocation.sidecar.enabled=true \
  --set graylog.config.geolocation.maxmindGeoIp.accountId=YOUR_ACCOUNT_ID \
  --set graylog.config.geolocation.maxmindGeoIp.licenseKey=YOUR_LICENSE_KEY
```

### 2. Deploy with External Secret

If you're using an external secret management system, create a Kubernetes secret with the MaxMind credentials:

```bash
kubectl create secret generic graylog-secrets \
  --from-literal=GEO_IP_MAXMIND_ACCOUNT_ID=YOUR_ACCOUNT_ID \
  --from-literal=GEO_IP_MAXMIND_LICENSE_KEY=YOUR_LICENSE_KEY
```

Then deploy with:

```bash
helm install graylog charts/graylog \
  --set graylog.config.geolocation.enabled=true \
  --set graylog.config.geolocation.sidecar.enabled=true \
  --set global.existingSecretName=graylog-secrets
```

## Configuration Options

### Enable/Disable GeoIP

```yaml
graylog:
  config:
    geolocation:
      enabled: true  # Set to false to disable GeoIP completely
      sidecar:
        enabled: true  # Set to false to disable sidecar (not recommended)
```

### Custom Update Schedule

Set the cron schedule for database updates (default: daily at midnight UTC):

```yaml
graylog:
  config:
    geolocation:
      sidecar:
        schedule: "0 2 * * *"  # 2 AM UTC
        # Other options:
        # schedule: "*/6 * * * *"   # Every 6 hours
        # schedule: "0 0 * * 0"     # Weekly on Sunday
```

### Custom MaxMind Editions

By default, the chart downloads GeoLite2-City and GeoLite2-ASN databases. To use different editions:

```yaml
graylog:
  config:
    geolocation:
      maxmindGeoIp:
        editionIds: "GeoIP2-City GeoIP2-ISP GeoIP2-Enterprise"
```

Available editions depend on your MaxMind account. Space-separated format.

### Resource Limits

Adjust CPU/memory allocation for the sidecar:

```yaml
graylog:
  config:
    geolocation:
      sidecar:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
```

## Monitoring

### Check Sidecar Status

```bash
# View logs from the sidecar
kubectl logs -f deployment/graylog -c geoip-updater

# Check if sidecar is running
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].name}' | grep geoip-updater
```

### Expected Log Output

When the sidecar updates the database:

```
[2026-07-17 02:00:00 UTC] GeoIP Sidecar started
[2026-07-17 02:00:00 UTC] Cron schedule: 0 2 * * *
[2026-07-17 02:00:00 UTC] Database directory: /usr/share/data/geolocation
[2026-07-17 02:00:00 UTC] Starting GeoIP database update...
[2026-07-17 02:00:15 UTC] GeoIP database update completed successfully
```

### Verify Databases Downloaded

```bash
# Exec into Graylog pod and check database files
kubectl exec -it pod/graylog-0 -- ls -lah /usr/share/data/geolocation/

# Output should show .mmdb files:
# -rw-r--r-- 1 root root 61M Jul 17 02:00 GeoLite2-City.mmdb
# -rw-r--r-- 1 root root 6.3M Jul 17 02:00 GeoLite2-ASN.mmdb
```

## Troubleshooting

### Sidecar Not Starting

**Error:** Pod crashes with "ImagePullBackOff"

- Verify network access to Docker Hub
- Check `imagePullSecrets` if using a private registry
- Verify image tag exists: `maxmindinc/geoipupdate:7.1.1`

**Error:** "GeoIP sidecar is enabled but MaxMind credentials are not provided"

- Set `graylog.config.geolocation.maxmindGeoIp.accountId`
- Set `graylog.config.geolocation.maxmindGeoIp.licenseKey`
- OR use `global.existingSecretName` with a secret containing `GEO_IP_MAXMIND_ACCOUNT_ID` and `GEO_IP_MAXMIND_LICENSE_KEY`

### Databases Not Updating

**Check 1:** Verify sidecar is running
```bash
kubectl get pods graylog-0 -o jsonpath='{.spec.containers[*].name}'
```

**Check 2:** Check sidecar logs for errors
```bash
kubectl logs graylog-0 -c geoip-updater --tail=50
```

**Check 3:** Verify credentials are correct
- MaxMind account ID and license key are valid
- Account has permission to download selected editions

**Check 4:** Check volume permissions
```bash
kubectl exec -it pod/graylog-0 -c geoip-updater -- \
  touch /usr/share/data/geolocation/test.txt && \
  rm /usr/share/data/geolocation/test.txt
```

### Custom Edition IDs Not Working

**Error:** "No databases matched the edition ids: GeoIP2-Enterprise"

- Verify the edition is available on your MaxMind account
- Check you have the correct license for that edition
- Account must have permission to download that edition

## Upgrading from CronJob

If you were previously using the CronJob approach:

1. The CronJob has been removed from the chart
2. Sidecar is now the only method for GeoIP updates
3. Existing deployments should automatically switch to sidecar on upgrade
4. No data loss - GeoIP databases persist on the volume

```bash
helm upgrade graylog charts/graylog \
  --set graylog.config.geolocation.enabled=true \
  --set graylog.config.geolocation.sidecar.enabled=true \
  --set graylog.config.geolocation.maxmindGeoIp.accountId=YOUR_ACCOUNT_ID \
  --set graylog.config.geolocation.maxmindGeoIp.licenseKey=YOUR_LICENSE_KEY
```

## Performance Considerations

### Sidecar Resource Usage

- **CPU:** Typically <10m during updates, <1m during idle
- **Memory:** ~128Mi under normal operation
- **Network:** Depends on database size (~100-200MB download)

### Update Duration

- First update: ~2-3 minutes (download + unpack)
- Subsequent updates: ~1-2 minutes (incremental updates)

### Scheduling Best Practices

- Schedule updates during off-peak hours
- Avoid overlap with other backup operations
- Consider timezone of your cluster (schedule uses UTC)
- For HA deployments, updates happen on each pod independently

## Security

### Security Context

The sidecar runs with the following security context by default:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
  readOnlyRootFilesystem: false
  runAsNonRoot: false
  runAsUser: 0
  seccompProfile:
    type: RuntimeDefault
```

The `runAsUser: 0` and `runAsNonRoot: false` are required for the sidecar to write to the volume. The root container then writes files that Graylog (running as uid 1100) can read.

### Secret Protection

- Credentials stored in Kubernetes Secret
- Secret referenced via `valueFrom.secretKeyRef` (never exposed as plaintext env var)
- Use RBAC to restrict Secret access
- Consider using encrypted storage for secrets at rest

## Advanced Configuration

### Custom Image

To use a different geoipupdate image version:

```yaml
graylog:
  config:
    geolocation:
      sidecar:
        image:
          tag: "7.0.0"  # Change version
```

### Additional Environment Variables

If using values overrides, you can add custom env vars:

```yaml
graylog:
  config:
    geolocation:
      sidecar:
        # Add to existing graylog.config.geolocation.sidecar.enabled configuration
        extraEnv:
          - name: GEOIPUPDATE_PROXY
            value: "proxy.example.com:8080"
```

## Testing

Run the functional test suite:

```bash
./tests/functional/geoip_sidecar_functional_tests.sh
```

Expected output: 15 passing tests

## References

- [MaxMind GeoIP Update Documentation](https://github.com/maxmind/geoipupdate)
- [GeoLite2 Free Database Info](https://www.maxmind.com/en/geolite2)
- [GeoIP2 Premium Databases](https://www.maxmind.com/en/products/geoip2-services)
