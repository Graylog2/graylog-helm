#!/bin/sh
# Behavioural tests for files/scripts/api-token-renew.sh: when does the script
# leave the token alone, when does it replace it, and does it clean up after a
# failed Secret write.
#
# Run it:
#   sh charts/graylog/tests/scripts/api-token-renew-behavior-test.sh
#
# A stub `curl` goes first on PATH. It serves a Secret that holds a token, the
# service user, and a token list whose expiry the scenario sets in STUB_EXPIRES
# (empty for a token with no expiry). The clock is fixed with NOW_EPOCH at
# 2026-11-04T00:00:00Z. Every call is appended to ${WORK}/calls so a scenario can
# assert which requests were made, for instance that the old token is deleted only
# after the Secret write and the new token is deleted when the write fails.
# STUB_SECRET, STUB_USERS, STUB_LIST, STUB_MINT and STUB_PATCH override the status code of that
# call, and STUB_MINT_BODY the body of the mint response.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPT="${SCRIPT_DIR}/../../files/scripts/api-token-renew.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "${WORK}/curl" <<'STUB'
#!/bin/sh
method=GET; prev=""
for a in "$@"; do
  [ "$prev" = "-X" ] && method="$a"
  prev="$a"; url="$a"
done
echo "$method $url" >> "${WORK}/calls"
code() { printf '\n%s' "$1"; }
case "$method $url" in
  "GET "*/system/lbstatus) printf '200' ;;
  "GET "*/secrets/*) [ "${STUB_SECRET:-200}" = 200 ] || { printf '{}'; code "$STUB_SECRET"; exit 0; }
    printf '{\n  "data": {\n    "token": "b2xkLXRva2Vu",\n    "username": "aGVsbQ=="\n  }\n}\n200' ;;
  "PATCH "*/secrets/*) printf '{}'; code "${STUB_PATCH:-200}" ;;
  "GET "*/users/helm-automation) printf '{"id":"uid1","username":"helm-automation"}'; code "${STUB_USERS:-200}" ;;
  "GET "*/users/uid1/tokens)
    if [ -z "${STUB_EXPIRES:-}" ]; then
      printf '{"tokens":[{"id":"tid-old","name":"helm","expires_at":null}]}'
    else
      printf '{"tokens":[{"id":"tid-old","name":"helm","last_access":"2026-11-03T00:00:00.000Z","created_at":"2026-08-01T00:00:00.000Z","expires_at":"%s"},{"id":"tid-other","name":"other","expires_at":"2026-11-04T01:00:00.000Z"}]}' "$STUB_EXPIRES"
    fi
    code "${STUB_LIST:-200}" ;;
  "POST "*/users/uid1/tokens/helm) printf '%s' "${STUB_MINT_BODY:-{\"id\":\"tid-new\",\"name\":\"helm\",\"token\":\"new-token\"}}"; code "${STUB_MINT:-200}" ;;
  "DELETE "*/users/uid1/tokens/*) code 204 ;;
  *) code 500 ;;
esac
STUB
chmod +x "${WORK}/curl"

fail=0
run() { # name, expected log fragment; the scenario's STUB_* are exported by the caller
  : > "${WORK}/calls"
  out=$(WORK="$WORK" PATH="${WORK}:${PATH}" NOW_EPOCH=$((20761 * 86400)) GRAYLOG_URL=http://g:9000 \
    SERVICE_USER=helm-automation TOKEN_NAME=helm TOKEN_TTL=P90D SECRET_NAME=s NAMESPACE=n \
    RENEW_BEFORE_SECONDS=1209600 sh "$SCRIPT" 2>&1)
  case "$out" in
    *"$2"*) echo "ok   $1" ;;
    *) echo "FAIL $1: expected \"$2\""; echo "$out" | sed 's/^/     /'; fail=1 ;;
  esac
}
called() { grep -q "$1" "${WORK}/calls"; } # fragment of "METHOD url"
expect_called() { if called "$2"; then echo "ok   $1"; else echo "FAIL $1: no call matching \"$2\""; fail=1; fi; }
expect_not_called() { if called "$2"; then echo "FAIL $1: unexpected call matching \"$2\""; fail=1; else echo "ok   $1"; fi; }

# 14 days is the window. 2026-11-04 plus 30 days is outside it, plus 3 days inside.
export STUB_EXPIRES=2026-12-04T00:00:00.000Z
run "leaves a token with 30 days left alone" "nothing to do"
expect_not_called "  and mints nothing" "POST .*tokens/helm"

export STUB_EXPIRES=2026-11-07T00:00:00.000Z
run "renews a token with 3 days left" "stored the new token"
expect_called "  and mints with the old token" "POST .*users/uid1/tokens/helm"
expect_called "  and patches the Secret" "PATCH .*secrets/s"
expect_called "  and revokes the old token" "DELETE .*tokens/tid-old"
expect_not_called "  and leaves other tokens alone" "DELETE .*tokens/tid-other"
expect_not_called "  and does not delete the new token" "DELETE .*tokens/tid-new"

export STUB_EXPIRES=2026-11-05T12:00:00.000Z
run "reads a fractional-second timestamp and a non-zero hour" "expires in 36h"

# The CronJob exists before the install hook has minted the first token.
export STUB_SECRET=404
run "exits cleanly while the install hook has not created the Secret yet" "does not exist yet"
expect_not_called "  and makes no Graylog call" "users/"
unset STUB_SECRET
export STUB_SECRET=500
run "fails on a Secret read error other than 404" "not readable (HTTP 500)"
unset STUB_SECRET

export STUB_EXPIRES=2026-11-07T00:00:00.000Z STUB_PATCH=403
run "deletes the new token when the Secret write fails" "writing Secret s failed"
expect_called "  and removes the orphan" "DELETE .*tokens/tid-new"
expect_not_called "  and keeps the old token" "DELETE .*tokens/tid-old"
unset STUB_PATCH

export STUB_EXPIRES=""
run "leaves a token with no expiry alone" "has no expiry"
export STUB_EXPIRES=2026-11-07T00:00:00.000Z

export STUB_USERS=401
run "points at helm upgrade when the token is rejected" "no longer authenticates"
unset STUB_USERS

export STUB_USERS=403
run "names the permission when reading the user is refused" "users:read,tokencreate,tokenlist,tokenremove:helm-automation"
unset STUB_USERS

export STUB_LIST=403
run "names the permission when listing tokens is refused" "listing tokens was refused"
unset STUB_LIST

export STUB_MINT=403
run "names the permission when minting is refused" "creating a token was refused"
expect_not_called "  and does not touch the Secret" "PATCH"
expect_not_called "  and keeps the old token" "DELETE"
unset STUB_MINT

# A 200 whose body holds no token must not rotate anything either.
export STUB_MINT_BODY='{"id":"tid-new","name":"helm"}'
run "refuses a mint response that carries no token" "carried no token"
expect_not_called "  and does not touch the Secret" "PATCH"
expect_not_called "  and keeps the old token" "DELETE"
unset STUB_MINT_BODY

# The mint call dies on a network error (curl exits non-zero, prints nothing).
export STUB_MINT=000
run "refuses an unreadable mint response" "creating the token failed"
expect_not_called "  and does not touch the Secret" "PATCH"
expect_not_called "  and keeps the old token" "DELETE"
unset STUB_MINT

exit "$fail"
