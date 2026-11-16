# Deploy on a host

A deployment lives in a repository of its own — the *consumer repository* —
that holds what is specific to one host: the inventory, the variables, the
playbook, the Terraform roots with their state backend. This repository
provides the roles, charts and modules it uses, pinned to a release.

## The host

- x86_64, Debian 13 or newer, or Ubuntu 22.04 or newer (role `host` checks
  both), reachable over SSH by a user with sudo; swap off.
- Memory for every node of every cluster: about 1 GiB per control-plane
  machine and per worker at rest, more under load. `mgmt-1` (1 + 2) and one
  workload cluster (3 + 2) fit in 12 GiB with little room; 32 GiB is
  comfortable.
- A dedicated block device for the LXD pool, given as `/dev/disk/by-id/…`:
  nothing mounted from it, no filesystem signature (`wipefs -a` it once). LXD
  formats it with btrfs. Every node's root disk lives on it: the local lab's
  40 GiB hold `mgmt-1` and one workload cluster.
- An uplink interface to the external network, other than the interface of
  the default route: it becomes a port of the bridge `br-ext6` and loses its
  own addresses. Role `lxd` enables systemd-networkd and hands it the uplink:
  take the uplink out of ifupdown, NetworkManager or netplan first.
- On that network, a router that advertises an IPv6 prefix (the external
  prefix) and reserved ranges in it for every cluster's MetalLB VIPs.
- IPv4 and IPv6 of the host's own on its default-route interface: the nodes'
  egress leaves through it, NAT'ed by LXD. Role `host` enables IPv6
  forwarding, which makes the kernel ignore router advertisements: an IPv6
  default route learned from them needs `accept_ra=2` on that interface, or
  a static route.
- Outbound HTTPS, without a proxy, to the snap store, `dl.k8s.io`,
  `github.com`, `images.lxd.canonical.com`, `images.linuxcontainers.org` and
  the image registries the nodes pull from (`registry.k8s.io`, `quay.io`,
  `docker.io`).
