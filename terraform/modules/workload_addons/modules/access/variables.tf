variable "cluster_name" {
  description = "Name of the workload Cluster."
  type        = string
}

variable "namespace" {
  description = "Namespace of the Cluster on the management cluster."
  type        = string
}

variable "api_host" {
  description = "Address the runner reaches the LXD host at (the handoff's `lxd_host_address`); the published API listens there."
  type        = string
}
