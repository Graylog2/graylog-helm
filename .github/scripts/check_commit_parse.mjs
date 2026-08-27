#!/usr/bin/env node
/**
 * Fail when a commit message release-please should read cannot be parsed.
 *
 * release-please parses commit messages with @conventional-commits/parser, a
 * strict PEG grammar. When the grammar rejects a message the whole commit is
 * discarded with a "commit could not be parsed" line in the log, the run stays
 * green, and the change never reaches CHANGELOG.md. If the commit was the only
 * `fix:` or `feat:` in a release window, no release PR opens at all.
 *
 * That is not hypothetical. #176 shipped a `fix(mongodb):` whose body wrapped so
 * that a line began with `max(max(initContainer), sum(containers))`. The grammar
 * reads a body line starting `word(` as a `type(scope` header, the nested paren
 * fails it, and the fix was silently absent from the release.
 *
 * This script imports the same parser at the same major version release-please
 * depends on, so it agrees with release-please by construction. A Python port
 * would drift from the grammar, which is why this one file is not Python like
 * its neighbours.
 *
 * Only messages whose subject looks like a Conventional Commit are checked.
 * A subject release-please would ignore anyway, "Update README.md", cannot be
 * silently dropped, because it was never going to be read.
 *
 * Usage:
 *   node check_commit_parse.mjs --range <git range>
 *   node check_commit_parse.mjs --file <path to a message>
 *   node check_commit_parse.mjs --file - < message.txt
 */

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { parser } from "@conventional-commits/parser";

// A subject release-please will attempt to read: a single-word type, an optional
// scope, an optional breaking `!`, then ": " and a description. Deliberately
// permissive about the type, because the grammar accepts any word, not a fixed
// list.
const CONVENTIONAL_SUBJECT = /^[A-Za-z][A-Za-z0-9]*(\([^)]*\))?!?: \S/;

// The PEG parser reports "... at <line>:<column>".
const POSITION = /\bat (\d+):(\d+)/;

function check(message) {
  const normalized = message.replace(/\r\n/g, "\n").replace(/\n+$/, "\n");
  try {
    parser(normalized);
    return null;
  } catch (error) {
    const detail = String(error.message).split("\n")[0];
    const match = POSITION.exec(detail);
    if (!match) return { detail };
    const line = Number(match[1]);
    const column = Number(match[2]);
    const text = normalized.split("\n")[line - 1] ?? "";
    return { detail, line, column, text };
  }
}

function report(label, subject, failure) {
  const lines = [
    `${label}: message rejected by the Conventional Commits grammar`,
    `  subject: ${subject}`,
    `  error:   ${failure.detail}`,
  ];
  if (failure.line !== undefined) {
    lines.push(`  line ${failure.line}: ${failure.text}`);
    lines.push(`  ${" ".repeat(`line ${failure.line}: `.length + failure.column - 1)}^`);
  }
  lines.push(
    "",
    "  release-please would discard this commit and stay green. Reword the body.",
    "  Most often the cause is a line that begins with `word(`, which the grammar",
    "  reads as a `type(scope` header. The same text mid-line parses fine, so",
    "  reflowing the line is usually enough.",
  );
  return lines.join("\n");
}

function commitsIn(range) {
  // %x00 between fields, %x01 between commits: commit messages contain blank
  // lines, so no textual separator is safe.
  const raw = execFileSync(
    "git",
    ["log", "--no-merges", "--format=%H%x00%B%x01", range],
    { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  );
  return raw
    .split("\x01")
    .map((entry) => entry.replace(/^\n/, ""))
    .filter((entry) => entry.trim())
    .map((entry) => {
      const [sha, message] = entry.split("\x00");
      return { sha, message };
    });
}

function main(argv) {
  const mode = argv[0];
  const value = argv[1];
  if (!["--range", "--file"].includes(mode) || !value) {
    console.error("usage: check_commit_parse.mjs (--range <range> | --file <path|->)");
    return 2;
  }

  const subjects = [];
  if (mode === "--file") {
    const message = value === "-"
      ? readFileSync(0, "utf8")
      : readFileSync(value, "utf8");
    subjects.push({ sha: null, message });
  } else {
    subjects.push(...commitsIn(value));
  }

  const failures = [];
  let checked = 0;

  for (const { sha, message } of subjects) {
    const subject = message.split("\n", 1)[0];
    if (!CONVENTIONAL_SUBJECT.test(subject)) continue;
    checked += 1;
    const failure = check(message);
    if (failure) {
      const label = sha ? sha.slice(0, 7) : "message";
      failures.push(report(label, subject, failure));
    }
  }

  if (checked === 0) {
    console.log("no Conventional Commit messages to check");
    return 0;
  }

  for (const failure of failures) {
    console.log(`::error::${failure.split("\n")[0]}`);
    console.log(failure);
    console.log("");
  }

  if (failures.length) {
    console.log(`${failures.length} of ${checked} message(s) would be dropped`);
    return 1;
  }

  console.log(`${checked} message(s) parse cleanly`);
  return 0;
}

process.exit(main(process.argv.slice(2)));
