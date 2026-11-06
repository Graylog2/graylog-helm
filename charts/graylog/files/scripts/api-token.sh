#!/bin/sh
# Create a Graylog service user and an API token for it, keep the token in a
# Kubernetes Secret, and renew it before it expires. One script, two modes,
# chosen by MODE.
#
#   hook   Helm post-install/post-upgrade hook Job. Waits for Graylog, signs in as
#          root, creates the service user if it is missing, mints a token and
#          creates or patches the Secret.
#   renew  CronJob. Mints the replacement with the token the Secret already holds
#          and patches the Secret. It never sees the root password, so it cannot
#          create the user or the Secret. A missing Secret is left to the hook.
#
# Both modes read the Secret first. A token that still works and has more than
# RENEW_BEFORE_SECONDS left means nothing to do. Otherwise they mint a new token,
# store it, and only then delete the old one. A failed write deletes the new token
# again, so nothing is orphaned and the old token stays.
#
# The server picks the token value and returns it exactly once, so this script
# cannot render it ahead of time or read it back later. It writes the Secret
# itself through the Kubernetes API.
#
# A token that is already expired or revoked cannot renew itself. The next helm
# upgrade fixes that, because the hook signs in as root. The service user needs
# users:tokenlist, users:tokencreate and users:tokenremove on itself for renew mode.
# The chart grants them in one comma form string: Graylog strips the plain
# per-permission self strings from a service account.
#
# Environment, both modes: MODE, GRAYLOG_URL, SERVICE_USER, TOKEN_NAME, TOKEN_TTL,
# SECRET_NAME, NAMESPACE, RENEW_BEFORE_SECONDS, and optionally CURL_EXTRA (extra
# curl flags for calls to Graylog, "-k" or "--cacert <file>") and NOW_EPOCH
# (current time, for tests). Hook only: ROOT_USER, ROOT_PASSWORD, SERVICE_ROLES
# (JSON array), SERVICE_PERMISSIONS (JSON array, optional), SECRET_LABELS (JSON
# object), SECRET_ANNOTATIONS (JSON object, optional), WAIT_SECONDS.
# Authored for the curlimages/curl image: POSIX sh, curl, sed, grep and base64
# only, so JSON is picked apart with sed rather than jq.
#
# Passwords, tokens and request bodies never reach a command line, where ps would
# show them. Credentials go to curl in config files under a private temp
# directory (-K), and bodies go through stdin (--data-binary @-). printf is a
# shell builtin, so it does not start a process either.
set -u
umask 077
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MODE="${MODE:-hook}"
case "$MODE" in
  hook|renew) ;;
  *) echo "api-token: error: MODE must be hook or renew, got ${MODE}"; exit 1 ;;
esac

# The Kubernetes API calls below are curl too, so the flags are applied per call
# through gl_curl rather than by wrapping curl itself.
gl_curl() { command curl ${CURL_EXTRA:-} "$@"; }

# Escape a value for a double-quoted curl config string.
cfg_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
printf 'header = "Authorization: Bearer %s"\n' "$(cat "/var/run/secrets/kubernetes.io/serviceaccount/token" 2>/dev/null)" > "${TMP}/k8s"
SECRET_ANNOTATIONS="${SECRET_ANNOTATIONS:-}"
[ -n "$SECRET_ANNOTATIONS" ] || SECRET_ANNOTATIONS='{}'

API="${GRAYLOG_URL}/api"
K8S="https://kubernetes.default.svc/api/v1/namespaces/${NAMESPACE}/secrets"
SA="/var/run/secrets/kubernetes.io/serviceaccount"

log() { echo "api-token: $*"; }
die() { log "error: $*"; exit 1; }

# Pull the first string value for a key out of a JSON document on stdin. The
# Kubernetes API pretty-prints for curl ("token": "x"), Graylog does not
# ("token":"x"), so allow whitespace around the colon.
jstr() { grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 | sed "s/^\"$1\"[[:space:]]*:[[:space:]]*\"//; s/\"\$//"; }
status_of() { printf '%s' "$1" | tail -n 1; }
body_of() { printf '%s' "$1" | sed '$d'; }
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

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

# Graylog request as whoever AUTH names: root in hook mode, the service user's own
# token in renew mode. Prints the body, then the status on its own line.
AUTH="${TMP}/root"
api() {
  method="$1"; path="$2"; body="${3:-}"
  if [ -n "$body" ]; then
    printf '%s' "$body" | gl_curl -sS --max-time 30 -X "$method" -K "$AUTH" \
      -H "X-Requested-By: graylog-helm" -H "Content-Type: application/json" \
      -H "Accept: application/json" --data-binary @- -w '\n%{http_code}' "${API}${path}"
  else
    gl_curl -sS --max-time 30 -X "$method" -K "$AUTH" \
      -H "X-Requested-By: graylog-helm" -H "Accept: application/json" \
      -w '\n%{http_code}' "${API}${path}"
  fi
}

