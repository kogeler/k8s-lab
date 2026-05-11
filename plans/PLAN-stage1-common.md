This file contains the common plan sections that apply to all stage-
specific documents. It covers the project-wide contract, architecture,
networking, gates, repo layout, typed variables, test harness, local
workflows, secrets policy and risk catalog.

The §1..§22 numbering is **continuous across all plan files** and is
split so that each file stays atomic in scope and so that cross-
references in the form `§<number>` are valid without naming the file:

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (workload_cluster TF module)
PLAN-stage1-4.md ................. §17      (Helm test contracts — Gate A + Gate B chart-side specs)
PLAN-stage1-5.md ................. §18      (pivot mgmt-1 → self-hosted)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 closure + self-review + recommendation)
```

Stage 1 v1.0 — closed.

## Table of contents

### PLAN-stage1-common.md — §1..§12 (project-wide contract)

- §1. Goal and scope of the plan
- §2. Fixed contract
  - §2.1. Platform
  - §2.2. Policy on packages and binaries
  - §2.3. Policy on isolation
  - §2.4. Policy on the bootstrap management cluster
  - §2.5. Policy on the repository boundary
  - §2.6. Policy on Ansible role development
    - §2.6.1. Native-first policy and idempotence of fallback steps
    - §2.6.2. Variables contract and layout
    - §2.6.3. Naming, tags, registers and flow control
    - §2.6.4. Handlers contract
    - §2.6.5. Role dependencies contract
    - §2.6.6. Comments, README and verifiability
  - §2.7. Ownership model between layers
  - §2.8. Policy on LXC node mode
  - §2.9. Policy on Terraform delivery for cluster add-ons
  - §2.10. Policy on node images
  - §2.11a. "Test before commit" policy
  - §2.11. Policy on dependency versions
  - §2.11b. "Plan is a live document; no separate progress file" policy
- §3. Architectural model — single canonical flow
  - §3.1. Sequence
  - §3.2. Driver
  - §3.3. Why pivot is mandatory
- §4. Final network architecture
- §5. Networking contract
- §6. Gate phases
- §7. Repository
- §8. Typed variables contract
  - §8a. Verified version log
- §9. Local development and testing
- §10. One-command local workflows
- §11. Secrets, artifacts and state
- §12. Risks and mitigation

### PLAN-stage1-1.md — §13..§14 (completed work)

- §13. Completed Ansible roles
  - §13.1. `base_system` (Step 1)
  - §13.2. `lxd_host` (Step 2)
  - §13.3. `lxd_project` (Step 3 + Step 4 substrate extension)
  - §13.4. `lxd_storage_pools` (Step 3)
  - §13.5. `lxd_network_int_managed` (Step 3)
  - §13.6. `lxd_profiles` (Step 3 lean baseline + Step 4 full CAPN baseline)
  - §13.7. `lxd_bootstrap_instance` (Step 3)
  - §13.8. `binary_fetch` (Step 4)
  - §13.9. `bootstrap_k3s` (Step 4)
  - §13.10. `bootstrap_clusterctl` (Step 6)
  - §13.11. `bootstrap_capn_secret` (Step 6)
  - §13.12. `export_artifacts` (Step 8)
  - §13.13. `pivot_clusterctl_move` (Step 18)
- §14. Completed phases
  - §14.1. Phase 0 — repo skeleton and local harness
  - §14.2. Phase 1 — host bootstrap
  - §14.3. Phase 2 — LXD substrate
  - §14.4. Phase 3 — bootstrap instance
  - §14.5. Phase 3.5 — `binary_fetch` (Step 4)
  - §14.6. Phase 4 — bootstrap management cluster (Steps 4 + 6 + 8)
  - §14.7. Workload cluster delivery via Terraform module (Step 16)
  - §14.8. Pivot mgmt-1 → self-hosted (Step 18)

### PLAN-stage1-2.md — §15 (Phases 3.5 + 4 bootstrap management cluster)

- §15. Phases 3.5 + 4 — Bootstrap management cluster
  - §15.1. Role: `binary_fetch`
  - §15.2. Role: `bootstrap_k3s`
  - §15.3. Role: `bootstrap_clusterctl`
  - §15.4. Role: `bootstrap_capn_secret`
  - §15.5. Bootstrap API publication (LXD proxy device, not a separate role)
  - §15.6. Role: `export_artifacts`
  - §15.7. Phase 3.5 execution
  - §15.8. Phase 4 execution

### PLAN-stage1-3.md — §16 (workload_cluster TF module: CAPI topology + add-ons + acceptance)

- §16. Workload cluster delivery via single Terraform module
  - §16.1. Ownership and delivery model (single module, helm test inside apply)
  - §16.2. Chart: `charts/capi-cluster-class/`
  - §16.3. Chart: `charts/capi-workload-cluster/`
  - §16.4. Module: `terraform/modules/workload_cluster/` (CAPI + add-ons + acceptance in one apply)
  - §16.5. Test fixture: `tests/fixtures/terraform/workload-clusters/lab-default/`
  - §16.6. Apply workload cluster (`make deploy-workload`)
  - §16.7. Workload kubeconfig export (internal step of the §16.4 module)

### PLAN-stage1-4.md — §17 (Helm test acceptance contracts — Gate A + Gate B chart-side specs)

- §17. Helm test acceptance contracts — Gate A + Gate B chart-side specs
  - §17.1. Helm test invocation contract (null_resource shape inside the §16.4 module)
  - §17.2. Gate B — CNI viability acceptance (chart-side spec + Step 13 status)
  - §17.3. Gate A — External L2 viability acceptance (chart-side spec + Step 14 status)

### PLAN-stage1-5.md — §18 (pivot mgmt-1 → self-hosted)

- §18. Pivot mgmt-1 → self-hosted (mandatory step in canonical flow)
  - §18.1. mgmt-1 helm install — on bootstrap
  - §18.2. Role: `pivot_clusterctl_move`
  - §18.3. Post-pivot workload creation

### PLAN-stage1-6.md — §19 (Phase 8 destroy)

- §19. Phase 8 — Destroy contract
  - §19.1. Role: `cleanup_bootstrap`
  - §19.2. Phase 8 execution

### PLAN-stage1-7.md — §20..§22 (Stage 1 closure)

- §20. Stage 1 — Closure
- §21. Stage 1 — Contract self-review
- §22. Stage 1 — Final recommendation for consumers

---

Below is the **full consolidated master plan v1.0** for coding agents. It already:

* includes the full original intent;
* accounts for the dual-NIC network architecture;
* incorporates all accepted review feedback;
* is organised in the **correct implementation sequence**;
* fixes a **single canonical flow** (substrate → mgmt-1 helm install → pivot → workload helm install — §3) without dispatch branches;
* adds **local development and testing via Molecule + Vagrant + Libvirt**, including an **in-VM RA source (radvd on the ext6-ra-peer veth) for the external IPv6 segment**;
* separates **mandatory gate checks** from the main implementation;
* fixes what exactly is done by **Ansible**, what exactly is done by **Terraform**, and what is considered **out of scope**.

---

# 1. Goal and scope of the plan

This is an implementation plan for a **Kubernetes laboratory infrastructure on a single bare metal host**, where:

* Kubernetes nodes are **LXC/LXD system containers**;
* node management is done via the **Cluster API provider Incus (CAPN)**, which **officially supports Incus, Canonical LXD and Canonical MicroCloud**; for our project the choice is fixed as **Canonical LXD via snap** with strict pinning of versions/images. ([capn.linuxcontainers.org][1])
* host: **Debian 13 Trixie**;
* local test VM: also **Debian 13 Trixie**;
* the host has **no Docker** and no permanent host-level Kubernetes;
* all non-standard binaries are downloaded by **Ansible roles** and placed under **`/opt/capi-lab`**;
* network design is **dual-NIC**:

  * `eth0` internal dual-stack = default route / node identity / regular egress;
  * `eth1` external IPv6-only = ingress-only / MetalLB / NodePort. ([Ubuntu Documentation][2])

This document describes the already **complete system**, but the main focus is the infrastructure bootstrap and networking for this scheme.

The boundary of the **current development repository** is fixed separately:

* this repo contains only **reusable implementation code**:

  * Ansible roles,
  * Terraform modules,
  * Helm charts (`charts/`, §2.9 + §16..§17) — the only carrier of
    Kubernetes CR content,
  * Molecule/Vagrant/libvirt test harness,
  * `Makefile` and scripts for full local testing;
* this repo **does not contain** direct configuration of real environments:

  * inventories,
  * host/group vars,
  * secrets,
  * environment-specific tfvars,
  * root modules for specific sites,
  * `make deploy TARGET=...`/`make destroy ...` for production-like environments;
* concrete environment composition must live in **separate private consumer repos** that import / consume the code from this repo.

---

# 2. Fixed contract

## 2.1. Platform

The following is fixed:

* target host: **Debian 13 Trixie**;
* local dev/test VM: **Debian 13 Trixie**;
* LXD is installed **via snap**, because this is the official recommended way to install LXD on Linux, including Debian; snap tracks/channels must be pinned. ([Ubuntu Documentation][3])

## 2.2. Policy on packages and binaries

On the Debian host:

* only **system APT packages** are allowed;
* custom APT repositories are **forbidden**;
* installation of non-standard tools via APT is **forbidden**;
* all non-standard tools must:

  * be downloaded by Ansible roles,
  * be version-pinned,
  * be checksum-verified,
  * be placed under `/opt/capi-lab/bin`.
    The LXD snap already pulls its own dependencies, and snap updates must be controlled separately via `snap refresh --hold` or `refresh.timer`. ([Ubuntu Documentation][3])

## 2.3. Policy on isolation

The whole lab lives in a separate **LXD project** — for example, `capi-lab`, so as not to disturb already manually created LXC/LXD containers and their networks. LXD projects isolate instances, and with feature flags enabled — also profiles, images and other entities. With `restricted=true` you can selectively allow needed sensitive features such as nesting. ([Ubuntu Documentation][4])

CAPN's access to the LXD API must go through a **restricted TLS certificate**, scoped only to the project `capi-lab`. The LXD documentation directly supports restricted TLS certificates with project confinement. ([Ubuntu Documentation][5])

## 2.4. Policy on the bootstrap management cluster

The bootstrap management cluster:

* must live **in a separate LXC system container**;
* must not live in the host namespace;
* must not use Docker/kind;
* must follow the same isolation policy: by default the bootstrap container is also considered an **unprivileged LXC**, and a privileged bootstrap container is not an acceptable shortcut;
* for our scheme is brought up as a **single-node k3s** inside the bootstrap container.
  K3s is a fully compliant lightweight Kubernetes distribution shipped as a single binary; `k3s server` supports `--tls-san`, `--disable=servicelb`, `--disable=traefik` and a config file. ([K3s][6])

## 2.5. Policy on the repository boundary

In this repo:

* only reusable roles/modules and the local test harness are allowed;
* test fixtures are allowed where needed for Molecule/Vagrant/libvirt e2e;
* any environment-specific data of real sites is forbidden:

  * real IPs/FQDNs,
  * inventories and host targeting,
  * plaintext secrets,
  * real LXD trust materials,
  * root orchestration for deploy/destroy in concrete environments.

Consequence: the orchestration layer for real environments is considered an **external consumer layer** and is not designed as part of this repo.

## 2.6. Policy on Ansible role development

The style contract for the roles in this repo deliberately follows the patterns of `mini-pig-ansible-collection/roles/init` and `mini-pig-ansible-collection/roles/naive_proxy`, but without blindly copying their domain logic. From these roles we take exactly the engineering style: defaults structure, naming for variables/tasks/handlers/tags, dispatcher-only `tasks/main.yml`, mandatory `preflight`, practical comments, short handlers, a strong `README.md` and realistic verification. ([30], [31], [32], [33])

Reference links the agent is allowed and encouraged to consult directly:

* `init` role: [30]
* `naive_proxy` role: [31]
* `naive_proxy` Molecule harness: [32]
* `naive_proxy` README: [33]

### 2.6.1. Native-first policy and idempotence of fallback steps

For Ansible role development we follow Ansible best practices. For any task we look first for a native module; imperative calls (shell and HTTP-mutation via `uri`) are allowed only as a last resort and must have a dedicated idempotence wrapper.

**Implementation path selection order (strict):**

1. first a native module from `ansible.builtin.*`;
2. then an appropriate module from an external Ansible collection (`community.general`, `ansible.posix`, `kubernetes.core`, `community.crypto`, etc.);
3. only if no suitable module exists or it objectively does not cover the required behaviour — fallback to `shell` / `command` / `script` / `raw`, or to `ansible.builtin.uri` with a mutating method (`POST` / `PUT` / `PATCH` / `DELETE`) is allowed.

**It is forbidden** to use shell scripts, `shell`, `command`, `script` or `raw` where the task can be solved by an existing native or collection module. `ansible.builtin.uri` for HTTP APIs is formally a native module (see §13.4/§13.5 — LXD REST via unix_socket), but with a mutating method it has the same imperative semantics as a shell fallback and is subject to the same idempotence requirements.

**Any fallback step must:**

* be explicitly justified by a short comment in the role code (why a native module does not fit);
* be truly idempotent: a second consecutive run is a no-op;
* honestly report `changed` — `true` ⇔ state was mutated, `false` ⇔ nothing was done;
* achieve idempotence and honest `changed` through an **additional wrapper in the task itself** — using one of these mechanisms:
  * pre-check (GET / `stat` / `getent` / API query) → `set_fact` with diff → `when:` guard on the mutating step, so that in steady state it simply does not run;
  * `creates:` / `removes:` for `shell`/`command` (Ansible itself skips the step and works correctly with `--check`);
  * stdout/rc parsing via `failed_when:` and `changed_when:` based on output content, not on a constant;
  * PUT with the full desired body instead of POST, if the API supports idempotent upsert;
  * register before/after and `changed_when:` based on the real diff;
* not replace already-existing declarative modules.

**Forbidden pattern:** masking an always-changed mutating step with `changed_when: false` to make the Molecule idempotence gate green. This is not idempotence, it is its simulation: it simultaneously breaks the Molecule idempotence gate, `ansible-playbook --check` (false-negative no-op for a real mutation) and drift detection in a steady-state cluster. `changed_when: false` is legitimate **only** on read-only steps (`GET` / `show` / `list` / `stat` / assertion).

Canonical fallback pattern via `uri`: `ansible/roles/lxd_storage_pools/tasks/pools.yml` — GET → derive existing → POST with `when: item.name not in existing` and `changed_when: true`; PATCH only on detected diff. Canonical shell fallback: `ansible/roles/lxd_host/tasks/refresh.yml` — pre-read of the current value via read-only `snap get`, then `set` only on diff with honest `changed_when`.

### 2.6.2. Variables contract and layout

Each role in this repo must observe the following contract:

* public variables live in `defaults/main.yml` and have a strict role prefix of the form `<role_name>_*`;
* internal/private variables, derived facts, helper paths, unit names and `register` values must have a leading underscore prefix of the form `_<role_name>_*`;
* faceless names like `enabled`, `config`, `result`, `packages`, `service_name` without a role prefix are forbidden;
* boolean variables and feature toggles must be named affirmatively and meaningfully: `<role_name>_enabled`, `<role_name>_flow_control_*`, `<role_name>_update_*`, not `do_*`, `with_*`, `run_*`;
* `defaults/main.yml` is grouped by meaningful sections and contains only practical comments about behaviour, trade-offs and caveats;
* sections in `defaults/main.yml` are formatted in a readable style like `# -- General --`, `# -- Network --`, `# -- Paths --`, if it helps to read the role contract quickly;
* if a role has a public contract, it must have its own `README.md` with purpose, requirements, variables, tags, examples, testing notes and known caveats;
* `tasks/main.yml` must be a dispatcher-only file that orchestrates short topical `include_tasks`, not a long "YAML script";
* task files must be named by domain (`preflight.yml`, `install.yml`, `config.yml`, `services.yml`, `healthchecks.yml`), not by random internal steps;
* input invariants and required parameters are checked in a separate `preflight.yml` via `ansible.builtin.assert` before any mutating task starts;
* `handlers/main.yml` is allowed only for genuinely reactive behaviour and must remain short and predictable;
* `templates/`, `files/`, `vars/`, `meta/` are added only by real necessity, not "just in case" boilerplate.

