# 04 — Repository structure

For developers about to edit code. Maps every shipped directory to
its purpose, names the runtime-only artefacts, and fixes the naming
and variable-prefix rules every new file must obey.

The architectural *why* lives in plan
[`§7`](../plans/PLAN-stage1-common.md) (Repository),
[`§2.5`](../plans/PLAN-stage1-common.md) (Repository boundary) and
[`§2.6`](../plans/PLAN-stage1-common.md) (Ansible role contract).

---

## Top-level tree

What is shipped in the repo (what you `git clone`):

```text
k8s-lab/
├── Makefile                     # the only entry point for local workflows (§7, §10)
├── README.md                    # repo-level pointer to doc/
├── ansible/                     # 14 roles + collection requirements + ansible.cfg
├── charts/                      # 5 Helm charts — every K8s object lives here
├── clusterctl/                  # reserved; runtime clusterctl.yaml is rendered by role templates
├── doc/                         # this documentation set
├── plans/                       # PLAN-stage1-*.md (English) — source of truth for "why"
├── PLAN-stage1-*.md             # Russian originals at repo root
├── scripts/                     # local-harness Python + shell helpers
├── terraform/                   # exactly ONE module: workload_cluster (§16.4)
├── tests/                       # Molecule + Vagrant + libvirt harness, fixtures
├── .ansible-lint                # role lint config
├── .yamllint                    # repo-wide YAML lint config
└── .gitignore
```

What appears only at runtime (gitignored, never committed):

```text
k8s-lab/
├── .artifacts/                  # mgmt.kubeconfig, mgmt.auto.tfvars.json, clusters/* (mode 0600)
├── ansible/collections/         # ansible-galaxy collection install -p
├── tests/vagrant/debian13/.vagrant/      # Vagrant state
├── tests/molecule/<scenario>/.molecule/  # Molecule scenario state
└── tests/fixtures/terraform/**/.terraform/ + tfstate*  # local TF state
```

The runtime split is deliberate: the repo carries no environment data,
no real kubeconfigs, no concrete tfvars. See plan
[`§2.5`](../plans/PLAN-stage1-common.md) for the boundary contract.

---

## ansible/

```text
ansible/
├── ansible.cfg          # roles_path, collections_path, ssh_args, pipelining
├── requirements.yml     # collection deps with lower-bound pins (§2.11)
├── collections/         # gitignored — populated by `make deps`
└── roles/               # 14 roles, snake_case directory names — see table below
```

The 14 roles in canonical-flow order (full details in
[`09-roles-reference.md`](09-roles-reference.md)):

| Role | One-line purpose |
|------|------------------|
| `base_system` | Host packages, kernel modules, sysctls, `/opt/capi-lab` root, btrfs mount contract. |
| `binary_fetch` | Download + checksum-verify pinned `kubectl`, `clusterctl`, and `k3s` into `/opt/capi-lab/bin`. |
| `lxd_host` | Install LXD via snap, pin channel, refresh policy, create the `br-ext6` host bridge. |
| `lxd_project` | Reconcile the `capi-lab` LXD project. |
| `lxd_storage_pools` | btrfs pool `capi-fast` on a dedicated block device. |
| `lxd_network_int_managed` | LXD-managed `capi-int` bridge (internal dual-stack plane). |
| `lxd_profiles` | CAPN unprivileged-kubeadm profiles `capi-controlplane` / `capi-worker`. |
| `lxd_bootstrap_instance` | Transient `capi-bootstrap-0` LXC + LXD `proxy` device for runner reach. |
| `bootstrap_k3s` | Single-node k3s server inside the bootstrap LXC. |
| `bootstrap_clusterctl` | `clusterctl init` on bootstrap k3s — CAPI/CABPK/KCP/CAPN. |
| `bootstrap_capn_secret` | CAPN identity Secret (`incus-identity`). |
| `export_artifacts` | Emit `.artifacts/mgmt.kubeconfig` + `mgmt.auto.tfvars.json`. |
| `pivot_clusterctl_move` | `clusterctl init` on mgmt-1 + `clusterctl move` from bootstrap. |
| `cleanup_bootstrap` | Destroy `capi-bootstrap-0`. |

