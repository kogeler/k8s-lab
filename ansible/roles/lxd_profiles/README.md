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

### Profile catalogue (role-internal)

The four profiles are not exposed as a user-overridable list. Their
substrate-required config — `security.nesting`, `security.privileged`,
`security.idmap.isolated`, `security.syscalls.intercept.mknod`,
`security.syscalls.intercept.setxattr`, `linux.kernel_modules`,
`raw.lxc` — lives in `vars/main.yml`. That choice is deliberate: any
of those values being missing breaks the lab (k3s crashloops, kubelet
can't open `/dev/kmsg`, containerd can't unpack images). Exposing them
as defaults would let a consumer accidentally disable the role by
clearing one of them.

User-tunable tuning goes through **per-profile extension variables**
that are merged on top of the baseline at apply time:

| Profile | `*_extra_config` | `*_extra_devices` |
| --- | --- | --- |
| `capi-base` | `lxd_profiles_capi_base_extra_config` | `lxd_profiles_capi_base_extra_devices` |
| `capi-bootstrap` | `lxd_profiles_capi_bootstrap_extra_config` | `lxd_profiles_capi_bootstrap_extra_devices` |
| `capi-controlplane` | `lxd_profiles_capi_controlplane_extra_config` | `lxd_profiles_capi_controlplane_extra_devices` |
| `capi-worker` | `lxd_profiles_capi_worker_extra_config` | `lxd_profiles_capi_worker_extra_devices` |

All default to `{}`. Keys set here take precedence over the baseline —
use them for non-critical knobs (e.g. extra `raw.idmap` mappings,
additional disk devices). If a consumer actually needs to turn off
something the baseline sets, treat that as a bug in the baseline, not
something to paper over with an extra.

### Flow control

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_profiles_enabled` | `true` | Whole-role toggle. |
| `lxd_profiles_flow_control_profiles` | `true` | Skip the profile create / merge section. |

## Tags

Both `_` and `-` spellings are accepted (plan §2.6.3):

* `lxd_profiles` / `lxd-profiles` — whole role.
* `lxd_profiles_preflight` — input validation only.
* `lxd_profiles_compose` — build the effective profile list (catalog + extras).
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

## Cloud-init vendor-data (external nic bring-up)

`capi-controlplane` and `capi-worker` ship a substrate-required
`cloud-init.vendor-data` key rendered from
`templates/capi-external-vendor-data.yaml.j2`. The template resolves
a single variable — `_ifname`, sourced from
`lxd_profiles_external_ifname` (default `eth1`) — and emits a
`#cloud-config` that:

* writes `/etc/sysctl.d/99-capi-ra.conf` enabling
  `accept_ra=2` / `accept_ra_defrtr=1` on the external nic;
* writes `/etc/systemd/network/30-capi-ext.network` with
  `IPv6AcceptRA=yes`, `LinkLocalAddressing=ipv6`, `DHCP=no`;
* runs `sysctl --load` and `networkctl reload` on first boot.

Without it the LXD nic device attaches eth1 at L2 only; the guest
never enables RA reception, so no global IPv6 is configured inside
the container.

Why `vendor-data`, not `user-data`: CAPN Machine templates ship their
own `cloud-init.user-data` on the instance (kubeadm bootstrap, CAPI
secrets). LXD merges the instance-level `user-data` by **replacing**
the profile-level one, so a profile-level `user-data` would never
reach a CAPN-created node. `vendor-data` is a separate cloud-init
source that merges with `user-data` natively — CAPN uses `user-data`
for kubeadm, the profile uses `vendor-data` for eth1 bring-up, no
conflict.

The key is role-internal and substrate-required: the injection is
driven by the `_external_vendor_data: true` marker on the catalog
entry (`vars/main.yml`), not by a user-facing variable. Consumers
cannot disable vendor-data through `lxd_profiles_capi_<role>_extra_config`
because extras are merged on top only for keys that don't collide —
but if a consumer's extras set `cloud-init.vendor-data` explicitly,
LXD receives the union via `combine`, and the extras-value wins. That
is a bug in the consumer override, not a feature.

`capi-base` and `capi-bootstrap` do NOT receive vendor-data — they
have no external nic and the bootstrap k3s container uses only eth0
on the internal bridge.

## Caveats

* **Unprivileged baseline hard-pins the CAPN knobs k3s needs.** The
  baseline now ships `security.syscalls.intercept.mknod`,
  `security.syscalls.intercept.setxattr`, `linux.kernel_modules` and
  `raw.lxc=lxc.apparmor.profile=unconfined` — without these k3s'
  embedded containerd fails image unpack and kubelet cannot open
  `/dev/kmsg`. The `boot-dir` disk mapping that CAPN docs list for
  kubeadm is still deferred to a later phase since `bootstrap_k3s`
  does not currently need it.
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
* **Restart-on-profile-change has a re-run blind spot.** When a
  profile entry changes, the role lists running instances in the
  project that reference that profile and restarts them via
  `community.general.lxd_container state=restarted` — most of the
  baseline keys (`security.privileged`, `security.idmap.isolated`,
  `security.syscalls.intercept.*`, `raw.lxc`) are *not* live-update
  per [LXD instance options reference][lxd-options], so without the
  restart the new values stay on the profile but never reach the
  running instance. If the profile change applies but the follow-up
  restart fails, a *re-run* sees the profile already matching
  (`changed=false`) and does not retry the restart — the instance
  stays on the old config until the operator restarts it manually
  or until something forces another profile change. A more robust
  drift detector would compare each instance's `expanded_config`
  against the profile baseline; that is intentionally deferred to
  keep Stage 1 scope tight.

[lxd-options]: https://documentation.ubuntu.com/lxd/latest/reference/instance_options/