### 2.6.3. Naming, tags, registers and flow control

For uniformity the repo fixes these rules:

* the canonical display-name of a role in task/handler names must be in kebab-case, even if the directory name of the role in the repo stays snake_case;
* for variables, facts and register names use the snake_case role prefix from the role directory name, e.g. `base_system_*` and `_base_system_*`, not the kebab-case display name;
* task names follow the scheme `<role> | <section> | <action>`;
* handler names follow the scheme `<role> | handlers | <action>`;
* `tasks/main.yml` uses `include_tasks` with `apply.tags`, and the calling task repeats the same set of `tags`;
* `preflight` must be the first include in `tasks/main.yml`, if the role changes anything on the target host at all;
* coarse-grained flow control is allowed only at the level of the role or a major subfeature, e.g. `<role>_enabled` and `<role>_flow_control_*`;
* per-task micro-switches are forbidden — they blur the role contract and complicate testing;
* public tags must include at least a role-level tag and a section-level tag; if both underscore and hyphen spelling exist for a role, both aliases may be supported;
* `register` names and `set_fact` names must remain scoped and readable: `_<role_name>_<section>_<purpose>_register` or `_<role_name>_<section>_<fact>`;
* temporary loop vars, helper vars and computed vars must not leak into globally shared names.
* **Non-Ansible naming** (Make targets, Molecule scenario directories under
  `tests/molecule/`, shell helpers, scripts) uses **kebab-case**.
  Mixing `_` and `-` in Make target names (e.g. `base_system-delegated-test`)
  is forbidden as an unnecessary source of pain on the command line. The scenario
  directory `tests/molecule/<name>/` is not a role directory and is not
  subject to the snake_case role contract — its name is always kebab-case, and
  the reference to the applied role goes through the `_shared_target_role` field in
  the scenario's `molecule.yml`.

### 2.6.4. Handlers contract

The handler approach in this repo is also fixed explicitly:

* handlers exist only for reactive actions after changes: `restart`, `reload`, `daemon-reload`, `recreate`, `reissue`, not for the role's main business logic;
* a handler must not do input validation, discovery, variable computation, template rendering or side orchestration that should be a regular task;
* if cascading behaviour is needed, a bounded `notify` chain inside the role is allowed, as in `naive_proxy`, but the dependency must be readable and finite;
* in handlers, prefer module-based actions like `ansible.builtin.systemd`/`service`; a shell fallback is allowed only as a documented exception;
* if a handler is forced to use shell/command for a tool gap, it must keep predictable `changed` semantics and not create a false "permanent changed" state for the role;
* handler names must be specific enough to be invoked via `notify` without collisions between roles.

### 2.6.5. Role dependencies contract

Any dependency between roles in this repo must be declared **in
the dependent role's `meta/main.yml`**, not emulated externally:

* if role `B` will not work correctly without what role `A` installs
  (packages, kernel knobs, on-disk artefacts, daemons), `A` must
  be in the `dependencies:` of role `B`;
* consumers (playbook `roles:`, another role's meta, Molecule converge
  via `include_role`) are NOT allowed to manually "arrange the order" —
  meta-deps must do this automatically;
* `prepare.yml` in a Molecule scenario is responsible only for **test-harness
  bootstrap** (apt cache, test deps, mock assets), but **not** for running
  other roles "because we know they are needed": this masks a missing dependency
  in the role itself;
* a dependency implemented only in the prepare step is considered a bug
  in the role's contract and must be migrated to `meta/main.yml`;
* meta-deps are the only supported way of automatic
  ordering — using `pre_tasks` / `ansible.builtin.import_role`
  from a playbook to substitute this semantic is forbidden.

Additional discipline for meta-dep formatting (mandatory starting from
Phase 2):

* **Each meta dep MUST carry a one-line `# why` comment** in
  `meta/main.yml`. Without a why-comment, a future reviewer will not be able to
  distinguish a required dependency from one that was left in by accident, and
  on a cleanup refactor the dep will be silently removed and a regression
  will appear later, untraceable to a commit.
* **Do not declare transitive meta deps.** If `lxd_profiles` requires
  `lxd_host`, and `lxd_host` is already declared as a dep of
  `lxd_project`, write only `lxd_project` in `lxd_profiles/meta/main.yml`.
  Listing the whole chain manually is forbidden — it inflates the
  graph and turns any future reordering into a merge conflict.
* **A role MUST NOT read or condition on variables using another
  role's `<other_role>_*` prefix.** Cross-role communication goes
  only through:
  1. global contract variables with the project prefix `k8s_lab_*`
     (§8, e.g. `k8s_lab_opt_root`, `k8s_lab_uplink_interface`),
     which are the stable inter-role interface. Naked globals without
     the `k8s_lab_` prefix are forbidden (memory
     `feedback_global_var_prefix.md`, 2026-04-23) — see also §2.6.2;

  2. facts published via `set_fact` + correct naming
     `_<role>_<section>_<fact>`, if a runtime value needs to be passed;
  reading another role's `<role>_*` in your own defaults/conditions creates
  implicit coupling invisible to the contract of either role.

Violating these rules creates "hidden" dependencies that
silently work in one Molecule scenario and break in another.

### 2.6.6. Comments, README and verifiability

The roles in this repo must not be "self-documenting" only in the author's opinion:

* non-trivial defaults, conditionals and operational caveats must have a short, substantive comment;
* the role's `README.md` must explain not only "what is installed" but also runtime model, managed artifacts, service units/timers, security/runtime notes and real usage examples;
* the verify path must check not only syntax and idempotence, but real role behaviour;
* using `command`/`shell` in verify is allowed only when no module equivalent exists or it cannot check the required runtime path; such an exception must be explicitly marked and must not introduce changes to the system.

## 2.7. Ownership model between layers

In this plan the source of truth is divided strictly and without overlap:

* **Ansible roles** own only:

  * host bootstrap,
  * LXD substrate,
  * bootstrap management cluster,
  * local harness and validation orchestration;
* **Terraform modules** own everything that becomes:

  * Cluster API objects,
  * Kubernetes objects inside management/workload clusters,
  * machine templates,
  * guest networking configuration of CAPN-managed nodes,
  * kube-proxy configuration,
  * cluster add-ons such as `Calico` and `MetalLB`;
* **test fixtures** do not implement separate logic and do not become another ownership layer:

  * they only wire reusable roles/modules together,
  * supply synthetic values,
  * run local contract checks.

Consequence:

* Ansible **does not** own guest networking inside CAPN-managed nodes;
* Ansible **does not** install `Calico`, `MetalLB` and cluster-scoped manifests in workload/target management clusters;
* `tests/fixtures/*` must not contain ad hoc manifests or one-off implementations missing from `ansible/roles`, `terraform/modules` or `charts/`.

## 2.8. Policy on LXC node mode

The project is **unprivileged-only** — this is a substrate invariant,
not a v1.0-specific decision and not a switchable option:

* control-plane and worker nodes (and the bootstrap k3s LXC) are launched
  as **unprivileged LXC containers**;
* the privileged path **is not and will not become** part of the supported
  implementation scope: not as a fallback, not as an opt-in toggle, not as a
  consumer override. Any PR / proposal raising privileged
  containers as an option is rejected at review without discussion.

This is a closed architectural item. If a consumer needs
privileged-equivalent capabilities, the path is **VM-based nodes** (out of
scope for this repo), not privileged LXC.

Reasons:

* The LXD documentation recommends using unprivileged containers by default and warns separately that privileged containers are not root-safe; for stronger isolation LXD also recommends `security.idmap.isolated=true` where containers do not need a shared UID/GID mapping. ([34])
* CAPN officially supports unprivileged containers for `instanceType: container`; for that path you must set `PRIVILEGED=false` / `.spec.unprivileged=true`, and pre-built kubeadm images with the proper runtime tuning are available starting from `v1.32.4`. ([24], [17])
* For Canonical LXD CAPN publishes a separate **unprivileged LXD kubeadm profile**: it uses `linux.kernel_modules`, requires `security.nesting=true`, mounts host `/boot` to `/usr/lib/ostree-boot` and additionally disables the `snapd` and `apparmor` systemd units inside the guest. ([17])
* Kubernetes user-namespaces docs require idmap-capable filesystems and runtime support; `containerd 2.0+` supports user namespaces for containers, while `KubeletInUserNamespace` as of Kubernetes `v1.35` is still `Alpha`. ([35], [36], [37])

Consequence:

* `lxd_profiles` for `capi-controlplane` and `capi-worker` are built on the **CAPN Canonical LXD unprivileged kubeadm baseline**, not on a privileged profile;
* for Kubernetes node containers, enable `security.idmap.isolated=true` unless a specific verified workload contract requires otherwise;
* `security.nesting=true` is allowed only on profiles where it is really required for the Kubernetes node/CRI path, not as a project-wide default;
* privileged LXC must not be used as a "quick workaround" for problems with kubelet, containerd, CNI or add-ons;
* if the unprivileged path does not pass a gate, only the following solutions are acceptable:
  * change the CNI / narrow the feature scope on the same unprivileged substrate,
  * or move to VM-based nodes;
* the agent must not waste time on parallel implementations of privileged and unprivileged modes.

## 2.9. Policy on Terraform + Helm delivery for Kubernetes objects

All Kubernetes objects that this repo creates on the bootstrap /
management / workload clusters are delivered **as Helm charts**,
installed by Terraform via the `hashicorp/helm` provider.

Fixed:

* Terraform uses the `hashicorp/helm` provider, pinned in §8 as
  `k8s_lab_helm_provider_version` (version + verification date — §8a);
* the only path to apply any K8s CRs is `helm_release`. `kubectl
  apply -f`, `kubernetes_manifest`, raw YAML under `manifests/*`,
  Ansible post-apply via `kubernetes.core.k8s` with state=present —
  forbidden for create/update/apply. `kubernetes.core.k8s_info` and the
  `hashicorp/kubernetes` provider are allowed **only on the read side**:
  data lookups, status polling, verify-assertions;
* upstream components are installed from their **official Helm chart sources**,
  wrapped in local wrapper charts (`charts/cni-calico/`,
  `charts/metallb-config/`) via `Chart.yaml` dependencies:

  * workload CNI: `projectcalico/tigera-operator` ([26]) — shipped
    implementation in `charts/cni-calico/`; swapping to a different CNI =
    write a new `charts/cni-<other>/` wrapper and change the
    `cni_chart_*` input in the §16.4 module;
  * MetalLB: `metallb/metallb` ([27]) — shipped via the
    `charts/metallb/` subchart wrapper.
* CRs that are not in upstream charts are delivered through **local
  wrapper / owned charts** of this repo under `charts/`. This
  covers two classes of objects:

  * **CAPI topology** (ClusterClass, Kubeadm/CP/Config templates,
    LXC*Templates, Cluster CRs) — §16.2 / §16.3;
  * **Add-ons configuration + validation** (MetalLB IPAddressPool /
    L2Advertisement, CNI + external L2 probe Pods via
    `helm.sh/hook: test`) — §17.2 / §17.3 chart-side specs.

### CAPI CR immutability and revision pattern

The CAPI admission webhook forbids changing most fields of `ClusterClass`
and `*Template` CRs once a Cluster has referenced them. Any
edit of values.yaml = a new chart version = a new set of objects with
new names; the old ones keep living until a controlled switchover.

The implementation is one line in the `metadata.name` of each such CR:

```yaml
metadata:
  name: {{ include "<chart>.fullname" . }}-{{ .Chart.Version }}
```

A chart referencing a ClusterClass (the workload-cluster chart referencing
the cluster-class chart) builds the same name from the same formula in a shared
values block (`clusterClass.chartVersion` is passed by the Terraform
module to both releases at once). Bumping `Chart.yaml.version` →
`helm upgrade` creates a new pair of ClusterClass + Templates and the reference
to them from the Cluster CR; the old ones live until a deliberate cleanup. Without
this, any live edit fails on `admission webhook denied: field is
immutable`.

### Ordering and webhook readiness

The order of helm_releases inside one Terraform apply is set by
explicit `depends_on`:

* CAPI controllers (brought in by `bootstrap_clusterctl` via `clusterctl
  init`, §13.10) — **not** a helm_release of this repo, but a mandatory
  predecessor of any Phase 5+ apply; Phase 4 closes before
  Phase 5 starts;
* `helm_release.cluster_class` — creates ClusterClass + *Templates;
* `helm_release.workload_cluster` (`depends_on = [cluster_class]`) —
  creates the Cluster CR that references the ClusterClass;
* `helm_release.cni_calico` / `helm_release.metallb` /
  `helm_release.metallb_config` — the same 5 releases inside one
  §16.4 module, but via the workload-aliased helm provider (see §16
  module internals).

`helm_release.wait = true` (default in `hashicorp/helm` 3.x) +
`atomic = true` are mandatory on all CR-data releases: without
`wait` the CAPI/CAPN admission webhooks may not be ready to accept traffic
before the next release in the depends_on chain reaches apply;
without `atomic`, partial failures leave the cluster in an inconsistent
state.

`force_update` must remain `false` (default) — enabling it
breaks the SSA ownership of the CAPI/CAPN controllers, leading to flip-flop
reconciliation.

### Test fixtures and orchestration

* `tests/fixtures/terraform/workload-clusters/lab-default/` —
  the only TF root in this repo (§16.5), invoking the §16.4 module
  `workload_cluster` which installs the whole stack in one apply
  (CAPI topology + CNI + MetalLB + chart-side helm tests);
* chart versions are pinned in the §8 variable contract and updated
  deliberately (each bump = an entry in the §8a verified version log);
* in-cluster validation (CNI viability, external L2 viability) is
  part of the same delivery policy, implemented as `helm.sh/hook:
  test` Pods inside `charts/cni-calico/` and `charts/metallb-config/`
  (§17.2 / §17.3), invoked by the §16.4 module via `null_resource` +
  `local-exec helm test` as part of `terraform apply` (§17.1).
  A failed test → null_resource non-zero → TF apply fails.
  Validation is not outside the policy but inside it. There are no separate Ansible
  roles for network validation;
* Terraform is assumed to be already installed on the runner; Ansible
  does not install it. The Helm CLI is also required on the runner — the §16.4
  module uses it via `null_resource` + `local-exec` for
  acceptance helm tests inside the apply. The operator / agent invokes
  Phase 5 manually via a Makefile target (`make deploy-workload` —
  §16.6).

## 2.10. Policy on node images

For `v1.0` the following image strategy is fixed:

* the local harness uses CAPN pre-built kubeadm images with the default simplestreams server by default, e.g. `capi:kubeadm/VERSION`; ([16], [20])
* `INSTALL_KUBEADM=true` is not part of the supported `v1.0` path, because the CAPN documentation explicitly describes this mode as a development-oriented fallback; ([20])
* consumer repos for real environments must be able to override image refs to their custom images with pinning by version/alias/fingerprint.

Consequence:

* in this repo the agent must build code around the prebuilt kubeadm image path;
* the install-kubeadm-at-runtime mode is not a CR field in the CAPN v1alpha2 API — it is modelled by adding `preKubeadmCommands` to KCPT/KCT (chart §16.2 accepts them via `controlPlane.preKubeadmCommands` / `worker.preKubeadmCommands`, the consumer-facing default is an empty list). The substrate-required `preKubeadmCommand` (dual-stack `node-ip` patch for the kubeadm config — see §16.2) is always rendered separately from consumer values; the consumer must not touch it. The default lab deployment uses prebuilt images and an empty consumer list;
* the risk of using evaluation-oriented CAPN images must be explicitly noted and not masked as a production-ready supply path;
* **cloud-init capability is substrate-required for any image**
  going into `k8s_lab_images_controlplane` / `k8s_lab_images_worker`.
  `charts/capi-cluster-class` delivers the eth1 RA reception baseline
  (sysctl + systemd-networkd drop-in) via `KubeadmConfigSpec.files`
  + `preKubeadmCommands` in both kubeadm templates (§16.2 / §16.3) —
  CABPK inlines them into user-data `write_files`, and cloud-init on
  every CAPN-spawned node applies them on first boot. CAPN-prebuilt
  `capi:kubeadm/*` images guarantee this; a consumer's custom image
  without cloud-init = a broken external L2 plane on every
  worker.

