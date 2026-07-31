#!/bin/sh
# Graylog preStop journal drain.
#
# Inlined into the graylog-app container's preStop hook by
# templates/workload/containers/_prestop-drain.tpl via .Files.Get. It lives here
# rather than under templates/ for two reasons: helm lint rejects a .sh extension
# in templates/ ("Valid extensions are .yaml, .yml, .tpl, or .txt"), and keeping
# it out of there means no Helm syntax, so editors and shellcheck can read it.
#
# Everything Helm supplies arrives as environment variables, rendered onto the
# container by "graylog.prestopDrain.env" in that same file. Run it by hand
# inside a pod to test:
#
#   GL_DRAIN_METRICS_URL=http://127.0.0.1:9833/metrics \
#   GL_DRAIN_BUDGET_SECONDS=60 GL_DRAIN_POLL_SECONDS=2 \
#   GL_DRAIN_SETTLE_SECONDS=0 GL_DRAIN_STALL_POLLS=5 \
#   GL_DRAIN_STATUS_INTERVAL_SECONDS=5 GL_DRAIN_GRACE_SECONDS=300 \
#   GL_DRAIN_RESERVE_SECONDS=45 GL_DRAIN_CONFIRM_POLLS=3 \
#   GL_DRAIN_METRICS_RETRIES=5 GL_DRAIN_FEASIBILITY_WARMUP_POLLS=5 \
#   sh prestop-drain.sh
#
# Every variable is required via ${VAR:?}: a missing one fails loudly at the top
# rather than defaulting to empty and producing nonsense arithmetic further down.

# Token-free journal drain. Always exits 0: a failing preStop hook
# would stall termination for the whole grace period and then get the
# container SIGKILLed, so every give-up path here hands over to
# Graylog's own graceful shutdown instead of erroring.
set -u

URL="${GL_DRAIN_METRICS_URL:?GL_DRAIN_METRICS_URL is not set}"
BUDGET="${GL_DRAIN_BUDGET_SECONDS:?GL_DRAIN_BUDGET_SECONDS is not set}"
POLL="${GL_DRAIN_POLL_SECONDS:?GL_DRAIN_POLL_SECONDS is not set}"
SETTLE="${GL_DRAIN_SETTLE_SECONDS:?GL_DRAIN_SETTLE_SECONDS is not set}"
STALL_LIMIT="${GL_DRAIN_STALL_POLLS:?GL_DRAIN_STALL_POLLS is not set}"
STATUS_EVERY="${GL_DRAIN_STATUS_INTERVAL_SECONDS:?GL_DRAIN_STATUS_INTERVAL_SECONDS is not set}"
CONFIRM_POLLS="${GL_DRAIN_CONFIRM_POLLS:?GL_DRAIN_CONFIRM_POLLS is not set}"
METRICS_RETRIES="${GL_DRAIN_METRICS_RETRIES:?GL_DRAIN_METRICS_RETRIES is not set}"
GRACE="${GL_DRAIN_GRACE_SECONDS:?GL_DRAIN_GRACE_SECONDS is not set}"
RESERVE="${GL_DRAIN_RESERVE_SECONDS:?GL_DRAIN_RESERVE_SECONDS is not set}"
WARMUP="${GL_DRAIN_FEASIBILITY_WARMUP_POLLS:?GL_DRAIN_FEASIBILITY_WARMUP_POLLS is not set}"

DEPTH_GAUGE="gl_journal_entries_uncommitted"
RATE_GAUGE="gl_journal_append_1_sec_rate"
# Reported in the feasibility verdict so an operator sees how much is actually on
# disk, not just a message count. The anchored matching in sample() is what keeps
# SIZE_GAUGE from also matching LIMIT_GAUGE, which is a prefix extension of it.
SIZE_GAUGE="gl_journal_size"
LIMIT_GAUGE="gl_journal_size_limit"

