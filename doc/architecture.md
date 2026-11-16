# Architecture

How a k8s-lab host is put together, how a deployment comes up, and who owns
what afterwards. Why each choice was made is in the
[decision records](decisions/README.md); the procedures are in the
[runbooks](runbooks/README.md).

## One host

Everything runs on one Debian or Ubuntu host. The host runs LXD (from its
snap) and nothing Kubernetes itself; every Kubernetes node is an
**unprivileged LXC system container** in one LXD project (`capi-lab` in the
reference values). The host is the single failure domain.

| Cluster | What it is | Default size | Lifetime |
|---|---|---|---|
| bootstrap cluster | k3s in one container (the *bootstrap instance*); hosts Cluster API long enough to create `mgmt-1` | one node | removed after the pivot |
| `mgmt-1` | the *management cluster*: Cluster API and CAPN (the LXD infrastructure provider), managing itself and every workload cluster | 1 control-plane machine, 2 workers | the deployment's life |
| workload clusters | where workloads run; any number | 3 control-plane machines, 2 workers (`lab-default`) | created and removed with Terraform |

What the host carries for them (role `lxd`):

| Object | Purpose |
|---|---|
| bridge `br-ext6` (systemd-networkd) | the external network; the host's uplink is its port; every node's `eth1` |
| LXD network `capi-int` | the internal dual-stack network (IPv4 `10.77.0.0/24`, IPv6 `fd42:77:1::/64`), DHCP and NAT by LXD; every node's `eth0` |
| storage pool `capi-fast` | btrfs on a dedicated block device; every node's root disk |
| image registry `capn` | CAPN's image server (`https://images.linuxcontainers.org/capn`), the source of every node image |
| project `capi-lab` | restricted to unprivileged containers, the devices the nodes need, and the registry `capn` |
| profiles `capi-*` | the container settings a node needs (nesting, `/dev/kmsg`, kernel modules, NICs) |
| listener on `capi-int` | the LXD API for CAPN, authenticated by a client certificate restricted to the project |

The API server of `mgmt-1` and of every workload cluster is published on the
host by an LXD proxy device on the cluster's load-balancer instance (CAPN's
haproxy): port `20000 + (adler32 of the cluster name) mod 10000`, on
`k8s_lab_api_listen_address` for `mgmt-1` and on the module input
`api_proxy.listenAddress` for a workload cluster (`0.0.0.0` by default). The
bootstrap cluster's k3s API is a proxy device on the bootstrap instance itself:
port `16443` (`bootstrap_api_port`) on `k8s_lab_api_listen_address`. The runner
reaches every cluster there.

## How a deployment comes up

The reference playbook [`tests/playbooks/management.yml`](../tests/playbooks/management.yml)
is a flat list of the six roles; a deployment derives its own from it. Each
role decides from the live state whether it has work to do, so the same
playbook runs the first time and on every later day.

```text
host        packages, kernel modules, sysctls, pinned binaries in /opt/capi-lab/bin
lxd         snap, bridge, registry, project, pool, network, listener, profiles
state       absent | bootstrapping | self_hosted  (refuses when mgmt-1's nodes exist without a working kubeconfig)
bootstrap   bootstrap instance + k3s                              (nothing once self_hosted)
clusterctl  providers on the API that manages mgmt-1: init, upgrade, never downgrade
capn_identity  client certificate, LXD trust, Secret per namespace
management_cluster  mgmt-1 on that API: class + Cluster releases, kubeconfig,
                    Calico, MetalLB, convergence check, Gate B, Gate A, handoff.json
clusterctl (pivot)  providers on mgmt-1, clusterctl move bootstrap -> mgmt-1
state, capn_identity, management_cluster   again, now on mgmt-1: its releases are re-adopted there
bootstrap (destroy)  the bootstrap instance is removed
----------------------------------------------------------------------------------------
Terraform, per workload cluster, on mgmt-1:  <root>/cluster, then <root>/addons
```

