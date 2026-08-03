#!/bin/sh
# Behavioural tests for the data-volume initialization logic in
# templates/config/init-graylog.yaml (J-04).
#
# The helm-unittest suite (tests/init_graylog_test.yaml) asserts on the *rendered*
# script text: that the sentinel is the marker, that the lock survives only as an
# elif, that the copy is guarded. None of that can tell you whether an existing
# volume gets clobbered on the first upgrade — which is the actual risk in this
# change, because volumes initialized by earlier chart versions carry the journal
# lock and no marker.
#
# So this renders the real script and runs it against fixture volumes.
#
# Run it:
#   sh charts/graylog/tests/scripts/init-graylog-behavior-test.sh
#   sh charts/graylog/tests/scripts/init-graylog-behavior-test.sh -v   # show output
#
# Two substitutions, and only two
# ------------------------------
# The script hardcodes /mnt/data (the volume) and /usr/share/graylog/data (the
# image defaults). Both are rewritten to temp directories so the script can run
# unprivileged. Everything else — the branch structure, the copy, the marker, the
# exit code — is the rendered article.
#
# Requires helm on PATH. Renders with default values, which yields the init
# sequence plus the MongoDB credentials check; GRAYLOG_MONGODB_URI is exported so
# that final check passes and does not mask the exit code under test.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CHART_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

command -v helm >/dev/null 2>&1 || { echo "FATAL: helm not on PATH" >&2; exit 1; }

WORK=$(mktemp -d 2>/dev/null) || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${WORK}"' EXIT
trap 'rm -rf "${WORK}"; exit 130' INT TERM

# ---- render the real init script ---------------------------------------------
# Pulled out of the ConfigMap by the same key the pod mounts. sed rather than a
# YAML parser to keep this dependency-free; the data key is a literal block scalar
# indented by 4, so stripping that indent reproduces the file verbatim.
RENDERED="${WORK}/init-script.rendered.sh"
helm template graylog "${CHART_DIR}" \
  --set graylog.config.rootPassword=behavior-test \
  > "${WORK}/all.yaml" 2>"${WORK}/helm.err" || {
    echo "FATAL: helm template failed" >&2; cat "${WORK}/helm.err" >&2; exit 1; }

awk '
  /^  init-script\.sh: \|$/ { grab=1; next }
  grab && /^    / { sub(/^    /, ""); print; next }
  grab && /^[[:space:]]*$/ { print ""; next }
  grab { exit }
' "${WORK}/all.yaml" > "${RENDERED}"

if [ ! -s "${RENDERED}" ]; then
  echo "FATAL: could not extract init-script.sh from the rendered chart" >&2
  exit 1
fi
grep -q '\.initialized' "${RENDERED}" || {
  echo "FATAL: extracted script has no .initialized logic - extraction is wrong" >&2
  sed -n 1,15p "${RENDERED}" >&2
  exit 1
}

# ---- fixtures ----------------------------------------------------------------
# The image's default data dir. Real Graylog images ship config/contentpacks/etc;
# the exact contents don't matter, only that the copy is observable.
IMAGE="${WORK}/image-data"
mkdir -p "${IMAGE}/config" "${IMAGE}/contentpacks"
echo "image-default" > "${IMAGE}/config/graylog.conf"
echo "image-default" > "${IMAGE}/contentpacks/pack.json"

PASS=0
FAIL=0
FAILED_NAMES=""

ok()  { PASS=$(( PASS + 1 )); printf '  ok   %s\n' "$1"; }
bad() {
  FAIL=$(( FAIL + 1 ))
  FAILED_NAMES="${FAILED_NAMES}
  - ${NAME}: $1"
  printf '  FAIL %s\n' "$1"
  [ "${VERBOSE}" = "1" ] && sed 's/^/       | /' "${OUT}"
}

SCENARIO_N=0
# begin <name> — fresh empty volume for the scenario.
begin() {
  SCENARIO_N=$(( SCENARIO_N + 1 ))
  NAME="$1"
  VOL="${WORK}/vol${SCENARIO_N}"
  OUT="${WORK}/vol${SCENARIO_N}.out"
  mkdir -p "${VOL}"
  printf '\n%s\n' "${SCENARIO_N}. ${NAME}"
}

# run — executes the rendered script against this scenario's volume.
run() {
  sed -e "s#/mnt/data#${VOL}#g" -e "s#/usr/share/graylog/data#${IMAGE}#g" \
    "${RENDERED}" > "${WORK}/run.sh"
  GRAYLOG_MONGODB_URI="mongodb://user:pass@host:27017/graylog" \
    sh "${WORK}/run.sh" > "${OUT}" 2>&1
  RC=$?
}