Role contract (plan [`§2.6`](../plans/PLAN-stage1-common.md)):
`tasks/main.yml` is dispatcher-only (`include_tasks` per topic);
`defaults/main.yml` carries the role's public vars prefixed with the
snake_case directory name; `meta/main.yml` declares `dependencies:`
(no ordering via `prepare.yml` or `pre_tasks`); each role has its
own `README.md`. Test harness:
`tests/molecule/<role-in-kebab-case>/`.

---

## terraform/

```text
terraform/
└── modules/
    └── workload_cluster/        # the ONLY TF module shipped here (§16.4)
        ├── main.tf              # 5 helm_release blocks + null_resource helm-tests
        ├── locals.tf
        ├── variables.tf
        ├── outputs.tf
        ├── providers.tf         # hashicorp/helm + hashicorp/kubernetes (read-side)
        └── versions.tf
```

No environment-specific TF roots exist in this repo —
`terraform/environments/`, `terraform/live/`, `prod/`, `dev/` are
absent by design. The single module is consumed by:

1. `tests/fixtures/terraform/workload-clusters/lab-default/` (test
   consumer, the only TF root in this repo);
2. private consumer repos for real sites, which wire their own
   tfvars, backends, and credentials.

Boundary rule: plan [`§2.5`](../plans/PLAN-stage1-common.md). Module
inputs/outputs: [`10-modules-and-charts.md`](10-modules-and-charts.md).

---

## charts/

```text
charts/
├── capi-cluster-class/          # ClusterClass + Kubeadm*/LXC* templates (§16.2)
├── capi-workload-cluster/       # Cluster CR instance (§16.3)
├── cni-calico/                  # wrapper over projectcalico/tigera-operator + Gate B (§17.2)
├── metallb/                     # subchart wrapper over upstream metallb/metallb (§17.3)
└── metallb-config/              # IPAddressPool + L2Advertisement + Gate A (§17.3)
```

Per chart (schemas in [`10-modules-and-charts.md`](10-modules-and-charts.md)):

| Chart | One-line purpose |
|-------|------------------|
| `capi-cluster-class` | Topology template — `ClusterClass`, `KubeadmControlPlaneTemplate`, `KubeadmConfigTemplate`, `LXC*MachineTemplate`. Chart-version-as-CR-name pattern lives here. |
| `capi-workload-cluster` | The `Cluster` CR that references a ClusterClass — one release per workload. |
| `cni-calico` | Wraps `tigera-operator` as a subchart, sets `Installation` values, ships **Gate B** (CNI viability) helm-test Pod. |
| `metallb` | Thin wrapper over upstream `metallb/metallb` (CRDs + controller + speaker). |
| `metallb-config` | IPAddressPool + L2Advertisement bound to `eth1`, plus **Gate A** (external L2) helm-test Pod. |

Helm-first delivery is a closed contract — plan
[`§2.9`](../plans/PLAN-stage1-common.md). No raw YAML lives outside
`charts/`; Ansible never creates Kubernetes objects via
`kubernetes.core.k8s state=present`; Terraform never uses
`kubernetes_manifest`.

---

## tests/

```text
tests/
├── molecule/
│   ├── Makefile                     # scenario pattern rules (`<scenario>-delegated-*`)
│   ├── shared/
│   │   ├── converge.yml             # universal — reads MOLECULE_SCENARIO_NAME
│   │   ├── verify.yml
│   │   ├── inventory/group_vars/k8slab_host.yml   # the ONE substrate group_vars file (§9.5)
│   │   └── tasks/                   # prepare.yml, prepare-btrfs-pool.yml,
│   │                                # prepare-clean-disk.yml, ext6-ra-source.yml (in-VM radvd),
│   │                                # wait-services.yml
│   ├── base-system/                 # one scenario per role — kebab-case
│   ├── binary-fetch/  lxd-host/  lxd-project/  lxd-storage-pools/
│   ├── lxd-network-int-managed/  lxd-profiles/  lxd-bootstrap-instance/
│   ├── bootstrap-k3s/  bootstrap-clusterctl/  bootstrap-capn-secret/
│   ├── export-artifacts/  cleanup-bootstrap/
│   └── e2e-local/                   # full canonical flow (§3.1) in one scenario
│
├── vagrant/debian13/
│   ├── Vagrantfile                  # libvirt provider; the shared local VM
│   ├── inventory.py                 # ad-hoc inventory generator for the running VM
│   ├── Makefile                     # `up`, `destroy`, `ssh`
│   └── libvirt-networks/            # mgmt-nat.xml, probe-ext6.xml (latter dormant)
│
└── fixtures/terraform/workload-clusters/lab-default/   # the only TF root in this repo (§16.5)
    └── main.tf, variables.tf, providers.tf, outputs.tf
```

