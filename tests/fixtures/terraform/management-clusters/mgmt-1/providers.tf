# Fixture-side `required_providers` only — no `provider "..."` blocks.
# The workload_cluster module owns mgmt + workload helm/kubernetes
# provider configurations internally (PLAN §16.4 / §16.5).

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
