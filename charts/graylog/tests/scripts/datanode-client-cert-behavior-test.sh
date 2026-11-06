#!/bin/sh
# Behavioural tests for files/scripts/datanode-client-cert.sh, in both of its modes.
#
#   renew  the CronJob: when does the script leave the certificate alone, when does
#          it reissue it, and what does it do when Graylog or the Secret write
#          fails. It must never touch the Data Node or create the Secret.
#   hook   the install and upgrade Job: does it wait for Graylog and the Data Node,
#          create a missing role and mapping, and create or patch the Secret.
#
# Run it:
#   sh charts/graylog/tests/scripts/datanode-client-cert-behavior-test.sh
#
# Needs openssl. The test makes real certificates with it, so the script's expiry
# check and key decryption run for real. A stub `curl` goes first on PATH. It serves
# the certificate Secret, the Data Node's security API, and answers
# POST /api/ca/clientcert by encrypting a fresh key with the password the script
# sends, the way Graylog does. Every call is appended to ${WORK}/calls so a scenario
# can assert which requests were made, and the PATCH and create bodies are kept in
# ${WORK}/patch and ${WORK}/create.
# STUB_CERT names the certificate the Secret holds (valid, soon, none), and
# STUB_SECRET, STUB_ISSUE, STUB_PATCH, STUB_CREATE, STUB_ROLE, STUB_MAPPING, STUB_PUT,
# STUB_GL_READY and STUB_DN_HEALTH override the status code of that call.
# STUB_BAD_KEY makes the issue response carry a key the password cannot open.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# SCRIPT overrides the script under test, so a mutation check can run against a copy.
SCRIPT="${SCRIPT:-${SCRIPT_DIR}/../../files/scripts/datanode-client-cert.sh}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A certificate that lasts 30 days and one that lasts 5. The window below is 10.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "${WORK}/old.key" -out "${WORK}/valid.crt" -days 30 -subj "/CN=old" 2>/dev/null
openssl req -x509 -newkey rsa:2048 -nodes -keyout "${WORK}/old.key" -out "${WORK}/soon.crt" -days 5 -subj "/CN=old" 2>/dev/null
# The certificate and key Graylog hands out on reissue.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "${WORK}/new.key" -out "${WORK}/new.crt" -days 30 -subj "/CN=graylog-client" 2>/dev/null
cp "${WORK}/new.crt" "${WORK}/new-ca.crt"
printf 'not a key\n' > "${WORK}/garbage.key"

cat > "${WORK}/curl" <<'STUB'
#!/bin/sh
method=GET; prev=""; stdin=""
for a in "$@"; do
  [ "$prev" = "-X" ] && method="$a"
  [ "$a" = "@-" ] && stdin=1
  prev="$a"; url="$a"
