#!/bin/sh
# Create a Graylog service user and an API token for it, and store the token in a
# Kubernetes Secret. Runs as a Helm post-install/post-upgrade hook Job.
#
# The server picks the token value and returns it exactly once, so this script
# cannot render it ahead of time or read it back later. It captures the response
# and writes the Secret itself through the Kubernetes API.
#
# Idempotent: when the Secret already holds a token that still authenticates, it
# exits without minting another. An expired or revoked token is replaced and the
# old one deleted.
#
# Environment: GRAYLOG_URL, ROOT_USER, ROOT_PASSWORD, SERVICE_USER, SERVICE_ROLES
# (JSON array), SERVICE_PERMISSIONS (JSON array, optional), TOKEN_NAME, TOKEN_TTL, SECRET_NAME, SECRET_LABELS (JSON object),
# NAMESPACE, WAIT_SECONDS, and optionally CURL_EXTRA (extra curl flags for calls to
# Graylog; "-k" when the in-cluster certificate cannot be verified). Authored for the curlimages/curl image: POSIX sh, curl,
# sed and grep only, so JSON is picked apart with sed rather than jq.
set -u

# The Kubernetes API calls below are curl too, so the flags are applied per call
# through gl_curl rather than by wrapping curl itself.
gl_curl() { command curl ${CURL_EXTRA:-} "$@"; }

API="${GRAYLOG_URL}/api"
K8S="https://kubernetes.default.svc/api/v1/namespaces/${NAMESPACE}/secrets"
SA="/var/run/secrets/kubernetes.io/serviceaccount"

log() { echo "api-token: $*"; }
die() { log "error: $*"; exit 1; }

# Pull the first string value for a key out of a JSON document on stdin. The
# Kubernetes API pretty-prints for curl ("token": "x"), Graylog does not
# ("token":"x"), so allow whitespace around the colon.
jstr() { grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 | sed "s/^\"$1\"[[:space:]]*:[[:space:]]*\"//; s/\"\$//"; }

# Graylog request as the root user. Prints the body, then the status on its own line.
root_api() {
  method="$1"; path="$2"; body="${3:-}"
  if [ -n "$body" ]; then
    gl_curl -sS --max-time 30 -X "$method" -u "${ROOT_USER}:${ROOT_PASSWORD}" \
      -H "X-Requested-By: graylog-helm" -H "Content-Type: application/json" \
      -H "Accept: application/json" -d "$body" -w '\n%{http_code}' "${API}${path}"
  else
    gl_curl -sS --max-time 30 -X "$method" -u "${ROOT_USER}:${ROOT_PASSWORD}" \
      -H "X-Requested-By: graylog-helm" -H "Accept: application/json" \
      -w '\n%{http_code}' "${API}${path}"
  fi
}
status_of() { printf '%s' "$1" | tail -n 1; }
body_of() { printf '%s' "$1" | sed '$d'; }

k8s() {
  method="$1"; url="$2"; ctype="$3"; body="${4:-}"
  if [ -n "$body" ]; then
    curl -sS --max-time 30 -X "$method" --cacert "${SA}/ca.crt" \
      -H "Authorization: Bearer $(cat ${SA}/token)" -H "Content-Type: ${ctype}" \
      -d "$body" -w '\n%{http_code}' "$url"
  else
    curl -sS --max-time 30 -X "$method" --cacert "${SA}/ca.crt" \
      -H "Authorization: Bearer $(cat ${SA}/token)" -w '\n%{http_code}' "$url"
  fi
}

# 1. Wait for Graylog. A hook does not wait for the pods unless helm --wait is set.
log "waiting up to ${WAIT_SECONDS}s for Graylog at ${GRAYLOG_URL}"
waited=0
until [ "$(gl_curl -s -o /dev/null --max-time 5 -w '%{http_code}' "${API}/system/lbstatus")" = "200" ]; do
  [ "$waited" -ge "$WAIT_SECONDS" ] && die "Graylog did not become ready in ${WAIT_SECONDS}s"
  sleep 5; waited=$((waited + 5))
done

