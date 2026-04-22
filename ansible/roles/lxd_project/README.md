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

### Feature isolation

Dict of `features.*` booleans. `true` = project owns its own copy,
`false` = project shares the `default` project's copy (read-only).

| Key | Default | Notes |
| --- | --- | --- |
| `images` | `true` | |
| `profiles` | `true` | |
| `networks` | `false` | LXD rejects `bridge` networks in non-default projects — inherit instead. |
| `networks.zones` | `false` | Must match `networks`; LXD enforces the pair. |
| `storage.volumes` | `true` | |
| `storage.buckets` | `true` | |

### Restrictions

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_project_restricted` | `true` | Master `restricted=true` flag — turns on the allow-list. |
| `lxd_project_restrictions` | see below | Dict of `restricted.*` keys to string values. |

Default `lxd_project_restrictions`:

```yaml
restricted.containers.nesting:   "allow"         # required by kubeadm nodes
restricted.containers.privilege: "unprivileged"  # plan §2.8 — no privileged path
restricted.devices.disk:         "managed"       # only LXD-managed pool volumes
restricted.devices.nic:          "allow"         # plan §4-5 external plane uses host bridge br-ext6
restricted.containers.lowlevel:  "allow"         # profiles need linux.kernel_modules / raw.lxc
```

`restricted.devices.nic` is deliberately `allow` (not `managed`):
the external plane attaches through the host-level Linux bridge
`br-ext6` owned by `lxd_host`, which LXD classifies as "unmanaged"
— `managed` rejects those NICs outright. A future iteration may
wrap `br-ext6` in a LXD-managed bridge via
`bridge.external_interfaces` and tighten this restriction back.

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
        lxd_project_restrictions:
          restricted.containers.nesting:   "allow"
          restricted.containers.privilege: "unprivileged"
          restricted.devices.disk:         "managed"
          restricted.devices.nic:          "managed"
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
