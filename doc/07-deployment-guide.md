# 07 — Deployment guide (real environments)

This is the practical chapter. It walks an operator from a blank
private "consumer" repository to a fully running k8s-lab on a real
Debian or Ubuntu Linux host: substrate, bootstrap, pivot, and a workload
cluster.

The flow described here is the production form of what
`tests/molecule/e2e-local/converge.yml` exercises locally — the same
roles, the same charts, the same Terraform module. Only the *inputs*
(real IPs, real images, real disks) differ.

> **Before you start**: you should have read
> [`01-overview.md`](01-overview.md) and
> [`02-architecture.md`](02-architecture.md), and you should have a
> Debian or Ubuntu Linux host that satisfies
> [`05-prerequisites.md`](05-prerequisites.md).

---

## Why a consumer repo

This repository carries no environment-specific data on purpose. Per
plan [`§2.5`](../plans/PLAN-stage1-common.md):

- no inventories;
- no host_vars / group_vars with real IPs, FQDNs, or interface names;
- no plaintext secrets, no real LXD trust material;
- no environment-specific Terraform root modules or backends;
- no `make deploy TARGET=prod` orchestration.

All of those live in **separate, private "consumer" repositories**
that import this repo (as a git submodule, a vendored copy, or an
ansible-collection / Terraform-source reference) and supply the
concrete values. This is a deliberate architectural rule, not
missing functionality: the reusable substrate stays free of any
operator's secrets or topology, so a single bug fix can be pulled by
every consumer without leaking environments into each other.

`make test-local-e2e` and the local Vagrant harness in this repo
exist for **regression testing** of the substrate, not for deploying
anywhere real. The rest of this chapter describes what a consumer repo
looks like.

---

## Recommended consumer-repo layout

```
my-k8s-lab-prod/
├── Makefile                       # one-liner deploy/destroy targets (TARGET=prod / staging)
├── inventories/
│   └── prod/
│       ├── hosts.yml
│       └── group_vars/
│           └── k8slab_host.yml    # site values for k8s_lab_*
├── playbooks/
│   ├── deploy.yml                 # phases A..D (substrate → mgmt-1 → pivot → cleanup)
│   └── destroy.yml                # phase 8 destroy
├── terraform/
│   └── workload-clusters/
│       └── prod-default/
│           ├── main.tf            # invokes terraform/modules/workload_cluster from k8s-lab
│           ├── variables.tf
│           ├── providers.tf
│           ├── outputs.tf
│           └── terraform.tfvars   # site overrides; secrets in vault
├── secrets/
│   └── prod/
│       └── vault.yml              # ansible-vault encrypted
├── k8s-lab/                       # this repo (git submodule)
└── README.md
```

What lives where:

| Path | Purpose |
|------|---------|
| `Makefile` | One-liner daily targets: `make deploy TARGET=prod`, `make workload TARGET=prod`, `make destroy TARGET=prod`. Wraps `ansible-playbook` and `terraform apply`. |
| `inventories/<env>/hosts.yml` | Real host targeting — bare-metal address + SSH user. One inventory per environment. |
| `inventories/<env>/group_vars/k8slab_host.yml` | Site values for the §8 typed variables — uplink interface, external IPv6 prefix, btrfs source device, runner-reachable LXD-host address. |
| `playbooks/deploy.yml` | Phases A–C of the canonical flow (substrate, mgmt-1, pivot, cleanup) — includes roles from `k8s-lab/ansible/roles/` + `kubernetes.core.helm` tasks. |
| `playbooks/destroy.yml` | Phase 8 reverse — terraform-destroys workloads, removes mgmt-1 + LXD substrate. |
| `terraform/workload-clusters/<name>/` | One TF root per workload cluster. Each invokes the `workload_cluster` module from `k8s-lab/`. Adding a second workload = `cp -r` this dir. |
| `secrets/<env>/vault.yml` | `ansible-vault`-encrypted secrets (sudoers password, mirror creds, …). |
| `k8s-lab/` | This repository, vendored as a git submodule so bug fixes can be pulled with `git submodule update --remote`. |

Key idea: **nothing in this layout invents new variables**. Every
`k8s_lab_*` is declared in plan
[`§8`](../plans/PLAN-stage1-common.md); every TF module input is
declared in `k8s-lab/terraform/modules/workload_cluster/variables.tf`.

---

## Step 1 — Clone and prepare

### 1.1. Bootstrap the consumer repo

```bash
mkdir my-k8s-lab-prod && cd my-k8s-lab-prod
git init
mkdir -p inventories/prod/group_vars \
         playbooks \
         terraform/workload-clusters/prod-default \
         secrets/prod
```

### 1.2. Add k8s-lab as a git submodule

```bash
git submodule add https://github.com/<your-org>/k8s-lab k8s-lab
git submodule update --init --recursive
```

Pin the submodule to a specific commit (or tag) so an unattended
`git submodule update --remote` does not silently move the substrate
under you:

```bash
cd k8s-lab && git checkout v1.0.0 && cd ..
git add k8s-lab
git commit -m "Pin k8s-lab to v1.0.0"
```

### 1.3. Set up the runner

The runner is the machine that runs `ansible-playbook` and
`terraform`. It does **not** have to be the bare-metal target host —
it just needs SSH access to it.

The runner needs Python 3.11+ with `ansible >= 2.16` and the
`kubernetes` PyPI package, plus `terraform >= 1.9`, `helm >= 3.14`
and `kubectl` matching `k8s_lab_kubectl_version` (currently
`v1.35.3`). See [`05-prerequisites.md`](05-prerequisites.md) for the
full list.

Install the Ansible collections k8s-lab roles depend on:

```bash
cd k8s-lab && make deps
```

This populates `k8s-lab/ansible/collections/` with the pinned set
(`community.general`, `kubernetes.core`, `ansible.posix`,
`community.crypto`).

---

## Step 2 — Fill in the network plan

Copy the shared substrate group_vars from the local harness and
replace synthetic values with real ones:

```bash
cp k8s-lab/tests/molecule/shared/inventory/group_vars/k8slab_host.yml \
   inventories/prod/group_vars/k8slab_host.yml
```

The shared file is the canonical reference for what variables a
fully wired substrate needs. Strip out the `lookup('env', 'K8SLAB_HOST_*')`
lines (those are local-Vagrant-only) and replace synthetic values
with real site values. The annotated minimum below is what every
operator must set:

