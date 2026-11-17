# workload_cluster

The management side of one workload cluster: its ClusterClass and its Cluster,
two Helm releases of `charts/capi-cluster-class` and
`charts/capi-workload-cluster` on the management cluster.

- A first apply returns once the cluster's API server is published on the LXD
  host and answers.
- A later change (machine counts, the Kubernetes version, a template value)
  returns once Cluster API has accepted it. The apply of the add-on root
  ([workload_addons](../workload_addons)) then waits for the rollout and runs
  the gates.

The module declares no provider: the root configures `helm` for the management
cluster. The add-ons live in a second root, so a change here never leaves a
workload provider unconfigured at plan time.

Used by `tests/fixtures/terraform/workload-clusters/lab-default/cluster`.

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

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.capi_cluster_class](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.capi_workload_cluster](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_proxy"></a> [api\_proxy](#input\_api\_proxy) | Overrides of the API publication on the LXD host, as the values `apiProxy` of charts/capi-workload-cluster (e.g. `listenAddress`, `port`). | `any` | `{}` | no |
| <a name="input_cluster"></a> [cluster](#input\_cluster) | The workload cluster. `namespace` holds the CAPN identity Secret `infrastructure_secret_name`; `external_ipv6_prefix` is the external network of the nodes' eth1, where NodePorts answer (all three from the management side's handoff); CIDRs are [IPv4, IPv6]. | <pre>object({<br/>    name                       = string<br/>    namespace                  = string<br/>    infrastructure_secret_name = string<br/>    external_ipv6_prefix       = string<br/>    kubernetes_version         = string<br/>    control_plane_count        = number<br/>    worker_count               = number<br/>    pod_cidrs                  = list(string)<br/>    service_cidrs              = list(string)<br/>  })</pre> | n/a | yes |
| <a name="input_cluster_class_values"></a> [cluster\_class\_values](#input\_cluster\_class\_values) | Overrides of the values of charts/capi-cluster-class (images, profiles, devices, kubeadm arguments and commands of control plane, workers and load balancer). A change renames the templates it touches, and the machines roll; CAPN never replaces an existing load balancer, so load-balancer values reach only a new cluster. | `any` | `{}` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
