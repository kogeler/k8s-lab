locals {
  # `.artifacts/mgmt.kubeconfig` lives at the repo root. Five
  # ".." steps from this fixture climb back up to the repo root:
  # lab-default → workload-clusters → terraform → fixtures → tests → repo.
  default_mgmt_kubeconfig_path = "${path.module}/../../../../../.artifacts/mgmt.kubeconfig"

  mgmt_kubeconfig_path = var.mgmt_kubeconfig_path != "" ? var.mgmt_kubeconfig_path : (
    var.k8s_lab_mgmt_kubeconfig_path != "" ? var.k8s_lab_mgmt_kubeconfig_path : local.default_mgmt_kubeconfig_path
  )

  # lxd_host_address is not part of the export_artifacts payload.
  # Derive it from the mgmt server URL host component. The regex
  # exposes two capture groups — [bracketed-ipv6, plain-host]; only one
  # matches per URL, the other comes back null. `coalesce` returns the
  # populated one. Skipped when the URL itself is empty (e.g. a fresh
  # `terraform plan` without the Phase 4 handoff present yet) — the
  # downstream module-side validation surfaces the missing input with a
  # clear error.
  _lxd_addr_match = var.k8s_lab_mgmt_api_server_url != "" ? regex(
    "^https?://(?:\\[([^\\]]+)\\]|([^:/]+))",
    var.k8s_lab_mgmt_api_server_url
  ) : [null, null]

  lxd_host_address = try(
    coalesce(local._lxd_addr_match[0], local._lxd_addr_match[1]),
    ""
  )
}

module "workload_cluster" {
  source = "../../../../../terraform/modules/workload_cluster"

  mgmt_kubeconfig_path = local.mgmt_kubeconfig_path
  lxd_host_address     = local.lxd_host_address

  cluster_name       = var.k8s_lab_workload_cluster_name
  cluster_namespace  = "capi-clusters"
  kubernetes_version = var.k8s_lab_kubernetes_version
  controlplane_count = var.k8s_lab_workload_controlplane_count
  worker_count       = var.k8s_lab_workload_worker_count

  cluster_class_chart_version    = var.cluster_class_chart_version
  cluster_workload_chart_version = var.cluster_workload_chart_version
  cni_calico_chart_version       = var.cni_calico_chart_version
  metallb_chart_version          = var.metallb_chart_version
  metallb_config_chart_version   = var.metallb_config_chart_version

  pod_cidrs = [
    var.k8s_lab_workload_pod_cidr_v4,
    var.k8s_lab_workload_pod_cidr_v6,
  ]
  service_cidrs = [
    var.k8s_lab_workload_service_cidr_v4,
    var.k8s_lab_workload_service_cidr_v6,
  ]

  infrastructure_secret_name     = var.k8s_lab_infrastructure_secret_name
  image_controlplane_ref         = var.k8s_lab_images_controlplane
  image_controlplane_fingerprint = var.k8s_lab_images_controlplane_fingerprint
  image_worker_ref               = var.k8s_lab_images_worker
  image_worker_fingerprint       = var.k8s_lab_images_worker_fingerprint
  controlplane_profiles_extra    = var.k8s_lab_controlplane_profiles_extra
  worker_profiles_extra          = var.k8s_lab_worker_profiles_extra
  controlplane_devices_extra     = var.k8s_lab_controlplane_devices_extra
  worker_devices_extra           = var.k8s_lab_worker_devices_extra
  kube_proxy_node_port_addresses = var.k8s_lab_kube_proxy_nodeport_addresses

  metallb_vip_range_v6 = var.k8s_lab_metallb_vip_range_v6
  metallb_interface    = var.k8s_lab_metallb_interface
}
