{{/*
GeoIP Sidecar Container Specification
Used in Graylog StatefulSet when geolocation is enabled.

This template defines the sidecar container spec for GeoIP database updates.
Volume mounts assume the following volumes are defined in the pod:
  - graylog-data (or similar): mounted at /usr/share/data
  - geoip-entrypoint: mounted at /geoip-scripts
  - geoip-tmp: mounted at /tmp
*/}}
{{- define "graylog.geolocation.sidecar" }}
{{- if and .Values.graylog.config.geolocation.enabled .Values.graylog.config.geolocation.sidecar.enabled }}
{{- $maxmind := .Values.graylog.config.geolocation.maxmindGeoIp }}
{{/* Inline credentials only reach a Secret when maxmindGeoIp.enabled is true. */}}
{{- $inline := and $maxmind.enabled $maxmind.accountId $maxmind.licenseKey }}
{{- if and $inline .Values.global.existingSecretName }}
{{- fail "graylog.config.geolocation.maxmindGeoIp.accountId/licenseKey cannot be used with global.existingSecretName -- the chart manages no Secret to store them in. Put the MaxMind credentials in their own Secret and reference it with graylog.config.geolocation.maxmindGeoIp.existingSecret." }}
{{- end }}
{{- if not (or $inline $maxmind.existingSecret) }}
{{- fail "GeoIP sidecar is enabled but MaxMind credentials are not provided. Set graylog.config.geolocation.maxmindGeoIp.accountId and licenseKey, or point graylog.config.geolocation.maxmindGeoIp.existingSecret at a Secret holding them (see examples/graylog-geoip-secret.yaml)." }}
{{- end }}
{{/* Inline credentials live in the chart-managed Secret; otherwise read the external one. */}}
{{- $credsSecret := $maxmind.existingSecret }}
{{- $accountIdKey := $maxmind.accountIdKey | default "GEO_IP_MAXMIND_ACCOUNT_ID" }}
{{- $licenseKeyKey := $maxmind.licenseKeyKey | default "GEO_IP_MAXMIND_LICENSE_KEY" }}
{{- if $inline }}
{{- $credsSecret = include "graylog.secretsName" . }}
{{- $accountIdKey = "GEO_IP_MAXMIND_ACCOUNT_ID" }}
{{- $licenseKeyKey = "GEO_IP_MAXMIND_LICENSE_KEY" }}
{{- end }}
{{- $image := .Values.graylog.config.geolocation.sidecar.image }}
- name: geoip-updater
  image: "{{ $image.repository }}{{ with $image.name }}/{{ . }}{{ end }}:{{ $image.tag }}"
  imagePullPolicy: {{ $image.imagePullPolicy | default .Values.graylog.image.imagePullPolicy }}
  {{- with .Values.graylog.config.geolocation.sidecar.securityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  command:
    - /bin/sh
    - /geoip-scripts/entrypoint.sh
  env:
    - name: GEOIPUPDATE_ACCOUNT_ID
      valueFrom:
        secretKeyRef:
          name: {{ $credsSecret }}
          key: {{ $accountIdKey }}
    - name: GEOIPUPDATE_LICENSE_KEY
      valueFrom:
        secretKeyRef:
          name: {{ $credsSecret }}
          key: {{ $licenseKeyKey }}
    - name: GEOIPUPDATE_EDITION_IDS
      value: "{{ .Values.graylog.config.geolocation.maxmindGeoIp.editionIds }}"
    - name: GEOIPUPDATE_FREQUENCY
      value: "0"
    - name: GEOIPUPDATE_DB_DIR
      value: "/usr/share/data/geolocation"
    - name: GEOIP_SCHEDULE
      value: "{{ .Values.graylog.config.geolocation.sidecar.schedule }}"
    - name: GEOIPUPDATE_VERBOSE
      value: "1"
  volumeMounts:
    - name: {{ include "graylog.volume.name" . }}
      mountPath: /usr/share/data/geolocation
      subPath: geolocation
    - name: geoip-tmp
      mountPath: /tmp
    - name: geoip-entrypoint
      mountPath: /geoip-scripts
      readOnly: true
  {{- with .Values.graylog.config.geolocation.sidecar.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
