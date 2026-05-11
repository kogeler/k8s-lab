# 14 — Glossary

This glossary collects every acronym, project-specific term, and
non-obvious upstream concept that appears in the k8s-lab plans, roles,
charts, and the rest of this documentation. Entries are flat and
alphabetical — operators consult this page when they hit a term they
do not recognise.

Each entry gives the term's meaning **as used in this project**. Where
the upstream definition is well-known (e.g. CAPI), the entry focuses on
how the project bends or constrains it. Plan section anchors point at
`../plans/PLAN-stage1-common.md` (general decisions) and
`../plans/PLAN-stage1-1.md` (Step-level work); other doc chapters are
cross-linked where they expand a topic in depth.

---

### CABPK

**Cluster API Bootstrap Provider Kubeadm.** The CAPI sub-controller
that owns `KubeadmConfig` / `KubeadmConfigTemplate` CRs and renders
them into cloud-init user-data for each new node. In k8s-lab CABPK
runs in namespace `capi-kubeadm-bootstrap-system` and is brought in by
`clusterctl init` together with CAPI core and KCP. Every
`KubeadmConfigSpec.files` entry from the chart-shipped templates is
inlined by CABPK into the node's `write_files`. See
[02-architecture.md §4.4](02-architecture.md) and plan `§16.2`/`§16.3`.

### CAPI

**Cluster API.** The upstream Kubernetes-native API for
provisioning and lifecycle-managing Kubernetes clusters. In k8s-lab
CAPI is the orchestration backbone: it owns the `Cluster`,
`ClusterClass`, `Machine`, `MachineDeployment`, `KubeadmControlPlane`
and infrastructure CRs. CAPI controllers run on bootstrap k3s before
pivot, then on `mgmt-1` afterwards. See
[02-architecture.md §3.3](02-architecture.md).

### CAPN

**Cluster API Provider for Incus/LXD.** Upstream project name
`cluster-api-provider-incus`, hosted at
`github.com/lxc/cluster-api-provider-incus`. CAPN is the CAPI
infrastructure provider that turns `LXCCluster` / `LXCMachine`
/ `LXCMachineTemplate` CRs into actual LXC containers on the LXD
substrate. CAPN officially supports both Incus and Canonical LXD;
k8s-lab uses Canonical LXD via snap, configured through CAPN's
unprivileged kubeadm profile. See plan `§2.5`–`§2.10`.

### canonical flow

The single linear nine-step sequence that brings a fresh host from
zero to a deployed workload cluster: substrate → bootstrap k3s →
`mgmt-1` Cluster CR → CNI + MetalLB on mgmt-1 → Gate A/B → pivot →
`cleanup_bootstrap` → workload Cluster CR → final Gate A/B. There are
no dispatch branches and no "with/without pivot" toggle — pivot is
mandatory because of the network-surface asymmetry between bootstrap
and self-hosted controllers. See
[02-architecture.md §3](02-architecture.md) and plan `§3`.

### `capi-int`

The LXD-managed internal bridge (dual-stack IPv4 `10.77.0.0/24` +
IPv6 ULA `fd42:77:1::/64`) that carries control-plane, node-to-node,
and egress traffic for every Kubernetes node and the bootstrap LXC.
Owned by the `lxd_network_int_managed` role. Each node's `eth0` lives
here. See [02-architecture.md §4.2](02-architecture.md).

### `capi-lab`

The LXD project name used by the entire lab. Every container — the
bootstrap k3s LXC, mgmt-1 nodes, workload nodes, and the haproxy LB
instance — lives in this project. The CAPN identity Secret references
this project; CAPN's TLS certificate is restricted to it. See plan
`§13.3`.

### Calico

Upstream CNI plugin shipped through the `tigera-operator` Helm chart
wrapped by `charts/cni-calico`. k8s-lab's only shipped CNI; runtime
swap to a different CNI is closed by design — see
[01-overview.md "Non-goals"](01-overview.md). Pod CIDR is
`fd42:77:2::/56` for IPv6.

### chart-version-as-CR-name

The pattern that sidesteps CAPI's admission webhook prohibition on
mutating `ClusterClass` and `*Template` fields. The chart embeds
`Chart.Version` (with dots replaced by dashes) into the CR's
`metadata.name`; bumping the chart version produces a fresh set of
immutable CRs and a new Cluster reference. The workload-cluster chart
rebuilds the same name from its
`Chart.yaml.annotations.k8s-lab.io/capi-cluster-class-chart-version`
pin; Terraform only echoes the computed name for outputs. See
[02-architecture.md §6](02-architecture.md) and plan
`§2.9`/`§12.10`.