done
body=""; [ -z "$stdin" ] || body=$(cat)
printf '%s %s\n' "$method" "$url" >> "${WORK}/calls"
# printf, not echo: some shells expand the \n in -w '\n%{http_code}' and split the line.
printf '%s\n' "$*" >> "${WORK}/args"
code() { printf '\n%s' "$1"; }
b64() { base64 < "$1" | tr -d '\n'; }
esc() { awk '{printf "%s\\n", $0}' "$1"; }   # PEM to a JSON string body
case "$method $url" in
  # Graylog and the Data Node, which the hook waits for.
  "GET "*/api/system/lbstatus) printf '%s' "${STUB_GL_READY:-200}" ;;
  "GET "*/_cluster/health) printf '{}'; code "${STUB_DN_HEALTH:-200}" ;;
  "GET "*/_plugins/_security/api/roles/*) printf '{}'; code "${STUB_ROLE:-200}" ;;
  "GET "*/_plugins/_security/api/rolesmapping/*) printf '{}'; code "${STUB_MAPPING:-200}" ;;
  "PUT "*/_plugins/_security/api/*) printf '%s' "$body" >> "${WORK}/put"; printf '{}'; code "${STUB_PUT:-200}" ;;
  # The certificate Secret.
  "GET "*/secrets/*)
    [ "${STUB_SECRET:-200}" = 200 ] || { printf '{}'; code "$STUB_SECRET"; exit 0; }
    case "${STUB_CERT:-valid}" in
      none) printf '{\n  "data": {\n    "ca.crt": "eA=="\n  }\n}\n200' ;;
      *) printf '{\n  "data": {\n    "ca.crt": "eA==",\n    "tls.crt": "%s"\n  }\n}\n200' "$(b64 "${WORK}/${STUB_CERT:-valid}.crt")" ;;
    esac ;;
  "PATCH "*/secrets/*) printf '%s' "$body" > "${WORK}/patch"; printf '{}'; code "${STUB_PATCH:-200}" ;;
  "POST "*/secrets) printf '%s' "$body" > "${WORK}/create"; printf '{}'; code "${STUB_CREATE:-201}" ;;
  "POST "*/api/ca/clientcert)
    printf '%s' "$body" > "${WORK}/issue-body"
    [ "${STUB_ISSUE:-200}" = 200 ] || { printf '{"message":"nope"}'; code "$STUB_ISSUE"; exit 0; }
    pw=$(printf '%s' "$body" | sed 's/.*"password":"\([^"]*\)".*/\1/')
    printf '%s' "$pw" > "${WORK}/pw"
    if [ -n "${STUB_BAD_KEY:-}" ]; then
      enc="${WORK}/garbage.key"
    else
      openssl pkcs8 -topk8 -in "${WORK}/new.key" -v2 aes256 -passout "file:${WORK}/pw" -out "${WORK}/enc.key" || echo "stub: openssl pkcs8 failed" >&2
      enc="${WORK}/enc.key"
    fi
    printf '{"ca_certificate":"%s","certificate":"%s","private_key":"%s"}' \
      "$(esc "${WORK}/new-ca.crt")" "$(esc "${WORK}/new.crt")" "$(esc "$enc")"
    code 200 ;;
  *) code 500 ;;
esac
STUB
chmod +x "${WORK}/curl"

fail=0
# name, expected log fragment. The scenario's STUB_* and MODE are exported by the
# caller. Hook-only inputs are always set, and renew mode must ignore them.
run() {
  : > "${WORK}/calls"; : > "${WORK}/args"; rm -f "${WORK}/patch" "${WORK}/create" "${WORK}/put" "${WORK}/issue-body"
  # A watchdog kills a script that never finishes, so a broken wait loop fails the
  # suite in 45 seconds instead of stalling CI. exec makes the subshell the script
  # itself, so the kill reaches it.
  ( WORK="$WORK" PATH="${WORK}:${PATH}" MODE="${MODE-renew}" GRAYLOG_URL=http://g:9000 \
    API_TOKEN="${API_TOKEN-tok-secret}" ROLE=graylog_metrics_reader PRINCIPAL=graylog-client LIFETIME=P30D \
    SECRET_NAME=s NAMESPACE=n RENEW_BEFORE_SECONDS=864000 \
    DATANODE_URL=https://dn:9200 GRAYLOG_PASSWORD_SECRET=pwsecret WAIT_SECONDS=0 \
    ROLE_DEFINITION='{"cluster_permissions":["cluster_monitor"]}' SECRET_LABELS='{"app":"graylog-app"}' \
    exec sh "$SCRIPT" > "${WORK}/out" 2>&1 ) &
  pid=$!
  ( sleep 45; kill "$pid" 2>/dev/null ) &
  watchdog=$!
  wait "$pid"; rc=$?
  kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
  out=$(cat "${WORK}/out")
  [ "$rc" -lt 128 ] || out="${out}
TIMED OUT: the script did not finish in 45 seconds"
  case "$out" in
    *"$2"*) echo "ok   $1" ;;
    *) echo "FAIL $1: expected \"$2\""; echo "$out" | sed 's/^/     /'; fail=1 ;;
  esac
}
called() { grep -q "$1" "${WORK}/calls"; } # fragment of "METHOD url"
expect_called() { if called "$2"; then echo "ok   $1"; else echo "FAIL $1: no call matching \"$2\""; fail=1; fi; }
expect_not_called() { if called "$2"; then echo "FAIL $1: unexpected call matching \"$2\""; fail=1; else echo "ok   $1"; fi; }
expect_exit() { if [ "$rc" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1: exit $rc, wanted $2"; fail=1; fi; }
expect_arg() { if grep -q -- "$2" "${WORK}/args"; then echo "ok   $1"; else echo "FAIL $1: no curl argument matching \"$2\""; fail=1; fi; }
expect_no_arg() { if grep -q -- "$2" "${WORK}/args"; then echo "FAIL $1: curl argument matched \"$2\""; fail=1; else echo "ok   $1"; fi; }

echo "== renew mode"
export MODE=renew

export STUB_CERT=valid
run "leaves a certificate with 30 days left alone" "nothing to do"
expect_exit "  and exits 0" 0
expect_not_called "  and asks Graylog for nothing" "api/ca/clientcert"
expect_not_called "  and writes nothing" "PATCH"

export STUB_CERT=soon
run "reissues a certificate with 5 days left" "stored the certificate in Secret s"
expect_exit "  and exits 0" 0
expect_called "  and asks Graylog for a certificate" "POST .*api/ca/clientcert"
expect_called "  and patches the Secret" "PATCH .*secrets/s"
expect_not_called "  and never creates the Secret" "POST .*/secrets$"
expect_not_called "  and never calls the Data Node" "_plugins\|_cluster"
expect_not_called "  and never waits on Graylog" "lbstatus"
if grep -q '"principal":"graylog-client","role":"graylog_metrics_reader"' "${WORK}/issue-body" \
  && grep -q '"certificate_lifetime":"P30D"' "${WORK}/issue-body"; then echo "ok   sends the principal, role and lifetime"
else echo "FAIL sends the principal, role and lifetime"; cat "${WORK}/issue-body"; fail=1; fi
# One patch, all three keys, certificate and key that belong together.
patch=$(cat "${WORK}/patch")
case "$patch" in
  *'"ca.crt"'*'"tls.crt"'*'"tls.key"'*) echo "ok   patches ca.crt, tls.crt and tls.key together" ;;
  *) echo "FAIL patches ca.crt, tls.crt and tls.key together: $patch"; fail=1 ;;
