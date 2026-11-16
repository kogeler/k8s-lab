# Plan-mode tests with a mocked Helm provider: what the module hands the charts,
# and which inputs it refuses.

mock_provider "helm" {}

variables {
  cluster = {
    name                       = "k8s-lab-test"
    namespace                  = "capi-clusters"
    infrastructure_secret_name = "incus-identity"
    external_ipv6_prefix       = "2001:db8:42:100::/64"
    kubernetes_version         = "v1.37.0"
    control_plane_count        = 3
    worker_count               = 2
    pod_cidrs                  = ["10.244.0.0/16", "fd42:77:2::/56"]
    service_cidrs              = ["10.96.0.0/16", "fd42:77:3::/112"]
  }
}

run "hands_the_charts_their_values" {
  command = plan

  override_resource {
    target          = helm_release.capi_cluster_class
    override_during = plan
    values          = { metadata = { revision = 4 } }
  }
  # Makes the computed attributes the configuration leaves unset known at plan
  # time (`atomic` among them).
  override_resource {
    target          = helm_release.capi_workload_cluster
    override_during = plan
    values          = {}
  }

  variables {
    cluster_class_values = { cluster = { name = "ignored" }, worker = { flavor = "c2-m4" } }
    api_proxy            = { port = 24000, infrastructureSecretName = "ignored" }
  }

  assert {
    condition     = helm_release.capi_cluster_class.name == "k8s-lab-test-class" && helm_release.capi_workload_cluster.name == "k8s-lab-test"
    error_message = "releases are named after the cluster"
  }
  assert {
    # Rolling back a failed topology change would ask for a Kubernetes downgrade.
    condition     = helm_release.capi_cluster_class.atomic == true && helm_release.capi_workload_cluster.atomic != true
    error_message = "the class release is atomic, the Cluster release is not"
  }
  assert {
    condition = (helm_release.capi_cluster_class.version == yamldecode(file("${path.module}/../../../charts/capi-cluster-class/Chart.yaml")).version
    && helm_release.capi_workload_cluster.version == yamldecode(file("${path.module}/../../../charts/capi-workload-cluster/Chart.yaml")).version)
    error_message = "chart versions come from Chart.yaml"
  }
  assert {
    # Helm merges in order: the overrides first, the module's own values last.
    condition = (yamldecode(helm_release.capi_cluster_class.values[0]).worker.flavor == "c2-m4"
      && yamldecode(helm_release.capi_cluster_class.values[1]) == {
        cluster         = { name = "k8s-lab-test" }
        capn            = { infrastructureSecretName = "incus-identity" }
        externalNetwork = { ipv6Prefix = "2001:db8:42:100::/64" }
    })
    error_message = "class overrides come first, the cluster's name, identity and external network last"
  }
  assert {
    condition = yamldecode(helm_release.capi_workload_cluster.values[0]) == {
      cluster        = { name = "k8s-lab-test", classRevision = 4 }
      kubernetes     = { version = "v1.37.0" }
      topology       = { controlPlane = { replicas = 3 }, workers = { replicas = 2 } }
      clusterNetwork = { pods = { cidrBlocks = ["10.244.0.0/16", "fd42:77:2::/56"] }, services = { cidrBlocks = ["10.96.0.0/16", "fd42:77:3::/112"] } }
      apiProxy       = { port = 24000, infrastructureSecretName = "incus-identity" }
    }
    error_message = "the Cluster chart gets the cluster's values, the class release's revision and the API overrides, with the cluster's own identity Secret"
  }
}

run "refuses_an_even_control_plane" {
  command = plan
  variables {
    cluster = merge(var.cluster, { control_plane_count = 2 })
  }
  expect_failures = [var.cluster]
}

run "refuses_a_single_worker" {
  command = plan
  variables {
    cluster = merge(var.cluster, { worker_count = 1 })
  }
  expect_failures = [var.cluster]
}

run "refuses_single_stack_cidrs" {
  command = plan
  variables {
    cluster = merge(var.cluster, { service_cidrs = ["10.96.0.0/16"] })
  }
  expect_failures = [var.cluster]
}

run "refuses_a_malformed_cidr" {
  command = plan
  variables {
    cluster = merge(var.cluster, { pod_cidrs = ["300.0.0.0/8", "fd42:77:2::/56"] })
  }
  expect_failures = [var.cluster]
}

run "refuses_a_version_without_a_patch" {
  command = plan
  variables {
    cluster = merge(var.cluster, { kubernetes_version = "v1.37" })
  }
  expect_failures = [var.cluster]
}

run "refuses_an_ipv4_external_prefix" {
  command = plan
  variables {
    cluster = merge(var.cluster, { external_ipv6_prefix = "192.0.2.0/24" })
  }
  expect_failures = [var.cluster]
}
