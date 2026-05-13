# Agent Guide

This file is the short working context for future coding agents. It is
deliberately a router, not a duplicate of the full plans and documentation.
When in doubt, follow the linked source of truth.

## Project In One Paragraph

`k8s-lab` is a reusable building-block repository for a single-host
Kubernetes lab on Debian or Ubuntu Linux. Kubernetes nodes are unprivileged
LXC/LXD system containers. Cluster lifecycle is driven by Cluster API with
CAPN. A transient k3s bootstrap LXC installs CAPI/CAPN, management ownership is
pivoted to a self-hosted `mgmt-1` cluster, and workload clusters are then
created through the single Terraform module. The repo ships Ansible roles,
Terraform module code, Helm charts, scripts, and a local Molecule + Vagrant +
libvirt harness. Real inventories, secrets, tfvars, backends, and production
orchestration live in private consumer repositories.

## Source Of Truth

- Start at [README.md](README.md) for the high-level project shape.
- Use [doc/README.md](doc/README.md) as the user-facing documentation index.
- Use [llms-full.txt](llms-full.txt) only when a single-file documentation
  snapshot is useful; regenerate it with `make docs-llm` after changing `doc/`.
- The plans under [plans/](plans/) are the architectural source of truth for
  why decisions exist. Section numbering is continuous across the plan files.
- The documentation under [doc/](doc/) is the source of truth for how users and
  operators work with the implemented system.
- The code is the source of truth for what is implemented now. Do not infer a
  new behavior from the backlog unless it is present in code.

Important entry points:

- [doc/01-overview.md](doc/01-overview.md): scope, goals, non-goals.
- [doc/02-architecture.md](doc/02-architecture.md): canonical flow, dual-NIC
  model, layer ownership, Gate A/B.
- [doc/03-stack.md](doc/03-stack.md): pinned external dependency versions.
- [doc/04-repository-structure.md](doc/04-repository-structure.md): directory
  layout, naming rules, variable-prefix contracts.
- [doc/08-configuration-reference.md](doc/08-configuration-reference.md):
  project globals, role inputs, Terraform inputs/outputs, chart values.
- [doc/09-roles-reference.md](doc/09-roles-reference.md): Ansible role index.
- [doc/10-modules-and-charts.md](doc/10-modules-and-charts.md): Terraform
  module and Helm chart contracts.
- [doc/12-testing.md](doc/12-testing.md): local validation policy and harness.
- [doc/13-troubleshooting.md](doc/13-troubleshooting.md): known failure modes.
- [CONTRIBUTING.md](CONTRIBUTING.md): contribution scope, style, and pre-PR
  checks.
- [CHANGELOG.md](CHANGELOG.md): per-version diff log. Each section is the
  authoritative source for the matching GitHub release body — release notes
  are a verbatim copy, never rewritten.
- [plans/PLAN-stage1-common.md](plans/PLAN-stage1-common.md): fixed
  architecture and development contracts.
- [plans/PLAN-stage2-common.md](plans/PLAN-stage2-common.md): opt-in backlog.
- [plans/PLAN-stage2-1.md](plans/PLAN-stage2-1.md): §23 — Step 18 hosted CI
  path on GitHub Actions (completed).

## Non-Negotiable Contracts

- This is a reusable implementation repo, not a site repo. Do not add real
  inventories, real host vars, plaintext secrets, real tfvars, production
  Terraform roots, or `make deploy TARGET=...` style orchestration here. See
  [doc/07-deployment-guide.md](doc/07-deployment-guide.md) for the consumer
  repo pattern.
- Target and local test platform is Debian 13. LXD is installed via pinned snap
  channel. Non-standard binaries are pinned, checksum-verified, and placed
  under `/opt/capi-lab/bin`.
- LXC nodes and the bootstrap LXC are unprivileged only. Privileged LXC is not
  an option, fallback, or toggle.
