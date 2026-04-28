# Module-owned provider configurations (PLAN §16.4 / §16.5):
#   * mgmt-aliased helm + kubernetes — point at the management cluster
#     via the kubeconfig file at var.mgmt_kubeconfig_path;
#   * workload-aliased helm — configured inline from the parsed +
#     rewritten workload kubeconfig (see locals.tf), no filesystem write.
#
# The fixture root MUST NOT redeclare these providers; if a future
# consumer needs cross-module helm.workload sharing it should be done
# via configuration_aliases + an explicit `providers = {...}` map.

provider "kubernetes" {
  alias       = "mgmt"
  config_path = var.mgmt_kubeconfig_path
}

provider "helm" {
  alias = "mgmt"
  kubernetes = {
    config_path = var.mgmt_kubeconfig_path
  }
}

provider "helm" {
  alias = "workload"
  # Inline credentials parsed from the workload kubeconfig Secret +
  # rewritten endpoint (locals.tf). When the upstream Secret is not yet
  # materialised (first plan/refresh before the wait null_resource has
  # ever run), the data source short-circuits to an empty object and
  # these fields evaluate to null — Terraform tolerates that until any
  # workload-scoped resource is actually instantiated.
  kubernetes = {
    host                   = try(local.workload_helm_kubernetes.host, null)
    cluster_ca_certificate = try(local.workload_helm_kubernetes.cluster_ca_certificate, null)
    client_certificate     = try(local.workload_helm_kubernetes.client_certificate, null)
    client_key             = try(local.workload_helm_kubernetes.client_key, null)
    tls_server_name        = try(local.workload_helm_kubernetes.tls_server_name, null)
  }
}
