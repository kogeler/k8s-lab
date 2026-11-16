output "cluster" {
  description = "`name`, `namespace`, `pod_cidrs` of the Cluster, and `generation`: the Cluster's generation and its ClusterClass release's revision, which change with every change of the topology or a template."
  value = {
    name      = var.cluster_name
    namespace = var.namespace
    pod_cidrs = local.cluster.spec.clusterNetwork.pods.cidrBlocks
    generation = [
      local.cluster.metadata.generation,
      local.cluster.metadata.annotations["k8s-lab.io/class-revision"],
    ]
  }
}

output "api_server_url" {
  description = "The published API server."
  value       = local.server
}

output "kubeconfig" {
  description = "The admin kubeconfig of the cluster, pointed at the published API server."
  sensitive   = true
  value = yamlencode(merge(local.source, {
    clusters = [{
      name    = local.source.clusters[0].name
      cluster = merge(local.source.clusters[0].cluster, { server = local.server, "tls-server-name" = local.tls_server_name })
    }]
  }))
}

output "kubernetes" {
  description = "The same connection as an object for a provider's `kubernetes` block (`helm`)."
  sensitive   = true
  value = {
    host                   = local.server
    tls_server_name        = local.tls_server_name
    cluster_ca_certificate = base64decode(local.source.clusters[0].cluster["certificate-authority-data"])
    client_certificate     = base64decode(local.source.users[0].user["client-certificate-data"])
    client_key             = base64decode(local.source.users[0].user["client-key-data"])
  }
}