```yaml
---
# inventories/prod/group_vars/k8slab_host.yml
#
# Every k8s_lab_* below is declared in plan §8.
# Role-scoped values (lxd_host_*, lxd_bootstrap_instance_*, etc.)
# keep their role prefix per plan §2.6.2.

# --- Project identity (§8) ----------------------------------------
k8s_lab_opt_root:     "/opt/capi-lab"
k8s_lab_project_name: "capi-lab"

# --- LXD snap policy (role lxd_host) ------------------------------
lxd_host_snap_channel:       "6/stable"
lxd_host_snap_refresh_mode:  "hold"          # never auto-refresh in prod
lxd_host_snap_refresh_timer_value: "fri,03:00-04:00"

# --- Networking (§8) ----------------------------------------------
# The "uplink" NIC carries the EXTERNAL IPv6 segment; LXD bridges
# it into br-ext6 so node eth1 sits directly on the external /64.
# The internal (control) NIC keeps the host's default route and is
# untouched by k8s-lab. See 02-architecture.md §4.
k8s_lab_uplink_interface:         "<your-uplink-nic>"     # e.g. enp2s0
k8s_lab_external_bridge_name:     "br-ext6"
k8s_lab_internal_network_name:    "capi-int"
k8s_lab_internal_ipv4_subnet:     "10.77.0.0/24"
k8s_lab_internal_ipv6_subnet:     "fd42:77:1::/64"

# Operator-provided external IPv6 /64 (announced by upstream router
# via RA on the uplink). NodePort + MetalLB VIPs land here.
k8s_lab_external_ipv6_prefix:     "<your-external-ipv6-prefix>/64"     # 2001:db8:42:100::/64
k8s_lab_external_node_ipv6_range: "<range-for-node-eth1>"              # 2001:db8:42:100::10-…::3f
k8s_lab_metallb_vip_range_v6:     "<range-for-metallb-vips>"           # 2001:db8:42:100::200-…::2ff

# Runner-reachable LXD-host address. Module §16.4 writes the
# workload kubeconfig with `server: https://<this>:<api-proxy-port>`.
# Set to the host's public DNS name or static IP.
k8s_lab_lxd_host_address: "<your-host-fqdn-or-ip>"

# --- Btrfs storage pool (§13.4) -----------------------------------
# REAL block device, /dev/disk/by-id/... path. The LXD snap is
# AppArmor-confined; arbitrary /mnt paths won't work. Device must
# be SIGNATURE-FREE on first converge (mkfs.btrfs runs without -f).
k8s_lab_storage_source:      "/dev/disk/by-id/<your-block-device>"
k8s_lab_storage_pool_name:   "capi-fast"
k8s_lab_storage_driver:      "btrfs"
k8s_lab_storage_btrfs_mount_options: "user_subvol_rm_allowed"

# --- Binary pinning (§8a verified) --------------------------------
k8s_lab_k3s_version:           "v1.35.3+k3s1"
k8s_lab_kubectl_version:       "v1.35.3"
k8s_lab_clusterctl_version:    "v1.12.5"
k8s_lab_capn_provider_version: "v0.8.5"

# --- Cluster identity + topology (§8) -----------------------------
# Workload CP MUST be odd (kubeadm KCP rejects even values under
# stacked etcd). Worker floor = 2 (Gate B pod-anti-affinity).
k8s_lab_management_cluster_name: "mgmt-1"
k8s_lab_workload_cluster_name:   "lab-default"
k8s_lab_kubernetes_version:      "v1.35.0"   # CAPN simplestreams set
k8s_lab_management_controlplane_count: 1
k8s_lab_management_worker_count:       2
k8s_lab_workload_controlplane_count:   3
k8s_lab_workload_worker_count:         2

# --- Workload Pod / Service CIDRs (dual-stack) --------------------
# MUST be disjoint from k8s_lab_internal_ipv6_subnet AND from any
# other cluster on the same network.
k8s_lab_workload_pod_cidr_v4:     "10.244.0.0/16"
k8s_lab_workload_pod_cidr_v6:     "fd42:77:2::/56"
k8s_lab_workload_service_cidr_v4: "10.96.0.0/16"
k8s_lab_workload_service_cidr_v6: "fd42:77:3::/112"

# --- CAPN identity Secret namespaces ------------------------------
k8s_lab_capn_identity_namespaces: ["capi-clusters"]

# --- Optional base_system btrfs mount assertion ------------------
# Keep false when LXD owns a raw block-device-backed btrfs pool.
# Set true only if your site pre-mounts a btrfs filesystem and wants
# base_system to assert that mount before LXD storage reconciliation.
base_system_btrfs_pool_required: false

# --- Role-scoped value bindings (plan §2.6.5: by VALUE) -----------
lxd_host_ext_bridge_uplink: "{{ k8s_lab_uplink_interface }}"

lxd_storage_pools_pools:
  - name:        "{{ k8s_lab_storage_pool_name }}"
    driver:      "{{ k8s_lab_storage_driver }}"
    description: "k8s-lab primary pool (btrfs on dedicated disk)"
    config:
      source: "{{ k8s_lab_storage_source }}"

# --- Bootstrap k3s API publication (§13.7 + §15.5) ----------------
# LXD proxy device userspace-forwards host :16443 → bootstrap
# 127.0.0.1:6443. `bind: host` = no host firewall rule needed.
lxd_bootstrap_instance_devices:
  k3s-api:
    type:    "proxy"
    listen:  "tcp:0.0.0.0:16443"
    connect: "tcp:127.0.0.1:6443"
    bind:    "host"
lxd_bootstrap_instance_wait_timeout: 300

# --- Runner-reachable mgmt API URL --------------------------------
# Phase A's export_artifacts rewrites the shipped mgmt.kubeconfig
# to this URL. TLS identity is decoupled
# (tls-server-name: kubernetes.default.svc), so any host:port that
# TCP-reaches bootstrap k3s' :6443 works.
export_artifacts_mgmt_api_server_url: >-
  https://{{ k8s_lab_lxd_host_address }}:16443
```

For every variable above, see [`08-configuration-reference.md`](08-configuration-reference.md)
for the full description, validation rules, and links to the §8 plan
section. Anything not listed there is consumer-tunable but rarely
needs to change in production.

---

## Step 3 — Inventory and SSH

A minimal inventory:

```yaml
# inventories/prod/hosts.yml
---
all:
  children:
    k8slab_host:
      hosts:
        host01.lab.example.net:
          ansible_user: deploy
          ansible_host: 203.0.113.10
          ansible_port: 22
          ansible_ssh_private_key_file: ~/.ssh/k8s-lab-prod
