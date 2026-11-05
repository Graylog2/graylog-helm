#!/bin/sh
# Renew the Graylog API token held in a Kubernetes Secret before it expires.
# Runs as a CronJob. Unlike api-token.sh it never sees the root password: the
# service user mints its replacement with the token it already has.
#
# Steps: read the token and user id from the Secret, look up the token's expiry, and when less
# than RENEW_BEFORE_SECONDS remain, mint a new token, store it in the Secret and
# only then delete the old one. A token that is already expired or revoked cannot
# renew itself. The next helm upgrade fixes that, because the hook Job signs in
# as root.
#
# The service user needs users:tokenlist, users:tokencreate and users:tokenremove
# on itself. The chart grants them in one comma form string: Graylog strips the
# plain per-permission self strings from a service account.
#
# Environment: GRAYLOG_URL, SERVICE_USER, TOKEN_NAME, TOKEN_TTL, SECRET_NAME,
# NAMESPACE, RENEW_BEFORE_SECONDS, and optionally CURL_EXTRA (extra curl flags for
# calls to Graylog) and NOW_EPOCH (current time, for tests). Authored for the
# curlimages/curl image: POSIX sh, curl, sed, grep and base64 only.
#
# The token and the Kubernetes bearer token never reach a command line, where ps
# would show them. Credentials go to curl in config files under a private temp
# directory (-K), and bodies go through stdin (--data-binary @-).
set -u
umask 077
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

gl_curl() { command curl ${CURL_EXTRA:-} "$@"; }

# Escape a value for a double-quoted curl config string.
cfg_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
printf 'header = "Authorization: Bearer %s"\n' "$(cat "/var/run/secrets/kubernetes.io/serviceaccount/token" 2>/dev/null)" > "${TMP}/k8s"

API="${GRAYLOG_URL}/api"
K8S="https://kubernetes.default.svc/api/v1/namespaces/${NAMESPACE}/secrets"
SA="/var/run/secrets/kubernetes.io/serviceaccount"

log() { echo "api-token-renew: $*"; }
die() { log "error: $*"; exit 1; }

jstr() { grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 | sed "s/^\"$1\"[[:space:]]*:[[:space:]]*\"//; s/\"\$//"; }
status_of() { printf '%s' "$1" | tail -n 1; }
body_of() { printf '%s' "$1" | sed '$d'; }

# Seconds since the epoch for 2026-11-05T00:05:33.055Z. Done in shell arithmetic
# because busybox and GNU date disagree on parsing and BSD date has no -d.
epoch() {
  set -- $(printf '%s' "$1" | sed 's/[-T:Z]/ /g; s/\.[0-9]*//; s/ 0*\([0-9]\)/ \1/g')
  y=$1; m=$2; d=$3
  [ "$m" -le 2 ] && y=$((y - 1))
  era=$((y / 400)); yoe=$((y - era * 400))
  doy=$(( (153 * ((m + 9) % 12) + 2) / 5 + d - 1 ))
  doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  echo $(( (era * 146097 + doe - 719468) * 86400 + $4 * 3600 + $5 * 60 + $6 ))
}

# 90000 -> 1d1h, 5415 -> 1h30m, 250 -> 4m10s. Short test lifetimes need the minutes.
fmt() {
  if [ "$1" -ge 86400 ]; then echo "$(($1 / 86400))d$(($1 % 86400 / 3600))h"
  elif [ "$1" -ge 3600 ]; then echo "$(($1 / 3600))h$(($1 % 3600 / 60))m"
  else echo "$(($1 / 60))m$(($1 % 60))s"; fi
}

k8s() {
  method="$1"; url="$2"; ctype="$3"; body="${4:-}"
  if [ -n "$body" ]; then
    printf '%s' "$body" | curl -sS --max-time 30 -X "$method" --cacert "${SA}/ca.crt" -K "${TMP}/k8s" \
      -H "Content-Type: ${ctype}" --data-binary @- -w '\n%{http_code}' "$url"
  else
    curl -sS --max-time 30 -X "$method" --cacert "${SA}/ca.crt" -K "${TMP}/k8s" \
      -w '\n%{http_code}' "$url"
  fi
}

# Graylog request as the service user, authenticating with the token.
token_api() {
  method="$1"; path="$2"; body="${3:-}"
  printf 'user = "%s:token"\n' "$(cfg_escape "$TOKEN")" > "${TMP}/tok"
  if [ -n "$body" ]; then
    printf '%s' "$body" | gl_curl -sS --max-time 30 -X "$method" -K "${TMP}/tok" \
      -H "X-Requested-By: graylog-helm" -H "Content-Type: application/json" \
      -H "Accept: application/json" --data-binary @- -w '\n%{http_code}' "${API}${path}"
  else
    gl_curl -sS --max-time 30 -X "$method" -K "${TMP}/tok" \
      -H "X-Requested-By: graylog-helm" -H "Accept: application/json" \
      -w '\n%{http_code}' "${API}${path}"
  fi
}

