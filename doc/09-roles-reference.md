# 09 — Ansible roles reference

This chapter is a uniform per-role reference for all **14 Ansible
roles** that make up the k8s-lab substrate, the bootstrap management
cluster, and the pivot/destroy edges. Roles are presented in the
order the canonical flow invokes them (plan
[`§3.1`](../plans/PLAN-stage1-common.md)), grouped by phase. A role
dependency graph and a recap of the role-author conventions follow at
the end.

For variable defaults and the cross-role typed `k8s_lab_*` contract,
see [`08-configuration-reference.md`](08-configuration-reference.md).
For the *why* behind any given role, follow the `§N.M` plan link in
each subsection — the plans, not this chapter, are the source of
truth.

Each role section follows the same template:

- **What it does.** Short prose summary.
- **Public inputs.** The most-overridden variables. Full list lives
  in `08-configuration-reference.md` and the role's own
  `defaults/main.yml`.
- **Dependencies (`meta/main.yml`).** Direct deps only. Plan
  [`§2.6.5`](../plans/PLAN-stage1-common.md) bans transitive
  re-declaration.
- **Runtime artefacts.** What the role leaves on the host or runner
  filesystem.
- **Tags.** Role-level tag (both `_` and `-` spellings accepted) and
  the section tags the dispatcher emits.
- **Plan reference.** The `§N.M` section in `plans/PLAN-stage1-*.md`
  that owns the role.

---

## Phase 0..1: Host bootstrap

These two roles run on the bare-metal Debian 13 host before any LXD
state exists. Together they own the host-side prerequisites: APT
packages, kernel modules, sysctl, the `/opt/capi-lab` tree, and the
pinned binaries everything downstream consumes.

### `base_system`

**What it does.** Minimal Debian 13 Trixie host preparation. Installs
only the APT packages allowed by plan
[`§2.2`](../plans/PLAN-stage1-common.md) (no custom APT repos),
optionally installs `btrfs-progs`, loads and persists the kernel
modules CAPN nodes and kubeadm need (`overlay`, `br_netfilter`,
`nf_conntrack`), applies a small Kubernetes-on-LXD sysctl baseline,
and creates the deterministic `/opt/capi-lab/{bin,etc}` tree later
roles populate. It does **not** install LXD, fetch non-system
binaries, or touch SSH/users/time-sync — those are environment
concerns. When `base_system_btrfs_pool_required=true`, preflight
asserts the dedicated LXD pool mountpoint is already a btrfs
filesystem; the role does not format or mount that disk itself.

**Public inputs.**
- `base_system_enabled` — whole-role toggle.
- `base_system_opt_root` — `/opt/capi-lab` (sources from the global
  `k8s_lab_opt_root`).
- `base_system_extra_packages`, `base_system_btrfs_extra_packages` —
  additive on top of the substrate-required list in
  `vars/main.yml`.
- `base_system_extra_sysctl`, `base_system_extra_kernel_modules` —
  additive baselines.
- `base_system_btrfs_pool_required`,
  `base_system_btrfs_pool_mountpoint` — opt-in btrfs-mount contract
  assertion.
- `base_system_flow_control_{packages,modules,sysctl}` — coarse
  section gates.

**Dependencies (`meta/main.yml`).** None.

**Runtime artefacts.**
- `/opt/capi-lab/{bin,etc}` (mode `0755`, root:root).
- `/etc/modules-load.d/<module>.conf` for each persisted kernel
  module.
- `/etc/sysctl.d/99-*.conf` entries for the required sysctl knobs.
- APT package state (no repo files added).

**Tags.** `base_system` / `base-system` and section tags
`base_system_preflight`, `base_system_install`,
`base_system_modules`, `base_system_sysctl`, `base_system_config`,
`base_system_healthchecks`.

**Plan reference.**
[`§13.1`](../plans/PLAN-stage1-1.md).

### `binary_fetch`

**What it does.** Downloads pinned upstream release binaries —
`kubectl`, `clusterctl`, `k3s` — into `/opt/capi-lab/bin` with
sha256 verification. Each binary is fed to
`ansible.builtin.get_url` with `checksum=sha256:<digest>`, so
tampering or version drift fails the task and an already-correct
file is not re-downloaded. The role does not run any
`install.sh`, does not add APT repos, and does not push anything
into containers — that lane belongs to Phase 4 roles.

The role supports three checksum sourcing styles, picked per
binary to match upstream practice (plan
[`§13.8`](../plans/PLAN-stage1-1.md)):

| Style | Used for | Source of digest |
|---|---|---|
| `plain` | `kubectl` | `<url>.sha256` — single-line hex digest fetched per run. |
| `manifest` | `k3s` | `sha256sum-<arch>.txt` — multi-line, role picks the row whose name column matches `binary_fetch_k3s_checksum_entry`. |
| `pinned` | `clusterctl` | Upstream publishes no sha256 asset; the digest is pinned in `defaults/main.yml` next to the version, refreshed manually at version-bump time. |

**Public inputs.**
- `binary_fetch_kubectl_version`, `binary_fetch_clusterctl_version`,
  `binary_fetch_k3s_version` — the version pins.
- `binary_fetch_clusterctl_checksum_sha256` — the pinned digest for
  the `pinned` style.
- `binary_fetch_bin_dir` — destination dir (defaults to
  `/opt/capi-lab/bin`).
- `binary_fetch_arch` — `amd64` only in Stage 1.
- `binary_fetch_download_timeout` — wall-clock budget per fetch.
- `binary_fetch_flow_control_{kubectl,clusterctl,k3s}` and the
  matching `*_enabled` toggles.

**Dependencies (`meta/main.yml`).**
- `base_system` — for `/opt/capi-lab/bin`, `ca-certificates`,
  `curl`, and the kernel/sysctl baseline.

**Runtime artefacts.**
- `/opt/capi-lab/bin/kubectl`
- `/opt/capi-lab/bin/clusterctl`
- `/opt/capi-lab/bin/k3s`

All three with `0755`, root:root, the exact pinned version on disk.

**Tags.** `binary_fetch` / `binary-fetch` plus section tags
`binary_fetch_preflight`, `binary_fetch_kubectl`,
`binary_fetch_clusterctl`, `binary_fetch_k3s`,
`binary_fetch_healthchecks`.

