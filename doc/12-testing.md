# 12 — Testing

Testing in k8s-lab is the operator's contract for "did my change keep
the canonical flow green?" There are three layers and they are run in
this order whenever a role, a chart, or a module is touched:

1. **`make lint`** — yamllint, ansible-lint, `terraform fmt -check`,
   `helm lint`. Cheap, deterministic, runs in seconds.
2. **Per-role Molecule scenarios** — one scenario per Ansible role
   under `tests/molecule/`, driven by Molecule's **delegated driver**
   on top of a single shared Vagrant + libvirt VM. Each scenario runs
   `prepare` → `converge` → `idempotence` → `verify` → `destroy`
   against the live VM.
3. **`make test-local-e2e`** — the `e2e-local` Molecule scenario,
   which executes the full canonical flow (substrate → bootstrap →
   pivot → cleanup → workload, plus Gates A/B at every cluster).

The harness is the **only** end-to-end driver shipped in the repo.
There is no CI; the "test before commit" rule (plan `§2.11a`,
user-memory `feedback_test_before_commit`) is enforced by running
this locally on the developer's machine.

The full specification lives in plan `§9` (local development and
testing) and `§9.5` (shared inventory architecture).

---

## 1. Lint

`make lint` is the entry point for static checks. It chains four
sub-targets in the order they typically catch the most bugs:

```bash
make lint
# == lint-yaml
# == lint-ansible
# == lint-terraform
# == lint-helm
```

| Sub-target | What it runs | Scope |
|---|---|---|
| `make lint-yaml` | `yamllint -c .yamllint .` | every `*.yml`/`*.yaml` in the repo against `.yamllint` |
| `make lint-ansible` | `ansible-lint roles/` from `ansible/` | every role under `ansible/roles/` |
| `make lint-terraform` | `terraform -chdir=<d> fmt -check -recursive` for every TF directory under `terraform/` and `tests/fixtures/terraform/` | formatting only — not `terraform validate` |
| `make lint-helm` | `helm lint <chart>` for every `charts/*/` with a `Chart.yaml` | the five wrapper charts (`capi-cluster-class`, `capi-workload-cluster`, `cni-calico`, `metallb`, `metallb-config`) |

When to run: **before every commit**, and again before opening any
PR. Lint failures are not optional and not gated on changed files —
the contract is "the entire repo is lint-clean at HEAD". The Python
side (yamllint, ansible-lint) requires the project venv to be
active; `terraform` and `helm` come from the system `PATH`.

---

## 2. Molecule scenarios

Every Ansible role under `ansible/roles/` has a matching scenario
directory under `tests/molecule/`. The naming contract (plan `§9.5.2`):

> The scenario directory name (kebab-case) equals the role directory
> name (snake_case → kebab-case). E.g. role `bootstrap_clusterctl`
> ⇄ scenario directory `bootstrap-clusterctl`. The scenario's
> `scenario.name` field in `molecule.yml` keeps the snake_case form
> so that `MOLECULE_SCENARIO_NAME` matches the role directory
> consumed by `shared/converge.yml` (see §3 below).

The currently wired scenarios, in canonical-flow order:

| # | Scenario directory | Role exercised | Phase |
|---|---|---|---|
| 1 | `base-system` | `base_system` | host substrate |
| 2 | `binary-fetch` | `binary_fetch` | host substrate |
| 3 | `lxd-host` | `lxd_host` | LXD substrate |
| 4 | `lxd-project` | `lxd_project` | LXD substrate |
| 5 | `lxd-storage-pools` | `lxd_storage_pools` | LXD substrate |
| 6 | `lxd-network-int-managed` | `lxd_network_int_managed` | LXD substrate |
| 7 | `lxd-profiles` | `lxd_profiles` | LXD substrate |
| 8 | `lxd-bootstrap-instance` | `lxd_bootstrap_instance` | bootstrap |
| 9 | `bootstrap-k3s` | `bootstrap_k3s` | bootstrap |
| 10 | `bootstrap-clusterctl` | `bootstrap_clusterctl` | bootstrap |
| 11 | `bootstrap-capn-secret` | `bootstrap_capn_secret` | bootstrap |
| 12 | `export-artifacts` | `export_artifacts` | bootstrap (handoff) |
| 13 | `cleanup-bootstrap` | `cleanup_bootstrap` | post-pivot |
| 14 | `e2e-local` | (composite — full canonical flow) | end-to-end |

