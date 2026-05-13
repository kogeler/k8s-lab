# 08 — Configuration reference

This chapter is a flat lookup of the project globals, primary
consumer-facing role inputs, Terraform inputs/outputs, and chart values
in k8s-lab.
Variables fall into a strict three-tier hierarchy:

1. **Project globals** — `k8s_lab_*` (and a small set of `lxd_host_*` that
   live in `host_vars` of role `lxd_host` rather than in a `k8s_lab_`
   namespace). These are the public interface contract of the repo and
   come from `PLAN-stage1-common.md` §8.
2. **Role-scoped inputs** — `<role_name>_*`. Public Ansible defaults from
   each role's `defaults/main.yml`; consumer-overridable.
3. **Role-private** — `_<role_name>_*`. Internal facts and substrate-
   required hardcoded baselines kept inside `vars/main.yml` of each
   role. **Not documented here** by design — they are role-internal and
   subject to change without a major bump.

Helm chart values (`charts/<chart>/values.yaml`) and Terraform module
inputs (`terraform/modules/workload_cluster/variables.tf`) are
consumer-facing too — they are documented in their own sections below.

Every value cited in this chapter is read directly from a source file
in this repo; if a row drifts from the source, the source wins. For the
complete raw role defaults, read the role's `defaults/main.yml`.

---

## Project globals (`k8s_lab_*`)

Source of truth: `PLAN-stage1-common.md` §8 (master typed-variables
contract). Versions inline in §8 are reconciled against §8a (verified
version log) — see the dedicated table at the end of this chapter.

### Global identity

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_opt_root` | string | `/opt/capi-lab` | no | Project-wide on-host filesystem root; consumed by every Ansible role that writes under `/opt`. |
| `k8s_lab_project_name` | string | `capi-lab` | no | LXD project name; consumed by `lxd_project`, `lxd_storage_pools`, `lxd_network_int_managed`, `lxd_profiles`, `lxd_bootstrap_instance`. |

### CAPI controls

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_cluster_topology_enabled` | bool | `true` | no | Surfaces as `CLUSTER_TOPOLOGY=true` on `clusterctl init`; required for the ClusterClass / managed-topology workflow Phase 5+ depends on. |
| `k8s_lab_unprivileged_nodes` | bool | `true` | no | Hard policy switch for the §2.8 unprivileged-LXC-only rule; flipping to `false` is unsupported by every chart in this repo. |
| `k8s_lab_infrastructure_secret_name` | string | `incus-identity` | no | Name of the CAPN identity Secret materialised by `bootstrap_capn_secret` and referenced from `LXCCluster.spec.secretRef.name`; matches CAPN upstream identity-secret default. |

### Workload API endpoint reachability

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_lxd_host_address` | string | — | yes | Runner-reachable address of the LXD host. The workload kube-apiserver listens on `capi-int` IPv6 (reachable only inside LXD); the §16.4 module rewrites the workload kubeconfig to `https://<this>:<port>` where `<port>` is a per-workload Adler-32 hash of `cluster.name` (default 20000-29999, override via chart values `loadBalancer.lxc.proxyApiPort`). On local Vagrant: the Vagrant VM IP. On prod: public IP / DNS name of the LXD host. |

### Host

The `lxd_host_*` group does **not** carry the `k8s_lab_` prefix because it
is role-scoped (consumed by role `lxd_host` directly, plan §13.2).

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_host_distro` | string | `debian-13` | no | Target host distribution. The role contract gates on the Debian / Ubuntu kernel and apt baseline (Debian 13+ or Ubuntu 22.04+); see role preflight checks for the strict assertion. |
| `lxd_host_snap_channel` | string | `6/stable` | no | LXD snap channel; feature-stable per the §8a deviation (Canonical recommends LTS `5.21/stable`). |
| `lxd_host_snap_refresh_mode` | string | `hold` | no | `hold` or `timer`; hold is indefinite, timer is `snap set system refresh.timer=...`. |
| `lxd_host_snap_refresh_timer_value` | string | `fri,03:00-04:00` | no | systemd-calendar expression used when `lxd_host_snap_refresh_mode=timer`. |

### Storage

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_storage_pool_name` | string | `capi-fast` | no | LXD storage pool name; consumed by `lxd_storage_pools`, profiles' root disk, and bootstrap instance. |
| `k8s_lab_storage_driver` | string | `btrfs` | no | LXD storage driver. The repo only verifies `btrfs`; other drivers (`dir`, `lvm`, `zfs`) are nominally accepted by `lxd_storage_pools`. |
| `k8s_lab_storage_source` | string | — | yes | Path to a **block device** (`/dev/disk/by-id/...`); not a mounted filesystem. The LXD snap is AppArmor-confined and has no access to host paths outside `/var/snap/lxd/common/`. For btrfs the device must be signature-free on first converge — LXD calls `mkfs.btrfs` without `-f`. |
| `k8s_lab_storage_btrfs_mount_options` | string | `user_subvol_rm_allowed` | no | Mounted on the LXD storage pool; without it kubelet GC breaks inside unprivileged CAPN nodes. Substrate-required even when overridden in extras. |

### Networking

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_uplink_interface` | string | — | yes | Physical NIC the host-side bridge `br-ext6` attaches to; preflight rejects empty to avoid bridging the mgmt NIC by accident. |
| `k8s_lab_external_bridge_name` | string | `br-ext6` | no | Plain Linux bridge owned by `lxd_host`; LXD profiles consume it as `parent`. |
| `k8s_lab_internal_network_name` | string | `capi-int` | no | LXD-managed bridge; provides DHCPv4 + RAv6 + dual-stack NAT. |
| `k8s_lab_internal_ipv4_subnet` | string | `10.77.0.0/24` | no | IPv4 plan of `capi-int`. |
| `k8s_lab_internal_ipv6_subnet` | string | `fd42:77:1::/64` | no | IPv6 plan of `capi-int` (ULA from `fd42:77::/48`). |
| `k8s_lab_internal_ipv4_nat` | bool | `true` | no | NAT44 on capi-int egress. |
| `k8s_lab_internal_ipv6_nat` | bool | `true` | no | NAT66 on capi-int egress. |
| `k8s_lab_external_ipv6_prefix` | string | — | yes | The provider-delegated IPv6 prefix on the external segment (covers node + VIP allocations). |
| `k8s_lab_external_node_ipv6_range` | string | — | yes | Range from which CAPN-spawned nodes get their `eth1` external IPv6 (RA receive). |
| `k8s_lab_metallb_vip_range_v6` | string | — | yes | IPv6 range MetalLB allocates VIPs from; format `<from>-<to>` or `<ip>/128`. |
| `k8s_lab_guest_internal_ifname` | string | `eth0` | no | Interface name inside CAPN guests for the internal plane. |
| `k8s_lab_guest_external_ifname` | string | `eth1` | no | Interface name inside CAPN guests for the external plane. |
| `k8s_lab_guest_network_backend` | string | `systemd-networkd` | no | Network manager inside CAPN guests; only systemd-networkd is exercised. |

### Bootstrap

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_bootstrap_instance_name` | string | `capi-bootstrap-0` | no | Name of the LXC container running transient k3s + CAPI controllers before pivot. |
| `k8s_lab_k3s_version` | string | `v1.35.3+k3s1` | no | k3s release for the bootstrap cluster. Verified 2026-04-21. |
| `k8s_lab_kubectl_version` | string | `v1.35.3` | no | kubectl client binary fetched into `/opt/capi-lab/bin`. Verified 2026-04-21. |
| `k8s_lab_clusterctl_version` | string | `v1.12.5` | no | clusterctl release used by `bootstrap_clusterctl` and `pivot_clusterctl_move`. Verified 2026-04-21. |
| `k8s_lab_capn_provider_version` | string | `v0.8.5` | no | CAPN release; `clusterctl init --infrastructure incus:<this>` consumes it. Verified 2026-04-21. |

