# 01 — Overview

## What is k8s-lab

**k8s-lab** is a reusable code repository for building a Kubernetes
laboratory on a single bare-metal Debian or Ubuntu Linux host where the
Kubernetes nodes are **LXC/LXD system containers**, not virtual machines,
and the cluster lifecycle is managed end-to-end by the **Cluster API
provider for Incus/LXD (CAPN)**.

It ships:

- **14 Ansible roles** that bootstrap the host, the LXD substrate, and
  a transient management cluster;
- **1 Terraform module** (`workload_cluster`) that delivers a complete
  workload Kubernetes cluster — CAPI topology, CNI, MetalLB, and
  acceptance tests — in a single `terraform apply`;
- **5 Helm charts** (`charts/`) that own every Kubernetes object
  (CAPI ClusterClass, workload Cluster CR, Calico, MetalLB, MetalLB
  config + Gate A/B helm-test hooks);
- **A Molecule + Vagrant + libvirt test harness** that runs the same
  code path on a developer laptop as on production hardware;
- **A `Makefile`** that ties the local lifecycle together (`make
  test-local-e2e`, `make deploy-workload`, `make destroy-*`,
  `make clean-local`).

## What problem this solves

A bare-metal Kubernetes lab on a single host needs to balance three
goals that usually fight each other:

1. **Real Kubernetes**, not a single-binary toy: multiple CP nodes,
   multiple workers, a real CNI with NetworkPolicy, a real load
   balancer, and a real CAPI control plane.
2. **No VM tax**: VMs eat memory and disk on a single host. LXC/LXD
   system containers run a full systemd guest at a fraction of the
   cost.
3. **Reproducibility**: every cluster must be re-creatable from code.
   Manual `kubectl apply -f` or `helm install` from a runbook does not
   count.

k8s-lab settles this by:

- using **unprivileged LXC system containers** (not VMs, not
  privileged LXC) as Kubernetes nodes, with a CAPN-tested kubeadm
  profile;
- bootstrapping a **transient single-node k3s** inside a separate LXC
  instance, running `clusterctl init`, then **pivoting to a
  self-hosted CAPI management cluster** before any workload cluster
  is created;
- delivering every Kubernetes object via **Helm charts installed by
  Terraform** — no `kubectl apply -f`, no raw manifests.

## What this repository is

This repository is a set of **reusable building blocks**. It is
intentionally **not** a turnkey installer.

- The roles, modules, and charts are **environment-agnostic**: they
  carry no real IPs, FQDNs, secrets, or site-specific values.
- The local Vagrant + libvirt harness is **the only end-to-end driver
  shipped here**. It exists so the same code can be exercised on a
  laptop before being applied to a real host.
- Real environments are deployed by **separate, private "consumer"
  repositories** that import this code and supply the concrete values
  (inventories, host_vars, secrets, tfvars, root TF modules,
  `make deploy TARGET=...`).

The boundary between this repo and a consumer repo is a **deliberate
architectural rule**, not a missing feature. See
[`07-deployment-guide.md`](07-deployment-guide.md) for the consumer
repo skeleton you copy-paste.

## What this repository is *not*

| It is not | What you should use instead |
|-----------|-----------------------------|
| A managed Kubernetes service. | A cloud provider. |
| A multi-host CAPI deployment tool. | Cluster API on real cloud infrastructure (CAPA, CAPG, CAPV…). |
| A privileged-LXC kubernetes installer. | This is **closed by design** — see `§2.8` of the plan. Use VM-based nodes if you need privileged-equivalent capabilities. |
| A Docker / kind / minikube replacement. | If single-binary "just works" is enough, prefer those. |
| A turnkey installer with `make deploy`. | A private consumer repo that imports this code. |
| A production HA cluster on a single host. | Multi-host clusters do not fit the single-host model. |

## Goals (Stage 1, closed v1.0)

The Stage 1 acceptance criteria — all met as of the v1.0 closure of
the plan — are:

- Single bare-metal host runs an unprivileged LXC substrate and a
  CAPN-driven Kubernetes lab.
- Default workload cluster topology = **3 control-plane + 2 worker
  nodes**, dual-stack IPv4/IPv6.
- Default management cluster topology = **1 control-plane + 2 worker
  nodes** (worker count = 2 is a chart-required floor for Gate B; CP
  remains 1 because etcd quorum HA cannot be obtained from a single
  host).
- **Helm-first delivery** of all Kubernetes objects, applied through
  the Terraform `hashicorp/helm` provider.
- **Bootstrap-and-pivot** is mandatory and is exercised in every
  end-to-end test run.
- **Acceptance gates A (external L2) and B (CNI viability)** run as
  chart-side `helm.sh/hook: test` Pods that fail the deploy if the
  data plane is not viable.
- **Local Vagrant + libvirt harness** runs the entire canonical flow
  on a developer machine, including in-VM `radvd` to model an external
  IPv6 segment.
