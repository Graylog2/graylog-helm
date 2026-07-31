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

          # kubelet discards preStop stdout — it only ever surfaces (truncated) in
          # a FailedPreStopHook event, and only when the hook fails. Writing to
          # PID 1's stdout puts these lines in the container's real log stream so
          # `kubectl logs` can see a drain happen. Keep the plain echo too: it is
          # what lands in the event if this hook ever does fail.
          log() {
            echo "[prestop-drain] $*"
            echo "[prestop-drain] $*" > /proc/1/fd/1 2>/dev/null || true
          }

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
          # Progress is measured against the best (lowest) depth seen so far, not
          # against the previous sample. Under live ingest the gauge oscillates
          # continuously — two consecutive samples are essentially never equal —
          # so an equality test never fires and the hook burns the whole budget
          # for nothing. Requiring a new low means "no improvement" is detected
          # even while the raw number jitters.
          stall=0
          best=""
          while [ "$(date +%s)" -lt "${deadline}" ]; do
            elapsed=$(( $(date +%s) - started ))
            # $NF is the gauge value; ^gl_ skips the "# HELP"/"# TYPE" lines, and
            # the anchored name avoids the similarly-spelled data-lake and kafka
            # gauges. awk exits non-zero when the gauge is absent. The append rate
            # is diagnostic only: it explains *why* a drain cannot finish.
            sample=$(curl -fsS --max-time 5 "${URL}" 2>/dev/null \
              | awk '/^gl_journal_entries_uncommitted[{ ]/ { v = $NF }
                     /^gl_journal_append_1_sec_rate[{ ]/   { r = $NF }
                     END { if (v == "") exit 1; printf "%d %d\n", v, r }')
            if [ -z "${sample}" ]; then
              log "journal gauge unavailable after ${elapsed}s; handing over to graceful shutdown"
              exit 0
            fi
            n=${sample% *}
            rate=${sample#* }
            if [ "${n}" -le 0 ]; then
              log "journal drained after ${elapsed}s"
              exit 0
            fi
            if [ -z "${best}" ] || [ "${n}" -lt "${best}" ]; then
              best="${n}"
              stall=0
            else
              stall=$((stall + 1))
              if [ "${stall}" -ge "${STALL_LIMIT}" ]; then
                # Endpoint removal only sheds newly-established connections.
                # Long-lived TCP inputs and UDP senders keep writing, so the
                # journal will not reach zero no matter how long we wait. Only
                # stopping the inputs can do that, and that needs a token.
                log "no progress in ${stall} polls (${elapsed}s): depth ${n}, best ${best}, still ingesting ${rate} msg/s. A true drain needs inputs stopped; handing over to graceful shutdown"
                exit 0
              fi
            fi
            sleep "${POLL}"
          done
          log "drain budget of ${BUDGET}s exhausted at depth ${n} (best ${best}, ingesting ${rate} msg/s); handing over to graceful shutdown"
          exit 0
{{- end }}
{{- end }}