External publication of the bootstrap API cluster, when needed, is done
via an LXD proxy device on the bootstrap LXC instance — see role
`lxd_bootstrap_instance` parameter `lxd_bootstrap_instance_devices`. No
project-wide global owns this because listen/connect/bind are properties
of a specific instance, not a project-wide contract.

### Images

Both images **must** be cloud-init-capable. The `capi-cluster-class`
chart delivers the `eth1` RA reception baseline via
`KubeadmConfigSpec.files` + `preKubeadmCommands` — CABPK inlines them
into user-data `write_files`, and cloud-init applies them on first boot.

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_images_controlplane` | string | `capi:kubeadm/VERSION` | no | CAPN image ref for control-plane LXC. The literal `VERSION` is substituted by CAPN at runtime. |
| `k8s_lab_images_worker` | string | `capi:kubeadm/VERSION` | no | CAPN image ref for worker LXC. |
| `k8s_lab_images_source_policy` | string | `capn-prebuilt` | no | `capn-prebuilt` (default upstream simplestreams) or `consumer-custom` (operator-supplied image with cloud-init kept). |
| `k8s_lab_images_controlplane_fingerprint` | string | `""` | no | Optional sha256 fingerprint pin for the CP image; empty = resolve by name. |
| `k8s_lab_images_worker_fingerprint` | string | `""` | no | Optional sha256 fingerprint pin for the worker image. |

### Templates (LXCMachineTemplate public contract)

Substrate-required baselines (`capi-base` + `capi-controlplane` /
`capi-worker` from role `lxd_profiles`; `instanceType: container`;
`unprivileged: true`; `skipDefaultKubeadmProfile: true`) are baked into
the chart itself. The variables below are consumer extras only, layered
on top of the baseline.

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_controlplane_profiles_extra` | list(string) | `[]` | no | Extra LXD profiles appended after the substrate baseline for CP machines. |
| `k8s_lab_worker_profiles_extra` | list(string) | `[]` | no | Extra LXD profiles for worker machines. |
| `k8s_lab_controlplane_devices_extra` | list(string) | `[]` | no | CAPN v1alpha2 CSV device overrides; example: `eth1,type=nic,network=br-ext6`. |
| `k8s_lab_worker_devices_extra` | list(string) | `[]` | no | CSV device overrides for workers. |
| `k8s_lab_idmap_isolated` | bool | `true` | no | Forces per-instance idmap isolation; flipping to `false` is incompatible with §2.8. |
| `k8s_lab_network_files_strategy` | string | `cabpk-files` | no | How RA reception baseline lands on guests; only `cabpk-files` is implemented. |
| `k8s_lab_patch_delivery_strategy` | string | `cabpk-files-plus-patches` | no | Strategy for delivering ClusterClass patches on top of CABPK files. |

### CNI / addons

CNI is Calico, shipped as the only wrapper in the repo
(`charts/cni-calico/`). Swapping CNI = adding a sibling wrapper chart
under `charts/cni-<other>/` and a corresponding TF module input. There
is no toggle global by design.

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_helm_provider_version` | string | `3.1.1` | no | `hashicorp/helm` Terraform provider version. Verified 2026-04-21. |
| `k8s_lab_calico_chart_repository` | string | `https://docs.tigera.io/calico/charts` | no | Upstream tigera-operator repo URL. |
| `k8s_lab_calico_chart_name` | string | `tigera-operator` | no | Upstream subchart name pinned in `charts/cni-calico/Chart.yaml` dependencies. |
| `k8s_lab_calico_chart_version` | string | `v3.31.5` | no | Upstream tigera-operator chart version. Verified 2026-04-21. |
| `k8s_lab_metallb_chart_repository` | string | `https://metallb.github.io/metallb` | no | Upstream MetalLB repo URL. |
| `k8s_lab_metallb_chart_name` | string | `metallb` | no | Upstream subchart name pinned in `charts/metallb/Chart.yaml` dependencies. |
| `k8s_lab_metallb_chart_version` | string | `0.15.3` | no | Upstream MetalLB chart version. Verified 2026-04-27. |
| `k8s_lab_kube_proxy_nodeport_addresses` | list(string) | `[]` | no | NodePort bind CIDRs; empty = bind all (kubeadm default). |
| `k8s_lab_metallb_enabled` | bool | `true` | no | Coarse switch to install MetalLB. |
| `k8s_lab_metallb_interface` | string | `eth1` | no | Interface name MetalLB speaker announces VIPs on; matches `k8s_lab_guest_external_ifname`. |
| `k8s_lab_metallb_node_selector_labels` | map(string) | `{}` | no | Extra L2Advertisement nodeSelectors layered on top of substrate-required CP exclusion. |
| `k8s_lab_metallb_wrapper_chart_path` | string | `charts/metallb-config` | no | Repo-relative path to the local config wrapper chart. |

### Clusters

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_management_cluster_name` | string | `mgmt-1` | no | Self-hosted post-pivot management cluster name. |
| `k8s_lab_workload_cluster_name` | string | `lab-default` | no | Default workload Cluster CR name. |
| `k8s_lab_kubernetes_version` | string | `v1.35.0` | no | Workload + mgmt K8s version. **Bounded by CAPN simplestreams** (`https://images.linuxcontainers.org/capn/streams/v1/images.json`); picking a version not in that set fails LXCMachine creation. Verified 2026-04-25. |
| `k8s_lab_management_controlplane_count` | int | `1` | no | Mgmt cluster CP count; must be odd (CAPI stacked-etcd quorum invariant). |
| `k8s_lab_management_worker_count` | int | `2` | no | Mgmt cluster worker count; chart-required floor is **2** for `cni-calico` Gate B (pod-anti-affinity probe). |
| `k8s_lab_workload_controlplane_count` | int | `3` | no | Workload cluster CP count; must be odd. |
| `k8s_lab_workload_worker_count` | int | `2` | no | Workload cluster worker count. |

