# export_artifacts

Close Phase 4 by shipping the bootstrap-management-cluster handoff
bundle from the LXD host to the runner's `.artifacts/` dir. Plan §16.6
/ §11.1.

## Scope

Produces on the runner:

* `.artifacts/bootstrap.kubeconfig` — admin kubeconfig for the
  bootstrap k3s cluster, pulled from the host-side path
  `bootstrap_clusterctl` materialises (server URL already rewritten
  to the container's eth0 IPv4). Phase 5 Terraform fixtures pass this
  path to the `kubernetes` / `helm` providers.
* `.artifacts/bootstrap.auto.tfvars.json` — the fact bundle Phase 5
  root modules auto-load (`*.auto.tfvars.json` is a Terraform-native
  convention, no extra `-var-file` wiring). Keys mirror the plan §8
  global contract verbatim (`k8s_lab_*`) so a fixture's `variable
  "..."` blocks match 1:1.
* `.artifacts/clusters/` — created empty; reserved for Phase 5.05
  `target.kubeconfig` / workload kubeconfigs.

## Out of scope

* materialising `mgmt.kubeconfig` / `clusters/<cluster>.kubeconfig` —
  those are Phase 5 / 5.05 deliverables and depend on a workload
  cluster existing first (plan §17.8);
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

The bootstrap API server URL in the tfvars payload is derived from
the just-shipped kubeconfig — the kubeconfig already carries the
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

* `_export_artifacts_required_bootstrap_kubeconfig_filename`
  (`bootstrap.kubeconfig`) — Phase 5 fixtures reference this name
  verbatim;
* `_export_artifacts_required_tfvars_filename`
  (`bootstrap.auto.tfvars.json`) — Terraform only auto-loads files
  matching the `*.auto.tfvars.json` glob;
* `_export_artifacts_required_clusters_subdir` (`clusters`) —
  Phase 5.05 writes per-cluster kubeconfigs under this subpath;
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
  `k8s_lab_bootstrap_api_server_url` matches the kubeconfig's URL.
