#!/bin/sh
# Issue a client certificate for the Data Node's OpenSearch API and keep it in a
# Kubernetes Secret. One script, two modes, chosen by MODE.
#
#   hook   Helm post-install/post-upgrade hook Job, after the API token Job. Waits
#          for Graylog and the Data Node, creates the OpenSearch role and an empty
#          mapping if they are missing, issues the certificate and creates or
#          patches the Secret.
#   renew  CronJob. Reissues the certificate before it expires and patches the
#          Secret, or creates the Secret when it is gone, for example after someone
#          deleted it. It never signs in as root, never reads the password secret and
#          never calls the Data Node, so it needs none of the setup above. It needs
#          the role and mapping to exist already, which the hook creates.
#
# Both modes read the Secret first. A certificate valid for more than
# RENEW_BEFORE_SECONDS means nothing to do. Otherwise they ask Graylog for a
# certificate (POST /api/ca/clientcert) with the API token, decrypt the private key,
# since a consumer cannot read the encrypted one the API returns, and write ca.crt,
# tls.crt and tls.key to the Secret in one request. A failed write leaves the old
# certificate in place.
#
# The role mapping step belongs to the hook because Graylog's API cannot create a
# role, and POST /api/ca/clientcert refuses a role that has no mapping. The hook
# signs a short-lived JWT with the password secret to call the Data Node's security
# API. If the role is deleted later, a renewal fails and says so: run helm upgrade.
#
# Reissuing does not revoke the old certificate: revoking a hand-made role returns a
# 500, so old certificates age out.
#
# Environment, both modes: MODE, GRAYLOG_URL, API_TOKEN, ROLE, PRINCIPAL, LIFETIME,
# RENEW_BEFORE_SECONDS, SECRET_NAME, NAMESPACE, and optionally CURL_EXTRA (extra curl
# flags for calls to Graylog), and SECRET_LABELS (JSON object, for a Secret the script
# has to create). Hook only: DATANODE_URL, GRAYLOG_PASSWORD_SECRET, ROLE_DEFINITION
# (JSON), WAIT_SECONDS.
# Needs sh, curl, openssl, sed, grep, tr and base64: the Graylog image has them all.
#
# The API token, the JWT, the Kubernetes bearer token and the key password never
# reach a command line, where ps would show them. Credentials go to curl in config
# files under a private temp directory (-K), and bodies go through stdin
# (--data-binary @-).
set -u
umask 077
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MODE="${MODE:-hook}"
case "$MODE" in
  hook|renew) ;;
  *) echo "datanode-client-cert: error: MODE must be hook or renew, got ${MODE}"; exit 1 ;;
esac

API="${GRAYLOG_URL}/api"
K8S="https://kubernetes.default.svc/api/v1/namespaces/${NAMESPACE}/secrets"
SA="/var/run/secrets/kubernetes.io/serviceaccount"
SEC="/_plugins/_security/api"
printf 'header = "Authorization: Bearer %s"\n' "$(cat "${SA}/token" 2>/dev/null)" > "${TMP}/k8s"

log() { echo "datanode-client-cert: $*"; }
die() { log "error: $*"; exit 1; }

status_of() { printf '%s' "$1" | tail -n 1; }
body_of() { printf '%s' "$1" | sed '$d'; }
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Escape a value for a double-quoted curl config string.
cfg_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# 90000 -> 1d1h, 5415 -> 1h30m, 250 -> 4m10s.
fmt() {
  if [ "$1" -ge 86400 ]; then echo "$(($1 / 86400))d$(($1 % 86400 / 3600))h"
  elif [ "$1" -ge 3600 ]; then echo "$(($1 / 3600))h$(($1 % 3600 / 60))m"
  else echo "$(($1 / 60))m$(($1 % 60))s"; fi
}

