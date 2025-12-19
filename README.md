Official Helm chart repository for Graylog.

## Usage

[Helm](https://helm.sh) must be installed to use the charts.
Please refer to Helm's [documentation](https://helm.sh/docs) to get started.

Once Helm has been set up correctly, add the repo as follows:

    helm repo add graylog https://graylog2.github.io/graylog-helm

If you had already added this repo earlier, run `helm repo update` to retrieve the latest versions of the packages.
You can then run `helm search repo graylog` to see the charts.

# Graylog Helm chart

For comprehensive documentation including requirements, chart details, and configuration values, 
refer to the chart [README.md](charts/graylog/README.md)

To install the graylog chart:

    helm install my-graylog graylog/graylog

To uninstall the chart:

    helm uninstall my-graylog

---
<small>&copy; 2025 <a href="https://graylog.org">Graylog, Inc.</a></small>