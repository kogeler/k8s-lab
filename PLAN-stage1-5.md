Этот файл владеет §18: pivot mgmt-1 → self-hosted as a mandatory step
inside the canonical e2e-local flow (plan §3 + §10). Нумерация §N
сквозная по всем plan-файлам; перекрёстные ссылки вида `§<номер>`
валидны без указания имени файла — см. `PLAN-stage1-common.md`
header для полного file lineup.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (workload_cluster TF module)
PLAN-stage1-4.md ................. §17      (Helm test contracts — Gate A + Gate B chart-side specs)
PLAN-stage1-5.md ................. §18      (pivot mgmt-1 → self-hosted)                        <-- этот файл
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 closure + self-review + recommendation)
```

---

# 18. Pivot mgmt-1 → self-hosted

Pivot — обязательная стадия canonical k8s-lab flow (§3 + §10): bootstrap
k3s — это transient scaffolding, его единственная задача — захостить
mgmt-1 Cluster CR ровно столько, сколько нужно `clusterctl init` +
`clusterctl move` чтобы превратить mgmt-1 в self-hosted CAPI management
cluster. После этого bootstrap LXC удаляется через `cleanup_bootstrap`.

Нет dispatch-веток / opt-in флагов. Standalone Make-target'а для
pivot'а нет — pivot — это часть `tests/molecule/e2e-local/` (§10.2)
и реализуется композицией существующих ролей.

## 18.1. mgmt-1 helm install — на bootstrap'е

mgmt-1 Cluster CR создаётся через те же `charts/capi-cluster-class/`
+ `charts/capi-workload-cluster/` (§16.2 / §16.3) что и workload —
просто с другими values:

* `cluster.name: "mgmt-1"` (из §8 `k8s_lab_management_cluster_name`);
* `clusterClass.name: "capn-mgmt"` — отдельный ClusterClass,
  позволяет mgmt и workload Cluster CR'ам сосуществовать в одном
  `capi-clusters` namespace до момента clusterctl move;
* `topology.controlPlane.replicas: 1`, `topology.workers.replicas: 2`
  (§8 + §2.12 mgmt-side replica policy + chart-required floor — см.
  ниже);
* `clusterNetwork.pods.cidrBlocks` / `services.cidrBlocks` — те же
  что у workload (Cluster CR'ы имеют independent clusterNetwork
  блоки; overlap на одной wire moot потому что каждый кластер —
  свой kube-proxy / CNI domain).

Установка идёт через `kubernetes.core.helm` напрямую в
`tests/molecule/e2e-local/converge.yml` против `.artifacts/mgmt.kubeconfig`
(который на этом этапе указывает на bootstrap k3s). После того как
helm install вернул control (chart's post-install hook
`api-proxy-attach` отработал, /livez ответил 200), на runner'е
материализуется `.artifacts/clusters/mgmt-1.kubeconfig` через
parse-and-rewrite (server URL → `https://<lxd_host>:<api-proxy-port>`,
`tls-server-name: kubernetes.default.svc`).

CNI Calico + MetalLB ставятся на mgmt-1 через те же
`charts/cni-calico/` + `charts/metallb/` + `charts/metallb-config/`
против `.artifacts/clusters/mgmt-1.kubeconfig`. Это требуется ДО
pivot'а потому что `clusterctl init` (запускаемый pivot ролью на
mgmt-1) ставит cert-manager + 4 CAPI/CAPN provider Deployments —
без pod networking они уйдут в crash-loop, `--wait-providers`
тайм-аутится.

Между CNI install и MetalLB install — explicit
`kubernetes.core.k8s_info` polling-task на все Nodes `Ready=True`
(см. §3.1 шаг 3 для rationale). Без поллинга MetalLB install с
`wait: true` тайм-аутится потому что Calico Installation CR
reconciliate'ится async после `helm install --wait` returnа.

Перед самим pivot'ом converge.yml гоняет helm tests на mgmt-1
(`capi-workload-cluster` cluster-ready hook + `cni-calico` Gate B
+ `metallb-config` Gate A) — гейт перед pivot'ом. Если mgmt-1 data
plane сломан, останавливаемся здесь, не на failed pivot'е.

**Worker count floor = 2.** `cni-calico` chart (§17.2) helm test
включает phase 6 «live pod-to-pod ICMP4+ICMP6 across workers» с
`requiredDuringScheduling pod-anti-affinity` — probe-a и probe-b
обязаны попасть на разные worker-ноды. На mgmt с 1 worker probe-b
застревает в `Pending` → helm test падает на gate. Поэтому §8
`k8s_lab_management_worker_count` default = `2`.

## 18.2. Role: `pivot_clusterctl_move`

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
   bootstrap kubeconfig stat. Always runs.
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

The role gates only on `pivot_clusterctl_move_enabled` (default
`true`); preflight always runs to surface misconfiguration. Pivot
mandatory in canonical flow §3 — there is no "MVP no-pivot" mode.