# 2. Keep the existing token when it still works. Checked as the token itself
# (Basic auth, token as the username) against the service user's own record.
# Graylog answers 401 for a token it does not accept and 403 for one it accepts
# but whose roles may not read that record (Reader, for one). Only 401 means the
# token is bad, so 200 and 403 both keep it.
existing="$(k8s GET "${K8S}/${SECRET_NAME}" "application/json")"
if [ "$(status_of "$existing")" = "200" ]; then
  old_token="$(body_of "$existing" | jstr token | base64 -d 2>/dev/null)"
  if [ -n "$old_token" ]; then
    code="$(gl_curl -s -o /dev/null --max-time 10 -u "${old_token}:token" -w '%{http_code}' "${API}/users/${SERVICE_USER}")"
    if [ "$code" = "200" ] || [ "$code" = "403" ]; then
      # The renewal CronJob needs the user id and cannot look it up, so a Secret
      # from before it was stored there gets it now. Best effort: a failure here
      # must not fail a run that has nothing else to do.
      if [ -z "$(body_of "$existing" | jstr userid)" ]; then
        uid="$(root_api GET "/users/${SERVICE_USER}" | sed '$d' | jstr id)"
        [ -n "$uid" ] && k8s PATCH "${K8S}/${SECRET_NAME}" "application/merge-patch+json" "{\"data\":{\"userid\":\"$(printf '%s' "$uid" | base64 | tr -d '\n')\"}}" >/dev/null && log "added the user id to Secret ${SECRET_NAME}"
      fi
      log "Secret ${SECRET_NAME} already holds a working token, nothing to do"
      exit 0
    fi
    log "token in ${SECRET_NAME} no longer authenticates (HTTP ${code}), replacing it"
  fi
fi

# 3. Make sure the service user exists, authenticating as root.
resp="$(root_api GET "/users/${SERVICE_USER}")"
case "$(status_of "$resp")" in
  200) log "service user ${SERVICE_USER} exists" ;;
  404)
    # The password is required by the API but never used: a service account cannot
    # sign in, and nothing keeps this value.
    pw="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)"
    payload="{\"username\":\"${SERVICE_USER}\",\"password\":\"${pw}\",\"email\":\"${SERVICE_USER}@graylog-helm.invalid\",\"first_name\":\"Helm\",\"last_name\":\"Automation\",\"permissions\":${SERVICE_PERMISSIONS:-[]},\"roles\":${SERVICE_ROLES},\"service_account\":true}"
    resp="$(root_api POST "/users" "$payload")"
    [ "$(status_of "$resp")" = "201" ] || die "creating user ${SERVICE_USER} failed (HTTP $(status_of "$resp")): $(body_of "$resp")"
    log "created service user ${SERVICE_USER}"
    resp="$(root_api GET "/users/${SERVICE_USER}")"
    ;;
  *) die "looking up user ${SERVICE_USER} failed (HTTP $(status_of "$resp")): $(body_of "$resp")" ;;
esac
user_id="$(body_of "$resp" | jstr id)"
[ -n "$user_id" ] || die "could not read the id of user ${SERVICE_USER}"

# 4. Remember the tokens already carrying our name so they can be retired.
old_ids="$(root_api GET "/users/${user_id}/tokens" | sed '$d' | tr '{}' '\n\n' \
  | grep "\"name\":\"${TOKEN_NAME}\"" | sed 's/.*"id":"\([^"]*\)".*/\1/')"

# 5. Mint the new token.
resp="$(root_api POST "/users/${user_id}/tokens/${TOKEN_NAME}" "{\"token_ttl\":\"${TOKEN_TTL}\"}")"
[ "$(status_of "$resp")" = "200" ] || die "creating the token failed (HTTP $(status_of "$resp")): $(body_of "$resp")"
new_token="$(body_of "$resp" | jstr token)"
new_id="$(body_of "$resp" | jstr id)"
[ -n "$new_token" ] || die "the token response carried no token"

# 6. Store it. A token that is minted but not stored is unrecoverable, so revoke
# it again rather than leave it orphaned if the write fails.
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
data="\"token\":\"$(b64 "$new_token")\",\"username\":\"$(b64 "$SERVICE_USER")\",\"userid\":\"$(b64 "$user_id")\""
if [ "$(status_of "$existing")" = "200" ]; then
  out="$(k8s PATCH "${K8S}/${SECRET_NAME}" "application/merge-patch+json" "{\"data\":{${data}}}")"
else
  out="$(k8s POST "${K8S}" "application/json" "{\"apiVersion\":\"v1\",\"kind\":\"Secret\",\"metadata\":{\"name\":\"${SECRET_NAME}\",\"labels\":${SECRET_LABELS}},\"type\":\"Opaque\",\"data\":{${data}}}")"
fi
case "$(status_of "$out")" in
  200|201) log "stored the token in Secret ${SECRET_NAME}" ;;
  *)
    root_api DELETE "/users/${user_id}/tokens/${new_id}" >/dev/null
    die "writing Secret ${SECRET_NAME} failed (HTTP $(status_of "$out")): $(body_of "$out")"
    ;;
esac

# 7. Retire the previous tokens only once the new one is safely stored.
for id in $old_ids; do
  [ "$id" = "$new_id" ] && continue
  root_api DELETE "/users/${user_id}/tokens/${id}" >/dev/null
  log "revoked previous token ${id}"
done
log "done"
