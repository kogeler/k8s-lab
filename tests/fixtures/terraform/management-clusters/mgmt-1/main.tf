locals {
  # `.artifacts/bootstrap.kubeconfig` lives at the repo root. Five
  # ".." steps from this fixture climb back up to the repo root:
  # mgmt-1 → management-clusters → terraform → fixtures → tests → repo.
  default_mgmt_kubeconfig_path = "${path.module}/../../../../../.artifacts/bootstrap.kubeconfig"

  mgmt_kubeconfig_path = var.mgmt_kubeconfig_path != "" ? var.mgmt_kubeconfig_path : (
    var.k8s_lab_bootstrap_kubeconfig_path != "" ? var.k8s_lab_bootstrap_kubeconfig_path : local.default_mgmt_kubeconfig_path
  )

  # lxd_host_address derivation matches the workload-clusters/lab-default/
  # fixture: pull the host portion out of `k8s_lab_bootstrap_api_server_url`
  # so the operator never hand-pins it for the local Vagrant flow.
  _lxd_addr_match = var.k8s_lab_bootstrap_api_server_url != "" ? regex(
    "^https?://(?:\\[([^\\]]+)\\]|([^:/]+))",
    var.k8s_lab_bootstrap_api_server_url
  ) : [null, null]

  lxd_host_address = try(
    coalesce(local._lxd_addr_match[0], local._lxd_addr_match[1]),
    ""
  )
}

# PLAN §18 — Phase 6 mgmt cluster.
#
# Reuses the same generic workload_cluster module that
# tests/fixtures/terraform/workload-clusters/lab-default/ uses; the only
# differences are:
#
#   * cluster_name = "mgmt-1" — distinct Cluster CR + helm releases.
#   * controlplane_count / worker_count = 1 / 1 — single-node CP +
#     worker is sufficient for self-hosting CAPI controllers (no HA
#     contract on Stage 1 mgmt — see PLAN §2.12 last bullet "mgmt
#     cluster — HA NOT applied automatically").
#   * class_prefix = "capn-mgmt" — keeps the rendered ClusterClass
#     metadata.name distinct from the workload fixture's
#     `capn-default-<slug>` so both can co-exist in the same namespace
#     during the pre-pivot window (operator may have a workload up
#     when running deploy-pivot; the workload still gets moved by
#     `clusterctl move` along with mgmt-1, but the fixture itself
#     does not require absence of workloads).
#   * metallb_vip_range_v6 = `<host_prefix>::300-::3ff` — disjoint
#     from workload's `::200-::2ff`. MetalLB is NOT semantically
#     needed on mgmt (CAPI controllers do not expose external
#     LoadBalancer Services) but the workload_cluster module installs
#     it unconditionally; isolating the VIP range avoids speaker
#     announcement collisions if mgmt + workload happen to coexist.
#
# After `terraform apply` returns, mgmt-1 is a fully reconciled CAPI
# cluster with CNI green and MetalLB available — i.e. a clean
# substrate the pivot_clusterctl_move role can `clusterctl init`
# against. The role itself runs from the Ansible playbook
# `tests/fixtures/ansible/pivot.yml` (driven by `make deploy-pivot`).
module "mgmt_cluster" {
  source = "../../../../../terraform/modules/workload_cluster"

  mgmt_kubeconfig_path = local.mgmt_kubeconfig_path
  lxd_host_address     = local.lxd_host_address

  cluster_name       = var.k8s_lab_management_cluster_name
  cluster_namespace  = "capi-clusters"
  kubernetes_version = var.k8s_lab_kubernetes_version
  controlplane_count = var.k8s_lab_management_controlplane_count
  worker_count       = var.k8s_lab_management_worker_count

  class_prefix = "capn-mgmt"

  cluster_class_chart_version    = var.cluster_class_chart_version
  cluster_workload_chart_version = var.cluster_workload_chart_version
  cni_calico_chart_version       = var.cni_calico_chart_version
  metallb_chart_version          = var.metallb_chart_version
  metallb_config_chart_version   = var.metallb_config_chart_version

  # Re-use workload pod/service CIDR defaults — different Cluster CRs
  # have independent clusterNetwork blocks; overlap on the same wire
  # is moot because each cluster is its own kube-proxy / CNI domain.
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

  metallb_vip_range_v6 = var.k8s_lab_management_metallb_vip_range_v6
  metallb_interface    = var.k8s_lab_metallb_interface
}
