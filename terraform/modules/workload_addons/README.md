# workload_addons

The workload side of one workload cluster: Calico and MetalLB, and their
acceptance. In order:

1. the Calico operator (`charts/cni-calico`), a wait for its CRDs, the Calico
   configuration (`charts/cni-calico-config`);
2. on the management cluster, the Cluster chart's `helm test`: Cluster API has
   converged (topology applied, nothing rolling out or scaling, Available);
3. Gate B: `helm test cni-calico-config`;
4. MetalLB (`charts/metallb`), a wait until its webhook answers, the MetalLB
   configuration (`charts/metallb-config`);
5. Gate A: `helm test metallb-config`.

The checks run again when their releases change (Helm revision) and when the
Cluster or its ClusterClass release changes (the Cluster's generation and its
`k8s-lab.io/class-revision` annotation). An apply after a change of
the cluster root therefore waits for the rollout and accepts the result.

The root configures `helm` for the workload cluster from
[modules/access](modules/access), which reads the connection on the
management cluster at plan time. The commands need `bash`, `kubectl` and
`helm` on the runner.

Used by `tests/fixtures/terraform/workload-clusters/lab-default/addons`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.3 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 3.3 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.cni_calico](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.cni_calico_config](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.metallb](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.metallb_config](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [terraform_data.calico_crds](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.cluster_converged](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.gate_cni](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.gate_metallb](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.metallb_webhook](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster"></a> [cluster](#input\_cluster) | The workload Cluster as modules/access reads it: `name`, `namespace` (on the management cluster), `pod_cidrs` ([IPv4, IPv6]), and `generation`, whose every change re-runs the convergence check and the gates. | <pre>object({<br/>    name       = string<br/>    namespace  = string<br/>    pod_cidrs  = list(string)<br/>    generation = any<br/>  })</pre> | n/a | yes |
| <a name="input_helm_test_timeout"></a> [helm\_test\_timeout](#input\_helm\_test\_timeout) | Deadline of each `helm test` (the convergence check and the gates). | `string` | `"15m"` | no |
| <a name="input_kubeconfig"></a> [kubeconfig](#input\_kubeconfig) | Admin kubeconfig of the workload cluster for the commands of the gates (modules/access). | `string` | n/a | yes |
| <a name="input_metallb"></a> [metallb](#input\_metallb) | Values of charts/metallb-config: `pool.rangeV6` (required) is the cluster's VIP range on the external network. | `any` | n/a | yes |
| <a name="input_mgmt_kubeconfig_path"></a> [mgmt\_kubeconfig\_path](#input\_mgmt\_kubeconfig\_path) | Kubeconfig of the management cluster, where the convergence check runs (the handoff's `mgmt_kubeconfig_path`). | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
