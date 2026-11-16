# Root 1 of the workload cluster lab-default: its management side
# (terraform/modules/workload_cluster). Apply it before ../addons, destroy it
# after. The management side's facts come from its handoff file, the cluster's
# own values from terraform.tfvars.

locals {
  handoff = jsondecode(file(coalesce(var.handoff_path, "${path.module}/../../../../../../.artifacts/handoff.json")))
}

provider "helm" {
  kubernetes = {
    config_path = coalesce(var.mgmt_kubeconfig_path, local.handoff.mgmt_kubeconfig_path)
  }
}

module "workload_cluster" {
  source = "../../../../../../terraform/modules/workload_cluster"

  cluster = {
    name                       = var.name
    namespace                  = coalesce(var.namespace, local.handoff.cluster_namespace)
    infrastructure_secret_name = local.handoff.infrastructure_secret_name
    external_ipv6_prefix       = local.handoff.external_ipv6_prefix
    kubernetes_version         = var.kubernetes_version
    control_plane_count        = var.control_plane_count
    worker_count               = var.worker_count
    pod_cidrs                  = var.pod_cidrs
    service_cidrs              = var.service_cidrs
  }
  cluster_class_values = var.cluster_class_values
}
