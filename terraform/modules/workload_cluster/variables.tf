# ----------------------------------------------------------------------------
# Mgmt-side connection
# ----------------------------------------------------------------------------

variable "mgmt_kubeconfig_path" {
  description = "Path to the management-cluster kubeconfig. Always points at .artifacts/mgmt.kubeconfig — the same file pre- and post-pivot (pivot_clusterctl_move overwrites it in place after clusterctl move). PLAN §16.4."
  type        = string
}

# ----------------------------------------------------------------------------
# Cluster identity + sizing (bound to PLAN §8 globals)
# ----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Workload Cluster CR name. §8 k8s_lab_workload_cluster_name."
  type        = string
}

variable "cluster_namespace" {
  description = "Namespace for the workload Cluster CR. MUST be one of §8 k8s_lab_capn_identity_namespaces."
  type        = string
  default     = "capi-clusters"
}

variable "kubernetes_version" {
  description = "K8s version for the workload cluster. Must exist in CAPN simplestreams set."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+(\\+.+)?$", var.kubernetes_version))
    error_message = "kubernetes_version must match v<major>.<minor>.<patch>(+suffix)?, e.g. v1.35.0."
  }
}

variable "controlplane_count" {
  description = "Workload control-plane replica count. CAPI KCP webhook rejects even values under stacked etcd."
  type        = number

  validation {
    condition     = var.controlplane_count > 0 && var.controlplane_count % 2 == 1
    error_message = "controlplane_count must be a positive odd integer (CAPI stacked-etcd quorum invariant)."
  }
}

variable "worker_count" {
  description = "Workload worker replica count (single MachineDeployment md-0 in MVP)."
  type        = number

  validation {
    condition     = var.worker_count > 0
    error_message = "worker_count must be a positive integer."
  }
}

# ----------------------------------------------------------------------------
# Per-workload ClusterClass identity
# ----------------------------------------------------------------------------

variable "cluster_class_chart_version" {
  description = "helm_release.version for charts/capi-cluster-class. §8 k8s_lab_capi_cluster_class_chart_version."
  type        = string
}

variable "cluster_workload_chart_version" {
  description = "helm_release.version for charts/capi-workload-cluster. §8 k8s_lab_capi_workload_cluster_chart_version. Must match the chart's pinned k8s-lab.io/capi-cluster-class-chart-version annotation."
  type        = string
}

variable "cluster_class_namespace" {
  description = "Namespace where the per-workload ClusterClass is installed. Default = same as cluster_namespace (each workload self-contained)."
  type        = string
  default     = ""
}

variable "class_prefix" {
  description = "Logical prefix passed to charts/capi-cluster-class as clusterClass.name. Final ClusterClass metadata.name = <prefix>-<chart-version-slug>."
  type        = string
  default     = "capn-default"
}

# ----------------------------------------------------------------------------
# CAPI cluster networking (consumed by capi-workload-cluster + cni-calico)
# ----------------------------------------------------------------------------

variable "pod_cidrs" {
  description = "[IPv4, IPv6] pod CIDRs (dual-stack). §8 k8s_lab_workload_pod_cidr_{v4,v6}."
  type        = list(string)

  validation {
    condition     = length(var.pod_cidrs) == 2
    error_message = "pod_cidrs must contain exactly two entries: [IPv4, IPv6]."
  }
}

variable "service_cidrs" {
  description = "[IPv4, IPv6] service CIDRs (dual-stack). §8 k8s_lab_workload_service_cidr_{v4,v6}."
  type        = list(string)

  validation {
    condition     = length(var.service_cidrs) == 2
    error_message = "service_cidrs must contain exactly two entries: [IPv4, IPv6]."
  }
}

# ----------------------------------------------------------------------------
# Substrate template extras (passthrough to capi-cluster-class chart)
# ----------------------------------------------------------------------------

variable "infrastructure_secret_name" {
  description = "CAPN identity Secret name. §8 k8s_lab_infrastructure_secret_name. Must already exist in cluster_namespace (provisioned by Ansible role bootstrap_capn_secret §13.11)."
  type        = string
  default     = "incus-identity"
}

variable "image_controlplane_ref" {
  description = "CAPN image ref for control-plane LXC (literal VERSION substituted at runtime). §8 k8s_lab_images_controlplane."
  type        = string
  default     = "capi:kubeadm/VERSION"
}

variable "image_controlplane_fingerprint" {
  description = "Optional sha256 fingerprint pin for the CP image. Empty = resolve by name."
  type        = string
  default     = ""
}

variable "image_worker_ref" {
  description = "CAPN image ref for worker LXC. §8 k8s_lab_images_worker."
  type        = string
  default     = "capi:kubeadm/VERSION"
}

variable "image_worker_fingerprint" {
  description = "Optional sha256 fingerprint pin for the worker image."
  type        = string
  default     = ""
}

