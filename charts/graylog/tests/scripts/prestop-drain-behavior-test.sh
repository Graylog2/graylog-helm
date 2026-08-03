#!/bin/sh
# Behavioural tests for files/scripts/prestop-drain.sh.
#
# The helm-unittest suite (tests/prestop_drain_test.yaml) asserts on the
# *rendered* hook: that the lifecycle block exists, that the budget arithmetic is
# right, that no debug `sleep` survived. It cannot tell whether the script
# actually drains anything - a `matchRegex` for "gl_journal_entries_uncommitted"
# passes whether or not the awk can match that gauge in real exporter output.
#
# So this runs the real script, unmodified, and asserts on what it decides.
#
# Run it:
#   sh charts/graylog/tests/scripts/prestop-drain-behavior-test.sh
#   sh charts/graylog/tests/scripts/prestop-drain-behavior-test.sh -v   # show output of failures
#
# How the exporter is faked
# -------------------------
# A stub `curl` is placed first on PATH. It serves one scripted /metrics
# response per invocation, so poll N of the drain loop sees sample N - no HTTP
# server, no timing races, no sleeps to tune. Invocation 1 is always the
# preflight scrape. Once the script runs off the end of a scenario's samples the
# stub keeps serving the last one, which is what lets a 5-sample fixture drive a
# stall or a timeout.
#
# Stubbing curl is the only substitution: every other line of the script - the
# awk parsing, the zero-confirmation streak, the stall detector, the feasibility
# projection, the verdict arithmetic - executes for real. What this deliberately
# does NOT cover is whether the real curl invocation is correct (its flags, the
# --max-time behaviour, HTTP error handling); that boundary is the stub.
#
# Scenarios run with poll/settle intervals of 0 so the suite finishes in about a
# second. Two scenarios that need a measurable rate window use real 1s polls and
# are marked accordingly.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CHART_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
DRAIN="${CHART_DIR}/files/scripts/prestop-drain.sh"

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

if [ ! -f "${DRAIN}" ]; then
  echo "FATAL: cannot find ${DRAIN}" >&2
  exit 1
fi

WORK=$(mktemp -d 2>/dev/null) || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${WORK}"' EXIT
trap 'rm -rf "${WORK}"; exit 130' INT TERM

# ---- the fake exporter -------------------------------------------------------
mkdir -p "${WORK}/bin"
cat > "${WORK}/bin/curl" <<'STUB'
#!/bin/sh
# Stub curl: serves ${GL_TEST_FIXTURES}/<n> on the nth invocation, ignoring all
# arguments. A fixture whose content is the single word FAIL exits non-zero,
# which is how an unreachable exporter is simulated. Past the end of the
# sequence the last fixture repeats, so a short fixture list can still drive a
# stall or a timeout.
set -u
n=$(cat "${GL_TEST_COUNTER}")
n=$(( n + 1 ))
echo "${n}" > "${GL_TEST_COUNTER}"
f="${GL_TEST_FIXTURES}/${n}"
if [ ! -f "${f}" ]; then
  last=$(ls "${GL_TEST_FIXTURES}" | sort -n | tail -1)
  f="${GL_TEST_FIXTURES}/${last}"
fi
if [ "$(cat "${f}")" = "FAIL" ]; then
  echo "curl: (7) Failed to connect to 127.0.0.1 port 9833" >&2
  exit 7
fi
cat "${f}"
STUB
chmod +x "${WORK}/bin/curl"

PASS=0
FAIL=0
FAILED_NAMES=""

# ---- scenario construction ---------------------------------------------------
SCENARIO_N=0
SHAPE=labeled

# begin <name> — starts a scenario and resets its config to the fast defaults.
begin() {
  SCENARIO_N=$(( SCENARIO_N + 1 ))
  NAME="$1"
  FX="${WORK}/s${SCENARIO_N}"
  OUT="${WORK}/s${SCENARIO_N}.out"
  mkdir -p "${FX}"
  SAMPLE_N=0
  SHAPE=labeled
  # Zero poll/settle keeps the suite fast. GRACE-RESERVE is the real deadline,
  # so 60s of headroom means no scenario ends by timeout unless it asks to.
  E_BUDGET=60; E_POLL=0; E_SETTLE=0; E_STALL=10; E_STATUS=0
  E_CONFIRM=3; E_RETRIES=3; E_GRACE=60; E_RESERVE=0; E_WARMUP=0
}

