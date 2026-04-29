Этот файл владеет §18: Phases 6 + 7 — optional pivot + post-pivot
workload cluster creation. Нумерация §N сквозная по всем plan-файлам;
перекрёстные ссылки вида `§<номер>` валидны без указания имени файла —
см. `PLAN-stage1-common.md` header для полного file lineup. Атомарный
scope этого шарда — Stage 2 pivot path (optional by default) плюс
workload cluster flow, который становится актуален только при включённом
`k8s_lab_pivot_enabled=true`.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (Phases 5 + 5.05 CAPI topology via Helm)
PLAN-stage1-4.md ................. §17      (Phases 5.1 + 5.2 + 5.3 Helm add-ons + in-cluster tests)
PLAN-stage1-5.md ................. §18      (Phases 6 + 7 pivot + workload clusters)      <-- этот файл
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 meta: out-of-scope, self-review, recommendation)
```

---

# 18. Phases 6 + 7 — Optional pivot + post-pivot workload creation

Этот раздел группирует:

* §18.1 — TF fixture `tests/fixtures/terraform/management-clusters/mgmt-1/`
  (создаёт target mgmt cluster CR на bootstrap k3s через тот же §16.4
  `workload_cluster` module);
* §18.2 — role `pivot_clusterctl_move` + Ansible playbook
  `tests/fixtures/ansible/pivot_clusterctl_move/playbook.yml`
  (`clusterctl init` на target + `clusterctl move` + retire
  bootstrap через `cleanup_bootstrap`);
* §18.3 — Make-target `deploy-pivot` + Phase 7 (workload clusters
  от self-hosted mgmt после pivot).

Phase 6 является **opt-in**: глобал `k8s_lab_pivot_enabled` (§8) по
умолчанию `false` (MVP path §3.1). Make-target `deploy-pivot`
форсит его в `true` через playbook-scope `vars:` — оператор просто
вызывает `make deploy-pivot` после Phase 4, без `-e` overrides.

## 18.1. TF fixture: `management-clusters/mgmt-1/`

**Статус: выполнено в Step 18 (2026-04-29).**

`tests/fixtures/terraform/management-clusters/mgmt-1/` — TF root,
зеркало `workload-clusters/lab-default/` с другими input'ами:

* `cluster_name = "mgmt-1"` (из §8 `k8s_lab_management_cluster_name`);
* `controlplane_count = 1`, `worker_count = 2` (§8 +
  §2.12 mgmt-side replica policy + chart-required floor — см. ниже);
* `class_prefix = "capn-mgmt"` — отдельный ClusterClass-нэйм
  (`capn-mgmt-<chart-version-slug>`), позволяет mgmt и workload
  Cluster CR'ам сосуществовать в одном `capi-clusters` namespace
  до момента clusterctl move;
* `metallb_vip_range_v6 = 2001:db8:42:100::300-::3ff` — disjoint от
  workload range `::200-::2ff`, исключает MetalLB speaker
  collision если mgmt + workload coexist на одном external L2 segment'е.

Module внутри fixture'а — тот же generic `workload_cluster` (§16.4),
который ставит ClusterClass + Cluster CR + CNI + MetalLB + Gate A/B
helm tests одним `terraform apply`'ем. К моменту запуска
pivot-роли (§18.2) target mgmt-1 cluster уже **полностью функционален**:
CAPI controllers ещё нет (их установит `clusterctl init` в pivot роли),
но Kubernetes API + CNI + node-level готовности — на месте.

**Worker count floor = 2.** `cni-calico` chart (§17.2) helm test
включает phase 6 «live pod-to-pod ICMP4+ICMP6 across workers» с
`requiredDuringScheduling pod-anti-affinity` — probe-a и probe-b
обязаны попасть на разные worker-ноды. На mgmt с 1 worker probe-b
застревает в `Pending` → TF apply падает на gate. Поэтому §8
`k8s_lab_management_worker_count` default = `2` (chart-required
floor для любого кластера, идущего через workload_cluster module);
оператор может поднимать до 3+ если нужен HA, но не ниже 2.

Параметризация — через тот же `.artifacts/bootstrap.auto.tfvars.json`
handoff (§13.12), что и workload fixture использует. Значения
§8 globals (`k8s_lab_management_*`) экспортируются `export_artifacts`
ролью.

## 18.2. Role + playbook: `pivot_clusterctl_move`

**Статус: выполнено в Step 18 (2026-04-29).**

Role lives at `ansible/roles/pivot_clusterctl_move/`.

Public contract (full role README — `ansible/roles/pivot_clusterctl_move/README.md`):

* `pivot_clusterctl_move_target_cluster_name` (default
  `{{ k8s_lab_management_cluster_name }}`) — Cluster CR name to
  pivot. Substrate-required cluster-namespace = `capi-clusters`
  (matches §8 `k8s_lab_capn_identity_namespaces` default).
* `pivot_clusterctl_move_target_api_address` (default
  `{{ k8s_lab_lxd_host_address }}`) — runner-reachable LXD host;
  rewritten into target kubeconfig server URL alongside per-cluster
  proxy port from Cluster CR's `k8s-lab.io/api-proxy-port` annotation.
* CAPN provider URL + version pulled from §8 globals — same release
  bootstrap cluster runs.

Substrate-required values (memory `feedback_required_values_hardcoded.md`)
in `vars/main.yml`:

* CAPN provider name `incus` — registered upstream;
* `tls-server-name: kubernetes.default.svc` — pinned in rewritten
  kubeconfig so TLS verification works regardless of `server:` URL
  vantage point;
* api-proxy-port annotation key `k8s-lab.io/api-proxy-port` — single
  source of truth shared with `capi-workload-cluster` chart's
  `_helpers.tpl apiProxyPort` helper;
* required Deployment list for post-init Available poll (cert-manager
  + 4 CAPI/CAPN providers) — mirrors `bootstrap_clusterctl`'s set.

Task layout (`tasks/main.yml` dispatcher):

1. `preflight.yml` — validate inputs + clusterctl binary stat +
   bootstrap kubeconfig stat. Always runs (catches misconfiguration
   in MVP mode too).
2. `target_kubeconfig.yml` — probe bootstrap for target Cluster CR;
   if present, poll for `<cluster>-kubeconfig` Secret + read
   api-proxy-port annotation, rewrite server URL +
   `tls-server-name`, write to
   `/opt/capi-lab/etc/pivot_clusterctl_move/mgmt.kubeconfig`
   (mode 0600). If absent, fall back to existing on-disk kubeconfig
   (post-pivot re-converge path).
3. `config.yml` — render `clusterctl.yaml` with CAPN provider URL.
4. `init.yml` — probe target for `capn-controller-manager` Deployment;
   skip when present (clusterctl init is all-or-nothing). Otherwise
   run `clusterctl init --infrastructure incus:<ver> --wait-providers`
   with `CLUSTER_TOPOLOGY=true` env (async/poll).
5. `move.yml` — guarded by the `target_kubeconfig.yml` probe fact
   `_pivot_clusterctl_move_target_on_bootstrap`. When `false`, move
   already happened, skip. Otherwise run
   `clusterctl move --kubeconfig=<bootstrap> --to-kubeconfig=<target>
    --namespace=capi-clusters` (async/poll).
6. `healthchecks.yml` — re-assert post-pivot end state from a
   separate process: cert-manager + 4 provider Deployments
   Available on target, 4 Provider CRs present, target Cluster CR on
   target, **bootstrap source flushed** (no Cluster CRs in target
   namespace on bootstrap).

Idempotence: every mutating step is gated on a read-only probe
(plan §2.6.1). Re-running on an already-pivoted host is reliably
`changed=false` end-to-end.

Meta-deps (single, with `# why` comment per §2.6.5):

