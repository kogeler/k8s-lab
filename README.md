# k8s-lab

Reusable implementation code for a single-host Kubernetes laboratory built on
LXC/LXD system containers and driven by Cluster API provider for Incus/LXD
(CAPN). Target host and local dev VM are both Debian 13 Trixie.

This repo intentionally ships **only reusable building blocks**:

* Ansible roles (host bootstrap, LXD substrate, bootstrap management cluster,
  local harness, validation gates).
* Terraform modules (Cluster API objects, machine templates, guest networking,
  cluster add-ons via Helm).
* Shared manifests / wrapper Helm charts.
* Molecule + Vagrant + libvirt local test harness.
* `Makefile` and scripts for local end-to-end testing.

Concrete environment composition (inventories, secrets, environment-specific
tfvars, site-specific root modules, `make deploy TARGET=…`) **does not belong
here** — it lives in separate private consumer repos that import this code.

For the full contract see `PLAN-stage1.md`. Implementation progress is tracked
in `PLAN-stage1-progress.md`.

## Layout

```
ansible/       # Roles — host/bootstrap/harness only
clusterctl/    # Pinned clusterctl.yaml
charts/        # Local wrapper Helm charts (e.g. MetalLB config CRs)
terraform/     # Reusable modules — cluster objects / guest net / add-ons
manifests/     # Shared inputs consumed by Terraform modules
tests/         # Molecule scenarios + Vagrant harness + Terraform test fixtures
scripts/       # Local automation helpers
.artifacts/    # Runtime-only: kubeconfigs, tfvars handoff, ephemeral trust
```

## Local workflows

All entry points are local-only by design.

```bash
make lint                 # static checks across Ansible / Terraform / Helm
make test-local-harness   # bring up Vagrant VM, verify harness prerequisites
make test-local-e2e       # full local pipeline (see plan §13.2)
make clean-local          # tear down local harness state
```

## Conventions

* **Two-NIC node design**: `eth0` = internal dual-stack (default route,
  kubelet node IP, egress); `eth1` = external IPv6-only (ingress only,
  NodePort, MetalLB VIP).
* **Unprivileged LXC only** for Kubernetes nodes (plan §2.8).
* **Ansible owns host/bootstrap/harness**; **Terraform owns** Cluster API
  objects, guest networking, kube-proxy policy, cluster add-ons (plan §2.7).
* **Native-first** Ansible policy: shell/command/script only as a documented
  last-resort fallback (plan §2.6.1).
* **Binaries under `/opt/capi-lab`** — no custom apt repos (plan §2.2).

## Status

Implementation is staged — see `PLAN-stage1-progress.md` for what is done
and what is next.