## 2.11a. "Test before commit" policy

A strict and basic requirement. No commit is allowed until
the code has been **actually executed** in this repo's local Vagrant/libvirt
loop and has passed the corresponding acceptance check:

* for any new or changed Ansible role — its Molecule scenario is
  run end-to-end against the shared Vagrant VM (at minimum
  `converge → idempotence → verify`), not against the podman/docker driver;
* for any new or changed `Makefile` target — the target is
  actually executed against the same harness;
* for any new or changed Helm chart (upstream values
  override, local wrapper chart, embedded test hook) — the chart
  is installed via the §16.4 TF module in the local harness `make
  deploy-workload` (or an equivalent Molecule e2e-local flow),
  `helm test <release>` must return exit=0. The Gate A/Gate B
  acceptance hooks (§17.2 / §17.3) also fall under this — acceptance
  is proven by a live run,
  not by static review;
* for any plan deviation that adds new verifiable behaviour
  (e.g. the btrfs pool contract from stage 1) — verify must **really
  fire on real state**, not just parse;
* static checks (`yamllint`, `ansible-lint`, `terraform fmt`) are
  necessary but **not sufficient**. "Lint is green" does not
  count as proof of working software;
* if a prerequisite is unavailable (libvirt down, KVM modules not loaded,
  Vagrant missing), the agent must stop and tell the
  user, not lower the bar to a weaker driver;
* commits happen **only after** the user has seen a passing run,
  or has explicitly authorised autonomous work on the task;
* exceptions are recorded directly in this document as separate
  deviation items under the appropriate section (role / phase /
  variable) with justification — see §2.11b on the workflow of "fixing
  the plan as we develop".

This policy cannot be "temporarily lifted" to speed up a session: it
exists because a passed lint stage too often masks
runtime bugs in Ansible / Molecule / Vagrant, and the local harness is already
reproducible enough for honest end-to-end runs.

## 2.11. Policy on dependency versions

A separate mandatory policy without which the rest of the contract loses meaning:

* all external dependencies — Kubernetes, k3s, CAPI/`clusterctl`, CAPN,
  the LXD snap channel, Helm charts (Calico/MetalLB), Terraform
  providers, Ansible collections, base OS images, container runtimes,
  CLI tools — must be pinned to the **current upstream stable
  version at the moment of the bump**;
* "stable safe default" from old documentation or from
  the model's memory **does not count** as a valid choice: before pinning, the agent must
  consult upstream (`GET /repos/<o>/<r>/releases/latest`, vendor snap
  info, registry index) and record the verified value;
* in `requirements.yml` / provider blocks / Helm chart references you must not
  use lower bounds that lock out future major releases:
  any entry of the form `>=X,<X+1` is considered a stale pin and must be removed
  at the moment of the bump;
* every pinned version and verification date is captured **inline
  next to the pin in §8** and additionally aggregated in the §8a table
  to distinguish a deliberate pin from a stale one;
* conflict resolution: if vendor official guidance (e.g. LXD
  Canonical recommendation for LTS 5.21 instead of feature track `6`)
  contradicts "the most recent stable upstream", by default we take
  the most recent feature-stable and explicitly note the trade-off in §8a
  (deviation section);
* the only exception: if upstream has not yet released a stable and only
  prereleases exist — then the previous stable is temporarily allowed, with
  an explicit note in §8a and a task to upgrade at the first stable
  release.

Consequence:

* any code change that introduces or changes a version pin must
  be accompanied by a sync of the §8 inline comment and, if needed,
  a row in the §8a table;
* default values in `defaults/main.yml`, `variables.tf` and shared
  Molecule vars must match the same current
  version as the table entry;
* the CI/lint stage (when it appears) must be able to flag stale pins
  against upstream.

## 2.11b. "Plan is a live document; no separate progress file" policy

The set of files `PLAN-stage1-common.md` + `PLAN-stage1-1.md` ..
`PLAN-stage1-7.md` (and the analogous `PLAN-stage<N>-*.md` set for
future stages) is the **single source of truth** for both
the plan's intent and execution status. The current map of file lineup
with §N ranges and subsection names lives in
the `## Table of contents` of `PLAN-stage1-common.md` (see start of file) — when
shards are added/split it is updated there. The §N numbering is
continuous across all these files (see header of `PLAN-stage1-common.md`), and
cross-references of the form `§<number>` are valid without naming the
file. A separate `PLAN-*-progress.md` / `CHANGELOG.md` or any
external tracker is **not maintained** by the repo — all additions, completion
notes, plan deviations and implementation notes live directly
in these files under the appropriate items (role / phase /
variable). General policies / contract / architecture live in
`PLAN-stage1-common.md`; stage-specific roles, modules, phase order live
in the corresponding `PLAN-stage<N>-*.md` shards (atomic split
along meaning blocks to minimise the context weight of an individual
shard for the coding agent).

What the agent must do **as development progresses**:

* when an implementation reveals that a previously-recorded plan item does not
  work as stated (we hit a platform limitation,
  an architectural detail surfaced only on test), the agent must
  **fix the plan item itself** and record the deviation alongside with
  a date (`Status: done in Step N (YYYY-MM-DD)` + explanation —
  see §13.3, §13.5 as reference);
* any useful architectural detail or implementation note
  not visible from the final code (why module X was chosen, how
  Y did not fit, what operational pitfall lurks) is added
  inline in the corresponding §13.X / Phase section;
* every completed plan item is marked with the line
  `**Status: done in Step N (YYYY-MM-DD).**` at the start of
  its subsection. "Step N" is the number of a major
  development iteration that the agent records in the git commit log and
  has agreed with the operator;
* the listed plan changes must be agreed with
  the operator (conversation level) when they change behaviour or
  scope; minor adjustments (wording, marking
  done, adding an implementation note without a contract change)
  the agent makes without asking.

What is forbidden:

