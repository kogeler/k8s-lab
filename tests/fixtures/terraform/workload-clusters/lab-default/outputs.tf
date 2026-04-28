output "cluster_name" {
  description = "Workload Cluster CR name."
  value       = module.workload_cluster.cluster_name
}

output "cluster_namespace" {
  description = "Namespace of the workload Cluster CR."
  value       = module.workload_cluster.cluster_namespace
}

output "cluster_class_name" {
  description = "Rendered ClusterClass metadata.name."
  value       = module.workload_cluster.cluster_class_name
}

output "kubeconfig" {
  description = "Workload kubeconfig content (rewritten + tls-server-name pinned). Sensitive — `terraform output -raw kubeconfig > path` to materialise."
  value       = module.workload_cluster.kubeconfig
  sensitive   = true
}

output "api_proxy_port" {
  description = "Per-cluster LXD-host listener port to reach the workload kube-apiserver."
  value       = module.workload_cluster.api_proxy_port
}

output "lxd_host_address" {
  description = "Resolved LXD host address (derived from k8s_lab_bootstrap_api_server_url)."
  value       = local.lxd_host_address
}

output "metallb_vip_range_v6" {
  description = "Echo of the MetalLB IPv6 VIP range."
  value       = module.workload_cluster.metallb_vip_range_v6
}

output "helm_releases" {
  description = "Map of helm_release identifiers + versions for smoke-checks."
  value       = module.workload_cluster.helm_releases
}
