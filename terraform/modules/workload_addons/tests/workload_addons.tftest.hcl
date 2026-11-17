# Plan-mode tests with a mocked Helm provider: what the module hands the charts,
# what re-runs each check, and which inputs it refuses.

mock_provider "helm" {}

variables {
  cluster = {
    name       = "k8s-lab-test"
    namespace  = "capi-clusters"
    pod_cidrs  = ["10.244.0.0/16", "fd42:77:2::/56"]
    generation = [1, 1]
  }
  kubeconfig           = "apiVersion: v1\nkind: Config\n"
  mgmt_kubeconfig_path = "/nonexistent/mgmt.kubeconfig"
  metallb              = { pool = { rangeV6 = "2001:db8:42:100::300-2001:db8:42:100::3ff" } }
}

run "hands_the_charts_their_values" {
  command = plan

  assert {
    condition = alltrue([for r in [helm_release.cni_calico, helm_release.cni_calico_config, helm_release.metallb, helm_release.metallb_config] :
    r.version == yamldecode(file("${path.module}/../../../charts/${r.name}/Chart.yaml")).version])
    error_message = "chart versions come from Chart.yaml"
  }
  assert {
    condition     = yamldecode(helm_release.cni_calico_config.values[0]) == { calico = { pods = { cidrBlocks = ["10.244.0.0/16", "fd42:77:2::/56"] } } }
    error_message = "Calico's pools are the Cluster's pod CIDRs"
  }
  assert {
    condition     = yamldecode(helm_release.metallb_config.values[0]) == var.metallb
    error_message = "metallb is the values of charts/metallb-config"
  }
}

# A distinct revision per release and a distinct generation, so each trigger
# shows exactly what it follows.
run "re_runs_each_check_on_its_own_triggers" {
  command = plan

  override_resource {
    target          = helm_release.cni_calico
    override_during = plan
    values          = { metadata = { revision = 2 } }
  }
  override_resource {
    target          = helm_release.cni_calico_config
    override_during = plan
    values          = { metadata = { revision = 3 } }
  }
  override_resource {
    target          = helm_release.metallb
    override_during = plan
    values          = { metadata = { revision = 5 } }
  }
  override_resource {
    target          = helm_release.metallb_config
    override_during = plan
    values          = { metadata = { revision = 7 } }
  }

  variables {
    cluster = merge(var.cluster, { generation = [11, "13"] })
  }

  assert {
    condition     = terraform_data.calico_crds.triggers_replace == 2 && terraform_data.metallb_webhook.triggers_replace == 5
    error_message = "the CRD and webhook waits follow their own release only"
  }
  assert {
    condition     = terraform_data.cluster_converged.triggers_replace == [11, "13"]
    error_message = "the convergence check follows the Cluster's generation and class revision only"
  }
  assert {
    condition     = terraform_data.gate_cni.triggers_replace == [2, 3, [11, "13"]]
    error_message = "Gate B follows both Calico releases and the Cluster"
  }
  assert {
    condition     = terraform_data.gate_metallb.triggers_replace == [5, 7, [11, "13"]]
    error_message = "Gate A follows both MetalLB releases and the Cluster"
  }
}

run "refuses_metallb_without_a_range" {
  command = plan
  variables {
    metallb = { l2 = { interface = "eth1" } }
  }
  expect_failures = [var.metallb]
}

run "refuses_a_range_that_is_not_first_last" {
  command = plan
  variables {
    metallb = { pool = { rangeV6 = "2001:db8:42:100::/120" } }
  }
  expect_failures = [var.metallb]
}

run "refuses_a_timeout_without_a_unit" {
  command = plan
  variables {
    helm_test_timeout = "900"
  }
  expect_failures = [var.helm_test_timeout]
}
