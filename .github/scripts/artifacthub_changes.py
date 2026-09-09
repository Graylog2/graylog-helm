#!/usr/bin/env python3
"""Rewrite a chart's artifacthub.io/changes annotation from its CHANGELOG.md.

release-please renders release notes only as Markdown; no updater can write
changelog content into a YAML field. This reads the most recent section of the
chart's CHANGELOG.md and regenerates the annotation, resolving each commit back
to the pull request that introduced it so entries carry named PR links.

ArtifactHub expects the annotation to describe only the changes introduced by
this chart version, so the previous contents are replaced, not appended to.

Run at packaging time, against a checkout of the release tag, and the result is
never committed: ArtifactHub reads the annotation from the packaged tarball it
fetches through index.yaml, so CHANGELOG.md stays the single source of truth and
nothing has to race release-please's force-push of the release branch.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

# release-please changelog section -> ArtifactHub kind. ArtifactHub accepts only
# added/changed/deprecated/removed/fixed/security; "deprecated" and "security"
# have no conventional-commit equivalent and stay manual.
SECTION_KINDS = {
    "Features": "added",
    "Bug Fixes": "fixed",
    "Performance Improvements": "changed",
    "Code Refactoring": "changed",
    "Reverts": "changed",
    "Documentation": "changed",
    "Dependencies": "changed",
    "Build System": "changed",
    "Continuous Integration": "changed",
    "Miscellaneous Chores": "changed",
    "⚠ BREAKING CHANGES": "changed",
}
DEFAULT_KIND = "changed"

VERSION_HEADING = re.compile(r"^##\s+\[?(?P<version>\d+\.\d+\.\d+)")
SECTION_HEADING = re.compile(r"^###\s+(?P<title>.+?)\s*$")
ENTRY = re.compile(
    r"^\*\s+"
    r"(?:\*\*(?P<scope>[^*]+?):\*\*\s+)?"
    r"(?P<desc>.+?)"
    r"\s+\(\[(?P<sha>[0-9a-f]{7,40})\]\((?P<url>[^)]+)\)\)\s*$"
)
# Squash merges leave a trailing "(#123)" in the subject. release-please renders
# it as a markdown link, "([#123](url))", when it can resolve one. Either form is
# redundant once the entry carries a resolved PR link of its own.
TRAILING_PR = re.compile(r"\s*\((?:\[#\d+\]\([^)]*\)|#\d+)\)\s*$")


def gh_json(*args: str):
    """Run `gh` and parse its stdout as JSON, returning None on any failure."""
    try:
        out = subprocess.run(
            ("gh", *args), capture_output=True, text=True, check=True
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    if not out:
        return None
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return None


def latest_section(changelog: str) -> tuple[str | None, list[dict]]:
    """Parse entries from the topmost version section of a CHANGELOG.md."""
    version: str | None = None
    entries: list[dict] = []
    kind = DEFAULT_KIND
    in_latest = False

    for line in changelog.splitlines():
        heading = VERSION_HEADING.match(line)
        if heading:
            if in_latest:
                break  # reached the previous release; stop
            version = heading.group("version")
            in_latest = True
            continue
        if not in_latest:
            continue

        section = SECTION_HEADING.match(line)
        if section:
            kind = SECTION_KINDS.get(section.group("title"), DEFAULT_KIND)
            continue

        entry = ENTRY.match(line)
        if entry:
            desc = TRAILING_PR.sub("", entry.group("desc")).strip()
            if entry.group("scope"):
                desc = f"{entry.group('scope')}: {desc}"
            entries.append(
                {
                    "kind": kind,
                    "description": desc,
                    "sha": entry.group("sha"),
                    "commit_url": entry.group("url"),
                }
            )

    return version, entries


def resolve_link(repo: str, entry: dict) -> tuple[str, str]:
    """Return a (name, url) link for an entry, preferring its pull request."""
    pulls = gh_json(
        "api", f"repos/{repo}/commits/{entry['sha']}/pulls", "--jq", "[.[0]]"
    )
    if pulls and pulls[0] and pulls[0].get("number"):
        pr = pulls[0]
        return f"PR #{pr['number']}", pr["html_url"]
    return f"Commit {entry['sha'][:7]}", entry["commit_url"]


def yaml_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(entries: list[dict], repo: str, base_indent: str) -> str:
    """Render the annotation's block-scalar body."""
    item = base_indent + "  "
    lines: list[str] = []
    for entry in entries:
        name, url = resolve_link(repo, entry)
        lines.append(f"{item}- kind: {entry['kind']}")
        lines.append(f"{item}  description: {yaml_quote(entry['description'])}")
        lines.append(f"{item}  links:")
        lines.append(f"{item}    - name: {yaml_quote(name)}")
        lines.append(f"{item}      url: {yaml_quote(url)}")
    return "\n".join(lines)


def splice(chart_text: str, body: str) -> str:
    """Replace the artifacthub.io/changes block, preserving the rest verbatim.

    Line-based on purpose: a YAML round-trip would reflow unrelated keys.
    """
    lines = chart_text.splitlines()
    # release-please round-trips Chart.yaml through a YAML parser when it bumps
    # `version:`, and that turns an empty block scalar into `""`. Both forms mean
    # the same empty annotation, so accept either and always write the block
    # scalar back. Matching only `|` made every release fail here.
    key = re.compile(
        r"^(?P<indent>\s*)artifacthub\.io/changes:\s*(?:\||\"\"|''|)\s*$"
    )

    start = next((i for i, l in enumerate(lines) if key.match(l)), None)
    if start is None:
        raise SystemExit(
            "artifacthub.io/changes annotation not found; add the key with an "
            "empty value (`artifacthub.io/changes: |`) first"
        )

    indent = key.match(lines[start]).group("indent")
    # Normalise the key line: the body below it is a block scalar regardless of
    # which empty form we found.
    lines[start] = f"{indent}artifacthub.io/changes: |"
    end = start + 1
    while end < len(lines) and (
        not lines[end].strip() or lines[end].startswith(indent + " ")
    ):
        end += 1
    # Trailing blank lines belong to whatever follows, not to this block.
    while end > start + 1 and not lines[end - 1].strip():
        end -= 1

    return "\n".join(lines[: start + 1] + body.splitlines() + lines[end:]) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--chart-dir", required=True, help="e.g. charts/graylog")
    ap.add_argument("--repo", required=True, help="owner/name")
    ap.add_argument("--check", action="store_true", help="exit 1 if out of date")
    args = ap.parse_args()

    chart_dir = Path(args.chart_dir)
    changelog_path = chart_dir / "CHANGELOG.md"
    chart_path = chart_dir / "Chart.yaml"

    if not changelog_path.is_file():
        print(f"no {changelog_path}; nothing to sync")
        return 0

    version, entries = latest_section(changelog_path.read_text())
    if not entries:
        print(f"no parseable entries in {changelog_path}; leaving annotation as-is")
        return 0

    original = chart_path.read_text()
    updated = splice(original, render(entries, args.repo, "  "))

    if updated == original:
        print(f"{chart_path} already up to date for {version}")
        return 0
    if args.check:
        print(f"{chart_path} is out of date for {version}")
        return 1

    chart_path.write_text(updated)
    print(f"updated {chart_path} with {len(entries)} change(s) for {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