### ClusterClass

CAPI's topology object that holds a reusable Cluster blueprint —
control-plane template, worker `MachineDeployment` templates,
infrastructure references, variables, and patches. In k8s-lab a
ClusterClass is shipped by `charts/capi-cluster-class`; the
`charts/capi-workload-cluster` Cluster CR references it through
`spec.topology.class`. The CR name carries the chart version (see
chart-version-as-CR-name).

### `clusterctl init`

The `clusterctl` subcommand that installs the CAPI core controllers,
CABPK, KCP, and a chosen infrastructure provider (CAPN here) into a
management cluster. In k8s-lab it is invoked by the
`bootstrap_clusterctl` role against bootstrap k3s, with versions
pinned in role defaults. See plan `§13.10`.

### `clusterctl move`

The `clusterctl` subcommand that migrates CAPI CRs (Cluster,
Machines, KCP, MachineDeployment, owned Secrets — everything carrying
the `cluster.x-k8s.io/move-…` label) from one management cluster to
another. In k8s-lab it pivots the `mgmt-1` Cluster CR from bootstrap
k3s onto self-hosted `mgmt-1`. **Helm release storage does not move**
— that is why workload Cluster CRs are never created on bootstrap.
See [02-architecture.md §3.3](02-architecture.md).

### dual-stack

IPv4 plus IPv6 on the same interface and the same Kubernetes object
(Pod, Service, Node). The `capi-int` bridge is dual-stack;
`kubelet --node-ip=<IPv4>,<IPv6>` is set explicitly to avoid the
auto-detection ambiguity in dual-stack bare-metal mode. The default
workload topology is dual-stack. See plan `§5.3`.

### e2e-local

The integration-level Molecule scenario at
`tests/molecule/e2e-local/`. It drives the entire canonical flow on a
single Vagrant VM end to end (substrate → bootstrap → pivot → workload
→ Gate A/B). It is the only place where the canonical flow runs as a
single shippable test. Targets: `make -C tests/molecule
e2e-local-vagrant-converge` and `…-verify`. See plan `§14.8`/`§9.2`.

### Gate A

External L2 viability acceptance gate. Asserts that MetalLB-announced
IPv6 VIPs are reachable over L2 NDP from outside the cluster. Lives in
`charts/metallb-config/templates/tests/metallb-vip.yaml` plus a
verify-side external `curl` from `ext6-ra-peer` (local) or an external
probe (production). Failure stops the deploy. See
[02-architecture.md §8.2](02-architecture.md) and plan `§17.3`.

### Gate B

CNI viability acceptance gate. Asserts that nodes reach `Ready`,
pod-to-pod direct reachability works in both address families, and
ClusterIP service routing works. Lives in
`charts/cni-calico/templates/tests/cni-ready.yaml`; uses
`requiredDuringScheduling` pod-anti-affinity to land probes on
distinct workers. Failure stops the deploy and is **not** a trigger
for runtime CNI swap. See [02-architecture.md §8.1](02-architecture.md)
and plan `§17.2`.

### `hashicorp/helm`

The Terraform provider that drives every Helm release in this project.
Pinned in plan `§8`. Used inside the `workload_cluster` module with
`wait = true` so that admission webhooks are settled before the next
release is installed. The `kubernetes` Terraform provider is allowed
**only** for read-side data lookups; mutating Kubernetes objects from
Terraform without going through Helm is forbidden. See plan `§2.9`.

### helm test hook

A Pod annotated with `helm.sh/hook: test`, executed by `helm test
<release>`. In k8s-lab Gate A and Gate B are both helm test hooks —
they live inside the chart that owns the data plane being validated,
not in a separate observability chart. The Terraform workload path
invokes `helm test` via `null_resource` + `local-exec`; the Ansible
e2e path invokes the same hooks with explicit `helm test` commands. See
plan `§17`.

### incus / LXD

`incus` is the upstream community fork of LXD; CAPN officially
supports both. **k8s-lab uses Canonical LXD installed via snap**, with
the snap channel pinned. The CAPN identity-secret default name remains
`incus-identity` for compatibility with upstream CAPN regardless of
which daemon is running. See plan `§2.5`.