# sample <depth> [rate] [size] [limit] — appends one scripted /metrics response.
#
# The decoy gauges are the point of the last two lines: gl_dataLakeJournal_* and
# the kafka gauge must not be read as the journal depth, and gl_journal_size must
# not pick up gl_journal_size_limit's value (it is a strict prefix of it).
sample() {
  SAMPLE_N=$(( SAMPLE_N + 1 ))
  _d="$1"; _r="${2:-100}"; _z="${3:-1048576}"; _l="${4:-5368709120}"
  case "${SHAPE}" in
    labeled)   _sfx='{node="a1b2c3d4-0000-0000-0000-000000000000",}' ;;
    unlabeled) _sfx='' ;;
    *) echo "FATAL: bad shape ${SHAPE}" >&2; exit 1 ;;
  esac
  cat > "${FX}/${SAMPLE_N}" <<EOF
# HELP gl_journal_entries_uncommitted Generated from Dropwizard metric import
# TYPE gl_journal_entries_uncommitted gauge
gl_journal_entries_uncommitted${_sfx} ${_d}
gl_journal_append_1_sec_rate${_sfx} ${_r}
gl_journal_size${_sfx} ${_z}
gl_journal_size_limit${_sfx} ${_l}
gl_dataLakeJournal_entries_uncommitted${_sfx} 7777777
gl_journal_kafka_entries_uncommitted${_sfx} 8888888
EOF
}

# unreachable — appends one scrape that fails.
unreachable() {
  SAMPLE_N=$(( SAMPLE_N + 1 ))
  echo FAIL > "${FX}/${SAMPLE_N}"
}

# run — executes the drain script against the scenario's fixtures.
run() {
  echo 0 > "${FX}.counter"
  GL_TEST_FIXTURES="${FX}" \
  GL_TEST_COUNTER="${FX}.counter" \
  PATH="${WORK}/bin:${PATH}" \
  GL_DRAIN_METRICS_URL="http://127.0.0.1:9833/metrics" \
  GL_DRAIN_BUDGET_SECONDS="${E_BUDGET}" \
  GL_DRAIN_POLL_SECONDS="${E_POLL}" \
  GL_DRAIN_SETTLE_SECONDS="${E_SETTLE}" \
  GL_DRAIN_STALL_POLLS="${E_STALL}" \
  GL_DRAIN_STATUS_INTERVAL_SECONDS="${E_STATUS}" \
  GL_DRAIN_CONFIRM_POLLS="${E_CONFIRM}" \
  GL_DRAIN_METRICS_RETRIES="${E_RETRIES}" \
  GL_DRAIN_GRACE_SECONDS="${E_GRACE}" \
  GL_DRAIN_RESERVE_SECONDS="${E_RESERVE}" \
  GL_DRAIN_FEASIBILITY_WARMUP_POLLS="${E_WARMUP}" \
  HOSTNAME="graylog-app-2" \
    sh "${DRAIN}" > "${OUT}" 2>&1
  RC=$?
}

# ---- assertions --------------------------------------------------------------
ok()   { PASS=$(( PASS + 1 )); printf '  ok   %s\n' "$1"; }
bad()  {
  FAIL=$(( FAIL + 1 ))
  FAILED_NAMES="${FAILED_NAMES}
  - ${NAME}: $1"
  printf '  FAIL %s\n' "$1"
  if [ "${VERBOSE}" = "1" ]; then
    sed 's/^/       | /' "${OUT}"
  fi
}

