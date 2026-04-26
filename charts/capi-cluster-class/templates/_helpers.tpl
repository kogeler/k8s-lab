{{/*
CR-name rotation contract (PLAN §16.2).

Every object rendered by this chart carries a version slug derived from
Chart.Version so that a `helm upgrade` with a bumped version produces a
distinct name and side-steps the CAPI webhook immutability rule on
ClusterClass/*Template objects that are already referenced by a Cluster.

The slug replaces "." with "-" to land inside DNS-1123-subdomain-safe
characters even under stricter downstream validators; the transform is
deterministic so charts/capi-workload-cluster (PLAN §16.3) and the
Terraform wrapper (PLAN §16.4) can reproduce the exact ClusterClass
name from the same inputs.
*/}}

{{- define "capi-cluster-class.versionSlug" -}}
{{- .Chart.Version | replace "." "-" | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
"{prefix}-{versionSlug}". Used as ClusterClass name and as the common
suffix for every other object — see individual template files.
*/}}
{{- define "capi-cluster-class.classFullName" -}}
{{- printf "%s-%s" .Values.clusterClass.name (include "capi-cluster-class.versionSlug" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Sub-object names. Each keeps the classFullName suffix so bumping the
chart version cascades through every referenced template simultaneously.
*/}}
{{- define "capi-cluster-class.lxcClusterTemplateName" -}}
{{- printf "%s-infra" (include "capi-cluster-class.classFullName" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "capi-cluster-class.lxcMachineTemplateCPName" -}}
{{- printf "%s-cp" (include "capi-cluster-class.classFullName" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "capi-cluster-class.lxcMachineTemplateWorkerName" -}}
{{- printf "%s-md0" (include "capi-cluster-class.classFullName" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "capi-cluster-class.kubeadmControlPlaneTemplateName" -}}
{{- printf "%s-kcp" (include "capi-cluster-class.classFullName" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "capi-cluster-class.kubeadmConfigTemplateWorkerName" -}}
{{- printf "%s-md0-bootstrap" (include "capi-cluster-class.classFullName" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Substrate-required LXD profile baselines. These names are owned by
role lxd_profiles (PLAN §13.6) and MUST appear on every CAPN-managed
instance — they carry the kubeadm / systemd / cloud-init overrides
the unprivileged LXC path relies on. Consumers extend via
`.Values.profilesExtra.{controlplane,worker}`; the baseline itself is
not user-tunable per memory rule "Chart-required values are hardcoded".
*/}}
{{- define "capi-cluster-class.controlPlaneProfiles" -}}
- capi-base
- capi-controlplane
{{- range .Values.profilesExtra.controlplane }}
- {{ . }}
{{- end }}
{{- end -}}

{{- define "capi-cluster-class.workerProfiles" -}}
- capi-base
- capi-worker
{{- range .Values.profilesExtra.worker }}
- {{ . }}
{{- end }}
{{- end -}}

{{/*
Substrate-required LXD profile baseline for the haproxy load balancer
LXC instance that CAPN spawns when `loadBalancer.lxc` mode is selected.
The LB instance must carry a profile that supplies a root disk device
and at least the internal-net NIC (so haproxy can reach control-plane
backends via capi-int) — without it CAPN aborts with
"No root device could be found" at instance-creation time.

`capi-base` (owned by role lxd_profiles, PLAN §13.6) is the minimal
profile that ships both prerequisites; consumer extras append after the
baseline through `loadBalancer.lxc.profilesExtra`. Like the CP / worker
baselines, this list is NOT user-tunable: the baseline is a hard
substrate invariant, only the extras are.
*/}}
{{- define "capi-cluster-class.loadBalancerProfiles" -}}
- capi-base
{{- range (((.Values.loadBalancer | default dict).lxc | default dict).profilesExtra | default list) }}
- {{ . }}
{{- end }}
{{- end -}}

{{/*
Common labels attached to every rendered object.
*/}}
{{- define "capi-cluster-class.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cluster-api
{{- end -}}

{{/*
CAPI / CAPN API availability gates. A chart install against a
bootstrap cluster that has not yet been `clusterctl init`-ed or has a
different infrastructure provider aborts with a readable error instead
of silently producing zero objects.
*/}}
{{- define "capi-cluster-class.requireCAPI" -}}
{{- if not (.Capabilities.APIVersions.Has "cluster.x-k8s.io/v1beta2/ClusterClass") -}}
{{- fail "CAPI core v1beta2 (cluster.x-k8s.io/v1beta2) is not served by the target cluster. Run `clusterctl init` with CAPI v1.10+ before installing this chart." -}}
{{- end -}}
{{- end -}}

{{- define "capi-cluster-class.requireCAPN" -}}
{{- if not (.Capabilities.APIVersions.Has "infrastructure.cluster.x-k8s.io/v1alpha2/LXCClusterTemplate") -}}
{{- fail "CAPN v1alpha2 (infrastructure.cluster.x-k8s.io/v1alpha2) is not served by the target cluster. Install cluster-api-provider-incus v0.8+ via `clusterctl init --infrastructure incus` first." -}}
{{- end -}}
{{- end -}}

{{- define "capi-cluster-class.requireKubeadm" -}}
{{- if not (.Capabilities.APIVersions.Has "controlplane.cluster.x-k8s.io/v1beta2/KubeadmControlPlaneTemplate") -}}
{{- fail "KubeadmControlPlane provider v1beta2 is not served by the target cluster. Re-run `clusterctl init` with the kubeadm control-plane + bootstrap providers." -}}
{{- end -}}
{{- if not (.Capabilities.APIVersions.Has "bootstrap.cluster.x-k8s.io/v1beta2/KubeadmConfigTemplate") -}}
{{- fail "KubeadmConfig bootstrap provider v1beta2 is not served by the target cluster. Re-run `clusterctl init` with the kubeadm bootstrap provider." -}}
{{- end -}}
{{- end -}}