* `bootstrap_clusterctl` — transitively pulls
  `bootstrap_k3s → binary_fetch → lxd_bootstrap_instance → …` so
  `clusterctl` binary + bootstrap kubeconfig are guaranteed by the
  time the role's tasks run.

The role hard-gates everything below `preflight` on
`k8s_lab_pivot_enabled | bool` AND `pivot_clusterctl_move_enabled`
(coarse-grained per §2.6.3) — calling the role with the default mode
is a documented no-op.

### Bootstrap retirement: `cleanup_bootstrap`

Phase 6 acceptance "bootstrap deleted" is owned by the existing
`cleanup_bootstrap` role (§19.1), not by `pivot_clusterctl_move`.
The pivot fixture playbook chains them in one play:

```yaml
roles:
  - role: pivot_clusterctl_move    # init + move + healthchecks
  - role: cleanup_bootstrap        # delete bootstrap LXC + proxy
```

`cleanup_bootstrap` has no meta-deps by design (reverse-motion);
the substrate it needs (LXD daemon, `capi-lab` project) is already
up from `pivot_clusterctl_move`'s meta-chain. Runner-side
`.artifacts/` is **not** wiped here (`cleanup_bootstrap_remove_artifacts:
false` set in playbook scope) — operator decides separately when to
clean stale `bootstrap.kubeconfig` / `bootstrap.auto.tfvars.json`.

