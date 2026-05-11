# 06 — Quickstart (local lab)

This chapter takes you from a fresh clone of the repository to a fully
working two-cluster Kubernetes lab on a single local Vagrant VM, without
touching any real hardware. It is the recommended first
hands-on after [`01-overview.md`](01-overview.md) and
[`02-architecture.md`](02-architecture.md) (plan `§9.1`, `§10.2`).

The local lab is the only end-to-end driver shipped in this repository;
real environments are operated through a private consumer repository
(see [`07-deployment-guide.md`](07-deployment-guide.md)). What you
build here uses the same code paths the consumer repo would call.

---

## What you'll have at the end

After a successful run, the local lab will look like this:

- **One local Vagrant VM** running on libvirt/KVM (`k8slab_host`),
  attached to a single libvirt network `k8slab-mgmt-nat`.
- **Inside the VM**, an LXD substrate hosting:
  - the transient bootstrap k3s LXC (`capi-bootstrap-0`) — destroyed
    again before the run finishes;
  - the **mgmt-1** self-hosted CAPI management cluster (1 CP + 2
    workers) running CAPI / CABPK / KCP / CAPN controllers as Pods;
  - the **`lab-default`** workload cluster (3 CP + 2 workers) managed
    by mgmt-1 via CAPN.
- **Calico CNI** on both clusters, with `natOutgoing` for IPv6
  pod-to-substrate traffic.
- **MetalLB** on both clusters, announcing IPv6 VIPs from
  `2001:db8:42:100::/64` on the in-VM `br-ext6` bridge (the local
  substitute for an upstream IPv6 segment — see plan `§9.2`).
- **All Gate A and Gate B helm tests passing** on both clusters,
  including an external curl from the VM to the workload's MetalLB
  VIP (plan `§6`, `§17`).
- A runner-side `.artifacts/mgmt.kubeconfig` pointing at the
  self-hosted mgmt-1 — usable directly with `kubectl`.

End-to-end runtime on a recent laptop with KVM acceleration:

- **First run** (cold image cache, fresh box, fresh apt + snap): **30–45 min**.
- **Subsequent run** with `make destroy-vm` in between: **~20 min**.
- **Repeat `test-local-e2e`** over an already-built VM: **~15–18 min**.

The dominant cost is image and binary downloads.

---

## Prerequisites

The full checklist lives in [`05-prerequisites.md`](05-prerequisites.md).
At a glance:

- **A Linux runner.** macOS is not tested by this harness.
- A Python virtualenv with **Ansible 2.16.x**, **Molecule**,
  `molecule-plugins[vagrant]`, **ansible-lint**, and **yamllint**
  active on `$PATH`. The Makefile does not own venv creation.
- **Vagrant + libvirt + KVM** with the runner user in the `libvirt`
  group and `/dev/kvm` accessible.
- **Terraform**, **helm**, **kubectl** on `$PATH`.
- ≈ **16 GB free RAM** (VM defaults to 12 GB) and ≈ **50 GB free disk**
  for the libvirt pool and in-VM LXD btrfs storage.

---

## 1. Clone and set up the runner

```bash
git clone <repo-url> k8s-lab
cd k8s-lab

python3 -m venv .venv
source .venv/bin/activate
pip install \
  'ansible-core==2.16.*' \
  molecule \
  'molecule-plugins[vagrant]' \
  ansible-lint \
  yamllint

# Project-local Ansible collections (gitignored under ansible/collections).
make deps
```

`make deps` runs `ansible-galaxy collection install --force -r
ansible/requirements.yml -p ansible/collections/`. The `--force` flag
is deliberate — without it `ansible-galaxy` skips collections already
present in the venv's site-packages, leaving holes in the
project-local tree.

Verify the runner is sane:

```bash
make lint
```

This runs `lint-yaml`, `lint-ansible`, `lint-terraform`, `lint-helm`
in sequence. A clean checkout passes all four. If `lint-ansible`
fails on a missing collection, re-run `make deps`.

---

## 2. Bring up the Vagrant VM and harness

```bash
make test-local-harness
```

This is two delegated steps under the hood:

1. **`make -C tests/vagrant/debian13 up`** — defines and starts the
   `k8slab-mgmt-nat` libvirt network from
   `tests/vagrant/debian13/libvirt-networks/mgmt-nat.xml`, then
   `vagrant up --provider=libvirt host`. The Vagrantfile boots
   `debian/trixie64` (configurable via `K8SLAB_BOX`), allocates 8
   vCPUs, 12 GB RAM, and a 40 GB qcow2 data disk pinned to
   `/dev/disk/by-id/virtio-k8slab-lxdpool` for the LXD btrfs pool.