# Renew mode authenticates with the token: Basic auth, token as the username.
use_token() {
  printf 'user = "%s:token"\n' "$(cfg_escape "$1")" > "${TMP}/tok"
  AUTH="${TMP}/tok"
}

PERMISSION_HINT="the service user needs users:tokencreate,tokenlist,tokenremove:${SERVICE_USER}. The chart grants it when it creates the user. Add it to an existing user by hand, then see docs/graylog/api-token.md"

# 1. Hook mode: wait for Graylog. A hook does not wait for the pods unless helm
# --wait is set.
if [ "$MODE" = hook ]; then
  printf 'user = "%s:%s"\n' "$(cfg_escape "$ROOT_USER")" "$(cfg_escape "$ROOT_PASSWORD")" > "${TMP}/root"
  log "waiting up to ${WAIT_SECONDS}s for Graylog at ${GRAYLOG_URL}"
  waited=0
  until [ "$(gl_curl -s -o /dev/null --max-time 5 -w '%{http_code}' "${API}/system/lbstatus")" = "200" ]; do
    [ "$waited" -ge "$WAIT_SECONDS" ] && die "Graylog did not become ready in ${WAIT_SECONDS}s"
    sleep 5; waited=$((waited + 5))
  done
fi

# 2. Look at the Secret.
existing="$(k8s GET "${K8S}/${SECRET_NAME}" "application/json")"
TOKEN=""; user_id=""
case "$(status_of "$existing")" in
  200)
    TOKEN="$(body_of "$existing" | jstr token | base64 -d 2>/dev/null)"
    user_id="$(body_of "$existing" | jstr userid | base64 -d 2>/dev/null)"
    ;;
  404)
    # No Secret yet is normal for the first minutes of an install: the CronJob
    # exists before the install hook has finished minting the first token. A
    # renewal has no root password to create the user with, so it leaves this to
    # the hook, and a failing run would only be noise.
    if [ "$MODE" = renew ]; then
      log "Secret ${SECRET_NAME} does not exist yet, so there is no token to renew. The install or upgrade hook creates it"
      exit 0
    fi
    ;;
  *) die "Secret ${SECRET_NAME} not readable (HTTP $(status_of "$existing"))" ;;
esac

# 3. Is the stored token still good, and how long does it have? Renew mode checks
# as the token itself and needs the user id from the Secret: looking it up by name
# needs users:edit on itself, which would let the user change its own roles, so it
# is not granted. Hook mode checks the token against the service user's own record
# first. Graylog answers 401 for a token it does not accept and 403 for one it
# accepts but whose roles may not read that record (Reader, for one). Only 401
# means the token is bad, so 200 and 403 both keep it.
keep=""
if [ "$MODE" = renew ]; then
  [ -n "$TOKEN" ] || die "Secret ${SECRET_NAME} has no token. Run helm upgrade to create it"
  [ -n "$user_id" ] || die "Secret ${SECRET_NAME} has no userid key. Run helm upgrade, which adds it"
  use_token "$TOKEN"
  keep=1
elif [ -n "$TOKEN" ]; then
  printf 'user = "%s:token"\n' "$(cfg_escape "$TOKEN")" > "${TMP}/old"
  code="$(gl_curl -s -o /dev/null --max-time 10 -K "${TMP}/old" -w '%{http_code}' "${API}/users/${SERVICE_USER}")"
  if [ "$code" = "200" ] || [ "$code" = "403" ]; then
    keep=1
    # The renewal CronJob needs the user id and cannot look it up, so a Secret
    # from before it was stored there gets it now. Best effort: a failure here
    # must not fail a run that has nothing else to do.
    if [ -z "$user_id" ]; then
      user_id="$(api GET "/users/${SERVICE_USER}" | sed '$d' | jstr id)"
      [ -n "$user_id" ] && k8s PATCH "${K8S}/${SECRET_NAME}" "application/merge-patch+json" "{\"data\":{\"userid\":\"$(b64 "$user_id")\"}}" >/dev/null && log "added the user id to Secret ${SECRET_NAME}"
    fi
  else
    log "token in ${SECRET_NAME} no longer authenticates (HTTP ${code}), replacing it"
  fi
fi

# The token list of the user, split to one token per line. Several tokens can
# share the name; the one that lives longest is the one the Secret holds.
list_tokens() {
  resp="$(api GET "/users/${user_id}/tokens")"
  list_status="$(status_of "$resp")"
  mine="$(body_of "$resp" | tr '{}' '\n\n' | grep "\"name\":\"${TOKEN_NAME}\"")"
  old_ids="$(printf '%s\n' "$mine" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
}

