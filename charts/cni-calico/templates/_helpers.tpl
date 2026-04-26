{{/*
Standard chart-name / fullname / labels helpers, mirroring the layout
of charts/capi-workload-cluster so an agent reading both sees the same
shape. PLAN §17.1.
*/}}

{{- define "cni-calico.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cni-calico.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "cni-calico.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "cni-calico.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/name: {{ include "cni-calico.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cluster-addons
{{- end -}}

{{/*
CRD readiness gate — Installation CR cannot be applied until tigera-
operator's CRDs (operator.tigera.io/v1) are registered. The dependency
chart ships them in its `crds/` directory which Helm installs ahead of
templates, but we still gate explicitly so a chart consumer that
skipped the dependency for any reason hits a readable failure rather
than the cryptic "no kind 'Installation' found in operator.tigera.io".
*/}}
{{- define "cni-calico.requireOperator" -}}
{{- if not (.Capabilities.APIVersions.Has "operator.tigera.io/v1/Installation") -}}
{{- fail "operator.tigera.io/v1 is not served. The tigera-operator dependency must be installed (see Chart.yaml) before this chart can render its Installation CR." -}}
{{- end -}}
{{- end -}}

{{/*
Substrate-required argument guards. Mirrors the policy used by
charts/capi-cluster-class kubeadm templates: substrate-managed knobs
are hardcoded, and consumer overrides through any `*ExtraArgs`-shaped
field are rejected with a `fail` printf. The CNI chart has no such
list at the moment (Installation CR has no `extraArgs` shape we
expose), so this stub exists for symmetry / future-proofing only.
*/}}
{{- define "cni-calico.assertNoReservedOverrides" -}}
{{/* intentionally empty — no consumer-facing pass-through args today */}}
{{- end -}}
