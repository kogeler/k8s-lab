# lxd_profiles

Create and configure the k8s-lab LXD profiles inside the `capi-lab`
project (plan §13.6).

## Purpose

Owns four LXD profiles:

* `capi-base` — root disk on the primary pool + internal NIC. Applied
  to every instance in capi-lab.
* `capi-bootstrap` — unprivileged + nesting, for the bootstrap k3s
  container.
* `capi-controlplane` — CAPN Canonical LXD **unprivileged kubeadm**
  baseline (nesting, idmap isolation, required kernel modules) +
  external NIC.
* `capi-worker` — same baseline as `capi-controlplane`, tagged for
  worker machines so operators can pin policies per role.

CAPN machine templates reference these profiles by name at plan /
apply time (owned by the Terraform modules under `terraform/`).

Out of scope:

* Instances themselves (`lxd_bootstrap_instance` owns the bootstrap
  container; CAPN owns cluster nodes).
* Storage pools (`lxd_storage_pools`) and managed networks
  (`lxd_network_int_managed`).
* Host-level Linux bridges (`lxd_host`).

## Requirements

* Target host runs **Debian 13 Trixie** or newer.
* `lxd_storage_pools` has created the pool referenced by
  `lxd_profiles_storage_pool` (default `capi-fast`).
* `lxd_network_int_managed` has created the bridge referenced by
  `lxd_profiles_internal_network` (default `capi-int`).
* `lxd_host` has created the external host bridge referenced by
  `lxd_profiles_external_bridge` (default `br-ext6`) — transitively
  pulled in via the meta chain.
* `community.general` collection (`lxd_profile` module) on the
  control node.

## Role variables

All public variables use the `lxd_profiles_*` prefix (plan §2.6.2).

### General

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_profiles_lxd_socket_uri` | `unix:/var/snap/lxd/common/lxd/unix.socket` | LXD daemon socket URI consumed by `community.general.lxd_profile`. |
| `lxd_profiles_project` | `capi-lab` | LXD project profiles live in. |

### Shared device targets

| Variable | Default |
| --- | --- |
| `lxd_profiles_storage_pool` | `capi-fast` |
| `lxd_profiles_internal_network` | `capi-int` |
| `lxd_profiles_external_bridge` | `br-ext6` |
| `lxd_profiles_internal_ifname` | `eth0` |
| `lxd_profiles_external_ifname` | `eth1` |

### Profiles

`lxd_profiles_profiles` is a list of profile definitions. Each entry:

| Field | Required | Description |
| --- | --- | --- |
| `name` | yes | Profile name. |
| `description` | no | Stored on the profile. |
| `config` | no | LXD config dict; string values. |
| `devices` | no | Device dict — device name → device config dict. |

Default list (see `defaults/main.yml` for the full content):

* `capi-base` — root disk on `capi-fast`, eth0 on `capi-int`.
* `capi-bootstrap` — `security.nesting=true`, `security.privileged=false`,
  `security.idmap.isolated=true`, no devices.
* `capi-controlplane` / `capi-worker` — adds `linux.kernel_modules`
  and eth1 on `br-ext6`.

### Flow control

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_profiles_enabled` | `true` | Whole-role toggle. |
| `lxd_profiles_flow_control_profiles` | `true` | Skip the profile create / merge section. |

## Tags

Both `_` and `-` spellings are accepted (plan §2.6.3):

* `lxd_profiles` / `lxd-profiles` — whole role.
* `lxd_profiles_preflight` — input validation only.
* `lxd_profiles_profiles` — profile create / merge.
* `lxd_profiles_healthchecks` — in-role healthchecks.

## Example

```yaml
- hosts: k8slab_host
  become: true
  roles:
    - role: lxd_profiles
      vars:
        lxd_profiles_project: "capi-lab"
        lxd_profiles_storage_pool: "capi-fast"
        lxd_profiles_internal_network: "capi-int"
        lxd_profiles_external_bridge: "br-ext6"
```

## Testing

Ships a Molecule delegated-driver scenario under
`tests/molecule/lxd-profiles/` that:

* converges the role on the shared Vagrant VM (pulls
  `lxd_storage_pools` / `lxd_network_int_managed` / `lxd_project` /
  `lxd_host` / `base_system` in through meta deps);
* asserts idempotence;
* runs verify reading each profile back via the LXD REST API and
  asserting name / description / every declared config key / every
  declared device shape (type + path/pool for disks, type + nictype +
  parent for nics).

Run locally:

```bash
make -C tests/molecule lxd-profiles-delegated-test
```

## Caveats

* **Unprivileged baseline is a lean subset for Stage 1.** The CAPN
  Canonical LXD unprivileged kubeadm profile lists more keys
  (`raw.lxc.*`, `security.syscalls.intercept.*`, `boot-dir` disk
  device mapping `/boot`). The Stage 1 profile ships the minimum
  required for the LXD substrate contract; the full tuning lands
  alongside `lxd_bootstrap_instance` / `bootstrap_k3s` when inner
  Kubernetes drives the exact kernel / syscall requirements.
* **Bridge networks live in the default project, profiles in
  capi-lab.** capi-lab resolves the `capi-int` nic parent via
  `features.networks=false` inheritance (see `lxd_project`). There is
  no per-profile project/network coupling to worry about on this
  host — LXD handles the lookup.
* **Device-level healthchecks are coarse.** The role asserts type +
  headline fields (path/pool for disks, nictype/parent for nics)
  rather than full device-dict equality, because LXD occasionally
  normalises optional keys and strict equality would produce
  false-positive drift reports.