### CAPN identity Secret target namespaces

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_capn_identity_namespaces` | list(string) | `["capi-clusters"]` | no | Every namespace where workload Cluster CRs (and thus LXCCluster CRs) will be created. CAPN v1alpha2 looks up `LXCCluster.spec.secretRef.name` in the same namespace as the CR; cross-namespace lookup is not supported. The role `bootstrap_capn_secret` materialises the Secret in each listed namespace. Empty list is valid for substrate-only runs. |

### Cluster networking (dual-stack)

Pod / Service CIDRs for the workload cluster are dual-stack. Values are
bound on both ends: `charts/capi-cluster-class/values.yaml` (kubeadm
networking) and `charts/capi-workload-cluster/values.yaml`
(`spec.clusterNetwork`). Both sides must agree.

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_workload_pod_cidr_v4` | string | `10.244.0.0/16` | no | IPv4 pod CIDR (k3s defaults-compatible). |
| `k8s_lab_workload_pod_cidr_v6` | string | `fd42:77:2::/56` | no | IPv6 pod CIDR (ULA from `fd42:77::/48`). |
| `k8s_lab_workload_service_cidr_v4` | string | `10.96.0.0/16` | no | IPv4 service CIDR. |
| `k8s_lab_workload_service_cidr_v6` | string | `fd42:77:3::/112` | no | IPv6 service CIDR. |

### Local Helm chart pins

Bumping a local chart version implies a new ClusterClass / Template name
via the name-versioning pattern (§2.9).

| Name | Type | Default | Required? | Notes |
| --- | --- | --- | --- | --- |
| `k8s_lab_capi_cluster_class_chart_version` | string | `0.6.3` | no | Pinned version of `charts/capi-cluster-class`. |
| `k8s_lab_capi_workload_cluster_chart_version` | string | `0.8.0` | no | Pinned version of `charts/capi-workload-cluster`; must match the chart's `k8s-lab.io/capi-cluster-class-chart-version` annotation. |

---

## Role inputs

Each subsection lists the public, consumer-overridable inputs for one
role. `_<role>_*` private vars are intentionally omitted.

### `base_system`

Plan §13.1. Minimal Debian or Ubuntu Linux host preparation.

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `base_system_enabled` | bool | `true` | Whole-role toggle; preflight still runs when false. |
| `base_system_opt_root` | string | `{{ k8s_lab_opt_root | default('/opt/capi-lab') }}` | Role filesystem root; sourced from the project global. |
| `base_system_opt_owner` / `base_system_opt_group` / `base_system_opt_mode` | string | `root` / `root` / `0755` | Ownership and mode for the role filesystem root. |
| `base_system_extra_packages` | list | `[]` | Site-specific extras merged on top of the required baseline. |
| `base_system_btrfs_enabled` | bool | `true` | Installs btrfs tooling support. |
| `base_system_btrfs_extra_packages` | list | `[]` | Extra btrfs-related packages layered on top of the required set. |
| `base_system_apt_cache_valid_time` | int | `3600` | APT cache freshness window in seconds. |
| `base_system_sysctl_apply` | bool | `true` | Apply required sysctls plus `base_system_extra_sysctl`. |
| `base_system_extra_sysctl` | map | `{}` | Extra sysctl values merged after the required baseline; required keys still win. |
| `base_system_extra_kernel_modules` | list | `[]` | Extra kernel modules appended after required modules. |
| `base_system_flow_control_packages` / `base_system_flow_control_sysctl` / `base_system_flow_control_modules` | bool | `true` | Major-section flow-control switches; no per-task switches. |
| `base_system_btrfs_pool_required` | bool | `false` | When true, asserts the expected mountpoint exists and is btrfs (downstream pool contract). |
| `base_system_btrfs_pool_mountpoint` | string | `/var/lib/k8slab/lxd-pool` | Path the contract assertion checks. |
| `base_system_btrfs_pool_fstype` / `base_system_btrfs_pool_label` | string | `btrfs` / `k8slab-lxdpool` | Expected filesystem type and label when the btrfs pool assertion is enabled. |

### `binary_fetch`

Plan §15.1. Fetches kubectl / clusterctl / k3s into `/opt/capi-lab/bin`
with checksum verification.

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `binary_fetch_kubectl_version` | string | `v1.35.3` | dl.k8s.io kubectl release. Mirrors `k8s_lab_kubectl_version`. |
| `binary_fetch_clusterctl_version` | string | `v1.12.5` | kubernetes-sigs/cluster-api release. Sha256 pinned in defaults (no upstream `.sha256` artefact). |
| `binary_fetch_clusterctl_checksum_sha256` | string | `b20044c66b62e273d6fe101ea82a00dc2329c28e2bca1e9b6274b744474429ba` | SHA256 of `clusterctl-linux-amd64` for the pinned version; recomputed on bump. |
| `binary_fetch_k3s_version` | string | `v1.35.3+k3s1` | k3s-io/k3s release. |
| `binary_fetch_arch` | string | `amd64` | Architecture; only amd64 exercised in Stage 1. |

### `lxd_host`

Plan §13.2. Installs LXD via snap, manages refresh policy, creates the
host-side `br-ext6` bridge.

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `lxd_host_snap_channel` | string | `6/stable` | LXD snap channel. |
| `lxd_host_snap_refresh_mode` | string | `hold` | `hold` or `timer`. |
| `lxd_host_snap_refresh_timer_value` | string | `fri,03:00-04:00` | Systemd-calendar expression used when mode = timer. |
| `lxd_host_ext_bridge_name` | string | `br-ext6` | Host-side Linux bridge name. |
| `lxd_host_ext_bridge_uplink` | string | `""` | **Required** when bridge enabled — preflight rejects empty (avoids bridging the mgmt NIC). |

### `lxd_project`

Plan §13.3. Creates the LXD project with a substrate-required
`restricted=true` allow-list.

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `lxd_project_name` | string | `capi-lab` | Project name; part of the inter-role contract. |
| `lxd_project_description` | string | `k8s-lab — CAPN substrate project` | Free-form description stored in LXD. |
| `lxd_project_lxd_socket_path` | string | `/var/snap/lxd/common/lxd/unix.socket` | Bare path; `ansible.builtin.uri` consumes it directly. |
| `lxd_project_extra_restrictions` | map | `{}` | Extra `restricted.*` entries layered on top of the required baseline. Keys must start with `restricted.` (preflight). |

### `lxd_storage_pools`

Plan §13.4. Creates LXD storage pools as global LXD objects.

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `lxd_storage_pools_lxd_socket_path` | string | `/var/snap/lxd/common/lxd/unix.socket` | LXD REST socket path. |
| `lxd_storage_pools_pools` | list(map) | `[{name: capi-fast, driver: btrfs, config: {source: ""}}]` | Pool definitions; consumer **must** override `config.source` with a path to a block device. |

### `lxd_network_int_managed`

Plan §13.5. Creates the `capi-int` LXD-managed bridge (dual-stack DHCP +
RA + NAT).

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `lxd_network_int_managed_lxd_socket_path` | string | `/var/snap/lxd/common/lxd/unix.socket` | LXD REST socket path. |
| `lxd_network_int_managed_networks` | list(map) | `[{name: capi-int, type: bridge, config: {ipv4.address: 10.77.0.1/24, ipv6.address: fd42:77:1::1/64}}]` | Network definitions; substrate-required NAT / DHCP keys merged on top from `vars/main.yml`. |

### `lxd_profiles`

