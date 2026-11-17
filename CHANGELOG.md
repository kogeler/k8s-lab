# Changelog

All notable changes to `k8s-lab` are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each tagged release on GitHub is created **only after** the matching
section below is merged into `main`; the release body is a verbatim
copy of the section here (no rewriting, no expansion).

---

## [2.0.0] — 2026-11-16

Kubernetes clusters on one Debian or Ubuntu host, managed by
Cluster API, with unprivileged LXC system containers as nodes.

### Added

- **Roles**: `host`, `lxd`, `bootstrap`, `clusterctl`, `capn_identity` and
  `management_cluster`, in one house style, with every input declared in
  `meta/argument_specs.yml`. Every role decides from the live state whether it
  has work to do, so a playbook derived from the reference
  `tests/playbooks/management.yml` is safe to run any number of times on a
  live host.
- **Common variables** `k8s_lab_*` as a contract (`doc/variable-contract.md`),
  checked by `make check`.
- **The flow**: a transient k3s bootstrap cluster, the Cluster API providers
  and CAPN through `clusterctl` (init, upgrade, never downgrade), the CAPN
  identity (one-run rotation, a Secret per namespace), `mgmt-1` through Helm,
  the pivot, `mgmt-1` managing itself and its own releases, the bootstrap
  cluster removed; `handoff.json` for the Terraform roots.
- **Charts**: `capi-cluster-class` (one ClusterClass per cluster, templates
  named after a hash of their spec, the node bootstrap), `capi-workload-cluster`
  (the Cluster, the API publication through an LXD proxy device, the
  convergence check), `cni-calico` and `cni-calico-config` (Gate B), `metallb`
  and `metallb-config` (Gate A); strict value schemas.
- **Terraform**: modules `workload_cluster` and `workload_addons` (with
  `modules/access`), applied from two roots per workload cluster; plan-mode
  tests with mocked providers.
- **Network**: `eth0` internal and dual-stack with the only default route;
  `eth1` external IPv6, where replies to what arrives leave the way they came
  (connection marks in each node's own namespace); NodePorts on the external
  prefix only; no rule in the host's firewall.
- **Lifecycle**: `mgmt.kubeconfig` rebuilt on every run; control-plane
  certificates for 1095 days, rolled 60 days before they expire; the CAPN
  certificate for 1825 days; LXD's automatic refreshes held; 168-hour leases on
  the internal network.
- **Tests**: Molecule scenarios `substrate`, `bootstrap` and `e2e-local` on a
  Debian 13 VM (Vagrant + libvirt), `gha` in GitHub Actions only; `make check`
  (lint, the variable contract, the generated reference, Terraform tests,
  kubeconform, docs checks, `mkdocs build --strict`).
- **Docs**: architecture, local quickstart, deployment, runbooks drilled on
  the harness (each says what was not exercised), troubleshooting, decision
  records, development; role, Terraform,
  chart and version reference generated from the code; `ROADMAP.md`.
- **Versions**: Kubernetes v1.37.0, Cluster API v1.14.4, CAPN v0.9.1, Calico
  v3.33.1, MetalLB 0.16.2, k3s v1.37.2+k3s1, LXD `6/stable`; Python tools in
  `uv.lock`, Ansible collections in `ansible/requirements.lock.yml`, binaries
  in `.tool-versions`.

---

[2.0.0]: https://github.com/kogeler/k8s-lab/releases/tag/v2.0.0