esac
stored_crt=$(printf '%s' "$patch" | sed 's/.*"tls.crt":"\([^"]*\)".*/\1/' | base64 -d)
stored_key=$(printf '%s' "$patch" | sed 's/.*"tls.key":"\([^"]*\)".*/\1/' | base64 -d)
if [ "$stored_crt" = "$(cat "${WORK}/new.crt")" ]; then echo "ok   stores the new certificate"
else echo "FAIL stores the new certificate"; fail=1; fi
case "$stored_key" in
  *"BEGIN PRIVATE KEY"*) echo "ok   stores the key decrypted" ;;
  *) echo "FAIL stores the key decrypted"; fail=1 ;;
esac
a=$(printf '%s' "$stored_crt" | openssl x509 -pubkey -noout 2>/dev/null | openssl md5)
b=$(printf '%s' "$stored_key" | openssl pkey -pubout 2>/dev/null | openssl md5)
if [ "$a" = "$b" ]; then echo "ok   stores a key that matches the certificate"
else echo "FAIL stores a key that matches the certificate"; fail=1; fi

# Secrets stay off the command line, where ps would show them.
expect_no_arg "keeps the API token off the command line" "tok-secret"
if grep -q "$(cat "${WORK}/pw")" "${WORK}/args"; then echo "FAIL keeps the key password off the command line"; fail=1
else echo "ok   keeps the key password off the command line"; fi

export STUB_CERT=none
run "reissues when the Secret holds no certificate" "missing or inside the"
expect_called "  and patches the Secret" "PATCH .*secrets/s"

