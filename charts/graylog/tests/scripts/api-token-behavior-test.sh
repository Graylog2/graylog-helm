#!/bin/sh
# Behavioural tests for files/scripts/api-token.sh in hook mode: when the script keeps
# the token already stored in the Secret, when it reissues one inside the renewal window, when it creates the user and mints a new token,
# whether it writes the Secret with POST or PATCH, and what it cleans up when
# something fails.
#
# Run it:
#   sh charts/graylog/tests/scripts/api-token-behavior-test.sh
#
# A stub `curl` goes first on PATH. It reads the -K credential file and the stdin
# body the way the real curl would, appends every call to ${WORK}/calls, every
# body to ${WORK}/bodies and every argument list to ${WORK}/args, and answers from
# the STUB_* variables a scenario sets. A scenario then asserts which calls were
# made and in what order. The args file proves that no password or token reached a
# command line. Graylog answers 401 for a token it rejects and 403 for a valid
# token whose roles cannot read the user record, so a Reader token must be kept.
#
# STUB_SECRET       status of the token Secret read (200 or 404)
# STUB_NO_USERID    Secret has no userid key
# STUB_TOKEN_CODE   status of GET /users/<name> made with the stored token
# STUB_USER         status of GET /users/<name> made as root (200 or 404). The user
#                   exists after a successful POST /users.
# STUB_CREATE_USER  status of POST /users
# STUB_OLD_TOKENS   the token list holds a token named like ours
# STUB_EXPIRES     expiry of the token in the list. The clock is fixed with NOW_EPOCH at
#                   2026-11-04T00:00:00Z and the renewal window is 14 days.
# STUB_MINT         status of the token mint
# STUB_WRITE        status of the Secret write

set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SCRIPT="${SCRIPT_DIR}/../../files/scripts/api-token.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "${WORK}/curl" <<'STUB'
#!/bin/sh
method=GET; kfile=""; devnull=""; prev=""; sawdata=""; url=""
for a in "$@"; do
  case "$prev" in -X) method="$a" ;; -K) kfile="$a" ;; -o) devnull="$a" ;; esac
  [ "$a" = "--data-binary" ] && sawdata=1
  prev="$a"; url="$a"
