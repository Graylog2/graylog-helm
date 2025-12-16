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
MongoDB service account name
*/}}
{{- define "graylog.mongodb.serviceAccountName" -}}
{{ $defaultName := "default" }}
{{- if .Values.mongodb.serviceAccount.create }}
{{- $defaultName = include "graylog.fullname" . | printf "%s-mongo-sa" }}
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
Graylog secret pepper
*/}}
{{- define "graylog.secretPepper" }}
{{- $pepper := .Values.graylog.config.customSecretPepper | default (randAlphaNum 96) }}
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
{{- include "graylog.fullname" . | printf "%s-backup-secret" }}
{{- end }}

{{/*
MongoDB Community Resource name
*/}}
{{- define "graylog.mongodb.crName" -}}
{{- include "graylog.fullname" . | printf "%s-mongo-rs" }}
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
{{- $defaultName := include "graylog.fullname" . | printf "%s-svc" }}
{{- .Values.graylog.service.nameOverride | default $defaultName }}
{{- end }}

{{/*
Graylog service app port
*/}}
{{- define "graylog.service.port.app" -}}
{{- .Values.graylog.service.ports.app | default 9000 | int }}
{{- end }}

{{/*
Graylog configmap name
*/}}
{{- define "graylog.configmap.name" -}}
{{- include "graylog.fullname" . | printf "%s-config" }}
{{- end }}

{{/*
Graylog data PVC/volume name
*/}}
{{- define "graylog.volume.name" -}}
{{- $defaultName := include "graylog.fullname" . | printf "%s-data" }}
{{- .Values.graylog.persistence.volumeNameOverride | default $defaultName }}
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
{{- define "graylog.datanode.service.name" -}}
{{- include "graylog.fullname" . | printf "%s-datanode-svc" }}
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
{{- include "graylog.fullname" . | printf "%s-datanode-config" }}
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
Graylog External URI
*/}}
{{- define "graylog.externalUri" }}
{{- $externalHost := "" }}
{{- $scheme := "http" }}
{{- $port := include "graylog.service.port.app" . | printf ":%s" }}
{{- $svc := include "graylog.service.name" . | lookup "v1" "Service" .Release.Namespace }}
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
{{- else if eq .Values.graylog.service.type "LoadBalancer" | and $svc $svc.status.loadBalancer }}
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
{{- define "graylog.ingress.web.name" }}
{{- include "graylog.fullname" . | printf "%s-web" }}
{{- end }}

{{/*
Cert-manager issuer name
*/}}
{{- define "graylog.cert-manager.issuer.name" }}
{{- include "graylog.fullname" . | printf "%s-letsencrypt" }}
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
{{- include "graylog.fullname" . | printf "%s-waiting-room" }}
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