Plan §13.6. Creates the four `capi-base` / `capi-bootstrap` /
`capi-controlplane` / `capi-worker` profiles in the LXD project.

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `lxd_profiles_project` | string | `capi-lab` | LXD project the profiles live in. |
| `lxd_profiles_storage_pool` | string | `capi-fast` | Pool the profiles' root disk references. |
| `lxd_profiles_internal_network` | string | `capi-int` | LXD-managed bridge for `eth0`. |
| `lxd_profiles_external_bridge` | string | `br-ext6` | Plain Linux bridge for `eth1`. |
| `lxd_profiles_capi_controlplane_extra_config` / `_extra_devices` | map / map | `{}` / `{}` | Extras merged on top of the substrate baseline (one pair per profile: `capi_base`, `capi_bootstrap`, `capi_controlplane`, `capi_worker`). |

### `lxd_bootstrap_instance`

Plan §13.7. Creates and starts the bootstrap LXC container.

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `lxd_bootstrap_instance_name` | string | `capi-bootstrap-0` | Container name. |
| `lxd_bootstrap_instance_extra_profiles` | list(string) | `[]` | Extras layered after the substrate-required `capi-base` + `capi-bootstrap` profiles. |
| `lxd_bootstrap_instance_image_alias` | string | `debian/13/cloud` | Image alias on `https://images.lxd.canonical.com`. |
| `lxd_bootstrap_instance_devices` | map | `{}` | Per-instance device overlay; **this is where the optional `k3s-api` LXD proxy device is declared** for external publication of the bootstrap API (plan §15.5 + §8 commentary). Example: `{k3s-api: {type: proxy, listen: "tcp:0.0.0.0:16443", connect: "tcp:127.0.0.1:6443", bind: host}}`. |
| `lxd_bootstrap_instance_state` | string | `started` | `started`, `stopped`, or `absent`. |
| `lxd_bootstrap_instance_readiness_ifname` | string | `eth0` | Interface the role-owned readiness gate polls (single-interface IPv4 wait — replaces the broken stock `wait_for_ipv4_addresses` on every-non-lo). |

### `bootstrap_k3s`

Plan §15.2. Installs k3s inside the already-running bootstrap container.

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `bootstrap_k3s_project` / `bootstrap_k3s_instance_name` | string / string | `capi-lab` / `capi-bootstrap-0` | Cross-role coupling by value (plan §2.6.5). |
| `bootstrap_k3s_extra_disable_components` | list | `[]` | Extras appended to the substrate-required disable list (`traefik`, `servicelb`). |
| `bootstrap_k3s_tls_san` | list | `[]` | SANs for the kube-apiserver cert; production / pivot consumers add host / FQDN here. |
| `bootstrap_k3s_token` | string | `""` | Optional join token; empty = k3s auto-generates. |
| `bootstrap_k3s_extra_args` | list | `[]` | Free-form extra args appended verbatim to `ExecStart`. |

### `bootstrap_clusterctl`

Plan §15.3. Runs `clusterctl init` against the bootstrap k3s.

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `bootstrap_clusterctl_capn_version` | string | `{{ k8s_lab_capn_provider_version | default('v0.8.5') }}` | Tracks the global pin; tunable for cherry-picking. |
| `bootstrap_clusterctl_capn_provider_url` | string | `https://github.com/lxc/cluster-api-provider-incus/releases/{{ ver }}/infrastructure-components.yaml` | Tunable for airgap mirrors. Provider name (`incus`) is substrate-locked. |
| `bootstrap_clusterctl_cluster_topology_enabled` | bool | `true` | Surfaces as `CLUSTER_TOPOLOGY=true` env on init. |
| `bootstrap_clusterctl_extra_providers` | list(map) | `[]` | Each entry: `{name, url, type}`. |
| `bootstrap_clusterctl_extra_init_flags` | list(string) | `[]` | Verbatim `--<kind>=<provider>:<version>` flags. |
| `bootstrap_clusterctl_init_timeout` | int | `600` | Wall-clock budget for `clusterctl init` (seconds). |

### `bootstrap_capn_secret`

Plan §15.4. Materialises the LXD identity Secret CAPN consumes.

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `bootstrap_capn_secret_lxd_project` | string | `{{ k8s_lab_project_name | default('capi-lab') }}` | LXD project the client cert is restricted to. |
| `bootstrap_capn_secret_internal_network_name` | string | `{{ k8s_lab_internal_network_name | default('capi-int') }}` | Used for `core.https_address` auto-resolution. |
| `bootstrap_capn_secret_lxd_https_bind_address` | string | `""` | `<ip>:<port>` literal; empty = auto-resolve to `capi-int` gateway IPv4. |
| `bootstrap_capn_secret_client_cert_validity_days` | int | `1095` | Client cert validity (3 years). |
| `bootstrap_capn_secret_namespaces` | list(string) | `{{ k8s_lab_capn_identity_namespaces | default(['capi-clusters']) }}` | Namespaces where the Secret is materialised. |

### `export_artifacts`

Plan §15.6. Ships handoff artefacts (`mgmt.kubeconfig` and
`mgmt.auto.tfvars.json`) to the runner's `.artifacts/`.

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `export_artifacts_run_meta_chain` | bool | `true` | Drives the meta-dep chain (`bootstrap_capn_secret` → … → `bootstrap_clusterctl` → `base_system`); flip to `false` for re-emit invocations on an already-converged substrate. |
| `export_artifacts_root` | string | `""` | **Required**: absolute path on the runner where artefacts land. Molecule passes `{{ MOLECULE_PROJECT_DIRECTORY }}/../../.artifacts`. |
| `export_artifacts_mgmt_kubeconfig_enabled` | bool | `true` | Per-artefact toggle. |
| `export_artifacts_tfvars_enabled` | bool | `true` | Per-artefact toggle. |
| `export_artifacts_mgmt_api_server_url` | string | `""` | When non-empty, rewrites every `clusters[].cluster.server` in the shipped kubeconfig (e.g. `https://<lxd_host_ip>:16443` for an LXD proxy device listener); TLS identity decoupled via `tls-server-name`. |
| `export_artifacts_tfvars_extra` | map | `{}` | Consumer dict merged on top of the baseline tfvars payload; baseline keys win on collision. |

### `pivot_clusterctl_move`

Plan §18.1. Pivots CAPI from the bootstrap k3s onto the self-hosted
mgmt-1 cluster.

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `pivot_clusterctl_move_target_cluster_name` | string | `{{ k8s_lab_management_cluster_name | default('mgmt-1') }}` | Target mgmt cluster name on the bootstrap side. |
| `pivot_clusterctl_move_target_cluster_namespace` | string | `capi-clusters` | Namespace the target Cluster CR lives in. |
| `pivot_clusterctl_move_target_api_address` | string | `{{ k8s_lab_lxd_host_address | default('') }}` | Address the rewritten target kubeconfig points its `server:` URL at. |
| `pivot_clusterctl_move_capn_version` | string | `{{ k8s_lab_capn_provider_version | default('v0.8.5') }}` | CAPN release on the target; tracks the project-wide pin. |
| `pivot_clusterctl_move_init_timeout` | int | `600` | Wall-clock budget for `clusterctl init` on the target (seconds). |
| `pivot_clusterctl_move_move_timeout` | int | `1200` | Wall-clock budget for `clusterctl move` (seconds). |

### `cleanup_bootstrap`