done
body=""; [ -n "$sawdata" ] && body="$(cat)"
creds=""; [ -n "$kfile" ] && creds="$(cat "$kfile" 2>/dev/null)"
echo "$method $url" >> "${WORK}/calls"
echo "$*" >> "${WORK}/args"
[ -n "$body" ] && echo "$method $url $body" >> "${WORK}/bodies"
reply() { # body, status
  if [ -n "$devnull" ]; then printf '%s' "$2"; else printf '%s\n%s' "$1" "$2"; fi
}
case "$method $url" in
  "GET "*/system/lbstatus) reply '' 200 ;;
  "GET "*/secrets/*)
    if [ "${STUB_SECRET:-200}" = 404 ]; then reply '{}' 404
    elif [ -n "${STUB_NO_USERID:-}" ]; then reply '{
  "data": {
    "token": "b2xkLXRva2Vu"
  }
}' 200
    else reply '{
  "data": {
    "token": "b2xkLXRva2Vu",
    "userid": "dWlkMQ=="
  }
}' 200; fi ;;
  "GET "*/users/helm-automation)
    case "$creds" in
      *old-token:token*) reply '' "${STUB_TOKEN_CODE:-200}" ;;
      *) if [ "${STUB_USER:-200}" = 200 ] || [ -f "${WORK}/created" ]; then reply '{"id":"uid1","username":"helm-automation"}' 200
         else reply '{}' 404; fi ;;
    esac ;;
  "POST "*/api/users) [ "${STUB_CREATE_USER:-201}" = 201 ] && : > "${WORK}/created"
    reply '{}' "${STUB_CREATE_USER:-201}" ;;
  "GET "*/users/uid1/tokens)
    if [ -n "${STUB_OLD_TOKENS:-}" ] || [ -n "${STUB_EXPIRES:-}" ]; then
      reply "{\"tokens\":[{\"id\":\"tid-old\",\"name\":\"helm\",\"expires_at\":\"${STUB_EXPIRES:-2026-12-04T00:00:00.000Z}\"}]}" 200
    else reply '{"tokens":[]}' 200; fi ;;
  "POST "*/users/uid1/tokens/helm)
    reply '{"id":"tid-new","name":"helm","token":"new-token-value"}' "${STUB_MINT:-200}" ;;
  "DELETE "*/users/uid1/tokens/*) reply '' 204 ;;
  "POST "*/secrets) reply '{}' "${STUB_WRITE:-201}" ;;
  "PATCH "*/secrets/*) reply '{}' "${STUB_WRITE:-200}" ;;
  *) reply '{}' 500 ;;
esac
STUB
chmod +x "${WORK}/curl"

fail=0
ROOT_PW=rootpw-for-the-stub

run() { # runs the script in the scenario set by the caller's exported STUB_* variables
  : > "${WORK}/calls"; : > "${WORK}/args"; : > "${WORK}/bodies"; rm -f "${WORK}/created"
  out=$(WORK="$WORK" PATH="${WORK}:${PATH}" GRAYLOG_URL=http://g:9000 ROOT_USER=admin \
    ROOT_PASSWORD="$ROOT_PW" SERVICE_USER=helm-automation SERVICE_ROLES='["Reader"]' \
    SERVICE_PERMISSIONS='["a:b"]' TOKEN_NAME=helm TOKEN_TTL=P90D SECRET_NAME=s \
    SECRET_LABELS='{"app":"graylog-app"}' SECRET_ANNOTATIONS='{"note":"kept"}' \
    NAMESPACE=n WAIT_SECONDS=5 MODE=hook RENEW_BEFORE_SECONDS=1209600 NOW_EPOCH=$((20761 * 86400)) sh "$SCRIPT" 2>&1)
  rc=$?
}
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; echo "$out" | sed 's/^/     /'; echo "     calls:"; sed 's/^/       /' "${WORK}/calls"; echo "     bodies:"; sed 's/^/       /' "${WORK}/bodies"; fail=1; }
check() { # name, command that must succeed
  name="$1"; shift
  if "$@"; then ok "$name"; else bad "$name"; fi
}
called() { grep -q -- "$1" "${WORK}/calls"; }
not_called() { ! grep -q -- "$1" "${WORK}/calls"; }
logged() { case "$out" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
before() { # first call matching $1 comes before the first matching $2
  a=$(grep -n -- "$1" "${WORK}/calls" | head -n 1 | cut -d: -f1)
  b=$(grep -n -- "$2" "${WORK}/calls" | head -n 1 | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}
body_has() { grep -q -- "$1" "${WORK}/bodies"; }
args_lack() { ! grep -q -- "$1" "${WORK}/args"; }
reset() { unset STUB_SECRET STUB_NO_USERID STUB_TOKEN_CODE STUB_USER STUB_CREATE_USER STUB_OLD_TOKENS STUB_EXPIRES STUB_MINT STUB_WRITE; }

# Step 2: keep or replace the stored token.
reset; export STUB_TOKEN_CODE=200 STUB_EXPIRES=2026-12-04T00:00:00.000Z; run
check "keeps a token that reads the user record (200)" logged "nothing to do"
check "  and mints nothing" not_called "POST .*/tokens/helm"
reset; export STUB_TOKEN_CODE=403 STUB_EXPIRES=2026-12-04T00:00:00.000Z; run
check "keeps a token whose role cannot read the record (403)" logged "nothing to do"
check "  and mints nothing" not_called "POST .*/tokens/helm"
reset; export STUB_TOKEN_CODE=401 STUB_USER=200; run
check "replaces a token Graylog rejects (401)" logged "no longer authenticates (HTTP 401)"