Three contracts make this layout work:

1. **Scenario name == role directory name (snake-to-kebab).**
   `tests/molecule/base-system/` targets `ansible/roles/base_system/`;
   `shared/converge.yml` reads `MOLECULE_SCENARIO_NAME` to pick the
   role. Plan [`§9.5`](../plans/PLAN-stage1-common.md).
2. **One substrate group_vars file.**
   `shared/inventory/group_vars/k8slab_host.yml` holds every
   prod-like substrate value — uplink, storage pool spec, wait
   budgets, the LXD `proxy` device. A scenario adds
   `<scenario>/host_vars/k8slab-host.yml` only for a true override.
   Plan [`§9.5.1`](../plans/PLAN-stage1-common.md).
3. **`tests/fixtures/` carries no implementation** — only invokes
   reusable roles/modules/charts with synthetic inputs. Plan
   [`§2.7`](../plans/PLAN-stage1-common.md).

Workflow: [`12-testing.md`](12-testing.md). Entry points: top-level
`Makefile`.

---

## scripts/

```text
scripts/
├── _harness.py                  # shared helpers: REPO_ROOT, vagrant ssh-config, run_make
├── molecule_run.py              # Molecule wrapper — brings up shared VM, exports K8SLAB_HOST_*
├── render_kubeconfig.py         # rewrite kubeconfig server URL into .artifacts/clusters/<name>.kubeconfig
├── export_bootstrap_facts.py    # emit .auto.tfvars.json from bootstrap cluster facts (§11.1)
└── wait_for_cluster.sh          # poll a kubeconfig until kube-apiserver returns Ready
```

- `_harness.py` — shared helpers (`REPO_ROOT`, `VAGRANT_DIR`,
  `PLATFORM_HOST_NAME = "k8slab-host"`, wrappers around
  `vagrant ssh-config` and `make`). Never invoked directly.
- `molecule_run.py` — invoked by `tests/molecule/Makefile` pattern
  rules; brings up the shared VM, exports `K8SLAB_HOST_*`, then
  `exec`s `molecule <action> -s <scenario>`.
- `render_kubeconfig.py` — rewrite kubeconfig server URL into
  `.artifacts/clusters/<cluster>.kubeconfig` (mode 0600).
- `export_bootstrap_facts.py` — emit `.auto.tfvars.json` from
  bootstrap facts. Plan [`§11.1`](../plans/PLAN-stage1-common.md).
- `wait_for_cluster.sh` — `kubectl get --raw=/readyz` poll with a
  deadline.

Local-harness only; consumer repos do not need these.

---

## clusterctl/

```text
clusterctl/              # currently empty / reserved
```

`bootstrap_clusterctl` renders the pinned runtime `clusterctl.yaml`
from `ansible/roles/bootstrap_clusterctl/templates/clusterctl.yaml.j2`
into `/opt/capi-lab/etc/bootstrap_clusterctl/clusterctl.yaml`.
Versions track the §8 / §8a verified-version log in the plan.

---

## .artifacts/

Runtime-only directory — gitignored except `.gitkeep`. Plan
[`§11.1`](../plans/PLAN-stage1-common.md).

```text
.artifacts/                      # mode 0700
├── .gitkeep                     # tracked
├── mgmt.kubeconfig              # mode 0600 — active management cluster kubeconfig
├── mgmt.auto.tfvars.json        # mode 0600 — handoff bundle for §16.5 TF fixture
├── harness-vm-id                # current Vagrant VM id (cascade-clean tracking)
└── clusters/<name>.kubeconfig   # mode 0600 — per-workload debug kubeconfigs
```

Contract:

