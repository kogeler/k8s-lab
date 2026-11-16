output "kubeconfig" {
  description = "Admin kubeconfig of the cluster at its published API server: `terraform output -raw kubeconfig`."
  value       = module.access.kubeconfig
  sensitive   = true
}

output "api_server_url" {
  description = "The published API server."
  value       = module.access.api_server_url
}