The `tests/molecule/Makefile` curated `SCENARIOS` list is the source
of truth; `make -C tests/molecule harness-smoke` enumerates and
sanity-checks it.

The `pivot_clusterctl_move` role is exercised only inside the
`e2e-local` composite scenario; it has no standalone Molecule
scenario by design (pivot is an end-to-end behaviour, not a
substrate primitive).

---

## 3. Driver model — delegated

Molecule supports several drivers (Docker, Podman, EC2…); k8s-lab
uses the **delegated** driver, which is also the default since
Molecule 6.x. The contract is a clean split (plan `§9.1`):

- **The harness owns `create` / `destroy`.** We bring the Vagrant +
  libvirt VM up via `make -C tests/vagrant/debian13 up` and tear it
  down via `make -C tests/vagrant/debian13 destroy`. The
  `scripts/molecule_run.py` wrapper invokes those Make targets and
  exports `K8SLAB_HOST_{ADDR,USER,PORT,KEY}` from `vagrant
  ssh-config` before exec'ing `molecule`.
- **Molecule owns `prepare` / `converge` / `idempotence` / `verify`.**
  Each scenario plays its own `prepare.yml` + the shared
  `converge.yml` (or its own `converge.yml` for integration
  scenarios) + a `verify.yml`.

In `molecule.yml` the wiring is plain:

```yaml
driver:
  name: default
  options:
    managed: false       # we own create/destroy ourselves

platforms:
  - name: k8slab-host
    groups:
      - k8slab_host
```

`managed: false` is what tells Molecule "do not generate a
create/destroy playbook from a driver template — just use the
inventory the harness gives you".

### 3.1. Why delegated

The decisive reason is **VM economy**. A naive Molecule run with the
Vagrant driver builds and destroys a VM per scenario; a full
canonical-flow check (14 scenarios) would take hours of `vagrant
up`/`destroy` cycles on a laptop. The delegated split lets us share
**one** Vagrant VM across all scenarios, which keeps full-cycle
runs in **minutes rather than hours**.

The `scripts/molecule_run.py` wrapper additionally self-heals when
the live VM identity changes (a `vagrant destroy` or host reboot
between two `molecule` invocations): it compares
`tests/vagrant/debian13/.vagrant/machines/host/libvirt/id` against
`.artifacts/harness-vm-id` and wipes any stale
`~/.ansible/tmp/molecule.*` scenario state when the UUIDs differ.
This is what makes `make -C tests/molecule <scenario>-vagrant-test`
"just work" against a fresh VM with no manual reset step.

---

## 4. Shared inventory architecture (§9.5)

Production playbooks read **one** host_vars file per host. The
harness mirrors this: every Molecule scenario sees the same
substrate `host_vars` so a scenario can never silently diverge from
the others. The Step 8 incident (plan `§9.5`) — `export-artifacts`
forgot the `lxd_bootstrap_instance_devices` proxy spec, the role
reconciled it to `{}`, and runner-side `kubectl` then could not
reach bootstrap — was the trigger for this consolidation.

### 4.1. Layout

```
tests/molecule/
├── shared/
│   ├── inventory/group_vars/k8slab_host.yml   ← single substrate file
│   ├── tasks/                                  ← shared prepare snippets
│   ├── converge.yml                            ← role-shim for per-role scenarios
│   └── verify.yml                              ← shared verify helpers
├── <scenario>/
│   ├── molecule.yml                            ← inventory.links + scenario meta
│   ├── prepare.yml
│   ├── verify.yml
│   └── host_vars/k8slab-host.yml               ← optional, scenario-local override
└── Makefile
```