# kubelet discards preStop stdout — it only ever surfaces (truncated) in
# a FailedPreStopHook event, and only when the hook fails. Writing to
# PID 1's stdout puts these lines in the container's real log stream so
# `kubectl logs` can see a drain happen. Keep the plain echo too: it is
# what lands in the event if this hook ever does fail.
# Probed once with a stat, not by opening it: if PID 1's stdout happens to
# be a regular file rather than the usual pipe, an open-for-write would
# truncate the container log. Appending for the same reason.
PID1_LOG=0
[ -w /proc/1/fd/1 ] 2>/dev/null && PID1_LOG=1
log() {
  lvl="$1"; shift
  line="[prestop-drain] $(date -u '+%Y-%m-%dT%H:%M:%SZ') ${lvl} $*"
  echo "${line}"
  # A bare `echo > /proc/1/fd/1 2>/dev/null` does NOT stay quiet when the
  # path is missing: the failure comes from the shell performing the
  # redirection, not from echo, so its stderr is not what gets silenced.
  if [ "${PID1_LOG}" = "1" ]; then
    echo "${line}" >> /proc/1/fd/1 2>/dev/null
  fi
  return 0
}
info()  { log "INFO " "$@"; }
warn()  { log "WARN " "$@"; }
error() { log "ERROR" "$@"; }
crit()  { log "CRIT " "$@"; }

# Byte counts for humans. The gauges are in bytes and reach the low gigabytes, so
# a raw number is unreadable in a verdict an operator has seconds to act on.
# One decimal place, worked out with integer arithmetic because POSIX sh has no
# floating point: the remainder is scaled by 10 before dividing, not after.
fmt_bytes() {
  _b="$1"
  if [ "${_b}" -ge 1073741824 ]; then
    printf '%d.%01dGiB' $(( _b / 1073741824 )) $(( _b % 1073741824 * 10 / 1073741824 ))
  elif [ "${_b}" -ge 1048576 ]; then
    printf '%d.%01dMiB' $(( _b / 1048576 )) $(( _b % 1048576 * 10 / 1048576 ))
  else
    printf '%dB' "${_b}"
  fi
}

# Same reasoning for durations: the whole point of the feasibility verdict is that
# the projection is wildly larger than the budget, and "7452s" does not land that
# way "2h4m" does.
fmt_duration() {
  _s="$1"
  if [ "${_s}" -ge 3600 ]; then
    printf '%dh%dm' $(( _s / 3600 )) $(( _s % 3600 / 60 ))
  elif [ "${_s}" -ge 60 ]; then
    printf '%dm%ds' $(( _s / 60 )) $(( _s % 60 ))
  else
    printf '%ds' "${_s}"
  fi
}

# Reads every gauge in one scrape. $NF is the value; ^gl_ skips the
# "# HELP"/"# TYPE" lines, and the anchored names avoid the
# similarly-spelled data-lake and kafka gauges. Exits non-zero when the
# depth gauge is absent, so callers can distinguish "no data" from zero.
#
# The anchoring matters more now that SIZE_GAUGE (gl_journal_size) is a strict
# prefix of LIMIT_GAUGE (gl_journal_size_limit): requiring "{" or a space
# immediately after the name is what stops the limit line from also matching the
# size gauge. Only the depth gauge is mandatory - size and limit default to 0 so
# a Graylog version that stops publishing them degrades the verdict's detail
# rather than aborting the drain.
sample() {
  curl -fsS --max-time 5 "${URL}" 2>/dev/null \
    | awk -v d="${DEPTH_GAUGE}" -v r="${RATE_GAUGE}" \
          -v s="${SIZE_GAUGE}" -v l="${LIMIT_GAUGE}" '
        $1 ~ "^"d"[{ ]" || index($1, d"{") == 1 { v = $NF }
        $1 ~ "^"r"[{ ]" || index($1, r"{") == 1 { a = $NF }
        $1 ~ "^"s"[{ ]" || index($1, s"{") == 1 { z = $NF }
        $1 ~ "^"l"[{ ]" || index($1, l"{") == 1 { m = $NF }
        END {
          if (v == "") exit 1
          if (z == "") z = 0
          if (m == "") m = 0
          printf "%d %d %d %d\n", v, a, z, m
        }'
}

# Splits a sample into globals. Four fields no longer fit the ${x% *}/${x#* }
# pair the two-field version used, and doing it in pure parameter expansion
# keeps this off the process-spawn path - it runs on every poll.
S_DEPTH=0; S_RATE=0; S_SIZE=0; S_LIMIT=0
parse_sample() {
  _rest="$1"
  S_DEPTH="${_rest%% *}"; _rest="${_rest#* }"
  S_RATE="${_rest%% *}";  _rest="${_rest#* }"
  S_SIZE="${_rest%% *}";  _rest="${_rest#* }"
  S_LIMIT="${_rest}"
}