2. **`make -C tests/molecule harness-smoke`** — runs `molecule
   --version` and lists the scenarios under `tests/molecule/` that
   are wired (have a `molecule.yml`). It does not run any scenario;
   it confirms that the Python side of the harness is ready.

A successful run leaves you with the `k8slab_host` libvirt domain
running and the network active. The runner reaches it through the
inventory script at `tests/vagrant/debian13/inventory.py`.

---

## 3. Run the full canonical flow

```bash
make test-local-e2e
```

This is the master target. It boots the VM if it is not already up,
then runs the `e2e-local` Molecule scenario through both `converge`
and `verify`. The scenario implements every step of the canonical
flow described in plan `§3.1` and chapter
[`02-architecture.md`](02-architecture.md) §3 — bootstrap, mgmt-1,
**pivot**, cleanup, workload — in a single playbook with no dispatch
branches. Pivot is mandatory and runs every time (plan `§3.3`).

What happens, phase by phase, with rough timings on a warm-cache run:

| Phase | What happens | Time |
|---|---|---|
| 0–4. Substrate + bootstrap k3s | Roles `base_system` → `binary_fetch` → `lxd_host` → `lxd_project` → `lxd_storage_pools` → `lxd_network_int_managed` → `lxd_profiles` → `lxd_bootstrap_instance` → `bootstrap_k3s` → `bootstrap_clusterctl` → `bootstrap_capn_secret` → `export_artifacts`. Ends with `.artifacts/mgmt.kubeconfig` pointing at bootstrap k3s and `clusterctl init` complete. | ~5–7 min |
| 5. mgmt-1 Cluster CR on bootstrap | `kubernetes.core.helm` installs `capi-cluster-class` + `capi-workload-cluster` (mgmt topology, 1 CP + 2 W) on bootstrap. CAPN provisions LXC nodes and a haproxy LB instance. | ~3–4 min |
| 5b. CNI Calico on mgmt-1 | `helm install cni-calico --wait` plus an explicit `k8s_info` poll on all Nodes Ready (Calico operator reconciles asynchronously, so `--wait` alone is not sufficient). | ~1–2 min |
| 5c. MetalLB on mgmt-1 | `helm install metallb` + `metallb-config`. | ~30 s |
| 5d. Gate A/B helm tests on mgmt-1 | `helm test` on `capi-workload-cluster` (cluster-ready), `cni-calico` (Gate B — CNI viability), `metallb-config` (Gate A — external L2). Failure here stops the run before pivot. | ~1 min |
| 6. Pivot | `pivot_clusterctl_move` — `clusterctl init` on mgmt-1, then `clusterctl move` from bootstrap → mgmt-1. CAPI CRs and the move-labelled CAPN identity Secret migrate. | ~2–3 min |
| 7. Re-emit `mgmt.kubeconfig` | A second `include_role: export_artifacts` with `run_meta_chain: false` overwrites `.artifacts/mgmt.kubeconfig` with mgmt-1 creds. | <10 s |
| 7b. `cleanup_bootstrap` | The `capi-bootstrap-0` LXC is destroyed. Helm releases that lived on bootstrap go away with it. | ~30 s |
| 8. Workload Cluster on mgmt-1 | Helm install of `capi-cluster-class` + `capi-workload-cluster` again, this time with workload-topology values (3 CP + 2 W, name `lab-default`). | ~3–5 min |
| 8b. CNI + MetalLB on workload | Calico install → poll Nodes Ready → MetalLB + MetalLB config. | ~2 min |
| 9. Verify (Gate A/B on workload) | `helm test` on the three workload charts plus an **external curl from the Vagrant VM via `ext6-ra-peer`** to the announced MetalLB IPv6 VIP. Workload Nodes Ready=True via the rewritten kubeconfig. CAPI snapshot of the self-hosted mgmt-1. | ~1 min |

The run is verbose: molecule streams every Ansible task, every helm
install, and every `helm test` PASS/FAIL line. If anything fails, the
output points directly at the role / helm release / helm test that
broke. See [`13-troubleshooting.md`](13-troubleshooting.md) for the
common ones.

---

## 4. Inspect the result

After `make test-local-e2e` returns successfully, the runner-side
`.artifacts/` directory holds the handoff bundle (plan `§11.1`):