Plan §19.1. Removes the bootstrap LXC container post-pivot.

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `cleanup_bootstrap_project` | string | `capi-lab` | LXD project hosting the bootstrap instance. |
| `cleanup_bootstrap_instance_name` | string | `capi-bootstrap-0` | Bootstrap container name; mirrors `lxd_bootstrap_instance_name`. |
| `cleanup_bootstrap_force_stop` | bool | `true` | Required by `community.general.lxd_container` for `state=absent` on a running instance. |
| `cleanup_bootstrap_remove_artifacts` | bool | `true` | Also deletes the runner-side `.artifacts/` root after the LXC is gone. |
| `cleanup_bootstrap_artifacts_root` | string | `""` | Path the artifact removal runs against; consumer pins it to whatever was passed to `export_artifacts_root`. Empty leaves the artefact removal step a no-op. |

---

## Terraform module: `workload_cluster`

Source: `terraform/modules/workload_cluster/{variables,outputs}.tf`.
Consumed by the Stage 1 fixture root and by Stage 2 consumer overlays.

### Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `mgmt_kubeconfig_path` | string | — | Path to the management-cluster kubeconfig. Always points at `.artifacts/mgmt.kubeconfig` — the same file pre- and post-pivot (`pivot_clusterctl_move` overwrites it in place after `clusterctl move`). PLAN §16.4. |
| `cluster_name` | string | — | Workload Cluster CR name. §8 `k8s_lab_workload_cluster_name`. |
| `cluster_namespace` | string | `capi-clusters` | Namespace for the workload Cluster CR. MUST be one of §8 `k8s_lab_capn_identity_namespaces`. |
| `kubernetes_version` | string | — | K8s version for the workload cluster. Must exist in CAPN simplestreams set. Validated against `^v[0-9]+\.[0-9]+\.[0-9]+(\+.+)?$`. |
| `controlplane_count` | number | — | Workload control-plane replica count. CAPI KCP webhook rejects even values under stacked etcd. Validated: positive odd integer. |
| `worker_count` | number | — | Workload worker replica count (single MachineDeployment `md-0` in MVP). Validated: positive integer. |
| `cluster_class_chart_version` | string | — | `helm_release.version` for `charts/capi-cluster-class`. §8 `k8s_lab_capi_cluster_class_chart_version`. |
| `cluster_workload_chart_version` | string | — | `helm_release.version` for `charts/capi-workload-cluster`. §8 `k8s_lab_capi_workload_cluster_chart_version`. Must match the chart's pinned `k8s-lab.io/capi-cluster-class-chart-version` annotation. |
| `cluster_class_namespace` | string | `""` | Namespace where the per-workload ClusterClass is installed. Default = same as `cluster_namespace`. |
| `class_prefix` | string | `capn-default` | Logical prefix passed to `charts/capi-cluster-class` as `clusterClass.name`. Final ClusterClass `metadata.name = <prefix>-<chart-version-slug>`. |
| `pod_cidrs` | list(string) | — | `[IPv4, IPv6]` pod CIDRs (dual-stack). §8 `k8s_lab_workload_pod_cidr_{v4,v6}`. Validated: exactly 2 entries. |
| `service_cidrs` | list(string) | — | `[IPv4, IPv6]` service CIDRs (dual-stack). §8 `k8s_lab_workload_service_cidr_{v4,v6}`. Validated: exactly 2 entries. |
| `infrastructure_secret_name` | string | `incus-identity` | CAPN identity Secret name. §8 `k8s_lab_infrastructure_secret_name`. Must already exist in `cluster_namespace` (provisioned by Ansible role `bootstrap_capn_secret` §13.11). |
| `image_controlplane_ref` | string | `capi:kubeadm/VERSION` | CAPN image ref for control-plane LXC (literal `VERSION` substituted at runtime). §8 `k8s_lab_images_controlplane`. |
| `image_controlplane_fingerprint` | string | `""` | Optional sha256 fingerprint pin for the CP image. Empty = resolve by name. |
| `image_worker_ref` | string | `capi:kubeadm/VERSION` | CAPN image ref for worker LXC. §8 `k8s_lab_images_worker`. |
| `image_worker_fingerprint` | string | `""` | Optional sha256 fingerprint pin for the worker image. |
| `load_balancer` | any | `{ lxc = {} }` | `LXCClusterTemplate.spec.template.spec.loadBalancer` (exactly one of `{lxc, oci, ovn, kubeVIP, external}`). MVP default = `{lxc = {}}`. |
| `controlplane_profiles_extra` | list(string) | `[]` | Consumer-supplied extra LXD profiles appended after the substrate baseline for control-plane LXC instances. |
| `worker_profiles_extra` | list(string) | `[]` | Consumer-supplied extra LXD profiles for worker LXC instances. |
| `controlplane_devices_extra` | list(string) | `[]` | CAPN v1alpha2 CSV device overrides for CP machines. Each entry: `"<name>,type=<t>,..."`. |
| `worker_devices_extra` | list(string) | `[]` | CAPN v1alpha2 CSV device overrides for worker machines. |
| `control_plane_tuning` | object (see below) | `{}` | kubeadm tuning for `KubeadmControlPlaneTemplate` (`feature_gates`, `*ExtraArgs`, `pre/postKubeadmCommands`). Substrate-reserved args are rejected by chart-side schema. |
| `worker_tuning` | object (see below) | `{}` | kubeadm tuning for `KubeadmConfigTemplate` (worker join side). |
| `kube_proxy_node_port_addresses` | list(string) | `[]` | kube-proxy NodePort bind CIDRs. Empty = bind all (kubeadm default). |
| `cni_calico_chart_version` | string | — | `helm_release.version` for `charts/cni-calico` (local wrapper around `projectcalico/tigera-operator`). |
| `metallb_chart_version` | string | — | `helm_release.version` for `charts/metallb` (subchart wrapper). Distinct from §8 `k8s_lab_metallb_chart_version` which pins the upstream subchart inside `Chart.yaml` dependencies. |
| `metallb_config_chart_version` | string | — | `helm_release.version` for `charts/metallb-config` (`IPAddressPool` + `L2Advertisement` + Gate A test). |
| `metallb_vip_range_v6` | string | — | IPv6 VIP range for MetalLB (`"<from>-<to>"` or `"<ip>/128"`). §8 `k8s_lab_metallb_vip_range_v6`. |
| `metallb_interface` | string | `eth1` | Interface name MetalLB speaker announces VIPs on. §8 `k8s_lab_metallb_interface`. |
| `metallb_extra_node_selectors` | map(string) | `{}` | Extra label matchers stacked on top of the substrate-required CP-exclusion in `L2Advertisement.nodeSelectors`. |
| `lxd_host_address` | string | — | Runner-reachable LXD host address (Vagrant VM IP for local; public IP/DNS for prod). Used to rewrite the workload kubeconfig server URL away from the internal `capi-int` IPv6 endpoint. §8 `k8s_lab_lxd_host_address`. Validated: non-empty. |
| `helm_test_timeout` | string | `15m` | Timeout passed to `helm test` for `cni-calico` and `metallb-config` Gate B / Gate A acceptance hooks. |

#### `control_plane_tuning` object shape

