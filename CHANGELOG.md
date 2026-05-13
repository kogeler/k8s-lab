# Changelog

All notable changes to `k8s-lab` are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each tagged release on GitHub is created **only after** the matching
section below is merged into `main`; the release body is a verbatim
copy of the section here (no rewriting, no expansion).

---

## [Unreleased]

_No changes._

---

## [1.1] — 2026-05-13

Stage 2 — Step 18 lands. Additive change: every Stage 1 substrate
invariant (unprivileged-LXC only, helm-first delivery, mandatory
CAPI pivot, dual-stack networking, CAPI/CAPN version pins) is
preserved. Production target stays Debian 13; Ubuntu is added only
for the CI substrate.

Authoritative spec: `plans/PLAN-stage2-1.md` §23.

### Added

- Hosted CI on GitHub Actions — `tests/molecule/gha` Molecule
  scenario plus `.github/workflows/molecule.yml`. Runs the full
  canonical bootstrap → pivot → workload flow on `ubuntu-latest`
  via `ansible_connection: local` (no nested virtualisation).
  `converge.yml` and `verify.yml` `import_playbook` the `e2e-local`
  equivalents verbatim — single source of truth for the flow.
- `make -C tests/molecule gha-local-*` target family — CI-only,
  three-layer guard refuses local invocation (Makefile + playbook
  assert + workflow-only).
- `requirements-gha.txt` — fully pinned Python dependency lockfile
  for the CI workflow (primaries + transitives resolved on Python
  3.13).
- Role variable `bootstrap_clusterctl_cert_manager_timeout` (default
  `""` = inherit clusterctl's 10-min internal wait; rendered into
  `clusterctl.yaml` when non-empty).
- `plans/PLAN-stage2-1.md` — §23 / Step 18 spec, status: completed.
- `AGENTS.md` — router document for coding agents.

### Changed

- All 14 role preflights: OS gate widened from `Debian 13+` to
  `Debian 13+ OR Ubuntu 22.04+`. Purely additive.
- `doc/12-testing.md` §11 rewritten (was *"There is no CI"*); §2
  scenario table grew a 15th row for `gha`; new §5.3 documents the
  `gha-local-*` Makefile family.
- *"Debian-family Linux"* → *"Debian or Ubuntu Linux"* prose update
  across `README.md`, `AGENTS.md`, `CITATION.cff`, `mkdocs.yml`,
  `llms.txt`, all `doc/*.md`, and `tests/molecule/shared/verify.yml`.
  README badge updated.
- `plans/PLAN-stage2-common.md` — *Hosted CI path without local
  runner* item moved to `PLAN-stage2-1.md` (completed).
- Workflow installs Helm `v4.1.4` and kubectl `v1.35.3` via
  `azure/setup-{helm,kubectl}@v4`.

### Fixed

- `ansible/roles/lxd_host/tasks/bridge.yml` — `MulticastSnooping=no`
  on `br-ext6`. Without it the kernel snoops with no querier on the
  pure-L2 segment and stops flooding upstream Router Advertisements
  to container ports after the MLD membership timeout, breaking
  SLAAC on freshly joined CAPN nodes. Matching assertion added to
  `tests/molecule/lxd-host/verify.yml`.

### Acceptance

- GHA workflow run [25793173461](https://github.com/kogeler/k8s-lab/actions/runs/25793173461)
  — green on `tests/molecule/gha (e2e on runner)`.
- Local Vagrant clean-VM `make test-local-e2e` (2026-05-13) — three
  PLAY RECAPs, all `failed=0 unreachable=0`.

[Full diff](https://github.com/kogeler/k8s-lab/compare/v1.0...v1.1)
— 56 files, +2181 / -238.

---

## [1.0] — 2026-05-11

Initial public release. Stage 1 closed.

### Included

- 14 Ansible roles — host bootstrap → LXD substrate → transient k3s
  bootstrap cluster → CAPI/CAPN init → pivot to self-hosted mgmt →
  cleanup → harness plumbing.
- 1 Terraform module — `terraform/modules/workload_cluster`: CAPI
  objects, machine templates, guest networking, add-ons via
  `hashicorp/helm`.
- 5 Helm charts in `charts/` — `capi-cluster-class`,
  `capi-workload-cluster`, `cni-calico`, `metallb`, `metallb-config`.
  Single carrier for every Kubernetes object the project creates.
- Molecule + Vagrant + libvirt local harness.
- `Makefile` for `lint` / `test-local-e2e` / `deploy-workload` /
  `reset-all` / `clean-local`.

### Substrate contract

- Single bare-metal Debian 13 host; **unprivileged-LXC only** (no toggle).
- Default topology: workload 3 CP + 2 worker, mgmt 1 CP + 2 worker
  (self-hosted after pivot).
- Mandatory CAPI bootstrap-and-pivot; bootstrap k3s LXC destroyed by
  `cleanup_bootstrap`.
- Helm-first delivery — no raw manifests, no `kubectl apply -f`.
- Chart-side Gate A (external L2) + Gate B (CNI viability)
  `helm.sh/hook: test` Pods fail the deploy on data-plane defects.
- Reusable-repo / private consumer-repo boundary — no site-specific
  inventories, secrets, or tfvars in this repo.

### Pinned stack

Kubernetes `v1.35.0` · k3s `v1.35.3+k3s1` · Cluster API `v1.12.5` ·
CAPN `v0.8.5` · LXD snap `6/stable` · Calico `v3.31.5` ·
MetalLB `v0.15.3` · Terraform `hashicorp/helm` `~> 3.1.1`. Full
version log in `plans/PLAN-stage1-common.md` `§8a`.

### Closed by design

Privileged LXC, multi-CNI runtime toggles, raw manifests, custom
APT repos on the host, host-firewall management, external etcd.

---

[Unreleased]: https://github.com/kogeler/k8s-lab/compare/v1.1...HEAD
[1.1]: https://github.com/kogeler/k8s-lab/compare/v1.0...v1.1
[1.0]: https://github.com/kogeler/k8s-lab/releases/tag/v1.0