The pivot is not optional. Helm keeps a release's record in a Secret of the
cluster it is installed on, and `clusterctl move` moves Cluster API objects,
not Helm records. Only `mgmt-1` itself is ever created on the bootstrap
cluster; its releases are installed again on `mgmt-1` after the move, which
adopts the moved objects. Every workload cluster is created afterwards, on
`mgmt-1`, where its Helm records and its objects live together. After the
pivot the controllers run on `mgmt-1`'s nodes behind Calico instead of in k3s
behind flannel, so everything they reach (the LXD API, the load balancers)
goes through Calico's outgoing NAT before a workload cluster depends on it.

Terraform reads the management side from `handoff.json` in the runner's
artifacts directory: `lxd_host_address`, `cluster_namespace`,
`infrastructure_secret_name`, `mgmt_kubeconfig_path`, `external_ipv6_prefix`.

## Who owns what

| Owner | Objects | Changed by |
|---|---|---|
| Ansible | the host, LXD, the bootstrap cluster, the providers, the CAPN identity, `mgmt-1` and its add-ons — for its whole life | the management playbook |
| Terraform | each workload cluster: its class and Cluster releases on `mgmt-1` (cluster root), its add-ons and checks (add-on root) | `terraform apply` of its two roots |
| Helm | every Kubernetes object the project creates, through the charts in `charts/` | — |

No operation needs both tools. Kubernetes objects are never applied as raw
manifests, with two exceptions: the Cluster API providers and cert-manager,
which `clusterctl` installs and upgrades, and the CAPN identity Secrets and
their namespaces, which role `capn_identity` writes with a server-side apply so
that the key never lands in a Helm release record. Reads (`kubectl get`,
`kubectl wait`, `helm test`) are fine. Terraform modules hold no provider
blocks; the roots configure them.

## Clusters and templates

- **One ClusterClass per cluster**, named after it (`charts/capi-cluster-class`).
  Its templates are named `<cluster>-<kind>-<8 hex of the sha256 of the spec>`:
  a changed spec is a new object, an unchanged spec keeps its name. Cluster API
  replaces the machines of a template that changed; the old template is
  removed with the release revision that dropped it.
- **The Cluster** (`charts/capi-workload-cluster`) carries the version, the
  replica counts, the networks and the class revision
  (`k8s-lab.io/class-revision`). After every install and upgrade its hook Job
  publishes the API server and waits until it answers.
- **The node image** is CAPN's `capi:kubeadm/<version>` from
  `https://images.linuxcontainers.org/capn`; only some Kubernetes patch
  releases get one.
- **Certificates**: kubeadm issues control-plane certificates for 1095 days;
  Kubeadm Control Plane replaces a control-plane machine 60 days before its
  certificates expire ([runbook](runbooks/certificates.md)).

## Network

Every node has two interfaces:

| | `eth0` (internal, `capi-int`) | `eth1` (external, `br-ext6`) |
|---|---|---|
| Addresses | IPv4 from LXD's DHCP (leases 168 h); IPv6 by SLAAC from LXD's advertisements | IPv6 by SLAAC from the external router's advertisements |
| Routes | the main table's only default route | the advertised routes in table 4200; the prefix on-link in the main table |
| Carries | kubelet node IP, control plane, Pod network (VXLAN), all egress (NAT by the host) | NodePorts, MetalLB VIPs, and the replies to what arrived on it |

**Replies leave the way the request came in.** A connection that arrives on
`eth1` gets the conntrack mark `0x100`; its replies carry it as a packet mark,
and the rule `fwmark 0x100/0x100 lookup 4200` sends them out of `eth1`.
Everything else leaves through `eth0`. A rule on the source address could not
do this: a reply from a Pod behind a VIP is forwarded traffic whose source
becomes the VIP only after routing.

The class chart puts on every node, through cloud-init before kubeadm:
`/etc/systemd/network/30-capi-ext.network` (RA routes to table 4200, the
on-link route, the fwmark rule), the mark rules
(`/etc/k8s-lab/ext-reply.rules`: two chains of their own in the node's
`ip6 mangle` table, loaded in one `ip6tables-nft-restore --noflush`
transaction by `k8s-lab-ext-reply.service` at every boot), a kubelet drop-in
that requires that unit (a node that cannot load the marks never joins), and
`ManageForeignRoutingPolicyRules=no` for systemd-networkd. The control plane's
kube-proxy configuration sets `nodePortAddresses` to the external prefix, so a
NodePort answers on `eth1` only. The rules live in each node's own network
namespace: the host's firewall never sees them. The host loads the kernel
modules they need (`nft_compat`, `xt_connmark`, `xt_mark`; role `host`).

