# Values in terraform.tfvars.

variable "handoff_path" {
  description = "The management side's handoff file; null = .artifacts/handoff.json at the repository root."
  type        = string
  default     = null
}

variable "mgmt_kubeconfig_path" {
  description = "Kubeconfig of the management cluster on this machine; null = the handoff's `mgmt_kubeconfig_path`, a path on the machine that ran Ansible."
  type        = string
  default     = null
}

variable "namespace" {
  description = "Namespace of the Cluster on the management cluster, as in ../cluster; null = the handoff's `cluster_namespace`."
  type        = string
  default     = null
}

variable "name" {
  description = "The cluster's name, as in ../cluster."
  type        = string
}

variable "metallb" {
  description = "Values of charts/metallb-config (module input `metallb`)."
  type        = any
}
