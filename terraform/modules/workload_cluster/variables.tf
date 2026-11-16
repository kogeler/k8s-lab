variable "cluster" {
  description = "The workload cluster. `namespace` holds the CAPN identity Secret `infrastructure_secret_name`; `external_ipv6_prefix` is the external network of the nodes' eth1, where NodePorts answer (all three from the management side's handoff); CIDRs are [IPv4, IPv6]."
  type = object({
    name                       = string
    namespace                  = string
    infrastructure_secret_name = string
    external_ipv6_prefix       = string
    kubernetes_version         = string
    control_plane_count        = number
    worker_count               = number
    pod_cidrs                  = list(string)
    service_cidrs              = list(string)
  })

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.cluster.kubernetes_version))
    error_message = "kubernetes_version is v<major>.<minor>.<patch>, e.g. v1.37.0."
  }
  validation {
    condition     = var.cluster.control_plane_count % 2 == 1
    error_message = "control_plane_count is odd (stacked etcd)."
  }
  validation {
    condition     = var.cluster.worker_count >= 2
    error_message = "worker_count is at least 2: the CNI gate spreads its servers over two workers."
  }
  validation {
    condition     = can(cidrhost(var.cluster.external_ipv6_prefix, 0)) && strcontains(var.cluster.external_ipv6_prefix, ":")
    error_message = "external_ipv6_prefix is an IPv6 prefix, e.g. 2001:db8:42:100::/64."
  }
  # `try` turns a missing entry into false: `&&` does not short-circuit before
  # Terraform 1.12.
  validation {
    condition = alltrue([for c in [var.cluster.pod_cidrs, var.cluster.service_cidrs] : try(
      length(c) == 2
      && can(cidrhost(c[0], 0)) && !strcontains(c[0], ":")
      && can(cidrhost(c[1], 0)) && strcontains(c[1], ":"),
    false)])
    error_message = "pod_cidrs and service_cidrs are [IPv4 CIDR, IPv6 CIDR], e.g. [\"10.244.0.0/16\", \"fd42:77:2::/56\"]."
  }
}

variable "api_proxy" {
  description = "Overrides of the API publication on the LXD host, as the values `apiProxy` of charts/capi-workload-cluster (e.g. `listenAddress`, `port`)."
  type        = any
  default     = {}
}

variable "cluster_class_values" {
  description = "Overrides of the values of charts/capi-cluster-class (images, profiles, devices, kubeadm arguments and commands of control plane, workers and load balancer). A change renames the templates it touches, and the machines roll; CAPN never replaces an existing load balancer, so load-balancer values reach only a new cluster."
  type        = any
  default     = {}
}