# Someone deleted the Secret. The renewal issues a certificate and creates it again,
# the way the hook does, without touching the Data Node.
export STUB_SECRET=404
run "creates the Secret when it has been deleted" "stored the certificate in Secret s"
expect_exit "  and exits 0" 0
expect_called "  and asks Graylog for a certificate" "POST .*api/ca/clientcert"
expect_called "  and creates the Secret" "POST .*/secrets$"
expect_not_called "  and does not patch a Secret that is not there" "PATCH"
expect_not_called "  and never calls the Data Node" "_plugins\|_cluster"
create=$(cat "${WORK}/create")
case "$create" in
  *'"kind":"Secret"'*'"name":"s"'*'"app":"graylog-app"'*'"ca.crt"'*'"tls.crt"'*'"tls.key"'*) echo "ok   creates a labelled Secret with all three keys" ;;
  *) echo "FAIL creates a labelled Secret with all three keys: $create"; fail=1 ;;
esac
created_crt=$(printf '%s' "$create" | sed 's/.*"tls.crt":"\([^"]*\)".*/\1/' | base64 -d)
if [ "$created_crt" = "$(cat "${WORK}/new.crt")" ]; then echo "ok   stores the new certificate in it"
else echo "FAIL stores the new certificate in it"; fail=1; fi
# Graylog refuses a certificate until the role mapping exists, so a renewal that runs
# before the hook has finished must fail without creating anything.
export STUB_ISSUE=500
run "creates nothing when Graylog will not issue a certificate" "recreates them"
expect_exit "  and exits 1" 1
expect_not_called "  and writes nothing" "POST .*/secrets$\|PATCH"
unset STUB_ISSUE
export STUB_CREATE=403
run "fails when the Secret cannot be created" "writing Secret s failed"
expect_exit "  and exits 1" 1
unset STUB_CREATE
unset STUB_SECRET
export STUB_SECRET=500
run "fails on a Secret read error other than 404" "not readable (HTTP 500)"
expect_exit "  and exits 1" 1
unset STUB_SECRET

export STUB_CERT=soon
export STUB_ISSUE=401
run "points at helm upgrade when the token is rejected" "no longer authenticates"
expect_exit "  and exits 1" 1
expect_not_called "  and writes nothing" "PATCH"
export STUB_ISSUE=403
run "names the permission when issuing is refused" "ca_clientcert:create"
expect_not_called "  and writes nothing" "PATCH"
export STUB_ISSUE=500
run "points at helm upgrade when the role or mapping is gone" "recreates them"
expect_not_called "  and writes nothing" "PATCH"
unset STUB_ISSUE

export STUB_BAD_KEY=1
run "stops when the private key cannot be decrypted" "could not decrypt the private key"
expect_exit "  and exits 1" 1
expect_not_called "  and leaves the old certificate in place" "PATCH"
unset STUB_BAD_KEY

export STUB_PATCH=403
run "fails when the Secret write is refused" "writing Secret s failed"
expect_exit "  and exits 1" 1
unset STUB_PATCH

# A valid certificate needs no token, so the CronJob stays quiet when the token is gone.
export STUB_CERT=valid
API_TOKEN="" run "does not need the token while the certificate is valid" "nothing to do"
unset API_TOKEN
export STUB_CERT=soon
API_TOKEN="" run "asks for a token only when it has to reissue" "no API token"
expect_exit "  and exits 1" 1
unset API_TOKEN

echo "== hook mode"
export MODE=hook

export STUB_CERT=valid
run "leaves a certificate with 30 days left alone" "nothing to do"
expect_exit "  and exits 0" 0
expect_not_called "  and does not wait on the Data Node" "_cluster/health"
expect_not_called "  and issues nothing" "api/ca/clientcert"

# First install: no Secret, role and mapping already there.
export STUB_SECRET=404
run "creates the Secret on a first install" "stored the certificate in Secret s"
expect_exit "  and exits 0" 0
expect_called "  and waits for Graylog" "GET .*lbstatus"
expect_called "  and waits for the Data Node" "GET .*_cluster/health"
expect_not_called "  and leaves an existing role alone" "PUT"
expect_called "  and creates the Secret" "POST .*/secrets$"
expect_not_called "  and does not patch a Secret that is not there" "PATCH"
create=$(cat "${WORK}/create")
case "$create" in
  *'"kind":"Secret"'*'"name":"s"'*'"app":"graylog-app"'*'"ca.crt"'*'"tls.crt"'*'"tls.key"'*) echo "ok   creates a labelled Secret with all three keys" ;;
  *) echo "FAIL creates a labelled Secret with all three keys: $create"; fail=1 ;;