# Pull the first string value for a key out of a JSON document on stdin, turning the
# \n escapes in a PEM back into newlines. The Kubernetes API pretty-prints when no
# Accept header is sent ("key": "value"), Graylog does not, so allow both.
jstr() { grep -o "\"$1\": *\"[^\"]*\"" | head -n 1 | sed "s/^\"$1\": *\"//; s/\"\$//; s/\\\\n/\\
/g"; }

# CURL_EXTRA holds flags, so it has to split into words.
# shellcheck disable=SC2086
gl_curl() { command curl ${CURL_EXTRA:-} "$@"; }

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

# Data Node security API call as an admin, authenticated with a fresh HS256 JWT.
# Verified against the cluster CA when the Secret already holds it. The very first
# run has no CA to check against yet, so it skips verification for this one
# in-cluster call. Hook mode only.
DN_TLS="-k"
dn_api() {
  method="$1"; path="$2"; body="${3:-}"
  now="$(date +%s)"
  h="$(printf '{"alg":"HS256","typ":"JWT"}' | b64url)"
  p="$(printf '{"sub":"admin","os_roles":["admin"],"iat":%s,"exp":%s}' "$now" "$((now + 300))" | b64url)"
  s="$(printf '%s.%s' "$h" "$p" | openssl dgst -sha256 -hmac "$GRAYLOG_PASSWORD_SECRET" -binary | b64url)"
  printf 'header = "Authorization: Bearer %s.%s.%s"\n' "$h" "$p" "$s" > "${TMP}/dn"
  if [ -n "$body" ]; then
    # shellcheck disable=SC2086
    printf '%s' "$body" | curl -sS --max-time 30 $DN_TLS -X "$method" -K "${TMP}/dn" \
      -H "Content-Type: application/json" --data-binary @- -w '\n%{http_code}' "${DATANODE_URL}${path}"
  else
    # shellcheck disable=SC2086
    curl -sS --max-time 30 $DN_TLS -X "$method" -K "${TMP}/dn" \
      -w '\n%{http_code}' "${DATANODE_URL}${path}"
  fi
}

# 1. Look at the Secret. A certificate with plenty of life left means nothing to do.
existing="$(k8s GET "${K8S}/${SECRET_NAME}" "application/json")"
case "$(status_of "$existing")" in
  200)
    body_of "$existing" | jstr 'tls.crt' | base64 -d > "$TMP/cur.crt" 2>/dev/null
    body_of "$existing" | jstr 'ca.crt' | base64 -d > "$TMP/ca.crt" 2>/dev/null
    if [ -s "$TMP/cur.crt" ] && openssl x509 -in "$TMP/cur.crt" -noout -checkend "$RENEW_BEFORE_SECONDS" >/dev/null 2>&1; then
      end="$(openssl x509 -in "$TMP/cur.crt" -noout -enddate | sed 's/notAfter=//')"
      log "certificate in ${SECRET_NAME} is valid until ${end}, more than the $(fmt "$RENEW_BEFORE_SECONDS") renewal window, nothing to do"
      exit 0
    fi
    log "certificate in ${SECRET_NAME} is missing or inside the $(fmt "$RENEW_BEFORE_SECONDS") renewal window, reissuing"
    [ -s "$TMP/ca.crt" ] && DN_TLS="--cacert $TMP/ca.crt"
    ;;
  404)
    # A missing Secret is expected on a first install, and after someone deletes it.
    # Both modes go on and create it below. A renewal that runs before the hook has
    # created the role mapping fails at the issue step without creating anything,
    # because Graylog refuses a certificate for a role with no mapping.
    log "Secret ${SECRET_NAME} does not exist, issuing a certificate and creating it"
    ;;
  *) die "Secret ${SECRET_NAME} not readable (HTTP $(status_of "$existing"))" ;;
esac

# 2. Wait for Graylog and the Data Node, then make sure the role and an empty mapping
# exist. A hook does not wait for the pods unless helm --wait is set. A PUT on the
# mapping replaces it, and issuing a certificate adds the principal to it, so only
# create what is missing.
if [ "$MODE" = hook ]; then
  log "waiting up to ${WAIT_SECONDS}s for Graylog and the Data Node"
  waited=0
  # shellcheck disable=SC2086
  until [ "$(curl -s -o /dev/null --max-time 5 ${CURL_EXTRA:-} -w '%{http_code}' "${API}/system/lbstatus")" = "200" ] \
    && [ "$(status_of "$(dn_api GET "/_cluster/health")")" = "200" ]; do
    [ "$waited" -ge "$WAIT_SECONDS" ] && die "Graylog or the Data Node did not become ready in ${WAIT_SECONDS}s"
    sleep 5; waited=$((waited + 5))
  done

  resp="$(dn_api GET "${SEC}/roles/${ROLE}")"
  if [ "$(status_of "$resp")" != "200" ]; then
    resp="$(dn_api PUT "${SEC}/roles/${ROLE}" "$ROLE_DEFINITION")"
    [ "$(status_of "$resp")" = "200" ] || [ "$(status_of "$resp")" = "201" ] \
      || die "creating role ${ROLE} failed (HTTP $(status_of "$resp")): $(body_of "$resp")"
    log "created role ${ROLE}"
  fi
  resp="$(dn_api GET "${SEC}/rolesmapping/${ROLE}")"
  if [ "$(status_of "$resp")" != "200" ]; then
    resp="$(dn_api PUT "${SEC}/rolesmapping/${ROLE}" '{"users":[],"backend_roles":[],"hosts":[]}')"
    [ "$(status_of "$resp")" = "200" ] || [ "$(status_of "$resp")" = "201" ] \
      || die "creating role mapping ${ROLE} failed (HTTP $(status_of "$resp")): $(body_of "$resp")"
    log "created role mapping ${ROLE}"
  fi
