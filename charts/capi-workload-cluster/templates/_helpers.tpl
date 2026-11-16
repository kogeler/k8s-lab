{{/* Labels of every object. */}}
{{- define "capi-workload-cluster.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cluster-api
{{- end -}}

{{/*
Host port of the published API server: apiProxy.port, or 20000 + (adler32 of
the cluster name mod 10000), the same for every render of the same name.
*/}}
{{- define "capi-workload-cluster.apiProxyPort" -}}
{{- if gt (int .Values.apiProxy.port) 0 -}}
{{- .Values.apiProxy.port -}}
{{- else -}}
{{- add 20000 (mod (atoi (adler32sum .Values.cluster.name)) 10000) -}}
{{- end -}}
{{- end -}}

{{/* LXD proxy listen address: tcp:<address>:<port>, IPv6 in brackets. */}}
{{- define "capi-workload-cluster.apiProxyListen" -}}
{{- $address := .Values.apiProxy.listenAddress -}}
{{- if contains ":" $address -}}{{- $address = printf "[%s]" $address -}}{{- end -}}
{{- printf "tcp:%s:%s" $address (include "capi-workload-cluster.apiProxyPort" .) -}}
{{- end -}}

{{/* A container of the `helm test` Pod; .wait is [name, resource, selector, condition]. */}}
{{- define "capi-workload-cluster.testWait" -}}
- name: {{ index .wait 0 }}
  image: {{ .root.Values.tests.image | quote }}
  args:
    - wait
    - {{ index .wait 1 }}
    - {{ index .wait 2 }}
    - --for=condition={{ index .wait 3 }}
    - --namespace={{ .root.Release.Namespace }}
    - --timeout={{ .root.Values.tests.timeoutSeconds }}s
    - --cache-dir=/tmp/kube
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop: ["ALL"]
    seccompProfile:
      type: RuntimeDefault
  resources:
    requests: {cpu: 10m, memory: 32Mi}
    limits: {memory: 128Mi}
  volumeMounts:
    - {name: tmp, mountPath: /tmp}
{{- end -}}
