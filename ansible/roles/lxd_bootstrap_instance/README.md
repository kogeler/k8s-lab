# lxd_bootstrap_instance

Create and start the LXC bootstrap container (`capi-bootstrap-0` by
default) inside the `capi-lab` project (plan §13.7).

## Purpose

Owns the bootstrap container lifecycle:

* **create** the instance from a canonical base image
  (`images:debian/13` by default) in the `capi-lab` project;
* **apply profiles** — `capi-base` (root disk on capi-fast + internal
  nic on capi-int) and `capi-bootstrap` (nesting, unprivileged, idmap
  isolated);
* **start** the container and wait for an IPv4 address to appear on
  every nic.

Out of scope:

* `k3s`, `kubectl`, `clusterctl` binaries inside the container —
  owned by `binary_fetch` / `bootstrap_k3s` in later phases.
* CAPN identity secret — owned by `bootstrap_capn_secret`.
* Bootstrap API publication on the host — owned by
  `bootstrap_api_publish`.

Implemented through the native `community.general.lxd_container`
module. Diff-logic caveats that bit `lxd_project` earlier do not
apply to instance CRUD; when they do show up the role falls back to
`ansible.builtin.uri` like the rest of Phase 2 (plan §2.6.1).

## Requirements

* Target host runs **Debian 13 Trixie** or newer.
* `lxd_profiles` has created the referenced profiles. Declared as a
  meta dependency, which transitively pulls the full substrate chain
  (`lxd_storage_pools`, `lxd_network_int_managed`, `lxd_project`,
  `lxd_host`, `base_system`) per plan §2.6.5.
* `community.general` collection (`lxd_container` module) on the
  control node.
* Outbound network from the host to the chosen image server (default
  `images.linuxcontainers.org`).

## Role variables

All public variables use the `lxd_bootstrap_instance_*` prefix
(plan §2.6.2).

### General

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_bootstrap_instance_lxd_socket_uri` | `unix:/var/snap/lxd/common/lxd/unix.socket` | LXD daemon socket URI consumed by `community.general.lxd_container`. |
| `lxd_bootstrap_instance_project` | `capi-lab` | LXD project the instance lives in. |

### Instance shape

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_bootstrap_instance_name` | `capi-bootstrap-0` | Instance name (LXD identifier; ≤63 chars, lowercase alnum / hyphen). |
| `lxd_bootstrap_instance_type` | `container` | `container` or `virtual-machine`. |
| `lxd_bootstrap_instance_profiles` | `[capi-base, capi-bootstrap]` | Profiles applied (order preserved). |

### Image source

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_bootstrap_instance_image_server` | `https://images.linuxcontainers.org` | Simplestreams / LXD remote URL. |
| `lxd_bootstrap_instance_image_protocol` | `simplestreams` | Remote protocol (`simplestreams` or `lxd`). |
| `lxd_bootstrap_instance_image_alias` | `debian/13` | Image alias or fingerprint. |

### Per-instance overlays

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_bootstrap_instance_config` | `{}` | Config keys layered on top of profile-supplied values. |
| `lxd_bootstrap_instance_devices` | `{}` | Devices layered on top of profile-supplied devices. |

### Lifecycle

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_bootstrap_instance_state` | `started` | Desired state: `started` / `stopped` / `absent`. |
| `lxd_bootstrap_instance_wait_ipv4` | `true` | Wait for every nic to receive an IPv4 address after start. |
| `lxd_bootstrap_instance_wait_timeout` | `120` | Seconds LXD may take to reach the desired state. |

### Flow control

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_bootstrap_instance_enabled` | `true` | Whole-role toggle. |
| `lxd_bootstrap_instance_flow_control_instance` | `true` | Skip create / start section. |

## Tags

Both `_` and `-` spellings accepted (plan §2.6.3):

* `lxd_bootstrap_instance` / `lxd-bootstrap-instance` — whole role.
* `lxd_bootstrap_instance_preflight` — input validation only.
* `lxd_bootstrap_instance_instance` — create + start.
* `lxd_bootstrap_instance_healthchecks` — in-role healthchecks.

## Example

```yaml
- hosts: k8slab_host
  become: true
  roles:
    - role: lxd_bootstrap_instance
      vars:
        lxd_bootstrap_instance_name: "capi-bootstrap-0"
        lxd_bootstrap_instance_profiles: [capi-base, capi-bootstrap]
        lxd_bootstrap_instance_image_alias: "debian/13"
```

## Testing

Ships a Molecule delegated-driver scenario under
`tests/molecule/lxd-bootstrap-instance/`. The scenario runs the full
meta chain on the shared Vagrant VM, creates the container, waits for
an IPv4 to appear on eth0 (via DHCP from `capi-int`), and asserts:

* instance exists in the right project with the right type and
  profiles;
* instance status is `Running`;
* at least one non-link-local IPv4 is reachable on any nic.

Run locally:

```bash
make -C tests/molecule lxd-bootstrap-instance-delegated-test
```

## Caveats

* **First converge pulls an image from the internet.** The test VM
  must have outbound access to `images.linuxcontainers.org` (or the
  alternative `lxd_bootstrap_instance_image_server` set by the
  consumer). Cold-cache runs can take tens of seconds even on a fast
  connection; `lxd_bootstrap_instance_wait_timeout` controls the
  upper bound.
* **`volatile.*` drift is ignored.** `ignore_volatile_options: true`
  on the module call prevents spurious "changed" reports on every
  idempotence run when LXD mutates volatile keys (mac addresses,
  last-state timestamps) behind our back.
* **Profile-driven root disk needs a valid pool.** The `capi-base`
  profile references `pool: capi-fast`; if `lxd_storage_pools` has
  not created that pool the instance create fails at the LXD layer
  — meta dependencies take care of ordering on a vanilla run.
