# export_artifacts

Close Phase 4 by shipping the management-cluster handoff bundle from
the LXD host to the runner's `.artifacts/` dir. Plan §15.6 / §11.1.

## Scope

Produces on the runner:

* `.artifacts/mgmt.kubeconfig` — admin kubeconfig for the active
  management cluster. In MVP path that is the bootstrap k3s cluster
  (pulled from the host-side path `bootstrap_clusterctl` materialises,
  with the server URL already rewritten to the container's eth0 IPv4).
  In Stage 2 pivot path the same file is overwritten in place by
  `pivot_clusterctl_move` after `clusterctl move` — pre- and post-pivot
  consumers point at the same path. Phase 5 Terraform fixtures pass
  this path to the `kubernetes` / `helm` providers.
* `.artifacts/mgmt.auto.tfvars.json` — the fact bundle Phase 5 root
  modules auto-load (`*.auto.tfvars.json` is a Terraform-native
  convention, no extra `-var-file` wiring). Keys mirror the plan §8
  global contract verbatim (`k8s_lab_*`) so a fixture's `variable
  "..."` blocks match 1:1.
* `.artifacts/clusters/` — created empty; reserved for per-workload
  kubeconfig debug copies written by Molecule e2e-local verify.

## Out of scope

* generating trust material for the runner — CAPN identity cert/key
  stay in LXD trust store, not in `.artifacts/`;
* committing the bundle — `.artifacts/` is gitignored; plan §11.1
  forbids plaintext secrets in the repo.

## Execution model

Role runs on the LXD host through the `bootstrap_capn_secret`
meta-dep chain (same host boundary every other Phase 4 role uses).
Artefact-write tasks flip to `delegate_to: localhost, become: false,
run_once: true` so files land under the runner user's UID with mode
0600 (plan §11.1). No controller-side `sudo` is required.

The mgmt API server URL in the tfvars payload is derived from the
just-shipped kubeconfig — the kubeconfig already carries the
rewritten container IPv4, so there's no second LXD REST probe.

## Idempotence

* `ansible.builtin.slurp` + `ansible.builtin.copy` compare bytes on
  the destination; unchanged inputs ⇒ `changed=false` on the second
  converge.
* `to_nice_json(sort_keys=True)` yields a deterministic payload for
  identical inputs, so tfvars rewrites are byte-stable too.
* Directory creation uses `state: directory` which is no-op when the
  dir already exists at the requested mode.

## Substrate-required vs. tunable

Memory rule `feedback_required_values_hardcoded.md`. `vars/main.yml`
holds values whose empty / wrong override would silently produce a
broken handoff:

* `_export_artifacts_required_mgmt_kubeconfig_filename`
  (`mgmt.kubeconfig`) — Phase 5 fixtures reference this name verbatim;
  the same path is overwritten in place across the pivot boundary;
* `_export_artifacts_required_tfvars_filename`
  (`mgmt.auto.tfvars.json`) — Terraform only auto-loads files
  matching the `*.auto.tfvars.json` glob;
* `_export_artifacts_required_clusters_subdir` (`clusters`) —
  Molecule e2e-local writes per-workload debug copies under this
  subpath;
* `_export_artifacts_required_file_mode` (`0600`) and
  `_export_artifacts_required_dir_mode` (`0700`) — plan §11.1 secret
  contract.

Public defaults expose only tunable surface: the whole-role toggle,
per-artefact toggles, the source kubeconfig path on the host, and a
`export_artifacts_tfvars_extra` merge-on-top dict for environment-
specific additions.

## Public variables

See `defaults/main.yml`. The one required input is
`export_artifacts_root` — an absolute runner-side path, no
auto-guessing (plan §11.1 fixes the contract, not the path).

`export_artifacts_run_meta_chain` (default `true`) gates the Phase 4
meta-dep import: the canonical first invocation runs the full
substrate chain, the post-pivot re-emit invocation sets it to
`false` (substrate is already up; bootstrap LXC may be retired by
the time the role's tasks finish, so re-running the chain would
either waste work or fail outright trying to talk to a dead
bootstrap API). The flag is consumed inside `meta/main.yml` via
`when:` on the `bootstrap_capn_secret` dependency.

## Testing

Molecule scenario: `tests/molecule/export-artifacts/`. Runs the
full meta-dep chain end-to-end on a Vagrant VM (plan §9.1):
`base_system → lxd_host → lxd_project → lxd_storage_pools →
lxd_network_int_managed → lxd_profiles → binary_fetch →
lxd_bootstrap_instance → bootstrap_k3s → bootstrap_clusterctl →
bootstrap_capn_secret → export_artifacts`.

Verify asserts:
* both artefacts exist on the runner under `export_artifacts_root`;
* mode is `0600`;
* kubeconfig is parseable YAML with a non-127.0.0.1 server URL;
* tfvars is parseable JSON, contains baseline `k8s_lab_*` keys, and
  `k8s_lab_mgmt_api_server_url` matches the kubeconfig's URL.
