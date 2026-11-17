# access

Data sources only, on the management cluster (the root's `kubernetes`
provider). Reads what a root needs to reach a workload cluster:

- the port of its published API server, from the Cluster's
  `k8s-lab.io/api-proxy-port` annotation;
- the admin kubeconfig Cluster API wrote, pointed at that server;
- the Cluster's generation and the revision of its ClusterClass release (the
  Cluster's `k8s-lab.io/class-revision` annotation), which
  [workload_addons](../..) uses to re-run its checks. The provider cannot read
  the ClusterClass itself: it panics on the differently shaped entries of
  `spec.patches`.

Because it reads at plan time, a root can configure its workload `helm`
provider from the outputs. The kubeconfig Secret is in that root's state, so
protect the state like the management kubeconfig.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_resources.cluster](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/data-sources/resources) | data source |
| [kubernetes_secret_v1.kubeconfig](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/data-sources/secret_v1) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_host"></a> [api\_host](#input\_api\_host) | Address the runner reaches the LXD host at (the handoff's `lxd_host_address`); the published API listens there. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the workload Cluster. | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace of the Cluster on the management cluster. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_server_url"></a> [api\_server\_url](#output\_api\_server\_url) | The published API server. |
| <a name="output_cluster"></a> [cluster](#output\_cluster) | `name`, `namespace`, `pod_cidrs` of the Cluster, and `generation`: the Cluster's generation and its ClusterClass release's revision, which change with every change of the topology or a template. |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | The admin kubeconfig of the cluster, pointed at the published API server. |
| <a name="output_kubernetes"></a> [kubernetes](#output\_kubernetes) | The same connection as an object for a provider's `kubernetes` block (`helm`). |
<!-- END_TF_DOCS -->
