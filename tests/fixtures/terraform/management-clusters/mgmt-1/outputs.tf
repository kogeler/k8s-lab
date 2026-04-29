output "cluster_name" {
  description = "Mgmt Cluster CR name."
  value       = module.mgmt_cluster.cluster_name
}

output "cluster_namespace" {
  description = "Namespace of the mgmt Cluster CR."
  value       = module.mgmt_cluster.cluster_namespace
}

output "cluster_class_name" {
  description = "Rendered ClusterClass metadata.name (capn-mgmt-<chart-version-slug>)."
  value       = module.mgmt_cluster.cluster_class_name
}

output "kubeconfig" {
  description = "Mgmt-1 kubeconfig content (rewritten + tls-server-name pinned). Sensitive."
  value       = module.mgmt_cluster.kubeconfig
  sensitive   = true
}

output "api_proxy_port" {
  description = "Per-cluster LXD-host listener port reaching the mgmt-1 kube-apiserver."
  value       = module.mgmt_cluster.api_proxy_port
}

output "lxd_host_address" {
  description = "Resolved LXD host address (derived from k8s_lab_bootstrap_api_server_url)."
  value       = local.lxd_host_address
}

output "metallb_vip_range_v6" {
  description = "Echo of the mgmt-isolated MetalLB IPv6 VIP range."
  value       = module.mgmt_cluster.metallb_vip_range_v6
}

output "helm_releases" {
  description = "Map of helm_release identifiers + versions for smoke-checks."
  value       = module.mgmt_cluster.helm_releases
}
