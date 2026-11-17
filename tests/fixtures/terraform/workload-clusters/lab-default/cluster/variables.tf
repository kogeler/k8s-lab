# Values in terraform.tfvars; module input `cluster` documents them.

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
  description = "Namespace of the Cluster on the management cluster, one that holds the CAPN identity Secret; null = the handoff's `cluster_namespace`."
  type        = string
  default     = null
}

variable "name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "control_plane_count" {
  type = number
}

variable "worker_count" {
  type = number
}

variable "pod_cidrs" {
  type = list(string)
}

variable "service_cidrs" {
  type = list(string)
}

variable "cluster_class_values" {
  type    = any
  default = {}
}