if [ -n "$keep" ] && [ -n "$user_id" ]; then
  list_tokens
  case "$list_status" in
    200) ;;
    401) die "the token in ${SECRET_NAME} no longer authenticates. Run helm upgrade: the hook Job signs in as root and mints a new one" ;;
    403) die "listing tokens was refused: ${PERMISSION_HINT}" ;;
    *) die "listing tokens failed (HTTP ${list_status}): $(body_of "$resp")" ;;
  esac
  [ -n "$mine" ] || die "no token named ${TOKEN_NAME} on ${SERVICE_USER}. Run helm upgrade to create one"
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
    log "Secret ${SECRET_NAME} holds a working token that expires in $(fmt "$left"), more than the $(fmt "$RENEW_BEFORE_SECONDS") renewal window, nothing to do"
    exit 0
  fi
  log "token expires in $(fmt "$left"), inside the $(fmt "$RENEW_BEFORE_SECONDS") renewal window, renewing"
elif [ -n "$keep" ]; then
  # Hook mode, working token, and the user id could not be found: nothing to
  # measure, so leave it.
  log "Secret ${SECRET_NAME} already holds a working token, nothing to do"
  exit 0
fi

# 4. Hook mode: make sure the service user exists, authenticating as root.
if [ "$MODE" = hook ] && [ -z "$keep" ]; then
  resp="$(api GET "/users/${SERVICE_USER}")"
  case "$(status_of "$resp")" in
    200) log "service user ${SERVICE_USER} exists" ;;
    404)
      # The password is required by the API but never used: a service account cannot
      # sign in, and nothing keeps this value.
      pw="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)"
      payload="{\"username\":\"${SERVICE_USER}\",\"password\":\"${pw}\",\"email\":\"${SERVICE_USER}@graylog-helm.invalid\",\"first_name\":\"Helm\",\"last_name\":\"Automation\",\"permissions\":${SERVICE_PERMISSIONS:-[]},\"roles\":${SERVICE_ROLES},\"service_account\":true}"
      resp="$(api POST "/users" "$payload")"
      [ "$(status_of "$resp")" = "201" ] || die "creating user ${SERVICE_USER} failed (HTTP $(status_of "$resp")): $(body_of "$resp")"
      log "created service user ${SERVICE_USER}"
      resp="$(api GET "/users/${SERVICE_USER}")"
      ;;
    *) die "looking up user ${SERVICE_USER} failed (HTTP $(status_of "$resp")): $(body_of "$resp")" ;;
  esac
  user_id="$(body_of "$resp" | jstr id)"
  [ -n "$user_id" ] || die "could not read the id of user ${SERVICE_USER}"
  # Remember the tokens already carrying our name so they can be retired.
  list_tokens
fi

# 5. Mint the new token, with root in hook mode and with the old token in renew mode.
resp="$(api POST "/users/${user_id}/tokens/${TOKEN_NAME}" "{\"token_ttl\":\"${TOKEN_TTL}\"}")"
case "$(status_of "$resp")" in
  200) ;;
  403) die "creating a token was refused: ${PERMISSION_HINT}" ;;
  *) die "creating the token failed (HTTP $(status_of "$resp")): $(body_of "$resp")" ;;
esac
new_token="$(body_of "$resp" | jstr token)"
new_id="$(body_of "$resp" | jstr id)"
[ -n "$new_token" ] || die "the token response carried no token"

# 6. Store it. A token that is minted but not stored is unrecoverable, so delete
# it again rather than leave it orphaned if the write fails. One request writes
# every key. The Secret is not owned by Helm, so a helm upgrade does not put the
# token in a release record.
data="\"token\":\"$(b64 "$new_token")\",\"username\":\"$(b64 "$SERVICE_USER")\",\"userid\":\"$(b64 "$user_id")\""
if [ "$(status_of "$existing")" = "200" ]; then
  out="$(k8s PATCH "${K8S}/${SECRET_NAME}" "application/merge-patch+json" "{\"data\":{${data}}}")"
else
  out="$(k8s POST "${K8S}" "application/json" "{\"apiVersion\":\"v1\",\"kind\":\"Secret\",\"metadata\":{\"name\":\"${SECRET_NAME}\",\"labels\":${SECRET_LABELS},\"annotations\":${SECRET_ANNOTATIONS}},\"type\":\"Opaque\",\"data\":{${data}}}")"
fi
case "$(status_of "$out")" in
  200|201) log "stored the new token in Secret ${SECRET_NAME}" ;;
  *)
    api DELETE "/users/${user_id}/tokens/${new_id}" >/dev/null
    die "writing Secret ${SECRET_NAME} failed (HTTP $(status_of "$out")): $(body_of "$out")"
    ;;
esac

# 7. Retire the old tokens only once the new one is safely stored. Renew mode
# switches to the new token first: deleting the old one with itself would leave
# nothing to authenticate the rest of the deletes.
[ "$MODE" = renew ] && use_token "$new_token"
for id in $old_ids; do
  [ "$id" = "$new_id" ] && continue
  api DELETE "/users/${user_id}/tokens/${id}" >/dev/null
  log "revoked previous token ${id}"
done
log "done"
