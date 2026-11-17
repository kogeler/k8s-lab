# The management side of a workload cluster: its ClusterClass and its Cluster,
# two Helm releases on the management cluster (the root's `helm` provider). The
# Cluster release's hook publishes the API server on the LXD host and returns
# once it answers. Add-ons and acceptance belong to workload_addons, applied
# from a second root.

locals {
  charts = "${path.module}/../../../charts"
}

resource "helm_release" "capi_cluster_class" {
  name      = "${var.cluster.name}-class"
  chart     = "${local.charts}/capi-cluster-class"
  version   = yamldecode(file("${local.charts}/capi-cluster-class/Chart.yaml")).version
  namespace = var.cluster.namespace
  atomic    = true

  # Helm merges the list in order, so the values the module owns win.
  values = [
    yamlencode(var.cluster_class_values),
    yamlencode({
      cluster         = { name = var.cluster.name }
      capn            = { infrastructureSecretName = var.cluster.infrastructure_secret_name }
      externalNetwork = { ipv6Prefix = var.cluster.external_ipv6_prefix }
    }),
  ]
}

# No `atomic`: rolling back a failed topology change would ask Cluster API for a
# Kubernetes downgrade.
resource "helm_release" "capi_workload_cluster" {
  name      = var.cluster.name
  chart     = "${local.charts}/capi-workload-cluster"
  version   = yamldecode(file("${local.charts}/capi-workload-cluster/Chart.yaml")).version
  namespace = var.cluster.namespace
  # A first install waits for the hook: machines, kubeconfig, published API.
  # Longer than the hook's own deadlines (45 min), so its message is the error.
  timeout = 3000

  # classRevision: a template change changes no field of the Cluster; the class
  # release's revision on the Cluster lets the add-on root see it.
  values = [yamlencode({
    cluster    = { name = var.cluster.name, classRevision = helm_release.capi_cluster_class.metadata.revision }
    kubernetes = { version = var.cluster.kubernetes_version }
    topology = {
      controlPlane = { replicas = var.cluster.control_plane_count }
      workers      = { replicas = var.cluster.worker_count }
    }
    clusterNetwork = {
      pods     = { cidrBlocks = var.cluster.pod_cidrs }
      services = { cidrBlocks = var.cluster.service_cidrs }
    }
    apiProxy = merge(var.api_proxy, { infrastructureSecretName = var.cluster.infrastructure_secret_name })
  })]
}