esac
# The very first run has no CA in the Secret to check the Data Node against.
if grep '_cluster/health' "${WORK}/args" | grep -q -- ' -k '; then echo "ok   skips Data Node verification before a CA exists"
else echo "FAIL skips Data Node verification before a CA exists"; fail=1; fi
expect_no_arg "keeps the signed JWT off the command line" "eyJ"
expect_no_arg "keeps the API token off the command line" "tok-secret"
expect_no_arg "keeps the password secret off the command line" "pwsecret"

# A later upgrade: the Secret exists but the certificate is due.
unset STUB_SECRET
export STUB_CERT=soon
run "patches the Secret on an upgrade" "stored the certificate in Secret s"
expect_called "  and patches it" "PATCH .*secrets/s"
expect_not_called "  and does not create it" "POST .*/secrets$"
if grep '_cluster/health' "${WORK}/args" | grep -q -- ' -k '; then echo "FAIL verifies the Data Node against the CA once the Secret has one"; fail=1
else echo "ok   verifies the Data Node against the CA once the Secret has one"; fi
expect_arg "  and passes that CA to curl" "--cacert .*ca.crt"

# The role is created from the definition, and the mapping starts empty.
export STUB_ROLE=404 STUB_MAPPING=404
run "creates a missing role and mapping" "created role mapping graylog_metrics_reader"
expect_called "  and PUTs the role" "PUT .*_plugins/_security/api/roles/graylog_metrics_reader"
expect_called "  and PUTs the mapping" "PUT .*_plugins/_security/api/rolesmapping/graylog_metrics_reader"
if grep -q 'cluster_monitor' "${WORK}/put" && grep -q '"users":\[\],"backend_roles":\[\],"hosts":\[\]' "${WORK}/put"; then
  echo "ok   sends the role definition and an empty mapping"
else echo "FAIL sends the role definition and an empty mapping"; cat "${WORK}/put"; fail=1; fi
expect_called "  and still issues the certificate" "POST .*api/ca/clientcert"
unset STUB_ROLE STUB_MAPPING

# A PUT on the mapping replaces it, so an existing one must never be written.
export STUB_ROLE=404
run "creates only the role when the mapping exists" "created role graylog_metrics_reader"
expect_not_called "  and leaves the mapping alone" "PUT .*rolesmapping"
unset STUB_ROLE

export STUB_ROLE=404 STUB_PUT=500
run "stops when the role cannot be created" "creating role graylog_metrics_reader failed"
expect_exit "  and exits 1" 1
expect_not_called "  and issues nothing" "api/ca/clientcert"
unset STUB_ROLE STUB_PUT

export STUB_DN_HEALTH=503
run "fails when the Data Node is not ready in time" "did not become ready"
expect_exit "  and exits 1" 1
expect_not_called "  and issues nothing" "api/ca/clientcert"
unset STUB_DN_HEALTH
export STUB_GL_READY=503
run "fails when Graylog is not ready in time" "did not become ready"
expect_not_called "  and issues nothing" "api/ca/clientcert"
unset STUB_GL_READY

export STUB_SECRET=404 STUB_CREATE=403
run "fails when the Secret cannot be created" "writing Secret s failed"
expect_exit "  and exits 1" 1
unset STUB_SECRET STUB_CREATE

export STUB_ISSUE=403
run "names the permission when issuing is refused" "ca_clientcert:create"
expect_not_called "  and writes nothing" "PATCH\|POST .*/secrets$"
unset STUB_ISSUE

API_TOKEN="" run "fails without a token once the setup is done" "no API token"
expect_exit "  and exits 1" 1
unset API_TOKEN

echo "== mode"
MODE=bogus run "rejects an unknown mode" "MODE must be hook or renew"
expect_exit "  and exits 1" 1
unset MODE
MODE="" run "treats an empty mode as hook" "waiting up to"

if [ "$fail" -eq 0 ]; then echo "all scenarios passed"; else echo "some scenarios FAILED"; fi
exit "$fail"
