# base_system

Minimal Debian 13 Trixie host preparation for the k8s-lab stack.

## Purpose

This role lays the foundation that every other role in `ansible/roles/`
assumes — and nothing beyond it. It:

* installs only the APT packages allowed by [plan §2.2][plan-22] — no
  custom APT repositories are added;
* optionally installs `btrfs-progs` when the downstream storage pool
  uses Btrfs (plan §13.4);
* loads and persists the kernel modules needed by LXD/kubeadm node
  containers (`overlay`, `br_netfilter`, `nf_conntrack`);
* applies a small set of sysctl knobs tuned for Kubernetes on LXD
  (inotify, fd, forwarding);
* creates the deterministic `/opt/capi-lab` tree (`bin/`, `etc/`) that
  later roles populate with binaries and configuration artefacts.

This role does **not** install LXD (see `lxd_host`), does **not** fetch
non-system binaries (see `binary_fetch`), and does **not** touch user
accounts, time sync or SSH — those are environment concerns handled by
the consumer repository.

## Requirements

* Target host runs **Debian 13 Trixie** or newer.
* `community.general` and `ansible.posix` collections are available on
  the control node (see repo-level `ansible/requirements.yml`).
* Ansible ≥ 2.16 on the control node.

## Role variables

All public variables use the `base_system_*` prefix. Internal values use
`_base_system_*` and must not be consumed outside the role.

### Required baseline (role-internal, not user-overridable)

The substrate-required APT package list, kernel modules and sysctl knobs
are NOT exposed as defaults. They live in `vars/main.yml` as
`_base_system_required_packages`, `_base_system_btrfs_required_packages`,
`_base_system_required_kernel_modules` and `_base_system_required_sysctl`.
That choice is deliberate: the role depends on every one of these values
on its target substrate (e.g. `snapd` for `lxd_host`, `python3-apt` for
Ansible's apt module, `overlay`/`br_netfilter`/`nf_conntrack` for
kube-proxy/containerd/CNI, `net.ipv4.ip_forward=1` for kube-proxy). An
empty override would break downstream roles with no preflight warning.

Consumers extend the baseline through `*_extra_*` variables (below).

### General

| Variable | Default | Description |
| --- | --- | --- |
| `base_system_enabled` | `true` | Whole-role toggle. `false` still runs preflight. |
| `base_system_opt_root` | `/opt/capi-lab` | Shared filesystem root for binaries and config. |
| `base_system_opt_owner` | `root` | Owner of `opt_root` and children. |
| `base_system_opt_group` | `root` | Group of `opt_root` and children. |
| `base_system_opt_mode` | `0755` | Mode of `opt_root` and children (octal string). |

### Package extras

| Variable | Default | Description |
| --- | --- | --- |
| `base_system_extra_packages` | `[]` | Appended on top of `_base_system_required_packages`. Site-specific extras. |
| `base_system_btrfs_enabled` | `true` | Install `btrfs-progs`. |
| `base_system_btrfs_extra_packages` | `[]` | Appended on top of `_base_system_btrfs_required_packages` when `btrfs_enabled=true`. |
| `base_system_apt_cache_valid_time` | `3600` | Seconds of APT cache freshness. |

### Kernel / sysctl extras

| Variable | Default | Description |
| --- | --- | --- |
| `base_system_extra_kernel_modules` | `[]` | Appended on top of `_base_system_required_kernel_modules`. |
| `base_system_sysctl_apply` | `true` | Apply sysctl values. |
| `base_system_extra_sysctl` | `{}` | Merged with `_base_system_required_sysctl`. Required entries always win the merge — an override here cannot disable a required knob. |

### Flow control

| Variable | Default | Description |
| --- | --- | --- |
| `base_system_flow_control_packages` | `true` | Skip the packages section when `false`. |
| `base_system_flow_control_sysctl` | `true` | Skip the sysctl section when `false`. |
| `base_system_flow_control_modules` | `true` | Skip the modules section when `false`. |

### LXD btrfs pool contract

`base_system` does NOT format or mount the disk that will back the LXD
storage pool — that is a host-provisioning step (the `lxd_pool` disk is
attached by Vagrant for tests; in production the installer/operator
provisions it). What `base_system` owns is the **contract**: when the
pool is required, preflight asserts that the expected path is already a
btrfs mount, so `lxd_storage_pools` can never accidentally point LXD at
a directory that silently falls back to the OS disk.

| Variable | Default | Description |
| --- | --- | --- |
| `base_system_btrfs_pool_required` | `false` | Enable contract assertion. |
| `base_system_btrfs_pool_mountpoint` | `/var/lib/k8slab/lxd-pool` | Path the pool disk must be mounted at. |
| `base_system_btrfs_pool_fstype` | `btrfs` | Filesystem type expected at the mountpoint. |
| `base_system_btrfs_pool_label` | `k8slab-lxdpool` | Filesystem label used by the canonical prepare step. |

This is a deliberate, documented deviation from the original narrow
packages-only scope of `base_system`. The deviation is logged inline in
plan §13.1 (Step 1 notes).

## Tags

Per-section tags follow the repo convention (plan §2.6.3). The underscore
and hyphen spellings are both accepted:

* `base_system` / `base-system` — everything.
* `base_system_preflight` — input validation only.
* `base_system_install` — APT packages only.
* `base_system_modules` — kernel module loading/persistence.
* `base_system_sysctl` — sysctl values.
* `base_system_config` — `/opt/capi-lab` tree.
* `base_system_healthchecks` — in-role healthchecks.

## Example

```yaml
- hosts: k8slab_host
  become: true
  roles:
    - role: base_system
      vars:
        base_system_btrfs_enabled: true
        # Required sysctls always apply; this adds a site knob on top.
        base_system_extra_sysctl:
          vm.swappiness: 10
```

## Testing

This role ships a Molecule delegated-driver scenario under
`tests/molecule/base-system/`. It converges the role on the shared
Vagrant VM, checks idempotence, and exercises a verify playbook that
asserts:

* required packages appear in the APT package index;
* kernel modules are currently loaded and listed in `/etc/modules-load.d/`;
* declared sysctl values are active;
* `/opt/capi-lab/{bin,etc}` exist with the declared ownership and mode.

Run locally:

```bash
make -C tests/molecule base-system-delegated-test
```

## Caveats

* The role assumes it runs with `become: true`. It will fail on several
  mutating tasks otherwise — preflight does not assert on privilege
  because Molecule scenarios sometimes inject their own escalation.
* `community.general.modprobe` with `persistent: present` writes to
  `/etc/modules-load.d/` managed by systemd-modules-load; hosts using
  a different module loader will need a variant role.
* We intentionally avoid adding a global `DEBIAN_FRONTEND=noninteractive`
  shim — the apt module already suppresses prompts and we do not want to
  normalise a shell-based pattern elsewhere.

[plan-22]: ../../../PLAN-stage1-common.md
