# binary_fetch

Fetch pinned `kubectl` / `clusterctl` / `k3s` release binaries into
`/opt/capi-lab/bin` on the k8s-lab host with upstream sha256
verification.

## Purpose

Plan §16.1. The role owns exactly the "binary delivery" step:

* downloads each binary from its upstream release asset URL;
* extracts the expected sha256 from the corresponding upstream
  `.sha256` / `sha256sum-*.txt` file and feeds it to
  `ansible.builtin.get_url` so the download is rejected on any
  fingerprint drift;
* writes the artefact with deterministic owner / group / mode;
* asserts that the binary runs and reports the pinned version back.

It does **not**:

* install any APT package or add a custom APT repo — that is
  [`base_system`'s](../base_system/README.md) lane (plan §2.2);
* run `install.sh`-style shell scripts — the binary is laid as a plain
  static file;
* push anything into LXC containers — that is the job of Phase 4 roles
  (`bootstrap_k3s` and friends).

## Checksum model

The verified-version log in `PLAN-stage1-common.md §8a` pins a single
version per binary. The role supports three checksum sourcing styles —
the choice per binary follows upstream practice:

| Style | Used for | Flow |
| --- | --- | --- |
| `plain` | kubectl | GET `<url>.sha256` (single-line hex digest), feed to `get_url` |
| `manifest` | k3s | GET `sha256sum-<arch>.txt` (`sha256sum(1)` format), pick the row where the name column matches `checksum_entry`, feed the digest to `get_url` |
| `pinned` | clusterctl | Upstream publishes no sha256 artefact — the digest is pinned in `defaults/main.yml` (audited at version bump time via `sha256sum` on the control node) |

In every case `ansible.builtin.get_url` receives `checksum=sha256:<digest>`
so tampering with the binary content fails the task; a re-run with an
already-correct file skips the download entirely (idempotent).

For the `plain` and `manifest` styles the pin + upstream asset is the
only source of truth — the digest is recomputed each run from the
upstream sha256 file. For `pinned` (clusterctl), the digest lives
alongside the version pin and must be refreshed together when the
version is bumped.

## Requirements

* Target host: Debian 13 Trixie or newer (`base_system` enforces).
* Outbound HTTPS reachability to `dl.k8s.io` and `github.com`.
* `ca-certificates` and `curl` already present (provided by
  `base_system`'s apt baseline).
* Ansible ≥ 2.16 on the control node.

## Role variables

All public variables use the `binary_fetch_*` prefix; internal values
use `_binary_fetch_*` and must not be consumed outside the role.

### General

| Variable | Default | Description |
| --- | --- | --- |
| `binary_fetch_enabled` | `true` | Whole-role toggle; preflight still runs when `false`. |
| `binary_fetch_opt_root` | `/opt/capi-lab` | Shared filesystem root (must match `base_system_opt_root`). |
| `binary_fetch_bin_dir` | `{{ binary_fetch_opt_root }}/bin` | Destination directory. |
| `binary_fetch_owner` / `binary_fetch_group` | `root` / `root` | Ownership applied to every artefact. |
| `binary_fetch_mode` | `0755` | Mode (octal string) applied to every artefact. |
| `binary_fetch_download_timeout` | `180` | Wall-time budget for each `uri` / `get_url` call (seconds). |
| `binary_fetch_arch` | `amd64` | Only `amd64` is currently wired; aarch64 would require URL-template work. |

### Per-binary pins

Each binary exposes a version pin, its URL template, its checksum URL
template, the checksum style and the destination filename. See
`defaults/main.yml` for the canonical list; the shape is identical for
kubectl, clusterctl and k3s (the only extra knob on k3s is
`binary_fetch_k3s_checksum_entry`, which names the filename column in
the `sha256sum-<arch>.txt` manifest).

### Flow control

| Variable | Default | Description |
| --- | --- | --- |
| `binary_fetch_flow_control_kubectl` | `true` | Skip the kubectl section when `false`. |
| `binary_fetch_flow_control_clusterctl` | `true` | Skip the clusterctl section when `false`. |
| `binary_fetch_flow_control_k3s` | `true` | Skip the k3s section when `false`. |
| `binary_fetch_kubectl_enabled` / `..._clusterctl_enabled` / `..._k3s_enabled` | `true` | Per-binary toggle — flow-control + enabled are both checked. |

## Tags

Per-section tags follow the repo convention (plan §2.6.3); both
underscore and hyphen spellings are accepted:

* `binary_fetch` / `binary-fetch` — everything.
* `binary_fetch_preflight` — input validation only.
* `binary_fetch_kubectl` / `binary_fetch_clusterctl` / `binary_fetch_k3s` — per-binary download + verification.
* `binary_fetch_healthchecks` — post-install runtime checks.

## Example

```yaml
- hosts: k8slab_host
  become: true
  roles:
    - role: binary_fetch
      vars:
        # Track the plan §8 contract values — the verified-version log
        # in §8a records the audit date.
        binary_fetch_kubectl_version:    "v1.35.3"
        binary_fetch_clusterctl_version: "v1.12.5"
        binary_fetch_k3s_version:        "v1.35.3+k3s1"
```

## Testing

The repo ships a Molecule delegated-driver scenario at
`tests/molecule/binary-fetch/`. It converges `binary_fetch` on the
shared Vagrant VM, asserts idempotence, and runs a verify playbook
that checks:

* each expected binary file exists in `/opt/capi-lab/bin/` with the
  declared ownership, mode and a plausible size;
* the sha256 of the on-disk file matches the digest derived from the
  upstream sha256 asset;
* each binary runs and reports a version string that contains the
  pinned version substring.

Run locally:

```bash
make -C tests/molecule binary-fetch-delegated-test
```

## Caveats

* The role fetches the sha256 file on every converge. This is
  intentional — it makes the pin + upstream asset the single source of
  truth and avoids a second digest table in the repo. The trade-off is
  one small HTTPS GET per binary per run (well under the download
  timeout).
* `get_url` computes the hash of the destination before downloading;
  when a file already matches, the task reports `changed=false` and
  the network fetch is skipped.
* kubectl's `.sha256` file historically contains just the hex digest,
  whereas some other Kubernetes assets use a `<hex>  <name>` format.
  The role's `plain` parser takes the first whitespace-separated
  token, so both layouts work.

[plan]: ../../../PLAN-stage1-common.md
