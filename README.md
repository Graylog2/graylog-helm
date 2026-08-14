# Graylog charts

Official open source Helm charts for Graylog.

## Getting started

New here? Head over to the [Graylog chart README](charts/graylog/README.md) for full
[installation instructions](charts/graylog/README.md#installation), requirements, and
post-installation steps to get Graylog up and running.

## Available modules

* [charts/graylog](charts/graylog/README.md) - official Graylog helm chart
* [docs](docs/) - documentation for testing and configuration guides
* [examples](examples/) - example values files and Kubernetes manifests

## Guides

Configuration and operations:

* [Managing Graylog secrets](docs/graylog-secrets.md) - required Secret keys and how to supply them
* [Bring your own MongoDB](docs/bring-your-own-mongo.md) - use an externally managed MongoDB
* [Bring your own OpenSearch](docs/bring-your-own-opensearch.md) - use an externally managed OpenSearch
* [GeoIP sidecar deployment](docs/GeoIP_Sidecar_Deployment_Guide.md) - enable and operate GeoIP lookups
* [Message handling](docs/graylog-message-handling.md) - inputs, the message journal, and safe scale-in
* [MongoDB backup and restore](docs/mongodb-backup-restore.md) - take and restore a `mongodump` backup
* [MicroK8s setup](docs/microk8s-setup-guide.md) - prepare a MicroK8s cluster for the chart

Contributing and releasing:

* [Testing](docs/TESTING.md) - run the chart test suite
* [Releasing](docs/RELEASING.md) - publish a chart release

---
<small>&copy; 2026 <a href="https://graylog.org">Graylog, Inc.</a></small>
