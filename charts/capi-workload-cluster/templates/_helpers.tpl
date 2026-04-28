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
Per-workload API proxy port (PLAN §16.3 Step 15).

Default: deterministic Adler-32 hash of the Cluster CR name, mapped
into the range 20000-29999 (`add 20000 (mod adler32 10000)`). Pure
function — re-rendering the same `cluster.name` always yields the
same port, which keeps `helm upgrade` no-op-friendly and makes the
written kubeconfig stable across re-applies.

Override: `loadBalancer.lxc.proxyApiPort` in values.yaml — explicit
integer wins over the hash. Used to resolve hash collisions when
two workload clusters on the same LXD host happen to land on the
same port (collision rate ≈ 0.5% on 10 workloads, ≈ 5% on 30; for
larger fleets the operator manages explicit assignments).

The hash uses Sprig `adler32sum`, which returns a *decimal* string
parseable directly through `atoi` — sha256sum returns hex which
Helm has no built-in decoder for.
*/}}
{{- define "capi-workload-cluster.apiProxyPort" -}}
{{- /* values.schema.json guarantees loadBalancer.lxc.proxyApiPort
       exists as an integer; values.yaml ships 0 as the default. */ -}}
{{- $override := .Values.loadBalancer.lxc.proxyApiPort | int -}}
{{- if gt $override 0 -}}
{{- $override -}}
{{- else -}}
{{- add 20000 (mod (atoi (adler32sum .Values.cluster.name)) 10000) -}}
{{- end -}}
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
