# 05 — Prerequisites

This chapter covers everything you need *before* the first
`make test-local-e2e` or `make deploy-workload`:

- (a) the **target host** the cluster lives on;
- (b) the **runner machine** you drive the deployment from;
- (c) the **network plan** you need to settle on paper before any
  variables are filled in;
- (d) the **trust / secret prerequisites** — what k8s-lab generates
  for you and what you must keep secret.

For the *local* Vagrant lab the host requirements collapse onto the
runner — see [Local lab vs production](#local-lab-vs-production) at
the end. Everything else still applies.

For the architectural *why* behind these requirements, see plan
[`§2`](../plans/PLAN-stage1-common.md), [`§4`–`§5`](../plans/PLAN-stage1-common.md),
[`§8`](../plans/PLAN-stage1-common.md), and [`§11`](../plans/PLAN-stage1-common.md).

---

## Target host

The target host is the single bare-metal machine that will run the
LXD substrate, the bootstrap k3s LXC, the management cluster, and
every workload cluster. The model is single-host by design — see
[`§2.1`](../plans/PLAN-stage1-common.md) and the architecture chapter
[`02-architecture.md`](02-architecture.md).

### Hardware

- **Architecture:** `x86_64` (the CAPN-prebuilt kubeadm LXC images
  are published for `amd64`).
- **Form factor:** bare metal. Nested virtualisation is not required
  on the host because the Kubernetes nodes are LXC containers, not
  VMs.
- **CPU:** **8 cores minimum** for the default Stage-1 footprint
  (3 CP + 2 worker workload, 1 CP + 2 worker mgmt, 1 transient
  bootstrap LXC = **9 LXC instances** plus 2 haproxy LB instances).
  More headroom matters at peak (parallel kubeadm joins, Calico
  operator reconcile, MetalLB speaker rollout).
- **RAM:** **32 GB minimum** for the default footprint. Kubernetes
  control planes and CAPI controllers each pull ~1.5–2 GB; Calico
  + MetalLB add another GB per cluster. With swap disabled
  (kubelet's hard requirement), under-provisioning shows up as OOM
  on the first kubeadm `init`.
- **Disk:** **200 GB** total, of which a **dedicated block device**
  (see Storage below) holds the LXD pool. Container root
  filesystems plus the CAPN image cache eat ~70 GB on a
  steady-state lab.

These are honest minimums for a working Stage-1 lab — they keep
headroom for `terraform apply` re-runs, helm rollbacks, and the
Gate A/B helm-test pods. A heavier footprint (5-CP HA workload,
multiple workloads on one mgmt) needs more of all three.

### Operating system

- **Debian-family Linux.** Other Linux families are out of scope: the role
  contract assumes apt, systemd-networkd, the `snap` package, the LXD
  snap, and the Debian-family kernel feature defaults. The host
  distribution is asserted by every role's preflight; see the role
  source for the strict gate.
- A clean install with the standard system utilities is enough —
  the roles install everything else (LXD via snap; `kubectl`,
  `clusterctl`, `k3s` binaries downloaded into
  `/opt/capi-lab/bin`, see [`§2.2`](../plans/PLAN-stage1-common.md)).

### Storage — dedicated block device for LXD

The LXD storage pool is **btrfs**, backed by a dedicated block
device. The path you provide must point at the device itself, not a
mounted filesystem:

```
k8s_lab_storage_source: /dev/disk/by-id/<stable-id>
```

Notes (driven by [`§2.11`](../plans/PLAN-stage1-common.md) and the
`§13.4` implementation note in
[`plans/PLAN-stage1-1.md`](../plans/PLAN-stage1-1.md)):

- Use a `/dev/disk/by-id/...` path, not `/dev/sdX`. Kernel probe
  order is not stable across reboots; `by-id` is.
- The device must be **signature-free** on the first converge. The
  `lxd_storage_pools` role calls `mkfs.btrfs` *without* `-f`, so
  any pre-existing partition table or filesystem signature aborts
  the format. Run `wipefs -a /dev/disk/by-id/<id>` once before the
  first deploy.
- The device is consumed wholesale by LXD. Do not pre-mount it,
  do not put a partition table on it.
- Size: 100 GB is workable for the Stage-1 default; 200 GB is
  comfortable.

### Kernel and namespaces

Recent Debian-family kernels ship these features by default. They are
listed here so you can sanity-check a non-default install:

- User namespaces enabled (Debian-family default).
- `unprivileged_userns_clone=1` (Debian-family default on recent releases).
- cgroup v2 (Debian-family default on recent releases).
- AppArmor enabled and active (LXD's snap profile depends on it).
- The kernel modules used by Calico — `overlay`, `br_netfilter`,
  `ip_tables`, `ip6_tables`, `xt_*`, `vxlan` — present. The
  `lxd_profiles` role declares them via `linux.kernel_modules` on
  the LXC profile; the host just needs them available.

The roles do **not** rebuild the kernel; if your host is a
non-standard kernel, verify the above first.

### SSH access

The runner must be able to reach the host as a sudoer. Provide:

- a Debian user account on the host, in `sudo` (NOPASSWD strongly
  recommended for non-interactive runs);
- the runner's SSH public key in that account's
  `~/.ssh/authorized_keys`;
- TCP/22 reachable from the runner.

The host firewall is **out of scope** for this repo (see
[`§11.4`](../plans/PLAN-stage1-common.md)) — k8s-lab does not write
nftables / iptables rules. Bootstrap-API publication for the
runner uses an LXD `proxy` device (`bind: host`), which leaves no
host-firewall rules behind.

---

## Runner machine

The runner is the developer-or-operator machine that drives Ansible,
Terraform, Helm, and (optionally for the local lab) Vagrant. The
runner does not have to be the host. It does not even have to be
Debian.

### Operating system

Any modern 64-bit Linux. Debian / Ubuntu work without surprises;
Fedora, Arch, etc., are fine if the tooling versions below are
available. macOS may work for the Ansible / Terraform / Helm path
but is unsupported for the local Vagrant + libvirt harness (KVM is
Linux-only).

### Python tooling — virtualenv

Ansible, Molecule, ansible-lint and yamllint are pulled in via a
Python virtualenv that the runner activates before invoking the
Makefile (the Makefile does not own the venv path — see
`Makefile:27-30`).

Create one and install the harness:

```bash
python3 -m venv ~/.venv/k8s-lab
source ~/.venv/k8s-lab/bin/activate
pip install --upgrade pip
pip install \
  'ansible-core>=2.16' \
  'molecule>=24.2' \
  'molecule-plugins[vagrant]>=23.5' \
  'ansible-lint>=24.2' \
  'yamllint>=1.35'
```

Required Python version: **3.11 or newer** (Debian 13 ships 3.13).

`molecule-plugins[vagrant]` brings in the delegated-to-Vagrant
glue used by the local harness ([`§9.1`](../plans/PLAN-stage1-common.md)).

The runner also needs the `kubernetes` Python package on the
*executor* node (for our roles, the LXD host VM) — the shared
Molecule prepare playbook installs `python3-kubernetes` via apt on
the host, so the runner's venv does not need it.

### System tools on PATH

The Makefile (`Makefile:31-42`) expects these binaries on the
runner's `PATH`. Versions track the upstream pins recorded in
[`§8a`](../plans/PLAN-stage1-common.md):

| Tool        | Minimum  | Notes |
|-------------|----------|-------|
| `terraform` | 1.9+     | Hashicorp official release; matches the module and fixture `required_version`. |
| `helm`      | v3.14+   | v3 only; v2 is dead. |
| `kubectl`   | matches `k8s_lab_kubernetes_version` minor (default `v1.35.0`) | Skew of ±1 minor is fine. |
| `vagrant`   | 2.4+     | Local harness only — see Local lab vs production below. |
| `jq`        | any      | Used by destroy targets to parse `mgmt.auto.tfvars.json`. |
| `git`       | any      | |
| `make`      | GNU make | The Makefile uses GNU extensions. |

For the local lab additionally:

- `libvirt` daemon (`libvirtd`) running, with `qemu-kvm`;
- runner user in the `libvirt` group (else `virsh net-define`
  fails, see `tests/vagrant/debian13/Vagrantfile:53`);
- `/dev/kvm` accessible to the runner user (KVM acceleration is
  required — without it the local Vagrant guest will crawl).

On Debian / Ubuntu:

```bash
sudo apt install -y \
  libvirt-daemon-system libvirt-clients qemu-kvm \
  vagrant jq git make
sudo usermod -aG libvirt "$USER"   # log out / back in
vagrant plugin install vagrant-libvirt
```

`terraform`, `helm`, `kubectl` install via their upstream binaries
or distro packages — pick whatever your environment standardises
on.

### Ansible collections

Collections are installed *project-locally* into
`ansible/collections/` (gitignored). The Makefile exports
`ANSIBLE_COLLECTIONS_PATH` to that path
(`Makefile:24-25`), so every Ansible invocation through `make`
resolves them deterministically.

Bootstrap them once after cloning:

```bash
make deps
```

This is shorthand for:

```bash
ansible-galaxy collection install --force \
  -r ansible/requirements.yml \
  -p ansible/collections
```

The required set is pinned in
[`ansible/requirements.yml`](../ansible/requirements.yml):

- `ansible.posix >=2.1.0`
- `community.general >=12.6.0`
- `community.crypto >=3.2.0`
- `kubernetes.core >=6.4.0`

### Sanity check

A fully-prepared runner should pass:

```bash
ansible --version           # 2.16+ from the venv
molecule --version
terraform version           # 1.9+
helm version --short        # v3.14+
kubectl version --client    # matches workload k8s minor
vagrant --version           # 2.4+ (local lab only)
ls ansible/collections/ansible_collections/kubernetes/core
```

---

## Network plan worksheet

Fill this out **before** writing any inventory or `tfvars`. Every
placeholder maps directly to a `k8s_lab_*` variable from
[`§8`](../plans/PLAN-stage1-common.md); use the worksheet as your
single source of truth and copy values from here into the consumer
repo's `host_vars` / `tfvars`.

```text
# ----- external plane (host uplink, IPv6 /64) -----------------------
# Mapped to k8s_lab_uplink_interface and the external addressing block
# in §5.1. The /64 is one logical reservation; node IPs and MetalLB
# VIPs are sub-ranges inside it, not separate routed subnets.

uplink_interface       : <eth-name-on-host>          # k8s_lab_uplink_interface         (required)
external_ipv6_prefix   : <2001:db8:abcd:ef::/64>     # k8s_lab_external_ipv6_prefix     (required)
host_ipv6              : <prefix>::1                 # used by host on br-ext6
node_ipv6_range        : <prefix>::10-<prefix>::3f   # k8s_lab_external_node_ipv6_range (required)
metallb_vip_range_v6   : <prefix>::200-<prefix>::2ff # k8s_lab_metallb_vip_range_v6     (required)
external_bridge_name   : br-ext6                     # k8s_lab_external_bridge_name     (default ok)

# ----- internal plane (LXD-managed dual-stack bridge) ---------------
# Defaults from §5.2 are sane for a single-host lab; only override
# them on a host where the v4 subnet collides with something else.

internal_network_name  : capi-int                    # k8s_lab_internal_network_name    (default)
internal_ipv4_subnet   : 10.77.0.0/24                # k8s_lab_internal_ipv4_subnet     (default)
internal_ipv6_subnet   : fd42:77:1::/64              # k8s_lab_internal_ipv6_subnet     (default)
internal_ipv4_nat      : true                        # k8s_lab_internal_ipv4_nat        (default)
internal_ipv6_nat      : true                        # k8s_lab_internal_ipv6_nat        (default)

# ----- workload Pod / Service CIDRs ---------------------------------
# Both CIDR families are mandatory (dual-stack, §5). IPv4 ranges are
# k3s-compatible defaults; IPv6 ranges are ULA from fd42:77::/48,
# kept consistent with k8s_lab_internal_ipv6_subnet.

workload_pod_cidr_v4    : 10.244.0.0/16              # k8s_lab_workload_pod_cidr_v4     (default)
workload_pod_cidr_v6    : fd42:77:2::/56             # k8s_lab_workload_pod_cidr_v6     (default)
workload_service_cidr_v4: 10.96.0.0/16               # k8s_lab_workload_service_cidr_v4 (default)
workload_service_cidr_v6: fd42:77:3::/112            # k8s_lab_workload_service_cidr_v6 (default)

# ----- runner reachability ------------------------------------------
# Runner-reachable address of the LXD host. The workload kube-apiserver
# listens on capi-int IPv6, reachable only from inside the host;
# §16.4 publishes it via an LXD proxy device on a per-cluster port.
# In production = the host's public IPv4 / FQDN. In local Vagrant =
# the VM's mgmt-nat IPv4.

lxd_host_address       : <ip-or-dns-of-host>         # k8s_lab_lxd_host_address         (required)

# ----- storage ------------------------------------------------------
# Path to the dedicated block device for the LXD btrfs pool.
# MUST be /dev/disk/by-id/... and signature-free on first converge.

storage_source         : /dev/disk/by-id/<stable-id> # k8s_lab_storage_source           (required)
```

The `(required)` marker matches the `required: true` flag in
[`§8`](../plans/PLAN-stage1-common.md). Variables marked
`(default)` have safe defaults you only override when something on
the host conflicts.

A few sanity rules to apply while filling the worksheet:

- The external `/64` must be a real, routable IPv6 prefix in
  production. SLAAC RA from the provider router is the source of
  truth on `eth1` of every node — see [`§5.3`](../plans/PLAN-stage1-common.md)
  and architecture [`§4.4`](02-architecture.md).
- `node_ipv6_range` and `metallb_vip_range_v6` must be disjoint
  sub-ranges of the external prefix. The defaults shown
  (`::10–::3f` for nodes, `::200–::2ff` for VIPs) are the
  canonical split.
- Workload Pod / Service CIDR v4 and v6 are **both** required —
  the workload cluster is dual-stack by design ([`§5`](../plans/PLAN-stage1-common.md))
  and a missing IPv6 range is rejected by kubeadm.

---

## TLS / trust prerequisites

Per [`§11`](../plans/PLAN-stage1-common.md):

- **LXD trust material is generated automatically.** The role
  `bootstrap_capn_secret` ([`§13.11`](../plans/PLAN-stage1-1.md))
  mints a project-scoped restricted TLS certificate for CAPN, adds
  it to the LXD trust store, and materialises it as a Kubernetes
  Secret (one per namespace listed in
  `k8s_lab_capn_identity_namespaces`). The operator does **not**
  pre-generate certs.

- **`.artifacts/mgmt.kubeconfig` is the single admin kubeconfig**
  for the active management cluster ([`§11.1`](../plans/PLAN-stage1-common.md)).
  It is written with mode `0600`, owned by the runner user, and
  is in `.gitignore`. Treat it as you would any cluster admin
  credential — do not check it in, do not paste it into ticket
  systems.

- **`.artifacts/mgmt.auto.tfvars.json`** is the runner-side handoff
  bundle from Phase 4 to Terraform. Same rules: 0600, gitignored,
  not committed.

- **The host firewall is the operator's property** ([`§11.4`](../plans/PLAN-stage1-common.md)).
  k8s-lab does not write to it. Bootstrap-API publication uses an
  LXD `proxy` device (`bind: host`) which is removed cleanly by
  `lxc delete`. A source-IP ACL — if you want one — is the
  consumer repo's job.

- **Real-environment secrets** (vault data, custom certs, host-side
  credentials added by your environment) live in the **consumer
  repo**, never in this repo. This repo carries no environment
  data ([`§2.5`](../plans/PLAN-stage1-common.md), [`§11.2`](../plans/PLAN-stage1-common.md)).

The protection model for the bootstrap Kubernetes API rests on two
layers, both within scope of this repo:

1. **Kubernetes mTLS** via the kubeconfig (k3s requires a client
   cert; the kubeconfig is enforced 0600 and gitignored);
2. **LXD API auth** via the project-scoped restricted TLS cert
   minted by `bootstrap_capn_secret`.

A source-IP ACL on the host firewall is an extra defence-in-depth
layer the consumer repo may add — it is not required for
correctness.

---

## What this repo does NOT need

Operators new to LXD often expect prerequisites this project
deliberately avoids. To reduce friction:

- **No host-side Docker.** Container nodes are LXC system
  containers managed by LXD. Docker is not used anywhere in the
  flow — not for the bootstrap, not on the host, not in tests.
- **No Kubernetes on the host itself.** All Kubernetes control
  planes and workers run inside LXC containers. The host runs only
  LXD (via snap) and a Linux bridge.
- **No custom APT repositories.** Forbidden by [`§2.2`](../plans/PLAN-stage1-common.md).
  Non-standard tools are downloaded by the roles into
  `/opt/capi-lab/bin` with version pins and checksum verification.
- **No host firewall configuration.** Out of scope by [`§11.4`](../plans/PLAN-stage1-common.md).
  The roles do not touch nftables / iptables.
- **No pre-existing Kubernetes cluster.** The bootstrap k3s LXC is
  brought up from scratch by the `bootstrap_k3s` role; CAPI is
  installed into it by `bootstrap_clusterctl`; the management
  cluster is provisioned by CAPN. There is no
  "import an existing cluster" path.
- **No pre-existing certificates.** All TLS material — k3s,
  kubeadm CA, CAPN identity Secret — is generated during the
  canonical flow.
- **No `kind`, `minikube`, or Docker Desktop.** The local lab uses
  Vagrant + libvirt + a local VM that mirrors the production host.
  There is no shortcut driver.

---

## Local lab vs production

The local Vagrant + libvirt lab does **not** need bare metal. The
runner can be the same machine as the local lab — Vagrant brings
up a local VM that plays the role of the host
([`§9.1`](../plans/PLAN-stage1-common.md), [`§9.2`](../plans/PLAN-stage1-common.md)).

What the local path needs from the runner instead of bare metal:

- **KVM acceleration available.** `/dev/kvm` accessible by the
  runner user; nested virtualisation enabled in the host's BIOS /
  the cloud VM provider (the Vagrant VM uses
  `libvirt.nested = true`, see `tests/vagrant/debian13/Vagrantfile:79`).
- **Headroom for the VM.** The Vagrantfile defaults to
  **8 vCPU, 12 GB RAM, 40 GB qcow2** for the LXD pool disk
  (`Vagrantfile:73-130`). The VM runs a slimmed-down topology —
  the e2e-local Molecule scenario exercises the full canonical
  flow including pivot — so the runner needs enough headroom on
  top of its own desktop usage. Practical floor: **8 GB RAM free
  for the VM** + your normal desktop, **2 vCPU spare**, and **50
  GB of free disk** on the libvirt storage pool.
- **`vagrant-libvirt` plugin installed** and the runner user in
  the `libvirt` group.
- **Ports for SSH-into-VM.** Vagrant handles this via its private
  NAT network; you do not provision external IPv6 — the lab models
  the external segment via in-VM `radvd` on a veth pair, see
  [`§9.2`](../plans/PLAN-stage1-common.md) and architecture
  [`§4.5`](02-architecture.md).

For the step-by-step local walkthrough see
[`06-quickstart-local.md`](06-quickstart-local.md). Once you can
run `make test-local-e2e` to a green Gate A/B, the same code path
graduates to a real bare-metal host via the consumer-repo pattern
in [`07-deployment-guide.md`](07-deployment-guide.md).
