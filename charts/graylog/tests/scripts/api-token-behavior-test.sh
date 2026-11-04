#!/bin/sh
# Behavioural tests for files/scripts/api-token.sh, step 2: when does the script
# keep the token already stored in the Secret, and when does it mint a new one.
#
# Run it:
#   sh charts/graylog/tests/scripts/api-token-behavior-test.sh
#
# A stub `curl` goes first on PATH. It answers the readiness probe, serves a
# Secret that holds a token, and answers the token check with the status code the
# scenario sets in STUB_USER_CODE. Any other call returns 500, so a scenario that
# decides to replace the token dies right after logging that decision. The tests
# read that log line. Graylog answers 401 for a token it rejects and 403 for a
# valid token whose roles cannot read the user record, so a Reader token must be
# kept.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPT="${SCRIPT_DIR}/../../files/scripts/api-token.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "${WORK}/curl" <<'STUB'
#!/bin/sh
for a in "$@"; do url="$a"; done
case "$url" in
  */system/lbstatus) printf '200' ;;
  */secrets/*) printf '{\n  "kind": "Secret",\n  "data": {\n    "token": "dGs=",\n    "username": "aGVsbQ=="\n  }\n}\n200' ;;
  */users/helm-automation) printf '%s' "${STUB_USER_CODE}" ;;
  *) printf '\n500' ;;
esac
STUB
chmod +x "${WORK}/curl"

fail=0
run() { # name, user-endpoint code, expected log fragment
  out=$(PATH="${WORK}:${PATH}" STUB_USER_CODE="$2" GRAYLOG_URL=http://g:9000 ROOT_USER=admin \
    ROOT_PASSWORD=x SERVICE_USER=helm-automation SERVICE_ROLES='["Reader"]' TOKEN_NAME=helm \
    TOKEN_TTL=P90D SECRET_NAME=s SECRET_LABELS='{}' NAMESPACE=n WAIT_SECONDS=5 \
    sh "$SCRIPT" 2>&1)
  case "$out" in
    *"$3"*) echo "ok   $1" ;;
    *) echo "FAIL $1: expected \"$3\""; echo "$out" | sed 's/^/     /'; fail=1 ;;
  esac
}

run "keeps a token that reads the user record (200)" 200 "nothing to do"
run "keeps a token whose role cannot read the record (403)" 403 "nothing to do"
run "replaces a token Graylog rejects (401)" 401 "no longer authenticates (HTTP 401)"

exit "$fail"