### 4.2. The single substrate file

`tests/molecule/shared/inventory/group_vars/k8slab_host.yml` carries:

- **Connection coordinates** via env-lookups —
  `ansible_host: "{{ lookup('env', 'K8SLAB_HOST_ADDR') }}"` and so
  on, populated by `scripts/molecule_run.py` from `vagrant
  ssh-config`.
- **`k8s_lab_*` globals** (plan `§8`) — version pins, network
  CIDRs, cluster identity, topology counts.
- **Substrate `host_vars` per role** — `lxd_host_*`,
  `lxd_storage_pools_pools`, `lxd_bootstrap_instance_devices`
  (the LXD proxy publishing bootstrap k3s on `:16443`),
  `bootstrap_k3s_wait_*`, `bootstrap_clusterctl_*`,
  `base_system_btrfs_pool_required: true` (prod-like default),
  `export_artifacts_root` and `_mgmt_api_server_url`.

### 4.3. Per-scenario `molecule.yml`

Each scenario file is small (~65 lines) and only carries the
links + scenario meta:

```yaml
provisioner:
  name: ansible
  inventory:
    links:
      group_vars: ../shared/inventory/group_vars
      host_vars:  host_vars            # only if scenario-local file exists
  playbooks:
    prepare:  prepare.yml
    converge: ${MOLECULE_PROJECT_DIRECTORY}/shared/converge.yml
    verify:   verify.yml

scenario:
  name: <role_name_in_snake_case>
```

The shared `converge.yml` reads `MOLECULE_SCENARIO_NAME` from the
environment (Molecule sets it for every play) and `include_role`s
the matching role under `ansible/roles/`. This is why the contract
"`scenario.name` == role directory name" is load-bearing — it is
what wires the converge step.

A subtlety from plan `§9.5.2`: `provisioner.inventory.host_vars`
inside `molecule.yml` is **silently dropped** when
`inventory.links` is non-empty (Molecule's
`provisioner/ansible.py:442` is all-or-nothing). That is why
scenario-local overrides MUST live in a real
`<scenario>/host_vars/k8slab-host.yml` file referenced through
`inventory.links.host_vars: host_vars`, not in `molecule.yml`.

### 4.4. Active scenario-local overrides

Per plan `§9.5.3`, the only override currently in use is
`base_system_btrfs_pool_required: false` on every scenario from
`binary-fetch` onwards (`binary-fetch`, `lxd-storage-pools`,
`lxd-network-int-managed`, `lxd-profiles`,
`lxd-bootstrap-instance`, `bootstrap-k3s`, `bootstrap-clusterctl`,
`bootstrap-capn-secret`, `export-artifacts`). The reason: those
roles either do not touch the btrfs pool contract, or LXD already
owns the disk from previous runs and the base_system btrfs check
is no longer applicable.

`base-system` is the only scenario that exercises
`base_system_btrfs_pool_required: true` end-to-end (it inherits
the shared default with no override).

---

## 5. Running individual scenarios

`tests/molecule/Makefile` exposes a pattern target:

```
<scenario>-<driver>-<action>
```

- **scenario** — kebab-case directory name from §2 above.
- **driver** — `delegated` (canonical) or `vagrant` (alias). Both
  resolve to the same recipe. The driver token stays in the target
  even when only one is wired, so the invocation scheme is stable
  across the repo (plan `§9.1`).
- **action** — one of `create`, `prepare`, `converge`,
  `idempotence`, `verify`, `test`, `destroy`, `lint`. `test`
  is the full sequence
  `dependency → create → prepare → converge → idempotence → verify → destroy`.

Examples:

