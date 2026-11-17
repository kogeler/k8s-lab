variable "cluster" {
  description = "The workload Cluster as modules/access reads it: `name`, `namespace` (on the management cluster), `pod_cidrs` ([IPv4, IPv6]), and `generation`, whose every change re-runs the convergence check and the gates."
  type = object({
    name       = string
    namespace  = string
    pod_cidrs  = list(string)
    generation = any
  })
}

variable "kubeconfig" {
  description = "Admin kubeconfig of the workload cluster for the commands of the gates (modules/access)."
  type        = string
  sensitive   = true
}

variable "mgmt_kubeconfig_path" {
  description = "Kubeconfig of the management cluster, where the convergence check runs (the handoff's `mgmt_kubeconfig_path`)."
  type        = string
}

variable "metallb" {
  description = "Values of charts/metallb-config: `pool.rangeV6` (required) is the cluster's VIP range on the external network."
  type        = any

  # The pattern of the chart's schema, which Helm checks only when it installs
  # the release, after Calico, the convergence check, Gate B and MetalLB.
  validation {
    condition     = can(regex("^[0-9a-fA-F:]*:[0-9a-fA-F:]*-[0-9a-fA-F:]*:[0-9a-fA-F:]*$", var.metallb.pool.rangeV6))
    error_message = "metallb.pool.rangeV6 is required: an IPv6 range <first>-<last>, e.g. 2001:db8:42:100::300-2001:db8:42:100::3ff."
  }
}

variable "helm_test_timeout" {
  description = "Deadline of each `helm test` (the convergence check and the gates)."
  type        = string
  default     = "15m"

  # Helm parses it as a Go duration only when the first check runs.
  validation {
    condition     = can(regex("^([0-9]+(\\.[0-9]+)?(ns|us|ms|s|m|h))+$", var.helm_test_timeout))
    error_message = "helm_test_timeout is a duration: numbers with a unit (h, m, s, ms), e.g. 15m or 1h30m."
  }
}
