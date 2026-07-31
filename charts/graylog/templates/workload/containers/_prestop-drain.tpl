{{/*
Graylog preStop journal drain — token-free variant.

Renders the `lifecycle:` block for the graylog-app container. Nothing is emitted
unless graylog.lifecycle.preStopDrain.enabled is true.

Why this exists: a StatefulSet guarantees identity, not data migration. Graylog's
graceful shutdown flushes in-memory buffers *into* the journal; it never drains
the journal *out* — that is the replacement pod's job. On scale-in there is no
replacement pod, so whatever is left in the journal is stranded in an orphaned
PVC and nothing will ever replay it. This hook is the only chance a doomed
ordinal gets to work its journal off.

Why it needs no credentials: journal depth is published as
`gl_journal_entries_uncommitted` by the Prometheus exporter on
graylog.service.ports.metrics, which answers unauthenticated on localhost. The
equivalent REST endpoint (GET /api/system/journal) requires admin auth — see
the token-based variant for what that buys.

Call with: {{ include "graylog.lifecycle" . | nindent 10 }}
*/}}
{{- define "graylog.lifecycle" -}}
{{- if .Values.graylog.lifecycle.preStopDrain.enabled }}
{{- $drain := .Values.graylog.lifecycle.preStopDrain }}
{{- $grace := .Values.graylog.terminationGracePeriodSeconds | int }}
{{- $settle := $drain.endpointPropagationDelaySeconds | int }}
{{- $reserve := $drain.shutdownReserveSeconds | int }}
{{- $poll := $drain.pollIntervalSeconds | int }}
{{/*
  The grace period is a hard ceiling covering the preStop hook AND the SIGTERM
  that follows it. If the hook is still running when it expires, the container is
  SIGKILLed, Graylog never receives SIGTERM, and the in-memory buffers this
  feature exists to protect are lost — strictly worse than no hook at all. So the
  drain budget is what is left after reserving time for the shutdown itself.
*/}}
{{- $budget := sub $grace (add $settle $reserve) | int }}
{{- if not .Values.graylog.service.metrics.enabled }}
{{- fail "graylog.lifecycle.preStopDrain.enabled=true requires graylog.service.metrics.enabled=true.\n  The drain reads journal depth from the Prometheus exporter, which is gated by that value (GRAYLOG_PROMETHEUS_EXPORTER_ENABLED).\n  Either:\n    Set graylog.service.metrics.enabled=true\n    Or set graylog.lifecycle.preStopDrain.enabled=false and drain manually (see the Message Journal Lifecycle runbook in the README)." }}
{{- end }}
{{- if le $budget 1 }}
{{- fail (printf "graylog.lifecycle.preStopDrain leaves no time to drain: terminationGracePeriodSeconds (%d) - endpointPropagationDelaySeconds (%d) - shutdownReserveSeconds (%d) = %d.\n  The drain budget must be positive, and a hook that consumes the whole grace period gets the container SIGKILLed before Graylog can flush its in-memory buffers.\n  Either:\n    Raise graylog.terminationGracePeriodSeconds\n    Or lower graylog.lifecycle.preStopDrain.shutdownReserveSeconds / endpointPropagationDelaySeconds." $grace $settle $reserve $budget) }}
{{- end }}
{{/* pollIntervalSeconds >= 1 is enforced by values.schema.json; only the
     cross-field constraints need a template-time guard. */}}
lifecycle:
  preStop:
    exec:
      command:
        - /bin/sh
        - -c
        - |
          {{/* A real .sh, kept outside templates/ so it contains no Helm syntax and
               tooling can read it. .Files.Get returns it verbatim - all of its
               configuration arrives through the env below. */}}
          {{- .Files.Get "files/scripts/prestop-drain.sh" | nindent 10 }}
{{- end }}
{{- end }}

{{/*
Environment for the preStop drain script.

Rendered into the graylog-app container's `env` so the hook - which inherits the
container environment - gets its configuration without any templating inside the
script itself. Also means `kubectl describe pod` shows exactly what the drain was
configured with, and the script can be run by hand for testing.

Deliberately not GRAYLOG_-prefixed: this container's environment is read as
server.conf overrides, and a GRAYLOG_ name would look like a setting that does
not exist.

Call with: {{ include "graylog.prestopDrain.env" . | nindent 12 }}
*/}}
{{- define "graylog.prestopDrain.env" -}}
{{- if .Values.graylog.lifecycle.preStopDrain.enabled }}
{{- $drain := .Values.graylog.lifecycle.preStopDrain }}
{{- $grace := .Values.graylog.terminationGracePeriodSeconds | int }}
{{- $settle := $drain.endpointPropagationDelaySeconds | int }}
{{- $reserve := $drain.shutdownReserveSeconds | int }}
- name: GL_DRAIN_METRICS_URL
  value: {{ printf "http://127.0.0.1:%d/metrics" (.Values.graylog.service.ports.metrics | default 9833 | int) | quote }}
{{/* Same derivation as "graylog.lifecycle", which is where it is validated. */}}
- name: GL_DRAIN_BUDGET_SECONDS
  value: {{ sub $grace (add $settle $reserve) | int | quote }}
- name: GL_DRAIN_POLL_SECONDS
  value: {{ $drain.pollIntervalSeconds | int | quote }}
- name: GL_DRAIN_SETTLE_SECONDS
  value: {{ $settle | quote }}
- name: GL_DRAIN_STALL_POLLS
  value: {{ $drain.stallPolls | int | quote }}
- name: GL_DRAIN_STATUS_INTERVAL_SECONDS
  value: {{ $drain.statusIntervalSeconds | int | quote }}
- name: GL_DRAIN_CONFIRM_POLLS
  value: {{ $drain.confirmPolls | int | quote }}
- name: GL_DRAIN_METRICS_RETRIES
  value: {{ $drain.metricsRetries | int | quote }}
{{/* 0 disables the projection outright, so int is the right coercion here - a
     `default` would silently turn the intended 0 back into the chart default. */}}
- name: GL_DRAIN_FEASIBILITY_WARMUP_POLLS
  value: {{ $drain.feasibilityWarmupPolls | int | quote }}
- name: GL_DRAIN_GRACE_SECONDS
  value: {{ $grace | quote }}
- name: GL_DRAIN_RESERVE_SECONDS
  value: {{ $reserve | quote }}
{{- end }}
{{- end }}