expect()    { if grep -qF -- "$1" "${OUT}"; then ok "says: $1"; else bad "missing: $1"; fi }
refute()    { if grep -qF -- "$1" "${OUT}"; then bad "must not say: $1"; else ok "silent on: $1"; fi }
expect_rc() { if [ "${RC}" = "$1" ]; then ok "exit ${RC}"; else bad "exit ${RC}, wanted $1"; fi }
exists()    { if [ -e "${VOL}/$1" ]; then ok "volume has $1"; else bad "volume missing $1"; fi }
absent()    { if [ -e "${VOL}/$1" ]; then bad "volume should not have $1"; else ok "volume lacks $1"; fi }
# content <relpath> <expected> — the file's contents, for detecting a clobber.
content() {
  actual=$(cat "${VOL}/$1" 2>/dev/null)
  if [ "${actual}" = "$2" ]; then ok "$1 == '$2'"; else bad "$1 == '${actual}', wanted '$2'"; fi
}

echo "init-graylog data-volume initialization: behavioural tests"
echo "rendered from: ${CHART_DIR}"

# =============================================================================
begin "a fresh volume is initialized and marked"
run
expect_rc 0
expect "Initializing data volume."
exists "config/graylog.conf"
exists ".initialized"
content "config/graylog.conf" "image-default"

# =============================================================================
begin "an already-marked volume is left alone"
touch "${VOL}/.initialized"
mkdir -p "${VOL}/config"
echo "live-data" > "${VOL}/config/graylog.conf"
run
expect_rc 0
expect "Data volume already initialized, skipping copy."
refute "Initializing data volume."
# The decisive assertion: local edits survive.
content "config/graylog.conf" "live-data"

# =============================================================================
# The upgrade path. Volumes initialized by earlier chart versions carry the
# journal lock and no marker. Re-running the copy here would overwrite a live
# volume with image defaults - the exact clobbering J-04 exists to prevent,
# triggered by the fix for it.
begin "a legacy volume with the journal lock is adopted, not clobbered"
mkdir -p "${VOL}/journal" "${VOL}/config"
touch "${VOL}/journal/.lock"
echo "0000000000000000042.log" > "${VOL}/journal/segment.log"
echo "live-data" > "${VOL}/config/graylog.conf"
echo "node-id-abc123" > "${VOL}/node-id"
run
expect_rc 0
expect "initialized by an earlier chart version"
refute "Initializing data volume."
content "config/graylog.conf" "live-data"
content "node-id" "node-id-abc123"
exists "journal/segment.log"
# ...and it is stamped, so the adoption happens exactly once.
exists ".initialized"

# =============================================================================
begin "an adopted legacy volume is skipped on the next restart"
mkdir -p "${VOL}/journal" "${VOL}/config"
touch "${VOL}/journal/.lock"
echo "live-data" > "${VOL}/config/graylog.conf"
run                                  # first boot after upgrade: adopts
expect "initialized by an earlier chart version"
run                                  # second boot: marker present
expect "Data volume already initialized, skipping copy."
refute "initialized by an earlier chart version"
content "config/graylog.conf" "live-data"

# =============================================================================
# The old sentinel's actual bug: no journal means no lock, so every restart
# re-ran the copy. Under the new logic such a volume is copied once more and then
# marked, so it self-heals instead of recurring forever.
begin "a legacy volume with no journal self-heals after one copy"
mkdir -p "${VOL}/config"
echo "live-data" > "${VOL}/config/graylog.conf"
run                                  # no marker, no lock -> copies (as before)
expect "Initializing data volume."
exists ".initialized"
run                                  # ...but only once
expect "Data volume already initialized, skipping copy."
refute "Initializing data volume."

# =============================================================================
# The regression J-04 is really about: initialization must not track journal
# state. A marked volume with the journal removed entirely must still be skipped.
begin "removing the journal does not re-trigger initialization"
touch "${VOL}/.initialized"
mkdir -p "${VOL}/config"
echo "live-data" > "${VOL}/config/graylog.conf"
run
expect_rc 0
expect "Data volume already initialized, skipping copy."
content "config/graylog.conf" "live-data"
absent "journal/.lock"

# =============================================================================
begin "deleting the marker forces a deliberate re-initialization"
touch "${VOL}/.initialized"
run
expect "already initialized"
rm -f "${VOL}/.initialized"
run
expect "Initializing data volume."
exists ".initialized"

# =============================================================================
# A partial copy must not be stamped as done, or the volume is permanently broken
# and never retried. Simulated by making the volume unwritable so cp fails.
begin "a failed copy is not marked initialized"
if [ "$(id -u)" = "0" ]; then
  printf '  skip root bypasses the mode bits this scenario relies on\n'
else
chmod 500 "${VOL}"
run
chmod 700 "${VOL}"
if [ "${RC}" = "0" ]; then
  bad "exit 0 after a failed copy, wanted non-zero"
else
  ok "exit ${RC} (non-zero on copy failure)"
fi
expect "failed to copy the default data directory"
absent ".initialized"
fi

# =============================================================================
printf '\n---\n'
printf '%d passed, %d failed\n' "${PASS}" "${FAIL}"
if [ "${FAIL}" != "0" ]; then
  printf 'failures:%s\n' "${FAILED_NAMES}"
  [ "${VERBOSE}" = "0" ] && printf '\nre-run with -v to see the script output for each failure\n'
  exit 1
fi
exit 0