# expect <literal substring> — the drain must have said this.
expect() {
  if grep -qF -- "$1" "${OUT}"; then ok "says: $1"; else bad "missing: $1"; fi
}
# refute <literal substring> — the drain must NOT have said this.
refute() {
  if grep -qF -- "$1" "${OUT}"; then bad "must not say: $1"; else ok "silent on: $1"; fi
}
# expect_rc <code>
expect_rc() {
  if [ "${RC}" = "$1" ]; then ok "exit ${RC}"; else bad "exit ${RC}, wanted $1"; fi
}
# expect_before <a> <b> — a must appear earlier in the log than b.
expect_before() {
  _la=$(grep -nF -- "$1" "${OUT}" | head -1 | cut -d: -f1)
  _lb=$(grep -nF -- "$2" "${OUT}" | head -1 | cut -d: -f1)
  if [ -n "${_la}" ] && [ -n "${_lb}" ] && [ "${_la}" -lt "${_lb}" ]; then
    ok "'$1' precedes '$2'"
  else
    bad "'$1' (line ${_la:-none}) should precede '$2' (line ${_lb:-none})"
  fi
}

header() { printf '\n%s\n' "$1"; }

echo "prestop-drain.sh behavioural tests"
echo "script under test: ${DRAIN}"

# =============================================================================
header "1. a journal that drains to zero reports SUCCESS"
begin "clean drain"
sample 500; sample 300; sample 120; sample 0; sample 0; sample 0
run
expect_rc 0
expect "RESULT: SUCCESS - journal fully drained (0 messages remaining)"
expect "depth held at 0 across 3 consecutive polls"
expect "drained 100% of the starting backlog (500 -> 0 messages)"
# A drained journal must not warn about stranding anything on the PVC.
refute "will be stranded in its PVC"

# =============================================================================
header "2. gauges without labels are still readable"
# The awk in sample() matches on '^name[{ ]' or index(\$1, name\"{\")==1. awk
# splits on whitespace, so \$1 can never contain a space - which makes the
# space branch unreachable and a match conditional on a '{' following the name.
# An exporter that publishes these gauges bare would therefore be unreadable and
# the hook would no-op with RESULT: UNKNOWN. Both shapes must work.
begin "unlabeled gauges"
SHAPE=unlabeled
sample 500; sample 200; sample 0; sample 0; sample 0
run
expect_rc 0
expect "RESULT: SUCCESS - journal fully drained (0 messages remaining)"
refute "RESULT: UNKNOWN"

# =============================================================================
header "3. decoy gauges are not mistaken for the journal's"
# gl_journal_size is a strict prefix of gl_journal_size_limit, and the data-lake
# and kafka gauges are spelled similarly to the depth gauge. A misread here
# would silently report the wrong backlog or the wrong disk figure.
begin "gauge anchoring"
sample 500 100 1073741824 2147483648
sample 0;  sample 0; sample 0
run
expect_rc 0
# 1GiB of a 2GiB cap = 50%. If SIZE had picked up LIMIT this would read 100%.
expect "journal on disk: 1.0GiB of 2.0GiB cap (50% full)"
# 7777777 / 8888888 are the decoys; the real depth is 500.
expect "journal at start: 500 messages on disk awaiting processing"
refute "7777777"
refute "8888888"

# =============================================================================
header "4. a momentary zero under live ingest is not success"
begin "zero blip"
sample 400
sample 0     # depth touches zero while messages are still arriving
sample 250   # ...and immediately pops back
sample 100; sample 0; sample 0; sample 0
run
expect_rc 0
expect "depth is 0 (confirmation 1/3)"
expect "depth rose back to 250 after 1 zero reading(s)"
# It must reach the real conclusion only after the confirmed streak.
expect "RESULT: SUCCESS"
expect_before "depth rose back to 250" "RESULT: SUCCESS"

# =============================================================================
header "5. a zero blip does not abort a drain that is still working"
# When depth pops back off zero the script resets `best` so later readings can
# still register as new lows - its own comment says this exists to stop the
# stall counter reporting INCOMPLETE "while the drain was in fact still
# working". The accumulated `stall` count has to be reset for that to hold.
begin "zero blip mid-stall"
E_STALL=4
sample 100
sample 60    # first loop poll: best=60, stall=1
sample 60    # stall=2
sample 60    # stall=3  (one short of the limit)
sample 0     # zero_streak=1
sample 55    # rose back: best=55. Genuine progress from 60.
sample 50; sample 40; sample 20; sample 0; sample 0; sample 0
run
expect_rc 0
expect "RESULT: SUCCESS"
refute "RESULT: INCOMPLETE"