```
.artifacts/
├── mgmt.kubeconfig            # admin kubeconfig for self-hosted mgmt-1
├── mgmt.auto.tfvars.json      # Phase 5 Terraform handoff
├── harness-vm-id              # local harness VM identity
└── clusters/
    └── lab-default.kubeconfig # workload kubeconfig (debug copy from verify.yml)
```

`mgmt.kubeconfig` is the same file used throughout the run: it pointed
at bootstrap k3s during Phase 4, was rewritten in place by the second
`export_artifacts` after pivot, and now holds mgmt-1 admin
credentials. Use it directly:

```bash
export KUBECONFIG=$PWD/.artifacts/mgmt.kubeconfig
kubectl get nodes -o wide
```

You should see three Ready nodes — `mgmt-1-CP-0`, `mgmt-1-W-0`,
`mgmt-1-W-1` — with both an IPv4 (capi-int subnet `10.77.0.0/24`) and
an external IPv6 in `2001:db8:42:100::/64`. The CAPI controllers run
on mgmt-1 itself (self-hosted):

```bash
kubectl get pods -n capi-system
kubectl get pods -n capn-system
kubectl get clusters -A
# the workload Cluster CR shows up under capi-clusters/lab-default
```

For the workload, verify already wrote a debug copy to
`.artifacts/clusters/lab-default.kubeconfig`. To regenerate it from
the Terraform fixture (after `make deploy-workload`, see §5):

```bash
make workload-kubeconfig
# wrote .artifacts/clusters/lab-default.kubeconfig
```

This reads `terraform output -raw kubeconfig` from the workload
fixture and writes it to `.artifacts/clusters/<cluster_name>.kubeconfig`
with mode 0600. Use it the same way:

```bash
kubectl --kubeconfig=.artifacts/clusters/lab-default.kubeconfig \
  get nodes -o wide
# 3 CP + 2 W, all Ready, dual-stack as on mgmt-1
```

To poke around inside the VM:

```bash
make -C tests/vagrant/debian13 ssh
# inside the guest:
sudo lxc list -f csv -c n,s --project capi-lab
# capi-bootstrap-0 is gone after cleanup_bootstrap; you should see
# mgmt-1-CP-0, mgmt-1-W-0..1, mgmt-1-LB-0,
# lab-default-CP-0..2, lab-default-W-0..1, lab-default-LB-0
```

The `tests/vagrant/debian13/Makefile` also exposes `status` (vagrant
status) and `inventory` (Ansible-compatible JSON) for diagnostics.

---

## 5. Deploy an additional workload (optional)

After `make test-local-e2e` the runner has everything it needs to
drive the Terraform workload-cluster route (plan `§3.2`, `§16.6`).
The e2e run has already installed `lab-default` through direct
`kubernetes.core.helm` tasks, so exercise the Terraform route by
removing that workload first:

```bash
make destroy-workload
make deploy-workload
```

This target asserts `.artifacts/mgmt.auto.tfvars.json` exists, then
`cd`s into `tests/fixtures/terraform/workload-clusters/lab-default/`
and runs `terraform init -upgrade` + `terraform apply -auto-approve
-var-file=<repo>/.artifacts/mgmt.auto.tfvars.json`. The `-var-file`
is needed because Terraform auto-loads `*.auto.tfvars.json` only from
cwd, not from the repo-level `.artifacts/`.

The fixture exists in this repo only as a wired test case for the
`workload_cluster` module. Defining additional, distinct workload
clusters is a **consumer-repo** activity (see
[`07-deployment-guide.md`](07-deployment-guide.md)).

Both routes install the same Helm releases against the same CAPN
substrate; only the orchestrator differs.

---

## 6. Tear down

The destroy / clean target graph is documented in plan `§19.2` and
implemented in the root `Makefile`. The naming convention is:

- **`destroy-*`** operates on running infrastructure (Terraform state,
  helm releases, the VM, libvirt domains). Each `destroy-*` cascades
  the matching `clean-*` targets so the operator never has to
  remember which files to wipe afterwards.
- **`clean-*`** is file-only and idempotent; safe to run with no
  infrastructure at all.
- **Compound targets** (`clean-local`, `reset-all`) chain
  destroy + clean for "start over" scenarios.

### Destroy the workload cluster

```bash
make destroy-workload
```

This branches automatically on what state actually exists:

1. **Terraform state present** (`tests/fixtures/terraform/workload-clusters/lab-default/terraform.tfstate`)
   plus `.artifacts/mgmt.auto.tfvars.json` → `terraform destroy
   -auto-approve -var-file=...`. This is the reverse of
   `make deploy-workload`.