### Re-emit `mgmt.kubeconfig` after pivot

Right after `pivot_clusterctl_move` finishes (mgmt-1 is now the
self-hosted CAPI management cluster, but the runner-side
`.artifacts/mgmt.kubeconfig` still points at bootstrap k3s), the
e2e-local converge invokes `export_artifacts` a SECOND TIME with:

```yaml
- include_role: export_artifacts
  vars:
    export_artifacts_run_meta_chain: false
    export_artifacts_mgmt_kubeconfig_source: "{{ k8s_lab_opt_root }}/etc/pivot_clusterctl_move/mgmt.kubeconfig"
    export_artifacts_mgmt_api_server_url: ""
    export_artifacts_tfvars_enabled: false
```

This overwrites the runner-side `.artifacts/mgmt.kubeconfig` with
mgmt-1 creds in place. Same file path; different content. All
downstream consumers (TF workload fixtures, post-pivot helm
installs) keep using the same path. After `cleanup_bootstrap`
deletes the bootstrap LXC, the bootstrap creds are gone with the
cluster — there's no orphaned `bootstrap.kubeconfig` to clean.

`run_meta_chain: false` skips the bootstrap_capn_secret meta-dep
import (Phase 4 substrate is already up; running it again would
either be wasteful or would fail outright once the bootstrap LXC
is gone). The flag is consumed inside `meta/main.yml` via `when:`
on the dependency declaration.

### Bootstrap retirement: `cleanup_bootstrap`

Bootstrap deletion is owned by the existing `cleanup_bootstrap`
role (§19.1), not by `pivot_clusterctl_move`. The e2e-local
converge chains them in order:

```yaml
- include_role: pivot_clusterctl_move    # init + move + healthchecks
- include_role: export_artifacts         # re-emit mgmt.kubeconfig
  vars: { run_meta_chain: false, ... }
- include_role: cleanup_bootstrap        # delete bootstrap LXC + proxy
```

`cleanup_bootstrap` has no meta-deps by design (reverse-motion);
the substrate it needs (LXD daemon, `capi-lab` project) is already
up from the prior chain. Runner-side `.artifacts/mgmt.kubeconfig`
is **not** wiped here (`cleanup_bootstrap_remove_artifacts: false`
is the e2e-local default) — it has just been overwritten with
mgmt-1 creds and is the canonical mgmt kubeconfig going forward.

### No separate Molecule scenario

The role's own healthchecks (`tasks/healthchecks.yml`) re-assert the
post-pivot end state — providers Available on target, Cluster CR
moved, bootstrap source flushed — as a **mandatory part of every run**
(no `flow_control` toggle for healthchecks). Acceptance is therefore
covered by the role itself plus the post-pivot workload helm tests
in `tests/molecule/e2e-local/verify.yml` — there is no
`tests/molecule/pivot/` scenario.

## 18.3. Post-pivot workload creation

After pivot + cleanup_bootstrap + re-emit, `.artifacts/mgmt.kubeconfig`
points at self-hosted mgmt-1. Workload Cluster CRs are created on
mgmt-1 directly via the same `charts/capi-cluster-class/` +
`charts/capi-workload-cluster/` chains, with workload-topology
values:

* `cluster.name: "lab-default"` (from §8 `k8s_lab_workload_cluster_name`);
* `clusterClass.name: "capn-default"` — distinct from mgmt-1's
  `capn-mgmt`, so both ClusterClass CRs coexist in `capi-clusters`
  namespace on mgmt-1;
* `topology.controlPlane.replicas: 3`, `topology.workers.replicas: 2`
  (§8 reference deployment).

Two delivery paths, both consume the same charts:

1. **Inside `tests/molecule/e2e-local/` converge** — step 8 of the
   canonical sequence (§3.1). `kubernetes.core.helm` installs
   ClusterClass + Cluster CR + CNI + MetalLB on mgmt-1 directly.
   `verify.yml` runs helm tests + Gate A external curl + Nodes
   Ready assertion.
2. **`make deploy-workload`** (TF route, §16.6) — `terraform
   apply` on `tests/fixtures/terraform/workload-clusters/lab-default/`
   uses `mgmt_kubeconfig_path = .artifacts/mgmt.kubeconfig`
   (default), so it talks to whatever cluster the file points at.
   After e2e-local has run, that's self-hosted mgmt-1. Useful for
   spawning ADDITIONAL workloads on the existing mgmt-1 (second,
   third…) without re-running the full e2e-local cycle.

Cluster API docs cover the full bootstrap-and-pivot flow (init →
move → retire bootstrap; target mgmt must already have at least one
worker before move — satisfied by §18.1's worker_count=2 default).
([Cluster API][8])

[7]: https://main.cluster-api.sigs.k8s.io/clusterctl/commands/init.html?utm_source=chatgpt.com "init - The Cluster API Book"
[8]: https://cluster-api.sigs.k8s.io/clusterctl/commands/move?utm_source=chatgpt.com "move - The Cluster API Book"