# Step 3, the renewal window. Inside it a helm upgrade reissues as root.
reset; export STUB_TOKEN_CODE=200 STUB_EXPIRES=2026-11-07T00:00:00.000Z; run
check "reissues a working token inside the renewal window" logged "inside the 14d0h renewal window"
check "  mints as root" called "POST .*/users/uid1/tokens/helm"
check "  patches the Secret" called "PATCH .*secrets/s"
check "  and revokes the old token after the write" before "PATCH .*secrets/s" "DELETE .*tokens/tid-old"
reset; export STUB_TOKEN_CODE=200 STUB_EXPIRES=2026-12-04T00:00:00.000Z; run
check "keeps a working token outside the window" logged "more than the 14d0h renewal window, nothing to do"

# Step 3, the user id backfill for a Secret written before the renewal CronJob.
reset; export STUB_NO_USERID=1; run
check "adds the user id to an older Secret" called "PATCH .*secrets/s"
check "  with the id from the root lookup" body_has '"userid":"dWlkMQ=="'
check "  and then exits without minting" not_called "POST .*/tokens/helm"

# Fresh install: no Secret, no user.
reset; export STUB_SECRET=404 STUB_USER=404; run
check "fresh install exits 0" test "$rc" -eq 0
check "creates the service user" called "POST .*/api/users$"
check "  with the roles, permissions and the service_account flag" body_has '"roles":\["Reader"\].*"service_account":true'
check "  and the extra permissions" body_has '"permissions":\["a:b"\]'
check "mints the token" called "POST .*/users/uid1/tokens/helm"
check "creates the Secret with POST" called "POST .*/secrets$"
check "  with the labels and annotations" body_has '"labels":{"app":"graylog-app"},"annotations":{"note":"kept"}'
NEW_B64=$(printf '%s' new-token-value | base64)
check "  and the token, user name and user id" body_has "\"token\":\"${NEW_B64}\",\"username\":\"aGVsbS1hdXRvbWF0aW9u\",\"userid\":\"dWlkMQ==\""
check "creates the user before it mints" before "POST .*/api/users$" "tokens/helm"
check "mints before it writes the Secret" before "tokens/helm" "POST .*/secrets$"
check "never patches a Secret that does not exist" not_called "PATCH"

# Existing user, existing Secret with a rejected token: PATCH, then revoke.
reset; export STUB_TOKEN_CODE=401 STUB_USER=200 STUB_OLD_TOKENS=1; run
check "reuses an existing user" not_called "POST .*/api/users$"
check "patches the existing Secret" called "PATCH .*secrets/s"
check "  and does not POST one" not_called "POST .*/secrets$"
check "revokes the old token" called "DELETE .*/users/uid1/tokens/tid-old"
check "  only after the Secret write" before "PATCH .*secrets/s" "DELETE .*tokens/tid-old"
check "  and never revokes the new token" not_called "DELETE .*tokens/tid-new"

# Failures.
reset; export STUB_TOKEN_CODE=401 STUB_USER=200 STUB_OLD_TOKENS=1 STUB_WRITE=500; run
check "a failed Secret write fails the Job" test "$rc" -ne 0
check "  deletes the token it just minted" called "DELETE .*tokens/tid-new"
check "  and keeps the old token" not_called "DELETE .*tokens/tid-old"

reset; export STUB_SECRET=404 STUB_USER=200 STUB_MINT=500; run
check "a failed mint fails the Job" test "$rc" -ne 0
check "  and writes no Secret" not_called "\(POST\|PATCH\) .*secrets"

reset; export STUB_SECRET=404 STUB_USER=404 STUB_CREATE_USER=500; run
check "a refused user creation fails the Job" test "$rc" -ne 0
check "  and mints nothing" not_called "tokens/helm"

# Secrets stay off the command line.
reset; export STUB_SECRET=404 STUB_USER=404; run
check "the root password is not a curl argument" args_lack "$ROOT_PW"
check "the new token is not a curl argument" args_lack "new-token-value"
check "the old token is not a curl argument" args_lack "old-token"

exit "$fail"