```

Group `k8slab_host` is what every k8s-lab role expects to be applied
to. Single-host topology = a single host in the group.

The SSH user (`deploy` above) needs:

- key-based SSH login from the runner;
- passwordless `sudo` (or a vault-stored `become_password`);
- ownership of `/opt/capi-lab` (or write access to `/opt/`).

If sudo needs a password, encrypt it with `ansible-vault` and reference
it via `ansible_become_password: "{{ vault_become_password }}"`.

---

## Step 4 — Vault secrets (if any)

Stage 1 itself stores **no host-side secrets** that the operator must
provide. The LXD trust material CAPN uses is generated by
`bootstrap_capn_secret` at converge time. Consumers usually vault
the SSH `become_password` (if sudoers needs one) and any private
mirror / registry credentials they pass to `binary_fetch`.

```bash
ansible-vault create --vault-password-file ~/.vault-pass-prod \
  secrets/prod/vault.yml
```

```yaml
# secrets/prod/vault.yml (example)
---
vault_become_password: "<sudo-password>"
```

Reference in inventory:

```yaml
# inventories/prod/hosts.yml (additions)
all:
  vars:
    ansible_become_password: "{{ vault_become_password }}"
```

Pass `--vault-password-file` (or `--ask-vault-pass`) to every
`ansible-playbook` invocation.

---

## Step 5 — Substrate + bootstrap (Phases A — initial mgmt.kubeconfig)

The substrate is brought up by **including the `export_artifacts`
role**. Through its `meta/main.yml dependencies:` chain it transitively
pulls every Phase 0–4 role:

```
export_artifacts
  └── bootstrap_capn_secret
        └── bootstrap_clusterctl
              └── bootstrap_k3s
                    └── lxd_bootstrap_instance
                          └── binary_fetch
                                └── lxd_profiles
                                      └── lxd_network_int_managed
                                            └── lxd_storage_pools
                                                  └── lxd_project
                                                        └── lxd_host
                                                              └── base_system
```

Single playbook block, single invocation:

```yaml
# playbooks/deploy.yml (Phase A — first run)
---
- name: "k8s-lab | Phase A | substrate + bootstrap k3s + initial mgmt.kubeconfig"
  hosts: k8slab_host
  become: true
  gather_facts: true
  roles:
    - role: k8s-lab/ansible/roles/export_artifacts
      vars:
        export_artifacts_root: "{{ playbook_dir }}/../.artifacts"
```

`export_artifacts_root` is **required** (the role's preflight rejects
empty values) — point it at a runner-side absolute path. `playbook_dir`
resolves on the runner, so `.artifacts/` lands at the consumer-repo
root.

Run it:

```bash
ansible-playbook \
  -i inventories/prod/hosts.yml \
  --vault-password-file ~/.vault-pass-prod \
  playbooks/deploy.yml
```

After a successful run, on the runner:

```
.artifacts/
├── mgmt.kubeconfig              # admin kubeconfig for bootstrap k3s
└── mgmt.auto.tfvars.json        # Phase 5 Terraform handoff bundle
```

`mgmt.kubeconfig` carries `tls-server-name: kubernetes.default.svc`,
its `server:` URL is rewritten to
`https://<k8s_lab_lxd_host_address>:16443` (per
`export_artifacts_mgmt_api_server_url`), and TCP traffic flows through
the LXD proxy device on the bootstrap LXC. File mode is `0600`,
ownership = runner user (plan [§11.1](../plans/PLAN-stage1-common.md)).

`mgmt.auto.tfvars.json` is a JSON object whose keys are §8 globals
verbatim (`k8s_lab_workload_cluster_name`, `k8s_lab_kubernetes_version`,
`k8s_lab_capn_provider_version`, `k8s_lab_mgmt_kubeconfig_path`,
`k8s_lab_mgmt_api_server_url`, …). Terraform auto-loads
`*.auto.tfvars.json` only from the current Terraform root, so Step 7
passes this repo-root artefact explicitly with `-var-file`.

Sanity check at this point:

```bash
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig version --client
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig get pods -A
```

You should see `k3s` server pods, the four CAPI providers
(`capi-system`, `capi-kubeadm-bootstrap-system`,
`capi-kubeadm-control-plane-system`, `capn-system`), and `cert-manager`.

---

## Step 6 — mgmt-1 + Gate A/B + pivot + cleanup_bootstrap (Phases B + C)

The remainder of the canonical pre-workload flow is implemented as
a sequence of Helm installs against `.artifacts/mgmt.kubeconfig`,
followed by the `pivot_clusterctl_move` role, a second
`export_artifacts` invocation (re-emit), and `cleanup_bootstrap`.

The block below mirrors the e2e-local converge flow but uses
consumer-repo paths and `k8s_lab_lxd_host_address` instead of the local
harness environment.

