# Mgmt-1 fixture variables. Defaults track §8 reference deployment so
# `terraform plan` works standalone without overrides. Phase 4's
# export_artifacts role drops `.artifacts/bootstrap.auto.tfvars.json`
# at the repo root (path discovered via path.module in main.tf); the
# auto-tfvars file overrides only the keys it provides — anything not
# in the bundle uses the §8 default declared here.
#
# `lxd_host_address` is NOT in the export_artifacts payload; the
# fixture derives it from `k8s_lab_bootstrap_api_server_url` host
# component (see main.tf locals) so the operator never has to
# hand-pin it for the local Vagrant flow.

# ---- Source of truth: bootstrap handoff ----------------------------------

variable "k8s_lab_bootstrap_kubeconfig_path" {
  description = "Path to the bootstrap k3s kubeconfig (rewritten to runner-reachable LXD-host endpoint by export_artifacts §13.12)."
  type        = string
  default     = ""
}

variable "k8s_lab_bootstrap_api_server_url" {
  description = "Bootstrap k3s API URL the runner can reach. Used to derive lxd_host_address."
  type        = string
  default     = ""
}

# ---- §8 globals consumed by the workload_cluster module ------------------

variable "k8s_lab_project_name" {
  type    = string
  default = "capi-lab"
}

variable "k8s_lab_infrastructure_secret_name" {
  type    = string
  default = "incus-identity"
}

variable "k8s_lab_management_cluster_name" {
  type    = string
  default = "mgmt-1"
}

variable "k8s_lab_kubernetes_version" {
  type    = string
  default = "v1.35.0"
}

variable "k8s_lab_management_controlplane_count" {
  description = "Mgmt control-plane replica count. CAPI invariant: must be odd. Default 1 (no HA on Stage 1 mgmt — PLAN §2.12 last bullet)."
  type        = number
  default     = 1
}

variable "k8s_lab_management_worker_count" {
  description = "Mgmt worker replica count. Default 2 — set by the cni-calico chart's helm test acceptance (phase 6 'live pod-to-pod across workers' enforces pod anti-affinity that requires 2 distinct worker nodes; with only 1 worker the probe-b Pod stays Pending and TF apply fails on the helm test gate). CAPI controllers + cert-manager do not architecturally need worker HA, but the workload_cluster module unconditionally drives Gate B helm test, so 2 workers is the floor for any cluster going through that module."
  type        = number
  default     = 2
}

# Pod / service CIDRs are re-used from the workload reference set
# (different Cluster CRs have independent clusterNetwork blocks; values
# may safely match).
variable "k8s_lab_workload_pod_cidr_v4" {
  type    = string
  default = "10.244.0.0/16"
}

variable "k8s_lab_workload_pod_cidr_v6" {
  type    = string
  default = "fd42:77:2::/56"
}

variable "k8s_lab_workload_service_cidr_v4" {
  type    = string
  default = "10.96.0.0/16"
}

variable "k8s_lab_workload_service_cidr_v6" {
  type    = string
  default = "fd42:77:3::/112"
}

# Mgmt-specific MetalLB range — disjoint from workload's `::200-::2ff`
# default to avoid speaker announcement collisions if both clusters
# coexist before pivot. MetalLB is not architecturally needed on mgmt
# (CAPI controllers do not expose Service type=LoadBalancer); the
# workload_cluster module installs it unconditionally, so we keep it
# functional but isolated.
variable "k8s_lab_management_metallb_vip_range_v6" {
  type    = string
  default = "2001:db8:42:100::300-2001:db8:42:100::3ff"
}

variable "k8s_lab_metallb_interface" {
  type    = string
  default = "eth1"
}

# ---- Image refs (default = upstream CAPN simplestreams) ------------------

variable "k8s_lab_images_controlplane" {
  type    = string
  default = "capi:kubeadm/VERSION"
}

variable "k8s_lab_images_controlplane_fingerprint" {
  type    = string
  default = ""
}

variable "k8s_lab_images_worker" {
  type    = string
  default = "capi:kubeadm/VERSION"
}

variable "k8s_lab_images_worker_fingerprint" {
  type    = string
  default = ""
}

variable "k8s_lab_controlplane_profiles_extra" {
  type    = list(string)
  default = []
}

variable "k8s_lab_worker_profiles_extra" {
  type    = list(string)
  default = []
}

variable "k8s_lab_controlplane_devices_extra" {
  type    = list(string)
  default = []
}

variable "k8s_lab_worker_devices_extra" {
  type    = list(string)
  default = []
}

variable "k8s_lab_kube_proxy_nodeport_addresses" {
  type    = list(string)
  default = []
}

# ---- Chart version pins (default = chart Chart.yaml versions in repo) ----

variable "cluster_class_chart_version" {
  description = "Tracks charts/capi-cluster-class/Chart.yaml version. §8 k8s_lab_capi_cluster_class_chart_version."
  type        = string
  default     = "0.6.3"
}

variable "cluster_workload_chart_version" {
  description = "Tracks charts/capi-workload-cluster/Chart.yaml version. §8 k8s_lab_capi_workload_cluster_chart_version. MUST be paired with the chart's pinned `k8s-lab.io/capi-cluster-class-chart-version` annotation."
  type        = string
  default     = "0.8.0"
}

variable "cni_calico_chart_version" {
  description = "Tracks charts/cni-calico/Chart.yaml version."
  type        = string
  default     = "0.2.0"
}

variable "metallb_chart_version" {
  description = "Tracks charts/metallb/Chart.yaml version."
  type        = string
  default     = "0.1.0"
}

variable "metallb_config_chart_version" {
  description = "Tracks charts/metallb-config/Chart.yaml version."
  type        = string
  default     = "0.1.3"
}

# ---- Mgmt-side connection ------------------------------------------------

variable "mgmt_kubeconfig_path" {
  description = "Override path to the mgmt-side kubeconfig. Default = .artifacts/bootstrap.kubeconfig at the repo root (Phase 4 export_artifacts handoff)."
  type        = string
  default     = ""
}

# ---- Auto-tfvars passthrough (silences warnings) -------------------------
# Keys emitted by the Phase 4 export_artifacts handoff that this fixture
# does not consume itself — declared as no-op variables so Terraform
# does not warn about unused values in `bootstrap.auto.tfvars.json`.

variable "k8s_lab_workload_cluster_name" {
  type    = string
  default = ""
}

variable "k8s_lab_workload_controlplane_count" {
  type    = number
  default = 0
}

variable "k8s_lab_workload_worker_count" {
  type    = number
  default = 0
}

variable "k8s_lab_metallb_vip_range_v6" {
  type    = string
  default = ""
}

variable "k8s_lab_unprivileged_nodes" {
  type    = bool
  default = true
}

variable "k8s_lab_pivot_enabled" {
  type    = bool
  default = false
}

variable "k8s_lab_cluster_topology_enabled" {
  type    = bool
  default = true
}

variable "k8s_lab_capn_provider_version" {
  type    = string
  default = ""
}
