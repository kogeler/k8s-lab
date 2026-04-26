{{/*
ClusterClass name reproduction (PLAN §16.3).

charts/capi-cluster-class/templates/_helpers.tpl renders the
ClusterClass metadata.name as "{prefix}-{slug(Chart.Version)}" where
slug = ToLower(Replace ".", "-"). This chart MUST reproduce the exact
same string so spec.topology.classRef.name resolves.

The cluster-class chart version this chart is compatible with is
pinned in Chart.yaml under
  annotations."k8s-lab.io/capi-cluster-class-chart-version"
and read here, so consumers (Terraform fixtures, direct `helm install`)
do NOT pass the version through values. Bumping the cluster-class
chart REQUIRES a paired bump of that annotation + this chart's own
version field — see Chart.yaml comment.
*/}}
{{- define "capi-workload-cluster.clusterClassVersion" -}}
{{- $v := index .Chart.Annotations "k8s-lab.io/capi-cluster-class-chart-version" -}}
{{- if not $v -}}
{{- fail "Chart.yaml is missing annotations[\"k8s-lab.io/capi-cluster-class-chart-version\"]; cannot derive ClusterClass metadata.name. Restore the annotation pinned to the matching charts/capi-cluster-class Chart.Version." -}}
{{- end -}}
{{- $v -}}
{{- end -}}

{{- define "capi-workload-cluster.classFullName" -}}
{{- $slug := include "capi-workload-cluster.clusterClassVersion" . | replace "." "-" | lower | trunc 63 | trimSuffix "-" -}}
{{- printf "%s-%s" .Values.clusterClass.name $slug | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels attached to every rendered object. Mirrors the
capi-cluster-class chart so the two releases can be correlated by
helm.sh/chart + app.kubernetes.io/part-of.
*/}}
{{- define "capi-workload-cluster.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cluster-api
{{- end -}}

{{/*
CAPI core API availability gate. A chart install against a bootstrap
cluster that has not yet been `clusterctl init`-ed aborts with a
readable error instead of silently producing zero objects.

CAPN gate is intentionally not enforced here — the Cluster CR itself
does not reference any CAPN type directly; it goes through the
ClusterClass which carries the CAPN-typed templateRefs. If the
ClusterClass is missing or its referenced *Templates are missing,
CAPI's webhook on Cluster admission fails the install with a clear
"ClusterClass <name> not found in namespace <ns>" message.
*/}}
{{- define "capi-workload-cluster.requireCAPI" -}}
{{- if not (.Capabilities.APIVersions.Has "cluster.x-k8s.io/v1beta2/Cluster") -}}
{{- fail "CAPI core v1beta2 (cluster.x-k8s.io/v1beta2) is not served by the target cluster. Run `clusterctl init` with CAPI v1.10+ before installing this chart." -}}
{{- end -}}
{{- end -}}
