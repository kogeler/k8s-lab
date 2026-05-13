# Contributing

Thanks for the interest. `k8s-lab` is a **reusable building-block
repository** — Ansible roles, a Terraform module, and Helm charts that
a separate, private "consumer" repository imports and composes into a
real deployment. The boundary between this repo and a consumer repo is
[a deliberate architectural rule](doc/01-overview.md), not a missing
feature.

## Before opening a PR

- Read [`doc/04-repository-structure.md`](doc/04-repository-structure.md)
  for the directory layout, naming rules, and variable conventions.
- Read [`doc/12-testing.md`](doc/12-testing.md) for the Molecule +
  Vagrant + libvirt harness.
- All `Makefile` lint targets must pass:
  ```
  make lint
  ```
- For any role / chart / module you touch, the matching Molecule
  scenario must converge end-to-end on the local Vagrant VM. The
  project policy is **no untested commits**:
  ```
  make -C tests/vagrant/debian13 up
  make -C tests/molecule <scenario>-delegated-converge
  make -C tests/molecule <scenario>-delegated-verify
  ```
- After pushing, the GitHub Actions Molecule workflow
  ([`.github/workflows/molecule.yml`](.github/workflows/molecule.yml))
  runs the same canonical end-to-end flow on `ubuntu-latest` via the
  CI-only `tests/molecule/gha` scenario — see
  [`doc/12-testing.md`](doc/12-testing.md) §11. **Do not run the gha
  scenario locally**: it mutates host networking, snap, iptables,
  swap, and `/etc/fstab` in ways meant for an ephemeral runner; a
  three-layer guard refuses local invocation.

## Scope

| Welcome | Out of scope |
|---------|--------------|
| Bug fixes in existing roles / charts / module. | New CNI / load-balancer choices (see [`doc/03-stack.md`](doc/03-stack.md)). |
| Documentation fixes under `doc/`. | Site-specific inventories, secrets, tfvars (those live in a consumer repo). |
| Test-harness improvements under `tests/`. | Privileged-LXC support (closed by design — plan `§2.8`). |
| New Molecule scenarios that cover existing roles. | Raw `kubectl apply -f` paths (forbidden — plan `§2.9`). |
| Stage 2 backlog items listed in [`plans/PLAN-stage2-common.md`](plans/PLAN-stage2-common.md), once a design step is agreed. | Host-firewall management (plan `§11.4`). |

## Plans and the source of truth

The `plans/PLAN-stage*.md` files are the architectural source of truth
— they say **why** a decision was made. The `doc/` files say **how**
to use the result. The code says **what** is implemented. A PR that
changes architectural behaviour must update the relevant `§N` section
in the plan in the same change (continuous `§N` numbering across all
plan files).

## Style

- **Ansible:** native-first (`ansible.builtin.*` and collection
  modules). `shell` / `command` / `script` only as a documented
  last-resort fallback (plan `§2.6.1`), and never with
  `changed_when: false` on a mutating step.
- **Helm:** every Kubernetes object must be delivered via a chart in
  `charts/`. No raw manifests, no `kubectl apply -f`.
- **Terraform:** module-only; the public `terraform/modules/workload_cluster`
  is the single front door. Provider versions are pinned in
  `versions.tf`.
- **Naming:** project-global variables use the `k8s_lab_` prefix.
  Role-scoped variables keep their role prefix.

## Reporting issues

Open a GitHub issue describing:

- what you tried (commit hash, role / chart name, `make` target);
- what happened (logs, `terraform plan` output, Molecule failure);
- what you expected.

For security issues, see [`SECURITY.md`](SECURITY.md).
