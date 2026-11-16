# Root 2 of the workload cluster lab-default: its add-ons and acceptance gates
# (terraform/modules/workload_addons). The workload provider is configured at
# plan time from what the management cluster holds for the cluster
# (modules/access), so ../cluster is applied first and destroyed last.

locals {
  handoff              = jsondecode(file(coalesce(var.handoff_path, "${path.module}/../../../../../../.artifacts/handoff.json")))
  mgmt_kubeconfig_path = coalesce(var.mgmt_kubeconfig_path, local.handoff.mgmt_kubeconfig_path)
}

provider "kubernetes" {
  config_path = local.mgmt_kubeconfig_path
}

module "access" {
  source = "../../../../../../terraform/modules/workload_addons/modules/access"

  cluster_name = var.name
  namespace    = coalesce(var.namespace, local.handoff.cluster_namespace)
  api_host     = local.handoff.lxd_host_address
}

provider "helm" {
  kubernetes = module.access.kubernetes
}

module "workload_addons" {
  source = "../../../../../../terraform/modules/workload_addons"

  cluster              = module.access.cluster
  kubeconfig           = module.access.kubeconfig
  mgmt_kubeconfig_path = local.mgmt_kubeconfig_path
  metallb              = var.metallb
}
