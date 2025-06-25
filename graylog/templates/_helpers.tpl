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
{{- $keys := index . 0 | splitList "." -}}
{{- $ctx := index . 1 -}}
{{- $small := dict "replicas" 1 | dict "graylog" }}
{{- $small = dict "replicas" 1 | set $small "datanode" }}
{{- if and (eq $ctx.Values.quicksetup "small") (len $keys | lt 0) }}
{{- $nested := index $keys 0 | get $small }}
{{- range $_, $k := rest $keys }}
{{- $nested = get $nested $k }}
{{- end }}
{{- print $nested }}
{{- end }}
{{- end }}

{{/*
Graylog replicas
*/}}
{{- define "graylog.replicas" }}
{{- list "graylog.replicas" . | include "graylog.quicksetup" | int | default .Values.graylog.replicas }}
{{- end }}

{{/*
Datanode replicas
*/}}
{{- define "datanode.replicas" }}
{{- list "datanode.replicas" . | include "graylog.quicksetup" | int | default .Values.datanode.replicas }}
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
Graylog secrets name
*/}}
{{- define "graylog.secretsName" -}}
{{- $defaultName := include "graylog.fullname" . | printf "%s-secrets" }}
{{- if .Values.global.existingSecret }}
{{- $defaultName = .Values.global.existingSecret }}
{{- end }}
{{- $defaultName }}
{{- end }}

{{/*
Graylog service name
*/}}
{{- define "graylog.serviceName" -}}
{{- $defaultName := include "graylog.fullname" . | printf "%s-svc" }}
{{- .Values.graylog.custom.service.nameOverride | default $defaultName }}
{{- end }}

{{/*
Graylog journal name
*/}}
{{- define "graylog.journalName" -}}
{{- $defaultName := include "graylog.fullname" . | printf "%s-journal-pvc" }}
{{- .Values.graylog.custom.persistence.journal.volumeNameOverride | default $defaultName }}
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