fi

# 3. Issue the certificate. The password only protects the key in transit. The token
# is the Basic auth user and "token" the password.
[ -n "${API_TOKEN:-}" ] || die "no API token. Check the Secret behind graylog.apiToken.secretName, or run helm upgrade to create it"
pw="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)"
printf 'user = "%s:token"\n' "$(cfg_escape "$API_TOKEN")" > "${TMP}/tok"
resp="$(printf '{"principal":"%s","role":"%s","password":"%s","certificate_lifetime":"%s"}' \
  "$PRINCIPAL" "$ROLE" "$pw" "$LIFETIME" \
  | gl_curl -sS --max-time 30 -X POST -K "${TMP}/tok" \
    -H "X-Requested-By: graylog-helm" -H "Content-Type: application/json" -H "Accept: application/json" \
    --data-binary @- -w '\n%{http_code}' "${API}/ca/clientcert")"
case "$(status_of "$resp")" in
  200) ;;
  401) die "the API token no longer authenticates. Run helm upgrade: the API token Job signs in as root and mints a new one" ;;
  403) die "issuing a certificate was refused. The token's user needs the ca_clientcert:create permission, see graylog.apiToken.permissions" ;;
  *) die "issuing the certificate failed (HTTP $(status_of "$resp")): $(body_of "$resp"). If the role ${ROLE} or its mapping is gone, run helm upgrade, which recreates them" ;;
esac
body_of "$resp" | jstr ca_certificate > "$TMP/new-ca.crt"
body_of "$resp" | jstr certificate > "$TMP/tls.crt"
body_of "$resp" | jstr private_key > "$TMP/key.enc"
printf '%s' "$pw" > "$TMP/pw"
openssl pkey -in "$TMP/key.enc" -passin "file:$TMP/pw" -out "$TMP/tls.key" 2>/dev/null \
  || die "could not decrypt the private key Graylog returned"
openssl x509 -in "$TMP/tls.crt" -noout >/dev/null 2>&1 || die "the certificate in the response is not valid PEM"
log "issued a certificate for ${PRINCIPAL}, valid until $(openssl x509 -in "$TMP/tls.crt" -noout -enddate | sed 's/notAfter=//')"

# 4. Store it. Merge-patch an existing Secret, create it otherwise. One request writes
# all three keys, so a consumer never sees a certificate with the wrong key. Helm
# does not own the Secret, so a helm upgrade does not put the key in a release record.
data="\"ca.crt\":\"$(base64 < "$TMP/new-ca.crt" | tr -d '\n')\",\"tls.crt\":\"$(base64 < "$TMP/tls.crt" | tr -d '\n')\",\"tls.key\":\"$(base64 < "$TMP/tls.key" | tr -d '\n')\""
if [ "$(status_of "$existing")" = "200" ]; then
  out="$(k8s PATCH "${K8S}/${SECRET_NAME}" "application/merge-patch+json" "{\"data\":{${data}}}")"
else
  out="$(k8s POST "${K8S}" "application/json" "{\"apiVersion\":\"v1\",\"kind\":\"Secret\",\"metadata\":{\"name\":\"${SECRET_NAME}\",\"labels\":${SECRET_LABELS}},\"type\":\"Opaque\",\"data\":{${data}}}")"
fi
case "$(status_of "$out")" in
  200|201) log "stored the certificate in Secret ${SECRET_NAME}" ;;
  *) die "writing Secret ${SECRET_NAME} failed (HTTP $(status_of "$out")): $(body_of "$out")" ;;
esac
log "done"