```hcl
control_plane_tuning = {
  feature_gates                 = optional(map(bool), {})
  api_server_extra_args         = optional(list(object({ name = string, value = string })), [])
  controller_manager_extra_args = optional(list(object({ name = string, value = string })), [])
  scheduler_extra_args          = optional(list(object({ name = string, value = string })), [])
  kubelet_extra_args            = optional(list(object({ name = string, value = string })), [])
  pre_kubeadm_commands          = optional(list(string), [])
  post_kubeadm_commands         = optional(list(string), [])
}
```

#### `worker_tuning` object shape

```hcl
worker_tuning = {
  feature_gates         = optional(map(bool), {})
  kubelet_extra_args    = optional(list(object({ name = string, value = string })), [])
  pre_kubeadm_commands  = optional(list(string), [])
  post_kubeadm_commands = optional(list(string), [])
}
```

### Outputs

| Name | Type | Description |
| --- | --- | --- |
| `cluster_name` | string | Workload Cluster CR name. |
| `cluster_namespace` | string | Namespace of the workload Cluster CR. |
| `cluster_class_name` | string | Rendered ClusterClass `metadata.name` (slug formula reproduced from `class_prefix` + chart version). |
| `kubeconfig` | string (sensitive) | Workload kubeconfig content (YAML string) with the server URL rewritten to `<lxd_host_address>:<api_proxy_port>` + `tls-server-name` pinned. Module never writes it to disk. |
| `api_proxy_port` | number | Per-cluster Adler-32-derived API proxy port (chart-side computation), echoed from the Cluster CR's `k8s-lab.io/api-proxy-port` annotation. |
| `metallb_vip_range_v6` | string | Echo of the MetalLB IPv6 VIP range (passthrough). |
| `helm_releases` | map(object) | Map of `helm_release` identifiers + versions for smoke-checks. Keys: `capi_cluster_class`, `capi_workload_cluster`, `cni_calico`, `metallb`, `metallb_config`. Each value: `{id, name, ns, version}`. |

### Usage example

```hcl
module "workload" {
  source = "git::https://github.com/<org>/k8s-lab.git//terraform/modules/workload_cluster?ref=v1.0.0"

  mgmt_kubeconfig_path = "${path.root}/.artifacts/mgmt.kubeconfig"

  cluster_name       = "lab-default"
  cluster_namespace  = "capi-clusters"
  kubernetes_version = "v1.35.0"
  controlplane_count = 3
  worker_count       = 2

  cluster_class_chart_version    = "0.6.3"
  cluster_workload_chart_version = "0.8.0"

  pod_cidrs     = ["10.244.0.0/16", "fd42:77:2::/56"]
  service_cidrs = ["10.96.0.0/16", "fd42:77:3::/112"]

  cni_calico_chart_version     = "0.2.1"
  metallb_chart_version        = "0.1.0"
  metallb_config_chart_version = "0.1.3"

  metallb_vip_range_v6 = "fd42:dead:beef::100-fd42:dead:beef::1ff"
  metallb_interface    = "eth1"

  lxd_host_address = "192.168.121.10"
}

output "workload_kubeconfig" {
  value     = module.workload.kubeconfig
  sensitive = true
}
```

The same fixture root pattern lives in
`tests/fixtures/terraform/workload-clusters/lab-default/` (Stage 1 local
harness). Consumer repos follow the shape above with their own tfvars.

---

## Helm charts — values reference

Every chart lives under `charts/` in this repo. Substrate-required CR
fields (`apiVersion/kind`, immutable identity keys, the unprivileged-LXC
profile baseline, `installation.enabled: false` on the tigera-operator
subchart, etc.) are baked into `templates/*.yaml` and **not** exposed —
per the memory rule "Chart-required values are hardcoded".

### `charts/capi-cluster-class`

PLAN §16.2. Renders the per-workload ClusterClass +
`KubeadmControlPlaneTemplate` + `LXCClusterTemplate` +
`LXCMachineTemplate` set.

| Path | Type | Default | Notes |
| --- | --- | --- | --- |
| `clusterClass.name` | string | `capn-default` | Logical prefix; final names = `{name}-{chart-version-slug}`. The workload-cluster chart MUST use the same transform. |
| `kubernetes.version` | string | `""` | Bound from §8 `k8s_lab_kubernetes_version`. CAPN substrings the literal `VERSION` inside image refs with this value. |
| `capn.infrastructureSecretName` | string | `""` | CAPN identity Secret name; project scoping lives inside the Secret payload (no separate field on LXCCluster v1alpha2). |
| `images.controlplane.ref` | string | `capi:kubeadm/VERSION` | CAPN image ref; `VERSION` is templated by CAPN at provision time. |
| `images.controlplane.fingerprint` | string | `""` | Optional sha256 pin. |
| `images.worker.ref` | string | `capi:kubeadm/VERSION` | CAPN image ref for workers. |
| `images.worker.fingerprint` | string | `""` | Optional sha256 pin. |
| `loadBalancer` | object | `{ lxc: {} }` | Exactly one mode (`lxc`, `oci`, `ovn`, `kubeVIP`, `external`); enforced via `values.schema.json` `maxProperties=1`. To switch modes, null out the default first (Helm deep-merges maps). |
| `loadBalancer.lxc.image` | object | (unset) | `{name, protocol, server, fingerprint}` — pin a custom haproxy image. |
| `loadBalancer.lxc.flavor` | string | (unset) | LXD instance flavor (resource preset). |
| `loadBalancer.lxc.target` | string | (unset) | Cluster-member or `@cluster-group` for multi-node LXD. |
| `loadBalancer.lxc.disableHealthzCheck` | bool | (unset) | Opt out of the haproxy `/healthz` check. |
| `loadBalancer.lxc.profilesExtra` | list(string) | (unset) | Consumer profiles appended after `capi-base`. |
| `profilesExtra.controlplane` | list(string) | `[]` | Extra profiles appended after the substrate baseline for CP machines. |
| `profilesExtra.worker` | list(string) | `[]` | Extra profiles for workers. |
| `devicesExtra.controlplane` | list(string) | `[]` | CSV device overrides on top of profile devices. |
| `devicesExtra.worker` | list(string) | `[]` | CSV device overrides for workers. |
| `controlPlane.featureGates` | map(bool) | `{}` | kubeadm feature gates for the CP. |
| `controlPlane.apiServerExtraArgs` | list({name, value}) | `[]` | Reserved-key guard rejects `bind-address`, `service-cluster-ip-range`. |
| `controlPlane.controllerManagerExtraArgs` | list({name, value}) | `[]` | Reserved-key guard rejects `allocate-node-cidrs`, `cluster-cidr`, `service-cluster-ip-range`. |
| `controlPlane.schedulerExtraArgs` | list({name, value}) | `[]` | scheduler args. |
| `controlPlane.kubeletExtraArgs` | list({name, value}) | `[]` | Reserved-key guard rejects `feature-gates`, `node-ip`, `provider-id`. |
| `controlPlane.preKubeadmCommands` | list(string) | `[]` | Commands run before kubeadm init/join on CP. |
| `controlPlane.postKubeadmCommands` | list(string) | `[]` | Commands run after kubeadm init/join on CP. |
| `worker.featureGates` | map(bool) | `{}` | kubeadm feature gates for workers. |
| `worker.kubeletExtraArgs` | list({name, value}) | `[]` | Reserved-key guard rejects `feature-gates`, `node-ip`, `provider-id`. |
| `worker.preKubeadmCommands` | list(string) | `[]` | Commands run before kubeadm join on workers. |
| `worker.postKubeadmCommands` | list(string) | `[]` | Commands run after kubeadm join on workers. |
| `kubeProxy.nodePortAddresses` | list(string) | `[]` | NodePort bind CIDRs. Empty = kubeadm default (bind all). |