# The disk half of the feasibility verdict. Split out because both infeasible
# paths report it identically, and because the percentage needs a guard: an
# absent limit gauge would divide by zero.
report_journal_state() {
  if [ "${S_LIMIT}" -gt 0 ]; then
    crit "  journal on disk: $(fmt_bytes "${S_SIZE}") of $(fmt_bytes "${S_LIMIT}") cap ($(( S_SIZE * 100 / S_LIMIT ))% full)"
    if [ "${S_SIZE}" -ge "${S_LIMIT}" ]; then
      crit "  the journal is AT its cap - Graylog is already discarding the oldest segments, so messages are being lost right now"
    fi
  else
    crit "  journal on disk: $(fmt_bytes "${S_SIZE}") (cap not published by this Graylog version)"
  fi
}

# Retrying wrapper around sample(). A single failed scrape is usually a blip -
# the exporter briefly busy, a dropped connection - and abandoning the drain on
# one miss throws away the whole point of the hook.
#
# Sets SAMPLE rather than echoing: callers use $( ) around sample(), and any
# warn() emitted during a retry would be captured into that output instead of
# reaching the log.
SAMPLE=""
sample_retry() {
  attempt=1
  while :; do
    if SAMPLE=$(sample); then
      [ "${attempt}" -gt 1 ] && info "metrics probe recovered on attempt ${attempt}"
      return 0
    fi
    if [ "${attempt}" -ge "${METRICS_RETRIES}" ]; then
      SAMPLE=""
      return 1
    fi
    warn "metrics probe failed (attempt ${attempt}/${METRICS_RETRIES}) - retrying in ${POLL}s"
    attempt=$(( attempt + 1 ))
    sleep "${POLL}"
  done
}

# Single exit point so every path reports a verdict in the same shape.
# Always exit 0 (see the header comment).
finish() {
  outcome="$1"; depth="$2"
  # Timings are derived here rather than passed in. The poll loop's own clock
  # starts after the settle wait, so quoting it alone reports "0s" for a journal
  # that actually took settle+poll to clear - accurate for the loop, misleading
  # about the hook. Report the total, and break it down.
  now=$(date +%s)
  total=$(( now - hook_started ))
  # Report the phases that actually ran. Quoting the configured SETTLE
  # unconditionally produced nonsense on the preflight path - "0s total (15s
  # settle + 0s draining)" - because that exit happens before the wait starts.
  if [ -z "${settle_started:-}" ]; then
    phase="preflight"
    spent="${total}s total, before the settle wait began"
  elif [ -z "${loop_started:-}" ]; then
    phase="settle"
    spent="${total}s total, during the settle wait"
  else
    phase="draining"
    # Measured, not assumed: the sleep can overrun under load, and metrics retries
    # can make preflight take real time. The three parts must sum to the total, or
    # the line invites exactly the "where did the rest go?" question.
    spent="${total}s total ($(( settle_started - hook_started ))s preflight + $(( loop_started - settle_started ))s settle + $(( now - loop_started ))s draining)"
  fi
  case "${outcome}" in
    drained)
      info "RESULT: SUCCESS - journal fully drained (0 messages remaining) in ${spent}, within the ${BUDGET}s budget" ;;
    stalled)
      warn "RESULT: INCOMPLETE - ${depth} messages still queued and no longer decreasing after ${spent} (budget ${BUDGET}s)"
      warn "the write side never stopped, so the journal cannot reach zero; only stopping the inputs can finish this drain" ;;
    timeout)
      warn "RESULT: INCOMPLETE - ${BUDGET}s timeout cutoff reached with ${depth} messages still undrained (${spent})" ;;
    infeasible)
      # Deliberately not a warn: this is the one outcome where the hook is telling
      # the operator that data loss is already committed and only manual action can
      # prevent it. The detail lines were emitted at the detection site.
      crit "RESULT: ABORTED - drain is not feasible; giving up immediately with ${depth} messages undrained (${spent})"
      crit "holding termination any longer would not have cleared them - returning the rest of the grace period to Graylog's own shutdown" ;;
    unavailable)
      if [ "${phase}" = "preflight" ]; then
        error "RESULT: UNKNOWN - no drain attempted; journal depth was never measurable (${spent})"
      else
        error "RESULT: UNKNOWN - drain abandoned; journal depth stopped being measurable (${spent})"
      fi ;;
  esac
  # How much of the backlog that existed when the hook started is now gone.
  # The baseline is the preflight sample, taken before the settle wait, because
  # that is "what was on disk when termination began" - the figure an operator
  # means by "did it drain". Integer arithmetic only; there is no floating point
  # in POSIX sh.
  if [ "${depth}" != "unknown" ]; then
    base="${start_depth:-0}"
    if [ "${base}" -le 0 ]; then
      info "drained n/a - the journal was already empty when the hook began"
    elif [ "${depth}" -ge "${base}" ]; then
      # Ingest outran processing, so nothing was net-drained. Reporting a negative
      # percentage would be noise; the two absolute numbers say it better.
      warn "drained 0% of the starting backlog - it grew from ${base} to ${depth} messages while ingest continued"
    else
      info "drained $(( (base - depth) * 100 / base ))% of the starting backlog (${base} -> ${depth} messages)"
    fi
  fi
  if [ "${outcome}" != "drained" ] && [ "${depth}" != "unknown" ] && [ "${depth}" -gt 0 ] 2>/dev/null; then
    warn "if this pod is being removed by a scale-in, those ${depth} messages will be stranded in its PVC - nothing replays an orphaned journal"
  fi
  # RESERVE is only the guaranteed FLOOR - the deadline is set so at least that
  # much is left in the worst case. A drain that finishes early leaves far more,
  # and quoting the floor understated it badly (45s reported when 280s remained).
  # Report what is actually left of the grace period.
  left=$(( GRACE - total ))
  [ "${left}" -lt 0 ] && left=0
  info "handing over to SIGTERM with ~${left}s of the ${GRACE}s grace period left for Graylog to shut down cleanly (guaranteed floor was ${RESERVE}s)"
  exit 0
}