- A host firewall, if any, that leaves LXD's table alone and accepts the
  forwarded traffic of `capi-int` and `br-ext6`
  ([architecture](architecture.md#network)).

## The runner

The machine that runs Ansible and Terraform: the binaries in
[`.tool-versions`](../.tool-versions) (Terraform, Helm, kubectl), Ansible and
the Kubernetes Python client at the versions in [`uv.lock`](../uv.lock), and
the collections at the versions in
[`ansible/requirements.lock.yml`](../ansible/requirements.lock.yml)
(`ansible-galaxy collection install --no-deps -r ansible/requirements.lock.yml -p <dir>`).
The runner reaches the host by SSH, the published API servers on
`k8s_lab_lxd_host_address`, and the Helm chart repositories of Calico and
MetalLB.

## The consumer repository

```text
consumer/
├── ansible.cfg                  roles_path = <checkout>/ansible/roles
│                                collections_path = <dir>
├── inventory/hosts.yml          the host, in a group the playbook targets
├── playbooks/management.yml     derived from tests/playbooks/management.yml
├── playbooks/group_vars/all.yml every k8s_lab_* variable and the required role inputs
└── clusters/<name>/{cluster,addons}/   two Terraform roots per workload cluster
```

`<checkout>` is a full clone of this repository at a release tag, for example
a git submodule: role `management_cluster` installs the charts from its
`charts/`. The Terraform roots take the modules from a git source at the same
tag (below). `<dir>` is where the collections were installed.

**The playbook** is the reference playbook with its own `hosts:`. It is safe to
run any number of times: every role decides from the live state whether it
has work to do; on a running deployment it neither re-creates the bootstrap
cluster nor restarts a node. It is
[`tests/playbooks/management.yml`](../tests/playbooks/management.yml), shown
here in full on the documentation site:

```yaml
--8<-- "tests/playbooks/management.yml"
```

**The variables.** Every common variable is required and is described in the
[variable contract](variable-contract.md); four role inputs have no default:
`lxd_uplink_interface`, `lxd_storage_source`,
`management_cluster_external_ipv6_prefix` and
`management_cluster_metallb_vip_range_v6`. The reference values below are the
local lab's, in
[`tests/playbooks/group_vars/all.yml`](../tests/playbooks/group_vars/all.yml):
replace the four role inputs (they describe the lab's VM) and the last
section's two values (`k8s_lab_lxd_host_address`, `k8s_lab_artifacts_dir`).

```yaml
--8<-- "tests/playbooks/group_vars/all.yml"
```

`k8s_lab_api_listen_address` is where the bootstrap cluster's and `mgmt-1`'s
API servers listen on the host; `0.0.0.0` publishes them on every IPv4
address. A workload cluster's API server listens on its module's
`api_proxy.listenAddress`, `0.0.0.0` unless the cluster root sets it
(`api_proxy = { listenAddress = "<address>" }` in its module block). On a host
with a public address, either set an internal address in both places and
make `k8s_lab_lxd_host_address` that address (every kubeconfig points
there), or filter the published ports on the host: `16443` (the bootstrap
cluster, during the first run) and `20000`–`29999` (`mgmt-1` and every
workload cluster, unless a root sets `api_proxy.port`). The roles add no
firewall rule.

## Run

```bash
ansible-playbook -i inventory/hosts.yml playbooks/management.yml
```

The first run takes 10–20 minutes. Its last plays check the result: the
convergence check, Gate B and Gate A on `mgmt-1`. Afterwards the runner holds
`<k8s_lab_artifacts_dir>/mgmt.kubeconfig` and `handoff.json`, both mode 0600.

```bash
kubectl --kubeconfig <k8s_lab_artifacts_dir>/mgmt.kubeconfig get clusters -A
```

## A workload cluster

Each workload cluster is a pair of Terraform roots, copied from
[`tests/fixtures/terraform/workload-clusters/lab-default`](../tests/fixtures/terraform/workload-clusters/lab-default/)
— `cluster/` (the class and Cluster releases on `mgmt-1`) and `addons/`
(Calico, MetalLB and the checks, on the new cluster). In the copy:

- point each `source` at this repository's modules at a release tag
  (`git::https://github.com/kogeler/k8s-lab.git//terraform/modules/workload_cluster?ref=<tag>`);
- add a state backend to each root: the add-on root's state holds the
  cluster's admin kubeconfig;
- set `handoff_path` in each `terraform.tfvars` to the runner's
  `<k8s_lab_artifacts_dir>/handoff.json` (the default only fits the
  fixture's place in this repository);
- to run Terraform on another machine, copy `handoff.json` and
  `mgmt.kubeconfig` there and set `mgmt_kubeconfig_path` next to
  `handoff_path` in each `terraform.tfvars`: the handoff holds the path on
  the machine that ran Ansible;
- set the cluster's values in each `terraform.tfvars`: the name, the
  Kubernetes version, the counts, the CIDRs, and a VIP range of its own; and
  `namespace` in both, for a cluster outside `k8s_lab_cluster_namespace` (a
  namespace with a CAPN identity, [capn-identity.md](runbooks/capn-identity.md)).

```bash
terraform -chdir=clusters/<name>/cluster init && terraform -chdir=clusters/<name>/cluster apply
terraform -chdir=clusters/<name>/addons init && terraform -chdir=clusters/<name>/addons apply
```

The add-on apply returns when the cluster has converged and both gates have
passed. Its kubeconfig:
`terraform -chdir=clusters/<name>/addons output -raw kubeconfig`.

The module interfaces are in the [Terraform reference](reference/terraform.md);
every input of the roles in the [role reference](reference/roles.md).

## Day 2

Upgrades, scaling, rotation, backups, reboots and teardown:
[runbooks](runbooks/README.md).
