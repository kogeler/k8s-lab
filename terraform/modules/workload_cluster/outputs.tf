output "cluster_name" {
  description = "Workload Cluster CR name."
  value       = var.cluster_name
}

output "cluster_namespace" {
  description = "Namespace of the workload Cluster CR."
  value       = var.cluster_namespace
}

output "cluster_class_name" {
  description = "Rendered ClusterClass metadata.name (slug-formula reproduced from class_prefix + chart version)."
  value       = local.cluster_class_full_name
}

output "kubeconfig" {
  description = "Workload kubeconfig content (YAML string) with the server URL rewritten to <lxd_host_address>:<api_proxy_port> + tls-server-name pinned. Sensitive — module never writes it to disk."
  value       = local.workload_kubeconfig_rewritten
  sensitive   = true
}

output "api_proxy_port" {
  description = "Per-cluster Adler-32-derived API proxy port (chart-side computation), echoed from the Cluster CR's k8s-lab.io/api-proxy-port annotation."
  value       = local.api_proxy_port
}

output "metallb_vip_range_v6" {
  description = "Echo of the MetalLB IPv6 VIP range (passthrough)."
  value       = var.metallb_vip_range_v6
}

output "helm_releases" {
  description = "Map of helm_release identifiers + versions for smoke-checks."
  value = {
    capi_cluster_class = {
      id      = helm_release.capi_cluster_class.id
      name    = helm_release.capi_cluster_class.name
      ns      = helm_release.capi_cluster_class.namespace
      version = helm_release.capi_cluster_class.version
    }
    capi_workload_cluster = {
      id      = helm_release.capi_workload_cluster.id
      name    = helm_release.capi_workload_cluster.name
      ns      = helm_release.capi_workload_cluster.namespace
      version = helm_release.capi_workload_cluster.version
    }
    cni_calico = {
      id      = helm_release.cni_calico.id
      name    = helm_release.cni_calico.name
      ns      = helm_release.cni_calico.namespace
      version = helm_release.cni_calico.version
    }
    metallb = {
      id      = helm_release.metallb.id
      name    = helm_release.metallb.name
      ns      = helm_release.metallb.namespace
      version = helm_release.metallb.version
    }
    metallb_config = {
      id      = helm_release.metallb_config.id
      name    = helm_release.metallb_config.name
      ns      = helm_release.metallb_config.namespace
      version = helm_release.metallb_config.version
    }
  }
}
