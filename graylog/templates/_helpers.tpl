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

{{- define "graylog.annotations" -}}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "graylog.selectorLabels" -}}
app.kubernetes.io/name: {{ include "graylog.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "graylog.serviceAccountName" -}}
{{ $defaultName := "default" }}
{{- if .Values.serviceAccount.create }}
{{- $defaultName = include "graylog.fullname" . | printf "%s-sa" }}
{{- end }}
{{- .Values.serviceAccount.nameOverride | default $defaultName }}
{{- end }}

{{/*
Quick setup values
*/}}
{{- define "graylog.quicksetup" }}
{{- $retval := "" -}}
{{/* get args: dot-separated key path, caller context */}}
{{- $keypath := index . 0 | splitList "." }}
{{- $hint := index . 1 }}
{{- if $hint -}}
{{/*
# define quicksetup dicts
hints:
  small:
    size:
      replicas:
        graylog: 1
        datanode: 1
  large:
    size:
      replicas:
        graylog: 3
        datanode: 5
*/}}
{{- $hints := dict -}}
{{/* "small" hint */}}
{{- $small := dict "size" }}
{{- $ssize := dict "replicas" }}
{{- $sreplicas := dict }}
{{- $_ := set $sreplicas "graylog" 1 }}
{{- $_ = set $sreplicas "datanode" 1 }}
{{- $_ = set $ssize "replicas" $sreplicas }}
{{- $_ = set $small "size" $ssize }}
{{- $_ = set $hints "small" $small -}}
{{/* "large" hint */}}
{{- $large := dict "size" }}
{{- $lsize := dict "replicas" }}
{{- $lreplicas := dict }}
{{- $_ = set $lreplicas "graylog" 3 }}
{{- $_ = set $lreplicas "datanode" 5 }}
{{- $_ = set $lsize "replicas" $lreplicas }}
{{- $_ = set $large "size" $lsize }}
{{- $_ = set $hints "large" $large -}}
{{/* traverse path, if hint is supported */}}
{{- $nested := get $hints $hint }}
{{- range $_, $key := $keypath }}
{{- $nested = get $nested $key }}
{{- end }}
{{- $retval = $nested }}
{{- end }}
{{- print $retval }}
{{- end }}

{{/*
Graylog replicas
*/}}
{{- define "graylog.replicas" }}
{{- .Values.graylog.replicas | default (list "size.replicas.graylog" .Values.quicksetup | include "graylog.quicksetup") | default 2 }}
{{- end }}

{{/*
Datanode replicas
*/}}
{{- define "datanode.replicas" }}
{{- .Values.datanode.replicas | default (list "size.replicas.datanode" .Values.quicksetup | include "graylog.quicksetup") | default 3 }}
{{- end }}

{{/*
Graylog image tag
*/}}
{{- define "graylog.imageTag" }}
{{- .Values.graylog.custom.image.tag | default .Chart.AppVersion }}
{{- end }}

{{/*
Graylog image
*/}}
{{- define "graylog.image" }}
{{- $name := .Values.graylog.custom.image.repository | default (.Values.graylog.enterprise | ternary "-enterprise" "" | printf "graylog/graylog%s" )  }}
{{- include "graylog.imageTag" . | printf "%s:%s" $name }}
{{- end }}

{{/*
Graylog root password
*/}}
{{- define "graylog.rootPassword" }}
{{- .Values.graylog.config.rootPassword | default "yabbadabbadoo" }}
{{- end }}

{{/*
Graylog secret pepper
*/}}
{{- define "graylog.secretPepper" }}
{{- $pepper := .Values.graylog.config.secretPepper | default (randAlphaNum 96) }}
{{- if len $pepper | ge 64 }}
{{- fail "Use at least 64 characters when setting a secret to pepper the stored user data." }}
{{- else }}
{{- print $pepper }}
{{- end }}
{{- end }}

{{/*
Graylog secret name
*/}}
{{- define "graylog.secretsName" -}}
{{- $defaultName := include "graylog.fullname" . | printf "%s-secrets" }}
{{- if .Values.global.existingSecretName }}
{{- $defaultName = .Values.global.existingSecretName }}
{{- end }}
{{- $defaultName }}
{{- end }}

{{/*
Graylog backup-secret name
*/}}
{{- define "graylog.backupSecretName" -}}
{{- $defaultName := include "graylog.fullname" . | printf "%s-backup-secret" }}
{{- .Values.mongodb.passwordUpdateJob.previousPasswords.existingSecret | default $defaultName }}
{{- end }}

{{/*
MongoDB secret name
*/}}
{{- define "graylog.mongodb.secretName" -}}
{{- $defaultName := include "graylog.fullname" . | printf "%s-mongo-secret" }}
{{- .Values.mongodb.auth.existingSecret | default $defaultName }}
{{- end }}

{{/*
Graylog service name
*/}}
{{- define "graylog.serviceName" -}}
{{- $defaultName := include "graylog.fullname" . | printf "%s-svc" }}
{{- .Values.graylog.custom.service.nameOverride | default $defaultName }}
{{- end }}

{{/*
Graylog service app port
*/}}
{{- define "graylog.service.port.app" -}}
{{- .Values.graylog.custom.service.ports.app | default 9000 | int }}
{{- end }}

{{/*
Graylog configmap name
*/}}
{{- define "graylog.configmapName" -}}
{{- include "graylog.fullname" . | printf "%s-config" }}
{{- end }}

{{/*
Graylog data PVC/volume name
*/}}
{{- define "graylog.volumeName" -}}
{{- $defaultName := include "graylog.fullname" . | printf "%s-data" }}
{{- .Values.graylog.custom.persistence.volumeNameOverride | default $defaultName }}
{{- end }}

{{/*
Graylog Datanode pod prefix
*/}}
{{- define "graylog.datanode.name" -}}
{{- include "graylog.fullname" . | printf "%s-datanode" }}
{{- end }}

{{/*
Graylog Datanode service name
*/}}
{{- define "graylog.datanode.serviceName" -}}
{{- include "graylog.fullname" . | printf "%s-datanode-svc" }}
{{- end }}

{{/*
Graylog Datanode hosts
*/}}
{{- define "graylog.datanode.hosts" -}}
{{- $builder := list }}
{{- range $i := include "datanode.replicas" . | int | until }}
{{- $builder = printf "%s-%d.%s.%s.svc.cluster.local" (include "graylog.datanode.name" $) $i (include "graylog.datanode.serviceName" $) ($.Release.Namespace) | append $builder }}
{{- end }}
{{- join "," $builder | quote }}
{{- end }}

{{/*
Datanode configmap name
*/}}
{{- define "graylog.datanode.configmapName" -}}
{{- include "graylog.fullname" . | printf "%s-datanode-config" }}
{{- end }}