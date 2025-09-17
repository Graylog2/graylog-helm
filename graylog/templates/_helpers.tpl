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
Graylog Datanode secret name
*/}}
{{- define "graylog.datanode.secretsName" -}}
{{- include "graylog.secretsName" . | printf "%s-datanode" }}
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
Custom enviroment variables
usage: {{ include "graylog.custom.env" .Values.{graylog|datanode} | indent N }}
*/}}
{{- define "graylog.custom.env" }}
{{- $explicit := list }}
{{- range $_, $e := .custom.extraEnv }}
{{- if $e.name }}{{ $explicit = append $explicit .name }}{{ end }}
- {{ toYaml $e | nindent 2 | trim }}
{{- end }}
{{- range $k, $v := .custom.env }}
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
{{- $port := .Values.graylog.custom.service.ports.app | default 9000 | int }}
{{- $scheme := .Values.graylog.config.tls.enabled | ternary "https" "http" }}
{{- printf "%s://$(POD_NAME).%s.%s.svc.cluster.local:%d/" $scheme (include "graylog.serviceName" .) .Release.Namespace $port }}
{{- end }}

{{/*
Graylog External URI
*/}}
{{- define "graylog.externalUri" }}
{{- $externalHost := "" }}
{{- $scheme := "http" }}
{{- $port := include "graylog.service.port.app" . | printf ":%s" }}
{{- $svc := include "graylog.serviceName" . | lookup "v1" "Service" .Release.Namespace }}
{{- if and .Values.graylog.config.tls.enabled .Values.graylog.config.tls.cn }}
  {{- $externalHost = .Values.graylog.config.tls.cn }}
  {{- $scheme = "https" }}
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
{{- else if eq .Values.graylog.custom.service.type "LoadBalancer" | and $svc $svc.status.loadBalancer }}
  {{- $lbName := index $svc.status.loadBalancer.ingress 0 }}
  {{- $externalHost = coalesce $lbName.hostname $lbName.ip }}
{{- end }}
{{- $externalHost = $externalHost | default .Values.graylog.config.network.externalUri }}
{{- if $externalHost }}
  {{- printf "%s://%s%s/" $scheme $externalHost $port }}
{{- end }}
{{- end }}

{{/*
GeoIP update JobSpec
usage: {{ list $geoSecretName $claimName $podIndex | include "graylog.geoip.job.spec" | indent }}
*/}}
{{- define "graylog.geoip.job.spec" }}
backoffLimit: 2
activeDeadlineSeconds: 900
template:
  spec:
    securityContext:
      runAsUser: 1100
      runAsGroup: 1100
      fsGroup: 1100
    containers:
      - name: geoipupdate
        image: maxmindinc/geoipupdate:latest
        envFrom:
          - secretRef:
              name: {{ index . 0 }}
        env:
          - name: GEOIPUPDATE_EDITION_IDS
            value: "GeoLite2-City GeoLite2-ASN"
          - name: GEOIPUPDATE_FREQUENCY
            value: "0"
          - name: GEOIPUPDATE_DB_DIR
            value: "/usr/share/data/geolocation"
        volumeMounts:
          - name: geoip-db
            mountPath: /usr/share/data
    restartPolicy: OnFailure
    volumes:
      - name: geoip-db
        persistentVolumeClaim:
          claimName: {{ printf "%s-%d" (index . 1) (index . 2) }}
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
{{- if and .Values.graylog.config.tls.enabled .Values.graylog.config.tls.updateKeyStore }}
{{- $extraOpts = append $extraOpts "-Djavax.net.ssl.trustStore=/usr/share/graylog/data/cacerts/graylog.jks" }}
{{- $extraOpts = .Values.graylog.config.tls.keyStorePass | default "changeit" | printf "-Djavax.net.ssl.trustStorePassword=%s" | append $extraOpts }}
{{- end }}
{{- prepend $extraOpts .Values.graylog.config.serverJavaOpts | compact | join " " }}
{{- end }}


{{/*
Ingress name
*/}}
{{- define "ingress.web.name" }}
{{- include "graylog.fullname" . | printf "%s-web" }}
{{- end }}

{{/*
Cert-manager issuer name
*/}}
{{- define "cert-manager.issuer.name" }}
{{- include "graylog.fullname" . | printf "%s-letsencrypt" }}
{{- end }}

{{/*
Cert-manager issuer checker
Return: true if there is at least one Issuer or ClusterIssuer in the cluster.
Usage: if (include "cert-manager.issuer.exists.any" . | eq "true") ...
*/}}
{{- define "cert-manager.issuer.exists.any" }}
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
{{- define "fallback.name" }}
{{- include "graylog.fullname" . | printf "%s-waiting-room" }}
{{- end }}