```bash
make test-local-harness                                      # bring up VM
make -C tests/molecule bootstrap-clusterctl-vagrant-test     # full cycle
make -C tests/molecule lxd-host-delegated-converge           # converge only
make -C tests/molecule lxd-host-delegated-destroy            # state only
make -C tests/molecule destroy-all                           # all scenario state
```

The shared `converge.yml` honours the meta-dependency chain in each
role's own `meta/main.yml` (user-memory
`feedback_role_dependencies`). Running
`bootstrap-clusterctl-vagrant-test` therefore pulls in `base_system`
→ `binary_fetch` → all `lxd_*` substrate roles →
`lxd_bootstrap_instance` → `bootstrap_k3s` → `bootstrap_clusterctl`
in dependency order. The shared VM caches everything earlier in the
chain, so the second scenario you run is fast.

The `harness-smoke` target lists every wired scenario without
running any of them — useful when a scenario directory has been
moved or renamed and you want to know whether the Make pattern
still resolves it.

---

## 6. Running e2e-local

```bash
make test-local-e2e
```

This is the master target. It (1) brings up the Vagrant VM if not
already running (`make -C tests/vagrant/debian13 up`), (2) runs
`make -C tests/molecule e2e-local-vagrant-converge` — substrate →
mgmt-1 helm install → CNI → MetalLB → Gate A/B → pivot → re-emit
`mgmt.kubeconfig` → `cleanup_bootstrap` → workload helm install →
CNI → MetalLB, and (3) runs `make -C tests/molecule
e2e-local-vagrant-verify` — workload Gate A/B + external curl to
the MetalLB VIP via `ext6-ra-peer` + workload Nodes Ready=True via
the runner-side rewritten kubeconfig + a CAPI snapshot of the
self-hosted mgmt-1.

The full phase breakdown with timings is in
[`06-quickstart-local.md`](06-quickstart-local.md) §3. Rough
runtimes:

- **first run** (cold image cache): 30–45 min;
- **warm cache, fresh VM**: ~20 min;
- **warm cache, existing VM**: ~15–18 min.

Failure halts at the first red gate. If Gate A/B on mgmt-1 fails,
pivot is never attempted — the run aborts before touching mgmt-1's
state. If pivot itself fails, `cleanup_bootstrap` is never run, so
the bootstrap LXC stays around for inspection (plan `§3`).

---

## 7. What `verify.yml` asserts

Every scenario carries a `verify.yml`. The assertion shape varies
by phase:

- **Substrate roles** (`base-system` … `lxd-profiles`) — artefacts
  on disk (paths, modes, file content), systemd services
  enabled+active, LXD object state via `lxc list -f json` or
  `community.general.lxd_*` modules.
- **Bootstrap roles** — `bootstrap-k3s` checks the k3s API on
  bootstrap LXC `127.0.0.1:6443`; `bootstrap-clusterctl` asserts
  the four CAPI provider namespaces are populated and cert-manager
  + CAPN Deployments are Ready; `bootstrap-capn-secret` checks the
  move-labelled identity Secret exists in every
  `k8s_lab_capn_identity_namespaces` namespace; `export-artifacts`
  checks `.artifacts/mgmt.kubeconfig` (mode 0600) authenticates
  against the bootstrap API.
- **`e2e-local`** runs (in this order):
  1. `helm test capi-workload-cluster -n capi-clusters` against
     mgmt-1 — chart-side cluster-ready hook;
  2. `helm test cni-calico -n tigera-operator` on the workload —
     Gate B (CNI viability);
  3. `helm test metallb-config -n metallb-system` on the workload —
     Gate A in-cluster;
  4. **external HTTP GET** from the Vagrant VM to the MetalLB
     IPv6 VIP — Gate A out-of-cluster, exercising the data path
     `ext6-ra-peer` → veth → `br-ext6` → speaker leader's eth1 →
     kube-proxy → backend Pod;
  5. workload Nodes Ready=True via the rewritten
     `.artifacts/clusters/lab-default.kubeconfig`, count =
     `k8s_lab_workload_controlplane_count + k8s_lab_workload_worker_count`;
  6. CAPI snapshot — Cluster, KubeadmControlPlane, MachineDeployment,
     Machine, LXCCluster, LXCMachine in `capi-clusters` against
     the self-hosted `mgmt.kubeconfig`. Confirms pivot landed cleanly.

