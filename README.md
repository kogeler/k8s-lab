# k8s-lab

[![License: MIT](https://img.shields.io/github/license/kogeler/k8s-lab)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/kogeler/k8s-lab?display_name=tag&sort=semver)](https://github.com/kogeler/k8s-lab/releases)
[![Lint](https://github.com/kogeler/k8s-lab/actions/workflows/lint.yml/badge.svg)](https://github.com/kogeler/k8s-lab/actions/workflows/lint.yml)
[![E2E](https://github.com/kogeler/k8s-lab/actions/workflows/e2e.yml/badge.svg)](https://github.com/kogeler/k8s-lab/actions/workflows/e2e.yml)
[![Docs](https://img.shields.io/badge/docs-k8s--lab.romancello.net-2088FF)](https://k8s-lab.romancello.net/)

Building blocks for Kubernetes clusters on one Debian or Ubuntu host, managed
by Cluster API: the nodes are unprivileged LXC system containers (LXD), a
self-hosted management cluster creates and runs any number of workload
clusters. The repository ships Ansible roles, Helm charts and Terraform
modules, and a harness that runs the whole flow on a local VM; a deployment
keeps its inventory, variables and Terraform state in a repository of its own.

## How it works

```text
host (Debian/Ubuntu, LXD snap)
│  Ansible: tests/playbooks/management.yml → your playbook
├─ bootstrap instance: k3s ──clusterctl init──► creates mgmt-1 ──clusterctl move──► removed
├─ mgmt-1: Cluster API + CAPN, Calico, MetalLB          (manages itself after the pivot)
│    └─ Terraform, per workload cluster: <root>/cluster, then <root>/addons
└─ workload clusters: Calico, MetalLB; gates checked on every change

every node:  eth0 internal (dual-stack, default route, egress)
             eth1 external (IPv6 from the router: NodePorts, MetalLB VIPs)
```

## Quickstart

On a Linux machine with KVM, libvirt and Vagrant
([prerequisites](doc/quickstart-local.md#prerequisites)):

```bash
uv sync --locked --all-groups && source .venv/bin/activate
make deps
make test-e2e        # VM, host, LXD, mgmt-1, pivot, a workload cluster, checks: ~15 min
```

On a real host: [deploy](doc/deploy.md).

## Status

| | |
|---|---|
| Release | v2.0.0 ([changelog](CHANGELOG.md)) |
| Versions | Kubernetes, Cluster API, CAPN, LXD, Calico, MetalLB and every tool: [versions](doc/reference/versions.md) |
| Tested on every change | the whole flow, a second run that must change nothing, a scale and a destroy — on a Debian 13 VM and in CI (Ubuntu 26.04) |
| Tested by drill | upgrades, scaling, rotation, reboot, backup and recovery, teardown: each [runbook](doc/runbooks/README.md) says when and what was not exercised |

## Limitations

- One host is one failure domain.
- `mgmt-1` runs one control-plane machine by default; back it up.
- Kubernetes versions are those CAPN publishes a node image for.
- The roles write no host firewall rules; the host's firewall must let the
  lab's bridges forward ([architecture](doc/architecture.md#network)).

## Documentation

[Architecture](doc/architecture.md) ·
[Quickstart](doc/quickstart-local.md) ·
[Deploy](doc/deploy.md) ·
[Runbooks](doc/runbooks/README.md) ·
[Troubleshooting](doc/troubleshooting.md) ·
[Decisions](doc/decisions/README.md) ·
[Reference](doc/reference/roles.md) ·
[Development](doc/development.md) — also at <https://k8s-lab.romancello.net/>.

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Roadmap](ROADMAP.md) ·
[MIT license](LICENSE)