- File mode `0600`, directory mode `0700`, owner = runner user.
- `mgmt.kubeconfig` is the **same file** through the whole canonical
  flow ([`§3.1`](../plans/PLAN-stage1-common.md)): first points at
  bootstrap k3s, then `export_artifacts` rewrites it in place after
  pivot to point at mgmt-1.
- `mgmt.auto.tfvars.json` is the JSON handoff from Ansible to
  Terraform (consumed via `-var-file=`).
- `clusters/<name>.kubeconfig` is produced by
  `make workload-kubeconfig` from the `kubeconfig` TF output.

Cleanup: `make clean-mgmt-bundle`, `make clean-workload-kubeconfig`,
`make clean-local`.

---

## What is NOT in this repo

Plan [`§2.5`](../plans/PLAN-stage1-common.md) is enforced by
*omission*. You will not find:

| Not here | Lives in |
|----------|----------|
| `inventories/prod/`, `inventories/local/` with real hosts | A private consumer repo. |
| `host_vars/<real-fqdn>.yml` with real IPs / ULA prefixes | A private consumer repo. |
| Plaintext or vault secrets, real LXD trust certificates | A private secrets store mounted into the consumer repo at runtime. |
| `terraform/environments/<site>/` root modules | A private consumer repo, importing `terraform/modules/workload_cluster/`. |
| `*.tfvars` / `*.tfvars.json` for real sites | A private consumer repo (gitignored here by design). |
| `make deploy TARGET=...`, `make destroy TARGET=...` | The consumer repo's own `Makefile`. |
| `*.deploy.yml` / `*.production.yml` playbooks | A private consumer repo. |

Consumer-repo pattern: [`07-deployment-guide.md`](07-deployment-guide.md).

---

## Naming conventions

Mixing them silently is forbidden — a target like
`base_system-delegated-test` (snake + kebab in one name) is rejected
at review.

### Ansible roles

- **Role directory** in `ansible/roles/` is **snake_case**:
  `base_system/`, `lxd_storage_pools/`, `bootstrap_clusterctl/`.
- **Role display-name** in task / handler names is **kebab-case**:
  `base-system`, `lxd-storage-pools`.
- **Task names** follow `<role> | <section> | <action>` with the
  role part in kebab-case:
  `base-system | preflight | assert opt root present`.
- **Handler names** follow `<role> | handlers | <action>`:
  `lxd-host | handlers | restart snap.lxd.daemon`.

The asymmetry is deliberate: Ansible variable names must match the
directory (snake_case-only); display names are kebab-case for parity
with Make targets and scenario directories. Plan
[`§2.6.3`](../plans/PLAN-stage1-common.md).

### Molecule scenarios + Make targets

- **Scenario directory** under `tests/molecule/<name>/` is
  **kebab-case**: `tests/molecule/base-system/`,
  `tests/molecule/lxd-storage-pools/`.
- **Scenario name** == **role directory name with `_` → `-`**.
  `base_system` (role) → `base-system` (scenario).
- **Make targets** are **kebab-case** end-to-end:
  `make -C tests/molecule base-system-delegated-test`,
  `make -C tests/molecule e2e-local-vagrant-converge`.

The reverse mapping (scenario → role) is read at runtime from
`MOLECULE_SCENARIO_NAME` by `tests/molecule/shared/converge.yml`.
Plan [`§2.6.3`](../plans/PLAN-stage1-common.md),
[`§9.5.2`](../plans/PLAN-stage1-common.md).

### Helm charts

- **Chart directory** in `charts/` is **kebab-case**:
  `charts/capi-cluster-class/`, `charts/cni-calico/`.
- **Chart name** in `Chart.yaml` matches the directory exactly.
- Chart-version-as-CR-name pattern (plan
  [`§2.9`](../plans/PLAN-stage1-common.md),
  [`§12.10`](../plans/PLAN-stage1-common.md)) appends `Chart.Version`
  with `.` → `-`: `capi-cluster-class-0-3-0`.

---

## Variable prefix rules

Ansible variable hygiene is a hard contract. **Three categories**;
every variable must fall into exactly one.

### Project globals: `k8s_lab_*`

Every project-wide variable carries the `k8s_lab_` prefix. These are
the stable inter-role interface — anything more than one role reads
is a global by definition.