### KCP / KubeadmControlPlane

CAPI's control-plane controller and the CR that owns the control-plane
Machines plus the etcd cluster (in stacked mode). Runs in namespace
`capi-kubeadm-control-plane-system`. KCP enforces odd replica counts
(1, 3, 5) for stacked etcd — k8s-lab's mgmt cluster uses 1 CP, the
workload cluster uses 3 CPs.

### KCPT / KubeadmControlPlaneTemplate

The reusable template referenced by a ClusterClass for control-plane
Machines. Shipped by `charts/capi-cluster-class`; carries
`KubeadmConfigSpec.files` and `preKubeadmCommands` for the eth1 RA
reception baseline.

### KCT / KubeadmConfigTemplate

The reusable template referenced by a ClusterClass for worker
`MachineDeployment` Machines. Same shipment path and same
file/preKubeadmCommands content as KCPT.

### `KubeadmConfigSpec.files`

The CABPK field used to deliver static files into a node's first-boot
cloud-init `write_files`. In k8s-lab this is how
`/etc/sysctl.d/99-capi-ra.conf` and
`/etc/systemd/network/30-capi-ext.network` are placed on every node
before kubelet starts. Substrate-required content; never moved into
optional values. See [02-architecture.md §4.4](02-architecture.md).

### kubeadm

The upstream Kubernetes node bootstrap tool. CAPN-prebuilt images
(`capi:kubeadm/<version>`) ship with a working kubeadm + kubelet +
containerd stack. k8s-lab does not run `INSTALL_KUBEADM=true` — that
mode is documented by CAPN as a development-only fallback. See plan
`§2.10`.

### kubelet

The Kubernetes node agent. In k8s-lab kubelet is launched with
`--node-ip=<IPv4>,<IPv6>` to pin the dual-stack node identity to the
internal NIC (`eth0` on `capi-int`). Never runs on the host itself.

### kube-proxy

The Kubernetes service-implementation agent. In k8s-lab kube-proxy is
launched with `--nodeport-addresses=<external IPv6 CIDR>` so that
NodePort accepts only on the external NIC (`eth1` on `br-ext6`),
keeping the ingress and egress paths separated.

### lab-default

The default name of the workload cluster. Created post-pivot via
`make deploy-workload` (Terraform) or by the e2e-local Molecule
scenario. Topology: 3 control-plane + 2 worker nodes, dual-stack. See
[02-architecture.md §2](02-architecture.md).

### LXC

Linux Containers. The kernel-level container API and the
low-level userspace tools (`lxc-*`) that talk to it. **k8s-lab's
Kubernetes nodes are unprivileged LXC system containers** managed
indirectly through LXD — never via raw `lxc-*` commands. Compare with
LXD below.

### LXD

The Canonical-maintained system-container daemon and tooling layer
sitting on top of LXC: REST API, `lxc` CLI, snapshots, projects,
profiles, networks, storage pools, image management. k8s-lab uses LXD
via snap. The community fork is `incus`; both are supported by CAPN
but k8s-lab fixes Canonical LXD via snap.

### LXD profile

A named bundle of LXD config keys + devices applied to instances. In
k8s-lab the `lxd_profiles` role provisions:

- `capi-controlplane` and `capi-worker` — built on CAPN's Canonical
  LXD unprivileged kubeadm baseline (`security.nesting=true`,
  `linux.kernel_modules=...`, `/boot` mount, snapd/apparmor disabled);
- the bootstrap profile for `capi-bootstrap-0`.

Profiles are project-scoped to `capi-lab`. See plan `§13.6`.

### LXD project

LXD's namespacing primitive. The lab uses one project: **`capi-lab`**.
The CAPN identity Secret restricts the TLS certificate to this
project, isolating the lab from any pre-existing instances on the
host. See plan `§13.3`.

### LXD proxy device

A userspace listener owned by the LXD daemon that forwards a host-side
TCP socket into a guest container. In k8s-lab a proxy device on
`capi-bootstrap-0` publishes `127.0.0.1:6443` inside the LB container
to `0.0.0.0:16443` on the host (or the Vagrant VM IP locally). Used
**only** for bootstrap-API publication so that the operator's runner
can reach `mgmt.kubeconfig`. Leaves no host-firewall rules behind. See
plan `§15.5`.

### MetalLB L2 mode

