# Contributing

## Git workflow

- Do not commit to `main`. Use a feature branch:
```sh
git checkout -b feat/my-feature
```
- Keep your branch up to date with `main`, and rebase or squash before you open a PR:
```sh
git fetch origin
git rebase origin/main
```
- [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) are required. release-please reads the commit subjects to pick the next chart version and write the changelog.
```sh
git commit -m "fix(datanode): correct the volume claim selector"
```
- The PR title is what counts. Squash merge is the only merge method, and the squash subject comes from the PR title when a branch has more than one commit. Write the title the way you want the changelog to read.
- Repository tooling changes (workflows, scripts, CI) use `ci:` or `chore:`, never `fix:` or `feat:`, so they do not release the chart.
- Mark breaking changes with `!` after the type or a `BREAKING CHANGE:` footer, and document them in [charts/graylog/UPGRADING.md](charts/graylog/UPGRADING.md) in the same PR.
- Never start a commit body line with `word(`. release-please reads it as a `type(scope` header and silently drops the whole commit, changelog entry included. Reflow the line. [docs/development/RELEASING.md](docs/development/RELEASING.md) explains why.
- Do not hand-edit `version:` in `charts/graylog/Chart.yaml`, `charts/graylog/CHANGELOG.md` or `.release-please-manifest.json`. release-please owns all three.
- Follow the [chart development guide](docs/DEVELOPMENT.md) when you change templates or values.
- Complete the steps in [docs/development/TESTING.md](docs/development/TESTING.md) before you submit a PR.
- At least one maintainer must review every PR before it merges.

## Local development

### Set up a dev cluster

The chart should work on any Kubernetes cluster. We use MicroK8s for local development. See [Setting up a MicroK8s cluster](docs/microk8s-setup-guide.md).

### Upgrading the chart

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

## Releasing

Releases are commit-driven. release-please reads the Conventional Commit subjects
that land on `main`, works out the next version, and keeps a release PR open with
the version bump and the changelog. Merging that PR is the release, and publication
follows automatically.

A commit contributes to a release only when its subject is a releasable type,
`feat:`, `fix:` or `perf:`, and it touches a file under `charts/graylog/`.

Contributors do not bump the chart version. A chart PR leaves `version:` at the last release.

For how to verify a publication and what to do when one fails, see [docs/development/RELEASING.md](docs/development/RELEASING.md).
