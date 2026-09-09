# Graylog Helm chart release guide

How a release of the Graylog Helm chart happens, and what a maintainer has to do
to cut one. Releases are commit-driven: what you write in a commit subject
decides the next version.

## Summary

[release-please](https://github.com/googleapis/release-please) reads the
Conventional Commit subjects that land on `main`, works out the next version, and
keeps a release pull request open with the version bump and the changelog. Merging
that pull request is the release.

1. A Conventional Commit pull request touching `charts/graylog/` is squash-merged to `main`.
2. release-please opens or updates `chore(main): release graylog <version>`, bumping `version:` in `Chart.yaml`, writing `charts/graylog/CHANGELOG.md`, and updating `.release-please-manifest.json`.
3. A maintainer reviews and merges that pull request. **This is the release trigger.**
4. release-please creates the tag and the GitHub release, both named `graylog-<version>`.
5. `release-graylog.yaml` generates the `artifacthub.io/changes` annotation from `CHANGELOG.md`, packages the chart, attaches the tarball to the release, and merges one entry into `index.yaml` on `gh-pages`.
6. Artifact Hub picks the version up on its next poll.

Steps 1 and 3 are the only manual ones.

Nobody edits `version:` in `Chart.yaml`, `charts/graylog/CHANGELOG.md`, or
`.release-please-manifest.json` by hand. release-please owns all three.

## What earns a release

A commit contributes to a release only when it meets both conditions.

**The subject is a releasable Conventional Commit type.** `feat:` gives a minor
bump, `fix:` and `perf:` give a patch. `ci:`, `chore:`, `docs:`, `test:`,
`refactor:` and `style:` are hidden sections: they land, they appear in no
changelog, and they trigger no release on their own.

**It touches a file under `charts/graylog/`.** Repository tooling changes never
release the chart, which is why they must use `ci:` or `chore:`.

The subject that counts is the one that lands on `main`. Squash merging is the
only merge method enabled, and the squash subject comes from the pull request
title when a branch has more than one commit. A pull request titled
`fix: correct the datanode selector` releases a patch no matter what its
individual commits said.

## Major versions and breaking changes

Add `!` after the type, or a `BREAKING CHANGE:` footer, and release-please bumps
the major and writes a `⚠ BREAKING CHANGES` section from the footer text.

```
feat(values)!: imagePullSecrets take LocalObjectReference objects

BREAKING CHANGE: global.imagePullSecrets and the per-image lists now take
{name: <secret>} objects instead of bare strings.
```

Document the change in `charts/graylog/UPGRADING.md` in the same pull request.
The changelog says what changed. `UPGRADING.md` says what the reader has to do
about it.

To set a version release-please would not have computed, put `Release-As: 2.0.0`
in the footer of a commit that touches `charts/graylog/`. Use it to correct
history, not as a substitute for marking commits breaking.

## One parser gotcha worth knowing

release-please parses commit messages with a strict PEG grammar, and it discards
whatever the grammar rejects without failing the run. The change never reaches
the changelog, and if it was the only `fix:` or `feat:` in the window, no release
pull request opens at all.

The grammar reads every body line as a possible header, so a body line that
begins with `word(` is read as `type(scope`. It survives if the parenthesis
closes on that line with nothing nested inside, and dies otherwise.

```
# breaks the parse: the line begins with a call containing a nested paren
max(max(initContainer), sum(containers)) sets the floor

# fine: the same text, not at the start of a line
a pod reserves max(max(initContainer), sum(containers))
```

This cost the 2.0.0 changelog a real chart fix, in #176. Reflowing the line is
enough to avoid it.

## Who can cut a release

- Write access to `Graylog2/graylog-helm`.
- Able to approve merges to `main`.
- Listed as an owner in `artifacthub-repo.yml` on `gh-pages`.

## Versioning

`charts/graylog/Chart.yaml` carries two independent versions.

| Field | Meaning | Owner |
|---|---|---|
| `version` | The chart version, SemVer | release-please |
| `appVersion` | The bundled Graylog version | a maintainer, in an ordinary pull request |

`graylog.image.tag` and `datanode.image.tag` default to `appVersion`, so changing
it moves the running images. When you change it, update two more fields in the
same `Chart.yaml`: the image tags in the `artifacthub.io/images` annotation, and
the version tag in the `icon:` URL.

## Cutting the release

**Test first.** Run the full pre-release procedure in [TESTING.md](TESTING.md)
against the commit the release pull request sits on. Nothing in CI gates
publication, so this is the real gate.

**Read the release pull request.** Confirm the computed version matches the
significance of what shipped, and that the changelog covers everything. A commit
the parser dropped is invisible here, so compare against the merged pull requests
in the window if the release matters.

**Edit `CHANGELOG.md` on the release pull request if you need to.** It is the
source of truth for the `artifacthub.io/changes` annotation, which the publish job
generates at packaging time. Anything you add here reaches Artifact Hub. Make it
the last change before merging: any push to `main` makes release-please
force-push the branch and discard your edit.

**Merge it.** Publication follows automatically.

## Verifying publication

```sh
# the release and its attached tarball
gh release view "graylog-<version>" -R Graylog2/graylog-helm --json tagName,assets

# the published index
curl -sS https://graylog2.github.io/graylog-helm/index.yaml \
  | yq e '.entries.graylog[] | .version + " -> " + .urls[0]' -

# the chart as a consumer sees it
helm repo add graylog https://graylog2.github.io/graylog-helm
helm repo update graylog
helm search repo graylog/graylog --versions | head
helm template graylog graylog/graylog --version <version> >/dev/null
```

Check all of the following.

- The `.tgz` is attached to the release.
- The new entry's URL is a release download URL.
- Every historical entry is still present and unchanged. Diff `index.yaml`
  against the previous revision on `gh-pages` and confirm the only change is an
  addition.
- `helm show chart graylog/graylog --version <version>` carries the
  `artifacthub.io/changes` annotation.

If `index.yaml` lost an entry or an existing URL changed, revert the `gh-pages`
commit. It is an ordinary branch with ordinary history. The publish job has a
guard that should fail before pushing in that case, so treat it as a bug.

## Troubleshooting

| Symptom | Cause |
|---|---|
| No release pull request after merging a chart change | The subject was a hidden type, or the change touched nothing under `charts/graylog/`, or the parser rejected the message |
| A merged change is missing from the changelog | Same three causes. Check the release-please run log for `could not be parsed` |
| The computed version is lower than expected | A breaking change landed without `!` or a `BREAKING CHANGE:` footer |
| The release pull request has no CI checks | Expected. Pull requests opened by `GITHUB_TOKEN` raise no `pull_request` events |
| `Chart.yaml` came back reformatted | release-please round-trips the file through a YAML parser and may rewrap long quoted strings. The parsed value is unchanged |
| The release exists but no tarball is attached | The `publish-chart` job failed or never ran. Re-run `release-graylog.yaml` by hand with the tag as input |
| Artifact Hub shows the version but no changelog | The annotation was empty at packaging time. Check `CHANGELOG.md` on the tag |

## Known gaps

- **Publication is not gated on tests.** `release-please` and `lint-and-test`
  both fire on push to `main` with no dependency between them, so a chart that
  fails `helm lint` can be tagged and published.
- **Release pull requests get no CI.** Quality gating happens on the pull
  requests feeding into `main`. A green or absent check on a release pull request
  says nothing about the chart.
- **`exclude-paths` does not work.** The config sets it for `.github` and `docs`,
  and commits touching only those paths were still attributed to the chart in
  testing. Commit type is the dependable guard.
- **Some ArtifactHub change kinds have no Conventional Commit equivalent.**
  `deprecated`, `removed` and `security` need a hand edit to `CHANGELOG.md` on
  the release pull request.

## Additional resources

- [TESTING.md](TESTING.md), the pre-release testing procedure
- [UPGRADING.md](../charts/graylog/UPGRADING.md), what users have to do between versions
- [CONTRIBUTING.md](../CONTRIBUTING.md), development setup and commit rules
- [release-please](https://github.com/googleapis/release-please), the release automation
