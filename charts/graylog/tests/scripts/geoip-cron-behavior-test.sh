#!/bin/sh
# Behavioural tests for the GeoIP sidecar cron matcher.
#
# The helm-unittest suite (tests/geolocation_sidecar_test.yaml) asserts that the
# schedule string reaches GEOIP_SCHEDULE. It cannot tell whether the sidecar ever
# acts on it. It did not: the previous matcher compared each field against "*" or
# the exact current value, and stripped leading zeros with `sed 's/^0*//'`, which
# turns "00" into "". So "0" never equalled "", and the chart default
# `0 0 * * *` never fired at all. Step syntax such as `*/6` never fired either,
# although tests/geolocation_sidecar_test.yaml uses it.
#
# So this renders the real ConfigMap, extracts the real functions, and drives
# them against a stubbed clock.
#
# Run it:
#   sh charts/graylog/tests/scripts/geoip-cron-behavior-test.sh
#   sh charts/graylog/tests/scripts/geoip-cron-behavior-test.sh -v
#
# How the clock is faked
# ----------------------
# A stub `date` is placed first on PATH. It answers +%M/+%H/+%d/+%m/+%w from
# environment variables the harness sets per case. Nothing else is substituted:
# denumber(), cron_match() and should_update() execute exactly as rendered.

set -u

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CHART_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- render the ConfigMap and extract entrypoint.sh -------------------------
helm template geoip "$CHART_DIR" \
  --set graylog.config.geolocation.enabled=true \
  --set graylog.config.geolocation.sidecar.enabled=true \
  --set graylog.config.geolocation.maxmindGeoIp.accountId=test \
  --set graylog.config.geolocation.maxmindGeoIp.licenseKey=test \
  --show-only templates/config/geoip-sidecar-entrypoint.yaml \
  > "$WORK/cm.yaml" 2>"$WORK/render.err" || {
    echo "FAIL: could not render the GeoIP entrypoint ConfigMap"
    cat "$WORK/render.err"
    exit 1
  }

# strip the YAML wrapper: keep everything indented under `entrypoint.sh: |`
awk '
  /^  entrypoint\.sh: \|/ { grab=1; next }
  grab { if (match($0, /^    /)) { print substr($0, 5) } else if (NF) { grab=0 } }
' "$WORK/cm.yaml" > "$WORK/entrypoint.sh"

[ -s "$WORK/entrypoint.sh" ] || { echo "FAIL: extracted entrypoint.sh is empty"; exit 1; }

# Keep every top-level function; the real script ends in `while true`.
# Extraction is deliberately name-agnostic, so that removing a helper shows up
# as a behavioural failure below rather than as an extraction error here.
awk '
  /^[a-z_][a-z0-9_]*\(\) \{/ { keep=1 }
  keep { print }
  /^\}$/ { keep=0 }
' "$WORK/entrypoint.sh" > "$WORK/funcs.sh"

grep -q '^should_update() {' "$WORK/funcs.sh" \
  || { echo "FAIL: did not extract should_update()"; exit 1; }

# --- stub date -------------------------------------------------------------
mkdir -p "$WORK/bin"
cat > "$WORK/bin/date" <<'STUB'
#!/bin/sh
case "$1" in
  +%M) echo "$FAKE_MIN" ;;
  +%H) echo "$FAKE_HOUR" ;;
  +%d) echo "$FAKE_DAY" ;;
  +%m) echo "$FAKE_MONTH" ;;
  +%w) echo "$FAKE_WDAY" ;;
  *)   echo "stub-date" ;;
esac
STUB
chmod +x "$WORK/bin/date"
PATH="$WORK/bin:$PATH"
export PATH

PASS=0
FAIL=0

# case SCHEDULE MIN HOUR DAY MONTH WDAY EXPECT(fire|skip) DESCRIPTION
case_run() {
  _sched="$1"; FAKE_MIN="$2"; FAKE_HOUR="$3"; FAKE_DAY="$4"
  FAKE_MONTH="$5"; FAKE_WDAY="$6"; _expect="$7"; _desc="$8"
  export FAKE_MIN FAKE_HOUR FAKE_DAY FAKE_MONTH FAKE_WDAY

  # `set -f` before the split: the schedule contains `*`, and an unquoted
  # expansion would otherwise be replaced by the directory listing.
  _out=$(
    . "$WORK/funcs.sh"
    set -f
    set -- $_sched
    set +f
    CRON_MINUTE="${1:-0}"; CRON_HOUR="${2:-0}"; CRON_DAY="${3:-*}"
    CRON_MONTH="${4:-*}"; CRON_WEEKDAY="${5:-*}"
    if should_update; then echo fire; else echo skip; fi
  )

  if [ "$_out" = "$_expect" ]; then
    PASS=$((PASS + 1))
    [ "$VERBOSE" -eq 1 ] && printf '  ok   %-16s %s\n' "$_sched" "$_desc"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %-16s at %s:%s  expected %s, got %s  (%s)\n' \
      "$_sched" "$FAKE_HOUR" "$FAKE_MIN" "$_expect" "$_out" "$_desc"
  fi
}

echo "GeoIP cron matcher behaviour"

# The regression this test exists for: the chart default.
case_run "0 0 * * *"   00 00 15 06 3 fire "chart default fires at midnight"
case_run "0 0 * * *"   01 00 15 06 3 skip "chart default does not fire at 00:01"
case_run "0 0 * * *"   00 01 15 06 3 skip "chart default does not fire at 01:00"

# Zero-padding in every field.
case_run "0 2 * * *"   00 02 15 06 3 fire "zero minute with non-zero hour"
case_run "5 0 * * *"   05 00 15 06 3 fire "zero hour with non-zero minute"
case_run "0 0 1 1 *"   00 00 01 01 3 fire "zero-padded day and month"

# Step syntax, which tests/geolocation_sidecar_test.yaml already uses.
case_run "*/6 * * * *" 48 10 15 06 3 fire "step matches multiple of 6"
case_run "*/6 * * * *" 49 10 15 06 3 skip "step skips non-multiple"
case_run "*/6 * * * *" 00 10 15 06 3 fire "step matches zero"
case_run "*/15 * * * *" 45 10 15 06 3 fire "quarter-hour step"

# Ranges and lists.
case_run "0 9-17 * * *" 00 13 15 06 3 fire "hour inside range"
case_run "0 9-17 * * *" 00 18 15 06 3 skip "hour outside range"
case_run "0 0,12 * * *" 00 12 15 06 3 fire "hour in list"
case_run "0 0,12 * * *" 00 06 15 06 3 skip "hour not in list"
case_run "0 0-23/6 * * *" 00 18 15 06 3 fire "range with step"

# Wildcards and weekday.
case_run "* * * * *"   37 09 15 06 3 fire "all wildcards always fire"
case_run "0 0 * * 0"   00 00 15 06 0 fire "weekday Sunday matches"
case_run "0 0 * * 0"   00 00 15 06 3 skip "weekday Sunday skips Wednesday"

# Malformed input must not fire rather than fire constantly.
case_run "abc * * * *" 00 00 15 06 3 skip "non-numeric minute does not fire"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