PERMISSION_HINT="the service user needs users:tokencreate,tokenlist,tokenremove:${SERVICE_USER}. The chart grants it when it creates the user. Add it to an existing user by hand, then see docs/graylog/api-token.md"

# 1. The current token.
existing="$(k8s GET "${K8S}/${SECRET_NAME}" "application/json")"
# No Secret yet is normal for the first minutes of an install: this CronJob exists
# before the install hook Job has finished minting the first token, which waits
# for Graylog to start. There is nothing to renew, and a failing run would only be
# noise. If the hook fails, Helm reports that.
case "$(status_of "$existing")" in
  200) ;;
  404) log "Secret ${SECRET_NAME} does not exist yet, so there is no token to renew. The install or upgrade hook creates it"; exit 0 ;;
  *) die "Secret ${SECRET_NAME} not readable (HTTP $(status_of "$existing"))" ;;
esac
TOKEN="$(body_of "$existing" | jstr token | base64 -d 2>/dev/null)"
[ -n "$TOKEN" ] || die "Secret ${SECRET_NAME} has no token. Run helm upgrade to create it"

# 2. The service user's id, which the token endpoints take instead of the name.
# The hook stores it in the Secret. Looking it up by name needs users:edit on
# itself, which would let the user change its own roles, so it is not granted.
user_id="$(body_of "$existing" | jstr userid | base64 -d 2>/dev/null)"
[ -n "$user_id" ] || die "Secret ${SECRET_NAME} has no userid key. Run helm upgrade, which adds it"

# 3. How long the token has left. Several tokens can share the name; the one that
# lives longest is the one the Secret holds.
resp="$(token_api GET "/users/${user_id}/tokens")"
case "$(status_of "$resp")" in
  200) ;;
  401) die "the token in ${SECRET_NAME} no longer authenticates. Run helm upgrade: the hook Job signs in as root and mints a new one" ;;
  403) die "listing tokens was refused: ${PERMISSION_HINT}" ;;
  *) die "listing tokens failed (HTTP $(status_of "$resp")): $(body_of "$resp")" ;;
esac
mine="$(body_of "$resp" | tr '{}' '\n\n' | grep "\"name\":\"${TOKEN_NAME}\"")"
[ -n "$mine" ] || die "no token named ${TOKEN_NAME} on ${SERVICE_USER}. Run helm upgrade to create one"
old_ids="$(printf '%s\n' "$mine" | sed 's/.*"id":"\([^"]*\)".*/\1/')"
newest=0
for stamp in $(printf '%s\n' "$mine" | grep -o '"expires_at":"[^"]*"' | sed 's/.*:"//; s/"$//'); do
  e="$(epoch "$stamp")"
  [ "$e" -gt "$newest" ] && newest="$e"
done
if [ "$newest" -eq 0 ]; then
  log "token ${TOKEN_NAME} has no expiry, nothing to do"
  exit 0
fi
now="${NOW_EPOCH:-$(date +%s)}"
left=$((newest - now))
if [ "$left" -gt "$RENEW_BEFORE_SECONDS" ]; then
  log "token expires in $(fmt "$left"), more than the $(fmt "$RENEW_BEFORE_SECONDS") renewal window, nothing to do"
  exit 0
fi
log "token expires in $(fmt "$left"), inside the $(fmt "$RENEW_BEFORE_SECONDS") renewal window, renewing"

# 4. Mint the replacement with the old token.
resp="$(token_api POST "/users/${user_id}/tokens/${TOKEN_NAME}" "{\"token_ttl\":\"${TOKEN_TTL}\"}")"
case "$(status_of "$resp")" in
  200) ;;
  403) die "creating a token was refused: ${PERMISSION_HINT}" ;;
  *) die "creating the token failed (HTTP $(status_of "$resp")): $(body_of "$resp")" ;;
esac
new_token="$(body_of "$resp" | jstr token)"
new_id="$(body_of "$resp" | jstr id)"
[ -n "$new_token" ] || die "the token response carried no token"

# 5. Store it. A token that is minted but not stored is unrecoverable, so delete
# it again rather than leave it orphaned if the write fails.
new_b64="$(printf '%s' "$new_token" | base64 | tr -d '\n')"
out="$(k8s PATCH "${K8S}/${SECRET_NAME}" "application/merge-patch+json" "{\"data\":{\"token\":\"${new_b64}\"}}")"
case "$(status_of "$out")" in
  200) log "stored the new token in Secret ${SECRET_NAME}" ;;
  *)
    token_api DELETE "/users/${user_id}/tokens/${new_id}" >/dev/null
    die "writing Secret ${SECRET_NAME} failed (HTTP $(status_of "$out")): $(body_of "$out")"
    ;;
esac

# 6. Retire the old tokens only once the new one is safely stored. Switch to the
# new token first: deleting the old one with itself would leave nothing to
# authenticate the rest of the deletes.
TOKEN="$new_token"
for id in $old_ids; do
  [ "$id" = "$new_id" ] && continue
  token_api DELETE "/users/${user_id}/tokens/${id}" >/dev/null
  log "revoked previous token ${id}"
done
log "done"