# ---- configuration -----------------------------------------------------
hook_started=$(date +%s)
info "journal drain starting on ${HOSTNAME:-unknown}"
info "config: budget=${BUDGET}s retries=${METRICS_RETRIES} poll=${POLL}s settle=${SETTLE}s stallPolls=${STALL_LIMIT} confirmPolls=${CONFIRM_POLLS} statusEvery=${STATUS_EVERY}s"
info "config: budget = terminationGracePeriodSeconds(${GRACE}s) - settle(${SETTLE}s) - shutdownReserve(${RESERVE}s)"
info "config: metrics=${URL} depthGauge=${DEPTH_GAUGE}"

# ---- preflight: is the endpoint there, and how much is queued? ---------
sample_retry || true
start_sample="${SAMPLE}"
if [ -z "${start_sample}" ]; then
  error "metrics endpoint ${URL} did not answer after ${METRICS_RETRIES} attempts, or ${DEPTH_GAUGE} is absent"
  error "the exporter only serves once Graylog has started; if this pod was still"
  error "starting up or already unhealthy, it had no journal activity to drain"
  finish unavailable unknown
fi
parse_sample "${start_sample}"
start_depth="${S_DEPTH}"
start_rate="${S_RATE}"
info "metrics endpoint reachable"
info "journal at start: ${start_depth} messages on disk awaiting processing, ingest ${start_rate} msg/s"
if [ "${S_LIMIT}" -gt 0 ]; then
  info "journal on disk: $(fmt_bytes "${S_SIZE}") of $(fmt_bytes "${S_LIMIT}") cap ($(( S_SIZE * 100 / S_LIMIT ))% full)"
fi
if [ "${start_depth}" -le 0 ]; then
  info "journal already empty before the settle wait"
fi

# Kubernetes removes a Terminating pod from every Service EndpointSlice,
# but kube-proxy convergence is not instant. Measuring before it lands
# reads traffic that is already going away.
settle_started=$(date +%s)
info "waiting ${SETTLE}s for EndpointSlice removal to propagate"
sleep "${SETTLE}"