Every step is idempotent: chart-side `helm test` Pods carry
`hook-delete-policy: before-hook-creation,hook-succeeded`.

---

## 8. Per-role Molecule sequence on a clean VM

When a role changes, a single `<role>-vagrant-test` is **not**
sufficient. Per user-memory rule
`feedback_per_role_molecule_sequence`, the obligatory check is to
run scenarios in dependency order on a freshly destroyed VM, **without
destroying the VM between them**, all the way through to
`export_artifacts`. `export_artifacts` is the credential-producing
role that downstream Phases 5+ depend on; running up to it
validates the artefact contract (`mgmt.kubeconfig`,
`mgmt.auto.tfvars.json`) even when the changed role itself is
upstream of it.

Recommended sequence — start with `make destroy-vm`, then run each
of the following with `make -C tests/molecule <s>-vagrant-test` in
order, breaking on first failure:

```
base-system → binary-fetch → lxd-host → lxd-project →
lxd-storage-pools → lxd-network-int-managed → lxd-profiles →
lxd-bootstrap-instance → bootstrap-k3s → bootstrap-clusterctl →
bootstrap-capn-secret → export-artifacts
```

If a step fails, the VM is left in the failed state for inspection —
`make destroy-vm` is the explicit reset.

---

## 9. Long-running tests in the background

Per user-memory rule `feedback_background_tests_streaming`,
`test-local-e2e` (30+ min) and the per-role chain above are
**not** to be run in the foreground with a 15-minute timeout
hanging over you. Run them in the background and stream the log:

```bash
make test-local-e2e &> /tmp/k8s-lab-e2e.log &
tail -f /tmp/k8s-lab-e2e.log
```

For active provisioning (CAPN reconciling LXC machines, kubeadm
init on a new CP, …) rule `feedback_active_provisioning_monitor`
adds a second tail on the substrate side — open another terminal
and watch CAPN controller logs and CR status (e.g. `kubectl -n
capn-system logs -l app.kubernetes.io/name=capi-provider-incus -f`
pre-pivot; `kubectl -n capi-clusters get cluster,machine,lxcmachine
-w` post-pivot).

The point is to catch the actual error before the test pod hits
its own timeout — the test stdout often goes silent for minutes
while the substrate is the one failing.

---

## 10. Where the harness lives

| Concern | Path |
|---|---|
| Scenario directories | `tests/molecule/<scenario>/` |
| Shared substrate `host_vars` | `tests/molecule/shared/inventory/group_vars/k8slab_host.yml` |
| Shared converge shim + prepare snippets | `tests/molecule/shared/converge.yml`, `tests/molecule/shared/tasks/` |
| Per-role wrapper Makefile | `tests/molecule/Makefile` |
| Vagrant VM lifecycle + libvirt nets | `tests/vagrant/debian13/{Makefile,Vagrantfile,libvirt-networks/}` |
| Molecule wrapper + SSH helper | `scripts/molecule_run.py`, `scripts/_harness.py` |
| Top-level lint + e2e targets | repo-root `Makefile` |

Plan sources: `§9` (local development), `§9.4` (Make scheme),
`§9.5` (shared inventory), `§10.2` (`test-local-e2e`),
`§13.x` (per-role scenario specifics).

---

## 11. CI

There is no CI in this repository. Linters and Molecule are
intentionally local-only — the "test before commit" policy
(plan `§2.11a`, user-memory `feedback_test_before_commit`) puts
the responsibility on the developer running the harness on a real
VM before pushing. A consumer repository wrapping this code is
free to add CI on top of `make lint` + `make test-local-e2e` —
that is a consumer concern, not a Stage 1 contract.