ClusterClass intentionally exposes no `clusterNetwork` — per-cluster pod
/ service CIDRs live on the Cluster CR, rendered by
`charts/capi-workload-cluster`.

### `charts/capi-workload-cluster`

PLAN §16.3. Renders exactly one Cluster CR (cluster.x-k8s.io/v1beta2) in
topology mode + the post-install `api-proxy` attach Job + the helm test
hook.

| Path | Type | Default | Notes |
| --- | --- | --- | --- |
| `cluster.name` | string | `lab-default` | Logical Cluster name; becomes `metadata.name` and the cluster-name label on every owned object. |
| `clusterClass.name` | string | `capn-default` | Logical prefix matching `capi-cluster-class .Values.clusterClass.name`. |
| `clusterClass.namespace` | string | `""` | Namespace where the ClusterClass lives; empty = same-namespace pattern. |
| `kubernetes.version` | string | `v1.35.0` | Goes to `spec.topology.version`; constrained by CAPN simplestreams image set. |
| `topology.controlPlane.replicas` | int | `3` | MUST be odd under default stacked etcd (CAPI KCP webhook rejects even values). |
| `topology.workers.replicas` | int | `2` | Single MachineDeployment `md-0`; the class name is hardcoded. |
| `loadBalancer.lxc.proxyApiPort` | int | `0` | Override the auto-derived port (Adler-32 of `cluster.name`, mapped to 20000-29999). 0 = use the hash. |
| `apiProxy.image` | string | `alpine:3.21` | Base image for the post-install / pre-delete hook Jobs that wire the LXD `api-proxy` device. Drives the LXD HTTPS REST API directly with mTLS material from the identity Secret (no `lxc` / `incus` CLI). |
| `apiProxy.infrastructureSecretName` | string | `incus-identity` | CAPN identity Secret consumed by the hook Job; tracks §8 `k8s_lab_infrastructure_secret_name`. |
| `apiProxy.lbWaitTimeoutSeconds` | int | `600` | Maximum wait inside the post-install Job for CAPN to materialise the haproxy LB LXC instance. |
| `clusterNetwork.pods.cidrBlocks` | list(string) | `["10.244.0.0/16", "fd42:77:2::/56"]` | Dual-stack pod CIDRs; up to two entries. |
| `clusterNetwork.services.cidrBlocks` | list(string) | `["10.96.0.0/16", "fd42:77:3::/112"]` | Dual-stack service CIDRs. |
| `tests.image` | string | `alpine:3.21` | helm test Pod base image; fetches kubectl from dl.k8s.io at runtime via `wget`. |
| `tests.nodesUpTimeoutSeconds` | int | `1200` | Max wait for workload-side node registration (3 CP + 2 W on cold cache ≈ 10-15 min). |

### `charts/cni-calico`

PLAN §17.1. Wrapper around `projectcalico/tigera-operator` shipping a
substrate-locked `Installation` CR and the Gate B helm test.

| Path | Type | Default | Notes |
| --- | --- | --- | --- |
| `calico.pods.cidrBlocks` | list(string) | `["10.244.0.0/16", "fd42:77:2::/56"]` | Dual-stack pod CIDRs. Indices are positional ([0] = IPv4, [1] = IPv6). Both pools have `natOutgoing` enabled in `templates/installation.yaml`. |
| `tigera-operator.installation.enabled` | bool | `false` | Disables the subchart's own `Installation` CR; the wrapper renders its own from `templates/installation.yaml` so substrate-required network fields (BGP, encapsulation, dataplane) stay hardcoded. |
| `tigera-operator.apiServer.enabled` | bool | `true` | Required for projectcalico.org aggregated APIs (`calicoctl`, NetworkPolicy v3). |
| `tigera-operator.goldmane.enabled` | bool | `false` | Calico flow-log aggregator; off by default. |
| `tigera-operator.whisker.enabled` | bool | `false` | Calico observability UI; off by default. |
| `tests.image` | string | `alpine:3.21` | Probe Pod image; alpine + busybox `ping`/`ping -6` + upstream kubectl via `wget`. |
| `tests.kubectlVersion` | string | `v1.35.0` | kubectl pinned to the workload K8s minor; fetched from dl.k8s.io at runtime. |
| `tests.nodesReadyTimeoutSeconds` | int | `600` | Max wait for `calico-node` DS rollout + per-Node CNI install + Node Ready=True. |
| `tests.podToPodTimeoutSeconds` | int | `120` | Probe Pod creation + ICMP roundtrip budget. |