# ---- drain loop --------------------------------------------------------
# Wall clock, not a tick count. Each iteration can block for up to the
# curl timeout, so counting polls would let the hook overrun BUDGET by
# a wide margin and get the container SIGKILLed mid-shutdown.
loop_started=$(date +%s)
# Anchored to the hook's own start, not the loop's. Preflight retries and an
# overrunning settle both eat wall clock before we get here; deriving the
# deadline from BUDGET alone would push the total past the grace period and get
# the container SIGKILLed with its buffers unflushed. This guarantees RESERVE
# seconds are left for SIGTERM no matter what happened earlier.
deadline=$(( hook_started + GRACE - RESERVE ))
remaining_budget=$(( deadline - loop_started ))
# A second or two goes on the preflight scrape itself; that is not worth a warning.
# Only flag a shortfall big enough to change the outcome.
if [ "${remaining_budget}" -lt $(( BUDGET - 10 )) ]; then
  warn "only ${remaining_budget}s of the ${BUDGET}s budget remain - preflight and settle took $(( BUDGET - remaining_budget ))s longer than planned"
fi
# Progress is measured against the best (lowest) depth seen so far, not
# against the previous sample. Under live ingest the gauge oscillates
# continuously — two consecutive samples are essentially never equal —
# so an equality test never fires and the hook burns the whole budget
# for nothing. Requiring a new low means "no improvement" is detected
# even while the raw number jitters.
stall=0
best=""
zero_streak=0
n="${start_depth}"
rate="${start_rate}"
last_status=-999
first_poll=1
# Feasibility gate state. polls counts iterations that actually sampled a
# non-zero depth, so the WARMUP window measures real draining rather than being
# consumed by zero-confirmation polls.
polls=0
feas_checked=0
feas_depth0=""
feas_t0=0
info "draining: up to ${BUDGET}s, giving up early after ${STALL_LIMIT} polls without a new low"
if [ "${WARMUP}" -gt 0 ]; then
  info "feasibility: projecting completion after ${WARMUP} polls; aborting immediately if it cannot finish in the budget"
else
  info "feasibility: projection disabled (feasibilityWarmupPolls=0)"