- The canonical flow is single-path: substrate -> bootstrap k3s ->
  `clusterctl init` -> `mgmt-1` install -> Gate A/B -> pivot -> bootstrap
  cleanup -> workload cluster. Pivot is mandatory.
- Node networking is dual-NIC: `eth0` is internal dual-stack and carries the
  default route, kubelet node IP, and egress; `eth1` is external IPv6-only for
  ingress, NodePort, and MetalLB VIPs.
- Ansible owns host bootstrap, LXD substrate, bootstrap management cluster,
  local harness, and artifact export. Terraform owns CAPI objects, guest node
  networking, kube-proxy policy, workload add-ons, and chart-side acceptance
  invocation. Helm charts are the only carrier for Kubernetes objects.
- Raw manifest application paths are forbidden for create/update:
  no `kubectl apply -f`, no `kubernetes_manifest`, and no
  `kubernetes.core.k8s state=present` for project-owned Kubernetes objects.
  Read-side status checks are allowed.
- Stage 2 backlog items require a design step, a plan update with a new step
  marker, implementation, and a fresh local Molecule/e2e regression. They must
  not weaken Stage 1 invariants.

## Repository Map

- `ansible/`: 14 reusable roles plus `ansible.cfg` and collection requirements.
- `charts/`: five local Helm charts:
  `capi-cluster-class`, `capi-workload-cluster`, `cni-calico`, `metallb`,
  `metallb-config`.
- `terraform/modules/workload_cluster/`: the only shipped Terraform module.
- `tests/molecule/`: per-role scenarios, the composite `e2e-local`
  scenario for the local Vagrant harness, and the CI-only `gha`
  scenario invoked through `.github/workflows/molecule.yml`.
- `tests/vagrant/debian13/`: shared local libvirt VM harness.
- `.github/workflows/molecule.yml`: the CI workflow that runs the
  `gha` Molecule scenario on `ubuntu-latest`. See
  [doc/12-testing.md](doc/12-testing.md) §11 for the substrate-
  specific overrides and failure-diagnostic contract.
- `tests/fixtures/terraform/workload-clusters/lab-default/`: the only
  Terraform root in this repo, used as a test consumer.
- `scripts/`: harness helpers, kubeconfig rendering, bootstrap fact export,
  cluster readiness polling.
- `.artifacts/`: runtime-only, gitignored except placeholders; may contain
  kubeconfigs and tfvars handoff files with mode `0600`.

## Working Rules By Area

### Ansible

- Mirror [doc/04-repository-structure.md](doc/04-repository-structure.md) and
  plan section 2.6.
- Role directories are `snake_case`; task and handler display names use
  kebab-case and the `<role> | <section> | <action>` pattern.
- `tasks/main.yml` is dispatcher-only and should include topical files such as
  `preflight.yml`, `install.yml`, `config.yml`, `healthchecks.yml`.
- Public role variables live in `defaults/main.yml` and use
  `<role_name>_*`. Private facts/registers use `_<role_name>_*`.
- Cross-role values go through `k8s_lab_*` globals or explicit `set_fact`
  outputs. A role must not read another role's `<other_role>_*` variables.
- Role dependencies belong in `meta/main.yml`, with one-line comments saying
  why each dependency exists. Do not fake role ordering in Molecule `prepare`.
- Prefer native Ansible modules, then collection modules. `shell`, `command`,
  `script`, `raw`, or mutating `uri` calls require an idempotence wrapper and
  honest `changed` semantics.
- Keep the role README and [doc/09-roles-reference.md](doc/09-roles-reference.md)
  current when public behavior or inputs change.

### Terraform

- The only module is
  [terraform/modules/workload_cluster/](terraform/modules/workload_cluster/).
  Do not add site-specific roots under `terraform/`.
- The module installs CAPI topology, CNI, MetalLB, MetalLB config, and
  chart-side acceptance tests through Helm releases.
