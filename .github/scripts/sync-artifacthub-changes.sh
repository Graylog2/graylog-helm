#!/usr/bin/env bash
# Push a regenerated artifacthub.io/changes annotation onto any open
# release-please PR. Runs after every release-please invocation because
# release-please force-pushes its branch whenever it regenerates the PR, which
# would otherwise discard the annotation commit.
set -euo pipefail

CONFIG="${CONFIG:-release-please-config.json}"
TARGET_BRANCH="${TARGET_BRANCH:-main}"
REPO="${REPO:?REPO must be set to owner/name}"

# Stash the updater outside the work tree: the checkouts below swap the tree to
# a release branch that may predate this script.
updater="$(mktemp)"
cp .github/scripts/artifacthub_changes.py "$updater"
trap 'rm -f "$updater"' EXIT

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

while IFS=$'\t' read -r path component; do
  branch="release-please--branches--${TARGET_BRANCH}"
  if [[ -n "$component" ]]; then
    branch="${branch}--components--${component}"
  fi

  pr="$(gh pr list --state open --head "$branch" --json number --jq '.[0].number // empty')"
  if [[ -z "$pr" ]]; then
    echo "== ${path}: no open release PR (branch ${branch}); skipping"
    continue
  fi

  echo "== ${path}: syncing annotation onto PR #${pr}"
  git fetch --quiet origin "$branch"
  git checkout --quiet -B "$branch" "origin/${branch}"

  python3 "$updater" --chart-dir "$path" --repo "$REPO"

  if git diff --quiet -- "${path}/Chart.yaml"; then
    echo "== ${path}: annotation already current"
    continue
  fi

  git add "${path}/Chart.yaml"
  git commit --quiet -m "chore: sync artifacthub.io/changes for ${component:-$path}"
  git push --quiet origin "$branch"
  echo "== ${path}: pushed to PR #${pr}"
done < <(jq -r '.packages | to_entries[] | [.key, (.value.component // "")] | @tsv' "$CONFIG")