**The host's firewall** is the host's. The roles write none; LXD keeps its NAT
for `capi-int` in its own table `inet lxd`. A host with its own nftables
ruleset must not `flush ruleset` (that deletes LXD's table), must accept
forwarded traffic of `capi-int` and `br-ext6` in every forward chain with a
`drop` policy (with `br_netfilter` loaded, bridged frames pass the host's
forward hook), needs IPv4 and IPv6 of its own for the nodes' egress, and lets
in the published API ports if they should be reachable. On an external
segment shared with others, reserve the VIP ranges, and stop other LXD tenants
from sending router advertisements (`security.ipv6_filtering=true` on their
NICs, not on the nodes').

## Add-ons and checks

| Release | What it installs | Check |
|---|---|---|
| `cni-calico` | the tigera operator, which creates the Calico CRDs | — |
| `cni-calico-config` | the dual-stack `Installation` (VXLAN for both families, nftables dataplane, outgoing NAT) and the `APIServer` | **Gate B** — CNI viability |
| `metallb` | MetalLB in native L2 mode | — |
| `metallb-config` | the IPv6 address pool and an L2 advertisement on `eth1` | **Gate A** — load-balancer viability |

Each check is a `helm test`, and a failed check fails the playbook run or
the Terraform apply:

- **Convergence check** (`capi-workload-cluster`): a Job of `kubectl wait`s —
  the topology is reconciled, the control plane and the MachineDeployments
  have finished rolling out and scaling, every machine is Ready, the Cluster
  is Available — each condition counted only for the object's current
  generation. As a Job it survives a drain of the node it runs on.
- **Gate B**: Calico runs at the chart's version on every node; then two
  servers on two workers answer over IPv4 and IPv6.
- **Gate A**: a LoadBalancer Service gets an address from the pool and
  answers it inside the cluster. Reachability from outside — from the host and
  from a client behind the external router — is what the e2e verify checks.

In a workload cluster's add-on root the convergence check and the gates run
again whenever the Cluster's generation, its class revision or a release they
check changes.

## Limitations

- One host, one failure domain; more control-plane machines protect against a
  node failing, not the host. Count every cluster's control planes against
  the host's memory (about 1 GiB each at rest).
- `mgmt-1` has one control-plane machine by default: an upgrade surges to a
  second etcd member and back; nothing remediates it automatically. Back it up
  ([backup-restore.md](runbooks/backup-restore.md)).
- Kubernetes versions are those CAPN publishes an image for.
- No MachineHealthChecks are shipped: after a host reboot every node is
  NotReady at once.
- The Helm Terraform provider reads a release it cannot reach as deleted: do
  not apply an add-on root while its cluster's API does not answer
  ([troubleshooting](troubleshooting.md)).
- Tested automatically: the whole flow, a second run, a scale and a destroy
  on every e2e run, locally and in CI. Tested by drill: everything in the
  runbooks, each with its date and what was not exercised.

## Terms

| Term | Meaning |
|---|---|
| host | the machine LXD runs on |
| runner | the machine the playbook and Terraform run on (may be the host) |
| bootstrap cluster / bootstrap instance | the transient k3s API / its LXD container |
| management cluster, `mgmt-1` | the self-hosted cluster running Cluster API and CAPN |
| workload cluster | a cluster created on `mgmt-1` by Terraform |
| pivot | `clusterctl move` of the Cluster API objects from the bootstrap cluster to `mgmt-1` |
| CAPN | `cluster-api-provider-incus`, Cluster API's provider for Incus and LXD |
| handoff file | `handoff.json`, the management side's facts for the Terraform roots |
| Gate A, Gate B | the load-balancer and CNI acceptance tests |
| convergence check | the Cluster chart's test: the cluster has settled on its last change |
