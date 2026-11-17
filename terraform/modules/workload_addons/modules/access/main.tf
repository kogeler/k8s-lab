# Reads, on the management cluster (the root's `kubernetes` provider), what an
# add-on root needs to reach a workload cluster: the published API port and the
# ClusterClass release's revision (annotations the Cluster chart writes), the
# Cluster's generation, and the admin kubeconfig Cluster API wrote. Data
# sources only: the root can configure its workload provider from them at plan
# time. (The provider cannot read the ClusterClass itself: it panics on the
# differently shaped entries of `spec.patches`.)

# The list form: for a missing object it returns an empty list, where the single
# form fails with "Provider produced null object".
data "kubernetes_resources" "cluster" {
  api_version    = "cluster.x-k8s.io/v1beta2"
  kind           = "Cluster"
  namespace      = var.namespace
  field_selector = "metadata.name=${var.cluster_name}"

  # Both annotations come from the Cluster chart as workload_cluster installs it.
  lifecycle {
    postcondition {
      condition     = can(tonumber(self.objects[0].metadata.annotations["k8s-lab.io/api-proxy-port"]))
      error_message = "Cluster ${var.namespace}/${var.cluster_name} is missing or has no published API port: apply its cluster root first."
    }
    postcondition {
      condition     = length(self.objects) == 0 || can(tonumber(self.objects[0].metadata.annotations["k8s-lab.io/class-revision"]))
      error_message = "Cluster ${var.namespace}/${var.cluster_name} has no class revision: apply its cluster root first."
    }
  }
}

data "kubernetes_secret_v1" "kubeconfig" {
  metadata {
    name      = "${var.cluster_name}-kubeconfig"
    namespace = var.namespace
  }

  lifecycle {
    postcondition {
      # Whether the key exists is no secret; `data` is null for a missing Secret.
      condition     = nonsensitive(contains(keys(coalesce(self.data, {})), "value"))
      error_message = "Cluster API has not written ${var.namespace}/${var.cluster_name}-kubeconfig yet: apply the cluster root first."
    }
  }
}

locals {
  cluster = data.kubernetes_resources.cluster.objects[0]
  server  = "https://${var.api_host}:${local.cluster.metadata.annotations["k8s-lab.io/api-proxy-port"]}"
  # A SAN of every API server certificate Cluster API issues, whatever address
  # the client dialled.
  tls_server_name = "kubernetes.default.svc"
  # The provider returns the Secret's data decoded and marks it sensitive.
  source = yamldecode(data.kubernetes_secret_v1.kubeconfig.data.value)
}
