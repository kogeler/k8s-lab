# Agent guide

The short working context for coding agents: what the project is, the rules
that do not bend, and where each topic is documented. It routes; the linked
pages own the details.

## The project

`k8s-lab` ships building blocks for Kubernetes on one Debian or Ubuntu host:
six Ansible roles, six Helm charts, Terraform modules, reference playbooks and
a Molecule + Vagrant + libvirt harness. Nodes are unprivileged LXC system
containers (LXD); Cluster API with CAPN manages them. A transient k3s
bootstrap cluster creates `mgmt-1`, which takes over through a mandatory pivot
and then manages itself; workload clusters are created through two Terraform
roots each (the cluster, then its add-ons). Deployments — inventories,
secrets, variables, state backends — live in their own repositories.

## Where things are

| Topic | Page |
|---|---|
| Model, flow, ownership, network, checks, limitations | [doc/architecture.md](doc/architecture.md) |
| Why it is built this way | [doc/decisions/](doc/decisions/README.md) |
| Local harness, conventions, CI, definition of done | [doc/development.md](doc/development.md) |
| Real-host deployment | [doc/deploy.md](doc/deploy.md) |
| Common variables | [doc/variable-contract.md](doc/variable-contract.md) |
| Day-2 procedures | [doc/runbooks/](doc/runbooks/README.md) |
| Failure modes | [doc/troubleshooting.md](doc/troubleshooting.md) |
| Inputs, values, versions (generated) | [doc/reference/](doc/reference/roles.md) |
| Open work | [ROADMAP.md](ROADMAP.md) |

The code is the truth for what is implemented; the decision records for why.

## Rules that do not bend

- No real inventories, host variables, secrets, tfvars, production Terraform
  roots or deployment playbooks in this repository. The reference playbooks in
  `tests/playbooks/` are what deployments derive theirs from.
- Unprivileged containers only — for nodes and the bootstrap instance. No
  privileged option, fallback or toggle.
- One flow: host → LXD → bootstrap cluster → providers → `mgmt-1` → checks →
  pivot → bootstrap removed → workload clusters. The pivot is not optional.
- One owner per cluster: Ansible owns the host, LXD, the bootstrap cluster and
  `mgmt-1` for its whole life; Terraform owns workload clusters. No operation
  needs both tools.
- Every Kubernetes object the project creates is in a chart under `charts/`. No
  `kubectl apply -f`, no `kubernetes_manifest`, no `kubernetes.core.k8s` with
  `state: present` for project objects. Two exceptions: the Cluster API
  providers and cert-manager (installed and upgraded by `clusterctl`), and the
  CAPN identity Secrets and their namespaces (role `capn_identity`), whose key
  must not land in a Helm release record. Reads are fine.
- Templates of a ClusterClass are named after a hash of their spec; a change is
  a new template and a rollout, never an edit in place.
- Network: `eth0` internal, dual-stack, the only default route; `eth1` external
  IPv6; replies to what arrives on `eth1` leave through `eth1` by marks in each
  node's own namespace; NodePorts only on the external prefix. The roles never
  write the host's firewall.
- Every role guards itself: on a live, pivoted host it decides from the state
  whether it has work and never re-creates, restarts or re-addresses.
- Common variables (`k8s_lab_*`) are read only as role-input defaults; a change
  updates [the contract](doc/variable-contract.md) and
  `tests/playbooks/group_vars/all.yml` in the same change (`make check`).
- Latest stable versions, verified upstream when pinned; binaries the host
  downloads are checksum-pinned and live under `/opt/capi-lab/bin`.

## Working

- Conventions per area (roles, charts, Terraform): [development](doc/development.md#conventions).
- Drive the harness through `make` (`make help`): `make vm-up`, `make test-*`,
  `make deploy-workload`, `make destroy-workload`, `make vm-reboot`,
  `make vm-destroy`, `make clean`. `vm-destroy` and the `destroy-*` targets
  remove running infrastructure: only when the task needs it.
- Long runs go to a log you follow: `make test-e2e > .cache/e2e.log 2>&1 &`.
  Watch the clusters too (machines, controller logs), not only the output.
- **Never run the `gha` scenario outside GitHub Actions**: not `make test-gha`,
  not `make -C tests/molecule gha-<action>`. It changes the machine it runs on;
  use `make test-e2e`.
- A test passed only if it ran in this workspace; quote its recap.
- Done means the [definition of done](doc/development.md#done): `make check`, the
  affected scenario with idempotence, `make test-e2e` on a fresh VM for roles,
  playbooks, charts, modules or the harness, docs updated, generated pages
  regenerated, a `CHANGELOG.md` entry.
- Do not commit `.artifacts/`, `ansible/collections/`, `.vagrant/`, Molecule or
  Terraform state, or kubeconfigs.

## Commits and releases

Agents do not commit, push, tag or release unless the maintainer asks. A
release is tagged only after its `CHANGELOG.md` section is merged to `main`;
the GitHub release body is a verbatim copy of that section.