MetalLB's Layer-2 advertisement mode: speakers respond to ARP/NDP for
allocated VIPs. k8s-lab's only shipped MetalLB mode. Speakers run as a
DaemonSet; HA per VIP is handled by the speaker's leader election. The
MetalLB controller deviates from the project's `replicas: 2` rule and
runs as a singleton — see plan `§2.12`. Compare with BGP mode below.

### MetalLB BGP mode

MetalLB's BGP advertisement mode: speakers peer with an upstream
router and announce VIPs as `/32` (`/128`) routes. **Not** part of
Stage 1; listed in the Stage 2 backlog
(`plans/PLAN-stage2-common.md`). See [01-overview.md](01-overview.md)
"Stage 2".

### `mgmt-1`

The default name of the self-hosted CAPI management cluster. Topology:
1 CP + 2 workers (worker count is a chart-required floor for Gate B's
anti-affinity probe; CP stays at 1 because etcd quorum HA cannot be
obtained from a single host). Long-lived. See
[02-architecture.md §2](02-architecture.md).

### Molecule

Ansible's role test framework. k8s-lab uses one Molecule scenario per
role (`tests/molecule/<role>/`) plus the integration scenario
`e2e-local`. The harness runs Molecule **only against the delegated
driver** — never podman/docker. See plan `§9`.

### Molecule delegated driver

The Molecule driver that hands instance lifecycle to an external
process. In k8s-lab that process is `vagrant up` against the
`tests/vagrant/debian13/` Vagrantfile, wrapped by per-scenario
`Makefile` targets. Each scenario's `prepare.yml` is responsible only
for test-harness adjustments — production-shape role state stays in
`converge.yml`. See plan `§9`.

### NDP

**Neighbor Discovery Protocol.** IPv6's equivalent of ARP — used to
resolve link-layer addresses, perform duplicate-address detection, and
discover routers (RA). MetalLB L2 mode answers NDP for IPv6 VIPs;
Gate A asserts an external NDP-resolved curl reaches the announced
VIP.

### NodePort

Kubernetes Service type that exposes a Service on a static port on
every node. In k8s-lab NodePort is restricted to the external NIC
through `kube-proxy --nodeport-addresses=<external IPv6 CIDR>`, so
NodePorts cannot leak onto the internal `capi-int` plane.

### pivot

Shorthand for `clusterctl move` from bootstrap k3s onto self-hosted
`mgmt-1`. After pivot the bootstrap LXC is destroyed
(`cleanup_bootstrap`), and any further workload Cluster CRs are
created against `mgmt-1`. Pivot is mandatory in every canonical flow
run. See [02-architecture.md §3.3](02-architecture.md).

### prebuilt CAPN images

Container images published on the CAPN simplestreams server, named
`capi:kubeadm/<version>`. They ship a working kubeadm + kubelet +
containerd stack tuned for unprivileged LXC, plus cloud-init. k8s-lab
uses these images by default; the alternative `INSTALL_KUBEADM=true`
runtime-installation path is closed. See plan `§2.10`.

### `preKubeadmCommands`

A `KubeadmConfigSpec` lifecycle hook list of shell commands executed
just **before** `kubeadm init` / `kubeadm join`. In k8s-lab it runs
`sysctl --load` and `networkctl reload` so that the eth1 RA-reception
sysctl + systemd-networkd drop-in delivered through
`KubeadmConfigSpec.files` is alive before kubelet, kube-proxy, and the
MetalLB speaker start. See [02-architecture.md §4.4](02-architecture.md).

### RA

**Router Advertisement.** The IPv6 ICMPv6 message a router emits to
announce prefixes and the default gateway. k8s-lab nodes accept RA on
`eth1` (`accept_ra=2` because the kernel `forwarding=1` setting
suppresses the default `accept_ra=1`). The default route from the RA
is **not** imported (`UseGateway=no`) — only the prefix is used for
SLAAC. See [02-architecture.md §4.3](02-architecture.md).

### radvd

Userspace IPv6 Router Advertisement daemon. In production the RA
source is the operator's upstream router; in the local Vagrant lab
there is no upstream router, so an in-VM `radvd` listens on the
`ext6-ra-peer` veth attached to `br-ext6` and announces
`2001:db8:42:100::/64`. Substrate behaviour on the node side is
identical between local and production; only the RA *source* differs.
See [02-architecture.md §4.5](02-architecture.md).

### `security.nesting`