- Keep provider version constraints in `versions.tf` and public inputs/outputs
  documented in [doc/08-configuration-reference.md](doc/08-configuration-reference.md)
  and [doc/10-modules-and-charts.md](doc/10-modules-and-charts.md).
- Test fixture logic under `tests/fixtures/terraform/` must stay a consumer of
  reusable code, not a second implementation layer.

### Helm Charts

- Every Kubernetes object this repo creates belongs in a chart under `charts/`.
- Update `values.yaml` and `values.schema.json` together.
- Preserve the chart-version-as-CR-name pattern for immutable CAPI CRs. A
  ClusterClass/template change normally means a chart version bump and a new CR
  name, not an in-place mutation.
- Gate B lives in `charts/cni-calico`; Gate A lives in
  `charts/metallb-config`. Failed chart tests must fail deployment.
- Keep chart behavior documented in
  [doc/10-modules-and-charts.md](doc/10-modules-and-charts.md).

### Tests And Harness

- The main testing reference is [doc/12-testing.md](doc/12-testing.md).
- `make lint` runs YAML, Ansible, Terraform formatting, and Helm lint checks.
- Per-role Molecule scenarios live under `tests/molecule/<role-in-kebab-case>/`.
  The scenario-to-role mapping is part of the contract.
- `pivot_clusterctl_move` is covered by `e2e-local`, not by a standalone
  Molecule scenario.
- For Ansible role changes, run the affected scenario and consider the
  dependency chain described in [doc/12-testing.md](doc/12-testing.md).
- For chart or Terraform module changes, validate via the local harness path
  that installs through the module, such as `make deploy-workload` on an
  existing management cluster or `make test-local-e2e`.
- Long e2e runs should be streamed to a log, for example:
  `make test-local-e2e &> /tmp/k8s-lab-e2e.log &` and
  `tail -f /tmp/k8s-lab-e2e.log`.
- Do not claim a test passed unless it actually ran in this workspace.
- The CI-only `gha` scenario (`tests/molecule/gha/`) is strictly forbidden
  to run locally — three-layer guard (playbook assert + Makefile target
  guard + workflow-only invocation), see
  [doc/12-testing.md](doc/12-testing.md) §5.3 and §11. The agent must NEVER
  invoke `make -C tests/molecule gha-local-*` from the dev box; use the
  Vagrant `e2e-local` flow for local equivalence and let the CI run for
  GHA verification.

## Documentation And Plan Updates

- If behavior changes, update the nearest user-facing chapter under `doc/`.
- If an architectural contract changes, update the relevant plan section in
  [plans/](plans/) in the same change.
- If role variables change, update
  [doc/08-configuration-reference.md](doc/08-configuration-reference.md) and
  [doc/09-roles-reference.md](doc/09-roles-reference.md).
- If chart values or module inputs change, update
  [doc/08-configuration-reference.md](doc/08-configuration-reference.md) and
  [doc/10-modules-and-charts.md](doc/10-modules-and-charts.md).
- If a new failure mode is debugged, add a recipe to
  [doc/13-troubleshooting.md](doc/13-troubleshooting.md).
- After changes under `doc/`, regenerate [llms-full.txt](llms-full.txt) with
  `make docs-llm`.

## Runtime And Safety Notes

- Do not commit `.artifacts/`, `ansible/collections/`,
  `tests/vagrant/debian13/.vagrant/`, Molecule state, Terraform state, or real
  kubeconfigs.
- Use the Makefile targets for local lifecycle operations:
  `make test-local-harness`, `make test-local-e2e`, `make deploy-workload`,
  `make workload-kubeconfig`, `make destroy-workload`, `make destroy-vm`,
  `make clean-local`, `make reset-all`.
- `destroy-*` targets affect running local infrastructure; use them only when
  the task requires it or the user asked for a reset.
- Prefer finding the closest existing role/chart/module pattern and extending
  it consistently over adding a new abstraction.
