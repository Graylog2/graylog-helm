## Git Workflow Guidelines

- Do **not** commit directly to `main`. Always use a feature branch:
```sh
git checkout -b feat/my-feature
```
- Before opening a PR, **rebase or squash** your commits to keep history clean:
```sh
git rebase origin/main
```
- Use clear and concise commit messages. We recommend following [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
```sh
git commit -m "docs: add CONTRIBUTING.md"
```
- Ensure your branch is up to date with `main` before creating a PR:
```sh
git fetch origin
git rebase origin/main
```

- Review and complete the steps in [docs/TESTING.md](docs/TESTING.md) before submitting a PR

- All PRs must be reviewed by at least one maintainer before merging.

## Local Development

### Setting up a dev Kubernetes cluster

This Helm chart should ideally work on any Kubernetes cluster.
For local development and iterative testing, we recommend using MicroK8s.

For more info on how to set up a local MicroK8s environment, see: [Setting up a MicroK8s cluster](docs/microk8s-setup-guide.md)

### Upgrading chart

> [!NOTE]
> Values can be passed into the chart from multiple sources, including
> - The `values.yaml` file in the chart, with all default values
> - A values file passed with the `--values` or `-f` flag (e.g. `helm upgrade graylog . -f mynewvals.yaml`)
> - Individual parameters passed with `--set` (e.g. `helm upgrade graylog . --set foo=bar`)
> 
> The default values in `values.yaml` can be overridden by a parent chart's `values.yaml` (in the event this chart is used as a subchart), which can in turn be overridden by a user-supplied values file with `-f`, which can in turn be overridden by `--set` parameters.

> [!NOTE]
> The `reset-values` and `reuse-values` flags can be used to control how values are handled during an upgrade:
> - `--reset-values`: Discards the previously set values and uses only the values provided in the current upgrade command (via `--values` or `--set`).
> - `--reuse-values`: Reuses the values from the last release and merges them with any new values provided in the upgrade command.
> 
> These two flags are mutually exclusive.
> 
> In addition, if no `-f` (or `--values`), or `--set` (or `--set-string`, or `--set-file`) flags are applied,
> `--reuse-values` will be used by default. Otherwise, `--reset-values` will be used by default.
```bash
# keeps previously set values and overrides current "appVersion"
helm upgrade graylog ./charts/graylog -n graylog --reuse-values --set version="7.1"
```