2. **No TF state** but `.artifacts/mgmt.kubeconfig` + tfvars present
   → the workload was installed by the Molecule e2e-local converge
   (which uses `kubernetes.core.helm` directly, no Terraform). The
   target falls back to two `helm uninstall` calls on mgmt-1
   (`<name>` Cluster CR first → CAPI cascade-deletes Machines + LXC
   nodes → then `<name>-class` ClusterClass). Calico / MetalLB live
   *inside* the workload and disappear with it.
3. Neither → nothing to destroy; the target only runs the clean-up.

In all three branches the target then runs `clean-tfstate` and
`clean-workload-kubeconfig` so the next deploy starts fresh.

### Destroy the Vagrant VM

```bash
make destroy-vm
```

This delegates to `make -C tests/vagrant/debian13 destroy`:
`vagrant destroy -f` plus a belt-and-braces sweep of any libvirt
domains and volumes the Vagrantfile is known to allocate (so a
SIGKILLed `vagrant up` cannot leave orphans), plus removal of stale
`.vagrant/machines/*/libvirt/` directories whose UUID no longer maps
to a real domain. Libvirt **networks** are left in place; to wipe
them too use `make -C tests/vagrant/debian13 wipe`.

`destroy-vm` then cascades `clean-mgmt-bundle`,
`clean-workload-kubeconfig`, and `clean-tfstate`.

### Full local reset

```bash
make clean-local   # "start over fast": destroy-vm + clean-molecule.
                   # No terraform destroy — the VM is already gone, so
                   # clean-tfstate (file delete) is sufficient.

make reset-all     # "exercise the full destroy chain":
                   # destroy-workload (real terraform destroy) →
                   # destroy-vm → clean-molecule. Slower.
```

---

## 7. Re-running individual scenarios

`tests/molecule/Makefile` exposes pattern targets in the form
`<scenario>-<driver>-<action>`. To re-run a single role's full
Molecule cycle without touching the rest of the canonical flow:

```bash
make -C tests/molecule bootstrap-clusterctl-vagrant-test
```

Scenarios: `base-system`, `binary-fetch`, `lxd-host`, `lxd-project`,
`lxd-storage-pools`, `lxd-network-int-managed`, `lxd-profiles`,
`lxd-bootstrap-instance`, `bootstrap-k3s`, `bootstrap-clusterctl`,
`bootstrap-capn-secret`, `export-artifacts`, `cleanup-bootstrap`,
`e2e-local`. Each scenario name matches its role directory under
`ansible/roles/` (snake_case internally, kebab-case as a scenario).

Actions: `create`, `prepare`, `converge`, `idempotence`, `verify`,
`test`, `destroy`, `lint`. The `delegated` and `vagrant` driver
tokens are interchangeable.

For the full testing model see [`12-testing.md`](12-testing.md).

---

## Common first-run problems

A short list; the deeper catalogue is in
[`13-troubleshooting.md`](13-troubleshooting.md).

- **libvirt permissions.** `virsh net-define` "permission denied" or
  `vagrant up` complaining about `qemu:///system` means the runner
  user is not in the `libvirt` group or `/dev/kvm` is unreadable.
  Add the user to the group, log out and back in, verify with
  `virsh -c qemu:///system net-list`.
- **Vagrant box not found.** The Vagrantfile defaults to
  `debian/trixie64` (override with `K8SLAB_BOX=...`). If missing,
  run `vagrant box add debian/trixie64 --provider=libvirt`.
- **"Volume for domain is already created"** on `vagrant up` after a
  killed run. `make destroy-vm` handles this via the
  `virsh vol-delete` + stale-state-dir sweep in the Vagrant Makefile.
  If it persists, `make -C tests/vagrant/debian13 wipe`.
- **"btrfs pool device dirty"** on the in-VM LXD storage pool. The
  Molecule shared `prepare` step wipes a loopback device, so this is
  rare on a clean Vagrant VM. Recovery: `make destroy-vm && make
  test-local-harness`.
- **Out of memory mid-run.** Full canonical flow + image pulls +
  `helm test` workloads need ~10 GB resident inside the VM. 16 GB
  free host RAM is the floor.
- **`make lint` fails on a missing collection.** Re-run `make deps`.

For deeper failure modes (pivot getting stuck, helm tests failing,
CAPN unable to reach the LXD daemon, Calico not reconciling) see
[`13-troubleshooting.md`](13-troubleshooting.md). For day-2
operations see [`11-operations.md`](11-operations.md).
