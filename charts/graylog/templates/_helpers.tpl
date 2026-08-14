{{/*
Expand the name of the chart.
*/}}
{{- define "graylog.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "graylog.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "graylog.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "graylog.labels" -}}
helm.sh/chart: {{ include "graylog.chart" . }}
{{ include "graylog.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "graylog.annotations" -}}
{{- with .Values.global.commonAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "graylog.selectorLabels" -}}
app.kubernetes.io/name: {{ include "graylog.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Object metadata labels block.
Merges, from lowest to highest precedence: global.commonLabels, the object's own
labels from values, the common chart labels, and chart-owned labels that must not
be overridden.
The block is indented by "indent" spaces and brings its own leading newline, so
call it left-trimmed ({{- include ... }}) and it lines up on its own.
Usage:
  {{- include "graylog.metadata.labels" (dict "context" $ "labels" .Values.graylog.labels "fixed" (dict "app" "graylog-app") "indent" 2) }}
*/}}
{{- define "graylog.metadata.labels" -}}
{{- $ctx := .context -}}
{{- $indent := .indent | default 2 | toString | atoi -}}
{{- $subIndent := add $indent 2 | toString | atoi -}}
{{- $merged := merge (dict) (.fixed | default dict) (include "graylog.labels" $ctx | fromYaml) (.labels | default dict) ($ctx.Values.global.commonLabels | default dict) -}}
{{- printf "labels:" | nindent $indent -}}
{{- toYaml $merged | nindent $subIndent -}}
{{- end -}}

{{/*
Object metadata annotations block. Renders nothing when there is nothing to set.
Merges, from lowest to highest precedence: global.commonAnnotations, the object's
own annotations from values, and chart-owned annotations that must not be
overridden (Helm hooks, resource policies).
Usage:
  {{- include "graylog.metadata.annotations" (dict "context" $ "annotations" .Values.graylog.annotations "indent" 2) }}
*/}}
{{- define "graylog.metadata.annotations" -}}
{{- $ctx := .context -}}
{{- $indent := .indent | default 2 | toString | atoi -}}
{{- $subIndent := add $indent 2 | toString | atoi -}}
{{- $merged := merge (dict) (.fixed | default dict) (.annotations | default dict) ($ctx.Values.global.commonAnnotations | default dict) -}}
{{- with $merged -}}
{{- printf "annotations:" | nindent $indent -}}
{{- toYaml . | nindent $subIndent -}}
{{- end -}}
{{- end -}}

{{/*
Pod template labels block. Same precedence rules as "graylog.metadata.labels",
but built on the selector labels so pods always match their workload selector.
Usage:
  {{- include "graylog.pod.labels" (dict "context" $ "labels" .Values.graylog.podLabels "fixed" (dict "app" "graylog-app") "indent" 6) }}
*/}}
{{- define "graylog.pod.labels" -}}
{{- $ctx := .context -}}
{{- $indent := .indent | default 2 | toString | atoi -}}
{{- $subIndent := add $indent 2 | toString | atoi -}}
{{- $merged := merge (dict) (.fixed | default dict) (include "graylog.selectorLabels" $ctx | fromYaml) (.labels | default dict) ($ctx.Values.global.commonLabels | default dict) -}}
{{- printf "labels:" | nindent $indent -}}
{{- toYaml $merged | nindent $subIndent -}}
{{- end -}}

{{/*
Metadata block for an IMMUTABLE object, i.e. a StatefulSet volumeClaimTemplate.

Deliberately NOT "graylog.metadata.labels". A StatefulSet's volumeClaimTemplates
cannot be changed after creation - Kubernetes only accepts updates to replicas,
ordinals, template, updateStrategy, persistentVolumeClaimRetentionPolicy and
minReadySeconds. Injecting the chart's identity labels here would rewrite that
field on every existing release and make `helm upgrade` fail, and because those
labels carry helm.sh/chart and app.kubernetes.io/version it would fail again on
every subsequent version bump.

So only what the user explicitly asked for is rendered: no chart labels and no
global.commonLabels/commonAnnotations. Setting these values on a release that
already exists is still a breaking change, but it is then an explicit,
one-time choice by the operator rather than something the chart does to them.

Usage:
  {{- include "graylog.claim.metadata" (dict "labels" .Values.graylog.persistence.labels "annotations" .Values.graylog.persistence.annotations "indent" 8) }}
*/}}
{{- define "graylog.claim.metadata" -}}
{{- $indent := .indent | default 2 | toString | atoi -}}
{{- $subIndent := add $indent 2 | toString | atoi -}}
{{- with .labels -}}
{{- printf "labels:" | nindent $indent -}}
{{- toYaml . | nindent $subIndent -}}
{{- end -}}
{{- with .annotations -}}
{{- printf "annotations:" | nindent $indent -}}
{{- toYaml . | nindent $subIndent -}}
{{- end -}}
{{- end -}}

{{/*
Init script ConfigMap name
*/}}
{{- define "graylog.cm.init.name" }}
{{- include "graylog.fullname" . | printf "%s-init-cm" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "graylog.serviceAccountName" }}
{{- $defaultName := "default" }}
{{- if .Values.serviceAccount.create }}
{{- $defaultName = include "graylog.fullname" . | printf "%s-sa" | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- .Values.serviceAccount.nameOverride | default $defaultName }}
{{- end }}

{{/*
MongoDB service account name
*/}}
{{- define "graylog.mongodb.serviceAccountName" }}
{{- $defaultName := "default" }}
{{- if .Values.mongodb.serviceAccount.create }}
{{- $defaultName = include "graylog.fullname" . | printf "%s-mongo-sa" | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- .Values.mongodb.serviceAccount.nameOverride | default $defaultName }}
{{- end }}

{{/*
Graylog replicas
*/}}
{{- define "graylog.replicas" }}
{{- .Values.graylog.replicas | default 2 | int }}
{{- end }}

{{/*
Datanode replicas
*/}}
{{- define "graylog.datanode.replicas" }}
{{- .Values.datanode.replicas | default 3 | int }}
{{- end }}

{{/*
Graylog image tag
*/}}
{{- define "graylog.tag" }}
{{- coalesce .Values.graylog.image.tag .Values.version | default .Chart.AppVersion }}
{{- end }}

{{/*
Graylog image
*/}}
{{- define "graylog.image" }}
{{- $name := .Values.graylog.image.repository | default (.Values.graylog.enterprise | ternary "-enterprise" "" | printf "graylog/graylog%s" )  }}
{{- include "graylog.tag" . | printf "%s:%s" $name }}
{{- end }}

{{/*
Graylog Datanode image tag
*/}}
{{- define "graylog.datanode.tag" }}
{{- coalesce .Values.datanode.image.tag .Values.version | default .Chart.AppVersion }}
{{- end }}

{{/*
Graylog Datanode image
*/}}
{{- define "graylog.datanode.image" }}
{{- $name := .Values.datanode.image.repository | default "graylog/graylog-datanode" }}
{{- include "graylog.datanode.tag" . | printf "%s:%s" $name }}
{{- end }}

{{/*
Random password generator
Usage: {{ include "graylog.randomPassword" $ }}
*/}}
{{- define "graylog.randomPassword" }}
  {{- if and .generated (hasKey .generated "password") }}
    {{- .generated.password }}
  {{- else }}
    {{- $gen := randAlphaNum 16 }}
    {{- if not .generated }}
        {{- $_ := set . "generated" (dict) -}}
    {{- end -}}
    {{- $_ := set .generated "password" $gen -}}
    {{- $gen -}}
  {{- end -}}
{{- end -}}

{{/*
Graylog root password
*/}}
{{- define "graylog.rootPassword" }}
{{- .Values.graylog.config.rootPassword | default (include "graylog.randomPassword" $) }}
{{- end }}

{{/*
Root password SHA-256 already stored in the cluster, base64-encoded, or "" if none.

Only the hash of the root password is ever persisted, so a password generated by
`graylog.randomPassword` cannot be recovered on a later release. Anything that
would otherwise present the generated password to the user must first check this
helper: a non-empty result means the stored hash wins and the freshly generated
password is discarded, so displaying it would be misleading.

Returns "" when `graylog.config.rootPassword` is set, so an explicitly configured
password always takes precedence over the stored hash. Without that, setting the
value on an existing release would be silently ignored and the documented
password-reset upgrade would have no effect.

Returns "" during `helm template` and other renders where `lookup` yields
nothing, which correctly matches the secret being (re)generated in that render.
*/}}
{{- define "graylog.storedRootPasswordSha" -}}
{{- if and (not .Values.global.existingSecretName) (empty .Values.graylog.config.rootPassword) }}
{{- $this := lookup "v1" "Secret" .Release.Namespace (include "graylog.secretsName" .) }}
{{- $backup := lookup "v1" "Secret" .Release.Namespace (include "graylog.backupSecretName" .) }}
{{- if $this }}
{{- index $this.data "GRAYLOG_ROOT_PASSWORD_SHA2" | default "" }}
{{- else if $backup }}
{{- index $backup.data "graylog-root-password-sha2" | default "" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generated root password already stored in the cluster, base64-encoded, or "" if none.

The plaintext of a generated root password lives in the backup secret so users can
retrieve it after install. It is only returned when its SHA-256 matches the stored
hash: a stale value left behind by an explicit password reset is never surfaced.
Returns "" when the user manages the password themselves (rootPassword set or
global.existingSecretName in use).
*/}}
{{- define "graylog.storedRootPassword" -}}
{{- if and (not .Values.global.existingSecretName) (empty .Values.graylog.config.rootPassword) }}
{{- $backup := lookup "v1" "Secret" .Release.Namespace (include "graylog.backupSecretName" .) }}
{{- $plain := "" }}
{{- if $backup }}
{{- $plain = index $backup.data "graylog-root-password" | default "" }}
{{- end }}
{{- $sha := include "graylog.storedRootPasswordSha" . }}
{{- if and $plain $sha (eq ($plain | b64dec | sha256sum | b64enc) $sha) }}
{{- $plain }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Graylog secret pepper
*/}}
{{- define "graylog.secretPepper" }}
{{- $pepper := .Values.graylog.config.customSecretPepper | default (randAlphaNum 96) }}
{{- if lt (len $pepper) 64 }}
{{- fail "Use at least 64 characters when setting a secret to pepper the stored user data." }}
{{- else }}
{{- print $pepper }}
{{- end }}
{{- end }}

{{/*
Graylog secret name
*/}}
{{- define "graylog.secretsName" -}}
{{- $defaultName := include "graylog.fullname" . | printf "%s-secrets" | trunc 63 | trimSuffix "-" }}
{{- if .Values.global.existingSecretName }}
{{- $defaultName = .Values.global.existingSecretName }}
{{- end }}
{{- $defaultName }}
{{- end }}

{{/*
Graylog Datanode secret name
*/}}
{{- define "graylog.datanode.secretsName" -}}
{{- include "graylog.secretsName" . | printf "%s-datanode" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Graylog backup-secret name
*/}}
{{- define "graylog.backupSecretName" -}}
{{- include "graylog.fullname" . | printf "%s-backup-secret" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
MongoDB Community Resource name
*/}}
{{- define "graylog.mongodb.crName" -}}
{{- include "graylog.fullname" . | printf "%s-mongo-rs" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
MongoDB Community Resource main username
*/}}
{{- define "graylog.mongodb.crUsername" -}}
{{- print "graylog" }}
{{- end }}

{{/*
MongoDB Community Resource main database
*/}}
{{- define "graylog.mongodb.crDatabase" -}}
{{- print "graylog" }}
{{- end }}

{{/*
MongoDB Community Resource Secret name
*/}}
{{- define "graylog.mongodb.crSecretName" -}}
{{- $crName := include "graylog.mongodb.crName" . }}
{{- $userName := include "graylog.mongodb.crUsername" . }}
{{- $dbName := include "graylog.mongodb.crDatabase" . }}
{{- printf "%s-%s-%s" $crName $userName $dbName }}
{{- end }}

{{/*
Graylog service name
*/}}
{{- define "graylog.service.name" -}}
{{- $defaultName := include "graylog.fullname" . | printf "%s-svc" | trunc 63 | trimSuffix "-" }}
{{- .Values.graylog.service.nameOverride | default $defaultName }}
{{- end }}

{{/*
Graylog service app port
*/}}
{{- define "graylog.service.port.app" -}}
{{- .Values.graylog.service.ports.app | default 9000 | int }}
{{- end }}

{{/*
DISABLED 2026-07-30 -- the settings are inert: the forwarder listener is
configured as attributes on a Graylog input of type "Forwarder", not through
server.conf, and unrecognised GRAYLOG_* env vars are silently dropped.
graylog.config.forwarder was removed from values.yaml, so this helper reads a
path that no longer exists -- re-add those values before restoring it.

Whether the Graylog server should listen for forwarder connections.
Defaults to ingress.forwarder.enabled so that exposing the ingest endpoint also
binds the ports behind it; set graylog.config.forwarder.enabled explicitly to
override (e.g. to bind the ports without creating an Ingress).

{{- define "graylog.forwarder.enabled" -}}
{{- $configured := .Values.graylog.config.forwarder.enabled -}}
{{- if kindIs "bool" $configured -}}
{{- $configured -}}
{{- else -}}
{{- .Values.ingress.forwarder.enabled | ternary true false -}}
{{- end -}}
{{- end }}
*/}}

{{/*
Graylog service port name for the forwarder message channel (default 13301).
Sourced from graylog.inputs, so it must stay in sync with that entry's name.
*/}}
{{- define "graylog.service.port.forwarder.message" -}}
{{- print "input-forwarder" }}
{{- end }}

{{/*
Graylog service port name for the forwarder configuration channel (13302).
Always exposed by the service; the forwarder polls it for configuration updates.
*/}}
{{- define "graylog.service.port.forwarder.config" -}}
{{- print "input-fwd-conf" }}
{{- end }}

{{/*
Graylog configmap name
*/}}
{{- define "graylog.configmap.name" -}}
{{- include "graylog.fullname" . | printf "%s-config" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Graylog data PVC/volume name
*/}}
{{- define "graylog.volume.name" -}}
{{- $defaultName := include "graylog.fullname" . | printf "%s-data" | trunc 63 | trimSuffix "-" }}
{{- .Values.graylog.persistence.volumeNameOverride | default $defaultName }}
{{- end }}

{{/*
Graylog Datanode pod prefix
*/}}
{{- define "graylog.datanode.name" -}}
{{- include "graylog.fullname" . | printf "%s-datanode" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Graylog Datanode service name
*/}}
{{- define "graylog.datanode.service.name" -}}
{{- include "graylog.fullname" . | printf "%s-datanode-svc" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Graylog Datanode hosts
*/}}
{{- define "graylog.datanode.hosts" -}}
{{- $builder := list }}
{{- range $i := include "graylog.datanode.replicas" . | int | until }}
{{- $builder = printf "%s-%d.%s.%s.svc.cluster.local" (include "graylog.datanode.name" $) $i (include "graylog.datanode.service.name" $) ($.Release.Namespace) | append $builder }}
{{- end }}
{{- join "," $builder | quote }}
{{- end }}

{{/*
Datanode configmap name
*/}}
{{- define "graylog.datanode.configmap.name" -}}
{{- include "graylog.fullname" . | printf "%s-datanode-config" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
BYO OpenSearch / Data Node mutual-exclusion validation.
Exactly one indexer source must be selected.
*/}}
{{- define "graylog.opensearch.validate" -}}
{{- if and .Values.datanode.enabled .Values.opensearch.enabled }}
{{- fail "datanode.enabled and opensearch.enabled are mutually exclusive. To bring your own OpenSearch, set datanode.enabled=false and opensearch.enabled=true." }}
{{- end }}
{{- if and (not .Values.datanode.enabled) (not .Values.opensearch.enabled) }}
{{- fail "No indexer configured: enable the bundled Data Node (datanode.enabled=true) or bring your own OpenSearch (opensearch.enabled=true)." }}
{{- end }}
{{- if .Values.opensearch.enabled }}
{{- if not .Values.opensearch.hosts }}
{{- fail "opensearch.enabled=true but opensearch.hosts is empty. Provide at least one OpenSearch node URI." }}
{{- end }}
{{- if and .Values.opensearch.tls.enabled (not .Values.opensearch.tls.caSecret) (not .Values.global.existingSecretName) }}
{{- /* CA may legitimately be a public/known CA; warn-by-convention only, no fail */ -}}
{{- end }}
{{- end }}
{{- end }}

{{/*
Size string to bytes, or "" when the format is not recognised.

Two conventions meet here: Kubernetes resource quantities on persistence.size and
Graylog's own size strings on the journal settings. They disagree - Kubernetes G is
10^9 and Gi is 2^30, while Graylog's gb is 2^30 (verified against the exporter:
maxSize 5gb reports gl_journal_size_limit 5368709120, exactly 5 x 1024^3). So
suffixes are matched exactly, never case-folded: lowercasing would collapse
Kubernetes M (10^6) onto m (milli).

Returns "" rather than guessing on anything unrecognised, fractional quantities like
1.5Gi included. Callers must treat "" as "cannot validate" and skip - a size this
cannot parse is not grounds for refusing to render.

Usage: {{ include "graylog.sizeToBytes" "8Gi" }}
*/}}
{{- define "graylog.sizeToBytes" -}}
{{- $s := . | toString | trim -}}
{{- $digits := regexFind "^[0-9]+" $s -}}
{{- if $digits -}}
{{- $suffix := substr (len $digits) (len $s) $s -}}
{{- $units := dict
    "" 1 "b" 1 "B" 1
    "k" 1000 "K" 1000 "M" 1000000 "G" 1000000000 "T" 1000000000000
    "Ki" 1024 "Mi" 1048576 "Gi" 1073741824 "Ti" 1099511627776
    "kb" 1024 "KB" 1024 "mb" 1048576 "MB" 1048576
    "gb" 1073741824 "GB" 1073741824 "tb" 1099511627776 "TB" 1099511627776 -}}
{{- if hasKey $units $suffix -}}
{{- mul (atoi $digits) (get $units $suffix) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Message journal durability validation (J-03).

An enabled journal on a non-persistent data dir is a data-loss configuration
wearing a durability costume: the volume renders as emptyDir while
GRAYLOG_MESSAGE_JOURNAL_ENABLED=true tells Graylog its write-ahead log survives
restarts. Every pod replacement then silently discards whatever had not been
processed yet.

Three things this deliberately does NOT treat as the broken combination:

  - existingClaim. `persistence.enabled=false` with an existingClaim still mounts
    a real PVC (see the volumes block in the Graylog StatefulSet), so the journal
    is durable and the config is legitimate.
  - graylog.enabled=false. No StatefulSet is rendered, so there is no pod and no
    journal to lose.
  - A journal that is genuinely turned off. messageJournal.enabled is
    schema-typed as a *string*, so `if .Values.graylog.config.messageJournal.enabled`
    is truthy even for "false" - a non-empty string. The comparison below has to
    be against the value, not its truthiness, or the guard fires on the very
    configuration it tells people to use.
*/}}
{{- define "graylog.journal.validate" -}}
{{- if .Values.graylog.enabled }}
{{/* Mirrors how config/graylog.yaml renders the env var: `default true` covers
     nil/empty, toString covers a bool from a values file, lower covers "False". */}}
{{- $journal := .Values.graylog.config.messageJournal.enabled | default true | toString | lower }}
{{- if ne $journal "false" }}
{{- if and (not .Values.graylog.persistence.enabled) (not .Values.graylog.persistence.existingClaim) }}
{{/* The first line is deliberately short and everything substantive follows a
     break: helm-unittest only matches a fail message from the first line break
     onward, so anything asserted in the test suite has to live below it. */}}
{{- $msg := "Cannot enable the message journal without persistent storage." }}
{{- $msg = cat $msg "\n\ngraylog.config.messageJournal.enabled is on while graylog.persistence.enabled=false, so the journal would be backed by an emptyDir volume: every unprocessed message is lost on any pod restart, eviction, or upgrade - while GRAYLOG_MESSAGE_JOURNAL_ENABLED=true tells Graylog its write-ahead log is durable." }}
{{- $msg = cat $msg "\n\nChoose one of the following instead:" }}
{{- $msg = cat $msg "\n\nOption A: Durable journal on chart-managed storage (recommended)" }}
{{- $msg = cat $msg "\n  --set graylog.persistence.enabled=true" }}
{{- $msg = cat $msg "\n\nOption B: Durable journal on a pre-provisioned claim" }}
{{- $msg = cat $msg "\n  --set graylog.persistence.existingClaim=my-graylog-data" }}
{{- $msg = cat $msg "\n\nOption C: No journal at all (ephemeral or test deployments only)" }}
{{- $msg = cat $msg "\n  --set-string graylog.config.messageJournal.enabled=false" }}
{{- $msg = cat $msg "\n  --set graylog.persistence.enabled=false" }}
{{- $msg = cat $msg "\n\nNote: messageJournal.enabled is a string in values.schema.json, so Option C needs --set-string. A bare `--set ...enabled=false` is rejected as a boolean." }}
{{- $msg = cat $msg "\n\nSee docs/graylog-message-handling.md for what the journal protects and how to drain it." }}
{{- fail $msg }}
{{- end }}
{{/*
  Journal cap vs volume size (J-06). Only checkable when the chart provisions the
  volume: an existingClaim's capacity is not knowable at render time, and a
  disabled persistence has no declared size (and is already rejected above).

  The cap is compared at 90% of the volume rather than 100%. The journal shares the
  data volume with the node-id, the truststore, content packs and GeoIP databases,
  and it can overshoot its cap briefly because reaping happens per segment. A full
  journal throttles inputs by design; a full data volume is a much worse failure.
*/}}
{{- if and .Values.graylog.persistence.enabled (not .Values.graylog.persistence.existingClaim) }}
{{- $capStr := .Values.graylog.config.messageJournal.maxSize | default "5gb" }}
{{- $volStr := .Values.graylog.persistence.size | default "8Gi" }}
{{- $cap := include "graylog.sizeToBytes" $capStr }}
{{- $vol := include "graylog.sizeToBytes" $volStr }}
{{- if and $cap $vol }}
{{- $capB := atoi $cap }}
{{- $volB := atoi $vol }}
{{- if gt (mul $capB 10) (mul $volB 9) }}
{{/* Suggestions in MiB: Graylog accepts mb, Kubernetes accepts Mi, and integer
     division keeps both on the safe side of the 90% line. */}}
{{- $maxCapMiB := div (mul $volB 9) 10485760 }}
{{- $minVolMiB := div (add (mul $capB 10) 9437183) 9437184 }}
{{- $msg := "The message journal cap does not fit the data volume." }}
{{- $msg = cat $msg (printf "\n\ngraylog.config.messageJournal.maxSize (%s) claims more than 90%% of graylog.persistence.size (%s). The journal shares that volume with the node-id, truststore, content packs and GeoIP databases, so it cannot have all of it." $capStr $volStr) }}
{{- $msg = cat $msg "\n\nA full journal throttles inputs by design. A full data volume does not - it takes the node down." }}
{{- $msg = cat $msg "\n\nEither:" }}
{{- $msg = cat $msg (printf "\n  Lower the cap:      --set-string graylog.config.messageJournal.maxSize=%dmb" $maxCapMiB) }}
{{- $msg = cat $msg (printf "\n  Or grow the volume: --set graylog.persistence.size=%dMi" $minVolMiB) }}
{{- $msg = cat $msg "\n\nNote that growing an existing volume needs a StorageClass with allowVolumeExpansion, and shrinking one is not supported at all." }}
{{- $msg = cat $msg "\n\nSee docs/graylog-message-handling.md for journal sizing." }}
{{- fail $msg }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Resolve OpenSearch basic-auth credentials as "user:pass" (empty string if none).
Inline values win; otherwise read from opensearch.auth.existingSecret via lookup.
*/}}
{{- define "graylog.opensearch.credentials" -}}
{{- $u := .Values.opensearch.auth.username | default "" | urlquery -}}
{{- $p := .Values.opensearch.auth.password | default "" | urlquery -}}
{{- if and (not $u) .Values.opensearch.auth.existingSecret -}}
  {{- $s := lookup "v1" "Secret" .Release.Namespace .Values.opensearch.auth.existingSecret -}}
  {{- if $s -}}
    {{- $u = index $s.data .Values.opensearch.auth.usernameKey | default "" | b64dec | urlquery -}}
    {{- $p = index $s.data .Values.opensearch.auth.passwordKey | default "" | b64dec | urlquery -}}
  {{- end -}}
{{- end -}}
{{- if $u -}}
{{- printf "%s:%s" $u $p -}}
{{- end -}}
{{- end -}}

{{/*
Build the comma-joined GRAYLOG_ELASTICSEARCH_HOSTS value, injecting credentials into
each URI after the scheme.
*/}}
{{- define "graylog.opensearch.hosts" -}}
{{- $creds := include "graylog.opensearch.credentials" . -}}
{{- $out := list -}}
{{- range .Values.opensearch.hosts -}}
  {{- $uri := . | trim -}}
  {{- if $creds -}}
    {{- $parts := regexSplit "://" $uri 2 -}}
    {{- if eq (len $parts) 2 -}}
      {{- $uri = printf "%s://%s@%s" (index $parts 0) $creds (index $parts 1) -}}
    {{- end -}}
  {{- end -}}
  {{- $out = append $out $uri -}}
{{- end -}}
{{- join "," $out -}}
{{- end -}}

{{/*
Dedicated OpenSearch connection secret name.
Kept separate from the main Graylog secret so GRAYLOG_ELASTICSEARCH_HOSTS is injected
even when the user supplies their own secret via global.existingSecretName.
*/}}
{{- define "graylog.opensearch.secretName" -}}
{{- include "graylog.fullname" . | printf "%s-opensearch" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Whether Graylog needs a custom Java truststore built at init time.
True when Graylog server TLS wants a keystore update, OR when a BYO OpenSearch CA
must be trusted.
*/}}
{{- define "graylog.truststore.enabled" -}}
{{- $graylogTls := and .Values.graylog.config.tls.enabled .Values.graylog.config.tls.updateKeyStore -}}
{{- $osCa := and .Values.opensearch.enabled .Values.opensearch.tls.enabled .Values.opensearch.tls.caSecret -}}
{{- if or $graylogTls $osCa -}}true{{- end -}}
{{- end -}}

{{/*
Provider-defined Storage Class name
*/}}
{{- define "graylog.provider.storageClassName" }}
{{- $names := dict }}
{{- $_ := include "graylog.fullname" . | printf "%s-gp3" | trunc 63 | trimSuffix "-" | set $names "aws" -}}
{{/* add more entries here */}}
{{- .Values.provider | default "" | get $names }}
{{- end }}

{{/*
Graylog Storage Class name
*/}}
{{- define "graylog.storageClassName" }}
{{- include "graylog.provider.storageClassName" . | coalesce .Values.graylog.persistence.storageClass .Values.global.storageClass | default "" }}
{{- end }}

{{/*
Datanode data Storage Class name
*/}}
{{- define "graylog.datanode.data.storageClassName" }}
{{- include "graylog.provider.storageClassName" . | coalesce .Values.datanode.persistence.data.storageClass .Values.global.storageClass | default "" }}
{{- end }}

{{/*
Datanode native libs Storage Class name
*/}}
{{- define "graylog.datanode.nativeLibs.storageClassName" }}
{{- include "graylog.provider.storageClassName" . | coalesce .Values.datanode.persistence.nativeLibs.storageClass .Values.global.storageClass | default "" }}
{{- end }}

{{/*
MongoDB Storage Class name
*/}}
{{- define "graylog.mongodb.storageClassName" }}
{{- include "graylog.provider.storageClassName" . | coalesce .Values.mongodb.persistence.storageClass .Values.global.storageClass | default "" }}
{{- end }}

{{/*
Custom enviroment variables
usage: {{ include "graylog.env" .Values.{graylog|datanode} | indent N }}
*/}}
{{- define "graylog.env" }}
{{- $explicit := list }}
{{- range $_, $e := .extraEnv }}
{{- if $e.name }}{{ $explicit = append $explicit .name }}{{ end }}
- {{ toYaml $e | nindent 2 | trim }}
{{- end }}
{{- range $k, $v := .env }}
{{- if has $k $explicit | not }}
- name: {{ $k }}
  value: {{ $v | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Graylog Publish URI
*/}}
{{- define "graylog.publishUri" }}
{{- $port := .Values.graylog.service.ports.app | default 9000 | int }}
{{- $scheme := .Values.graylog.config.tls.enabled | ternary "https" "http" }}
{{- printf "%s://$(POD_NAME).%s.%s.svc.cluster.local:%d/" $scheme (include "graylog.service.name" .) .Release.Namespace $port }}
{{- end }}

{{/*
Graylog External URI, or "" when no source gives a hostname.
An explicit network.externalUri skips the Service lookup, so a changed load
balancer address cannot restart the pods. A bare hostname gets the tls.enabled
scheme and the app port, so a public endpoint needs the full URI form.
*/}}
{{- define "graylog.externalUri" }}
{{- $externalUri := "" }}
{{- $externalHost := "" }}
{{- $scheme := "http" }}
{{- $port := include "graylog.service.port.app" . | printf ":%s" }}
{{- $explicit := .Values.graylog.config.network.externalUri | default "" }}
{{- if and .Values.graylog.config.tls.enabled .Values.graylog.config.tls.cn }}
  {{- $externalHost = .Values.graylog.config.tls.cn }}
  {{- $scheme = "https" }}
{{- else if $explicit }}
  {{- if contains "://" $explicit }}
    {{- $externalUri = printf "%s/" (trimSuffix "/" $explicit) }}
  {{- else }}
    {{- $externalHost = $explicit }}
    {{- if .Values.graylog.config.tls.enabled }}
      {{- $scheme = "https" }}
    {{- end }}
  {{- end }}
{{- else if and .Values.ingress.enabled .Values.ingress.web.enabled .Values.ingress.web.tls }}
  {{- with .Values.ingress.web.tls }}
    {{- with (index . 0).hosts }}
        {{- $externalHost = index . 0 | default "" }}
    {{- end }}
  {{- end }}
  {{- $scheme = "https" }}
  {{- $port = "" }}
{{- else if and .Values.ingress.enabled .Values.ingress.web.enabled .Values.ingress.web.hosts }}
  {{- with .Values.ingress.web.hosts }}
    {{- with (index . 0) }}
        {{- $externalHost = .host | default "" }}
    {{- end }}
  {{- end }}
  {{- $port = "" }}
{{- else if eq .Values.graylog.service.type "LoadBalancer" }}
  {{- $svc := include "graylog.service.name" . | lookup "v1" "Service" .Release.Namespace }}
  {{- if and $svc $svc.status.loadBalancer $svc.status.loadBalancer.ingress }}
    {{- $lb := index $svc.status.loadBalancer.ingress 0 }}
    {{- $externalHost = coalesce $lb.hostname $lb.ip }}
  {{- end }}
{{- end }}
{{- if $externalUri }}
  {{- $externalUri }}
{{- else if $externalHost }}
  {{- printf "%s://%s%s/" $scheme $externalHost $port }}
{{- end }}
{{- end }}

{{/*
Graylog plugin URLs
*/}}
{{- define "graylog.plugin.URLs" }}
{{- if and .Values.graylog.config.plugins.enabled .Values.graylog.config.init.assetFetch.enabled .Values.graylog.config.init.assetFetch.plugins.enabled .Values.graylog.plugins }}
{{- $urls := list }}
{{- $baseUrl := .Values.graylog.config.init.assetFetch.plugins.baseUrl | default "" }}
{{- $skipChecksum := .Values.graylog.config.init.assetFetch.skipChecksum | default false }}
{{- $allowHttp := .Values.graylog.config.init.assetFetch.allowHttp | default false }}
{{- if not $allowHttp | and (hasPrefix "http://" $baseUrl) }}
{{- printf "Validation error: plugin baseUrl is '%s'. Only HTTPS is allowed for plugin URLs." $baseUrl | fail }}
{{- end }}
{{- range .Values.graylog.plugins }}
{{- $url := .url }}
{{- if $url }}
{{- if and (not $skipChecksum) (empty .checksum) }}
{{- printf "Validation error: checksum verification is enabled but no checksum hash has been provided for plugin '%s'." .name | fail }}
{{- end }}
{{- if and (hasPrefix "http://" $url | not) (hasPrefix "https://" $url | not) }}
{{- $url = printf "%s/%s" (trimSuffix "/" $baseUrl) (trimPrefix "/" $url) }}
{{- end }}
{{- if not $allowHttp | and (hasPrefix "http://" $url) }}
{{- printf "Validation error: plugin '%s' is using URL '%s'. Only HTTPS is allowed for plugin URLs." .name $url | fail }}
{{- end }}
{{- if not $skipChecksum }}
{{- $url = printf "%s|%s" $url .checksum }}
{{- end }}
{{- $urls = printf "%s|%s" .name $url | append $urls }}
{{- end }}
{{- end }}
{{- $urls | join "^" | quote }}
{{- end }}
{{- end }}

{{/*
Geolocation mmdb URLs
*/}}
{{- define "graylog.mmdb.URLs" }}
{{- if and .Values.graylog.config.geolocation.enabled .Values.graylog.config.init.assetFetch.geolocation.enabled .Values.graylog.config.geolocation.mmdbSources.city.url .Values.graylog.config.geolocation.mmdbSources.asn.url }}
{{- $urls := list }}
{{- $baseUrl := .Values.graylog.config.init.assetFetch.geolocation.baseUrl | default "" }}
{{- $skipChecksum := .Values.graylog.config.init.assetFetch.skipChecksum | default false }}
{{- $allowHttp := .Values.graylog.config.init.assetFetch.allowHttp | default false }}
{{- if not $allowHttp | and (hasPrefix "http://" $baseUrl) }}
{{- printf "Validation error: baseUrl is '%s' for geolocation mmdb sources. Only HTTPS is allowed for mmdb URLs." $baseUrl | fail }}
{{- end }}
{{- range $key, $vals := .Values.graylog.config.geolocation.mmdbSources }}
{{- $name := eq $key "asn" | ternary ($key | upper) ($key | title) | printf "GeoLite2-%s" }}
{{- with $vals }}
{{- $url := .url }}
{{- if $url }}
{{- if and (not $skipChecksum) (empty .checksum) }}
{{- printf "Validation error: checksum verification is enabled but no checksum hash has been provided for mmdb '%s'." $name | fail }}
{{- end }}
{{- if and (hasPrefix "http://" $url | not) (hasPrefix "https://" $url | not) }}
{{- $url = printf "%s/%s" (trimSuffix "/" $baseUrl) (trimPrefix "/" $url) }}
{{- end }}
{{- if not $allowHttp | and (hasPrefix "http://" $url) }}
{{- printf "Validation error: geolocation database '%s' is using URL '%s'. Only HTTPS is allowed for mmdb URLs." $name $url | fail }}
{{- end }}
{{- if not $skipChecksum }}
{{- $url = printf "%s|%s" $url .checksum }}
{{- end }}
{{- $urls = printf "%s|%s" $name $url | append $urls }}
{{- end }}
{{- end }}
{{- end }}
{{- $urls | join "^" | quote }}
{{- end }}
{{- end }}

{{/*
Graylog Java Options
*/}}
{{- define "graylog.javaOpts" }}
{{- $extraOpts := .Values.graylog.config.extraServerJavaOpts | default list }}
{{- if eq (include "graylog.truststore.enabled" .) "true" }}
{{- $extraOpts = append $extraOpts "-Djavax.net.ssl.trustStore=/usr/share/graylog/data/cacerts/graylog.jks" }}
{{- $extraOpts = .Values.graylog.config.tls.keyStorePass | default "changeit" | printf "-Djavax.net.ssl.trustStorePassword=%s" | append $extraOpts }}
{{- end }}
{{- prepend $extraOpts .Values.graylog.config.serverJavaOpts | compact | join " " }}
{{- end }}


{{/*
Ingress name
*/}}
{{- define "graylog.ingress.web.name" }}
{{- include "graylog.fullname" . | printf "%s-web" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Forwarder message channel ingress name
*/}}
{{- define "graylog.ingress.forwarder.message.name" }}
{{- include "graylog.fullname" . | printf "%s-forwarder-message-channel" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Forwarder configuration channel ingress name
*/}}
{{- define "graylog.ingress.forwarder.config.name" }}
{{- include "graylog.fullname" . | printf "%s-forwarder-config-channel" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Cert-manager issuer name
*/}}
{{- define "graylog.cert-manager.issuer.name" }}
{{- include "graylog.fullname" . | printf "%s-letsencrypt" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Cert-manager issuer checker
Return: true if there is at least one Issuer or ClusterIssuer in the cluster.
Usage: if (include "cert-manager.issuer.exists.any" . | eq "true") ...
*/}}
{{- define "graylog.cert-manager.issuer.exists.any" }}
{{- $gv := "cert-manager.io/v1" }}
{{- $exists := false }}
{{- if .Capabilities.APIVersions.Has $gv }}
{{- $ci := lookup $gv "ClusterIssuer" "" "" | default dict }}
{{- $ni := lookup $gv "Issuer" .Release.Namespace "" | default dict }}
{{- $hasCI := $ci.items | default (list) | len | lt 0 }}
{{- $hasNI := $ni.items | default (list) | len | lt 0 }}
{{- $exists = or $hasCI $hasNI }}
{{- end }}
{{- $exists }}
{{- end }}

{{/*
Fallback service/deployment name
*/}}
{{- define "graylog.fallback.name" }}
{{- include "graylog.fullname" . | printf "%s-waiting-room" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Default ingress path
*/}}
{{- define "graylog.ingress.defaultPath" }}
{{- print "/" }}
{{- end }}

{{/*
Default ingress pathType
*/}}
{{- define "graylog.ingress.defaultPathType" }}
{{- print "ImplementationSpecific" }}
{{- end }}

{{/*
Graylog ConfigMap template checksum
*/}}
{{- define "graylog.configChecksum" }}
{{- include (print $.Template.BasePath "/config/graylog.yaml") . | sha256sum }}
{{- end }}

{{/*
Datanode ConfigMap template checksum
*/}}
{{- define "graylog.datanode.configChecksum" }}
{{- include (print $.Template.BasePath "/config/datanode.yaml") . | sha256sum }}
{{- end }}

{{/*
Secrets template checksum
Renders the secrets template once and caches the result for consistent checksums
*/}}
{{- define "graylog.secretsChecksum" -}}
{{- if not (index $ "__secretsChecksum") -}}
  {{- $_ := include (print $.Template.BasePath "/config/secret/secrets.yaml") . | sha256sum | set $ "__secretsChecksum" -}}
{{- end -}}
{{- index $ "__secretsChecksum" -}}
{{- end -}}