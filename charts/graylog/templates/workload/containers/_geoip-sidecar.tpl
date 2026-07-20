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
{{- if not .Values.global.existingSecretName }}
{{- if or (empty .Values.graylog.config.geolocation.maxmindGeoIp.accountId) (empty .Values.graylog.config.geolocation.maxmindGeoIp.licenseKey) }}
{{- fail "GeoIP sidecar is enabled but MaxMind credentials are not provided. Set graylog.config.geolocation.maxmindGeoIp.accountId and licenseKey, or provide global.existingSecretName with GEO_IP_MAXMIND_ACCOUNT_ID and GEO_IP_MAXMIND_LICENSE_KEY keys." }}
{{- end }}
{{- end }}
- name: geoip-updater
  image: "{{ .Values.graylog.config.geolocation.sidecar.image.repository }}/{{ .Values.graylog.config.geolocation.sidecar.image.name }}:{{ .Values.graylog.config.geolocation.sidecar.image.tag }}"
  imagePullPolicy: {{ .Values.graylog.image.imagePullPolicy }}
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
          name: {{ include "graylog.secretsName" . }}
          key: GEO_IP_MAXMIND_ACCOUNT_ID
    - name: GEOIPUPDATE_LICENSE_KEY
      valueFrom:
        secretKeyRef:
          name: {{ include "graylog.secretsName" . }}
          key: GEO_IP_MAXMIND_LICENSE_KEY
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