* reviving a separate progress file in any form;
* keeping "what is done" in external systems (GitHub wiki, Notion,
  agent's memory notes) as a substitute for these files — agent memory
  is for preferences and durable workflow hints, not for a
  duplicate registry of completed items;
* leaving a mismatch between actual code behaviour and the plan
  text for longer than one session — if a divergence is noticed,
  either the code is brought in line with the plan, or the plan is
  revised within the same session.

## 2.12. HA policy for workload cluster add-ons

`k8s_lab_workload_controlplane_count` and `k8s_lab_workload_worker_count`
by default provide a fully HA-capable site (default workload
= 3 CP + 2 worker, see §8). It follows that there is a mandatory contract
for everything the §16.4 module installs in the workload cluster via Helm
pass:

* **Replica contract.** Any component whose architecture allows
  multi-replica active/active or leader-elected active/standby
  (i.e. `Deployment` / `StatefulSet` controllers) is deployed with
  `replicas: 2` by default. This applies in particular to:
  * Calico — `calico-kube-controllers` + `calico-apiserver` via
    `Installation.spec.controlPlaneReplicas: 2` (the operator itself gives
    them 2 replicas + built-in podAntiAffinity);
  * MetalLB speaker (`metallb-speaker`) and the Calico node agent
    (`calico-node`) are `DaemonSet`s; their "auto-2" replicas
    come from the fact that `k8s_lab_workload_worker_count = 2`, no separate
    override is needed;
  * any ingress controller / cert-manager / external-dns /
    metrics-server / etc. that may be added to this pass —
    `replicas: 2` by default + `topologySpreadConstraints` or
    `podAntiAffinity` on `kubernetes.io/hostname`, so that replicas
    actually land on two different worker nodes.
* **MetalLB controller — explicit deviation from §2.12** (Step 14):
  upstream `metallb` chart 0.15.3 does NOT set
  `controller.replicas` (the controller is a singleton by upstream design;
  HA delivered through the speaker DaemonSet's leader-election per VIP
  via memberlist). Acceptance criteria for the §16 module do not require
  `replicas==2 + podAntiAffinity` for the MetalLB controller —
  speaker DS rollout + `metallb-controller` Available is the §2.12
  floor for this chart. Documented inline in
  `charts/metallb/values.yaml` + §17.3.
* **When HA does NOT apply.** If a component is architecturally
  a single singleton (like the MetalLB controller above) —
  `replicas: 1` is allowed with an explicit inline comment in the chart
  values explaining why. This is an explicit deviation, not a norm.
* **Test contract — both replicas working in tandem.** §16.4
  acceptance is NOT limited to `kubectl wait deployment <X>
  --for=condition=Available`: condition=Available allows
  `availableReplicas >= maxUnavailable`, which for `replicas: 2 +
  maxUnavailable: 1` gives a green signal even when only one
  is running. Acceptance tests must explicitly assert:
  * `status.readyReplicas == 2` and `status.availableReplicas == 2`
    on every such Deployment / StatefulSet (where applicable);
  * the pair of replica Pods really lives on different nodes
    (`spec.nodeName` is unique across the component's Pod list);
  * leader-elected components have exactly one active
    leader and the second pod in standby.
* **Propagation to the mgmt cluster.** The mgmt cluster in the default
  topology is `1+2` (worker count 2 is a chart-required floor for
  Gate B, see §18.1; the CP stays at 1 because etcd quorum HA is not
  achievable on a single bare-metal host). The replica contract on mgmt
  is activated automatically by the same Terraform condition
  `var.worker_count >= 2`. CP-side HA on mgmt is enabled by the operator
  by raising `k8s_lab_management_controlplane_count` to `3` (the CAPI
  webhook rejects even values under stacked etcd) — that is
  legitimate but not required for the basic pivot.

This contract is documented and enforced in §16.6 acceptance, and
mirrored by concrete assertions in the §9.4 Integration / Full E2E
test scope.

---

# 3. Architectural model — single canonical flow

The architecture is fixed as **one linear path**, modelling the
canonical Cluster API bootstrap-and-pivot pattern. There are no modes /
switches / dispatch branches: bootstrap k3s is **transient
scaffolding** whose only task is to host the mgmt-1
Cluster CR for exactly as long as needed for `clusterctl init` + `clusterctl
move` to turn mgmt-1 into a self-hosted CAPI management
cluster.

## 3.1. Sequence

1. **Substrate + bootstrap k3s.** An Ansible role chain (Phase 0..4)
   brings up the host substrate (LXD, networks, profiles), the bootstrap LXC
   container, and `k3s server` inside it; `clusterctl init` (via
   the `bootstrap_clusterctl` role) makes bootstrap k3s a temporary CAPI
   management cluster. `bootstrap_capn_secret` materialises the CAPN
   identity Secret with the `clusterctl.cluster.x-k8s.io/move: "true"`
   label (the label is always present — pivot is mandatory).
2. **mgmt-1 Cluster CR on bootstrap.** Helm releases
   `capi-cluster-class` + `capi-workload-cluster` with mgmt-topology
   values (1 CP / 2 worker by default, `class_prefix=capn-mgmt`)
   create the `mgmt-1` Cluster CR in the `capi-clusters` namespace on
   bootstrap. CAPN provisions LXC nodes + the haproxy LB instance.
3. **CNI + MetalLB on mgmt-1.** Helm releases `cni-calico` +
   `metallb` + `metallb-config` against the runner-reachable mgmt-1
   kubeconfig. Between the CNI install and the MetalLB install — an explicit
   `kubernetes.core.k8s_info` polling task on all Nodes
   `Ready=True`: `helm install cni-calico --wait` blocks
   only until tigera-operator is Available, while the Installation CR +
   calico-node DS reconcile asynchronously; without polling
   the next MetalLB install's Pods stay Pending on NotReady
   Nodes and `--wait` times out.
4. **Gate A/B helm tests on mgmt-1.** `helm test` on three charts
   (`capi-workload-cluster` cluster-ready hook, `cni-calico` Gate B,
   `metallb-config` Gate A) — the gate before pivot. If the mgmt-1
   data plane is broken, we stop here, not on a failed pivot.
5. **clusterctl init + move bootstrap → mgmt-1.** The
   `pivot_clusterctl_move` role installs the CAPI controllers on mgmt-1 and
   moves all CAPI CRs from the `capi-clusters` namespace on bootstrap
   to mgmt-1 (including the mgmt-1 Cluster CR, ClusterClass, *Templates,
   Machines, KCP, MachineDeployment, owned Secrets — the `move-label`
   pulls the CAPN identity Secret along).
6. **Re-emit `.artifacts/mgmt.kubeconfig`.** A second include of the
   `export_artifacts` role with `export_artifacts_run_meta_chain: false` +
   `export_artifacts_mgmt_kubeconfig_source` = the host-side staging from
   pivot. The same runner-side file that held bootstrap creds is
   overwritten with mgmt-1 creds.
7. **`cleanup_bootstrap`.** The bootstrap LXC is removed. mgmt-1 is now
   self-hosted, the CAPI controllers run on it.
8. **Workload Cluster + add-ons on mgmt-1.** Helm releases
   `capi-cluster-class` + `capi-workload-cluster` with workload-topology
   values (3 CP / 2 worker, `class_prefix=capn-default`,
   `name=lab-default`) against the just-updated
   `.artifacts/mgmt.kubeconfig`. Then `cni-calico` → poll Nodes
   Ready (the same Calico-async-reconcile gate as in step 3) →
   `metallb` + `metallb-config` against the workload kubeconfig.
9. **Gate A/B helm tests on the workload.** Final acceptance — `helm
   test` on three charts + an external curl to the MetalLB VIP via
   `ext6-ra-peer` (Gate A out-of-cluster proof).

After Phase 9: bootstrap k3s is gone, mgmt-1 is self-hosted with CAPI
controllers + CNI + MetalLB, and the `lab-default` workload runs and
sits under mgmt-1's management.

## 3.2. Driver

The end-to-end flow is implemented as `tests/molecule/e2e-local/converge.yml`
+ `verify.yml` (a Molecule scenario) and is launched via `make
test-local-e2e`. There are no standalone Make targets for individual
pivot/mgmt phases — each stage is the inclusion of an existing
role (`export_artifacts`, `pivot_clusterctl_move`, `cleanup_bootstrap`)
or a native `kubernetes.core.helm` install in the playbook.

`make deploy-workload` remains the Terraform route for an operator
who wants to add an **additional** workload Cluster CR
(a second, third…) on an already-self-hosted mgmt-1 via the TF module
`workload_cluster` + the fixture `tests/fixtures/terraform/workload-clusters/lab-default/`.
The same TF route also implements the "production prod-like" path of deploying
workloads to real environments. Bootstrap → mgmt-1 → cleanup
is never done via Make — that is the e2e-local Molecule scenario.

## 3.3. Why pivot is mandatory

Helm-release secrets (`sh.helm.release.v1.<release>.v1` in the
release namespace) are stored as Kubernetes Secrets, not as CAPI
CRs. `clusterctl move` follows only the object reference graph
of ClusterClass + Cluster CRs and does not touch helm storage. If
a workload Cluster CR is created on bootstrap, its helm-release
storage stays on bootstrap and disappears with `cleanup_bootstrap`,
leaving an "orphaned Cluster CR without an owning helm
release" on the target mgmt-1. Any `terraform destroy` / `helm uninstall`
on this CR after pivot fails with `release not found`.

The solution is to never create workload Cluster CRs on bootstrap.
mgmt-1 is the only "helper" of bootstrap, and pivot is the only
way to correctly free it from the scaffolding. After pivot, all
subsequent workloads are created on mgmt-1. Therefore pivot is
mandatory + workload-on-bootstrap does not exist as a path.

`clusterctl init` + `clusterctl move` are the official CAPI
bootstrap-and-pivot flow ([Cluster API][7], [Cluster API][8]).

### Network surface asymmetry between bootstrap and self-hosted

bootstrap k3s runs in a regular LXC (single binary) — k3s server +
all CAPI/CAPN controllers run in **host-network mode** directly on
the bootstrap LXC instance. The source IP of their traffic is the bootstrap
container's own `eth0` IPv6 in the `capi-int` subnet (`fd42:77:1::xxx`).

Self-hosted mgmt-1 is a full Kubernetes — the same CAPI/CAPN
controllers run as Pods, the source IP of their traffic is the Pod
IPv6 in `fd42:77:2::/56` (Calico-managed Pod CIDR).

This change of network surface — bootstrap host-network ↔ self-hosted
Pod-network — is **a different routing context** for outbound connections
to the substrate (capi-int LXD bridge, host LXD daemon HTTPS, haproxy LB
instances). Any feature that works on bootstrap (e.g.,
the CAPI cluster-cache reach to the LB IPv6) must be explicitly checked in
self-hosted Pod-network mode, because pre-pivot success **does not**
guarantee post-pivot success.

A concrete example: Pod→substrate IPv6 SNAT via Calico
`natOutgoing: Enabled` (§17.2) — invisible pre-pivot because
the host-network bootstrap does not route Pod IPv6 at all. Post-pivot
it is mandatory, otherwise the CAPI controllers cannot reach the workload
LB. Therefore the canonical flow §3.1 includes pivot **as a mandatory
step inside e2e-local converge** — that is the form of "we run
the self-hosted path in every end-to-end test".

---

# 4. Final network architecture

## 4.1. Overall scheme

The bare metal host has two network planes:

### External plane

* a Linux bridge, e.g. `br-ext6`;
* tied to the host's uplink/WAN interface;
* external IPv6 /64 runs on this segment;
* RA and NDP go on it;
* the **external NIC** of every Kubernetes node is plugged into it;
* it is used only for:

  * external IPv6 of nodes,
  * NodePort ingress,
  * MetalLB IPv6 VIP.
    The LXD `bridged` NIC uses an existing bridge on the host and creates a veth pair; managed and unmanaged bridge attachments are both supported. ([Ubuntu Documentation][9])

### Internal plane

* an LXD managed bridge, e.g. `capi-int`;
* dual-stack;
* a local L2 segment;
* `dnsmasq` for DHCP/DNS/IPv6 RA;
* NAT44/NAT66 via the host;
* all regular control-plane/admin/node-to-node/egress traffic goes here.
  The LXD bridge documentation explicitly says the bridge creates an L2 segment, runs `dnsmasq` for DHCP/IPv6 RAs/DNS and performs NAT by default. For IPv6 a /64 is recommended on an LXD bridge. ([Ubuntu Documentation][2])

## 4.2. Role of interfaces inside a node

### `eth0` = internal

* dual-stack;
* kubelet/node identity;
* `--node-ip`;
* default route;
* pod/node/control-plane underlay;
* all regular egress.

### `eth1` = external

* IPv6-only;
* global IPv6 on the external segment;
* ingress only;
* not the default route;
* NodePort and MetalLB ingress.

For Kubernetes dual-stack cluster docs explicitly require a dual-stack-capable CNI and recommend `kubelet --node-ip=<IPv4>,<IPv6>` for bare-metal dual-stack nodes. ([Kubernetes][10])

## 4.3. Why ingress and egress are separated

Ingress and egress are deliberately separated:

* the external NIC must not become "the main lifeline network" of the node;
* the internal NIC carries the regular underlay logic;
* the external segment stays a narrowly specialised north-south path;
* it is easier to control kubelet/node IP and the default route.
  This matches your target role for the interfaces and reduces the risk that kubelet, kube-proxy or regular system egress will suddenly leave through the external IPv6 ingress NIC. ([Kubernetes][10])

---

# 5. Networking contract

## 5.1. External addressing

Example:

* external prefix: `2001:db8:1200:3400::/64`
* host: `2001:db8:1200:3400::1`
* node ext IPv6 range: `::10-::3f`
* MetalLB VIP range: `::200-::2ff`

This is **a logical reservation** within one /64, not a split into different routed subnets. MetalLB `IPAddressPool` can use ranges/CIDRs inside an IPv6 prefix. ([metallb.io][11])

## 5.2. Internal addressing

Example:

* IPv4: `10.77.0.0/24`
* IPv6 ULA: `fd42:77:1::/64`

Recommended baseline for `capi-int`:

* `ipv4.address=10.77.0.1/24`
* `ipv4.dhcp=true`
* `ipv4.nat=true`
* `ipv6.address=fd42:77:1::1/64`
* `ipv6.dhcp=true`
* `ipv6.dhcp.stateful=true`
* `ipv6.nat=true`

LXD supports `ipv6.dhcp.stateful`, and static IPv6 assignment for an instance NIC is possible only if the parent managed network has `ipv6.dhcp.stateful=true`. ([Ubuntu Documentation][12])

## 5.3. Guest-side route policy

For the Debian 13 guest, **systemd-networkd** is chosen.

This policy for CAPN-managed nodes must reach the machines via Terraform-owned machine bootstrap data/templates, not via Ansible post-config inside workload/management clusters.

The concrete delivery mechanism is also fixed:

* `KubeadmControlPlaneTemplate` and `KubeadmConfigTemplate` via CABPK are the only supported path;
* network files must reach the nodes via `KubeadmConfigSpec.files`;
* commands enabling/reloading `systemd-networkd` and related pre-bootstrap actions must go via `preKubeadmCommands`;
* kubelet flags such as `--node-ip` must be set via `nodeRegistration.kubeletExtraArgs`;
* kubeadm/kubelet patches must be delivered via `files` + `patches.directory`, where appropriate. ([7], [28], [29])

### `eth1` (external)

* `IPv6AcceptRA=yes`
* `[IPv6AcceptRA] UseGateway=no`

This allows:

* receiving RAs;
* getting on-link reachability / addressing;
* **not** importing the default route into the main table.
  The systemd-networkd manpage officially supports `IPv6AcceptRA=` and `UseGateway=` for RAs. ([Kubernetes][10])

### `eth0` (internal)

* a regular dual-stack config;
* default route;
* kubelet node IP.

## 5.4. kube-proxy NodePort policy

Since the contract requires that NodePort be accepted **only** on the external IPv6 addresses of the node, `--nodeport-addresses=<external IPv6 CIDR>` or the equivalent field in the kube-proxy config is **mandatory**. This setting must come via Terraform-owned cluster configuration, not via Ansible. The Kubernetes docs state directly that `nodePortAddresses` restricts on which local node IPs NodePort connections are accepted. ([Kubernetes][13])

## 5.5. MetalLB policy

MetalLB L2 stays the baseline solution.

MetalLB manifests and policy must be applied by Terraform modules as part of cluster-scoped configuration.

If the upstream MetalLB chart values are insufficient for the precise delivery of `IPAddressPool` and `L2Advertisement` with the required `interfaces`/`nodeSelectors`, those CRs must be delivered by a separate local wrapper Helm chart of this repo, installed by the same `helm_release`, not by ad hoc manifest apply.

Required:

* an `IPAddressPool` from the external IPv6 range;
* an `L2Advertisement` with:

  * `interfaces: [eth1]`
  * `nodeSelectors` for nodes with the external NIC

MetalLB docs separately warn that the `interfaces` selector by itself **does not affect leader election**, so it must be combined with `nodeSelectors`, otherwise the VIP may be selected on a node without the required interface. In L2 mode only one node announces a given VIP. ([metallb.io][11])

---

# 6. Validation gates — in-cluster via Helm test hooks

Validation gates (CNI viability, external L2 viability) are implemented
as **chart-side `helm.sh/hook: test` Pods** in the same Helm charts
that already install the corresponding component on the steady-state path:
Gate B in `charts/cni-calico/` (Step 13), Gate A in
`charts/metallb-config/` (Step 14). The invocation is via
`null_resource` + `local-exec helm test` inside a single §16.4 TF
module as part of `terraform apply` (see §17.1 contract +
§17.2/§17.3 chart specs). A failed helm test fails TF apply
and stops the pipeline.

Doctrine:

* **Production-path mirror.** Worker nodes are created by CAPN via
  manifest change → CAPN controller → LXD API → cloud-init inside
  the container. Validation goes through the same mechanism — a Helm test Pod
  runs on a real worker node, uses the production LXD
  profile and the cloud-init-configured eth1.
* **One-tool pipeline.** Phase 5 is driven by a single Terraform
  module §16.4. Helm natively supports test hooks
  (`helm.sh/hook: test` annotation on a Pod), the TF module invokes
  them via `null_resource` immediately after the corresponding
  `helm_release`.
* **Real data plane.** A Helm test Job with `hostNetwork: true` and
  anti-affinity across worker nodes uses the very same eth1 /
  br-ext6 / LXD profiles as production workloads. RA/NDP/
  multi-MAC/ingress are checked on the real data plane.

## Gate A — External L2 viability

Implementation: a pair of tests around the `metallb-config` release (§17.3).
Acceptance is split into a **chart-side helm test hook**
(in-cluster proof) and a **verify-side external curl** (out-of-cluster
proof). MetalLB is the only consumer of external L2 capability (NDP
for IPv6 VIP announcement), so acceptance sits with the release where
the capability is first really needed.

Test stack: the chart's hook driver Pod creates a real demo
Deployment (nginx-on-alpine, dual-family `listen 80; listen [::]:80;`)
+ Service type=LoadBalancer (`ipFamilies: [IPv6]`, single-stack v6).
The demo stack is driver-managed (kubectl apply from inside the driver Pod),
not annotated with `helm.sh/hook: test` — it survives `Phase: Succeeded` and
is available to the verify-side test for an external curl.

Acceptance criteria (Gate A is green when both pass):

1. **chart-side helm test hook PASS** (`helm test metallb-config`,
   exit=0). 8 in-cluster phases:
   - kubectl install
   - metallb controller Deployment Available (label-selector,
     release-name agnostic)
   - metallb speaker DaemonSet rolled out
   - cleanup of stale demo from prior run (idempotent re-runs)
   - apply demo Deployment + LoadBalancer Service
   - backend Pod Ready
   - `Service.status.loadBalancer.ingress[0].ip` allocated AND
     in-pool (string-prefix sanity vs `pool.rangeV6`)
   - in-cluster HTTP probe FROM driver Pod (`wget [VIP]:80`,
     non-hairpin path: the driver is not a Service endpoint, kube-proxy
     nftables DNAT short-circuits)
2. **verify-side external curl PASS** — Molecule e2e-local Verify
   reads VIP via `kubernetes.core.k8s_info` (workload kubeconfig on
   VM), then `ansible.builtin.uri url=http://[<VIP>]:80/` **on the
   VM** (not delegate_to runner). Path: VM → `ext6-ra-peer`
   (`2001:db8:42:100::1/64`) → veth → `br-ext6` → eth1 of speaker
   leader (NDP-resolved) → kube-proxy nftables DNAT (`mark-for
   -masquerade` + DNAT to backend Pod v6 IP) → backend nginx →
   HTTP 200 body matches `^ok`. Production-path mirror: same
   networking the consumer's external segment uses; only the RA
   source is in-VM radvd vs. provider router.

The test driver Pod survives `Phase: Succeeded` via
`hook-delete-policy: before-hook-creation` (no hook-succeeded). Same
rationale as cni-calico Step 13: `helm test --logs` race with
hook-succeeded reaping. Demo Deployment + Service are NOT
hook-annotated; they live under the release until the next `helm test` cycle or
`helm uninstall`.

If the chart-side hook fails — Phase 5 apply does not pass,
further implementation halts (MetalLB without working L2 is
useless). The fallback branch (routed / proxy-NDP) is a consumer
decision point, not part of Stage 1 scope.

Important: a local pass validates **the reusable code path and the in-VM harness
RA/segment model** (§9.2 Step 9), but does not prove properties of
a specific real uplink/switch/provider. The consumer repo for
the real environment must run an equivalent test on the actual
external segment — that is the same chart, the same profiles, only the RA
arrives from a real provider router instead of in-VM radvd, and
the verify-side curl runs from a truly external endpoint.

## Gate B — CNI compatibility

Implementation: a Helm test hook on the CNI release (shipped — Calico via
`charts/cni-calico/`), §17.2. This is the first Helm release after the CAPI
topology in the §16.4 module chain, and without a working CNI no other
add-on will go further — therefore validation is exactly here.

Acceptance criteria:

* **nodes become Ready** — all control plane and worker nodes are in the
  Ready state after the CNI install (the test hook reads `kubectl get nodes`);
* **pod-to-pod works** — the test hook deploys 2 Pods on different worker
  nodes and checks direct pod-IP reachability in the set of
  address families that the chosen CNI claims;
* **Service networking works** — the test hook creates a Service of
  type ClusterIP and checks that traffic via the Service endpoint arrives;
* **we do not run into nested LXC restrictions** — CNI bring-up does not fail
  on missing kernel features; if it does — the gate
  fails with a clear message;
* **MetalLB preparation** — iptables/ipvs chains look as
  MetalLB expects (not checked directly here, validation in
  Gate A — §17.3 — covers it).

### Decided (CNI baseline, independent of the test mechanism)

* **the unprivileged LXC substrate is fixed up front and not negotiable for CNI convenience**
* **workload CNI = Calico** — a single shipped implementation in the repo
  (`charts/cni-calico/`). It provides NetworkPolicy, dual-stack IPAM
  and an eBPF option, which the target architecture in §4/§5 requires.
* **there is no alternative-path bundle in the repo** and **no toggle variable**
  for automatic CNI switching to another implementation. The §16.4
  module accepts `cni_calico_chart_version` as input for the shipped
  Calico wrapper; swapping to a different CNI is an explicit design
  decision (a new wrapper chart `charts/cni-<whatever>/` + a new
  input in the module), not a runtime flag.
* **privileged LXC is forbidden as a workaround for CNI problems**

Why so:

* the target architecture in §4/§5 is dual-stack IPv4+IPv6 with NetworkPolicy
  enforcement. Calico covers both requirements with one implementation;
* the Calico documentation for a standard Kubernetes installation
  describes some capabilities, so Gate B (§17.2) on
  our unprivileged LXC substrate is mandatory — acceptance via a live
  probe, not static review ([26]);
* if Gate B fails — that is a signal that the chosen CNI implementation
  is incompatible with the unprivileged LXC substrate. The decision to swap CNI
  (a new wrapper chart) is a separate design step, after honest
  root-cause analysis, not an automatic fallback without understanding
  why Calico did not work. The unprivileged LXC substrate stays
  fixed; CNI is a variable;
* therefore for `v1.0` the priority is:
  * first preserve host-level isolation through unprivileged LXC,
  * then use Calico as the target CNI,
  * Gate B passes — plan executed; does not pass — stop, root-cause
    analysis + replacement of the wrapper chart in a separate step.

## Substrate precondition — eth1 RA reception baseline via KubeadmConfigSpec

For the Gate A/B helm tests in the §16.4 module to even have a
working eth1 on worker nodes — the external NIC must be
configured **before the first Helm install** in the module chain. This
baseline is delivered by `charts/capi-cluster-class` via
`KubeadmConfigSpec.files` + `preKubeadmCommands` in both
`KubeadmControlPlaneTemplate` and `KubeadmConfigTemplate` (§16.2 / §16.3):

* two files on every CAPN-spawned node:
  * `/etc/sysctl.d/99-capi-ra.conf` — `net.ipv6.conf.eth1.{disable_ipv6=0,
    accept_ra=2, accept_ra_defrtr=1}`. `accept_ra=2` is required because
    workload nodes run with `forwarding=1` for k8s pod networking,
    and the default `accept_ra=1` ignores RAs when forwarding=1;
  * `/etc/systemd/network/30-capi-ext.network` — `[Match] Name=eth1
    [Network] DHCP=no LinkLocalAddressing=ipv6 IPv6AcceptRA=yes`;
* `preKubeadmCommands` runs `sysctl --load` + `networkctl reload`,
  so the config is alive before kubelet, kube-proxy, MetalLB speaker
  start;
* CABPK inlines the files as user-data `write_files` — the only
  reliable wiring on a kubeadm-bootstrapped node, where CAPI/CABPK
  exclusively owns the user-data slot;
* the consumer's `k8s_lab_images_controlplane` / `k8s_lab_images_worker`
  **must** be cloud-init-capable (CAPN-prebuilt `capi:kubeadm/*`
  images already provide this, see §8a).

Effect: eth1 SLAACs a global IPv6 from the upstream RA, the MetalLB speaker
sends NDP replies on announced VIPs with a global source IPv6.

---

# 7. Repository

```text
repo/
  Makefile
  README.md

  ansible/
    ansible.cfg
    roles/
      base_system/
      binary_fetch/
      lxd_host/
      lxd_project/
      lxd_storage_pools/
      lxd_network_int_managed/
      lxd_profiles/
      lxd_bootstrap_instance/
      bootstrap_k3s/
      bootstrap_clusterctl/
      bootstrap_capn_secret/
      pivot_clusterctl_move/
      cleanup_bootstrap/
      export_artifacts/

  clusterctl/
    clusterctl.yaml

  charts/
    capi-cluster-class/    # §16.2 ClusterClass + Kubeadm*/LXC* templates
    capi-workload-cluster/ # §16.3 Cluster CR instance
    cni-calico/            # §17.2 wrapper over projectcalico/tigera-operator (shipped CNI) + Gate B inline
    metallb/               # §17.3 minimal subchart-wrapper over upstream metallb (CRDs + controller + speaker)
    metallb-config/        # §17.3 IPAddressPool + L2Advertisement + Gate A inline (helm test hook)

  terraform/
    modules/
      workload_cluster/    # §16.4 the only TF module — CAPI topology + CNI + MetalLB + helm tests in one apply

  tests/
    molecule/
      Makefile
      shared/
        converge.yml
        verify.yml
        vars/
        tasks/
          prepare.yml
          wait-services.yml
      # scenario directory names are kebab-case (Molecule / Make target
      # convention) — they reference the snake_case Ansible role via
      # `_shared_target_role` inside molecule.yml; see §2.6.3.
      base-system/
      binary-fetch/
      lxd-host/
      lxd-project/
      lxd-storage-pools/
      lxd-network-int-managed/
      lxd-profiles/
      lxd-bootstrap-instance/
      bootstrap-k3s/
      bootstrap-clusterctl/
      bootstrap-capn-secret/
      export-artifacts/
      cleanup-bootstrap/
      pivot/
      e2e-local/
    fixtures/
      terraform/
        workload-clusters/
          lab-default/   # §16.5 the only TF root, invokes the workload_cluster module
            main.tf
            variables.tf
            providers.tf
            outputs.tf
    vagrant/
      debian13/
        Vagrantfile
        inventory.sh
        libvirt-networks/
          mgmt-nat.xml
          probe-ext6.xml  # dormant, K8SLAB_PROBE=1 gated

  scripts/
    render_kubeconfig.py
    export_bootstrap_facts.py
    wait_for_cluster.sh
    molecule_create.sh
    molecule_destroy.sh

  .artifacts/
    .gitkeep
```

In principle:

* the repo has **no** `inventories/prod`, `inventories/local` and top-level deploy playbooks for real environments;
* the repo has **no** environment root modules for specific sites;
* `tests/fixtures/terraform/*` exist only as **test consumers** for local e2e and module-contract checks;
* `tests/molecule/*` is a common repo-level harness, but in operational style it must follow the best practices of `naive_proxy`: shared prepare/verify logic, a unified wrapper `Makefile`, explicit workarounds for `molecule + vagrant-libvirt`;
* `tests/fixtures/*` do not contain separate implementation logic, only invoke reusable roles/modules with synthetic inputs;
* every role must have its own `README.md`, `defaults/main.yml`, dispatcher `tasks/main.yml` and split task files by major sub-themes;
* **all Kubernetes objects are delivered via Helm** (§2.9). `charts/`
  is the only source of truth for CR content, applied only by
  Terraform `helm_release`. There is no separate ownership layer
  `manifests/`; raw YAML for apply, `kubectl apply -f`,
  `kubernetes_manifest`, `kubernetes.core.k8s state=present` are
  forbidden for create/update;
* **The Makefile is the only entry point** for all orchestration
  operations (rule `feedback_makefile_only.md`). Phase 0..4
  is tested via Molecule scenarios (`make -C tests/molecule
  <scenario>-delegated-test`), Phase 5 is run via
  the only TF target of the root Makefile (`make deploy-workload`,
  §16.6). Terraform + Helm CLI are assumed to be already installed on the
  runner; Ansible does not install them. `vagrant` / `virsh` / `molecule`
  / `terraform` are not invoked directly;
* production consumer repos must build their own inventories/playbooks/root modules around these roles/modules.

Ansible roles are the standard reusable unit for orchestration; Terraform modules are the standard reusable composition unit; the Molecule delegated driver lets us manage the VM lifecycle ourselves via Vagrant/libvirt. ([ansible.readthedocs.io][14])

---

# 8. Typed variables contract

Below is the essential set. In code it must land in `defaults/main.yml` and `variables.tf`.

This is precisely the **public interface contract** of the reusable roles and modules.

* test fixtures inside this repo may use synthetic values;
* concrete values for real environments, secrets, overlays and tfvars must be set in separate private consumer repos.

Naming rule (memory `feedback_global_var_prefix.md`, 2026-04-23):
every project-wide global carries the `k8s_lab_` prefix. Role-scoped
variables keep their `<role_name>_*` prefix per §2.6.2. There is no
third naming category — naked globals like `opt_root` or
`api_publish_port` are banned because they collide silently with
unrelated vars inherited from wider inventory.

Variables are grouped below by logical section for readability
(these are NOT namespaces in Ansible — the `_section_` fragment is
part of the flat variable name; `k8s_lab_storage_pool_name` is a
single identifier, not `k8s_lab.storage.pool_name`).

```yaml
# ---- global ----
k8s_lab_opt_root: {type: string, default: "/opt/capi-lab"}
k8s_lab_project_name: {type: string, default: "capi-lab"}

# ---- capi ----
k8s_lab_infrastructure_secret_name: {type: string, default: "incus-identity"}  # matches CAPN upstream identity-secret default name
k8s_lab_cluster_topology_enabled: {type: bool, default: true}
k8s_lab_unprivileged_nodes: {type: bool, default: true}

# ---- workload api endpoint reachability ----
# Runner-reachable address of the LXD host. The workload kube-apiserver
# listens on capi-int IPv6 (`fd42:77:1::/64`), which is reachable
# only from inside the VM/LXD instances. Module §16.4 writes the workload
# kubeconfig with `server: https://<k8s_lab_lxd_host_address>:<port>`,
# where the port is a per-workload Adler-32 hash of cluster.name (default
# range 20000-29999, override via chart values
# `loadBalancer.lxc.proxyApiPort`). An LXD proxy device on the CAPN
# haproxy LB instance with `bind=host` forwards host:<port> →
# 127.0.0.1:6443 inside the LB. On local Vagrant — Vagrant VM IP, on
# prod — public IP / DNS name of the LXD host.
k8s_lab_lxd_host_address: {type: string, required: true}

# ---- host ----
k8s_lab_host_distro: {type: string, default: "debian-13"}
# lxd_host_* inputs are consumed by role lxd_host (plan §13.2) and
# already carry the role prefix — they are NOT globals and therefore
# do NOT take a k8s_lab_ prefix.
lxd_host_snap_channel: {type: string, default: "6/stable"}          # verified 2026-04-21; plan §2.11 — newest feature-stable track
lxd_host_snap_refresh_mode: {type: string, default: "hold"}         # hold|timer
lxd_host_snap_refresh_timer: {type: string, default: "fri,03:00-04:00"}

# ---- storage ----
k8s_lab_storage_pool_name: {type: string, default: "capi-fast"}
k8s_lab_storage_driver: {type: string, default: "btrfs"}
# `source` is the path to a block device (/dev/disk/by-id/...),
# not to a mounted filesystem. The LXD snap is AppArmor-confined and has no
# access to arbitrary host paths outside /var/snap/lxd/common/.
# For the btrfs driver, LXD formats the device via mkfs.btrfs
# without -f, so the device must be signature-free on the first
# converge — see §13.4 implementation notes.
k8s_lab_storage_source: {type: string, required: true}
k8s_lab_storage_btrfs_mount_options: {type: string, default: "user_subvol_rm_allowed"}

# ---- networking ----
k8s_lab_uplink_interface: {type: string, required: true}
k8s_lab_external_bridge_name: {type: string, default: "br-ext6"}
k8s_lab_internal_network_name: {type: string, default: "capi-int"}
k8s_lab_internal_ipv4_subnet: {type: string, default: "10.77.0.0/24"}
k8s_lab_internal_ipv6_subnet: {type: string, default: "fd42:77:1::/64"}
k8s_lab_internal_ipv4_nat: {type: bool, default: true}
k8s_lab_internal_ipv6_nat: {type: bool, default: true}
k8s_lab_external_ipv6_prefix: {type: string, required: true}
k8s_lab_external_node_ipv6_range: {type: string, required: true}
k8s_lab_metallb_vip_range_v6: {type: string, required: true}
k8s_lab_guest_internal_ifname: {type: string, default: "eth0"}
k8s_lab_guest_external_ifname: {type: string, default: "eth1"}
k8s_lab_guest_network_backend: {type: string, default: "systemd-networkd"}

# ---- bootstrap ----
k8s_lab_bootstrap_instance_name: {type: string, default: "capi-bootstrap-0"}
# Defaults track current upstream stable per plan §2.11; every bump
# records its verification date inline next to the pin. See §8a.
k8s_lab_k3s_version: {type: string, default: "v1.35.3+k3s1"}         # verified 2026-04-21
k8s_lab_kubectl_version: {type: string, default: "v1.35.3"}          # verified 2026-04-21
k8s_lab_clusterctl_version: {type: string, default: "v1.12.5"}       # verified 2026-04-21
k8s_lab_capn_provider_version: {type: string, default: "v0.8.5"}     # verified 2026-04-21
# External publication of the bootstrap API cluster, if required, is
# done via an LXD proxy device on the bootstrap LXC instance — see §15.5 + role
# lxd_bootstrap_instance (parameter `lxd_bootstrap_instance_devices`).
# No separate globals are introduced for this: listen/connect/bind
# are passed by the consumer in host_vars of that role, because it is a property
# of A SPECIFIC instance, not a project-wide contract. A source-IP ACL on
# the host firewall is out of scope for this repo (§11.4).

# ---- images ----
# Contract: both images MUST be cloud-init-capable.
# `charts/capi-cluster-class` delivers the eth1 RA reception baseline
# (sysctl + systemd-networkd drop-in) via `KubeadmConfigSpec.files`
# + `preKubeadmCommands` — CABPK inlines them into user-data
# `write_files`, and cloud-init on every CAPN-spawned node applies
# them on first boot. CAPN-prebuilt `capi:kubeadm/*` images
# guarantee this; a consumer's custom image must keep cloud-init in
# the same form.
k8s_lab_images_controlplane: {type: string, default: "capi:kubeadm/VERSION"}
k8s_lab_images_worker: {type: string, default: "capi:kubeadm/VERSION"}
k8s_lab_images_source_policy: {type: string, default: "capn-prebuilt"}   # capn-prebuilt|consumer-custom
k8s_lab_images_controlplane_fingerprint: {type: string, default: ""}
k8s_lab_images_worker_fingerprint: {type: string, default: ""}

# ---- templates ----
# LXCMachineTemplate public contract (see §16.2). Substrate-required
# baselines (`capi-base` + `capi-controlplane` / `capi-worker` from role
# `lxd_profiles` §13.6; `instanceType: container`;
# `unprivileged: true`; `skipDefaultKubeadmProfile: true`) are baked
# into the chart itself by the memory rule "Chart-required values are
# hardcoded". The variables below are consumer extras only on top of the baseline.
k8s_lab_controlplane_profiles_extra: {type: list(string), default: []}
k8s_lab_worker_profiles_extra: {type: list(string), default: []}
# Devices accepted in CAPN v1alpha2 []string CSV format, for example
# `"eth1,type=nic,network=br-ext6"` — these are overrides on top of LXD
# profiles, not a replacement for them.
k8s_lab_controlplane_devices_extra: {type: list(string), default: []}
k8s_lab_worker_devices_extra: {type: list(string), default: []}
k8s_lab_idmap_isolated: {type: bool, default: true}
k8s_lab_network_files_strategy: {type: string, default: "cabpk-files"}
k8s_lab_patch_delivery_strategy: {type: string, default: "cabpk-files-plus-patches"}

# ---- cni ----
# Default workload CNI = Calico. Shipped in the repo as the only
# wrapper implementation (`charts/cni-calico/`), consumed by the §16.4
# module directly via the `cni_calico_chart_version` input. Swapping
# to a different CNI implementation (Cilium, kube-router, etc.) — add
# a new wrapper chart in `charts/cni-<whatever>/` + add a
# corresponding input in the §16.4 module. There is no toggle variable in §8
# by design — a one-time design decision, not a runtime flag.
# Privileged LXC as a workaround for CNI problems is forbidden (§2.8).

# ---- addons ----
# Defaults track current upstream stable per plan §2.11. Verification
# dates inline — §8a below compiles a single table. Only shipped
# upstream dependencies are listed; the CNI / MetalLB wrapper chart paths
# are implicit in the §16.4 module — pins of upstream versions inside the charts
# `charts/cni-calico/Chart.yaml` + `charts/metallb/Chart.yaml`
# (k8s_lab_calico_chart_version + k8s_lab_metallb_chart_version —
# pins of dependencies in `Chart.yaml` of the wrappers).
k8s_lab_helm_provider_version: {type: string, default: "3.1.1"}                                           # verified 2026-04-21
k8s_lab_calico_chart_repository: {type: string, default: "https://docs.tigera.io/calico/charts"}
k8s_lab_calico_chart_name: {type: string, default: "tigera-operator"}
k8s_lab_calico_chart_version: {type: string, default: "v3.31.5"}                                          # verified 2026-04-21
k8s_lab_metallb_chart_repository: {type: string, default: "https://metallb.github.io/metallb"}
k8s_lab_metallb_chart_name: {type: string, default: "metallb"}
k8s_lab_metallb_chart_version: {type: string, default: "0.15.3"}                                          # verified 2026-04-27
k8s_lab_kube_proxy_nodeport_addresses: {type: list(string), default: []}  # derive from external IPv6 policy if empty
k8s_lab_metallb_enabled: {type: bool, default: true}
k8s_lab_metallb_interface: {type: string, default: "eth1"}
k8s_lab_metallb_node_selector_labels: {type: map(string), default: {}}
k8s_lab_metallb_wrapper_chart_path: {type: string, default: "charts/metallb-config"}

# ---- clusters ----
k8s_lab_management_cluster_name: {type: string, default: "mgmt-1"}
k8s_lab_workload_cluster_name: {type: string, default: "lab-default"}
# Workload/mgmt Kubernetes version. NOT a free-form "latest upstream
# stable" pick (memory rule §2.11) — CAPN consumes prebuilt LXC images
# from `https://images.linuxcontainers.org/capn/`, and that
# simplestreams server publishes only a curated subset (typically the
# `.0` of each minor + occasional patches). Workload Cluster CRs that
# request a version absent from simplestreams fail at LXCMachine
# provisioning time with `Failed getting image: The requested image
# couldn't be found for fingerprint "kubeadm/<ver>"`.
#
# Therefore this pin tracks "latest stable kubeadm image available on
# CAPN simplestreams", verified by:
#   curl https://images.linuxcontainers.org/capn/streams/v1/images.json
# (separate from k3s/kubectl pins, which target dl.k8s.io binaries
# and have no such constraint).
k8s_lab_kubernetes_version: {type: string, default: "v1.35.0"}           # verified 2026-04-25 against CAPN simplestreams
# Topology defaults for the two CAPN-provisioned clusters.
#
# Hard CAPI invariant: kubeadm-based KubeadmControlPlane with stacked
# etcd (the only topology this repo supports — external etcd is out of
# scope for v1.0) REJECTS even controlPlane.replicas at the webhook
# level (split-brain risk under partition). Therefore CP counts MUST
# be odd: 1 (no HA), 3 (minimum HA), 5 (HA with maintenance margin).
# Workload default = 3 → real multi-CP kubeadm reconciliation +
# Calico/MetalLB failover paths get exercised in §17.x.
# Mgmt default = 1 → small footprint; mgmt is self-hosted post-pivot
# (canonical flow §3) and runs CAPI controllers, but no user
# workloads land on it. Bumping mgmt CP to 3 is the operator's call
# when CAPI controller HA is desired.
#
# Worker counts are unconstrained by the etcd quorum rule; defaults
# track v1.0 lab footprint (2 workers mgmt, 2 workers workload).
# Workload counts are tunable via Terraform vars on the workload
# fixture root (§16.6); mgmt counts are consumed via §8 globals by
# the e2e-local converge play (§10.2).
#
# Mgmt worker floor = 2: this is a CHART-REQUIRED minimum, not a
# production HA preference. The cni-calico chart's helm test phase 6
# ("live pod-to-pod ICMP4+ICMP6 across workers" — §17.2) uses
# `requiredDuringScheduling pod-anti-affinity` to ensure probe-a and
# probe-b land on distinct worker nodes; with worker_count=1 probe-b
# stays Pending and TF apply fails on the gate. Any cluster going
# through the workload_cluster TF module (§16.4) — which
# unconditionally drives Gate B — therefore requires ≥2 workers.
k8s_lab_management_controlplane_count: {type: int, default: 1}
k8s_lab_management_worker_count:       {type: int, default: 2}   # chart-required floor (Gate B) — see comment above
k8s_lab_workload_controlplane_count:   {type: int, default: 3}   # CAPI invariant: must be odd
k8s_lab_workload_worker_count:         {type: int, default: 2}

# ---- CAPN identity Secret target namespaces ----
# Architectural truth (verified Step 11 against CAPN v0.8.5 controller
# behaviour): CAPN does NOT read the LXD identity Secret from its own
# controller namespace (`capn-system`). It looks the Secret up by
# `LXCCluster.spec.secretRef.name` in the **same namespace as the
# LXCCluster CR**. CAPN v1alpha2 LXCCluster.spec.secretRef has no
# `namespace` field — cross-namespace lookup is not supported.
#
# Therefore the identity Secret must live in EVERY namespace where
# workload Cluster CRs (and thus LXCCluster CRs created by the
# capi-cluster-class chart on Cluster reconcile) will be created.
# §13.11 `bootstrap_capn_secret` materialises the Secret in each
# namespace listed here; §19.x Phase 8 destroy removes it from the
# same list.
#
# Default = ["capi-clusters"] matches the workload-cluster chart's
# default Release.Namespace (§16.3). Multi-cluster scenarios (e.g.
# fleet of per-tenant Cluster CRs across namespaces) extend this list.
# The list MAY be empty for runs that do not (yet) need workload
# Cluster CRs — the role short-circuits the Secret task and only
# materialises HTTPS listener + LXD trust entry.
k8s_lab_capn_identity_namespaces: {type: list(string), default: ["capi-clusters"]}

# ---- cluster networking (dual-stack, §5) ----
# Pod / Service CIDRs for the workload cluster are set dual-stack
# (IPv4 + IPv6 in both cluster ranges, §4/§5). The values are bound
# in charts/capi-cluster-class/values.yaml (spec.clusterNetwork.*) and
# charts/capi-workload-cluster/values.yaml — both sides must
# agree, otherwise kubeadm and the CAPI topology disagree.
# IPv4 ranges — ULA-style standard (k3s defaults-compatible);
# IPv6 — ULA from the `fd42:77::/48` family, consistent with §8
# k8s_lab_internal_ipv6_subnet naming.
k8s_lab_workload_pod_cidr_v4:     {type: string, default: "10.244.0.0/16"}
k8s_lab_workload_pod_cidr_v6:     {type: string, default: "fd42:77:2::/56"}
k8s_lab_workload_service_cidr_v4: {type: string, default: "10.96.0.0/16"}
k8s_lab_workload_service_cidr_v6: {type: string, default: "fd42:77:3::/112"}

# ---- helm charts (local, of this repo) ----
# Local chart versions are pinned; bumping the version = a new
# ClusterClass/*Template name via the name-versioning pattern (§2.9).
k8s_lab_capi_cluster_class_chart_version:    {type: string, default: "0.5.0"}
k8s_lab_capi_workload_cluster_chart_version: {type: string, default: "0.5.0"}
```

## 8a. Verified version log

Per §2.11, every external dependency pin is recorded with its upstream
verification date. The table is compiled from inline comments in §8;
if an inline date diverges from the table — the inline source is the truth, and
the table needs to be regenerated at the next review.

| Component | Version | Where used | Verification date |
| --- | --- | --- | --- |
| Kubernetes (workload/mgmt) | `v1.35.0` | `k8s_lab_kubernetes_version` | 2026-04-25 |
| k3s (bootstrap) | `v1.35.3+k3s1` | `k8s_lab_k3s_version` | 2026-04-21 |
| kubectl | `v1.35.3` | `k8s_lab_kubectl_version` | 2026-04-21 |
| Cluster API (clusterctl) | `v1.12.5` | `k8s_lab_clusterctl_version` | 2026-04-21 |
| CAPN | `v0.8.5` | `k8s_lab_capn_provider_version` | 2026-04-21 |
| LXD snap channel | `6/stable` | `lxd_host_snap_channel` | 2026-04-21 |
| Calico (tigera-operator) chart | `v3.31.5` | `k8s_lab_calico_chart_version` | 2026-04-21 |
| MetalLB chart | `0.15.3` | `k8s_lab_metallb_chart_version` | 2026-04-27 |
| Terraform helm provider | `3.1.1` | `k8s_lab_helm_provider_version` | 2026-04-21 |
| ansible.posix collection | `>=2.1.0` | `ansible/requirements.yml` | 2026-04-21 |
| community.general collection | `>=12.6.0` | `ansible/requirements.yml` | 2026-04-21 |
| community.crypto collection | `>=3.2.0` | `ansible/requirements.yml` | 2026-04-21 |
| kubernetes.core collection | `>=6.0.0` (resolved 6.4.0) | `ansible/requirements.yml` | 2026-04-23 |
| python3-kubernetes (Debian Trixie) | `30.1.0-2` | `tests/molecule/shared/tasks/prepare.yml` | 2026-04-23 |

Deviation (recorded in Step 1, current as of 2026-04-22):
Canonical recommends LXD LTS `5.21/stable` for production; we
read §2.11 "latest stable" literally and use feature-stable
track `6/stable`. Trade-off: regression risk is higher, CAPN has not declared
explicit compatibility with LXD 6.x. If at Gate B or earlier an
incompatibility surfaces, we downgrade to `5.21/stable` and record this in
the plan change log.

Constraint (recorded Step 11, 2026-04-25): `k8s_lab_kubernetes_version`
is bounded by the set of prebuilt `capi:kubeadm/<ver>` images published
on the upstream CAPN simplestreams (`https://images.linuxcontainers.org/capn/`).
The server mints images only for selected releases (typically `<minor>.0`
plus rare patches) — trying to set `kubernetes.version` for which
no image exists hits the CAPN runtime error
`Failed getting image: The requested image couldn't be found for
fingerprint "kubeadm/<ver>"` already at the creation of the first
LXCMachine. As of 2026-04-25 simplestreams returns
`kubeadm/v1.33.0`, `kubeadm/v1.33.5`, `kubeadm/v1.34.0`,
`kubeadm/v1.35.0` (and their `/ubuntu` variants). `v1.35.0` — the latest
relevant for our pin; upstream `dl.k8s.io/release/stable.txt`
shows newer (`v1.35.4`/`v1.36.0`), but for this repo they
are irrelevant until CAPN publishes a matching image. The pin
is updated only after a fresh check of `streams/v1/images.json`.

---

# 9. Local development and testing

## 9.1. Basic local loop

The runner is the developer's local Linux machine.

Locally **a single Debian 13 VM via Vagrant + libvirt** is brought up to mimic the target Debian host. Vagrant-libvirt is a Vagrant plugin that adds a Libvirt provider and supports the normal `up`, `destroy`, `provision`, `ssh`, `reload` lifecycle. ([vagrant-libvirt.github.io][22])

Molecule is used in **delegated mode**: the developer implements `create`/`destroy`, while Molecule is responsible for `prepare/converge/idempotence/verify`. Delegated is the default driver in Molecule and explicitly expects developer-supplied create/destroy logic. ([ansible.readthedocs.io][14])

For the current repo this is the **main and mandatory verification method**. Verification of real environments and wiring of consumer configuration is not part of it.
`tests/fixtures/*` remain a thin wrapper layer and must not contain alternative implementation logic.
A local pass does not replace consumer-side validation on the real external segment.

The operational style of the local harness is also fixed in advance:

* the repo-level `tests/molecule/Makefile` must provide unified targets of the form `<scenario>-<driver>-<action>`;
* even if a scenario has only one driver for now, the driver name stays in the target name for a stable invocation scheme;
* explicit wiring of environment quirks for `molecule + vagrant-libvirt` is allowed and expected, rather than relying on "magic" autodiscovery.

## 9.2. How to model the second interface and IPv6 /64

> **Step 9 (2026-04-24) pivot.** The section below describes the original
> Step 1 design via the libvirt `ext6-mock` network. It **did not work**:
> libvirt did not enable RA in dnsmasq, `tcpdump` on `br-ext6` saw 0 packets.
> The current architecture is an in-VM RA source via the veth pair
> `ext6-ra` ↔ `ext6-ra-peer` + radvd; the libvirt side is simplified to
> a single NIC `k8slab-mgmt-nat`. Details and rationale are in the section
> "Step 9 pivot: RA source moved inside the VM" below. The original
> §9.2 text is left as historical reference of Step 1 attempts.

This is now a mandatory requirement.

### Local libvirt scheme

You need to create **two libvirt networks**:

1. **`mgmt-nat`** — a regular management/SSH network to the test VM.
2. **`ext6-mock`** — a separate IPv6 network that emulates the "provider's external segment".

`ext6-mock` must be defined via libvirt network XML so that it:

* is a separate L2 segment for the test VM's second interface;
* brings up an IPv6 `/64`;
* hands out IPv6 via embedded DHCPv6/RA;
* if possible, does not mix with the management NAT network.

Libvirt network XML officially supports:

* IPv6 addressing on virtual networks,
* DHCPv6 ranges,
* Router Advertisement for IPv6 default route,
* isolated and NAT networks,
* bridge mode using an existing host bridge. It also documents that for IPv6 the default route is established via Router Advertisement. ([Libvirt][23])

### Practical local design

For `ext6-mock` in the local lab I recommend:

* **isolated IPv6 network** or **NAT network with IPv6 enabled**, but without dependence on a real external provider;
* address, for example:

  * `2001:db8:42:100::1/64`
* DHCPv6 range within this /64.

Example XML idea:

```xml
<network ipv6='yes'>
  <name>ext6-mock</name>
  <bridge name='virbr-ext6'/>
  <ip family='ipv6' address='2001:db8:42:100::1' prefix='64'>
    <dhcp>
      <range start='2001:db8:42:100::100' end='2001:db8:42:100::1ff'/>
    </dhcp>
  </ip>
</network>
```

This gives you a **mocked RA/DHCPv6 /64** that will be seen by the second NIC of the Debian test VM. Then **inside the VM itself** the `lxd_host` role will create the host-side bridge `br-ext6` and bind this second NIC to it as required by the consumer environment. ([Libvirt][23])

### Deviations recorded in Step 1

* **Actual libvirt network names used:** `k8slab-mgmt-nat`
  and (in Step 1) `k8slab-ext6-mock` / `k8slab-probe-ext6` (the prefix
  `k8slab-` is to avoid clashes with user networks in the
  default libvirt namespace). The names `ext6-mock` / `mgmt-nat` above
  are logical labels in the plan text.
* **Host bridge names of libvirt networks ≤15 chars (Linux IFNAMSIZ).**
  The original `virbr-k8slab-mgmt` (17 chars) and `virbr-k8slab-ext6`
  (17 chars) fail with "error creating bridge interface: Numerical
  result out of range". We use `k8slab-mgmt`, `k8slab-ext6`,
  `k8slab-probe` (all ≤12). XML comments explain the limitation
  for future edits.
* **`ext6-mock` XML — dual-stack isolated** (not pure IPv6).
  The vagrant-libvirt `private_network` plugin fails on pure
  IPv6 networks (`undefined method 'to_range' for nil`, the plugin tries
  to compute the DHCPv4 range). Workaround: a minimal
  RFC 5737 TEST-NET-1 `192.0.2.0/30` is added to the XML — it carries no
  traffic, only needed
  to let the plugin reach the end of `private_network` validation.
  External ingress and the MetalLB VIP still stay IPv6-only
  (an allocation policy, not a limit of the L2 segment). The network is
  **isolated** (no `<forward/>`), so RA/NDP/multiple-MAC signals
  do not mix with the IPv4 traffic of the mgmt network.
* **IPv6-only NIC in the Vagrantfile — `type: "dhcp"`**. The vagrant-libvirt
  plugin tries to auto-configure the guest NIC and crashes
  on networks without IPv4 config. `type: "dhcp"` on `private_network` is
  a documented plugin flag that says "the IP comes via DHCP, do not
  compute it yourself".

### Step 9 pivot: RA source moved inside the VM (2026-04-24)

**Problem.** Libvirt-mock `k8slab-ext6-mock` was serving DHCPv6 via
dnsmasq, but **was not sending Router Advertisements**: libvirt does not
auto-add `--enable-ra` to dnsmasq (unlike LXD-managed
networks like `capi-int`, where `dnsmasq --enable-ra --dhcp-range
::,constructor:...,ra-stateless` starts automatically). Ad hoc check at Step 9:
`rdisc6 -1 -w 3000 eth2` on the Vagrant VM — no
response; `tcpdump -i br-ext6 'icmp6 && (ip6[40] >= 133 && ip6[40] <= 136)'`
for 15 sec — 0 packets. Therefore the architectural contract §13.6
(container eth1 gets a global IPv6 by SLAAC via RA from
the external segment) **could never have passed end-to-end** against
libvirt-mock — the guest's `IPv6AcceptRA=yes` was there, but there was nothing
to receive.

**Solution.** The RA source moved **inside the Vagrant VM**. A new
harness task `tests/molecule/shared/tasks/ext6-ra-source.yml`
(included via `tests/molecule/shared/tasks/prepare.yml` →
applied in each scenario's prepare) creates:

* a veth pair `ext6-ra` ↔ `ext6-ra-peer` via systemd-networkd
  `.netdev` with `Kind=veth` + `[Peer]` block;
* `ext6-ra` is enslaved into `br-ext6` by the same
  `30-br-ext6-uplink.network` from the production role `lxd_host` (in
  shared host_vars `lxd_host_ext_bridge_uplink: ext6-ra` is pinned);
* `ext6-ra-peer` gets a global IPv6 `2001:db8:42:100::1/64`;
* `radvd` listens on `ext6-ra-peer` and sends RA for
  `2001:db8:42:100::/64` (`AdvSendAdvert on`, `AdvAutonomous on`,
  `AdvOnLink on`).

The RA multicast sent by radvd on `ext6-ra-peer` goes through
the veth into `ext6-ra`, is flooded by the bridge `br-ext6` to all ports,
including `eth1` of any container attached via the
`capi-worker` / `capi-controlplane` profiles with `nictype=bridged
parent=br-ext6`. Inside the container `KubeadmConfigSpec.files`
(charts/capi-cluster-class, §16.2 / §16.3) has already laid out
`/etc/systemd/network/30-capi-ext.network` with `IPv6AcceptRA=yes` →
systemd-networkd SLAACs a global IPv6 in the prefix.

**What was removed from the Vagrant/libvirt scheme:**

* `tests/vagrant/debian13/libvirt-networks/ext6-mock.xml` (was not sending
  RA, was a workaround for a problem that was never solved);
* the second `private_network` block in the Vagrantfile (was eth2, dragged
  a dormant interface without carrier into the VM);
* `k8slab-ext6-mock` in `Makefile NETS` and in `network_xmls` in the
  Vagrantfile;
* `synced_folder "/vagrant"` was set to `disabled: true` — NFS export
  required interactive sudo on the host and broke `make up`. No
  scripts in the VM read `/vagrant` anyway (Ansible drives via
  SSH).

The `k8slab-probe-ext6` libvirt network and the probe VM (`K8SLAB_PROBE=1`
gated) are left dormant — they will require a separate redesign for
working with the in-VM RA architecture, scope outside Step 9.

**End-to-end proof (Step 9 manual test):** two
containers `capi-test-worker-0` + `capi-test-cp-0` were spun up from
`images:debian/13/cloud` with profiles `capi-base + capi-worker` and
`capi-base + capi-controlplane` respectively. After cloud-init
`status: done`:

* `/etc/sysctl.d/99-capi-ra.conf` — byte-match with the rendered
  template;
* `/etc/systemd/network/30-capi-ext.network` — byte-match;
* `ip -6 -br addr show dev eth1` — global IPv6 in
  `2001:db8:42:100::/64` (EUI-64 from the container's MAC);
* `ip -6 route show default` — default route
  `via fe80::<ext6-ra-peer LLA> dev eth1 proto ra`.

Runtime `net.ipv6.conf.eth1.accept_ra = 0` — expected behaviour of
systemd-networkd (with `IPv6AcceptRA=yes` it processes RAs in
user space via Nettle, the kernel sysctl stays 0 to avoid
duplication); a global IPv6 on the interface is direct proof
that RAs are accepted, just via another codepath.

**Side effect (not Step 9 scope):** the default route is currently
duplicated — both on eth1 (our harness radvd) and on eth0
(LXD-managed `capi-int` dnsmasq with `ra-stateless` also sends
`default via me`). Production §5.3 Guest-side route policy
requires egress **only via eth1**. A separate debt for a future
iteration (probably `lxd_network_int_managed` — disable
the default-advert on the internal-bridge dnsmasq).

## 9.3. How to verify external ingress locally

For a full e2e test you also need a **probe endpoint** on the same
external L2 segment (after the Step 9 pivot — that is the bridge `br-ext6` inside
the Vagrant VM, not a libvirt network):

* either a separate probe VM, attached to `br-ext6` via a host veth
  (analogue of `k8slab-probe-ext6` in the Step 1 design — would require
  redesign for the new architecture);
* or a separate netns inside the Vagrant VM, attached to `br-ext6`
  via a second veth pair;
* or `ext6-ra-peer` itself (the Step 9 harness RA source) — it already
  has a global IPv6 in the prefix and sees the bridge, the minimal
  setup for a dev-scope probe.

It will play the role of the "external client" for verifying:

* external IPv6 reachability of nodes;
* NodePort;
* MetalLB VIP;
* NDP/failover.

## 9.4. What must be tested in Molecule

### Role-level

The minimum mandatory separate scenarios:

* `base_system`
* `binary_fetch`
* `lxd_host`
* `lxd_project`
* `lxd_storage_pools`
* `lxd_network_int_managed`
* `lxd_profiles`
* `lxd_bootstrap_instance`
* `bootstrap_k3s`
* `bootstrap_clusterctl` — Step 6 §13.10. The scenario run brings
  the whole Phase 0..3.5 chain up via meta-deps + bootstrap_k3s itself, then
  applies bootstrap_clusterctl converge → idempotence → verify.
  Verify asserts the host kubeconfig (mode 0600, server URL rewritten from
  127.0.0.1 to capi-int IP), kubectl Ready node via the kubeconfig, 7
  Deployments (cert-manager + 4 CAPI/CAPN) Available, 4 ProviderCR
  pairs via `kubernetes.core.k8s_info`, ClusterTopology=true in
  capi-controller-manager args.
* `bootstrap_capn_secret` — Step 6 §13.11. The scenario run brings
  the Phase 0..4-partial chain up via meta-deps (including
  bootstrap_clusterctl), then applies the role and verifies: LXD
  `core.https_address` bound on the capi-int subnet, exactly one client
  cert in the trust store with restricted=true + projects=[capi-lab], a Secret
  with 5 correct data keys (server URL = `https://10.77.x.x:8443`,
  project=capi-lab, correct PEM bodies), `server-crt` byte-equal
  to live `/var/snap/lxd/common/lxd/server.crt`, presence of the pivot
  move-label `clusterctl.cluster.x-k8s.io/move=true` (default —
  pivot is mandatory, §3 + §10).
* `export_artifacts` — Step 8 §13.12. The run brings up the whole Phase 4
  chain via meta-deps (including bootstrap_capn_secret), then
  applies the role and verifies on the runner side:
  `.artifacts/mgmt.kubeconfig` + `.artifacts/mgmt.auto.tfvars.json`
  present with mode 0600, kubeconfig server is not 127.0.0.1, tfvars
  contains baseline `k8s_lab_*` keys, the API server URL in tfvars
  matches cluster[].server in the shipped kubeconfig,
  `kubernetes.core.k8s_info kind=Node` via the shipped kubeconfig
  sees a Ready node (Phase 5 smoke test).

### Integration-level

End-to-end Phase 0..5 coverage lives in `tests/molecule/e2e-local/`
(§9.4 Full E2E below + §14.7) — separate integration-only scenarios
(in past plan revisions listed as `bootstrap_cluster` and
`cluster_addons_helm`) **are not shipped** and not planned: their acceptance
is fully subsumed by the `e2e-local` run (Phase 0..4 substrate +
Phase 5 workload_cluster module + chart-side helm tests Gate A/B +
runner-side workload Nodes Ready via the rewritten kubeconfig).

`workload_cluster` acceptance (TF module §16.4 + Molecule e2e-local) —
in addition to checking the fact that Helm releases are installed, is responsible for running
**chart-side helm test hooks** (§6, §17.1 invocation contract),
implementing Gate A (§17.3, external L2) and Gate B (§17.2, CNI
viability). It also asserts the **§2.12 HA pair contract** for every
workload-cluster component with `replicas >= 2`:

* `kubectl get deploy <X> -o jsonpath='{.status.readyReplicas}'`
  and `availableReplicas` equal `.status.replicas`
  (condition=Available is not enough — see §2.12 Test contract);
* `kubectl get pods -l <selector> -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l`
  == 2 (replicas on different worker nodes);
* for leader-elected components — exactly one lease holder,
  the second pod in standby (the verification mechanism depends on the component type:
  logs, lease object, leader-election config map — see §2.12).

Pivot acceptance is exercised inside the same `e2e-local` Molecule
scenario as a mandatory step in the canonical sequence (§3 + §10) —
no standalone Make-target / playbook orchestrates pivot separately.
The `pivot_clusterctl_move` role's own healthchecks
(`tasks/healthchecks.yml`) ARE the acceptance: 4 CAPI/CAPN provider
Deployments Available on target, 4 Provider CRs present, target
Cluster CR on target, bootstrap source flushed (zero Cluster CRs in
target namespace on bootstrap). The e2e-local converge.yml chains
`pivot_clusterctl_move` → second `export_artifacts` (re-emit) →
`cleanup_bootstrap` so post-pivot end-state is closed in one play.

### Full E2E

* `e2e_local` runs the canonical sequence from §3.1 in full in a single
  Molecule playbook — substrate → mgmt-1 helm install → mgmt-1 Gate
  A/B helm tests → pivot → re-emit `mgmt.kubeconfig` →
  cleanup_bootstrap → workload helm install → workload Gate A/B
  helm tests + external curl. No dispatch branches on
  `pivot_enabled` or similar; pivot is a mandatory stage.
  converge.yml includes the `export_artifacts` role (Phase 0..4
  marker), then `kubernetes.core.helm` × N for the mgmt-1 charts,
  then three `helm test` shell-fallbacks (no native equivalent
  in `kubernetes.core`), then `pivot_clusterctl_move` →
  `export_artifacts` (re-emit with `run_meta_chain: false`) →
  `cleanup_bootstrap`, then `kubernetes.core.helm` × N for the
  workload charts. verify.yml — three `helm test` of the workload
  charts + an external curl to the MetalLB VIP from the VM (via
  `ext6-ra-peer`) + workload Nodes Ready=True via the rewritten
  kubeconfig + a CAPI snapshot of the self-hosted mgmt-1.

### Molecule harness style contract

For this repo the Molecule/Vagrant/libvirt harness must follow the practical style of `naive_proxy`, adapted to a multi-role repo:

* the common wrapper `Makefile` in `tests/molecule/` must provide targets in the form `<scenario>-<driver>-<action>`;
* the harness **is never invoked directly** (`vagrant`, `virsh`,
  `molecule`, `ansible-playbook`) — only via the Makefile entry
  points (§10). Exception: read-only diagnostics (`vagrant status`,
  `virsh net-list`). Justification in memory
  `feedback_makefile_only.md`.
* shared `converge.yml`, `verify.yml` helpers and tasks are factored into
  `tests/molecule/shared/`, so role-level and integration-level
  scenarios do not duplicate boilerplate;
* **substrate host_vars live in a single shared group_vars file**
  (`tests/molecule/shared/inventory/group_vars/k8slab_host.yml`) and
  are propagated via `inventory.links.group_vars` in every
  `molecule.yml` — the full architecture and rationale are in §9.5;
* scenario-local overrides live in a real inventory file
  `<scenario>/host_vars/k8slab-host.yml` + `inventory.links.host_vars:
  host_vars` in `molecule.yml` (see §9.5.2 — `inventory.host_vars` in
  `molecule.yml` is silently dropped when `links` is set);
* **the target role for shared converge** is determined from
  `MOLECULE_SCENARIO_NAME` env var, **not** from the `_shared_target_role`
  host_vars (follows from the molecule limitation above);
  contract: `scenario.name == role directory name`;
* for `vagrant-libvirt` you must explicitly pass through `ANSIBLE_LIBRARY` from `molecule_plugins.vagrant` or an equivalent plugin modules path, if the Molecule version does not do it itself;
* `GIT_DIR=/dev/null` or an equivalent shim is allowed if it is needed to keep Molecule from getting confused about role/collection mode due to the layout of this repo;
* workarounds for driver-specific caveats must be recorded in the harness code, not left in the developer's head: example — safe editing of `/etc/hosts` on non-podman targets via `lineinfile`, when atomic rename can clash with bind-mount semantics;
* `prepare` must use native modules to install test dependencies and load test artifacts;
* `verify` must check real runtime outcomes: readiness, rendered configs, file ownership/mode, systemd state, network data path, retries/until for asynchronous states;
* a scenario is considered insufficient if it checks only `converge + idempotence` but does not check useful role behaviour;
* `command`/`shell` in `verify` is allowed only as an explicitly documented exception when a specific runtime path needs to be checked without an adequate module equivalent.

Order (canonical flow §3, all inline in the e2e-local Molecule
playbook — no standalone Make targets between stages):

1. `vagrant up`
2. base substrate + bootstrap k3s (Phase 0..4 via
   `include_role: export_artifacts` + meta-chain)
3. mgmt-1 helm install on bootstrap (`capi-cluster-class` +
   `capi-workload-cluster` via `kubernetes.core.helm` with
   mgmt-topology values, §18.1)
4. CNI Calico → poll mgmt-1 Nodes Ready (Calico operator async
   reconcile gate — without it the next MetalLB install's Pods stay Pending
   on NotReady Nodes) → MetalLB on mgmt-1
5. helm tests on mgmt-1 (`capi-workload-cluster` cluster-ready +
   `cni-calico` Gate B + `metallb-config` Gate A) — the gate before
   pivot. All three shell-fallback `command: helm test` tasks
   run with `become: false` (delegate_to: localhost against
   the play-level `become: true` on the VM, without the override sudo runs on the
   runner — the runner user is not sudo-able without a password)
6. pivot — `include_role: pivot_clusterctl_move` (§18.2)
7. re-emit `.artifacts/mgmt.kubeconfig` to mgmt-1 creds —
   `include_role: export_artifacts` with `run_meta_chain: false`
   (§13.12)
8. `include_role: cleanup_bootstrap` — bootstrap LXC removed
9. workload helm install on the self-hosted mgmt-1
   (`capi-cluster-class` + `capi-workload-cluster` with
   workload-topology values)
10. CNI Calico → poll workload Nodes Ready (the same Calico-async
    gate as in step 4) → MetalLB on the workload
11. verify.yml — helm tests on the workload + Gate A external curl +
    Nodes Ready=True + a CAPI snapshot of the self-hosted mgmt-1
12. destroy

## 9.5. Shared inventory architecture

**Status: done in Step 8 (2026-04-23).** Before Step 8 every
`tests/molecule/<scenario>/molecule.yml` duplicated substrate
host_vars (uplink, storage pool spec, wait budgets, LXD proxy device,
ansible-connection env-lookups, etc.), and a scenario could silently
drift from the others. The Step 8 incident (`export-artifacts`
forgot `lxd_bootstrap_instance_devices`, the role reconciled the proxy
device to `{}` on converge) exposed the swarm of this problem. Production
playbooks do not work like that — there is one host_vars file and all roles read
the same values; the harness must mimic this.

### §9.5.1. Layout

```
tests/molecule/shared/inventory/
└── group_vars/
    └── k8slab_host.yml    ← all prod-like substrate (a single file)

tests/molecule/<scenario>/
├── molecule.yml           ← only inventory.links + scenario meta
└── host_vars/             ← optional, only if a scenario-local override is needed
    └── k8slab-host.yml
```

`shared/inventory/group_vars/k8slab_host.yml` holds:

* ansible-connection env-lookups (`ansible_host/user/port/key/common_args`);
* `k8s_lab_*` globals (the former `shared/vars/common.yml` — eliminated);
* `lxd_host_ext_bridge_uplink: "eth2"`;
* `lxd_storage_pools_pools` (capi-fast btrfs on the Vagrant disk);
* `lxd_bootstrap_instance_wait_timeout`;
* `lxd_bootstrap_instance_devices.k3s-api` (LXD proxy
  `bind: host, listen: tcp:0.0.0.0:16443, connect: tcp:127.0.0.1:6443`) —
  **the only place where the proxy device lives**; runner-side reach
  works for every scenario that gets to `capi-bootstrap-0`;
* `bootstrap_k3s_wait_retries` / `wait_delay`;
* `bootstrap_clusterctl_init_timeout` / `wait_retries` / `wait_delay`;
* `base_system_btrfs_pool_required: true` (prod-like default —
  installer provisions btrfs mount);
* `export_artifacts_root` + `export_artifacts_mgmt_api_server_url`
  (runner-path + publish URL — derivatives of scenario env vars).

### §9.5.2. Scenario wiring

`<scenario>/molecule.yml` carries canonically only:

```yaml
provisioner:
  inventory:
    links:
      group_vars: ../shared/inventory/group_vars
      host_vars:  host_vars         # only if scenario-local file exists
```

The target role is determined in `shared/converge.yml` from
the `MOLECULE_SCENARIO_NAME` env var (Molecule sets it before
`ansible-playbook`). Contract: `scenario.name` in molecule.yml
matches the role directory name under `ansible/roles/`. Anything that
the scenario adds is a true scenario-local override, living in a
real file `<scenario>/host_vars/k8slab-host.yml`.

**Why not `provisioner.inventory.host_vars` in molecule.yml.**
Molecule's `provisioner/ansible.py:442` decides all-or-nothing: if
`inventory.links` is non-empty, `_add_or_update_vars` (which
materialises `inventory.host_vars`) is skipped, and the content is silently
lost. Therefore scenario-local overrides need to go through a real inventory
file + a separate `links.host_vars`.

### §9.5.3. Scenario-local overrides in the repo

As of Step 8 (2026-04-23) the actual overrides in use are:

| Scenario | Override | Rationale |
|---|---|---|
| `binary-fetch` | `base_system_btrfs_pool_required: false` | The target role does not test the btrfs contract; prepare does not format the pool disk |
| `lxd-storage-pools` | `base_system_btrfs_pool_required: false` | prepare-clean-disk.yml wipes the pool → LXD owns the disk; the base_system btrfs check is not applicable |
| `lxd-network-int-managed` | same | LXD already owns the disk from previous runs |
| `lxd-profiles` | same | |
| `lxd-bootstrap-instance` | same | |
| `bootstrap-k3s` | same | |
| `bootstrap-clusterctl` | same | |
| `bootstrap-capn-secret` | same | |
| `export-artifacts` | same | |

The `base-system` scenario is the only one that tests the contract end-to-end with
`required: true` (it inherits from the shared default without an override).

### §9.5.4. Acceptance

* the shared group_vars file is **one**; changing a substrate key =
  editing exactly one place;
* every scenario's `molecule.yml` does not exceed ~65 lines
  (scenario-local config only — driver, platforms, provisioner
  links, scenario name);
* end-to-end regression at Step 8 (2026-04-23, pristine VM):
  all 12 ready scenarios passed full-cycle in sequence
  (create → prepare → converge → idempotence → verify → destroy).

---

# 10. One-command local workflows

This repo **must not have** `make deploy TARGET=...` or other entry points for real environments. Those are provided by private consumer repos.

## 10.1. Local harness smoke

```bash
make test-local-harness
```

Should:

1. bring up / verify the Vagrant + libvirt test VM;
2. prepare the Molecule delegated prerequisites;
3. verify that the Vagrant inventory/scripts/fixtures are ready for local scenarios.

## 10.2. Local full E2E

```bash
make test-local-e2e
```

Runs the Molecule scenario `tests/molecule/e2e-local/` which
runs the canonical sequence from §3.1 in full in a single playbook:

1. `vagrant up --provider=libvirt` (if the VM is not yet there);
2. Molecule create / prepare;
3. converge.yml — substrate (Phase 0..4) → mgmt-1 helm install on
   bootstrap → CNI Calico → poll mgmt-1 Nodes Ready (Calico
   async reconcile gate) → MetalLB → mgmt-1 Gate A/B helm tests
   (the gate before pivot) → `clusterctl init + move` via the role
   `pivot_clusterctl_move` → re-emit `.artifacts/mgmt.kubeconfig`
   (a second include of `export_artifacts` with `run_meta_chain: false`)
   → `cleanup_bootstrap` → workload helm install on mgmt-1 → CNI
   Calico → poll workload Nodes Ready → MetalLB;
4. verify.yml — workload Gate A/B helm tests + external curl to
   the MetalLB VIP via `ext6-ra-peer` + workload Nodes Ready=True
   via the runner-side kubeconfig + a CAPI snapshot of the self-hosted mgmt-1.

An additional workload (a second, third…) on an already-self-hosted mgmt-1
is brought up by a separate `make deploy-workload` (the TF route, §16.6) —
this target accepts `.artifacts/mgmt.kubeconfig` (= self-hosted
mgmt-1 after the e2e-local run) and `.artifacts/mgmt.auto.tfvars.json`
as input; a single `terraform apply` on the §16.5 fixture brings up
another workload Cluster + CNI + MetalLB + chart-side helm tests.

## 10.3. Local cleanup

```bash
make clean-local
```

Should perform the local destroy contract described above:

* tear down test fixtures;
* remove temporary `.artifacts`;
* destroy the Vagrant/libvirt resources created by the harness.

---

# 11. Secrets, artifacts and state

## 11.1. `.artifacts/`

Contains:

* `mgmt.kubeconfig` — the only admin kubeconfig for the active
  management cluster. The same file lives through the entire canonical
  sequence (§3.1): first it points to bootstrap k3s (after Phase
  4 substrate including `export_artifacts`), then it is overwritten
  in place by a second include of `export_artifacts` (with
  `run_meta_chain: false` + a source override on host-side staging
  from pivot) to mgmt-1 creds. After `cleanup_bootstrap` the bootstrap
  endpoint is removed together with the container, and the file
  contains only valid mgmt-1 credentials. All runner-side consumers
  (TF workload fixtures, Molecule e2e-local verify) keep one path
  through the entire lifecycle;
* `mgmt.auto.tfvars.json` — the Phase 5 Terraform handoff bundle
  (TF-native `*.auto.tfvars.json` auto-load), parametrising every
  fixture root from §8 globals;
* `clusters/<cluster>.kubeconfig` — per-workload debug copies of the
  rewritten kubeconfigs, written by Molecule e2e-local verify.yml
  for operator inspection (the §16.4 TF module does not write to this subdir;
  it keeps the kubeconfig only in state and emits it via `terraform
  output -raw kubeconfig`).

Rules:

* `.gitignore`
* file mode `0600`
* owner = runner user

## 11.2. LXD trust material

In this repo:

* only ephemeral/synthetic materials for the local harness are allowed;
* plaintext cert/key for real environments are not committed;
* real trust materials and vault data must live in private consumer repos.

For MVP local tests:

* it is allowed to keep encrypted test material in `ansible-vault`, if without it the harness cannot be reproduced;
* preferably generate trust material on the fly.

## 11.3. Terraform state

For the MVP of the current repo:

* local state on the runner only for test fixtures;
* state is not considered the source of truth for real environments.

The backend strategy for real environments is determined by consumer repos and is not part of this repo.

## 11.4. Bootstrap API auth

The protection of the bootstrap Kubernetes API rests on two layers, both of which are
WITHIN SCOPE of this repo:

* **Kubernetes API mTLS / kubeconfig** — the k3s API server always
  requires a client certificate. `.artifacts/mgmt.kubeconfig`
  carries the admin cert, accessible only to the runner (mode 0600, gitignore).
* **LXD API auth** — separately, via a restricted TLS secret
  (`capi-lab` project-scoped client cert). Implemented by
  `bootstrap_capn_secret` (§15.4); confirmed by the CAPN identity-secret
  format. ([capn.linuxcontainers.org][19])

**Host firewall — OUT OF scope of this repo.** Reasons:

* in production, the host firewall is the operator's property (already configured
  per corporate policy); the role is not allowed to write there to
  avoid overriding the environment's rules and leaving holes at
  destroy phase.
* Any external publication of TCP ports of the bootstrap container is done
  via an **LXD proxy device** of type `host` (a userspace listener of the LXD
  daemon on the host → socket inside the instance). LXD owns this
  mechanism completely: created via the declarative
  `lxd_bootstrap_instance_devices` (§13.7 `lxd_bootstrap_instance`),
  removed on `lxc delete`, leaves no dangling rules in
  distro-owned nftables tables.
* A source-IP ACL on the host firewall, if the operator needs one, is
  the job of external consumer-repo roles (vendor-specific firewall
  management), not Stage 1 substrate.
* Kubernetes API mTLS + the LXD restricted TLS secret are sufficient
  protection without a source-IP filter: the kubeconfig is enforced to 0600 and
  not committed; the LXD identity secret is scoped to the project `capi-lab`,
  so even a compromised client cannot reach foreign
  instances.

---

# 12. Risks and mitigation

## 12.1. External L2 may fail

Mitigation:

* the Gate A external L2 helm test hook (§6 → §17.3) fails
  `terraform apply` via a `null_resource` before MetalLB
  pretends to serve VIPs on a broken L2 segment; CAPN workers
  are still already created but the cluster data plane is not released
  to a production-like state until the test passes.

## 12.2. Unprivileged LXC node path may fail on userns/runtime/CNI edges

Mitigation:

* pin CAPN-tested unprivileged kubeadm image path (`v1.32.4+`)
* the Gate B CNI helm test hook (§6 → §17.2) on the first Terraform-
  created cluster after the CNI release fails `terraform apply` if
  CNI bring-up breaks
* keep unprivileged substrate fixed and vary CNI inside that constraint
* shipped CNI = Calico (`charts/cni-calico/`). Swap to another
  implementation on Gate B failure — a separate design step (a new
  wrapper chart + edit of the corresponding chart-version input in
  the §16.4 module), not a runtime toggle. The §16.4 module contains no
  branch logic for CNI choice — extensibility via replacing the
  `cni_calico_*` input family with new inputs in the module
  signature
* never switch to privileged LXC as a silent fallback

## 12.3. Default route may land on external NIC

Mitigation:

* systemd-networkd
* `UseGateway=no`
* route validation in verify

## 12.4. kubelet may pick wrong node IP

Mitigation:

* explicit `--node-ip`
* validate `kubectl get nodes -o wide`

## 12.5. Snap auto-refresh may destabilize LXD

Mitigation:

* snap channel pin
* hold or maintenance window

## 12.6. Helm-release storage does not move with `clusterctl move`

`clusterctl move` follows only the object reference graph of CAPI CRs;
helm-release secrets (`sh.helm.release.v1.<release>.v1`) are stored as
regular Kubernetes Secrets and do not move. If a workload Cluster CR
is created on bootstrap, its helm storage stays on bootstrap and
flies away with `cleanup_bootstrap` — leaving an orphaned CR on the target mgmt
without an owning helm release; `terraform destroy` / `helm uninstall`
on it after that fails with `release not found`.

Mitigation:

* the canonical sequence (§3.1) NEVER creates workload Cluster CRs
  on bootstrap — the only CAPI CR on bootstrap is
  mgmt-1 itself (transient, removed together with bootstrap after pivot
  via cleanup_bootstrap; the helm release storage on the same
  trajectory does not stay orphaned because the Cluster CR
  left with the move chain);
* workloads are created ONLY after pivot on the already-self-hosted
  mgmt-1, where helm storage and the Cluster CR coincide in local-cluster
  ownership.

## 12.7. CAPN + Canonical LXD drift risk

Mitigation:

* pin versions
* maintain compatibility matrix
* do not auto-upgrade substrate casually

## 12.8. Secrets leakage through artifacts

Mitigation:

* vault
* gitignore
* mode 0600
* no plaintext certs in repo

## 12.9. CAPN pre-built images are evaluation-oriented

Mitigation:

* local harness may use `capi:kubeadm/VERSION` images for reproducibility
* consumer repos should support custom image override and pinning
* install-kubeadm-at-runtime via `preKubeadmCommands` does not become an implicit workaround path — it is allowed only as a deliberate consumer choice, not as the default lab deployment

## 12.10. CAPI CR immutability blocks `helm upgrade` in place

Once a Cluster has referenced a ClusterClass + `*Template`, the admission
webhook forbids editing most of their fields. A silent `helm upgrade` with
changed values fails on `admission webhook denied: field is immutable`
and leaves the release in a broken state.

Mitigation:

* the name-versioning pattern in both charts §16.2 / §16.3:
  `metadata.name = "{prefix}-{slug(Chart.Version)}"`, where
  `slug = Chart.Version | replace "." "-"` for DNS-1123-safe names;
* the Cluster CR builds the rendered ClusterClass name from the same formula
  (`spec.topology.classRef.name: "{prefix}-{class_chart_version_slug}"`),
  both versions come from the Terraform module in one signal;
* bumping the chart version = a new pair of objects with new names; the old ones
  live until a deliberate cleanup; zero in-place edit.

## 12.11. Webhook + CR race on the first apply

A Cluster CR may reach the ClusterClass webhook before the latter is
fully reconciled; the result is `failed calling webhook ... connection
refused` or a transient validation error.

Mitigation:

* `helm_release.wait = true` (default in `hashicorp/helm` 3.x) on every
  release that owns CRs — wait for Ready on every resource in the release
  before returning to the Terraform graph;
* an explicit `depends_on = [helm_release.cluster_class]` on the workload
  release;
* `helm_release.atomic = true` — rollback a broken release so as not to
  leave the cluster in an inconsistent state. `force_update` stays
  `false` (default), otherwise the SSA ownership of the CAPI controllers slips
  (flip-flop reconciliation).

---

[1]: https://capn.linuxcontainers.org/?utm_source=chatgpt.com "Introduction - The cluster-api-provider-incus book"
[2]: https://documentation.ubuntu.com/lxd/latest/reference/network_bridge/?utm_source=chatgpt.com "Bridge network - LXD documentation"
[3]: https://documentation.ubuntu.com/lxd/latest/installing/?utm_source=chatgpt.com "How to install LXD - LXD documentation"
[4]: https://documentation.ubuntu.com/lxd/latest/reference/projects/?utm_source=chatgpt.com "Project configuration - LXD documentation"
[5]: https://documentation.ubuntu.com/microcloud/latest/lxd/howto/projects_confine/?utm_source=chatgpt.com "How to confine users to specific projects - LXD documentation"
[6]: https://docs.k3s.io/?utm_source=chatgpt.com "K3s - Lightweight Kubernetes | K3s"
[7]: https://main.cluster-api.sigs.k8s.io/clusterctl/commands/init.html?utm_source=chatgpt.com "init - The Cluster API Book"
[8]: https://cluster-api.sigs.k8s.io/clusterctl/commands/move?utm_source=chatgpt.com "move - The Cluster API Book"
[9]: https://documentation.ubuntu.com/lxd/latest/reference/devices_nic/?utm_source=chatgpt.com "Type: nic - LXD documentation"
[10]: https://kubernetes.io/docs/concepts/services-networking/dual-stack/?utm_source=chatgpt.com "IPv4/IPv6 dual-stack | Kubernetes"
[11]: https://metallb.io/configuration/_advanced_l2_configuration?utm_source=chatgpt.com "Advanced L2 configuration :: MetalLB, bare metal load-balancer for Kubernetes"
[12]: https://documentation.ubuntu.com/lxd/stable-5.0/reference/network_bridge/?utm_source=chatgpt.com "Bridge network - LXD documentation"
[13]: https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/?utm_source=chatgpt.com "kube-proxy | Kubernetes"
[14]: https://ansible.readthedocs.io/projects/molecule/configuration/?utm_source=chatgpt.com "Configuration - Ansible Molecule"
[15]: https://snapcraft.io/docs/how-to-guides/manage-snaps/manage-updates/?utm_source=chatgpt.com "Manage updates - Snap documentation"
[16]: https://capn.linuxcontainers.org/reference/default-simplestreams-server.html?utm_source=chatgpt.com "Default simplestreams server - The cluster-api-provider-incus book"
[17]: https://capn.linuxcontainers.org/reference/profile/kubeadm.html?utm_source=chatgpt.com "Kubeadm profile - The cluster-api-provider-incus book"
[18]: https://docs.k3s.io/cli/server?utm_source=chatgpt.com "server | K3s"
[19]: https://capn.linuxcontainers.org/reference/identity-secret.html?utm_source=chatgpt.com "Identity secret - The cluster-api-provider-incus book"
[20]: https://capn.linuxcontainers.org/reference/templates/default.html?utm_source=chatgpt.com "Default - The cluster-api-provider-incus book"
[21]: https://capn.linuxcontainers.org/reference/api/v1alpha2/api.html?utm_source=chatgpt.com "v1alpha2 API - The cluster-api-provider-incus book"
[22]: https://vagrant-libvirt.github.io/vagrant-libvirt/about/?utm_source=chatgpt.com "About - Vagrant Libvirt Documentation"
[23]: https://libvirt.org/formatnetwork.html?utm_source=chatgpt.com "libvirt: Network XML format"
[24]: https://capn.linuxcontainers.org/explanation/unprivileged-containers.html?utm_source=chatgpt.com "Unprivileged Containers - The cluster-api-provider-incus book"
[25]: https://registry.terraform.io/providers/hashicorp/helm/latest?utm_source=chatgpt.com "hashicorp/helm | Terraform Registry"
[26]: https://docs.tigera.io/calico/latest/getting-started/kubernetes/helm?utm_source=chatgpt.com "Installing with Helm | Calico Documentation"
[27]: https://metallb.io/installation/index.html?utm_source=chatgpt.com "Installation :: MetalLB, bare metal load-balancer for Kubernetes"
[28]: https://main.cluster-api.sigs.k8s.io/tasks/bootstrap/kubeadm-bootstrap/kubelet-config.html?utm_source=chatgpt.com "Kubelet configuration - The Cluster API Book"
[29]: https://main.cluster-api.sigs.k8s.io/tasks/bootstrap/kubeadm-bootstrap/index.html?utm_source=chatgpt.com "Kubeadm based bootstrap - The Cluster API Book"
[30]: https://github.com/kogeler/mini-pig-ansible-collection/tree/main/roles/init "mini-pig-ansible-collection init role"
[31]: https://github.com/kogeler/mini-pig-ansible-collection/tree/main/roles/naive_proxy "mini-pig-ansible-collection naive_proxy role"
[32]: https://github.com/kogeler/mini-pig-ansible-collection/tree/main/roles/naive_proxy/molecule "mini-pig-ansible-collection naive_proxy molecule harness"
[33]: https://github.com/kogeler/mini-pig-ansible-collection/blob/main/roles/naive_proxy/README.md "mini-pig-ansible-collection naive_proxy README"
[34]: https://documentation.ubuntu.com/lxd/default/howto/security_harden/ "How to harden security for LXD"
[35]: https://kubernetes.io/docs/concepts/workloads/pods/user-namespaces/ "User Namespaces | Kubernetes"
[36]: https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/ "Feature Gates | Kubernetes"
[37]: https://kubernetes.io/docs/tasks/administer-cluster/kubelet-in-userns/ "Running Kubernetes Node Components as a Non-root User | Kubernetes"
[38]: https://github.com/flannel-io/flannel "flannel GitHub repository"
[39]: https://flannel-io.github.io/flannel/index.yaml "flannel Helm repository index"
