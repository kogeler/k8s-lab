# Security Policy

## Scope

`k8s-lab` is a **laboratory / homelab building-block project**. It is
not intended for production workloads, regulated data, or anything
sensitive. The default topology runs on a single bare-metal host and
makes no high-availability or hardening guarantees beyond what is
documented in [`doc/02-architecture.md`](doc/02-architecture.md).

## Reporting a vulnerability

If you believe you have found a security issue in the code shipped by
this repository — Ansible roles, Terraform module, Helm charts, or
test harness — please report it **privately** via GitHub Security
Advisories:

- <https://github.com/kogeler/k8s-lab/security/advisories/new>

Do not open a public issue for security-sensitive reports.

When reporting, please include:

- a short description of the issue,
- a minimal reproduction (Ansible task / chart values / terraform vars),
- the affected commit or release tag,
- impact assessment as you see it.

There is no SLA. This is a single-maintainer project; reports will be
triaged on a best-effort basis.

## Out of scope

The following are explicitly **not** considered vulnerabilities in this
repository:

- Issues in upstream components (Kubernetes, Cluster API, CAPN, LXD,
  Calico, MetalLB, Terraform providers, Helm, k3s, kubeadm). Please
  report those to the relevant upstream project.
- Issues that require an attacker who already has root on the host or
  cluster-admin in the management or workload cluster.
- Hardening recommendations that contradict the project's documented
  non-goals (e.g., "use privileged LXC", "add a host firewall role" —
  see plan `§2.8`, `§11.4`).
- Findings that depend on running this code on a multi-tenant host, or
  exposing the lab APIs to the public internet without the operator
  taking the documented isolation steps.