```yaml
# playbooks/deploy.yml (Phases B + C — appended to Phase A above)
- name: "k8s-lab | Phases B+C | mgmt-1 + pivot + cleanup_bootstrap"
  hosts: k8slab_host
  become: true
  gather_facts: true
  vars:
    _repo_root: "{{ playbook_dir }}/.."
    _k8s_lab_root: "{{ _repo_root }}/k8s-lab"
    _artifacts_root: "{{ _repo_root }}/.artifacts"
    _clusters_dir: "{{ _artifacts_root }}/clusters"
    _mgmt_kubeconfig: "{{ _artifacts_root }}/mgmt.kubeconfig"
    _opt_root: "{{ k8s_lab_opt_root | default('/opt/capi-lab') }}"
    _pivot_target_kubeconfig_host_path: "{{ _opt_root }}/etc/pivot_clusterctl_move/mgmt.kubeconfig"

    _capi_namespace: "capi-clusters"
    _metallb_namespace: "metallb-system"
    _tigera_namespace: "tigera-operator"

    _cluster_class_chart: "{{ _k8s_lab_root }}/charts/capi-cluster-class"
    _workload_chart:      "{{ _k8s_lab_root }}/charts/capi-workload-cluster"
    _cni_calico_chart:    "{{ _k8s_lab_root }}/charts/cni-calico"
    _metallb_chart:       "{{ _k8s_lab_root }}/charts/metallb"
    _metallb_config_chart: "{{ _k8s_lab_root }}/charts/metallb-config"

    _mgmt_cluster_name:   "{{ k8s_lab_management_cluster_name }}"
    _mgmt_class_prefix:   "capn-mgmt"
    _mgmt_kc_runner: "{{ _clusters_dir }}/{{ _mgmt_cluster_name }}.kubeconfig"
    _mgmt_cp_count:       "{{ k8s_lab_management_controlplane_count | int }}"
    _mgmt_worker_count:   "{{ k8s_lab_management_worker_count | int }}"
    _kubernetes_version:  "{{ k8s_lab_kubernetes_version }}"
    _lxd_host_address: "{{ k8s_lab_lxd_host_address }}"
    _metallb_vip_range_v6: "{{ k8s_lab_metallb_vip_range_v6 }}"
    _metallb_interface: "{{ k8s_lab_metallb_interface | default('eth1') }}"
    _ansible_python: "{{ ansible_playbook_python }}"

    _pod_cidrs:
      - "{{ k8s_lab_workload_pod_cidr_v4 }}"
      - "{{ k8s_lab_workload_pod_cidr_v6 }}"
    _service_cidrs:
      - "{{ k8s_lab_workload_service_cidr_v4 }}"
      - "{{ k8s_lab_workload_service_cidr_v6 }}"

  tasks:
    # --- Phase B.1 — mgmt-1 ClusterClass on bootstrap k3s -----------------
    - name: "deploy | mgmt-1 | install ClusterClass on bootstrap"
      kubernetes.core.helm:
        kubeconfig: "{{ _mgmt_kubeconfig }}"
        name: "{{ _mgmt_cluster_name }}-class"
        chart_ref: "{{ _cluster_class_chart }}"
        release_namespace: "{{ _capi_namespace }}"
        create_namespace: false
        wait: true
        wait_timeout: 5m
        values:
          clusterClass:
            name: "{{ _mgmt_class_prefix }}"
          kubernetes:
            version: "{{ k8s_lab_kubernetes_version }}"
          capn:
            infrastructureSecretName: "{{ k8s_lab_infrastructure_secret_name | default('incus-identity') }}"
      delegate_to: localhost
      become: false

    # --- Phase B.2 — mgmt-1 Cluster CR on bootstrap k3s -------------------
    - name: "deploy | mgmt-1 | install Cluster CR on bootstrap"
      kubernetes.core.helm:
        kubeconfig: "{{ _mgmt_kubeconfig }}"
        name: "{{ _mgmt_cluster_name }}"
        chart_ref: "{{ _workload_chart }}"
        release_namespace: "{{ _capi_namespace }}"
        create_namespace: false
        wait: true
        wait_timeout: 25m
        values:
          cluster:
            name: "{{ _mgmt_cluster_name }}"
          clusterClass:
            name: "{{ _mgmt_class_prefix }}"
          kubernetes:
            version: "{{ k8s_lab_kubernetes_version }}"
          topology:
            controlPlane:
              replicas: "{{ _mgmt_cp_count | int }}"
            workers:
              replicas: "{{ _mgmt_worker_count | int }}"
          clusterNetwork:
            pods:
              cidrBlocks: "{{ _pod_cidrs }}"
            services:
              cidrBlocks: "{{ _service_cidrs }}"
          apiProxy:
            infrastructureSecretName: "{{ k8s_lab_infrastructure_secret_name | default('incus-identity') }}"
      delegate_to: localhost
      become: false

    # --- Phase B.3 — runner-reachable kubeconfig for mgmt-1 ---------------
    - name: "deploy | mgmt-1 | read kubeconfig Secret on bootstrap"
      kubernetes.core.k8s_info:
        kubeconfig: "{{ _mgmt_kubeconfig }}"
        api_version: v1
        kind: Secret
        namespace: "{{ _capi_namespace }}"
        name: "{{ _mgmt_cluster_name }}-kubeconfig"
      register: _deploy_mgmt_kc_secret
      until: >-
        (_deploy_mgmt_kc_secret.resources | length) == 1
        and ((_deploy_mgmt_kc_secret.resources[0].data.value | default('')) | length) > 0
      retries: 60
      delay: 10
      delegate_to: localhost
      become: false
      vars:
        ansible_python_interpreter: "{{ _ansible_python }}"

    - name: "deploy | mgmt-1 | read api-proxy-port from Cluster CR"
      kubernetes.core.k8s_info:
        kubeconfig: "{{ _mgmt_kubeconfig }}"
        api_version: cluster.x-k8s.io/v1beta2
        kind: Cluster
        namespace: "{{ _capi_namespace }}"
        name: "{{ _mgmt_cluster_name }}"
      register: _deploy_mgmt_cluster
      delegate_to: localhost
      become: false
      vars:
        ansible_python_interpreter: "{{ _ansible_python }}"

    - name: "deploy | mgmt-1 | bind api-proxy-port"
      ansible.builtin.set_fact:
        _mgmt_api_proxy_port: >-
          {{ _deploy_mgmt_cluster.resources[0].metadata.annotations['k8s-lab.io/api-proxy-port'] }}

    - name: "deploy | mgmt-1 | ensure runner-side clusters directory exists"
      ansible.builtin.file:
        path: "{{ _clusters_dir }}"
        state: directory
        mode: "0700"
      delegate_to: localhost
      become: false

    - name: "deploy | mgmt-1 | parse kubeconfig"
      ansible.builtin.set_fact:
        _mgmt_kc_parsed: >-
          {{ _deploy_mgmt_kc_secret.resources[0].data.value | b64decode | from_yaml }}

    - name: "deploy | mgmt-1 | write runner-reachable kubeconfig"
      ansible.builtin.copy:
        dest: "{{ _mgmt_kc_runner }}"
        content: "{{ _mgmt_kc_rebuilt | to_nice_yaml(indent=2) }}"
        mode: "0600"
      delegate_to: localhost
      become: false
      vars:
        _mgmt_kc_rebuilt:
          apiVersion: "v1"
          kind: "Config"
          clusters:
            - name: "{{ _mgmt_kc_parsed.clusters[0].name }}"
              cluster: "{{ _mgmt_kc_parsed.clusters[0].cluster | combine({
                  'server': 'https://' ~ _lxd_host_address ~ ':' ~ _mgmt_api_proxy_port,
                  'tls-server-name': 'kubernetes.default.svc'
                }) }}"
          users: "{{ _mgmt_kc_parsed.users }}"
          contexts: "{{ _mgmt_kc_parsed.contexts }}"
          current-context: "{{ _mgmt_kc_parsed['current-context'] }}"

    - name: "deploy | mgmt-1 | wait for /livez through runner endpoint"
      ansible.builtin.uri:
        url: "https://{{ _lxd_host_address }}:{{ _mgmt_api_proxy_port }}/livez"
        method: GET
        validate_certs: false
        status_code: [200, 401]
        timeout: 10
      register: _deploy_mgmt_apiserver_probe
      retries: 60
      delay: 10
      until: _deploy_mgmt_apiserver_probe.status in [200, 401]
      delegate_to: localhost
      become: false

    # --- Phase B.4 — CNI + MetalLB on mgmt-1 ------------------------------
    - name: "deploy | mgmt-1 | install CNI Calico"
      kubernetes.core.helm:
        kubeconfig: "{{ _mgmt_kc_runner }}"
        name: cni-calico
        chart_ref: "{{ _cni_calico_chart }}"
        release_namespace: "{{ _tigera_namespace }}"
        create_namespace: true
        dependency_update: true
        wait: true
        wait_timeout: 10m
        values:
          calico:
            pods:
              cidrBlocks: "{{ _pod_cidrs }}"
          tests:
            kubectlVersion: "{{ _kubernetes_version }}"
      delegate_to: localhost
      become: false
      vars:
        ansible_python_interpreter: "{{ _ansible_python }}"

    - name: "deploy | mgmt-1 | wait for all Nodes Ready after CNI"
      kubernetes.core.k8s_info:
        kubeconfig: "{{ _mgmt_kc_runner }}"
        api_version: v1
        kind: Node
      register: _deploy_mgmt_nodes_post_cni
      retries: 60
      delay: 10
      until: >-
        ((_deploy_mgmt_nodes_post_cni.resources | default([])) | length)
          == ((_mgmt_cp_count | int) + (_mgmt_worker_count | int))
        and ((_deploy_mgmt_nodes_post_cni.resources
               | map(attribute='status.conditions')
               | map('selectattr', 'type', 'eq', 'Ready')
               | map('first')
               | map(attribute='status')
               | unique
               | list) == ['True'])
      delegate_to: localhost
      become: false
      vars:
        ansible_python_interpreter: "{{ _ansible_python }}"

    - name: "deploy | mgmt-1 | install upstream MetalLB"
      kubernetes.core.helm:
        kubeconfig: "{{ _mgmt_kc_runner }}"
        name: metallb
        chart_ref: "{{ _metallb_chart }}"
        release_namespace: "{{ _metallb_namespace }}"
        create_namespace: true
        dependency_update: true
        wait: true
        wait_timeout: 10m
      delegate_to: localhost
      become: false
      vars:
        ansible_python_interpreter: "{{ _ansible_python }}"

    - name: "deploy | mgmt-1 | install MetalLB config"
      kubernetes.core.helm:
        kubeconfig: "{{ _mgmt_kc_runner }}"
        name: metallb-config
        chart_ref: "{{ _metallb_config_chart }}"
        release_namespace: "{{ _metallb_namespace }}"
        create_namespace: false
        wait: true
        wait_timeout: 10m
        values:
          pool:
            rangeV6: "{{ _metallb_vip_range_v6 }}"
          l2:
            interface: "{{ _metallb_interface }}"
          tests:
            kubectlVersion: "{{ _kubernetes_version }}"
      delegate_to: localhost
      become: false
      vars:
        ansible_python_interpreter: "{{ _ansible_python }}"

    # --- Phase B.5 — Gate A/B helm tests on mgmt-1 ------------------------
    - name: "deploy | mgmt-1 | helm test capi-workload-cluster"
      ansible.builtin.command:
        argv:
          - helm
          - test
          - "{{ _mgmt_cluster_name }}"
          - --namespace
          - "{{ _capi_namespace }}"
          - --kubeconfig
          - "{{ _mgmt_kubeconfig }}"
          - --logs
          - --timeout
          - 35m
      delegate_to: localhost
      become: false

    - name: "deploy | mgmt-1 | helm test cni-calico (Gate B)"
      ansible.builtin.command:
        argv:
          - helm
          - test
          - cni-calico
          - --namespace
          - "{{ _tigera_namespace }}"
          - --kubeconfig
          - "{{ _mgmt_kc_runner }}"
          - --logs
          - --timeout
          - 15m
      delegate_to: localhost
      become: false

    - name: "deploy | mgmt-1 | helm test metallb-config (Gate A)"
      ansible.builtin.command:
        argv:
          - helm
          - test
          - metallb-config
          - --namespace
          - "{{ _metallb_namespace }}"
          - --kubeconfig
          - "{{ _mgmt_kc_runner }}"
          - --logs
          - --timeout
          - 15m
      delegate_to: localhost
      become: false

    # --- Phase C.1 — pivot bootstrap → mgmt-1 -----------------------------
    - name: "deploy | pivot | clusterctl init + move bootstrap → mgmt-1"
      ansible.builtin.include_role:
        name: "{{ _k8s_lab_root }}/ansible/roles/pivot_clusterctl_move"
      vars:
        pivot_clusterctl_move_target_cluster_name: "{{ _mgmt_cluster_name }}"
        pivot_clusterctl_move_target_cluster_namespace: "{{ _capi_namespace }}"
        pivot_clusterctl_move_target_api_address: "{{ k8s_lab_lxd_host_address }}"

    # --- Phase C.2 — re-emit .artifacts/mgmt.kubeconfig with mgmt-1 creds -
    - name: "deploy | re-emit | overwrite mgmt.kubeconfig"
      ansible.builtin.include_role:
        name: "{{ _k8s_lab_root }}/ansible/roles/export_artifacts"
      vars:
        export_artifacts_root: "{{ _artifacts_root }}"
        export_artifacts_run_meta_chain: false
        export_artifacts_mgmt_kubeconfig_source: "{{ _pivot_target_kubeconfig_host_path }}"
        export_artifacts_mgmt_api_server_url: ""
        export_artifacts_tfvars_enabled: false

    # --- Phase C.3 — retire the bootstrap LXC -----------------------------
    - name: "deploy | cleanup | retire bootstrap LXC"
      ansible.builtin.include_role:
        name: "{{ _k8s_lab_root }}/ansible/roles/cleanup_bootstrap"
      vars:
        cleanup_bootstrap_remove_artifacts: false
```