# =============================================================================
header "6. a journal that stops falling reports INCOMPLETE"
begin "stalled"
E_STALL=3
sample 800 250
run
expect_rc 0
expect "RESULT: INCOMPLETE"
expect "no longer decreasing"
expect "the write side never stopped"
expect "no new low in 3 polls"
# Stalling on a scale-in is exactly when the operator needs the PVC warning.
expect "will be stranded in its PVC - nothing replays an orphaned journal"

# =============================================================================
header "7. feasibility gate: a journal that is not draining at all aborts"
begin "infeasible - flat"
E_WARMUP=3
sample 1000000 5000
sample 1000000; sample 1010000; sample 1020000
run
expect_rc 0
expect "FEASIBILITY: journal is NOT draining"
expect "time to clear:   never at this rate"
expect "drain rate:      0 msg/s - nothing is being worked off"
expect "RESULT: ABORTED - drain is not feasible"
expect "read-only index block or a disk watermark"
expect "stop the inputs and drain manually to save them"

# =============================================================================
header "8. feasibility gate: a drain too slow to finish aborts with an ETA"
begin "infeasible - too slow"
E_WARMUP=3
E_GRACE=60; E_RESERVE=0; E_BUDGET=60
sample 1000000 5000
sample 1000000; sample 999900; sample 999800
run
expect_rc 0
expect "FEASIBILITY: drain cannot finish in the time available"
expect "RESULT: ABORTED - drain is not feasible"
expect "short by:"
# Must hand the unused grace period back rather than sit on it.
expect "returning the rest of the grace period to Graylog's own shutdown"

# =============================================================================
header "9. feasibility gate: a viable drain passes and completes"
begin "feasible"
E_WARMUP=3
sample 1000
sample 800; sample 500; sample 200; sample 0; sample 0; sample 0
run
expect_rc 0
expect "feasibility OK:"
expect "RESULT: SUCCESS"
refute "RESULT: ABORTED"

# =============================================================================
header "10. feasibilityWarmupPolls=0 disables the projection"
begin "feasibility disabled"
E_WARMUP=0
E_STALL=3
sample 1000000 5000
sample 1000000
run
expect_rc 0
expect "feasibility: projection disabled (feasibilityWarmupPolls=0)"
refute "FEASIBILITY:"
# Without the projection the only backstop is the stall detector.
expect "RESULT: INCOMPLETE"

# =============================================================================
header "11. a sub-1-msg/s drain does not divide by zero"
# drain_rate floors to 0 msg/s for anything slower than one message per second.
# The ETA is computed as n*observed/cleared rather than n/drain_rate precisely
# so that 0 never reaches a divisor; `$(( n / 0 ))` would abort the hook
# mid-shutdown.
#
# Needs a real poll interval to make the rate window measurable. One message
# cleared across a >=2s window is what floors the integer division to 0 - with
# 1s polls the window lands on either side of a second boundary and the rate
# comes out 1 or 2 depending on timing, which made this flaky.
begin "sub-1 msg/s"
E_WARMUP=2
E_POLL=2
sample 900000 5000
sample 900000; sample 899999
run
expect_rc 0
expect "drain rate:      0 msg/s"
expect "RESULT: ABORTED"
refute "divide by zero"
refute "division by 0"

# =============================================================================
header "12. a journal at its size cap is called out explicitly"
begin "at cap"
E_WARMUP=3
# The cap has to be on every sample, not just preflight: report_journal_state
# reads the most recent parse, so a fixture that only caps the first sample
# reports the cap at preflight and then a stale-looking 0% in the verdict.
sample 2000000 7000 5368709120 5368709120
sample 2000000 7000 5368709120 5368709120
sample 2000000 7000 5368709120 5368709120
sample 2000000 7000 5368709120 5368709120
run
expect_rc 0
# Reported once at preflight and again in the verdict.
expect "journal on disk: 5.0GiB of 5.0GiB cap (100% full)"
expect "the journal is AT its cap"
expect "messages are being lost right now"