**Plan reference.**
[`§13.8`](../plans/PLAN-stage1-1.md) and
[`§15.1`](../plans/PLAN-stage1-2.md).

---

## Phase 2: LXD substrate

These five roles assemble the LXD substrate the bootstrap LXC and
every CAPN-spawned Kubernetes node will live on: snap install,
project, storage pool, internal managed bridge, and the four
substrate profiles. All five run on the host, in this order.

### `lxd_host`

**What it does.** Owns everything host-side around LXD but nothing
inside it. Installs the `lxd` snap (channel `6/stable` by default,
plan [`§2.11`](../plans/PLAN-stage1-common.md) deviation from
Canonical's 5.21 LTS recorded inline), applies a deterministic snap
refresh policy (`hold` indefinitely or a weekly `timer` window),
blocks until `lxd waitready` returns, and creates the host-side
external Linux bridge `br-ext6` declaratively via
systemd-networkd drop-ins with the operator-supplied uplink as a
member. The bridge is a plain Linux bridge — **not** an LXD-managed
network — and is later referenced by profiles via
`nictype: bridged` / `parent: br-ext6`.

**Public inputs.**
- `lxd_host_snap_channel` — default `6/stable`.
- `lxd_host_snap_refresh_mode` — `hold` or `timer`.
- `lxd_host_snap_refresh_hold_value` / `..._timer_value`.
- `lxd_host_ext_bridge_enabled`, `lxd_host_ext_bridge_name` (default
  `br-ext6`), `lxd_host_ext_bridge_uplink` (REQUIRED when bridge is
  enabled — preflight asserts).
- `lxd_host_ext_bridge_mtu`, `lxd_host_ext_bridge_stp`,
  `lxd_host_ext_bridge_forward_delay`.
- `lxd_host_wait_ready`, `lxd_host_wait_ready_timeout`.
- `lxd_host_flow_control_{snap,refresh,bridge}`.

**Dependencies (`meta/main.yml`).**
- `base_system` — provides `snapd`, `/opt/capi-lab`, kernel modules.

**Runtime artefacts.**
- LXD snap installed and pinned to `lxd_host_snap_channel`.
- `snap set system refresh.{hold,timer}=...` system-wide config.
- `/etc/systemd/network/<prio>-<bridge>.netdev`,
  `<prio>-<bridge>.network`,
  `<prio>-<uplink>.network` drop-ins.
- `systemd-networkd.service` enabled.
- Bridge interface `br-ext6` (or override) up, with the configured
  uplink as a member; `LinkLocalAddressing=no`, `IPv6AcceptRA=no`
  on the bridge itself (containers, not the host, carry the
  external IPv6).

**Tags.** `lxd_host` / `lxd-host` plus `lxd_host_preflight`,
`lxd_host_install`, `lxd_host_refresh`, `lxd_host_waitready`,
`lxd_host_bridge`, `lxd_host_healthchecks`.

**Plan reference.**
[`§13.2`](../plans/PLAN-stage1-1.md).

### `lxd_project`

**What it does.** Creates and configures the k8s-lab LXD project
(`capi-lab` by default) with feature isolation and the
`restricted=true` allow-list per plan
[`§2.3`](../plans/PLAN-stage1-common.md) and
[`§13.3`](../plans/PLAN-stage1-1.md). The substrate-required
restriction set is hardcoded in the role (`vars/main.yml`) so an
operator cannot accidentally disable it from defaults — it pins
`restricted.containers.privilege=unprivileged` (plan
[`§2.8`](../plans/PLAN-stage1-common.md) hard-lock),
`restricted.containers.nesting=allow` (k8s nodes need nesting),
`restricted.devices.disk=managed`, `restricted.devices.proxy=allow`
(needed for the bootstrap API publish path), and several other
substrate-required keys. The role talks to LXD through
`ansible.builtin.uri` over the snap unix socket; PATCH semantics
mean operator-set keys outside the role's contract are left alone.

**Public inputs.**
- `lxd_project_name` (default `capi-lab`).
- `lxd_project_description`.
- `lxd_project_lxd_socket_path`.
- `lxd_project_extra_restrictions` — extra `restricted.*` keys
  merged on top of the baseline (preflight rejects keys that don't
  start with `restricted.`).
- `lxd_project_flow_control_project`.

**Dependencies (`meta/main.yml`).**
- `lxd_host` — provides the running, waitready LXD daemon.

**Runtime artefacts.**
- LXD project named `lxd_project_name` with feature isolation
  (`features.images=true`, `features.profiles=true`,
  `features.storage.{volumes,buckets}=true`,
  `features.networks=false`, `features.networks.zones=false`) and
  the `restricted.*` allow-list applied.

**Tags.** `lxd_project` / `lxd-project` plus
`lxd_project_preflight`, `lxd_project_project`,
`lxd_project_healthchecks`.

**Plan reference.**
[`§13.3`](../plans/PLAN-stage1-1.md).

### `lxd_storage_pools`

**What it does.** Creates and configures LXD storage pools through
the LXD REST API (`ansible.builtin.uri`). Pools themselves are
global LXD entities; project scoping happens via
`restricted.devices.disk=managed` on the project. The role
substrate-requires the `btrfs.mount_options=user_subvol_rm_allowed`
key on every btrfs pool (kubelet garbage-collection inside
unprivileged CAPN nodes breaks without it) — the key is merged on
top of each entry's user-supplied `config` at apply time and cannot
be silently dropped. The default list ships one pool (`capi-fast`,
btrfs), with `config.source` empty by default — the operator MUST
supply it; preflight rejects empty.

**Public inputs.**
- `lxd_storage_pools_pools` — list of `{name, driver, description,
  config}` entries. `config.source` is required per entry.
- `lxd_storage_pools_lxd_socket_path`.
- `lxd_storage_pools_flow_control_pools`.

**Dependencies (`meta/main.yml`).**
- `lxd_project` — pulls in `lxd_host` and `base_system` through its
  own meta chain.

**Runtime artefacts.**
- LXD storage pool(s) per `lxd_storage_pools_pools`, e.g.
  `capi-fast` btrfs on the operator-supplied block device. LXD
  replaces `config.source` with the filesystem UUID after first
  mount and stashes the original under `config.volatile.initial_source`.

**Tags.** `lxd_storage_pools` / `lxd-storage-pools` plus
`lxd_storage_pools_preflight`, `lxd_storage_pools_pools`,
`lxd_storage_pools_healthchecks`.

**Plan reference.**
[`§13.4`](../plans/PLAN-stage1-1.md).

### `lxd_network_int_managed`

**What it does.** Creates and configures the k8s-lab internal
managed bridge — `capi-int` by default — that provides dual-stack
DHCPv4 / IPv6 RA + DHCPv6 and NAT egress for every CAPN node's
internal NIC. Bridges live in the **default** LXD project (LXD
rejects `bridge` networks in non-default projects); `capi-lab`
references them through its `features.networks=false` inheritance.
The substrate-required NAT/DHCP baseline (`ipv4.nat=true`,
`ipv4.dhcp=true`, `ipv6.nat=true`, `ipv6.dhcp=true`) is hardcoded in
`vars/main.yml` and merged on top of each network entry's
user-supplied `config` — required keys always win the combine.

**Public inputs.**
- `lxd_network_int_managed_networks` — list of `{name, type,
  description, config}` entries. Default ships `capi-int` with
  `ipv4.address: 10.77.0.1/24` and `ipv6.address: fd42:77:1::1/64`.
- `lxd_network_int_managed_lxd_socket_path`.
- `lxd_network_int_managed_flow_control_networks`.

**Dependencies (`meta/main.yml`).**
- `lxd_project` — `features.networks=false` is what lets the
  default-project bridges resolve from `capi-lab`.

**Runtime artefacts.**
- Managed LXD bridge `capi-int` (default) in the LXD default
  project, with NAT44/NAT66, DHCPv4, IPv6 RA + DHCPv6 active. Host
  interface name = network name (≤15 chars, IFNAMSIZ).

**Tags.** `lxd_network_int_managed` / `lxd-network-int-managed`
plus `lxd_network_int_managed_preflight`,
`lxd_network_int_managed_networks`,
`lxd_network_int_managed_healthchecks`.

**Plan reference.**
[`§13.5`](../plans/PLAN-stage1-1.md).

### `lxd_profiles`

**What it does.** Creates the four substrate LXD profiles inside
the `capi-lab` project: `capi-base` (root disk on `capi-fast` +
internal NIC on `capi-int`, applied to every instance),
`capi-bootstrap` (nesting + idmap-isolated unprivileged for the
bootstrap k3s container), `capi-controlplane` and `capi-worker`
(both carrying the CAPN unprivileged kubeadm baseline — nesting,
idmap isolation, the required syscall intercepts, kernel modules,
`raw.lxc` apparmor unconfine — plus an external NIC on `br-ext6`).
The substrate-required config + device baseline is hardcoded in
`vars/main.yml`; consumers extend it with per-profile
`*_extra_config` / `*_extra_devices` dicts that win on collision.
The role does **not** populate `cloud-init.user-data` /
`cloud-init.vendor-data` — those slots belong to the chart layer
(`charts/capi-cluster-class`, plan
[`§16.2`](../plans/PLAN-stage1-3.md) /
[`§16.3`](../plans/PLAN-stage1-3.md)), which delivers the eth1 RA
reception baseline as `KubeadmConfigSpec.files` `write_files`.

**Public inputs.**
- `lxd_profiles_project` — must match `lxd_project_name`.
- `lxd_profiles_storage_pool`, `lxd_profiles_internal_network`,
  `lxd_profiles_external_bridge` — re-point every profile's device
  references with one set of values.
- `lxd_profiles_internal_ifname` (default `eth0`) and
  `lxd_profiles_external_ifname` (default `eth1`).
- Per-profile extras: `lxd_profiles_capi_{base,bootstrap,controlplane,worker}_extra_{config,devices}`.
- `lxd_profiles_lxd_socket_uri`.
- `lxd_profiles_flow_control_profiles`.

**Dependencies (`meta/main.yml`).**
- `lxd_storage_pools` — provides the pool the `capi-base` root disk
  references.
- `lxd_network_int_managed` — provides the internal bridge the
  `capi-base` NIC references.

**Runtime artefacts.**
- Four LXD profiles in `capi-lab`: `capi-base`, `capi-bootstrap`,
  `capi-controlplane`, `capi-worker`. CAPN machine templates
  reference these by name at Terraform plan/apply time.
- When a baseline value changes, the role lists running instances
  in the project that reference the affected profile and restarts
  them via `community.general.lxd_container state=restarted` (see
  the role's caveat about this re-run blind spot).

**Tags.** `lxd_profiles` / `lxd-profiles` plus
`lxd_profiles_preflight`, `lxd_profiles_compose`,
`lxd_profiles_profiles`, `lxd_profiles_healthchecks`.

**Plan reference.**
[`§13.6`](../plans/PLAN-stage1-1.md).

---

## Phase 3: Bootstrap LXC

A single role brings up the LXC container the bootstrap k3s
cluster will live in.

### `lxd_bootstrap_instance`

**What it does.** Creates and starts the bootstrap LXC instance —
`capi-bootstrap-0` by default — inside `capi-lab`. The instance is
launched from `images:debian/13/cloud` (Canonical's LXD
simplestreams remote) so the cached rootfs matches every other
container LXD spawns in the project. The role always applies the
substrate-required profiles `capi-base` and `capi-bootstrap`
(hardcoded in `vars/main.yml`) and appends extras from
`lxd_bootstrap_instance_extra_profiles` left-to-right. Per-instance
config and device overlays go through
`lxd_bootstrap_instance_config` / `lxd_bootstrap_instance_devices`
and are passed straight into `community.general.lxd_container`.
The role owns its own readiness gate (`tasks/wait_ready.yml`),
polling LXD REST for a non-link-local IPv4 on a single named
interface (default `eth0`) — the stock `wait_for_ipv4_addresses`
flag was dropped because it polls every NIC and hangs on the
inner CNI veth-pairs k3s creates.

**Publishing the API outside the host.** Host firewall is
out-of-project-scope (plan
[`§11.4`](../plans/PLAN-stage1-common.md)). To expose the
container's k3s API on a host-side port, consumers pass an LXD
proxy device through `lxd_bootstrap_instance_devices`, e.g.:

```yaml
lxd_bootstrap_instance_devices:
  k3s-api:
    type:    proxy
    listen:  "tcp:0.0.0.0:16443"
    connect: "tcp:127.0.0.1:6443"
    bind:    host
```

No nftables/iptables rules are written anywhere on the host.

**Public inputs.**
- `lxd_bootstrap_instance_name` (default `capi-bootstrap-0`).
- `lxd_bootstrap_instance_project`.
- `lxd_bootstrap_instance_extra_profiles`.
- `lxd_bootstrap_instance_image_server` /
  `_image_protocol` / `_image_alias`.
- `lxd_bootstrap_instance_config`,
  `lxd_bootstrap_instance_devices`.
- `lxd_bootstrap_instance_state` (`started` / `stopped` / `absent`).
- `lxd_bootstrap_instance_readiness_ifname`,
  `lxd_bootstrap_instance_wait_timeout`.
- `lxd_bootstrap_instance_flow_control_instance`.

**Dependencies (`meta/main.yml`).**
- `lxd_profiles` — transitively pulls
  `lxd_storage_pools`, `lxd_network_int_managed`,
  `lxd_project`, `lxd_host`, `base_system`.

**Runtime artefacts.**
- LXC instance `capi-bootstrap-0` (default) in `capi-lab`, running,
  with `capi-base` + `capi-bootstrap` profiles applied and any
  per-instance proxy / device overlay attached.
- Image cache pull on first run (cold-cache may take tens of
  seconds).

**Tags.** `lxd_bootstrap_instance` / `lxd-bootstrap-instance` plus
`lxd_bootstrap_instance_preflight`,
`lxd_bootstrap_instance_instance`,
`lxd_bootstrap_instance_wait_ready`,
`lxd_bootstrap_instance_healthchecks`.

**Plan reference.**
[`§13.7`](../plans/PLAN-stage1-1.md).

---

## Phase 4: Bootstrap management cluster

Three roles run k3s inside `capi-bootstrap-0`, install CAPI/CAPN on
top of it, and materialise the LXD identity Secret CAPN reads to
talk to the host LXD daemon.

### `bootstrap_k3s`

**What it does.** Installs k3s inside `capi-bootstrap-0` and brings
the single-node bootstrap cluster up. The role pushes the host's
`/opt/capi-lab/bin/k3s` (laid by `binary_fetch`) into the container
at `/usr/local/bin/k3s` via `lxc file push`, renders a minimal
systemd unit + env file, enables and starts `k3s.service`, then
polls `k3s kubectl get nodes` until the node reports Ready.

The substrate-required server flags are hardcoded in
`vars/main.yml` — `--disable=traefik` and `--disable=servicelb`
(plan [`§2.9`](../plans/PLAN-stage1-common.md) /
[`§5.5`](../plans/PLAN-stage1-common.md) deliver ingress and
LoadBalancer through Helm releases, and k3s' bundled versions
would race the add-ons pass), plus `KubeletInUserNamespace=true`
(plan [`§2.8`](../plans/PLAN-stage1-common.md) hard-locks
unprivileged LXC; kubelet would otherwise crash on `/dev/kmsg`),
and the dual-stack pod / service CIDRs and cluster DNS plan
[`§13.9`](../plans/PLAN-stage1-1.md) /
[`§15.2`](../plans/PLAN-stage1-2.md) require so CAPI controllers
can reach IPv6-addressed workload-cluster LB endpoints. Idempotence
is earned per-step: binary push compares sha256 between host and
container before calling `lxc file push`; systemd unit + env are
rendered, diffed against in-container content, and pushed only on
drift.

**Public inputs.**
- `bootstrap_k3s_project`, `bootstrap_k3s_instance_name`.
- `bootstrap_k3s_lxc_cli` (default `/snap/bin/lxc`).
- `bootstrap_k3s_extra_disable_components` — additive on top of the
  required `traefik`/`servicelb` baseline.
- `bootstrap_k3s_tls_san` — additional kube-apiserver SANs.
- `bootstrap_k3s_token`.
- `bootstrap_k3s_extra_kubelet_feature_gates` — merged into the
  same `--kubelet-arg=feature-gates` list as the required gates;
  cannot remove them.
- `bootstrap_k3s_extra_args` — verbatim ExecStart appendix.
- `bootstrap_k3s_wait_retries`, `bootstrap_k3s_wait_delay`.
- `bootstrap_k3s_flow_control_{install,service}`.

**Dependencies (`meta/main.yml`).**
- `binary_fetch` — provides `/opt/capi-lab/bin/k3s`.
- `lxd_bootstrap_instance` — provides the running container.

**Runtime artefacts.**
- Inside `capi-bootstrap-0`:
  - `/usr/local/bin/k3s` (mode `0755`, sha256-pinned).
  - `/etc/systemd/system/k3s.service`.
  - `/etc/default/k3s`.
  - `/etc/rancher/k3s/k3s.yaml` (mode
    `bootstrap_k3s_write_kubeconfig_mode`, default `0644`) — the
    raw, in-container kubeconfig.
  - `k3s.service` enabled and active.
- On the host: persistent staging dir
  `{{ k8s_lab_opt_root }}/etc/bootstrap_k3s/` for the rendered unit
  + env file used by the diff path.

**Tags.** `bootstrap_k3s` / `bootstrap-k3s` plus
`bootstrap_k3s_preflight`, `bootstrap_k3s_install`,
`bootstrap_k3s_service`, `bootstrap_k3s_healthchecks`.

**Plan reference.**
[`§13.9`](../plans/PLAN-stage1-1.md) and
[`§15.2`](../plans/PLAN-stage1-2.md).

### `bootstrap_clusterctl`

**What it does.** Turns the bare bootstrap k3s cluster into a CAPI
management cluster. The role:

1. fetches the in-container kubeconfig out of
   `capi-bootstrap-0` via `lxc file pull`, rewrites every
   `clusters[].cluster.server` to point at the container's
   internal IPv4 (read live from LXD on
   `bootstrap_clusterctl_container_ifname`, default `eth0`) instead
   of the in-container `127.0.0.1`, and stages it on the host at
   `{{ k8s_lab_opt_root }}/etc/bootstrap_clusterctl/bootstrap.kubeconfig`
   with mode `0600`;
2. renders a pinned `clusterctl.yaml` declaring the CAPN provider
   entry (`incus:<version>`);
3. runs `clusterctl init --infrastructure incus:<version>` once,
   pre-checking the CAPN controller Deployment via `kubectl` and
   skipping when present (since `clusterctl init` is not
   idempotent);
4. waits for cert-manager + CAPI/CAPN controller Deployments to
   report `Available`;
5. asserts `clusterctl get providers` returns the four expected
   provider types.

The CAPN provider name (`incus`) and the in-container kubeconfig
path are substrate-locked in `vars/main.yml`; only the version and
the upstream URL (for airgap mirrors) are tunable on the public
surface.

**Public inputs.**
- `bootstrap_clusterctl_capn_version` (default sources from
  `k8s_lab_capn_provider_version`).
- `bootstrap_clusterctl_capn_provider_url` — overridable for airgap
  mirrors.
- `bootstrap_clusterctl_cluster_topology_enabled` — sets
  `CLUSTER_TOPOLOGY=true` on the init invocation; default `true`.
- `bootstrap_clusterctl_extra_providers` and
  `bootstrap_clusterctl_extra_init_flags` — additional providers /
  flags on top of the CAPN baseline.
- `bootstrap_clusterctl_extra_wait_deployments` — extra Deployments
  the post-init readiness loop polls.
- `bootstrap_clusterctl_init_timeout`,
  `bootstrap_clusterctl_wait_retries`,
  `bootstrap_clusterctl_wait_delay`.
- `bootstrap_clusterctl_flow_control_{kubeconfig,config,init}`.

**Dependencies (`meta/main.yml`).**
- `bootstrap_k3s` — transitively pulls `binary_fetch`,
  `lxd_bootstrap_instance`, and the rest of the substrate.

**Runtime artefacts.**
- On the host:
  - `{{ k8s_lab_opt_root }}/etc/bootstrap_clusterctl/bootstrap.kubeconfig` (mode `0600`).
  - `{{ k8s_lab_opt_root }}/etc/bootstrap_clusterctl/clusterctl.yaml` (mode `0600`).
- Inside the bootstrap k3s cluster:
  - cert-manager namespace and Deployments.
  - `capi-system`, `capi-kubeadm-bootstrap-system`,
    `capi-kubeadm-control-plane-system`, `capn-system` namespaces
    and their controller Deployments, all `Available`.

**Tags.** `bootstrap_clusterctl` / `bootstrap-clusterctl` plus
`bootstrap_clusterctl_preflight`,
`bootstrap_clusterctl_kubeconfig`,
`bootstrap_clusterctl_config`,
`bootstrap_clusterctl_init`,
`bootstrap_clusterctl_healthchecks`.

**Plan reference.**
[`§13.10`](../plans/PLAN-stage1-1.md) and
[`§15.3`](../plans/PLAN-stage1-2.md).

### `bootstrap_capn_secret`

**What it does.** Materialises the LXD identity Secret CAPN reads
to talk to the host LXD daemon. Three pieces, in order:

1. **LXD HTTPS listener.** PATCHes `core.https_address` so the
   daemon listens on a single bind address — by default, the IPv4
   gateway of the LXD-managed internal bridge (`capi-int` by
   default; auto-resolved from
   `bootstrap_capn_secret_internal_network_name`). That keeps the
   API endpoint reachable from the project's internal network and
   invisible on the host's external NICs. Port `8443` is
   substrate-locked (CAPN convention).
2. **Client cert + LXD trust.** Generates a self-signed client
   TLS cert/key with `community.crypto`, then trusts the cert into
   LXD as a `client`-type entry **restricted to the project named
   by `k8s_lab_project_name`** so CAPN cannot touch foreign
   projects. Existing trust entries with mismatched project
   restriction fail loud rather than silently relax scope.
3. **Kubernetes Secret fanout.** Renders + applies the CAPN
   identity Secret in **every** namespace listed in
   `bootstrap_capn_secret_namespaces` (sourced from
   `k8s_lab_capn_identity_namespaces`, default `["capi-clusters"]`).
   Each Secret carries the five identity-spec keys (`server`,
   `server-crt`, `client-crt`, `client-key`, `project`). Each
   target namespace is created first if missing. The
   `clusterctl.cluster.x-k8s.io/move=true` label is attached by
   default so `clusterctl move` carries the Secrets across at
   pivot time.

The Secret is **not** placed in `capn-system` — CAPN v1alpha2
`LXCCluster.spec.secretRef` does not carry a namespace field, so
CAPN looks the Secret up in the namespace of the LXCCluster CR
(i.e. the workload Cluster CR's namespace). The fanout matches
that lookup.

**Public inputs.**
- `bootstrap_capn_secret_lxd_project` (sources from
  `k8s_lab_project_name`).
- `bootstrap_capn_secret_internal_network_name` (sources from
  `k8s_lab_internal_network_name`).
- `bootstrap_capn_secret_lxd_https_bind_address` — empty (default)
  triggers auto-resolve; literal `<ip>:<port>` skips it.
- `bootstrap_capn_secret_name` (sources from
  `k8s_lab_infrastructure_secret_name`, default `incus-identity`).
- `bootstrap_capn_secret_namespaces` (sources from
  `k8s_lab_capn_identity_namespaces`).
- `bootstrap_capn_secret_pivot_enabled` — default `true`; flip to
  `false` only for ad-hoc substrate-only test runs.
- Cert metadata: `_cn`, `_country`, `_organization`,
  `_validity_days`, `_key_size`, `_key_type`.
- `bootstrap_capn_secret_kubeconfig_path`.
- `bootstrap_capn_secret_flow_control_{lxd_https,client_cert,lxd_trust,secret}`.

**Dependencies (`meta/main.yml`).**
- `bootstrap_clusterctl` — provides the kubeconfig and the
  `capn-system` namespace `clusterctl init` creates.

**Runtime artefacts.**
- On the host:
  - `{{ k8s_lab_opt_root }}/etc/bootstrap_capn_secret/client.key`
    (mode `0600`).
  - `client.csr`, `client.crt` (mode `0644`).
  - `secret.yaml` — staged manifest copy.
- LXD-side:
  - `core.https_address` set to the bridge gateway (or operator
    override).
  - `lxc config trust list` entry
    `bootstrap_capn_secret_trust_name` (default `k8slab-capn`),
    `client` type, `restricted: true`,
    `projects: [<lxd_project>]`.
- Inside the bootstrap k3s cluster:
  - For each namespace in `bootstrap_capn_secret_namespaces`: the
    namespace itself plus a `Secret` named
    `bootstrap_capn_secret_name`, carrying the five identity keys
    and the `clusterctl.cluster.x-k8s.io/move=true` label (when
    `pivot_enabled=true`).

**Tags.** `bootstrap_capn_secret` / `bootstrap-capn-secret` plus
section tags `bootstrap_capn_secret_preflight`,
`bootstrap_capn_secret_lxd_https`,
`bootstrap_capn_secret_client_cert`,
`bootstrap_capn_secret_lxd_trust`,
`bootstrap_capn_secret_secret`,
`bootstrap_capn_secret_healthchecks`.

**Plan reference.**
[`§13.11`](../plans/PLAN-stage1-1.md) and
[`§15.4`](../plans/PLAN-stage1-2.md).

---

## Phase 4 close: Artefact handoff

One role closes Phase 4 by shipping the management-cluster handoff
bundle from the LXD host to the runner.

### `export_artifacts`

**What it does.** Writes the runner-side handoff bundle:

- `.artifacts/mgmt.kubeconfig` — admin kubeconfig for the active
  management cluster. On the canonical first invocation that is
  the bootstrap k3s cluster, sourced from
  `{{ k8s_lab_opt_root }}/etc/bootstrap_clusterctl/bootstrap.kubeconfig`.
  After pivot the same file is overwritten in place by the
  post-pivot re-emit invocation.
- `.artifacts/mgmt.auto.tfvars.json` — the fact bundle Phase 5
  Terraform fixtures consume with explicit `-var-file` wiring because
  Terraform auto-loads `*.auto.tfvars.json` only from the current
  Terraform root. Keys mirror the `k8s_lab_*` global contract verbatim.
- `.artifacts/clusters/` — created empty; reserved for per-workload
  kubeconfig debug copies written by `e2e-local` verify.

The role runs on the LXD host through the
`bootstrap_capn_secret` meta-dep chain, but the artefact-write
tasks flip to `delegate_to: localhost, become: false, run_once:
true` so files land on the runner with mode `0600` and runner-user
ownership (plan
[`§11.1`](../plans/PLAN-stage1-common.md)).

**Used twice in the canonical flow.** Once after Phase 4 (ships the
bootstrap cluster's creds), once after pivot (ships mgmt-1's
creds). The second invocation sets
`export_artifacts_run_meta_chain: false` to skip the substrate
chain — by then the substrate is already up, and after
`cleanup_bootstrap` the bootstrap LXC may already be gone.

The optional `export_artifacts_mgmt_api_server_url` rewrite lets
runners that are not on the LXD host (i.e. need the LXD proxy
listener URL) replace `clusters[].cluster.server` in the shipped
kubeconfig before write.

**Public inputs.**
- `export_artifacts_root` — REQUIRED, absolute runner-side path.
- `export_artifacts_run_meta_chain` — `true` for canonical first
  invocation, `false` for the post-pivot re-emit.
- `export_artifacts_mgmt_kubeconfig_source` — host-side source.
- `export_artifacts_mgmt_api_server_url` — non-empty triggers
  in-place server URL rewrite of the shipped kubeconfig.
- `export_artifacts_tfvars_extra` — consumer dict merged on top of
  the baseline tfvars (baseline keys win on collision).
- `export_artifacts_flow_control_{mgmt_kubeconfig,tfvars}`.

**Dependencies (`meta/main.yml`).**
- `bootstrap_capn_secret` — gated by
  `when: export_artifacts_run_meta_chain | default(true) | bool`,
  so the post-pivot re-emit invocation skips the substrate chain.

**Runtime artefacts.**
- `<export_artifacts_root>/mgmt.kubeconfig` (mode `0600`).
- `<export_artifacts_root>/mgmt.auto.tfvars.json` (mode `0600`).
- `<export_artifacts_root>/clusters/` (mode `0700`).

**Tags.** `export_artifacts` / `export-artifacts` plus
`export_artifacts_preflight`,
`export_artifacts_mgmt_kubeconfig`,
`export_artifacts_tfvars`,
`export_artifacts_healthchecks`.

**Plan reference.**
[`§15.6`](../plans/PLAN-stage1-2.md).

---

## Phase 7: Pivot

One role drives the canonical CAPI bootstrap-and-pivot flow,
relocating the CAPI graph from the bootstrap k3s cluster to the
self-hosted target management cluster (mgmt-1).

### `pivot_clusterctl_move`

**What it does.** Three steps:

1. **Materialise a runner-reachable target kubeconfig.** Reads the
   `<cluster>-kubeconfig` Secret produced on the bootstrap cluster
   by `charts/capi-workload-cluster`, rewrites
   `clusters[].cluster.server` to `https://<lxd-host>:<api-proxy-port>`
   (the port comes from the `k8s-lab.io/api-proxy-port` annotation
   the chart writes onto the Cluster CR), pins
   `tls-server-name: kubernetes.default.svc`, and stages the
   result at
   `{{ k8s_lab_opt_root }}/etc/pivot_clusterctl_move/mgmt.kubeconfig`
   with mode `0600`.
2. **`clusterctl init --infrastructure incus:<ver>`** against the
   target kubeconfig — same provider set the bootstrap cluster
   already runs.
3. **`clusterctl move --to-kubeconfig`** to relocate every CAPI
   CR (Cluster, ClusterClass, *Templates, KubeadmControlPlane,
   MachineDeployment, owned Machines + Secrets) from bootstrap
   onto target. The `move=true` label on the CAPN identity Secret
   (set by `bootstrap_capn_secret`) carries the Secret across.

The role is idempotent across every (init done? move done?)
combination — it probes the target for `capn-system/capn-controller-manager`
to gate `init`, and the bootstrap for the source Cluster CR to
gate `move`. Re-running after a successful pivot is reliably
`changed=false`.

**Out of scope.** Target mgmt cluster CREATION (Cluster CR +
ClusterClass + Templates + LB instance + CNI) is owned by the
chart layer (`charts/capi-cluster-class` +
`charts/capi-workload-cluster`) driven by the orchestrator;
bootstrap deletion is owned by `cleanup_bootstrap`; workload
cluster creation post-pivot is just another `make deploy-workload`
against the new mgmt kubeconfig.

**Public inputs.**
- `pivot_clusterctl_move_target_cluster_name` (sources from
  `k8s_lab_management_cluster_name`).
- `pivot_clusterctl_move_target_cluster_namespace`
  (default `capi-clusters`).
- `pivot_clusterctl_move_target_api_address` (sources from
  `k8s_lab_lxd_host_address`) — REQUIRED, runner-reachable LXD
  host address.
- `pivot_clusterctl_move_capn_version`,
  `pivot_clusterctl_move_capn_provider_url`.
- `pivot_clusterctl_move_cluster_topology_enabled`.
- `pivot_clusterctl_move_extra_providers`,
  `_extra_init_flags`, `_extra_wait_deployments`.
- `pivot_clusterctl_move_init_timeout` (default `600`),
  `_move_timeout` (default `1200`).
- `pivot_clusterctl_move_wait_target_kubeconfig_retries/_delay`,
  `_wait_retries/_delay`.
- `pivot_clusterctl_move_flow_control_{target_kubeconfig,config,init,move}`.

**Dependencies (`meta/main.yml`).**
- `bootstrap_clusterctl` — same kubeconfig path is the input;
  cross-role coupling by value.

**Runtime artefacts.**
- On the host:
  - `{{ k8s_lab_opt_root }}/etc/pivot_clusterctl_move/mgmt.kubeconfig` (mode `0600`).
  - `{{ k8s_lab_opt_root }}/etc/pivot_clusterctl_move/clusterctl.yaml` (mode `0600`).
- On the target mgmt cluster: cert-manager + CAPI / CABPK / KCP /
  CAPN providers, plus every CAPI CR previously on bootstrap.
- On the bootstrap cluster: the migrated CRs are gone (move
  deletes from source after creating on target).

**Tags.** `pivot_clusterctl_move` / `pivot-clusterctl-move` plus
`pivot_clusterctl_move_preflight`,
`pivot_clusterctl_move_target_kubeconfig`,
`pivot_clusterctl_move_config`,
`pivot_clusterctl_move_init`,
`pivot_clusterctl_move_move`,
`pivot_clusterctl_move_healthchecks`.

**Plan reference.**
[`§18.2`](../plans/PLAN-stage1-5.md) (and [`§18.1`](../plans/PLAN-stage1-5.md) for the broader pivot context).

---

## Phase 8: Destroy

One role removes the bootstrap LXC instance once the pivot has
completed and the target mgmt cluster is operating self-hosted.

### `cleanup_bootstrap`

**What it does.** Deletes the bootstrap container
(`capi-bootstrap-0` by default) inside the `capi-lab` LXD project.
Since the instance-level proxy device that publishes the bootstrap
k3s API (e.g. `k3s-api`, set via `lxd_bootstrap_instance_devices`)
is an instance property, LXD removes it with the container — so
"bootstrap API publication" in plan
[`§19.1`](../plans/PLAN-stage1-6.md) is covered by the same
step. When `cleanup_bootstrap_artifacts_root` is set and
`cleanup_bootstrap_remove_artifacts=true` (the default), the role
also wipes that directory on the runner via `delegate_to:
localhost` — those files (kubeconfig, CAPN secret, trust
material) point at a now-dead endpoint and would leak into the
next redeploy. Empty path leaves the artefacts step a no-op.

The role probes LXD availability first and gracefully skips when
the daemon / project / instance is already absent. Re-runs after a
successful cleanup, and first-time runs against a
never-bootstrapped host, both report `changed=false`.

**Out of scope.** Workload / management cluster teardown, Helm
add-on removal, LXD project / pool / managed-network / profile
destruction, and host-side bridge removal. Those belong to the
broader Phase 8 destroy orchestrator (plan
[`§19.2`](../plans/PLAN-stage1-6.md)), not this role.

**Public inputs.**
- `cleanup_bootstrap_project` (default `capi-lab`).
- `cleanup_bootstrap_instance_name` (default `capi-bootstrap-0`).
- `cleanup_bootstrap_force_stop` — default `true` (leftover state
  is worse than a hard stop; flip to `false` for graceful-only
  cleanup).
- `cleanup_bootstrap_delete_timeout`.
- `cleanup_bootstrap_remove_artifacts`,
  `cleanup_bootstrap_artifacts_root`.
- `cleanup_bootstrap_lxd_socket_uri`,
  `cleanup_bootstrap_lxd_socket_path`.
- `cleanup_bootstrap_flow_control_{instance,artifacts}`.

**Dependencies (`meta/main.yml`).**
None — by design. Cleanup is reverse-motion; it must not
re-install LXD / project / pool / profiles just to delete one
instance. If the substrate is already gone the role is a no-op.
This is the only role in the repo with no `meta/main.yml` deps.

**Runtime artefacts.**
- Bootstrap container `capi-bootstrap-0` and its proxy device
  removed from `capi-lab`.
- When configured, `<cleanup_bootstrap_artifacts_root>/` removed
  from the runner.

**Tags.** `cleanup_bootstrap` / `cleanup-bootstrap` plus
`cleanup_bootstrap_preflight`,
`cleanup_bootstrap_instance`,
`cleanup_bootstrap_artifacts`,
`cleanup_bootstrap_healthchecks`.

**Plan reference.**
[`§19.1`](../plans/PLAN-stage1-6.md).

---

## Role dependency graph

The 14 roles connect through `meta/main.yml` dependencies into a
single rooted DAG. The graph below shows the **direct** deps each
role declares (plan
[`§2.6.5`](../plans/PLAN-stage1-common.md) bans transitive
re-declaration, so the chain is explicit one-edge-at-a-time):

```text
base_system
└── lxd_host
    └── lxd_project
        ├── lxd_storage_pools
        │   └── lxd_profiles ←─┐
        ├── lxd_network_int_managed
        │   └── lxd_profiles ←─┘
        │       └── lxd_bootstrap_instance
        │           └── bootstrap_k3s
        │               └── bootstrap_clusterctl
        │                   ├── bootstrap_capn_secret
        │                   │   └── export_artifacts*
        │                   └── pivot_clusterctl_move
        │
        └── (pulls into)
            binary_fetch  ──── (also pulled by) ──── bootstrap_k3s

cleanup_bootstrap   (no deps — reverse-motion)
```

(* `export_artifacts` declares the `bootstrap_capn_secret` dep
guarded by `when: export_artifacts_run_meta_chain | bool`; the
post-pivot re-emit invocation flips it off.)

`binary_fetch` declares only `base_system` directly; `bootstrap_k3s`
pulls it in alongside `lxd_bootstrap_instance`.
`lxd_profiles` declares both `lxd_storage_pools` and
`lxd_network_int_managed` because neither implies the other.

When an operator runs the canonical end-to-end flow (the single
Molecule scenario `tests/molecule/e2e-local`), the chain unfolds in
the order shown in plan
[`§3.1`](../plans/PLAN-stage1-common.md):

```text
base_system → lxd_host → lxd_project → lxd_storage_pools
  → lxd_network_int_managed → lxd_profiles
  → lxd_bootstrap_instance → binary_fetch
  → bootstrap_k3s → bootstrap_clusterctl → bootstrap_capn_secret
  → export_artifacts                                      (Phase 4 close)
  → [Helm: capi-cluster-class + capi-workload-cluster +
          cni-calico + metallb + metallb-config on bootstrap]
                                                         (Phase 5)
  → [helm test on three releases]                        (Phase 6 — Gate A/B)
  → pivot_clusterctl_move                                (Phase 7)
  → export_artifacts (run_meta_chain: false)             (re-emit)
  → cleanup_bootstrap                                    (Phase 8 — bootstrap teardown)
  → [Helm + Terraform deploy of workload cluster]        (Phase 9)
```

Most operators do not invoke roles directly. The Molecule e2e
scenario, the per-role delegated-driver scenarios (one per role
under `tests/molecule/<role>/`), and consumer-repo playbooks all
use `include_role` / `roles:` lists that resolve the meta chain
automatically.

---

## Conventions reminder

The roles in this chapter are not free-form; every one of them
follows the same authoring contract from plan
[`§2.6`](../plans/PLAN-stage1-common.md). When you read or modify
a role, expect the following:

- **Native-first execution
  ([`§2.6.1`](../plans/PLAN-stage1-common.md)).** Tasks use
  `ansible.builtin.*` and collection modules first
  (`community.general`, `community.crypto`, `kubernetes.core`,
  `ansible.posix`, `ansible.builtin.uri` for the LXD REST surface).
  `shell` / `command` / `script` / `raw` and mutating `uri` calls
  appear only where no module covers the operation, and each is
  wrapped to be idempotent (pre-check + `when:` / `creates:` /
  diff). `changed_when: false` on a mutating step is forbidden.
  Documented shell fallbacks: `lxc file push` / `lxc exec` in
  `bootstrap_k3s`, `clusterctl init|move` in
  `bootstrap_clusterctl` and `pivot_clusterctl_move`,
  `snap set system refresh.*` in `lxd_host`, `lxc project show` in
  `lxd_project` healthchecks.

- **Variable contract
  ([`§2.6.2`](../plans/PLAN-stage1-common.md)).** Public, exposed
  variables are prefixed with the role name
  (`base_system_*`, `lxd_host_*`, …). Internal / derived facts use
  the underscore-prefixed `_<role>_*` form and stay inside the
  role. Cross-role couplings are by *value*, not by reading
  another role's prefixed var (plan
  [`§2.6.5`](../plans/PLAN-stage1-common.md) bans
  `<other_role>_*` reads). Globals consumed by multiple roles use
  the project-wide `k8s_lab_*` prefix.

- **Substrate-required values are hardcoded.** Anything whose
  empty / wrong override would silently break the role lives in
  `vars/main.yml` under `_<role>_required_*` and is **not**
  exposed in `defaults/main.yml`. Consumers extend with
  `*_extra_*` knobs whose values are merged on top of the
  baseline — required keys win the merge. This applies to APT
  packages, sysctl knobs, kernel modules, LXD project
  restrictions, network NAT/DHCP keys, btrfs mount options,
  profile baselines, k3s server flags, CAPN provider names, and
  identity-Secret keys.

- **Naming, tags, registers, flow control
  ([`§2.6.3`](../plans/PLAN-stage1-common.md)).** Top-level and
  section tags accept both underscore and hyphen spellings (e.g.
  `lxd_host` and `lxd-host`). Flow-control toggles are coarse —
  role-level (`<role>_enabled`) and section-level
  (`<role>_flow_control_<section>`) only; no per-task switches.
  Registers and facts follow `_<role>_*` naming.

- **Handlers contract
  ([`§2.6.4`](../plans/PLAN-stage1-common.md)).** Roles that need
  service / daemon side-effects (e.g. `lxd_host`'s
  `systemd-networkd reload`, `bootstrap_k3s`'s `daemon-reload` and
  service-restart) declare them in `handlers/main.yml` and notify
  via the standard `notify:` keyword.

- **Role dependencies declared in `meta/main.yml`
  ([`§2.6.5`](../plans/PLAN-stage1-common.md)).** Every ordering
  rule lives in the role's own `meta/main.yml`. Consumers do not
  emulate ordering with `prepare.yml` / `pre_tasks` / hand-rolled
  `include_role` chains. Transitive deps are not re-declared
  (`base_system` is pulled by `lxd_host`; downstream roles do not
  re-state it). The single exception is `cleanup_bootstrap`,
  which has no deps by design — it is reverse-motion and must not
  re-install the substrate just to delete one instance.

When in doubt about a value or behaviour, the role's own
`README.md` and `defaults/main.yml` are authoritative for *what*
the role does; the linked plan section is authoritative for *why*
it does it that way.