After Phases B+C complete:

- **`.artifacts/mgmt.kubeconfig`** now points at the **self-hosted
  mgmt-1 cluster** (the bootstrap k3s endpoint is gone). Same file
  path, new contents — every downstream consumer (Step 7's Terraform,
  day-2 `kubectl`) keeps a single mgmt-creds path.
- The `capi-bootstrap-0` LXC instance is **deleted**; its proxy
  device on `:16443` is gone with it.
- mgmt-1 runs the four CAPI controllers (CAPI core, CABPK, KCP, CAPN)
  as Pods on its own kube-apiserver. CAPN can now reconcile workload
  Cluster CRs.

Run the full deploy.yml (idempotent; safe to re-run on retry):

```bash
ansible-playbook \
  -i inventories/prod/hosts.yml \
  --vault-password-file ~/.vault-pass-prod \
  playbooks/deploy.yml
```

Sanity check:

```bash
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig get nodes -o wide
# 1 CP + 2 worker, all Ready

kubectl --kubeconfig=.artifacts/mgmt.kubeconfig get pods -A | grep -E 'capi-|capn-'
# capi-system / capi-kubeadm-bootstrap-system / capi-kubeadm-control-plane-system / capn-system
# all Pods Running (NOT in k3s on bootstrap any more — they live on mgmt-1)
```