variable "load_balancer" {
  description = "LXCClusterTemplate.spec.template.spec.loadBalancer (exactly one of {lxc, oci, ovn, kubeVIP, external}). MVP default = {lxc = {}}."
  type        = any
  default     = { lxc = {} }
}

variable "controlplane_profiles_extra" {
  description = "Consumer-supplied extra LXD profiles appended after the substrate baseline for control-plane LXC instances."
  type        = list(string)
  default     = []
}

variable "worker_profiles_extra" {
  description = "Consumer-supplied extra LXD profiles for worker LXC instances."
  type        = list(string)
  default     = []
}

variable "controlplane_devices_extra" {
  description = "CAPN v1alpha2 CSV device overrides for CP machines. Each entry: \"<name>,type=<t>,...\""
  type        = list(string)
  default     = []
}

variable "worker_devices_extra" {
  description = "CAPN v1alpha2 CSV device overrides for worker machines."
  type        = list(string)
  default     = []
}

variable "control_plane_tuning" {
  description = "kubeadm tuning for KubeadmControlPlaneTemplate (feature_gates, *ExtraArgs, pre/postKubeadmCommands). Substrate-reserved args are rejected by chart-side schema."
  type = object({
    feature_gates                 = optional(map(bool), {})
    api_server_extra_args         = optional(list(object({ name = string, value = string })), [])
    controller_manager_extra_args = optional(list(object({ name = string, value = string })), [])
    scheduler_extra_args          = optional(list(object({ name = string, value = string })), [])
    kubelet_extra_args            = optional(list(object({ name = string, value = string })), [])
    pre_kubeadm_commands          = optional(list(string), [])
    post_kubeadm_commands         = optional(list(string), [])
  })
  default = {}
}

variable "worker_tuning" {
  description = "kubeadm tuning for KubeadmConfigTemplate (worker join side)."
  type = object({
    feature_gates         = optional(map(bool), {})
    kubelet_extra_args    = optional(list(object({ name = string, value = string })), [])
    pre_kubeadm_commands  = optional(list(string), [])
    post_kubeadm_commands = optional(list(string), [])
  })
  default = {}
}

variable "kube_proxy_node_port_addresses" {
  description = "kube-proxy NodePort bind CIDRs. Empty = bind all (kubeadm default)."
  type        = list(string)
  default     = []
}

# ----------------------------------------------------------------------------
# Add-ons chart versions
# ----------------------------------------------------------------------------

variable "cni_calico_chart_version" {
  description = "helm_release.version for charts/cni-calico (local wrapper around projectcalico/tigera-operator)."
  type        = string
}

variable "metallb_chart_version" {
  description = "helm_release.version for charts/metallb (subchart wrapper). Distinct from §8 k8s_lab_metallb_chart_version which pins the upstream subchart inside Chart.yaml dependencies."
  type        = string
}

variable "metallb_config_chart_version" {
  description = "helm_release.version for charts/metallb-config (IPAddressPool + L2Advertisement + Gate A test)."
  type        = string
}

# ----------------------------------------------------------------------------
# MetalLB pool / advertisement
# ----------------------------------------------------------------------------

variable "metallb_vip_range_v6" {
  description = "IPv6 VIP range for MetalLB (\"<from>-<to>\" or \"<ip>/128\"). §8 k8s_lab_metallb_vip_range_v6."
  type        = string
}

variable "metallb_interface" {
  description = "Interface name MetalLB speaker announces VIPs on. §8 k8s_lab_metallb_interface."
  type        = string
  default     = "eth1"
}

variable "metallb_extra_node_selectors" {
  description = "Extra label matchers stacked on top of the substrate-required CP-exclusion in L2Advertisement.nodeSelectors."
  type        = map(string)
  default     = {}
}

# ----------------------------------------------------------------------------
# Workload kubeconfig endpoint rewrite
# ----------------------------------------------------------------------------

variable "lxd_host_address" {
  description = "Runner-reachable LXD host address (e.g. Vagrant VM IP for local harness, public IP/DNS for prod). Used to rewrite the workload kubeconfig server URL away from the internal capi-int IPv6 endpoint towards the LXD proxy device on the haproxy LB instance. §8 k8s_lab_lxd_host_address."
  type        = string

  validation {
    condition     = length(var.lxd_host_address) > 0
    error_message = "lxd_host_address must be non-empty. For the local Vagrant flow it is derived from k8s_lab_mgmt_api_server_url in the fixture; ensure .artifacts/mgmt.auto.tfvars.json is present (Phase 4 export_artifacts must have run)."
  }
}

variable "helm_test_timeout" {
  description = "Timeout passed to `helm test` for cni-calico and metallb-config Gate B/A acceptance hooks."
  type        = string
  default     = "15m"
}