# =============================================================================
header "13. an unreachable exporter at preflight attempts no drain"
begin "preflight unreachable"
E_RETRIES=3
unreachable
run
expect_rc 0
expect "RESULT: UNKNOWN - no drain attempted; journal depth was never measurable"
expect "did not answer after 3 attempts"
# It must not claim to have waited for endpoints or drained anything.
refute "waiting 0s for EndpointSlice removal"
refute "drained"

# =============================================================================
header "14. a transient scrape failure is retried, not fatal"
begin "retry recovers"
E_RETRIES=5
unreachable; unreachable   # two blips at preflight...
sample 300                 # ...then the exporter answers
sample 0; sample 0; sample 0
run
expect_rc 0
expect "metrics probe failed (attempt 1/5)"
expect "metrics probe recovered on attempt 3"
expect "RESULT: SUCCESS"

# =============================================================================
header "15. losing the exporter mid-drain abandons rather than lies"
begin "lost mid-drain"
E_RETRIES=2
sample 500      # preflight fine
sample 400      # draining
unreachable     # and then gone for good
run
expect_rc 0
expect "RESULT: UNKNOWN - drain abandoned; journal depth stopped being measurable"
expect "metrics endpoint stopped answering"
refute "RESULT: SUCCESS"

# =============================================================================
header "16. an already-empty journal short-circuits"
begin "already empty"
sample 0
run
expect_rc 0
expect "journal already empty before the settle wait"
expect "RESULT: SUCCESS"
expect "drained n/a - the journal was already empty when the hook began"

# =============================================================================
header "17. exhausting the budget reports the timeout, not success"
# GRACE - RESERVE = 0 puts the deadline at the hook's start, so the loop is
# never entered - the deterministic way to reach the timeout verdict.
begin "timeout"
E_GRACE=1; E_RESERVE=1; E_BUDGET=0
sample 750
run
expect_rc 0
expect "RESULT: INCOMPLETE - 0s timeout cutoff reached with 750 messages still undrained"
expect "will be stranded in its PVC"
refute "RESULT: SUCCESS"

# =============================================================================
header "18. a journal that grows is reported as no progress, not negative"
begin "backlog grew"
E_STALL=3
sample 100 500
sample 200; sample 300; sample 400
run
expect_rc 0
expect "drained 0% of the starting backlog - it grew from 100 to 400 messages"

# =============================================================================
header "19. the verdict's phase breakdown sums to the total"
begin "phase accounting"
sample 50; sample 0; sample 0; sample 0
run
expect_rc 0
# Preflight + settle + draining, all measured. A preflight-only exit must not
# claim a settle it never waited.
expect "s total (0s preflight + 0s settle + 0s draining)"
expect "handing over to SIGTERM with"
expect "guaranteed floor was 0s"

begin "phase accounting - preflight exit"
unreachable
run
expect_rc 0
expect "before the settle wait began"
refute "settle + "

# =============================================================================
header "20. a missing configuration variable fails loudly"
# Every GL_DRAIN_* is read with ${VAR:?} so an incomplete environment aborts at
# the top instead of defaulting to empty and producing nonsense arithmetic.
# This is the one path that is allowed to exit non-zero.
begin "missing env"
sample 100
echo 0 > "${FX}.counter"
GL_TEST_FIXTURES="${FX}" GL_TEST_COUNTER="${FX}.counter" \
PATH="${WORK}/bin:${PATH}" \
GL_DRAIN_METRICS_URL="http://127.0.0.1:9833/metrics" \
  sh "${DRAIN}" > "${OUT}" 2>&1
RC=$?
if [ "${RC}" != "0" ]; then ok "exit ${RC} (non-zero as designed)"; else bad "exited 0 with no config"; fi
expect "GL_DRAIN_BUDGET_SECONDS"

# =============================================================================
printf '\n---\n'
printf '%d passed, %d failed\n' "${PASS}" "${FAIL}"
if [ "${FAIL}" != "0" ]; then
  printf 'failures:%s\n' "${FAILED_NAMES}"
  [ "${VERBOSE}" = "0" ] && printf '\nre-run with -v to see the drain output for each failure\n'
  exit 1
fi
exit 0