---

## Step 7 — Workload cluster (Phase D — Terraform)

Adding workload clusters to a self-hosted mgmt-1 is the
**Terraform-driven path**. Each workload = one Terraform root that
invokes `terraform/modules/workload_cluster` from this repo.

### 7.1. providers.tf

```hcl
# terraform/workload-clusters/prod-default/providers.tf
#
# Fixture-side `required_providers` only — no provider configuration
# blocks. The workload_cluster module owns mgmt + workload helm /
# kubernetes provider configurations internally.

terraform {
  required_version = ">= 1.9"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
```

### 7.2. variables.tf

A consumer variables.tf mirrors the §8 globals that the
`mgmt.auto.tfvars.json` bundle carries. The simplest path is to
**copy the in-repo fixture's variables.tf verbatim**:

```bash
cp k8s-lab/tests/fixtures/terraform/workload-clusters/lab-default/variables.tf \
   terraform/workload-clusters/prod-default/variables.tf
```

That file declares all of the variables the §16.6 reference fixture
uses (`k8s_lab_mgmt_kubeconfig_path`, `k8s_lab_mgmt_api_server_url`,
the §8 cluster-identity / topology / CIDR / image / chart-version
globals, plus auto-tfvars passthrough variables that silence
warnings about `mgmt.auto.tfvars.json` keys this root does not
itself consume). Defaults match the §8 reference deployment so a
fresh `terraform plan` works without overrides — adjust only
where the operator's site differs.

### 7.3. main.tf

The in-repo fixture
(`k8s-lab/tests/fixtures/terraform/workload-clusters/lab-default/main.tf`)
is the canonical reference; copy it and rewrite the `source` path so
it climbs out of the consumer repo into the submodule. The two
load-bearing differences:

```hcl
# terraform/workload-clusters/prod-default/main.tf

locals {
  default_mgmt_kubeconfig_path = abspath("${path.root}/../../../.artifacts/mgmt.kubeconfig")
  mgmt_kubeconfig_path = (
    var.k8s_lab_mgmt_kubeconfig_path != ""
    ? var.k8s_lab_mgmt_kubeconfig_path
    : local.default_mgmt_kubeconfig_path
  )

  # lxd_host_address is not in the export_artifacts payload — derive
  # it from the mgmt API URL host component (same regex the in-repo
  # fixture uses).
  _lxd_addr_match = var.k8s_lab_mgmt_api_server_url != "" ? regex(
    "^https?://(?:\\[([^\\]]+)\\]|([^:/]+))",
    var.k8s_lab_mgmt_api_server_url
  ) : [null, null]
  lxd_host_address = try(
    coalesce(local._lxd_addr_match[0], local._lxd_addr_match[1]),
    ""
  )
}

module "workload_cluster" {
  # Climb out of the consumer-repo's TF root into the vendored k8s-lab
  # submodule. The in-repo fixture climbs `../../../../../` (5 levels);
  # consumer roots typically sit 3 levels deep under repo root.
  source = "../../../k8s-lab/terraform/modules/workload_cluster"

  mgmt_kubeconfig_path = local.mgmt_kubeconfig_path
  lxd_host_address     = local.lxd_host_address

  cluster_name       = var.k8s_lab_workload_cluster_name
  cluster_namespace  = "capi-clusters"
  kubernetes_version = var.k8s_lab_kubernetes_version
  controlplane_count = var.k8s_lab_workload_controlplane_count
  worker_count       = var.k8s_lab_workload_worker_count

  cluster_class_chart_version    = var.cluster_class_chart_version
  cluster_workload_chart_version = var.cluster_workload_chart_version
  cni_calico_chart_version       = var.cni_calico_chart_version
  metallb_chart_version          = var.metallb_chart_version
  metallb_config_chart_version   = var.metallb_config_chart_version

  pod_cidrs     = [var.k8s_lab_workload_pod_cidr_v4, var.k8s_lab_workload_pod_cidr_v6]
  service_cidrs = [var.k8s_lab_workload_service_cidr_v4, var.k8s_lab_workload_service_cidr_v6]

  infrastructure_secret_name     = var.k8s_lab_infrastructure_secret_name
  image_controlplane_ref         = var.k8s_lab_images_controlplane
  image_controlplane_fingerprint = var.k8s_lab_images_controlplane_fingerprint
  image_worker_ref               = var.k8s_lab_images_worker
  image_worker_fingerprint       = var.k8s_lab_images_worker_fingerprint
  controlplane_profiles_extra    = var.k8s_lab_controlplane_profiles_extra
  worker_profiles_extra          = var.k8s_lab_worker_profiles_extra
  controlplane_devices_extra     = var.k8s_lab_controlplane_devices_extra
  worker_devices_extra           = var.k8s_lab_worker_devices_extra
  kube_proxy_node_port_addresses = var.k8s_lab_kube_proxy_nodeport_addresses

  metallb_vip_range_v6 = var.k8s_lab_metallb_vip_range_v6
  metallb_interface    = var.k8s_lab_metallb_interface
}
```

### 7.4. outputs.tf

Same shape as the in-repo fixture's
`outputs.tf` — re-export `cluster_name`, `cluster_namespace`,
`kubeconfig` (sensitive), `api_proxy_port`, `metallb_vip_range_v6`,
and `helm_releases` from `module.workload_cluster`. Copy the file
verbatim from
`k8s-lab/tests/fixtures/terraform/workload-clusters/lab-default/outputs.tf`.

### 7.5. terraform.tfvars

The site-specific values that aren't in `mgmt.auto.tfvars.json`:

```hcl
# terraform/workload-clusters/prod-default/terraform.tfvars
k8s_lab_workload_cluster_name = "prod-default"
k8s_lab_metallb_vip_range_v6  = "<your-external-ipv6-range-for-vips>"   # e.g. 2001:db8:42:100::200-2001:db8:42:100::2ff
```

### 7.6. Apply

