{{/*
Container probes for the Graylog and Data Node containers.

The readiness probe is a StatefulSet's only rollout throttle. Nothing else paces
a rolling update, so a probe that goes green before the application can serve
lets the rollout move on to the next pod anyway. Each default below therefore
checks something that only becomes true once the pod can serve, rather than
checking that a port is open.

  graylog   startup/readiness  HTTP GET /api/system/lbstatus
                               Unauthenticated. Returns 200 ALIVE or 503 DEAD.
                               Graylog sets DEAD during graceful shutdown, and
                               an operator can set it by hand with
                               PUT /api/system/lbstatus/override/dead, which
                               needs credentials and an X-Requested-By header.
                               Readiness on this path is what lets the scale-in
                               drain in docs/graylog-message-handling.md pull a
                               pod out of the Service endpoints.

            liveness           TCP connect on the app port.
                               Not lbstatus, on purpose. DEAD means "stop
                               sending me traffic", not "this process is
                               broken". Liveness on lbstatus would have kubelet
                               kill a healthy pod that is draining or parked for
                               maintenance. Liveness is for a hung process, and
                               a TCP connect answers that.

  datanode  startup/readiness  TCP connect on the OpenSearch HTTP port (9200).
                               The Data Node binds its own REST API on 8999
                               about 34 seconds before it starts OpenSearch on
                               an idle single-node cluster, and the gap grows
                               when there are shards to recover. A probe on 8999
                               reports Ready while OpenSearch is still down, and
                               kubelet then takes down the next pod. 9200 binds
                               later, so it tracks when the node can serve.

            liveness           TCP connect on the Data Node API port (8999).
                               Liveness asks whether the Data Node process is
                               alive. Whether OpenSearch has come up is a
                               readiness question.

The Data Node gets no HTTP probe by default because both of its ports serve
HTTPS with authentication. An unauthenticated request returns 401 on "/" and 404
on every other path, so there is no health endpoint to probe. The image also
ships no HTTP client (no curl, wget, nc or python3), so an exec probe has
nothing to call. Gating Data Node readiness on real shard recovery needs an
endpoint the Data Node does not expose unauthenticated today. If your deployment
has one, override datanode.readinessProbe.httpGet or .exec.

Any probe block may carry its own httpGet, tcpSocket, exec or grpc key in
standard Kubernetes syntax. That replaces the chart default for that probe. The
timing fields still apply.
*/}}

{{/*
Render one probe.

Usage:
  {{- include "graylog.probe" (dict
        "name"    "readinessProbe"
        "probe"   .Values.graylog.readinessProbe
        "default" (include "graylog.probe.handler.lbstatus" .)
        "indent"  10) }}

Renders nothing when the probe is disabled, so the caller needs no guard.
*/}}
{{- define "graylog.probe" -}}
{{- $probe := .probe | default dict -}}
{{- $name := .name -}}
{{- $indent := .indent | default 10 | toString | atoi -}}
{{- $subIndent := add $indent 2 | toString | atoi -}}
{{- if $probe.enabled -}}
{{/* A user-supplied handler replaces the chart default. Only one is allowed.
     Kubernetes rejects a probe carrying two handlers, and picking one here
     would hide the mistake behind a probe that checks the wrong thing. */}}
{{- $handlers := list -}}
{{- range $key := list "httpGet" "tcpSocket" "exec" "grpc" -}}
{{- if index $probe $key -}}
{{- $handlers = append $handlers $key -}}
{{- end -}}
{{- end -}}
{{- if gt (len $handlers) 1 -}}
{{/* Keep the first line short and put everything else after a line break.
     helm-unittest matches a fail message only from the first line break
     onward, so anything the test suite asserts on has to sit below it. */}}
{{- $msg := "A probe declares more than one handler." -}}
{{- $msg = printf "%s\n\n%s sets %s, and a Kubernetes probe can only have one handler." $msg $name (join " and " $handlers) -}}
{{- $msg = printf "%s\n  Keep the handler you want and remove the others." $msg -}}
{{- fail $msg -}}
{{- end -}}
{{- printf "%s:" $name | nindent $indent -}}
{{- if $handlers -}}
{{- $key := first $handlers -}}
{{- dict $key (index $probe $key) | toYaml | nindent $subIndent -}}
{{- else -}}
{{- .default | trim | nindent $subIndent -}}
{{- end -}}
{{- range $field := list "initialDelaySeconds" "periodSeconds" "timeoutSeconds" "failureThreshold" -}}
{{- with index $probe $field -}}
{{- printf "%s: %d" $field (. | int) | nindent $subIndent -}}
{{- end -}}
{{- end -}}
{{/* Kubernetes requires successThreshold=1 on liveness and startup probes and
     rejects any other value, so only readiness renders it. */}}
{{- if eq $name "readinessProbe" -}}
{{- with $probe.successThreshold -}}
{{- printf "successThreshold: %d" (. | int) | nindent $subIndent -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Default handler for Graylog startup and readiness: the unauthenticated
load-balancer status endpoint.
*/}}
{{- define "graylog.probe.handler.lbstatus" -}}
httpGet:
  path: /api/system/lbstatus
  port: {{ .Values.graylog.service.ports.app | int }}
  scheme: {{ .Values.graylog.config.tls.enabled | ternary "HTTPS" "HTTP" }}
{{- end -}}

{{/*
Default handler for Graylog liveness: a TCP connect on the app port.
*/}}
{{- define "graylog.probe.handler.graylogTcp" -}}
tcpSocket:
  port: {{ .Values.graylog.service.ports.app | int }}
{{- end -}}

{{/*
Default handler for Data Node liveness: a TCP connect on the Data Node REST API
port.
*/}}
{{- define "graylog.probe.handler.datanodeApiTcp" -}}
tcpSocket:
  port: {{ .Values.datanode.service.ports.api | default 8999 | int }}
{{- end -}}

{{/*
Default handler for Data Node startup and readiness: a TCP connect on the
OpenSearch HTTP port.
*/}}
{{- define "graylog.probe.handler.datanodeDataTcp" -}}
tcpSocket:
  port: {{ .Values.datanode.service.ports.data | default 9200 | int }}
{{- end -}}