Examples (full list in
[`08-configuration-reference.md`](08-configuration-reference.md);
schema in plan [`§8`](../plans/PLAN-stage1-common.md)):

```yaml
k8s_lab_opt_root: "/opt/capi-lab"
k8s_lab_project_name: "capi-lab"
k8s_lab_uplink_interface: "eth0"
k8s_lab_external_bridge_name: "br-ext6"
k8s_lab_internal_network_name: "capi-int"
k8s_lab_external_ipv6_prefix: "..."
k8s_lab_metallb_vip_range_v6: "..."
k8s_lab_lxd_host_address: "..."
```

The `_section_` fragment (`storage`, `internal`, `external`,
`images`) is part of the **flat** variable name, not a YAML
namespace: `k8s_lab_storage_pool_name` is one identifier, not
`k8s_lab.storage.pool_name`.

Naked globals like `opt_root`, `enabled`, `api_publish_port` are
**banned** — plan [`§2.6.5`](../plans/PLAN-stage1-common.md). They
collide silently with vars inherited from wider inventory, make
grep-by-name useless, and hide ownership.

### Role public vars: `<role_name>_*`

Every variable a role exposes in `defaults/main.yml` carries the
role's snake_case directory name as a prefix:

```yaml
# ansible/roles/base_system/defaults/main.yml
base_system_enabled: true
base_system_btrfs_pool_required: true
base_system_extra_kernel_modules: [wireguard]

# ansible/roles/lxd_host/defaults/main.yml
lxd_host_snap_channel: "6/stable"
lxd_host_snap_refresh_mode: "hold"
```

Only the role itself reads these. **A role MUST NOT read variables
with another role's `<other_role>_*` prefix** — that creates
coupling invisible to either role's contract. Cross-role
communication goes through `k8s_lab_*` globals or `set_fact` (next
section). Plan [`§2.6.2`](../plans/PLAN-stage1-common.md),
[`§2.6.5`](../plans/PLAN-stage1-common.md). Booleans are
**affirmatively** named: `<role>_enabled`, `<role>_flow_control_*`.
`do_*` / `with_*` / `run_*` are banned.

### Role private vars: `_<role_name>_*`

Internal facts, derived values, registers, and helper vars carry a
**leading underscore** plus the role prefix:

```yaml
# ansible/roles/lxd_storage_pools/tasks/pools.yml
- ansible.builtin.uri: ...
  register: _lxd_storage_pools_pools_query_register

- ansible.builtin.set_fact:
    _lxd_storage_pools_pools_existing: "{{ ... }}"
```

Patterns: facts `_<role>_<section>_<fact>`; registers
`_<role>_<section>_<purpose>_register`. The leading underscore says
"internal — do not depend on this from outside the role". Faceless
register names like `result`, `out`, `tmp` are forbidden. Plan
[`§2.6.2`](../plans/PLAN-stage1-common.md),
[`§2.6.3`](../plans/PLAN-stage1-common.md).

---

## Cross-role communication

A role needs a value computed by another. Exactly two supported
mechanisms (plan [`§2.6.5`](../plans/PLAN-stage1-common.md)):

1. **Project global with the `k8s_lab_` prefix.** For stable values
   in the substrate contract (paths, network names, addresses).
   Documented in plan [`§8`](../plans/PLAN-stage1-common.md) and
   [`08-configuration-reference.md`](08-configuration-reference.md);
   sourced from inventory `group_vars` (production) or from
   `tests/molecule/shared/inventory/group_vars/k8slab_host.yml` (test
   harness).
2. **Runtime fact via `set_fact`** named `_<role>_<section>_<fact>`,
   for values that only exist after a role has run. The producing
   role must be in the consumer's `meta/main.yml` `dependencies:`.

Anything else — naked globals, reading another role's
`<other_role>_*` defaults, arranging order via `pre_tasks` /
`import_role` to substitute meta-deps — is forbidden by plan
[`§2.6.5`](../plans/PLAN-stage1-common.md). Violations create hidden
dependencies that pass one Molecule scenario and break another.

---

The plan says *why*; this chapter says *how* it looks once you
follow it. Mirror the patterns above when adding new code, and grep
the existing layout for the closest analogue.
