# k8s-lab — Documentation

This directory holds the user-facing documentation for **k8s-lab**, a
reusable building-block repository for a single-host Kubernetes
laboratory built on LXC/LXD system containers and the Cluster API
provider for Incus/LXD (CAPN).

If you have not seen the project yet, start with
[`01-overview.md`](01-overview.md).

If you want to spin up a local end-to-end lab on your laptop in ~30
minutes, jump to [`06-quickstart-local.md`](06-quickstart-local.md).

If you intend to deploy this on a real bare-metal host, the canonical
path is described in [`07-deployment-guide.md`](07-deployment-guide.md).

---

## Suggested reading order

The chapters are numbered so that reading them in order takes you from
"what is this project" to "I am operating it in production" without
backtracking. Each chapter is also self-contained — you can jump
directly to the one that answers your question.

| # | Chapter | When to read |
|---|---------|--------------|
| 01 | [Overview](01-overview.md) | First. Goals, scope, non-goals, what this repo *is* and *is not*. |
| 02 | [Architecture](02-architecture.md) | After overview. Dual-NIC node design, canonical bootstrap-and-pivot flow, layer ownership. |
| 03 | [Stack](03-stack.md) | When you need to know "what versions of what". |
| 04 | [Repository structure](04-repository-structure.md) | Before you edit code. Directory layout, naming rules, variable conventions. |
| 05 | [Prerequisites](05-prerequisites.md) | Before any deployment. Host requirements, runner setup, network plan. |
| 06 | [Quickstart (local)](06-quickstart-local.md) | First hands-on. Vagrant + libvirt VM, full E2E in one make target. |
| 07 | [Deployment guide](07-deployment-guide.md) | When you are ready to deploy on a real host. Consumer-repo pattern, step-by-step. |
| 08 | [Configuration reference](08-configuration-reference.md) | Look-up. Project globals, primary role inputs, Terraform inputs/outputs, and chart values. |
| 09 | [Roles reference](09-roles-reference.md) | Look-up. All 14 Ansible roles in one place. |
| 10 | [Modules and charts](10-modules-and-charts.md) | Look-up. The Terraform module and 5 Helm charts. |
| 11 | [Operations](11-operations.md) | Day-2. Adding workloads, kubeconfigs, destroy chain, upgrades. |
| 12 | [Testing](12-testing.md) | When you change a role / chart / module. Molecule + harness. |
| 13 | [Troubleshooting](13-troubleshooting.md) | When something is broken. Common failures and recipes. |
| 14 | [Glossary](14-glossary.md) | Anytime you hit an unfamiliar acronym. |

---

## Reading by role

If you have a specific job in mind, here are the minimum chapter sets:

- **"I want to evaluate whether to use this for my lab."**
  → 01 → 02 → 06.
- **"I have a target host and want to deploy."**
  → 01 → 02 → 03 → 05 → 06 (first do it locally) → 07.
- **"I need to operate the cluster I already deployed."**
  → 11 → 13. Look up specifics in 08, 09, 10 as needed.
- **"I want to extend a role / chart / module."**
  → 04 → 09/10 → 12.
- **"I am debugging a failure."**
  → 13. Then 09/10 for the role/chart involved.

---

## Source of architectural truth

Architectural decisions, contracts, deviations, and the full
implementation plan live in `PLAN-stage1-*.md` (Russian originals at the
repo root) and `plans/PLAN-stage1-*.md` (English translation). This
documentation summarises and operationalises those plans for end users
— it does **not** duplicate them. Where a decision needs deeper
context, this documentation links into the relevant `§N` plan section.

The plan numbering `§1..§22` is continuous across all `PLAN-*.md`
files; references of the form `§13.4` are valid without naming the
file. See [`plans/PLAN-stage1-common.md`](../plans/PLAN-stage1-common.md)
for the master file lineup.

---

## License

k8s-lab is licensed under the [MIT License](../LICENSE). The license applies to
the code and documentation in this repository. Third-party components referenced
or installed by the project, including Kubernetes, CAPI, CAPN, LXD, Terraform
providers, Ansible collections, Helm chart dependencies, and container images,
retain their own licenses.

---

## Conventions used in this documentation

- **Code blocks are copy-paste ready.** Where a placeholder needs
  substitution, it is wrapped in angle brackets (`<your-uplink-iface>`).
- **`$` prefix** indicates a runner-side shell command;
  **`#` prefix** (rare) indicates a host-side root shell.
- **Inline backticks** surround file paths, variable names, CLI flags,
  and CR/Kubernetes object kinds.
- **Cross-references to PLAN sections** look like `§13.4` and link
  into the English translation under `plans/`.
- **"Runner"** = the operator's local machine (where you run
  `ansible-playbook` / `terraform` / `helm`). **"Host"** = the bare
  metal target Debian 13 machine. **"Bootstrap"** = the temporary
  k3s LXC instance used during the initial Cluster API pivot.

---

## Feedback and changes

Documentation tracks the code. If you change a role's variable
contract, update [`08-configuration-reference.md`](08-configuration-reference.md)
and the role's entry in [`09-roles-reference.md`](09-roles-reference.md)
in the same change. If you change a Helm chart's values schema,
update [`10-modules-and-charts.md`](10-modules-and-charts.md). If you
add a new failure mode you debugged, drop a recipe into
[`13-troubleshooting.md`](13-troubleshooting.md).

The plan files (`PLAN-stage1-*.md`) remain the source of truth for
*why* something is the way it is. The documentation here is the source
of truth for *how to use* it.