```bash
cd terraform/workload-clusters/prod-default
terraform init -upgrade
terraform apply -var-file=../../../.artifacts/mgmt.auto.tfvars.json
cd ../../..
```

The `-var-file` is needed because Terraform auto-loads
`*.auto.tfvars.json` only from the current directory — Phase 4 dropped
the file at `.artifacts/` (consumer repo root), not in the Terraform
root.

What `terraform apply` does, in order (the module's internal graph):

1. **`helm_release.capi_cluster_class`** — installs
   `charts/capi-cluster-class` on mgmt-1 → ClusterClass + KCPTemplate
   + LXCMachineTemplate + LXCClusterTemplate + KubeadmConfigTemplate
   CRs.
2. **`helm_release.capi_workload_cluster`** — installs
   `charts/capi-workload-cluster` → workload Cluster CR. CAPN reads
   it, provisions LXC instances (3 CP + 2 worker + 1 LB by default),
   kubeadm bootstraps them. The chart's post-install hook blocks
   until the kube-apiserver is `/livez` green.
3. **`data.kubernetes_resource.workload_cluster_cr`** and
   **`data.kubernetes_resource.workload_kubeconfig_secret`** read the
   Cluster CR annotation `k8s-lab.io/api-proxy-port` and the CAPI
   kubeconfig Secret; the module rebuilds the workload kubeconfig with
   `server: https://<lxd_host_address>:<port>`.
4. **`helm_release.cni_calico`** — installs `charts/cni-calico` on
   the workload cluster → tigera-operator + Calico Installation.
   Gate B below is the post-install readiness barrier.
5. **`helm_release.metallb`** — installs upstream MetalLB on the
   workload cluster (`charts/metallb` is a thin wrapper around the
   upstream metallb subchart).
6. **`helm_release.metallb_config`** — installs the IPAddressPool +
   L2Advertisement.
7. **Gate B** — `null_resource.helm_test_cni_calico` runs `helm test
   cni-calico --timeout 15m`, asserting CNI viability (pod-to-pod v4
   + v6, ClusterIP routing).
8. **Gate A** — `null_resource.helm_test_metallb_config` runs `helm
   test metallb-config --timeout 15m`, asserting MetalLB allocates
   and announces an IPv6 VIP.

If any gate fails, `terraform apply` fails. See plan
[`§17`](../plans/PLAN-stage1-4.md) for the gate definitions.

After apply succeeds: workload Cluster CR is up, Calico is green,
MetalLB is announcing on `eth1`, and the workload kubeconfig is in
Terraform state.

---

## Step 8 — Verifying the deployment

### 8.1. mgmt-1 nodes

```bash
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig get nodes -o wide
# Expected:
#   mgmt-1-cp-0       Ready    control-plane
#   mgmt-1-md-0-...   Ready    <none>
#   mgmt-1-md-0-...   Ready    <none>
```

### 8.2. Materialise the workload kubeconfig

```bash
cd terraform/workload-clusters/prod-default
mkdir -p ../../../.artifacts/clusters
umask 077
terraform output -raw kubeconfig > ../../../.artifacts/clusters/prod-default.kubeconfig
cd ../../..
```

### 8.3. Workload nodes

```bash
kubectl --kubeconfig=.artifacts/clusters/prod-default.kubeconfig get nodes -o wide
# Expected:
#   prod-default-...-cp-0   Ready    control-plane
#   prod-default-...-cp-1   Ready    control-plane
#   prod-default-...-cp-2   Ready    control-plane
#   prod-default-...-md-0-... Ready  <none>
#   prod-default-...-md-0-... Ready  <none>
```

### 8.4. CAPI topology view (on mgmt-1)

```bash
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig \
  get clusters,machinedeployments,kubeadmcontrolplanes -A
# Expected:
#   namespace=capi-clusters
#   cluster.cluster.x-k8s.io/prod-default               Provisioned
#   kubeadmcontrolplane.controlplane.cluster.x-k8s.io   ready=true
#   machinedeployment.cluster.x-k8s.io/prod-default-md-0  Running 2/2
```

`clusterctl` (binary on the host at `/opt/capi-lab/bin/clusterctl`)
is also useful:

```bash
ssh deploy@host01.lab.example.net \
  sudo /opt/capi-lab/bin/clusterctl --kubeconfig=/opt/capi-lab/etc/pivot_clusterctl_move/mgmt.kubeconfig \
  describe cluster prod-default -n capi-clusters
```

### 8.5. External Gate A reachability

The workload's MetalLB announces on `eth1`, which is bridged to
`br-ext6`, which is bridged to your uplink NIC. From a probe outside
the LXD host (any machine with IPv6 reachability to your external
prefix):

```bash
VIP="$(kubectl --kubeconfig=.artifacts/clusters/prod-default.kubeconfig \
  -n metallb-system \
  get svc k8s-lab-metallb-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"

# From the external probe machine:
curl -6 --max-time 5 "http://[$VIP]/"
# ok
```

If the external curl times out but the helm test PASSes, the cluster
is internally healthy but the operator's external L2 segment doesn't
deliver NDP responses to the VIP — see
[`13-troubleshooting.md`](13-troubleshooting.md) Gate A section.

---

## Step 9 — Adding more workload clusters

Once mgmt-1 is self-hosted, every additional workload is a `cp -r`
of the Terraform root:

```bash
cp -r terraform/workload-clusters/prod-default \
      terraform/workload-clusters/prod-other
```

Edit `terraform/workload-clusters/prod-other/terraform.tfvars`:

```hcl
k8s_lab_workload_cluster_name = "prod-other"

# Pod / Service CIDRs MUST NOT overlap any other cluster on the same
# mgmt-1. Calico SNATs Pod traffic, but the kube-apiserver still sees
# Pod IPs internally — overlap = silent cross-cluster Pod-IP collision.
k8s_lab_workload_pod_cidr_v4     = "10.245.0.0/16"
k8s_lab_workload_pod_cidr_v6     = "fd42:77:4::/56"
k8s_lab_workload_service_cidr_v4 = "10.97.0.0/16"
k8s_lab_workload_service_cidr_v6 = "fd42:77:5::/112"

# MetalLB VIP range MUST be disjoint from every other workload's range.
k8s_lab_metallb_vip_range_v6 = "<another-external-ipv6-range-for-vips>"
```

Apply:

```bash
cd terraform/workload-clusters/prod-other
terraform init -upgrade
terraform apply -var-file=../../../.artifacts/mgmt.auto.tfvars.json
```

Each workload Terraform root carries its own state. Destroying one
does not affect the others.

---

## Day-2 / destroy / upgrade

The destroy chain is the inverse of deploy:

1. `terraform destroy` per workload root → `helm uninstall` of all
   add-ons, `helm uninstall` of the Cluster CR (CAPN cascade-deletes
   LXC instances), `helm uninstall` of the ClusterClass.
2. Re-run a "Phase 8 destroy" playbook that uninstalls mgmt-1 charts,
   then deletes mgmt-1 LXC instances, then rolls back the substrate
   (LXD project, networks, storage pool, host bridge).

Upgrades:

- **Substrate**: bump pins in `inventories/prod/group_vars/k8slab_host.yml`
  and re-run `playbooks/deploy.yml`. Roles are idempotent.
- **Workload chart versions**: bump `cluster_class_chart_version` /
  `cluster_workload_chart_version` in
  `terraform.tfvars`, then `terraform apply`. The
  chart-version-as-CR-name pattern (plan
  [`§2.9`](../plans/PLAN-stage1-common.md), see also
  [`02-architecture.md`](02-architecture.md) §6) creates fresh
  ClusterClass + Templates objects.
- **Kubernetes version**: bump `k8s_lab_kubernetes_version` (Ansible)
  + matching variable on the Terraform side; verify against the CAPN
  simplestreams set first.

See [`11-operations.md`](11-operations.md) for the full operational
playbook (rolling upgrades, certificate rotation, backup/restore of
mgmt-1, etc.).

---

## Production-vs-local differences to remember

The local Vagrant harness mocks several pieces of real infrastructure.
In production those pieces are operator-supplied:

| Concern | Local harness | Production |
|---------|---------------|------------|
| External IPv6 RA source | In-VM `radvd` on `ext6-ra-peer` | The provider router on the operator's external segment |
| External IPv6 prefix | `2001:db8:42:100::/64` (documentation range) | The operator's globally-routable /64 |
| Image source | `capi:kubeadm/<ver>` from upstream simplestreams (same as prod default) | Same — unless the operator overrides `k8s_lab_images_controlplane` / `k8s_lab_images_worker` to point at a local mirror. Image MUST stay cloud-init-capable (plan §2.10). |
| LXD storage source | `/dev/disk/by-id/virtio-k8slab-lxdpool` (Vagrant-attached virtual disk) | A real, dedicated, signature-free block device on the host |
| Runner-reachable mgmt URL | Vagrant VM IP from `vagrant ssh-config` | The host's public DNS name or static IP — set as `k8s_lab_lxd_host_address` |
| Pod CIDR uniqueness | Single isolated VM, no neighbours | Must not overlap any other Kubernetes cluster on the same network — and must not overlap `k8s_lab_internal_ipv6_subnet` |
| Host firewall | None (Vagrant VM is firewall-free) | Operator-managed. k8s-lab does not write firewall rules (plan §11.4); bootstrap API publication uses LXD proxy devices, not nftables. |

If something works locally but breaks in prod, walk down this table
first — most surprises live here.

---

## Common first-deploy gotchas

### G-1. btrfs pool device must be signature-free

The `lxd_storage_pools` role formats the device with `mkfs.btrfs`
**without `-f`**. If the device has any leftover filesystem signature
(an old ext4, an old btrfs, a ZFS label), mkfs refuses. Wipe with
`wipefs -a /dev/disk/by-id/<...>` before the first converge — and
double-check the device path is the **right one** before doing so.

### G-2. cloud-init capability of consumer-supplied images

`charts/capi-cluster-class` delivers the eth1 RA reception baseline
(sysctl + systemd-networkd drop-in for `accept_ra=2`) through
`KubeadmConfigSpec.files` + `preKubeadmCommands`. CABPK inlines them
into cloud-init `write_files`. If the image you point CAPN at has
**no cloud-init** or has a stripped-down cloud-init that ignores
`write_files`, the eth1 baseline never lands, the workload nodes
never SLAAC a global IPv6 on `eth1`, and Gate A fails.

The CAPN-prebuilt `capi:kubeadm/<ver>` images have cloud-init. Custom
operator images **must** preserve it.

### G-3. Pod CIDR overlapping the internal LXD network

`k8s_lab_internal_ipv6_subnet` (default `fd42:77:1::/64`) and
`k8s_lab_workload_pod_cidr_v6` (default `fd42:77:2::/56`) are
deliberately disjoint. If overlap is introduced, kube-proxy and
Calico fight over routes and Service-IP traffic gets blackholed.
Keep `pod_cidr_v6`, `service_cidr_v6`, `internal_ipv6_subnet` and
your external IPv6 prefix mutually disjoint.

### G-4. DNS / SSH from the runner to the LXD host

The runner needs to TCP-reach `k8s_lab_lxd_host_address:16443`
(bootstrap API) and `k8s_lab_lxd_host_address:<api-proxy-port>` (mgmt
+ each workload's API). Use IP addresses or pre-warm DNS — flaky
runner-side DNS makes the /livez probes time out before the
kube-apiserver is even contacted.

### G-5. `clusterctl move` and helm release storage

Pivot relocates **CAPI CRs**, not helm releases. Any helm release
installed on bootstrap k3s — other than the mgmt-1 ClusterClass +
Cluster CR pair, which is the canonical scaffolding — is lost when
`cleanup_bootstrap` deletes the LXC. The canonical flow installs
workload charts only on mgmt-1 (post-pivot) or on a workload cluster
(post-deploy). See plan
[`§3.3`](../plans/PLAN-stage1-common.md).

---

## Where to read more

| Question | Source |
|----------|--------|
| What variable does X mean? | [`08-configuration-reference.md`](08-configuration-reference.md) |
| What does role Y do? | [`09-roles-reference.md`](09-roles-reference.md) and the role's own README |
| What does chart Z deliver? | [`10-modules-and-charts.md`](10-modules-and-charts.md) |
| Why is the deploy stuck on Gate B? | [`13-troubleshooting.md`](13-troubleshooting.md) |
| Why is the canonical flow this shape? | [plan `§3`](../plans/PLAN-stage1-common.md) |
| Why does the consumer-repo boundary exist? | [plan `§2.5`](../plans/PLAN-stage1-common.md) |
| Final consumer recommendation | [plan `§22`](../plans/PLAN-stage1-7.md) |
| Operations & lifecycle | [`11-operations.md`](11-operations.md) |

The [`tests/molecule/e2e-local/converge.yml`](../tests/molecule/e2e-local/converge.yml)
play is the canonical, executable reference for the entire flow
described in this chapter. When in doubt about ordering or arguments,
cross-check against it.
