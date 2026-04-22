# lxd_project

Create and configure the k8s-lab LXD project with feature isolation and
restriction policy (plan §2.3 / §13.3).

## Purpose

This role owns only the LXD project object — a logical container for
all k8s-lab assets inside a single LXD host. Its job is to make sure:

* the project exists with the expected name (`capi-lab` by default);
* feature isolation is on for every axis (profiles, images, networks,
  network zones, storage volumes, storage buckets);
* the project is `restricted=true` with an explicit allow-list that
  permits nesting and LXD-managed disk / NIC devices, and hard-blocks
  privileged containers per plan §2.8.

Out of scope: storage pools, managed networks, profiles, instances —
each of those is owned by its own role inside the project.

## Requirements

* Target host runs **Debian 13 Trixie** or newer.
* `lxd_host` has already run (LXD snap installed, daemon `waitready`).
  Declared as a meta dependency so callers pull it in automatically
  (plan §2.6.5).
* `community.general` collection available on the control node.

## Role variables

All public variables use the `lxd_project_*` prefix (plan §2.6.2).

### Identity

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_project_name` | `capi-lab` | LXD project name. Lowercase alnum / `_` / `-`, ≤63 chars. |
| `lxd_project_description` | `k8s-lab — CAPN substrate project` | Free-form description. |
| `lxd_project_lxd_socket_path` | `/var/snap/lxd/common/lxd/unix.socket` | Path to the LXD unix socket (consumed by `ansible.builtin.uri`). |

### Substrate baseline (role-internal)

Project feature isolation and the `restricted=true` allow-list are
not exposed as user-overridable defaults — they live in
`vars/main.yml`. Every key there is consumed by another role in this
repo, so disabling any of them silently breaks downstream:

* `features.{images, profiles, storage.volumes, storage.buckets}` =
  `true` — project owns its own copy of those.
* `features.{networks, networks.zones}` = `false` — LXD rejects
  `bridge` networks in non-default projects (plan §13.5 deviation),
  so we inherit the default project's read-only view.
* `restricted = true` — turn on the allow-list.
* `restricted.containers.nesting = allow` — k8s nodes need nesting.
* `restricted.containers.privilege = unprivileged` — plan §2.8 hard-lock.
* `restricted.containers.lowlevel = allow` — profiles need
  `raw.lxc` + `linux.kernel_modules`.
* `restricted.containers.interception = allow` — profiles need
  `security.syscalls.intercept.*` for containerd.
* `restricted.devices.disk = managed` — only LXD-managed pool volumes.
* `restricted.devices.nic = allow` — external plane attaches through
  the host-level Linux bridge `br-ext6` owned by `lxd_host`, which
  LXD classifies as "unmanaged" (a future iteration may wrap it in a
  LXD-managed bridge and tighten this back).
* `restricted.devices.unix-char = allow` — profiles map host
  `/dev/kmsg` into k8s nodes for kubelet's oomWatcher.

### Extensions

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_project_extra_restrictions` | `{}` | Extra `restricted.*` keys merged on top of the baseline. Use to layer additional restrictions; not for disabling baseline values. |

### Flow control

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_project_enabled` | `true` | Whole-role toggle. |
| `lxd_project_flow_control_project` | `true` | Skip the project create/update section. |

## Tags

Both `_` and `-` spellings are accepted (plan §2.6.3):

* `lxd_project` / `lxd-project` — the whole role.
* `lxd_project_preflight` — input validation only.
* `lxd_project_project` — project create/update.
* `lxd_project_healthchecks` — in-role healthchecks.

## Example

```yaml
- hosts: k8slab_host
  become: true
  roles:
    - role: lxd_project
      vars:
        lxd_project_name: "capi-lab"
        # Layer an extra restriction on top of the baseline:
        lxd_project_extra_restrictions:
          restricted.virtual-machines.lowlevel: "block"
```

## Testing

Ships a Molecule delegated-driver scenario under
`tests/molecule/lxd-project/` that:

* converges the role on the shared Vagrant VM (pulls `lxd_host` and
  `base_system` in transitively through meta dependencies);
* re-converges and asserts idempotence;
* runs a verify playbook that reads the live project config via
  `lxc project show` and asserts every feature flag and restriction
  key the role owns.

Run locally:

```bash
make -C tests/molecule lxd-project-delegated-test
```

## Caveats

* The role talks to the LXD REST API through `ansible.builtin.uri`
  rather than `community.general.lxd_project`. The community module's
  diff logic silently dropped `features.*` transitions in local tests
  (accepted by LXD via `lxc project set`, accepted via raw REST, but
  reported `changed=0` without a PATCH being sent). `uri` gives
  explicit control over the wire payload and matches how the rest of
  this repo's Phase 2 roles (lxd_storage_pools,
  lxd_network_int_managed) talk to LXD — still native-first per plan
  §2.6.1.
* PATCH semantics mean the role PATCHes rather than PUTs — keys the
  operator set by hand outside this role's contract are left alone.
* `lxc project show` in healthchecks is a documented shell fallback
  (plan §2.6.1): the `community.general.lxd_*_info` family does not
  cover projects, and reading the state is the only way to catch a
  silent drift after converge.
