# Graylog charts

Official open source Helm charts for Graylog.

## Getting started

New here? Start with the [Graylog chart README](charts/graylog/README.md). It has the
[installation instructions](charts/graylog/README.md#installation), requirements and
post-installation steps.

## Available modules

* [charts/graylog](charts/graylog/README.md) - the Graylog Helm chart
* [docs](docs/) - configuration guides, run books and development docs
* [examples](examples/) - example values files and Kubernetes manifests

## Guides

Configuration and operations:

* [Managing Graylog secrets](docs/graylog-secrets.md) - required Secret keys and how to supply them
* [Bring your own MongoDB](docs/bring-your-own-mongo.md) - use an externally managed MongoDB
* [Bring your own OpenSearch](docs/bring-your-own-opensearch.md) - use an externally managed OpenSearch
* [GeoIP sidecar deployment](docs/GeoIP_Sidecar_Deployment_Guide.md) - enable and operate GeoIP lookups
* [Data Node roles and node groups](docs/datanode/datanode-node-roles.md) - run dedicated Data Node groups
* [Data Node safe updates](docs/datanode/datanode-safe-updates.md) - update and scale Data Nodes without losing shards
* [Message handling](docs/graylog-message-handling.md) - inputs, the message journal, and safe scale-in
* [MongoDB backup and restore](docs/mongodb-backup-restore.md) - take and restore a `mongodump` backup
* [MicroK8s setup](docs/microk8s-setup-guide.md) - prepare a MicroK8s cluster for the chart

Contributing and releasing:

* [Chart development guide](docs/DEVELOPMENT.md) - conventions for templates and values
* [Testing](docs/development/TESTING.md) - run the chart test suite
* [Releasing](docs/development/RELEASING.md) - publish a chart release

---
<small>&copy; 2026 <a href="https://graylog.org">Graylog, Inc.</a></small>
