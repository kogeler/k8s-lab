# Plan-mode tests with a mocked management cluster.

mock_provider "kubernetes" {
  mock_data "kubernetes_resources" {
    defaults = {
      objects = [{
        metadata = { generation = 3, annotations = { "k8s-lab.io/api-proxy-port" = "24242", "k8s-lab.io/class-revision" = "7" } }
        spec     = { clusterNetwork = { pods = { cidrBlocks = ["10.244.0.0/16", "fd42:77:2::/56"] } } }
      }]
    }
  }

  mock_data "kubernetes_secret_v1" {
    defaults = {
      data = {
        value = <<-EOT
          apiVersion: v1
          kind: Config
          clusters:
            - name: k8s-lab-test
              cluster:
                server: https://[fd42:77:1::10]:6443
                certificate-authority-data: Q0E=
          users:
            - name: k8s-lab-test-admin
              user:
                client-certificate-data: Q0VSVA==
                client-key-data: S0VZ
          contexts:
            - name: k8s-lab-test-admin@k8s-lab-test
              context: {cluster: k8s-lab-test, user: k8s-lab-test-admin}
          current-context: k8s-lab-test-admin@k8s-lab-test
        EOT
      }
    }
  }
}

variables {
  cluster_name = "k8s-lab-test"
  namespace    = "capi-clusters"
  api_host     = "192.0.2.10"
}

run "rewrites_the_kubeconfig_to_the_published_api" {
  command = plan

  assert {
    condition     = output.api_server_url == "https://192.0.2.10:24242"
    error_message = "the server is the LXD host and the annotated port"
  }
  assert {
    condition = nonsensitive(yamldecode(output.kubeconfig).clusters[0].cluster) == {
      server                     = "https://192.0.2.10:24242"
      tls-server-name            = "kubernetes.default.svc"
      certificate-authority-data = "Q0E="
    }
    error_message = "only server and tls-server-name change"
  }
  assert {
    condition     = nonsensitive(yamldecode(output.kubeconfig)["current-context"]) == "k8s-lab-test-admin@k8s-lab-test"
    error_message = "users and contexts stay as Cluster API wrote them"
  }
  assert {
    condition = nonsensitive(output.kubernetes) == {
      host                   = "https://192.0.2.10:24242"
      tls_server_name        = "kubernetes.default.svc"
      cluster_ca_certificate = "CA"
      client_certificate     = "CERT"
      client_key             = "KEY"
    }
    error_message = "the provider connection carries the decoded credentials"
  }
  assert {
    condition     = output.cluster.generation == [3, "7"] && output.cluster.pod_cidrs == ["10.244.0.0/16", "fd42:77:2::/56"]
    error_message = "generation is [Cluster generation, class release revision]; pod CIDRs come from the Cluster"
  }
}

run "refuses_a_cluster_without_a_class_revision" {
  command = plan

  override_data {
    target = data.kubernetes_resources.cluster
    values = { objects = [{ metadata = { generation = 1, annotations = { "k8s-lab.io/api-proxy-port" = "24242" } }, spec = { clusterNetwork = { pods = { cidrBlocks = [] } } } }] }
  }

  expect_failures = [data.kubernetes_resources.cluster]
}

run "refuses_a_missing_cluster" {
  command = plan

  override_data {
    target = data.kubernetes_resources.cluster
    values = { objects = [] }
  }

  expect_failures = [data.kubernetes_resources.cluster]
}

run "refuses_a_cluster_without_a_published_port" {
  command = plan

  override_data {
    target = data.kubernetes_resources.cluster
    values = { objects = [{ metadata = { generation = 1, annotations = {} }, spec = { clusterNetwork = { pods = { cidrBlocks = [] } } } }] }
  }

  expect_failures = [data.kubernetes_resources.cluster]
}

run "refuses_a_cluster_without_a_kubeconfig" {
  command = plan

  override_data {
    target = data.kubernetes_secret_v1.kubeconfig
    values = { data = null }
  }

  expect_failures = [data.kubernetes_secret_v1.kubeconfig]
}
