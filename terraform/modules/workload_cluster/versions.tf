# Module-side provider configurations live in providers.tf; this file
# only declares the providers the module uses + Terraform core version.
# The fixture root must NOT define its own provider blocks for these
# (PLAN §16.4 / §16.5 — module owns mgmt + workload aliases).

terraform {
  required_version = ">= 1.9"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
