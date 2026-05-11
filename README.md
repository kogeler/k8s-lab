# k8s-lab

Reusable implementation code for a single-host Kubernetes laboratory built on
LXC/LXD system containers and driven by Cluster API provider for Incus/LXD
(CAPN). Target host and local dev VM are both Debian 13 Trixie.

This repo intentionally ships **only reusable building blocks**:

* Ansible roles (host bootstrap, LXD substrate, bootstrap management cluster,
  local harness, validation gates).
* Terraform module (Cluster API objects, machine templates, guest networking,
  cluster add-ons via Helm).
* Local wrapper Helm charts.
* Molecule + Vagrant + libvirt local test harness.
* `Makefile` and scripts for local end-to-end testing.

Concrete environment composition (inventories, secrets, environment-specific
tfvars, site-specific root modules, `make deploy TARGET=…`) **does not belong
here** — it lives in separate private consumer repos that import this code.

## Documentation

Start with [doc/README.md](doc/README.md) for the full user-facing
documentation.

Common entry points:

* [Overview](doc/01-overview.md) — core idea, goals, non-goals.
* [Architecture](doc/02-architecture.md) — bootstrap and pivot flow, dual-NIC
  model, layer ownership, and validation gates.
* [Quickstart local](doc/06-quickstart-local.md) — Vagrant + libvirt local
  end-to-end workflow.
* [Deployment guide](doc/07-deployment-guide.md) — real-host deployment through
  a private consumer repository.
* [Configuration reference](doc/08-configuration-reference.md) — project
  globals, role inputs, Terraform inputs and outputs, and chart values.

The translated plans live under [plans/](plans/). The root `PLAN-stage1-*.md`
files are kept as the original plan set.

## Layout

```
ansible/       # Reusable roles for host, LXD substrate, bootstrap, and pivot
charts/        # Local wrapper Helm charts
clusterctl/    # Reserved; runtime clusterctl.yaml is rendered by roles
doc/           # User-facing documentation
plans/         # English translated plan files
scripts/       # Local automation helpers
terraform/     # Reusable workload_cluster module
tests/         # Molecule scenarios + Vagrant harness + Terraform fixtures
LICENSE        # MIT License
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

Stage 1 is closed as v1.0. This repository ships reusable building blocks only;
real-environment composition lives in consumer repositories.

## License

k8s-lab is licensed under the [MIT License](LICENSE). The license applies to
this repository's code and documentation. Third-party tools, providers, charts,
collections, and container images keep their own licenses.