fi
while [ "$(date +%s)" -lt "${deadline}" ]; do
  elapsed=$(( $(date +%s) - loop_started ))
  remaining=$(( deadline - $(date +%s) ))
  sample_retry || true
  sample="${SAMPLE}"
  if [ -z "${sample}" ]; then
    error "metrics endpoint stopped answering after ${elapsed}s and did not recover in ${METRICS_RETRIES} attempts (it responded during preflight)"
    finish unavailable unknown
  fi
  parse_sample "${sample}"
  n="${S_DEPTH}"
  rate="${S_RATE}"
  [ -z "${best}" ] && best="${n}"

  # A SINGLE zero is not proof the journal is drained. Under live ingest the depth
  # oscillates and momentarily touches zero while messages are still arriving;
  # exiting on that would declare success, hand over to SIGTERM, and let whatever
  # arrives next be journaled and then orphaned on the PVC. Require the depth to
  # stay at zero across CONFIRM_POLLS consecutive samples - if anything is still
  # writing, it pops back above zero and the streak resets.
  if [ "${n}" -le 0 ]; then
    zero_streak=$(( zero_streak + 1 ))
    if [ "${zero_streak}" -ge "${CONFIRM_POLLS}" ]; then
      if [ "${first_poll}" = "1" ] && [ "${CONFIRM_POLLS}" -le 1 ]; then
        info "journal was already empty at the first poll - it cleared during the ${SETTLE}s settle wait"
      else
        info "depth held at 0 across ${zero_streak} consecutive polls - nothing is still writing"
      fi
      finish drained 0
    fi
    info "depth is 0 (confirmation ${zero_streak}/${CONFIRM_POLLS}) - re-checking that nothing is still arriving"
    first_poll=0
    sleep "${POLL}"
    continue
  fi
  if [ "${zero_streak}" -gt 0 ]; then
    warn "depth rose back to ${n} after ${zero_streak} zero reading(s): messages are still arriving, so the journal is NOT drained"
    zero_streak=0
    # Restart the progress baseline. Leaving best at 0 would make every
    # subsequent reading "no new low", so the stall counter would climb every
    # poll and report INCOMPLETE while the drain was in fact still working.
    best="${n}"
  fi
  first_poll=0

  if [ "${n}" -lt "${best}" ]; then
    best="${n}"
    stall=0
  else
    stall=$((stall + 1))
  fi

  # Throttled so a long drain does not bury the log, but always report
  # the first sample so there is a datapoint even on a short run.
  if [ $(( elapsed - last_status )) -ge "${STATUS_EVERY}" ]; then
    info "draining: ${n} messages queued (best ${best}), ingest ${rate} msg/s, ${elapsed}s elapsed, ${remaining}s left, ${stall}/${STALL_LIMIT} polls without progress"
    last_status="${elapsed}"
  fi

  # ---- feasibility gate ------------------------------------------------
  # The stall detector answers "is depth still falling?" It never asks "can this
  # finish in the time left?", and the two diverge badly. A terminating pod is
  # pulled from the EndpointSlice, ingest tapers, and depth genuinely does keep
  # reaching new lows - so the stall counter keeps resetting and the hook runs
  # its entire budget. Observed on a flooded cluster: 7.24M queued messages
  # draining at ~1k msg/s needed ~2h, had 240s, cleared ~2%, and stranded the
  # rest. The budget bought nothing and delayed every pod in the rollout.
  #
  # So project it. One evaluation, once WARMUP polls have produced a measured
  # rate; if the projection does not fit, abort now and hand the remaining grace
  # period back to Graylog's shutdown, which can at least use it. A drain that
  # passes the gate but degrades afterwards is still caught by the stall
  # detector, so this does not need to re-arm.
  polls=$(( polls + 1 ))
  if [ -z "${feas_depth0}" ]; then
    feas_depth0="${n}"
    feas_t0=$(date +%s)
  elif [ "${WARMUP}" -gt 0 ] && [ "${feas_checked}" = "0" ] && [ "${polls}" -ge "${WARMUP}" ]; then
    feas_checked=1
    observed=$(( $(date +%s) - feas_t0 ))
    # Guard the divisor: a fast loop can measure the window as 0s.
    [ "${observed}" -lt 1 ] && observed=1
    cleared=$(( feas_depth0 - n ))
    budget_left=$(( deadline - $(date +%s) ))
    [ "${budget_left}" -lt 0 ] && budget_left=0
    if [ "${cleared}" -le 0 ]; then
      crit "FEASIBILITY: journal is NOT draining - depth went ${feas_depth0} -> ${n} messages over ${observed}s"
      report_journal_state
      crit "  backlog:         ${n} messages awaiting processing"
      crit "  drain rate:      0 msg/s - nothing is being worked off (ingest ${rate} msg/s)"
      crit "  time to clear:   never at this rate"
      crit "  time available:  ${budget_left}s of the ${BUDGET}s drain budget"
      crit "  the indexer is refusing writes or cannot keep up; check for a read-only index block or a disk watermark on the indexer"
      crit "  ${n} messages will NOT be drained by this hook - stop the inputs and drain manually to save them"
      finish infeasible "${n}"
    fi
    drain_rate=$(( cleared / observed ))
    # Projected as n * observed / cleared rather than n / drain_rate: integer
    # division floors a slow-but-real drain to 0 msg/s, and dividing by that
    # would abort the script outright. This form has no such hole, and it keeps
    # the sub-1-msg/s precision that the floored rate throws away.
    eta=$(( n * observed / cleared ))
    if [ "${eta}" -gt "${budget_left}" ]; then
      crit "FEASIBILITY: drain cannot finish in the time available - aborting instead of holding termination for nothing"
      report_journal_state
      crit "  backlog:         ${n} messages awaiting processing"
      crit "  drain rate:      ${drain_rate} msg/s measured over ${observed}s (ingest ${rate} msg/s)"
      crit "  time to clear:   ~$(fmt_duration "${eta}") at that rate"
      crit "  time available:  ${budget_left}s of the ${BUDGET}s drain budget"
      crit "  short by:        ~$(fmt_duration $(( eta - budget_left )))"
      crit "  ${n} messages will NOT be drained by this hook - stop the inputs and drain manually to save them"
      finish infeasible "${n}"
    fi
    info "feasibility OK: ${n} messages at ${drain_rate} msg/s projects ~$(fmt_duration "${eta}"), inside the ${budget_left}s remaining"
  fi

  if [ "${stall}" -ge "${STALL_LIMIT}" ]; then
    # Endpoint removal only sheds newly-established connections.
    # Long-lived TCP inputs, UDP senders and internally generated inputs
    # keep writing, so the journal will not reach zero however long we
    # wait.
    warn "no new low in ${stall} polls: depth ${n}, best ${best}, still ingesting ${rate} msg/s"
    finish stalled "${n}"
  fi
  sleep "${POLL}"
done
finish timeout "${n}"
