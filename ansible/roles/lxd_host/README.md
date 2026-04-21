# lxd_host

Host-side preparation for running LXD on the k8s-lab stack.

## Purpose

This role owns everything that lives on the host OS around LXD, but
nothing that lives inside LXD (plan §8.3). Concretely it:

* installs the `lxd` snap and pins its channel (default `6/stable`,
  verified upstream per plan §2.11);
* applies a deterministic snap refresh policy — indefinite hold (default)
  or a weekly timer window;
* blocks until the LXD daemon reports `waitready`, so downstream LXD
  entity roles can talk to the socket / API on the first task;
* creates a host-side Linux bridge (`br-ext6` by default), declaratively
  via systemd-networkd drop-ins, and attaches an uplink interface as a
  bridge member. This is a plain Linux bridge — NOT an LXD managed
  network. LXD profiles later reference it through `nictype: bridged` /
  `parent: br-ext6`.

Out of scope: LXD projects, storage pools, managed networks, profiles,
and instances — each is owned by a dedicated role.

## Requirements

* Target host runs **Debian 13 Trixie** or newer.
* `base_system` has already run (snapd installed, `/opt/capi-lab` tree
  created, kernel modules loaded).
* `community.general` collection available on the control node.
* Host runs systemd (required for systemd-networkd).

## Role variables

All public variables use the `lxd_host_*` prefix (plan §2.6.2).

### Snap

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_host_snap_name` | `lxd` | Snap package name. |
| `lxd_host_snap_channel` | `6/stable` | Channel to track. |
| `lxd_host_snap_classic` | `false` | LXD is strictly confined — kept explicit to guard against flips. |
| `lxd_host_snap_seed_wait_timeout` | `180` | Seconds to wait for snapd seeding. |

### Refresh policy

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_host_snap_refresh_mode` | `hold` | `hold` or `timer`. |
| `lxd_host_snap_refresh_hold_value` | `forever` | Value of `refresh.hold` when mode=hold. Accepts `forever` or an RFC3339 timestamp. |
| `lxd_host_snap_refresh_timer_value` | `fri,03:00-04:00` | Value of `refresh.timer` when mode=timer. |

### Daemon readiness

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_host_wait_ready` | `true` | Block on `lxd waitready`. |
| `lxd_host_wait_ready_timeout` | `300` | Seconds. |

### External bridge

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_host_ext_bridge_enabled` | `true` | Create the bridge. |
| `lxd_host_ext_bridge_name` | `br-ext6` | Bridge name (≤15 chars, Linux IFNAMSIZ). |
| `lxd_host_ext_bridge_uplink` | `""` | REQUIRED when enabled. Uplink interface name (e.g. `eth1`). |
| `lxd_host_ext_bridge_stp` | `false` | Enable STP. |
| `lxd_host_ext_bridge_mtu` | `1500` | Bridge MTU. |
| `lxd_host_ext_bridge_forward_delay` | `0` | Bridge forward delay (seconds). |
| `lxd_host_ext_bridge_link_local` | `no` | `LinkLocalAddressing=` for the bridge itself. |
| `lxd_host_ext_bridge_accept_ra` | `no` | `IPv6AcceptRA=` for the bridge itself. |
| `lxd_host_networkd_dir` | `/etc/systemd/network` | Where drop-ins are written. |
| `lxd_host_networkd_file_priority` | `30` | Numeric filename prefix. |

### Flow control

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_host_enabled` | `true` | Whole-role toggle. |
| `lxd_host_flow_control_snap` | `true` | Skip snap install section. |
| `lxd_host_flow_control_refresh` | `true` | Skip refresh-policy section. |
| `lxd_host_flow_control_bridge` | `true` | Skip bridge section. |

## Tags

Both `_` and `-` spellings are accepted for top-level and section-level
tags (plan §2.6.3):

* `lxd_host` / `lxd-host` — the whole role.
* `lxd_host_preflight` — input validation only.
* `lxd_host_install` — snap install + channel pin.
* `lxd_host_refresh` — snap refresh policy.
* `lxd_host_waitready` — `lxd waitready` block.
* `lxd_host_bridge` — external host bridge via systemd-networkd.
* `lxd_host_healthchecks` — in-role healthchecks.

## Example

```yaml
- hosts: k8slab_host
  become: true
  roles:
    - role: lxd_host
      vars:
        lxd_host_snap_channel: "6/stable"
        lxd_host_snap_refresh_mode: "hold"
        lxd_host_ext_bridge_uplink: "eth1"
```

## Testing

Ships a Molecule delegated-driver scenario under
`tests/molecule/lxd-host/` that:

* converges the role on the shared Vagrant VM;
* re-converges and asserts idempotence;
* runs a verify playbook that exercises the real runtime state:
  `snap list lxd`, `lxd waitready`, bridge presence in
  `/sys/class/net/`, and the uplink being a member of the bridge.

Run locally:

```bash
make -C tests/molecule lxd-host-delegated-test
```

## Caveats

* Bridge config uses systemd-networkd drop-ins and enables
  `systemd-networkd.service`. On the Vagrant test VM the management NIC
  is managed by `networking.service` (ifupdown); the role relies on
  systemd-networkd matching only the named uplink interface, so the mgmt
  NIC stays with ifupdown. Match patterns are explicit `Name=<iface>`;
  never wildcarded.
* `snap set system refresh.*` is used for refresh policy because there
  is no Ansible module for it. The fallback to `ansible.builtin.command`
  is guarded by a prior `snap get system refresh.*` read so idempotence
  is preserved. This is a documented exception to the native-first
  policy (plan §2.6.1).
* Snap channel `6/stable` is a plan §2.11 deviation from Canonical's
  `5.21/stable` LTS recommendation. Rationale and rollback trigger are
  recorded in `PLAN-stage1-progress.md`.
