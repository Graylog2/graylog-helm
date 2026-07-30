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
          # Token-free journal drain. Always exits 0: a failing preStop hook
          # would stall termination for the whole grace period and then get the
          # container SIGKILLed, so every give-up path here hands over to
          # Graylog's own graceful shutdown instead of erroring.
          set -u
          URL="http://127.0.0.1:{{ .Values.graylog.service.ports.metrics | default 9833 | int }}/metrics"
          BUDGET={{ $budget }}
          POLL={{ $poll }}
          SETTLE={{ $settle }}
          STALL_LIMIT={{ $drain.stallPolls | int }}

          log() { echo "[prestop-drain] $*"; }

          # Kubernetes removes a Terminating pod from every Service
          # EndpointSlice, but kube-proxy convergence is not instant. Measuring
          # before it lands reads traffic that is already going away.
          log "waiting ${SETTLE}s for endpoint removal to propagate"
          sleep "${SETTLE}"

          # Wall clock, not a tick count. Each iteration can block for up to the
          # curl timeout, so counting polls would let the hook overrun BUDGET by
          # a wide margin and get the container SIGKILLed mid-shutdown.
          started=$(date +%s)
          deadline=$((started + BUDGET))
          stall=0
          last=""
          while [ "$(date +%s)" -lt "${deadline}" ]; do
            elapsed=$(( $(date +%s) - started ))
            # $NF is the gauge value; ^gl_ skips the "# HELP"/"# TYPE" lines, and
            # the anchored name avoids the similarly-spelled data-lake and kafka
            # gauges. awk exits non-zero when the gauge is absent.
            n=$(curl -fsS --max-time 5 "${URL}" 2>/dev/null \
              | awk '/^gl_journal_entries_uncommitted[{ ]/ { v = $NF } END { if (v == "") exit 1; printf "%d\n", v }')
            if [ -z "${n}" ]; then
              log "journal gauge unavailable after ${elapsed}s; handing over to graceful shutdown"
              exit 0
            fi
            if [ "${n}" -le 0 ]; then
              log "journal drained after ${elapsed}s"
              exit 0
            fi
            if [ "${n}" = "${last}" ]; then
              stall=$((stall + 1))
              if [ "${stall}" -ge "${STALL_LIMIT}" ]; then
                # Endpoint removal only sheds newly-established connections.
                # Long-lived TCP inputs and UDP keep arriving, so a flat gauge
                # means waiting longer will not help.
                log "journal flat at ${n} uncommitted entries across ${stall} polls (${elapsed}s); senders are still writing, handing over to graceful shutdown"
                exit 0
              fi
            else
              stall=0
            fi
            last="${n}"
            sleep "${POLL}"
          done
          log "drain budget of ${BUDGET}s exhausted with ${last} uncommitted entries remaining; handing over to graceful shutdown"
          exit 0
{{- end }}
{{- end }}
