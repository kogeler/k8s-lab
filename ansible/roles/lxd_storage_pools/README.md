# lxd_storage_pools

Create and configure LXD storage pools (plan §13.4).

## Purpose

Owns LXD storage pool objects. Pools themselves are global LXD entities;
project scoping happens through `restricted.devices.disk=managed` on the
project (owned by `lxd_project`). This role does not touch volumes,
profile device references, or the consumer workloads — each of those is
handled by its own role.

Implemented entirely through the LXD REST API via
`ansible.builtin.uri` over the snap unix socket. No shell fallbacks —
`community.general` ships an `_info` module for pools but no CREATE
module, and `uri` is the closest native equivalent to a declarative API
client (plan §2.6.1).

## Requirements

* Target host runs **Debian 13 Trixie** or newer.
* `lxd_project` has already run (pulls in `lxd_host`, which pulls in
  `base_system`). Declared as a meta dependency so callers get the full
  chain automatically (plan §2.6.5).
* Host disk(s) backing the pool are prepared per the chosen driver:
  * `btrfs` on a block device — the device must be free of filesystem
    signatures on first converge; LXD formats it in place.
  * `dir` — target directory exists and is empty.
* `ansible.builtin.uri` (built in — no extra collection).

## Role variables

All public variables use the `lxd_storage_pools_*` prefix (plan §2.6.2).

### General

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_storage_pools_lxd_socket_path` | `/var/snap/lxd/common/lxd/unix.socket` | Path to the LXD unix socket used by `ansible.builtin.uri`. Note: bare path, not a `unix:` URI. |

### Pools

`lxd_storage_pools_pools` is a list of pool definitions. Each entry:

| Field | Required | Description |
| --- | --- | --- |
| `name` | yes | LXD pool name. Lowercase alnum / `_` / `-`, start with a letter, ≤63 chars. |
| `driver` | yes | One of `btrfs`, `dir`, `lvm`, `zfs`. |
| `description` | no | Free-form description stored on the pool. |
| `config` | yes | Dict of LXD storage pool config keys. Values must be strings (LXD wire contract). `config.source` must be non-empty. |

Default list:

```yaml
lxd_storage_pools_pools:
  - name:        "capi-fast"
    driver:      "btrfs"
    description: "k8s-lab primary pool (btrfs on dedicated block device)"
    config:
      source: ""   # caller MUST override — preflight rejects empty
```

**Driver-required config baseline (role-internal, not user-overridable):**
driver-specific keys every k8s-lab pool must carry live in
`vars/main.yml` as `_lxd_storage_pools_driver_required_config` and are
merged on top of each entry's user-supplied `config` at apply time —
**required keys always win**, so an override in `lxd_storage_pools_pools`
cannot silently drop them. Currently:

```yaml
btrfs:
  btrfs.mount_options: "user_subvol_rm_allowed"
```

(kubelet garbage-collection inside unprivileged CAPN nodes breaks
without `user_subvol_rm_allowed`). Non-btrfs drivers have empty baselines
for now; add more driver-specific keys here if the substrate requires
them.

### Flow control

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_storage_pools_enabled` | `true` | Whole-role toggle. |
| `lxd_storage_pools_flow_control_pools` | `true` | Skip the create/update section. |

## Tags

Both `_` and `-` spellings are accepted (plan §2.6.3):

* `lxd_storage_pools` / `lxd-storage-pools` — the whole role.
* `lxd_storage_pools_preflight` — input validation only.
* `lxd_storage_pools_pools` — pool create / drift correction.
* `lxd_storage_pools_healthchecks` — in-role healthchecks.

## Example

```yaml
- hosts: k8slab_host
  become: true
  roles:
    - role: lxd_storage_pools
      vars:
        lxd_storage_pools_pools:
          - name:        "capi-fast"
            driver:      "btrfs"
            description: "primary pool"
            config:
              # `btrfs.mount_options=user_subvol_rm_allowed` is merged
              # on top automatically from vars/main.yml — only `source`
              # needs to come from the consumer here.
              source: "/dev/disk/by-id/virtio-k8slab-lxdpool"
```

## Testing

Ships a Molecule delegated-driver scenario under
`tests/molecule/lxd-storage-pools/` that:

* wipes filesystem signatures off the dedicated LXD-pool block device
  in `prepare.yml` so LXD can format it in place;
* converges the role (pulls `lxd_project` / `lxd_host` / `base_system`
  in through meta dependencies);
* asserts idempotence and runs a verify playbook that reads the live
  pool state back through `ansible.builtin.uri` and asserts driver /
  `volatile.initial_source` / every declared config key.

Run locally:

```bash
make -C tests/molecule lxd-storage-pools-delegated-test
```

## Caveats

* **`source` is a one-time creation parameter.** LXD replaces
  `config.source` with the filesystem UUID after first mount and keeps
  the original path under `config.volatile.initial_source`. Healthchecks
  assert against `volatile.initial_source`; the PATCH drift step skips
  `source` entirely. Changing the backing device of an existing pool
  requires deleting and recreating it by hand.
* **Block device must be signature-free on first converge.** `lxc
  storage create <pool> btrfs source=<dev>` runs `mkfs.btrfs` without
  `-f` internally, so any pre-existing filesystem on the device aborts
  the create. The Molecule scenario wipes signatures in `prepare.yml`
  for this reason; production hosts are expected to supply a clean
  disk.
* **`uri` vs `community.general`.** The pool lifecycle is driven by
  `ansible.builtin.uri` because `community.general` does not ship a
  CREATE module for storage pools (only `_info`). This keeps the role
  native-first (plan §2.6.1).
