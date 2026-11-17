# Variable contract

What a deployment must supply for the Ansible roles to run, and where each value
goes. Written for the person or agent who prepares a real deployment's
playbooks.

## Two kinds of variable

- **Common variables** (`k8s_lab_*`) are values that two roles, or a role and
  Terraform, must agree on, plus the version pins. No role defines them. Every
  one of them is **required**; there is no fallback value anywhere.
- **Role inputs** (`<role>_*`) are defined in each role's `defaults/main.yml`.
  An input that mirrors a common variable defaults to it, so a deployment can
  still override one role's view. A few inputs have no sensible default and
  are required (below).

## How to supply them

Put every common variable and every required role input in
`group_vars/all.yml` **next to the playbook** (not in the inventory, which holds
hosts and connection data only). The reference is
[`tests/playbooks/group_vars/all.yml`](https://github.com/kogeler/k8s-lab/blob/main/tests/playbooks/group_vars/all.yml),
used by the test harness with the reference playbooks
[`tests/playbooks/substrate.yml`](https://github.com/kogeler/k8s-lab/blob/main/tests/playbooks/substrate.yml)
and
[`tests/playbooks/management.yml`](https://github.com/kogeler/k8s-lab/blob/main/tests/playbooks/management.yml).
Copy it and replace the values of its last two blocks: the four role inputs
without a default, which describe the test VM's disk, uplink and external
network, and the two harness-only values. A kept external prefix is not
caught by any gate: Gate A runs inside the cluster.

`make check` fails when a common variable is set in the reference file but no
role reads it, is read by a role but not set there, or is missing from this
page. For a role with `meta/argument_specs.yml` it also fails when the role
reads a common variable outside `defaults/main.yml` or does not declare it there
as required, when the declared inputs and `defaults/main.yml` disagree, when two
roles declare a common variable with a different type or description, and when
the tables below are stale.

Change a pin's version and its digest together: `make check` does not compare
them; the host's checksum-verified download does.

## Common variables

Rendered from the roles' `meta/argument_specs.yml`, their `defaults/main.yml`
and the reference file (`scripts/check_variable_contract.py --write`).
*harness*: the reference file derives the value from the test VM or the
checkout; a deployment sets its real value.

<!-- generated: common-variables -->
| Variable | Type | Reference value | Meaning | Role inputs that default to it |
|---|---|---|---|---|
| `k8s_lab_opt_root` | path | `/opt/capi-lab` | Host directory for pinned binaries (bin/) and role state (etc/). | `bootstrap_opt_root`, `capn_identity_dir`, `clusterctl_target_kubeconfig`, `clusterctl_opt_root`, `host_opt_root`, `management_cluster_opt_root` |
| `k8s_lab_project_name` | str | `capi-lab` | LXD project every cluster instance lives in. | `bootstrap_project`, `capn_identity_project`, `lxd_project_name`, `management_cluster_lxd_project` |
| `k8s_lab_management_cluster_name` | str | `mgmt-1` | Name of the management cluster. | `clusterctl_cluster_name`, `management_cluster_name` |
| `k8s_lab_bootstrap_instance_name` | str | `capi-bootstrap-0` | LXD instance of the bootstrap cluster. | `bootstrap_instance_name`, `management_cluster_bootstrap_instance` |
| `k8s_lab_cluster_namespace` | str | `capi-clusters` | Namespace of the Cluster API objects and the CAPN identity Secret. | `capn_identity_namespaces`, `clusterctl_cluster_namespace`, `management_cluster_namespace` |
| `k8s_lab_infrastructure_secret_name` | str | `incus-identity` | Name of the CAPN identity Secret. | `capn_identity_secret_name`, `management_cluster_infrastructure_secret_name` |
| `k8s_lab_api_listen_address` | str | `0.0.0.0` | IPv4 address of the host the published API servers listen on; restrict it on a host with a public address. | `bootstrap_api_listen_address`, `management_cluster_api_listen_address` |
| `k8s_lab_kubernetes_version` | str | `v1.37.0` | Kubernetes version of the management cluster; must have an image on the CAPN image server. | `management_cluster_kubernetes_version` |
| `k8s_lab_k3s_version` | str | `v1.37.2+k3s1` | k3s release of the bootstrap cluster, for example v1.37.2+k3s1. | `host_k3s_version` |
| `k8s_lab_k3s_sha256` | str | `265b3ee6…ddbda` | sha256 of the amd64 k3s binary of that release (row k3s of its sha256sum-amd64.txt). | `host_k3s_sha256` |
| `k8s_lab_kubectl_version` | str | `v1.37.2` | kubectl release, for example v1.37.2. | `host_kubectl_version` |
| `k8s_lab_kubectl_sha256` | str | `c0448752…5f8f4` | sha256 of the linux/amd64 kubectl binary of that release (its kubectl.sha256). | `host_kubectl_sha256` |
| `k8s_lab_clusterctl_version` | str | `v1.14.4` | Cluster API release of clusterctl and of the core and kubeadm providers. | `clusterctl_capi_version`, `host_clusterctl_version` |
| `k8s_lab_clusterctl_sha256` | str | `c7301a85…fa79b` | sha256 of clusterctl-linux-amd64 of that release (upstream publishes none: compute it with sha256sum). | `host_clusterctl_sha256` |
| `k8s_lab_capn_provider_version` | str | `v0.9.1` | Release of the CAPN infrastructure provider. | `clusterctl_capn_version` |
| `k8s_lab_lxd_host_address` | str | *harness* | The host as the runner reaches it (an IPv4 address or a name); the published API servers are on this address. | `bootstrap_api_host`, `management_cluster_api_host` |
| `k8s_lab_artifacts_dir` | path | *harness* | Runner directory of the kubeconfigs and handoff.json (0600 files). | `bootstrap_artifacts_dir`, `management_cluster_artifacts_dir` |
<!-- end generated -->

Terraform roots receive the management side's values through the handoff
file `handoff.json` in `k8s_lab_artifacts_dir` (written by `management_cluster`,
input `management_cluster_handoff_path`), read with `jsondecode(file())`:
`lxd_host_address`, `cluster_namespace`, `infrastructure_secret_name` (from the
common variables of the same meaning), `mgmt_kubeconfig_path` and
`external_ipv6_prefix` (from `management_cluster_external_ipv6_prefix`: the
external network is the host's, the same for every cluster). Workload cluster
values belong to each Terraform root.

## Published facts

Set by `management_cluster` with `tasks_from: state`, read by the roles that
come after it in the play. Never set them in `group_vars`.

| Fact | Meaning |
|---|---|
| `k8s_lab_management_state` | `absent` (first run), `bootstrapping` (the bootstrap instance exists) or `self_hosted` (`mgmt.kubeconfig` reaches a cluster that holds its own `Cluster` object). Nodes of the management cluster without either make the state task fail instead of bootstrapping over them |
| `k8s_lab_management_kubeconfig` | Host path of the kubeconfig of the API that manages the management cluster: the bootstrap cluster's, or `mgmt.kubeconfig` once self-hosted |
| `k8s_lab_management_kubeconfig_runner` | The same, on the runner |

A role that needs the state and does not find it fails with a message naming
the `state` entry point. `bootstrap` and `clusterctl` (`tasks_from: pivot`) end
themselves when the state is `self_hosted`; `bootstrap` (`tasks_from: destroy`)
refuses to delete the bootstrap instance unless it is. `clusterctl` manages the
providers through `k8s_lab_management_kubeconfig`; `capn_identity` and the main
entry point of `management_cluster` act through `k8s_lab_management_kubeconfig_runner`.

## Required role inputs

<!-- generated: required-inputs -->
| Input | Role | Reference value | Meaning |
|---|---|---|---|
| `lxd_storage_source` | `lxd` | `/dev/disk/by-id/virtio-k8slab-lxdpool` | Block device of the btrfs pool, preferably a /dev/disk/by-id path. LXD formats it; it must not be mounted. The pool keeps this device for its whole life. |
| `lxd_uplink_interface` | `lxd` | `ext6-ra` | Host interface bridged to the external network (node eth1). It loses its own addresses, so it must not be the interface of the default route. |
| `management_cluster_external_ipv6_prefix` | `management_cluster` | `2001:db8:42:100::/64` | The external IPv6 network of the nodes' eth1, `<prefix>/<length>`; NodePorts answer only there. |
| `management_cluster_metallb_vip_range_v6` | `management_cluster` | `2001:db8:42:100::200-2001:db8:42:100::2ff` | IPv6 VIP range on the external network, `<first>-<last>`. |
<!-- end generated -->

All other role inputs have defaults that suit a real host: the
[role reference](reference/roles.md) lists them, generated from each role's
`meta/argument_specs.yml` and `defaults/main.yml`.