- **Reusable shared repo / private consumer repo** boundary is
  enforced; this repo carries no environment-specific data.

## Non-goals

These were considered and explicitly rejected:

- **Privileged LXC.** Substrate invariant — the only LXC mode supported
  is unprivileged. If a feature does not work in unprivileged LXC, the
  fix is to change CNI / narrow scope or to switch to VM-based nodes
  (out of scope of this repo). See plan `§2.8`.
- **Multi-CNI runtime toggle.** Calico is the shipped CNI; swapping to
  a different one is a deliberate design step (a new wrapper chart),
  not a runtime flag.
- **Raw manifests / `kubectl apply -f`.** Forbidden as a delivery path.
  Helm charts are the only carrier of CR content. See plan `§2.9`.
- **`kubectl` calls in roles.** Roles use `kubernetes.core.k8s_info`
  for reads. The only deliberate `kubernetes.core.k8s state=present`
  create-side exception is the CAPN identity Secret — see plan
  `§2.6.1`.
- **Custom APT repositories on the host.** Forbidden. All non-standard
  binaries are downloaded by Ansible roles into `/opt/capi-lab/bin`,
  with version pinning and checksum verification. See plan `§2.2`.
- **Host firewall management.** Out of scope. The host firewall is the
  operator's property; bootstrap API publication uses LXD `proxy`
  devices, which leave no host-firewall rules behind. See plan
  `§11.4`.
- **External etcd.** Stage 1 ships only stacked-etcd KubeadmControlPlane
  topology. CAPI invariants require odd CP replica counts (1, 3, 5).
- **Privileged bootstrap container.** The bootstrap k3s LXC is also
  unprivileged.

## Stage 2 — what may follow

The plan keeps a **Stage 2 backlog** of opt-in features that may be
implemented on top of the working substrate without regressing it:

- BGP-based Pod IPv6 routing (replacing Calico SNAT for IPv6);
- e2e-local HA pair assertions extension;
- additional add-ons, etc.

See [`plans/PLAN-stage2-common.md`](../plans/PLAN-stage2-common.md) for
the full list. Stage 2 items are **not** part of this v1.0 contract;
each requires its own design step, implementation, and lint/test
cycle, and must not regress Stage 1 invariants.

## High-level mental model

```
┌─────────────────────────────────────────────────────────────────────┐
│ Bare-metal host (Debian or Ubuntu Linux)                               │
│                                                                     │
│   ┌──────────────┐    LXD substrate (snap, project=capi-lab)       │
│   │ /opt/capi-lab│         │                                        │
│   │   /bin       │         │                                        │
│   │   kubectl    │         ▼                                        │
│   │   clusterctl │   ┌─────────────────────────────────────────┐   │
│   │   k3s        │   │ LXD project "capi-lab"                  │   │
│   └──────────────┘   │                                         │   │
│                      │   capi-bootstrap-0   (transient)        │   │
│                      │      └─ k3s server                      │   │
│                      │      └─ CAPI controllers (host-network) │   │
│                      │      └─ CAPN controller                 │   │
│                      │                                         │   │
│                      │   mgmt-1-CP   mgmt-1-W0  mgmt-1-W1     │   │
│                      │      │           │           │         │   │
│                      │      └─ CAPI/CAPN now self-hosted here │   │
│                      │                                         │   │
│                      │   lab-default-CP{0..2} lab-default-W{0,1}   │
│                      │      └─ workload CNI=Calico             │   │
│                      │      └─ MetalLB IPv6 VIPs               │   │
│                      └─────────────────────────────────────────┘   │
│                                                                     │
│   br-ext6 (Linux bridge)  ──── eth1 (uplink, IPv6 /64) ─── network │
│   capi-int (LXD bridge)   ──── eth0 (internal dual-stack)          │
└─────────────────────────────────────────────────────────────────────┘
```

The architecture chapter ([`02-architecture.md`](02-architecture.md))
expands this into the canonical bootstrap-and-pivot flow, the dual-NIC
node design, and the Ansible / Terraform / Helm ownership split.

## Where the source of truth lives

| Question | Source of truth |
|----------|-----------------|
| Why was X decided this way? | The relevant `§N` section in `plans/PLAN-stage1-*.md` (English) or `PLAN-stage1-*.md` (Russian original). |
| What does role X do? | The role's own `README.md` under `ansible/roles/<role>/`, plus [`09-roles-reference.md`](09-roles-reference.md). |
| What does the chart's value Y do? | The chart's `values.yaml` + `values.schema.json` under `charts/<chart>/`, plus [`10-modules-and-charts.md`](10-modules-and-charts.md). |
| What is the deployment workflow? | [`07-deployment-guide.md`](07-deployment-guide.md). |
| How do I configure variable Z? | [`08-configuration-reference.md`](08-configuration-reference.md). |
| Why is my deploy failing? | [`13-troubleshooting.md`](13-troubleshooting.md). |

The plans say *why*. The documentation says *how*. The code says
*what*.