LXD config key (`security.nesting=true`) that allows nested
containers/namespaces inside the guest. Required by CAPN's Canonical
LXD unprivileged kubeadm profile so that containerd can operate. Set
on `capi-controlplane` / `capi-worker` profiles only — not as a
project-wide default. See plan `§2.8`.

### `security.idmap.isolated`

LXD config key (`security.idmap.isolated=true`) that gives each
container its own isolated UID/GID range, hardening the unprivileged
LXC boundary. Enabled on Kubernetes node profiles unless a verified
workload contract requires otherwise. See plan `§2.8`.

### `linux.kernel_modules`

LXD config key listing kernel modules the daemon ensures are loaded
before the guest starts. CAPN's unprivileged kubeadm profile uses it
to load the modules required by containerd, kubelet, kube-proxy and
Calico (e.g. `br_netfilter`, `ip_vs`, `nf_conntrack`, `overlay`). Set
on `capi-controlplane` / `capi-worker`. See plan `§2.8`.

### SLAAC

**Stateless Address Autoconfiguration.** The IPv6 mechanism by which a
host derives a global unicast address from an RA-advertised prefix +
its interface identifier. k8s-lab nodes obtain their `eth1` global
IPv6 via SLAAC from the on-link RA. See
[02-architecture.md §4.3](02-architecture.md).

### stacked etcd

The KubeadmControlPlane topology where etcd runs as static Pods
collocated with the kube-apiserver on the control-plane Machines. The
**only** topology shipped in Stage 1; external etcd is explicitly out
of scope. KCP enforces odd replica counts under stacked etcd (1, 3,
5). See [01-overview.md](01-overview.md) "Non-goals".

### substrate

Everything below the management cluster: the Debian-family Linux host,
LXD via snap, the `br-ext6` Linux bridge, the `capi-int` LXD bridge, LXD
storage pools and profiles, the `capi-lab` LXD project, and the
bootstrap LXC instance up to and including `bootstrap_clusterctl`.
Phases 0..3 of the canonical flow. Owned exclusively by Ansible roles.
See plan `§14.3`.

### tigera-operator

The upstream Calico operator Helm chart. k8s-lab wraps it in
`charts/cni-calico`, which adds the project's `Installation` CR,
IP pool config (`fd42:77:2::/56`, `natOutgoing: Enabled` for IPv6),
and the Gate B helm test hook. The wrapper exists so substrate-required
fields are hardcoded and only legitimate optional extensions surface
as values.

### unprivileged LXC

LXC instance run with a UID/GID remapping (user namespace) so that
root inside the container is an unprivileged UID on the host.
**Substrate invariant** in this project: control-plane nodes, workers,
and the bootstrap k3s LXC are all unprivileged. Privileged LXC is
closed by design — the fix path is "narrow CNI / feature scope" or
"switch to VM-based nodes (out of scope)", never "raise privileges".
See plan `§2.8`.

### vagrant-libvirt

Vagrant provider plugin that uses libvirt/KVM as the VM backend. The
local harness runs a single VM via vagrant-libvirt
(`tests/vagrant/debian13/`). Several environment quirks
(IFNAMSIZ-truncated bridge names, `private_network type: dhcp` for
IPv6-only NICs, disabled `synced_folder "/vagrant"`, …) are wired
explicitly into the Vagrantfile rather than left to autodiscovery. See
plan `§9.1`/`§9.2`.

### veth

Virtual ethernet pair. A pair of linked kernel network devices where a
frame entering one end exits the other. In the local harness a
`ext6-ra` ↔ `ext6-ra-peer` veth pair connects the in-VM `radvd`
listener to `br-ext6`, replacing the upstream router that would emit
RA in production. See [02-architecture.md §4.5](02-architecture.md).

### VIP

**Virtual IP.** In k8s-lab specifically: a MetalLB-announced
LoadBalancer IP (IPv6, allocated from a configured `IPAddressPool`).
Reached over the external `eth1` NIC via L2 NDP. Validated end-to-end
by Gate A (helm test hook + external curl from `ext6-ra-peer`).

---

For per-role and per-chart details, see
[09-roles-reference.md](09-roles-reference.md) and
[10-modules-and-charts.md](10-modules-and-charts.md). For the *why*
behind any decision, the relevant `§N` in
[`../plans/PLAN-stage1-common.md`](../plans/PLAN-stage1-common.md) or
[`../plans/PLAN-stage1-1.md`](../plans/PLAN-stage1-1.md) is always the
source of truth.
