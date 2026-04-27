{{/*
Standard chart-name / fullname / labels helpers, mirroring the layout
of charts/cni-calico so an agent reading both sees the same shape.
PLAN §17.1.
*/}}

{{- define "metallb-config.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "metallb-config.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "metallb-config.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "metallb-config.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/name: {{ include "metallb-config.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cluster-addons
{{- end -}}

{{/*
NOTE: no client-side CRD readiness gate here.

Unlike charts/cni-calico (which depends on tigera-operator that ships
CRDs via Helm's `crds/` folder mechanism — installed BEFORE template
render so `Capabilities.APIVersions.Has` works on render), the metallb
0.15.3 subchart ships its CRDs as regular `templates/` in a `crds`
sub-dependency. Helm 3's kind-sorted apply order still installs them
before the IPAddressPool / L2Advertisement CRs at apply time, but on
the render stage `Capabilities.APIVersions.Has "metallb.io/v1beta1"`
is false and a `fail`-based gate would create a false-positive
client-side error on the very first `helm install`.

If the metallb subchart is disabled (`metallb.crds.enabled: false`
overridden by a consumer), the apply will fail server-side with the
unmistakable "no matches for kind IPAddressPool in version
metallb.io/v1beta1" — which is enough signal for triage.
*/}}

{{/*
Required-value guards for consumer-supplied tunables that have no safe
default (substrate would silently misbehave or template would render an
invalid CR). values.schema.json catches type/shape; this guard catches
the empty-string case which JSON schema's `minLength: 1` already covers
on the way in but we re-assert for the `helm template --set` path
where schema bypass is possible.
*/}}
{{- define "metallb-config.requireValues" -}}
{{- if not .Values.pool.rangeV6 -}}
{{- fail "metallb-config: pool.rangeV6 is required (bind to §8 k8s_lab_metallb_vip_range_v6). Empty values are rejected because IPAddressPool with no addresses renders as an inert CR and silently breaks LoadBalancer Services downstream." -}}
{{- end -}}
{{- if not .Values.l2.interface -}}
{{- fail "metallb-config: l2.interface is required (bind to §8 k8s_lab_metallb_interface). Empty values are rejected because L2Advertisement with no `interfaces` selector lets MetalLB pick any speaker NIC, which on this dual-NIC substrate would announce VIPs on the wrong segment." -}}
{{- end -}}
{{- end -}}
