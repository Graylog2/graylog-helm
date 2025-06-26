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
Size presets
usage: (list <size preset key> <size field to index> . | list "graylog" | include "presets.size")
*/}}
{{- define "presets.size" }}
{{- $indices := dict "replicas" 0 "cpu" 1 "memory" 2 -}}
{{- $defaults := dict }}
{{- $_ := list 2 1 1 | set $defaults "graylog" }}
{{- $_  = list 3 0.5 3.5 | set $defaults "datanode" }}
{{- $dictName  := index . 0 }}
{{- $args := index . 1 | initial }}
{{- $ctx := index . 1 | last }}
{{- $sizeKey   := index $args 0 | default "default" }}
{{- $fieldToIndex := index $args 1 | required "please request a valid size field: replicas, cpu, memory" }}
{{- if hasKey $defaults $dictName | not }}
  {{- fail "presets are only available for 'graylog' and 'datanode'" }}
{{- end }}
{{- $default := index $defaults $dictName }}
{{- $presets := $ctx.Files.Get "files/presets.yaml" | fromYaml | default dict }}
{{- $values := dig "size" $sizeKey $dictName $default $presets }}
{{- index $indices $fieldToIndex | index $values }}
{{- end }}

{{/*
Graylog size presets
Returns {replicas|cpu|memory} values for a given preset
usage: (list $key <field> . | include "graylog.presets.size")
  e.g. (list "small" "replicas" . | include "graylog.presets.size")
*/}}
{{- define "graylog.presets.size" }}
{{- list "graylog" . | include "presets.size" }}
{{- end }}

{{/*
Datanode size presets
Returns {replicas|cpu|memory} values for a given preset
usage: (list $key <field> . | include "datanode.presets.size")
  e.g. (list "small" "replicas" . | include "datanode.presets.size")
*/}}
{{- define "datanode.presets.size" }}
{{- list "datanode" . | include "presets.size" }}
{{- end }}

{{/*
Graylog replicas
*/}}
{{- define "graylog.replicas" }}
{{- .Values.graylog.replicas | default (list .Values.size "replicas" . | include "graylog.presets.size") | default 2 }}
{{- end }}

{{/*
Datanode replicas
*/}}
{{- define "datanode.replicas" }}
{{- .Values.datanode.replicas | default (list .Values.size "replicas" . | include "datanode.presets.size") | default 3 }}
{{- end }}

{{/*
Graylog image tag
*/}}
{{- define "graylog.imageTag" }}
{{- coalesce .Values.graylog.custom.image.tag .Values.version | default .Chart.AppVersion }}
{{- end }}

{{/*
Graylog image
*/}}
{{- define "graylog.image" }}
{{- $name := .Values.graylog.custom.image.repository | default (.Values.graylog.enterprise | ternary "-enterprise" "" | printf "graylog/graylog%s" )  }}
{{- include "graylog.imageTag" . | printf "%s:%s" $name }}
{{- end }}

{{/*
Graylog Datanode image tag
*/}}
{{- define "datanode.imageTag" }}
{{- coalesce .Values.datanode.custom.image.tag .Values.version | default .Chart.AppVersion }}
{{- end }}

{{/*
Graylog Datanode image
*/}}
{{- define "datanode.image" }}
{{- $name := .Values.datanode.custom.image.repository | default "graylog/graylog-datanode" }}
{{- include "datanode.imageTag" . | printf "%s:%s" $name }}
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

{{/*
Graylog plugins
*/}}
{{- define "graylog.pluginURLs" }}
{{- $urls := list }}
{{- $baseUrl := .Values.graylog.config.plugins.baseUrl }}
{{- $skipChecksum := .Values.graylog.config.plugins.skipChecksum }}
{{- $allowHttp := .Values.graylog.config.plugins.allowHttp }}
{{- if not $allowHttp | and (hasPrefix "http://" $baseUrl) }}
{{- printf "Validation error: plugin baseUrl is '%s'. Only HTTPS is allowed for plugin URLs." $baseUrl | fail }}
{{- end }}
{{- range $name, $plugin := .Values.graylog.plugins }}
{{- $url := $plugin.url }}
{{- if and (not $skipChecksum) (empty $plugin.checksum) }}
{{- printf "Validation error: checksum verification is enabled but no checksum hash has been provided for plugin '%s'." $name | fail }}
{{- end }}
{{- if and (hasPrefix "http://" $url | not) (hasPrefix "https://" $url | not) }}
{{- $url = printf "%s/%s" (trimSuffix "/" $baseUrl) (trimPrefix "/" $url) }}
{{- end }}
{{- if not $allowHttp | and (hasPrefix "http://" $url) }}
{{- printf "Validation error: plugin '%s' is using URL '%s'. Only HTTPS is allowed for plugin URLs." $name $url | fail }}
{{- end }}
{{- if not $skipChecksum }}
{{- $url = printf "%s|%s" $url $plugin.checksum }}
{{- end }}
{{- $urls = printf "%s|%s" $name $url | append $urls }}
{{- end }}
{{- $urls | join "^" | quote }}
{{- end }}
