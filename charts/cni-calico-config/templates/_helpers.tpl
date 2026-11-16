{{- define "cni-calico-config.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cluster-addons
{{- end -}}

{{/* Annotations of a test resource (argument: its hook weight); deleted on success. */}}
{{- define "cni-calico-config.testHook" -}}
helm.sh/hook: test
helm.sh/hook-weight: {{ . | quote }}
helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
{{- end -}}

{{/* securityContext of every gate container. */}}
{{- define "cni-calico-config.containerSecurity" -}}
runAsNonRoot: true
runAsUser: 65534
runAsGroup: 65534
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/* resources of the gate's waits and client: not the first Pods evicted. */}}
{{- define "cni-calico-config.testResources" -}}
requests: {cpu: 10m, memory: 32Mi}
limits: {memory: 128Mi}
{{- end -}}