Substrate-locked Installation fields (not exposed): `cni.type: Calico`,
IPAM type, `bgp: Disabled`, `linuxDataplane: Iptables`, ipPool
encapsulation `VXLAN`, `controlPlaneReplicas: 2`. BGP infra is absent on
the CAPN/LXD substrate; IPIP encapsulation does not support IPv6;
unprivileged LXC needs Iptables dataplane (eBPF requires kernel
privileges user namespaces don't grant).

### `charts/metallb`

PLAN §17.1. Minimal subchart wrapper around upstream `metallb/metallb`.
No wrapper-owned templates — exists only to pin substrate-required
subchart toggles. Two-release split with `charts/metallb-config` is
required because the subchart's CRDs live in `templates/crds/` rather
than the Helm `crds/` folder; bundling them with custom resources in a
single release fails Helm 3's pre-apply manifest validation.

| Path | Type | Default | Notes |
| --- | --- | --- | --- |
| `metallb.crds.enabled` | bool | `true` | Subchart's own switch for CRD sub-dependency; flipping it off breaks the two-release contract. |
| `metallb.frrk8s.enabled` | bool | `false` | No BGP / frr-k8s infrastructure on this lab substrate. |
| `metallb.speaker.tolerateMaster` | bool | `true` | Speaker DS lands on CP nodes too; the L2Advertisement nodeSelector in the sibling chart restricts VIP **announcement** to workers, but speakers across the fleet simplify memberlist convergence. |
| `metallb.speaker.frr.enabled` | bool | `false` | L2 mode only; drops the frrouting sidecar. |

### `charts/metallb-config`

PLAN §17.1. Ships custom resources only — `IPAddressPool` +
`L2Advertisement` + the helm test driver Pod (Gate A acceptance).

| Path | Type | Default | Notes |
| --- | --- | --- | --- |
| `pool.rangeV6` | string | `""` | IPv6 VIP range; bound by consumer to §8 `k8s_lab_metallb_vip_range_v6`. **No safe default** — every consumer must declare. Format: `<from>-<to>` or `<ip>/128`. |
| `l2.interface` | string | `eth1` | Interface MetalLB speaker announces VIPs on. Bound to §8 `k8s_lab_metallb_interface`. Combined with the substrate-required worker-only nodeSelector. |
| `l2.extraNodeSelectors` | map(string) | `{}` | Optional consumer label matchers added to L2Advertisement nodeSelectors; substrate-required CP exclusion is always enforced. |
| `tests.image` | string | `alpine:3.21` | Driver Pod image; alpine + busybox `wget`. |
| `tests.demoImage` | string | `nginx:1.27-alpine` | Backend Pod image; nginx by default listens on `[::]:80` (required for the demo Service's `ipFamilies: [IPv6]`). |
| `tests.demoName` | string | `k8s-lab-metallb-demo` | Backend Service / Deployment basename. |
| `tests.demoPort` | int | `80` | Port the demo backend listens on; 80 keeps `curl http://[<VIP>]/` ergonomic. |
| `tests.kubectlVersion` | string | `v1.35.0` | kubectl pinned to the workload K8s minor. |
| `tests.vipAllocationTimeoutSeconds` | int | `600` | Speaker DS rollout + controller Available + VIP allocation + cold image pull on backend Pod. |

Substrate-locked fields (not exposed): `interfaces: [<l2.interface>]`,
L2Advertisement nodeSelectors excluding control-plane, IPAddressPool
`protocol=L2`, IPv6 single-stack.

---

## Verified versions table

Reproduces `PLAN-stage1-common.md` §8a. Every external dependency pin is
recorded with its upstream verification date.

| Component | Version | Where used | Verification date |
| --- | --- | --- | --- |
| Kubernetes (workload/mgmt) | `v1.35.0` | `k8s_lab_kubernetes_version` | 2026-04-25 |
| k3s (bootstrap) | `v1.35.3+k3s1` | `k8s_lab_k3s_version` | 2026-04-21 |
| kubectl | `v1.35.3` | `k8s_lab_kubectl_version` | 2026-04-21 |
| Cluster API (clusterctl) | `v1.12.5` | `k8s_lab_clusterctl_version` | 2026-04-21 |
| CAPN | `v0.8.5` | `k8s_lab_capn_provider_version` | 2026-04-21 |
| LXD snap channel | `6/stable` | `lxd_host_snap_channel` | 2026-04-21 |
| Calico (tigera-operator) chart | `v3.31.5` | `k8s_lab_calico_chart_version` | 2026-04-21 |
| MetalLB chart | `0.15.3` | `k8s_lab_metallb_chart_version` | 2026-04-27 |
| Terraform helm provider | `3.1.1` | `k8s_lab_helm_provider_version` | 2026-04-21 |
| ansible.posix collection | `>=2.1.0` | `ansible/requirements.yml` | 2026-04-21 |
| community.general collection | `>=12.6.0` | `ansible/requirements.yml` | 2026-04-21 |
| community.crypto collection | `>=3.2.0` | `ansible/requirements.yml` | 2026-04-21 |
| kubernetes.core collection | `>=6.4.0` | `ansible/requirements.yml` | 2026-04-23 |
| python3-kubernetes (Debian Trixie) | `30.1.0-2` | `tests/molecule/shared/tasks/prepare.yml` | 2026-04-23 |

**Deviations:**

- *LXD snap channel* (Step 1, current as of 2026-04-22): Canonical
  recommends LTS `5.21/stable` for production; this repo reads §2.11
  ("latest stable") literally and uses feature-stable `6/stable`.
  Trade-off: regression risk is higher; CAPN has not declared explicit
  compatibility with LXD 6.x. If at Gate B or earlier an
  incompatibility surfaces, downgrade to `5.21/stable` and record this
  in the plan change log.

- *Kubernetes pin* (Step 11, 2026-04-25): bounded by the set of prebuilt
  `capi:kubeadm/<ver>` images on
  `https://images.linuxcontainers.org/capn/`. As of 2026-04-25
  simplestreams returns `kubeadm/v1.33.0`, `kubeadm/v1.33.5`,
  `kubeadm/v1.34.0`, `kubeadm/v1.35.0` (and their `/ubuntu` variants).
  `v1.35.0` — the latest relevant for our pin. Upstream
  `dl.k8s.io/release/stable.txt` shows newer (`v1.35.4`/`v1.36.0`), but
  for this repo they are irrelevant until CAPN publishes a matching
  image. The pin is updated only after a fresh check of
  `streams/v1/images.json`.

---

## Override precedence

How values flow from the source of truth into a running stack:

### Ansible

1. Role `defaults/main.yml` is the lowest-precedence baseline.
2. Role `vars/main.yml` (substrate-required `_<role>_*`) wins over
   defaults but is **not** consumer-tunable by design.
3. Inventory `group_vars/all.yml` and `host_vars/<host>.yml` are the
   normal consumer override layer (e.g. `k8s_lab_storage_source`,
   `k8s_lab_uplink_interface`, `k8s_lab_external_ipv6_prefix`).
4. Play-level `vars:` and `--extra-vars` win on top of inventory.
5. Substrate-required values inside a role's `vars/main.yml` cannot be
   overridden — they are merged on top of consumer extras at task
   time, so attempting to disable a required key has no effect.

### Helm (charts/)

1. Each chart's `values.yaml` ships the public defaults documented
   above.
2. The `values.schema.json` next to it validates types, enums,
   `maxProperties` (e.g. `loadBalancer.maxProperties=1`), and reserved
   keys.
3. Override path: `kubernetes.core.helm` `values:` parameter (Ansible),
   `helm_release.values` HCL list (Terraform), or
   `helm install -f values.override.yaml` (manual). The
   `hashicorp/helm` Terraform provider is pinned to the Helm 3 SDK —
   Helm 4 hooks are not portable.
4. Substrate-required fields baked into `templates/*.yaml` are not
   overridable.

### Terraform

1. `module "workload_cluster"` accepts the inputs documented in the
   *Inputs* table above; type validation (`condition` blocks) is
   enforced at plan time.
2. Consumer-set values land via `tfvars` files, `-var-file=...`, or
   `-var key=value`.
3. **`mgmt.auto.tfvars.json`** is auto-emitted by the Ansible role
   `export_artifacts` (Phase 4 close-out) into the runner's
   `.artifacts/` directory. Terraform auto-loads
   `*.auto.tfvars.json` only from the current Terraform root, so callers
   pass this repo-root artefact explicitly with `-var-file`. The file
   carries: cluster identity, CAPN version, topology toggles, and the
   mgmt API endpoint derived from the rewritten kubeconfig.
4. The companion `.artifacts/mgmt.kubeconfig` is referenced by
   absolute path (`var.mgmt_kubeconfig_path`) — same file pre- and
   post-pivot; `pivot_clusterctl_move` overwrites it in place after
   `clusterctl move`.

### Cross-references

- `PLAN-stage1-common.md` §8 — master typed-variables contract.
- `PLAN-stage1-common.md` §8a — verified version log + deviations.
- `PLAN-stage1-1.md` §13.x — per-role implementation notes
  (numbered to match the role inputs above).
- `PLAN-stage1-3.md` §16.x — Terraform module + Helm chart
  contracts.
- `doc/02-architecture.md` — narrative for how these knobs combine
  into the substrate / bootstrap / pivot / workload chain.
