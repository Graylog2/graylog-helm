# Graylog Helm Chart Release Guide

This document describes how to cut a new release of the Graylog Helm chart, from
pre-release testing through publication on [Artifact Hub](https://artifacthub.io/packages/search?repo=graylog2).
It is intended for chart maintainers.

## Summary

Releases are **version-driven** and automated by
[`helm/chart-releaser-action`](https://github.com/helm/chart-releaser-action),
configured in [`.github/workflows/release.yaml`](../.github/workflows/release.yaml).

The flow is:

1. (manual) Chart owners sync and approve a new release. They
    - Make sure `appVersion` has been bumped to the latest available version of Graylog in an earlier PR.
    - Make sure other dependencies/image tags have been upgraded to the latest working version.
    - Approve existing README.md language, content, and structure.
2. (manual) A `Make release <version>` commit lands on `main` via PR.
    - The commit updates `version` to `<version>` in `charts/graylog/Chart.yaml`
3. (automated) The release workflow triggers automatically (it can also be triggered manually via `workflow_dispatch`).
4. (automated) `chart-releaser` packages the chart, creates a GitHub release and a git tag
   named `graylog-<version>`, and updates `index.yaml` on the `gh-pages` branch.
5. (automated) Artifact Hub polls `gh-pages` and picks up the new version.

> [!IMPORTANT]
> `chart-releaser` only creates a release for a chart version that does **not**
> already have a matching tag. The release commit is the commit that bumps `version:` in `Chart.yaml`.
> **It should be the last change to land before the release**. If the version is unchanged, the workflow skips it as
> a no-op (it does not re-release).

Publication metadata lives on the `gh-pages` branch, not `main`:

- `index.yaml` — the Helm repository index (what `helm repo add` reads).
- `artifacthub-repo.yml` — Artifact Hub ownership/repository metadata.

## Who can make a new release?

Releases can be made only by contributors that fulfill the following conditions:

- Have write access to the `Graylog2/graylog-helm` repository.
- Are able to approve merges to the `main` branch.
- Listed as an owner in `artifacthub-repo.yml` on `gh-pages`.

## Versioning

The chart carries two independent versions in `charts/graylog/Chart.yaml`:

| Field        | Meaning                                          | Versioning scheme |
|--------------|--------------------------------------------------|-------------------|
| `version`    | The **chart** version. Drives the release.       | [SemVer](https://semver.org/) |
| `appVersion` | The bundled **Graylog application** version.     | Tracks Graylog    |

Bump `version` according to SemVer:

- **Major**: breaking changes to values, defaults, or required Kubernetes/Helm versions.
- **Minor**: new features or values, backward compatible.
- **Patch**: bug fixes and documentation-only changes.

> [!NOTE]
> When the bundled Graylog version changes, `appVersion` is **not** the only field to update.
> Also review, in the same `Chart.yaml`:
> - the image tags in the `artifacthub.io/images` annotation (`graylog/graylog`, `graylog/graylog-datanode`)
> - the version tag in the `icon:` URL.

## Release Steps

### Step 1: E2E Testing

Run the **Full Test** tier from [TESTING.md](TESTING.md#full-test-major-changes-releases)
on all the following environments:

- a local MicroK8s cluster
- an AWS EKS cluster (`--set provider=aws`)

**Expected:** all phases pass on both clusters.

### Step 2: Drift Check

Confirm the three value surfaces agree. These are maintained manually and drift easily:

| Source                                   | Check                                             |
|------------------------------------------|---------------------------------------------------|
| `charts/graylog/values.yaml`             | Source of truth for defaults                      |
| `charts/graylog/values.schema.json`      | Every value is represented; types/defaults match  |
| `charts/graylog/README.md` values table  | The [Values Reference](../charts/graylog/README.md#graylog-helm-chart-values-reference) section reflects current keys, defaults, and descriptions |

**Expected:** a new/changed/removed value in `values.yaml` is reflected in both the
schema and the README values reference, with matching defaults.

### Step 3: Security Scan (optional)

Public security scanning is disabled for this repository on Artifact Hub, so scan the
bundled images locally before release:

```sh
trivy image graylog/graylog:<appVersion>
trivy image graylog/graylog-datanode:<appVersion>
trivy config ./charts/graylog
```

**Expected:** no unexpected new HIGH/CRITICAL findings versus the previous release.

### Step 4: Update `Chart.yaml`

In `charts/graylog/Chart.yaml`:

1. Bump `version` (see [Versioning](#versioning)).
2. Confirm `appVersion`, the image tags in the `artifacthub.io/images` annotation, and
   the `icon:` URL are already correct (bumped in an earlier PR).
3. Replace the `artifacthub.io/changes` annotation with the changelog for the new release.
   Use the existing `kind`/`description`/`links` structure, for example:

   ```yaml
   artifacthub.io/changes: |
     - kind: added
       description: "Short summary of the change"
       links:
         - name: "PR title"
           url: "https://github.com/Graylog2/graylog-helm/pull/<n>"
   ```

   Valid `kind` values are `added`, `changed`, `deprecated`, `removed`, `fixed`, `security`.
4. Set `artifacthub.io/containsSecurityUpdates` and `artifacthub.io/prerelease` appropriately for this release.

### Step 5: Cut the Release

Land the `Chart.yaml` change on `main` via a merged PR. This is the release trigger.

The workflow will:

- package the chart into `graylog-<version>.tgz`,
- create GitHub release + tag `graylog-<version>`,
- commit the updated `index.yaml` to `gh-pages`.

You can also start it manually from the **Actions** tab
(**Release Graylog Chart** → **Run workflow**), but the version must still be new.

### Step 6: Verify Publication

```sh
# 1. GitHub release + tag exist for the new version
gh release view "graylog-<version>" --repo Graylog2/graylog-helm

# 2. gh-pages index.yaml lists the new version
gh api "repos/Graylog2/graylog-helm/contents/index.yaml?ref=gh-pages" \
  --jq '.content' | base64 -d | grep -A2 "version: <version>"

# 3. The chart is pullable from the published repo
helm repo add graylog https://graylog2.github.io/graylog-helm
helm repo update
helm search repo graylog/graylog --versions | head
```

Finally, check the
[Artifact Hub package page](https://artifacthub.io/packages/helm/graylog2/graylog):

- the new version appears. Artifact Hub polls `gh-pages` periodically (check the next polling cycle on the settings page)
- the changelog from `artifacthub.io/changes` renders correctly

---

## Release Checklist

```markdown
## Release Checklist

### Pre-release testing (TESTING.md Full Test)
- [ ] Full Test passes on local MicroK8s
- [ ] Full Test passes on AWS EKS
- [ ] Upgrade from the currently released version succeeds

### Drift check
- [ ] `values.yaml` and `values.schema.json` in sync
- [ ] README "Values Reference" table in sync with `values.yaml`

### Security (optional)
- [ ] trivy scan of graylog / graylog-datanode images reviewed
- [ ] trivy scan of local chart reviewed

### Chart.yaml
- [ ] `version` bumped (SemVer)
- [ ] image tags and icon URL bumped (if Graylog version changed)
- [ ] `appVersion` already has the correct version (if Graylog version changed)
- [ ] `artifacthub.io/changes` changelog replaced for this release
- [ ] `containsSecurityUpdates` / `prerelease` flags set correctly

### Release
- [ ] `Chart.yaml` change merged to main
- [ ] Release workflow succeeded

### Verify publication
- [ ] GitHub release + tag graylog-<version> created
- [ ] `index.yaml` lists the new version in `gh-pages`
- [ ] Chart pullable via helm repo (`helm search repo`)
- [ ] Artifact Hub shows the new version and renders the changelog
```

---

## Additional Resources

- [TESTING.md](TESTING.md) — pre-release testing procedure
- [CONTRIBUTING.md](../CONTRIBUTING.md) — development setup and workflow
- [chart-releaser-action](https://github.com/helm/chart-releaser-action) — the release automation
