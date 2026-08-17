{{/*
Container probes for the Graylog and Data Node containers.

A StatefulSet has exactly one rollout throttle: the readiness probe. Nothing
else paces a rolling update, so the fidelity of that probe *is* the safety
mechanism, and a probe that answers faster than the application recovers lets
the rollout outrun it. The defaults below are therefore chosen to mean "this pod
can actually serve", not "a port is open".

  graylog   startup/readiness  HTTP GET /api/system/lbstatus
                               Unauthenticated, 200 ALIVE / 503 DEAD. Graylog
                               flips it to DEAD during graceful shutdown, and an
                               operator can flip it by hand
                               (PUT /api/system/lbstatus/override/dead, which
                               needs credentials and an X-Requested-By header).
                               Readiness on this path is what makes the scale-in
                               drain in docs/graylog-message-handling.md able to
                               take a pod out of the Service endpoints.

            liveness           TCP connect on the app port.
                               Deliberately NOT lbstatus. DEAD means "stop
                               sending me traffic", not "this process is
                               broken": liveness on lbstatus would have kubelet
                               kill a perfectly healthy pod that is draining, or
                               that an operator has parked for maintenance.
                               Liveness is for a wedged process, and that is what
                               a TCP connect answers.

  datanode  startup/readiness  TCP connect on the OpenSearch HTTP port (9200).
                               The Data Node binds its own REST API (8999) well
                               before it starts OpenSearch - measured ~34s apart
                               on an idle single-node cluster, and longer with
                               shards to recover. Probing 8999 therefore reports
                               Ready while OpenSearch is still down, and on a
                               rolling update kubelet takes down the next pod on
                               the strength of that. 9200 is the later and more
                               honest signal.

            liveness           TCP connect on the Data Node API port (8999).
                               The Data Node process being alive is what liveness
                               is for; OpenSearch coming up is readiness' job.

Why the Data Node gets no HTTP probe by default: both of its ports serve HTTPS
*with authentication*. An unauthenticated request to either 8999 or 9200 gets
401 on "/" and 404 on every other path, so there is no unauthenticated health
endpoint to probe, and the image ships no HTTP client (no curl, wget, nc or
python3) for an exec probe to use instead. Gating Data Node readiness on real
shard recovery needs an endpoint the Data Node does not currently expose
unauthenticated. If your deployment has one, override
datanode.readinessProbe.httpGet or .exec - see below.

Overriding the handler: any probe block may carry its own httpGet, tcpSocket,
exec or grpc key in standard Kubernetes syntax, which replaces the chart default
for that probe entirely. The timing fields are applied either way.
*/}}

{{/*
Render one probe.

Usage:
  {{- include "graylog.probe" (dict
        "name"    "readinessProbe"
        "probe"   .Values.graylog.readinessProbe
        "default" (include "graylog.probe.handler.lbstatus" .)
        "indent"  10) }}

Emits nothing at all when the probe is disabled, so the caller needs no guard.
*/}}
{{- define "graylog.probe" -}}
{{- $probe := .probe | default dict -}}
{{- $name := .name -}}
{{- $indent := .indent | default 10 | toString | atoi -}}
{{- $subIndent := add $indent 2 | toString | atoi -}}
{{- if $probe.enabled -}}
{{/* A user-supplied handler replaces the chart default. Exactly one is allowed:
     Kubernetes rejects a probe carrying two handlers, and silently picking one
     here would hide the mistake behind a probe that tests the wrong thing. */}}
{{- $handlers := list -}}
{{- range $key := list "httpGet" "tcpSocket" "exec" "grpc" -}}
{{- if index $probe $key -}}
{{- $handlers = append $handlers $key -}}
{{- end -}}
{{- end -}}
{{- if gt (len $handlers) 1 -}}
{{/* The first line is deliberately short and everything substantive follows a
     break: helm-unittest only matches a fail message from the first line break
     onward, so anything asserted in the test suite has to live below it. */}}
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
     rejects anything else, so it is only rendered for readiness. */}}
{{- if eq $name "readinessProbe" -}}
{{- with $probe.successThreshold -}}
{{- printf "successThreshold: %d" (. | int) | nindent $subIndent -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Default handler: Graylog's unauthenticated load-balancer status endpoint.
*/}}
{{- define "graylog.probe.handler.lbstatus" -}}
httpGet:
  path: /api/system/lbstatus
  port: {{ .Values.graylog.service.ports.app | int }}
  scheme: {{ .Values.graylog.config.tls.enabled | ternary "HTTPS" "HTTP" }}
{{- end -}}

{{/*
Default handler: TCP connect on the Graylog app port.
*/}}
{{- define "graylog.probe.handler.graylogTcp" -}}
tcpSocket:
  port: {{ .Values.graylog.service.ports.app | int }}
{{- end -}}

{{/*
Default handler: TCP connect on the Data Node REST API port.
*/}}
{{- define "graylog.probe.handler.datanodeApiTcp" -}}
tcpSocket:
  port: {{ .Values.datanode.service.ports.api | default 8999 | int }}
{{- end -}}

{{/*
Default handler: TCP connect on the Data Node's OpenSearch HTTP port.
*/}}
{{- define "graylog.probe.handler.datanodeDataTcp" -}}
tcpSocket:
  port: {{ .Values.datanode.service.ports.data | default 9200 | int }}
{{- end -}}