### No separate Molecule scenario

The role's own healthchecks (`tasks/healthchecks.yml`) re-assert the
post-pivot end state — providers Available on target, Cluster CR
moved, bootstrap source flushed — as a **mandatory part of every run**
(no `flow_control` toggle for healthchecks). Acceptance is therefore
covered by the role itself, not by an external Molecule verify play.
A dedicated `tests/molecule/pivot/` scenario is **not** part of this
repo.

## 18.3. Phase 6 + Phase 7 execution

### Phase 6 — `make deploy-pivot`

**Статус: выполнено в Step 18 (2026-04-29 e2e on the local Vagrant
harness — 275 ok / 6 changed / 0 failed; 4 CAPI providers Available
on mgmt-1; Cluster CR moved bootstrap → target; capi-bootstrap-0
container absent post-cleanup).**

Single Make-target `deploy-pivot` (root Makefile) chains three
stages:

1. **Stage 0/2** — `make -C tests/vagrant/debian13 up` (idempotent
   VM check).
2. **Stage 1/2** — `terraform init -upgrade` + `terraform apply
   -auto-approve -var-file=.artifacts/bootstrap.auto.tfvars.json` on
   `tests/fixtures/terraform/management-clusters/mgmt-1/`. Stands up
   mgmt-1 cluster on the bootstrap k3s (CAPI topology + CNI + MetalLB
   + Gate A/B helm tests pass inline, same as §16.6 workload flow).
3. **Stage 2/2** — `vagrant ssh-config host` parsed once into
   `K8SLAB_HOST_*` env vars; `ANSIBLE_ROLES_PATH` /
   `ANSIBLE_COLLECTIONS_PATH` exported; `ansible-playbook -i
   tests/fixtures/ansible/pivot_clusterctl_move/hosts.yml -i
   tests/molecule/shared/inventory <playbook>`. Same shared
   substrate `group_vars` Molecule scenarios use are picked up
   through the second `-i` argument.

Inline shell in the Make recipe — no Python wrapper around
ansible-playbook (the wiring is 4 env exports + one awk pass over
`vagrant ssh-config`).

Phase 6 acceptance:

* TF apply on mgmt-1 fixture exits 0 (Gate A external L2 + Gate B CNI
  helm tests pass on the target cluster — §17.2 / §17.3);
* `pivot_clusterctl_move` healthchecks all pass (4 providers
  Available + Cluster CR moved + bootstrap flushed);
* `cleanup_bootstrap` healthchecks pass (bootstrap container absent
  via LXD REST probe).

### Phase 7 — Workload clusters from self-hosted mgmt

After Phase 6 the bootstrap k3s is gone; subsequent workload
deploys consume the mgmt-1 kubeconfig instead of the bootstrap one.
Mechanically Phase 7 is a re-run of `make deploy-workload` (§16.6)
with one tfvar override:

```bash
# Materialise target mgmt kubeconfig once (TF output → file)
make mgmt-kubeconfig
# Then deploy workload against it
cd tests/fixtures/terraform/workload-clusters/lab-default \
  && terraform apply -auto-approve \
       -var-file=../../../../.artifacts/bootstrap.auto.tfvars.json \
       -var=mgmt_kubeconfig_path=../../../../.artifacts/clusters/mgmt-1.kubeconfig
```

The `mgmt_kubeconfig_path` variable on the workload fixture
(§16.5) accepts this override; the `workload_cluster` module
itself (§16.4) is mgmt-agnostic — it just talks to whichever
kubeconfig you point its `helm.mgmt` provider alias at. No new
Makefile target / TF root / module is introduced for Phase 7.

Phase 7 acceptance:

* `terraform apply` green against the self-hosted mgmt-1 kubeconfig;
* chart-side helm tests (Gate A + Gate B) inside the module green
  (see §17.1 invocation contract).

Cluster API docs cover the full bootstrap-and-pivot flow (init →
move → retire bootstrap; target mgmt must already have at least one
worker before move — satisfied by §18.1's worker_count=2 default).
([Cluster API][8])

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
