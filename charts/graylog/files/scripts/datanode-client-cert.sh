#!/bin/sh
# Issue a client certificate for the Data Node's OpenSearch API and store it in a
# Kubernetes Secret. Runs as a Helm post-install/post-upgrade hook Job after the API
# token Job.
#
# 1. Create the OpenSearch role and an empty role mapping on a Data Node, signing a
#    short-lived JWT with the password secret. Graylog's API cannot do this, and
#    POST /api/ca/clientcert refuses a role that has no mapping.
# 2. Ask Graylog for a client certificate with the API token (POST /api/ca/clientcert).
# 3. Decrypt the private key, since a consumer cannot read the encrypted one the API
#    returns, and write the CA, certificate and key to the Secret.
#
# Idempotent: when the Secret holds a certificate that is valid for more than
# RENEW_BEFORE_SECONDS, the script exits. Reissuing does not revoke the old
# certificate: revoking a hand-made role returns a 500, so old certificates age out.
#
# Environment: GRAYLOG_URL, DATANODE_URL, API_TOKEN, GRAYLOG_PASSWORD_SECRET,
# ROLE, ROLE_DEFINITION (JSON), PRINCIPAL, LIFETIME, RENEW_BEFORE_SECONDS,
# SECRET_NAME, SECRET_LABELS (JSON object), NAMESPACE, WAIT_SECONDS, and optionally
# CURL_EXTRA (extra curl flags for calls to Graylog). Needs sh, curl, openssl, sed,
# grep, tr and base64: the Graylog image has them all.
set -u

TMP="$(mktemp -d)"; chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

API="${GRAYLOG_URL}/api"
K8S="https://kubernetes.default.svc/api/v1/namespaces/${NAMESPACE}/secrets"
SA="/var/run/secrets/kubernetes.io/serviceaccount"
SEC="/_plugins/_security/api"

log() { echo "datanode-client-cert: $*"; }
die() { log "error: $*"; exit 1; }

status_of() { printf '%s' "$1" | tail -n 1; }
body_of() { printf '%s' "$1" | sed '$d'; }
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Pull the first string value for a key out of a JSON document on stdin, turning the
# \n escapes in a PEM back into newlines.
jstr() { grep -o "\"$1\":\"[^\"]*\"" | head -n 1 | sed "s/^\"$1\":\"//; s/\"\$//; s/\\\\n/\\
/g"; }

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

# Data Node security API call as an admin, authenticated with a fresh HS256 JWT.
# Verified against the cluster CA when the Secret already holds it. The very first
# run has no CA to check against yet, so it skips verification for this one
# in-cluster call.
DN_TLS="-k"
[ -s "$TMP/ca.crt" ] && DN_TLS="--cacert $TMP/ca.crt"
dn_api() {
  method="$1"; path="$2"; body="${3:-}"
  now="$(date +%s)"
  h="$(printf '{"alg":"HS256","typ":"JWT"}' | b64url)"
  p="$(printf '{"sub":"admin","os_roles":["admin"],"iat":%s,"exp":%s}' "$now" "$((now + 300))" | b64url)"
  s="$(printf '%s.%s' "$h" "$p" | openssl dgst -sha256 -hmac "$GRAYLOG_PASSWORD_SECRET" -binary | b64url)"
  if [ -n "$body" ]; then
    # shellcheck disable=SC2086
    curl -sS --max-time 30 $DN_TLS -X "$method" -H "Authorization: Bearer $h.$p.$s" \
      -H "Content-Type: application/json" -d "$body" -w '\n%{http_code}' "${DATANODE_URL}${path}"
  else
    # shellcheck disable=SC2086
    curl -sS --max-time 30 $DN_TLS -X "$method" -H "Authorization: Bearer $h.$p.$s" \
      -w '\n%{http_code}' "${DATANODE_URL}${path}"
  fi
}

# 1. Look at the Secret. A certificate with plenty of life left means nothing to do.
existing="$(k8s GET "${K8S}/${SECRET_NAME}" "application/json")"
if [ "$(status_of "$existing")" = "200" ]; then
  body_of "$existing" | jstr 'tls.crt' | base64 -d > "$TMP/cur.crt" 2>/dev/null
  body_of "$existing" | jstr 'ca.crt' | base64 -d > "$TMP/ca.crt" 2>/dev/null
  if [ -s "$TMP/cur.crt" ] && openssl x509 -in "$TMP/cur.crt" -noout -checkend "$RENEW_BEFORE_SECONDS" >/dev/null 2>&1; then
    log "Secret ${SECRET_NAME} holds a certificate valid for more than ${RENEW_BEFORE_SECONDS}s, nothing to do"
    exit 0
  fi
  log "certificate in ${SECRET_NAME} is missing or close to expiry, reissuing"
  [ -s "$TMP/ca.crt" ] && DN_TLS="--cacert $TMP/ca.crt"
fi

# 2. Wait for Graylog and the Data Node. A hook does not wait for the pods unless
# helm --wait is set.
log "waiting up to ${WAIT_SECONDS}s for Graylog and the Data Node"
waited=0
until [ "$(curl -s -o /dev/null --max-time 5 ${CURL_EXTRA:-} -w '%{http_code}' "${API}/system/lbstatus")" = "200" ] \
  && [ "$(status_of "$(dn_api GET "/_cluster/health")")" = "200" ]; do
  [ "$waited" -ge "$WAIT_SECONDS" ] && die "Graylog or the Data Node did not become ready in ${WAIT_SECONDS}s"
  sleep 5; waited=$((waited + 5))
done

# 3. Make sure the role and an empty mapping exist. A PUT on the mapping replaces it,
# and issuing a certificate adds the principal to it, so only create what is missing.
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

# 4. Issue the certificate. The password only protects the key in transit.
pw="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)"
resp="$(curl -sS --max-time 30 ${CURL_EXTRA:-} -X POST -u "${API_TOKEN}:token" \
  -H "X-Requested-By: graylog-helm" -H "Content-Type: application/json" -H "Accept: application/json" \
  -d "{\"principal\":\"${PRINCIPAL}\",\"role\":\"${ROLE}\",\"password\":\"${pw}\",\"certificate_lifetime\":\"${LIFETIME}\"}" \
  -w '\n%{http_code}' "${API}/ca/clientcert")"
[ "$(status_of "$resp")" = "200" ] || die "issuing the certificate failed (HTTP $(status_of "$resp")): $(body_of "$resp")"
body_of "$resp" | jstr ca_certificate > "$TMP/new-ca.crt"
body_of "$resp" | jstr certificate > "$TMP/tls.crt"
body_of "$resp" | jstr private_key > "$TMP/key.enc"
printf '%s' "$pw" > "$TMP/pw"
openssl pkey -in "$TMP/key.enc" -passin "file:$TMP/pw" -out "$TMP/tls.key" 2>/dev/null \
  || die "could not decrypt the private key Graylog returned"
openssl x509 -in "$TMP/tls.crt" -noout >/dev/null 2>&1 || die "the certificate in the response is not valid PEM"
log "issued a certificate for ${PRINCIPAL}, valid until $(openssl x509 -in "$TMP/tls.crt" -noout -enddate | sed 's/notAfter=//')"

# 5. Store it. Merge-patch an existing Secret, create it otherwise. Helm does not own
# it, so a helm upgrade does not put the key in a release record.
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
