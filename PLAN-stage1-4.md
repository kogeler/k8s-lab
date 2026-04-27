Этот файл владеет §17: Phases 5.1 + 5.2 + 5.3 — Terraform Helm
add-ons pass + in-cluster validation через Helm test hooks.
Нумерация §N сквозная по всем plan-файлам; перекрёстные ссылки
вида `§<номер>` валидны без указания имени файла — см.
`PLAN-stage1-common.md` header для полного file lineup. Атомарный
scope этого шарда — всё, что касается cluster add-ons layer поверх
уже существующего target kubeconfig (см. §16.8) плюс два connected
in-cluster gate'а (CNI viability и external L2 viability), которые
реализованы как Helm test hooks на соответствующих release'ах, а
не как отдельные Ansible/Terraform phases.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (Phases 5 + 5.05 CAPI topology via Helm)
PLAN-stage1-4.md ................. §17      (Phases 5.1 + 5.2 + 5.3 Helm add-ons + in-cluster tests)  <-- этот файл
PLAN-stage1-5.md ................. §18      (Phases 6 + 7 pivot + workload clusters)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 meta: out-of-scope, self-review, recommendation)
```

---

# 17. Phases 5.1 + 5.2 + 5.3 — Helm add-ons + in-cluster tests

Этот раздел группирует Helm add-ons module (§17.1), его test fixtures
(§17.2), контракт Helm test hook'ов которые реализуют acceptance
Gate A + Gate B из §6 (§17.3), и три phases: 5.1 (apply Helm add-ons
pass), 5.2 (CNI Helm test на первом Terraform-created cluster),
5.3 (MetalLB Helm test покрывающий external L2 acceptance).

Gate'ы реализованы как `helm.sh/hook: test` Job'ы внутри тех же chart
release'ов, которые ставят CNI/MetalLB. Single-tool Terraform→Helm
пайплайн; тестируют реальный data plane на real worker-нодах;
используют production-path LXD profiles + cloud-init.

## 17.1. Module: `modules/cluster_addons_helm`

**Статус: chart `charts/cni-calico/` (CNI-side)
выполнено в Step 13 (2026-04-26, version 0.2.0).** Local wrapper над
upstream `projectcalico/tigera-operator` v3.31.5 через `Chart.yaml`
`dependencies:`. Substrate-required hardcoded'ы в Installation CR
(template `templates/installation.yaml`):
* `cni.type: Calico`, `ipam.type: Calico` — chart-level invariant;
* `calicoNetwork.bgp: Disabled` — нет BGP infra на CAPN/LXD
  substrate'е;
* `calicoNetwork.linuxDataplane: Nftables` — native nf_tables, без
  iptables compat layer; пара с kube-proxy `mode: nftables` через
  KubeProxyConfiguration в charts/capi-cluster-class KCPT (§16.2
  Step 13). Calico docs формулируют это как контракт: "your
  cluster's kube-proxy must also be in nftables mode";
* `calicoNetwork.ipPools[*].encapsulation: VXLAN` — IPIP IPv4-only,
  BGP infra нет, VXLAN единственный dual-stack-capable mode;
* `calicoNetwork.ipPools[*].nodeSelector: all()` — single-tier лаба,
  per-pool node tagging не нужен;
* `controlPlaneReplicas: 2` — HA pair §2.12 contract для
  calico-kube-controllers + calico-apiserver (operator gives them
  2 replicas + built-in podAntiAffinity).

Subchart toggle'ы (`tigera-operator` dependency): `installation.
enabled: false` (рендерим свою Installation CR), `apiServer.
enabled: true` (нужен для projectcalico.org aggregated APIs),
`goldmane: false` / `whisker: false` (observability extras —
optional, off в лаб-footprint'е). Typha остаётся auto-deployed
operator'ом (он сам разруливает replicas — ~50 нод threshold для
auto-enable; в лабе на 5 нод typha запустится но не нагружает
apiserver значимо).

Helm test hook `templates/tests/cni-ready.yaml` — chart-level
acceptance драйвер (alpine + busybox `wget` upstream kubectl + 6
step'ов): tigera-operator Available → calico-system rollouts +
Pods Ready → workload Nodes Ready=True → dual-stack `podCIDRs`
per-Node → 2 ephemeral probe Pod'а (`k8s-lab-cni-probe-a/-b`) на
разных worker'ах через podAntiAffinity + nodeAffinity NotIn
control-plane → ICMP4/ICMP6 через `kubectl exec` от одного к
другому. Memory rules: `feedback_no_bitnami_images.md` (alpine +
busybox + dl.k8s.io kubectl wget), `feedback_test_artifact_naming.md`
(`k8s-lab-*` prefix для probe Pods).

**RBAC / hook-policy substrate-required choices (Step 13):**
* Test SA + ClusterRole + ClusterRoleBinding в
  `templates/tests/rbac.yaml` — **regular release resources**, НЕ
  `helm.sh/hook: test`. Hook-annotated не-Pod resources ломают
  `helm test --logs` non-zero exit'ом ("unable to get pod logs for
  <SA-name>"); helm walks the hook list and tries to fetch logs
  for each kind. SA/Role/Binding installed at `helm install` time,
  торнутся только на `helm uninstall` — RBAC scaffolding не
  ephemeral, тестовый Pod использует SA как стабильный mount-point.
  ClusterRole grants: `core/{nodes,namespaces}` (get,list),
  `core/pods` (get,list,create,delete), `core/pods/exec` (create),
  `apps/{deployments,daemonsets}` (get,list,watch — для kubectl
  rollout status / wait gating).
* Test Pod hook-delete-policy = `before-hook-creation` only, НЕ
  `before-hook-creation,hook-succeeded`. Race-condition между
  `Phase: Succeeded` и `helm test --logs` log-fetch step'ом — при
  коротком тесте (~15s) hook-succeeded реапает Pod до того как
  helm дойдёт до log pull, exit 1 c "pods not found". Test Pod
  выживает после Succeeded, реапается через before-hook-creation
  на следующем `helm test` или на `helm uninstall`. Workload-chart
  cluster-ready test (§16.3) использует full
  `before-hook-creation,hook-succeeded` потому что у него Phase 2
  ~20 минут — helm успевает streamить логи.

`charts/cni-probe/` (§17.3 separate probe chart) **не реализован
отдельно** в Step 13. Pod-to-pod ICMP / dual-stack `podCIDR` /
Node Ready acceptance свёрнуты в hook chart'а cni-calico —
aligned с паттерном charts/capi-workload-cluster's
`templates/tests/cluster-ready.yaml`. Если в будущем потребуется
CNI-agnostic probe (для swap на Cilium / kube-router), отдельный
`cni-probe` chart можно ввести как chart-independent; сейчас это
DRY-нарушение без пользы.

Step 13 НЕ включает Terraform module `modules/cluster_addons_helm/`
(пустой placeholder). MetalLB + cluster_addons_helm + Phase 5.1
fixture — следующий Step. Этот Status block документирует только
CNI chart side; всё остальное в §17.1 описано как design contract
для последующих шагов.

Тонкая Terraform-обёртка над набором `helm_release` resources для
cluster add-ons. Ставится **только после** того, как у runner есть
kubeconfig target-кластера (Phase 5.05 / §16.8).

Состав:

* **CNI** — один `helm_release`, chart адресуется через inputs
  `cni_chart_path` + `cni_chart_values` (см. «Extensibility» ниже).
  Shipped реализация в repo — `charts/cni-calico/`: локальный wrapper
  chart с `dependencies`-ссылкой на upstream
  `projectcalico/tigera-operator` ([26]) с pinned version из §8
  `k8s_lab_calico_chart_version`. Wrapper owns Installation CR +
  default IPPool'ы dual-stack (pod CIDR'ы из §8
  `k8s_lab_workload_pod_cidr_v4` / `k8s_lab_workload_pod_cidr_v6`);
* **MetalLB** (Step 14, 2026-04-27): два local wrapper chart'а как
  два `helm_release`-а — split необходим потому что upstream metallb
  0.15.3 ships CRDs as `templates/crds/` (regular templates), not the
  Helm `crds/` folder. A single-release wrapper bundling subchart +
  custom resources fails Helm 3 pre-apply validation with
  `no matches for kind "IPAddressPool"`:

  * `charts/metallb/` — minimal subchart-wrapper над upstream
    `metallb/metallb` 0.15.3 ([27]). Pin upstream version в Chart.yaml
    `dependencies:` block (§8 `k8s_lab_metallb_chart_version`).
    values.yaml хардкодит substrate-required toggles
    (`crds.enabled: true`, `frrk8s.enabled: false`,
    `speaker.frr.enabled: false`, `speaker.tolerateMaster: true`).
    Wrapper-owned templates: none — the chart exists only to ship
    upstream subchart with pinned values per memory rule
    "Chart-required values are hardcoded";
  * `charts/metallb-config/` (§8 `k8s_lab_metallb_wrapper_chart_path`)
    — wrapper-owned IPAddressPool + L2Advertisement CRs + helm test
    driver Pod (Gate A acceptance, §17.6). bind'ит §8
    `k8s_lab_metallb_vip_range_v6` + `k8s_lab_metallb_interface` +
    `k8s_lab_metallb_node_selector_labels`. No subchart deps. Installed
    SECOND so CRDs are registered first.
  * **HA pair contract §2.12 deviation specific to MetalLB**: upstream
    chart 0.15.3 does NOT expose `controller.replicas` — controller
    is single-replica by upstream design (allocates VIPs from the
    pool, no state partitioning). HA delivered through speaker
    DaemonSet (leader-elected per-VIP via memberlist).
* **Probe chart'ы** (§17.3):

  * Gate B (CNI viability, §17.5) — Step 13 решение: реализован
    inline в `charts/cni-calico/templates/tests/cni-ready.yaml`
    как `helm.sh/hook: test` Pod (см. §17.1 Status выше).
    Отдельный `charts/cni-probe/` НЕ shipped (был бы dry-нарушение
    при single shipped CNI implementation). Если придёт CNI-swap
    кандидат и появится потребность в CNI-agnostic probe'е,
    cni-probe вводится как chart-independent;
  * Gate A (external L2 viability, §17.6) — Step 14 решение:
    реализован inline в `charts/metallb-config/templates/tests/`
    (rbac.yaml + metallb-vip.yaml). Отдельный
    `charts/metallb-probe/` НЕ shipped. Symmetric to cni-calico
    decision: единственная shipped реализация L2-mode acceptance
    живёт прямо у chart'а её владельца.

Все upstream-chart'ы приходят через **локальные wrapper chart'ы** этого
repo (dependencies в `Chart.yaml` → upstream), не напрямую через
remote `chart = "<url>"`. Это даёт: local-testable chart shape
(`helm template` без сети), unified version pin в §8, возможность
накладывать value-patches на upstream без раздвоения source control
в repo.

### Extensibility для CNI

Module **не содержит** branch-логики по выбору CNI (`if var.cni ==
"calico"` и т.п.). Интерфейс один:

```hcl
variable "cni_chart_path"   { type = string }
variable "cni_chart_values" { type = any, default = {} }
```

Fixture (§17.2) передаёт `cni_chart_path =
"${path.module}/../../../../../charts/cni-calico"` для дефолтного
Calico-пути. Swap на другой CNI (Cilium, kube-router, что угодно)
— добавить соответствующий wrapper chart в `charts/cni-<whatever>/`,
написать для него values, поменять input в fixture; код модуля и
наших default'ов не трогается. Нет toggle-flag'а в §8, нет
alternative-path bundle'а в repo.

Provider contract для CNI chart'а (любой реализации, не только Calico):

* chart должен владеть IPAM-конфигурацией dual-stack — потребляет
  те же §8 `k8s_lab_workload_pod_cidr_v4` / `_v6`, что §16.2
  ClusterClass;
* release лежит в namespace, который chart сам создаёт (для Calico
  baseline — `tigera-operator` + `calico-system`); module не
  хардкодит namespace;
* HA replica contract §2.12: multi-replica-capable Deployments
  должны ехать с `replicas: 2 + podAntiAffinity` по
  `kubernetes.io/hostname`. Для Calico (Step 13) это
  satisfied через `Installation.spec.controlPlaneReplicas: 2` —
  operator драйвит calico-kube-controllers + calico-apiserver на
  2 реплики с встроенным podAntiAffinity'ом. Calico typha остаётся
  auto-managed operator'ом (auto-enable threshold ~50 нод); на
  лабе он запускается без явного toggle, не считается частью
  HA-pair contract'а.

Контракт модуля в целом:

* single owner CNI installation, MetalLB + config CR-ов, probe
  Job'ов. Вне этого модуля никто CR-ы add-on'ов в target cluster не
  льёт;
* `kube-proxy` policy остаётся Terraform-owned, но задаётся через
  kubeadm/bootstrap path в §16.2 ClusterClass (не через Helm add-ons);
* Helm add-ons pass intentionally отделён от CAPI topology pass
  (§16) — у них разные target-кластеры (`bootstrap` vs `workload`) и
  разные helm-provider wiring'и.

## 17.2. Test fixture — Helm add-ons

Единственный MVP test root для Phase 5.1+.

### `tests/fixtures/terraform/workload-clusters/lab-default/addons`

Shape:

```
tests/fixtures/terraform/workload-clusters/lab-default/addons/
  providers.tf
  variables.tf
  main.tf
  outputs.tf
```

**providers.tf:**

```hcl
provider "helm" {
  kubernetes {
    config_path = var.k8s_lab_target_kubeconfig_path  # Phase 5.05 output
  }
}
provider "kubernetes" {
  config_path = var.k8s_lab_target_kubeconfig_path
}
```

`.artifacts/bootstrap.auto.tfvars.json` эмиттит
`k8s_lab_target_kubeconfig_path = .artifacts/clusters/<workload>.kubeconfig`
на том же прогоне `export_artifacts`, когда включён §16.8 `tasks/
mgmt_kubeconfig.yml` — TF auto-load'ит файл и заполняет input без
ручного tfvars.

**main.tf:**

* `module "cluster_addons" { source = "../../../../../terraform/modules/cluster_addons_helm" ... }`;
* `cni_chart_path = "${path.module}/../../../../../charts/cni-calico"`
  — дефолтный Calico-путь; swap на другой wrapper = правка этой
  строки;
* `cni_chart_values` — dict с dual-stack CIDR'ами (§8
  `k8s_lab_workload_pod_cidr_v4` / `_v6`) и любыми chart-specific
  overrides;
* плоский проброс §8 `k8s_lab_*` ключей для MetalLB (VIP range,
  interface, node-selector labels) и probe address;
* единственный `depends_on` — тривиально, module изнутри сам
  секвенсит `cni → metallb → probe` через `depends_on`-ы между
  `helm_release`-ами.

## 17.3. Helm test hooks contract (CNI + external L2 validation)

Acceptance Gate A (external L2) и Gate B (CNI) реализуются как
Helm test Job'ы с annotation `helm.sh/hook: test`, упакованные в
wrapper chart'ы (`charts/cni-probe/`, `charts/metallb-probe/` — см.
§7 repo layout). Chart'ы — локальные в этом repo, ссылаются из
Terraform `helm_release` по relative path:
`chart = "${path.module}/../../../../../charts/cni-probe"`.
Запуск — `helm test <release>` после `terraform apply`, обёрнутый в
Terraform `null_resource` с `local-exec` provisioner'ом, чтобы
результат теста влиял на состояние `terraform apply`.

### Wrapper chart layout

Каждый probe chart содержит:

```
charts/<probe-name>/
  Chart.yaml
  values.yaml
  values.schema.json
  templates/
    rbac.yaml          # ServiceAccount + ClusterRole + ClusterRoleBinding
    job-test.yaml      # helm.sh/hook: test Job spec
    _helpers.tpl       # name/label helpers
```

Chart ставится тем же Terraform Helm add-ons pass'ом (§17.4) как
отдельный `helm_release` рядом с основным CNI/MetalLB release'ом
(зависимость управляется через `depends_on` на Terraform-уровне).

### Шейп Job'ов

**CNI probe Job (Phase 5.2, §17.5) — `charts/cni-probe/`:**

* `kind: Job`, `metadata.annotations."helm.sh/hook": test`,
  `helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded`;
* `spec.template.spec.tolerations` — допускаем control-plane taint'ы
  для flexibility;
* `spec.template.spec.serviceAccountName: cni-probe-sa` (chart
  создаёт ServiceAccount + RoleBinding — details в «RBAC» ниже);
* Pod 1 (readiness checker): `kubectl get nodes -o
  jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'`
  через `kubectl` image (`bitnami/kubectl:<k8s_version>` или
  equivalent); ассертит все ноды `True`;
* `parallelism: 2` + `podAntiAffinity` по `kubernetes.io/hostname`
  + `nodeSelector` на worker-ноды → 2 Pod'а на разных worker'ах
  ping'ают друг друга по Pod IP (pod-to-pod reachability). Pod IP
  discovery через downward API: `env: - name: PEER_IP valueFrom:
  fieldRef: fieldPath: status.podIP` + sidecar-Service с headless
  resolution;
* Pod также создаёт ClusterIP Service (через `kubectl apply`) и
  ping'ает его VIP — Service networking coverage.

**MetalLB probe Job (Phase 5.3, §17.6) — `charts/metallb-probe/`:**

* `kind: Job`, `metadata.annotations."helm.sh/hook": test`,
  `helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded`;
* `spec.template.spec.hostNetwork: true` — Pod видит eth1
  worker-нод'ы напрямую, что необходимо для теста L2-уровня
  external segment'а;
* `spec.template.spec.dnsPolicy: ClusterFirstWithHostNet` — чтобы
  Service DNS продолжал работать при hostNetwork;
* **`securityContext.capabilities.add: [NET_RAW]`** — `ping6`
  требует `CAP_NET_RAW` для raw ICMPv6 socket'а; без этого Job
  падает с `Lacking privilege for raw socket`. `NET_ADMIN` НЕ
  нужен (мы только читаем, не меняем);
* `nodeSelector` или worker-node affinity (не controlplane);
* `parallelism: 2` + anti-affinity по `kubernetes.io/hostname` →
  2 Pod'а на разных worker'ах;
* каждый Pod (image с `iproute2` + `iputils-ping`, например
  `alpine` или собственный `ghcr.io/<org>/metallb-probe:vX`):
  1. читает локальный MAC eth1 через `ip -j link show eth1 | jq`
     (IFNAME приходит из chart values `probe.ifname`);
  2. читает локальный global IPv6 eth1 (`ip -j -6 addr show eth1`);
  3. peer'а обнаруживает через headless Service resolution (chart
     создаёт Service + ENDPOINTSLICE на Pod'ах Job'а);
  4. ping6'ит peer's global IPv6 через eth1;
  5. ping6'ит `probe.address` через eth1;
* probe address приходит через chart values (`probe.address`),
  биндится из §8 `k8s_lab_external_probe_address`. Полная схема
  проброса — в subsection «Probe address flow».

### RBAC

CNI probe нуждается в доступе к Node/Pod/Service API:

```yaml
# charts/cni-probe/templates/rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cni-probe-sa
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ include "cni-probe.fullname" . }}
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
rules:
  - apiGroups: [""]
    resources: ["nodes", "pods", "services"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["create", "delete"]    # для Service networking проверки
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ include "cni-probe.fullname" . }}
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
subjects:
  - kind: ServiceAccount
    name: cni-probe-sa
    namespace: {{ .Release.Namespace }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ include "cni-probe.fullname" . }}
```

MetalLB probe нуждается только в peer discovery через собственный
headless Service — ClusterRole на чтение Endpoints/EndpointSlice:

```yaml
rules:
  - apiGroups: ["discovery.k8s.io"]
    resources: ["endpointslices"]
    verbs: ["get", "list"]
```

Все RBAC-объекты несут тот же `helm.sh/hook: test` annotation, что
и Job — чтобы они создавались/удалялись синхронно с test lifecycle.

### Probe address flow

Путь `k8s_lab_external_probe_address` из §8 глобала до `ping6`
argument'а внутри Job'а:

1. **Shared inventory** (`tests/molecule/shared/inventory/group_vars/k8slab_host.yml`
   для local harness; real production inventory — в consumer repo):
   ```yaml
   k8s_lab_external_probe_address: "2001:db8:42:100::1"
   ```
2. **Terraform tfvars** (`.artifacts/bootstrap.auto.tfvars.json`,
   эмиттится ролью `export_artifacts` §15.6 через вариант в §8
   `k8s_lab_*` контракте):
   ```json
   { "k8s_lab_external_probe_address": "2001:db8:42:100::1" }
   ```
3. **Terraform fixture root** (`tests/fixtures/terraform/.../addons/variables.tf`):
   ```hcl
   variable "k8s_lab_external_probe_address" { type = string }
   ```
4. **`helm_release` values block** (`.../addons/main.tf`):
   ```hcl
   resource "helm_release" "metallb_probe" {
     name       = "metallb-probe"
     chart      = "${path.module}/../../../../../charts/metallb-probe"
     namespace  = "metallb-system"
     values = [yamlencode({
       probe = {
         address = var.k8s_lab_external_probe_address
         ifname  = "eth1"
       }
     })]
     depends_on = [helm_release.metallb]
   }
   ```
5. **Chart values.yaml** (`charts/metallb-probe/values.yaml`):
   ```yaml
   probe:
     address: ""      # required, no safe default
     ifname:  "eth1"
   ```
6. **Job template** (`charts/metallb-probe/templates/job-test.yaml`):
   ```yaml
   env:
     - name: PROBE_ADDRESS
       value: {{ .Values.probe.address | quote }}
     - name: PROBE_IFNAME
       value: {{ .Values.probe.ifname | quote }}
   command: ["/bin/sh", "-c"]
   args: ["ping6 -c 3 -W 5 -I $PROBE_IFNAME $PROBE_ADDRESS"]
   ```
7. **Pod runtime:** `ping6 -c 3 -W 5 -I eth1 2001:db8:42:100::1` —
   фактический тест L2 reachability.

`values.schema.json` в chart'е валидирует `probe.address` как
non-empty string matching IPv6 regex, чтобы ошибка миссинговой
переменной детектилась на `helm template` стадии, а не во время
rollout'а Job'а.

## 17.4. Phase 5.1 — Helm add-ons pass

Orchestration — `make deploy-workload-addons` (target в корневом
`Makefile`):

```makefile
deploy-workload-addons:
	cd tests/fixtures/terraform/workload-clusters/lab-default/addons \
	  && terraform init -upgrade \
	  && terraform apply -auto-approve
```

Контракт:

* оператор / агент вызывает target вручную после того, как Phase 5
  (§16.7) и Phase 5.05 (§16.8) зелёные и
  `.artifacts/clusters/<workload>.kubeconfig` материализован;
* `hashicorp/helm` provider pinned в §8 `k8s_lab_helm_provider_version`;
* CNI ставится из `charts/cni-calico/` (wrapper над
  `projectcalico/tigera-operator`), Installation CR dual-stack с
  IPPool'ами из §8 `k8s_lab_workload_pod_cidr_v4` / `..._v6`;
  swap на другую CNI-реализацию — через `cni_chart_path` input в
  module (§17.1), не toggle;
* MetalLB ставится из upstream `metallb/metallb` + локальный
  `charts/metallb-config/` с IPAddressPool / L2Advertisement;
* **HA replica contract (§2.12)** на workload-кластере: каждый
  multi-replica-capable Deployment / StatefulSet → `replicas: 2` с
  antiaffinity по `kubernetes.io/hostname`. Calico
  `calico-kube-controllers` + `calico-apiserver` через
  `Installation.spec.controlPlaneReplicas: 2` (operator gives them 2
  + built-in podAntiAffinity). DaemonSet-ы (MetalLB speaker, Calico
  node) сами получают по одной реплике на worker — отдельный
  override не нужен. **MetalLB controller — explicit deviation
  from §2.12** (Step 14): upstream `metallb` chart 0.15.3 NOT exposes
  `controller.replicas` (controller is a singleton by upstream
  design; HA delivered through speaker DS leader-election per VIP
  via memberlist gossip);
* `helm_release.wait = true` + `atomic = true` на всех release'ах;
  `depends_on`-цепочка внутри `cluster_addons_helm` module'а (§17.1):
  CNI → MetalLB → probe-chart'ы.

Acceptance:

* все helm_release'ы applied на workload-кластер без ошибок;
* повторный `terraform apply / plan` — no-op;
* **HA pair contract (§2.12):** для каждого Deployment/StatefulSet с
  replicas≥2 ассерт'ятся `status.readyReplicas == status.replicas` и
  `status.availableReplicas == status.replicas`; пара Pod'ов реально
  на двух разных worker-нодах (`spec.nodeName` уникален); для
  leader-elected компонентов (MetalLB controller, cert-manager если
  есть) ровно один holder lease, второй pod в standby.

## 17.5. Phase 5.2 — CNI Helm test

**Статус (Step 13, 2026-04-26): chart-side end-to-end зелёный**
через `tests/molecule/e2e-local/` Molecule сценарий (см. §17.5
Step 13 acceptance status block ниже за full evidence). Phase 5.2
= `helm test cni-calico` на workload-кластере, чарт и hook'и
shipped (§17.1 Status). Полный end-to-end через Terraform fixture
(§17.4) — следующий Step (требует TF module
`cluster_addons_helm` + Phase 5.1 fixture, не реализованы в Step 13).

CNI release `cni-calico` несёт `helm.sh/hook: test` Pod из своего
templates/tests/cni-ready.yaml (§17.1 Status / §17.3 Step 13
Folded-in note). Phase 5.2 — это `helm test cni-calico` после
`terraform apply` (или после `helm install` напрямую в bring-up'е).

Сделать:

* CNI delivered Terraform-ом через `cni_chart_path` wrapper chart
  (§17.4 / §17.1 — default `charts/cni-calico/`);
* test hook (Pod) валидирует CNI viability на dual-stack: Calico
  Pods Ready, workload Nodes Ready=True, dual-stack `podCIDRs`
  per-Node, pod-to-pod ICMP4/ICMP6 across two workers;
* privileged LXC как workaround CNI-проблем запрещён (§2.8). Если
  Gate B фейлит — это сигнал, что CNI-реализация несовместима с
  unprivileged LXC substrate'ом; решение о swap'е CNI на другой
  wrapper chart (новый `charts/cni-<whatever>/`) — отдельный дизайн-
  step, не автоматический toggle внутри прогона.

Acceptance:

* workload cluster usable с установленным CNI;
* CNI helm test (`cni-calico-test-cni-ready` Pod) завершается exit=0
  на dual-stack baseline;
* результат зафиксирован как chart/contract decision, не ad hoc test
  note.

### Step 13 acceptance status (2026-04-26)

End-to-end зелёный на свежем workload-кластере, провизионированном
через ClusterClass 0.5.0 (kube-proxy `mode: nftables` baked
declarative-style at kubeadm init, см. §16.2 Step 13). Прогон
последовательностью `make clean-local` → bump VM RAM 6 → 12 GB →
`make up` → `make -C tests/molecule e2e-local-vagrant-converge` →
`make -C tests/molecule e2e-local-vagrant-verify`:

* converge — `failed=0 ok=307 changed=4`. Цепочка задач: substrate
  + bootstrap k3s (existing roles) → ClusterClass 0.5.0 + workload-
  cluster 0.5.0 (existing helm tasks) → helm CLI install on VM,
  Chart.yaml slurp, `helm dependency update` + `helm package` на
  runner'е, copy .tgz на VM, poll `<cluster>-kubeconfig` Secret в
  bootstrap, materialize workload kubeconfig в
  `/opt/capi-lab/etc/<cluster>.kubeconfig` на VM, `helm install
  cni-calico` на VM (workload API runner-нереachable — обязан
  запускаться на VM). Все chart helm tasks через
  `kubernetes.core.helm`, никаких shell для install pipeline'а.
* verify — `failed=0 ok=14 changed=4`. Workload-chart `helm test`
  10-фазный (см. §16.3 Step 12 расширения) → `cp=3/3 worker=2/2
  ALL TOPOLOGY CHECKS PASSED`, `classRef=capn-default-0-5-0`,
  AVAILABLE=True. cni-calico `helm test` 6-фазный → `Phase:
  Succeeded`: tigera-operator Available, calico-node DaemonSet +
  calico-kube-controllers Deployment rolled out, все Pods в
  calico-system Ready, все 5 workload Nodes Ready=True, dual-
  stack `podCIDRs` per-Node, dual-stack ICMP4/ICMP6 между
  ephemeral probe Pod'ами на разных worker-нодах через `kubectl
  exec`. Snapshot tasks (CAPI snapshot, workload kubeconfig
  exporter, in-cluster nodes snapshot Pod) — все прошли.

Chart-level live evidence на freshly-bootstrapped кластере:
kube-proxy ConfigMap содержит `mode: nftables` +
`conntrack.{maxPerCore: 0, min: 0}` напрямую от kubeadm init (без
ConfigMap patch'ей), все 5 kube-proxy Pods Running 0 restarts —
архитектурный declarative path работает clean без mid-flight
conntrack disruption.

Step 13 closing note про lab-VM RAM: 6 GB RAM Vagrantfile-baseline
не хватало под full workload (bootstrap k3s LXC + 5 workload LXC
+ haproxy LB LXC + Calico add-ons), kswapd thrash → OOM-related
LXD daemon transaction failures + apiserver flap. Bumped 6144 →
12288 MB (env-override `K8SLAB_MEM_MB`), `free=11Gi load<5` после
полной цепочки. Inline rationale в `tests/vagrant/debian13/
Vagrantfile`.

## 17.6. Phase 5.3 — MetalLB Helm test (covers external L2 acceptance)

**Статус (Step 14, 2026-04-27): chart-side end-to-end зелёный** через
`tests/molecule/e2e-local/` Molecule сценарий — chart-side `helm test
metallb-config` 8-фазный + verify-side external HTTP curl с VM,
оба зелёные на свежем кластере. См. §17.6 Step 14 acceptance status
block ниже за full evidence. Phase 5.3 = два artifact'а, оба shipped
(§17.1 / §17.4): pair of helm releases + verify-side curl in
Molecule. Полный end-to-end через Terraform fixture (§17.4) — следующий
Step (требует TF module `cluster_addons_helm` + Phase 5.1 fixture, не
реализованы в Step 14).

MetalLB delivery — два local wrapper chart'а как два helm release'а
(§17.1):

1. `charts/metallb/` ставится первым (subchart wrapper над upstream
   `metallb/metallb` 0.15.3; CRDs + controller + speaker DS;
   substrate-required toggles `crds.enabled=true`,
   `frrk8s.enabled=false`, `speaker.frr.enabled=false` в values.yaml);
2. `charts/metallb-config/` ставится вторым (IPAddressPool +
   L2Advertisement + helm test driver Pod; subchart-free).

Two-release split rationale: upstream metallb 0.15.3 ships CRDs as
regular `templates/crds/` (sub-dependency), not the Helm `crds/`
folder mechanism. A single-release wrapper bundling CRDs + custom
resources fails Helm 3 pre-apply manifest validation with
`no matches for kind "IPAddressPool" in version "metallb.io/v1beta1"`.
Splitting into two releases registers CRDs first, then reconciles
CRs against an already-live `metallb.io` API.

Phase 5.3 acceptance has two halves (Gate A criteria — §6):

* **chart-side helm test hook** (driver Pod, 8 phases in-cluster) —
  proves controller Available, speaker DS rolled out, IPAddressPool +
  L2Advertisement reconciled, demo Service got VIP from pool, demo
  backend reachable via VIP through kube-proxy nftables DNAT
  (non-hairpin: probe runs from driver Pod, not from a backend Pod —
  Calico's default veth filter drops backend-to-self-via-Service);
* **verify-side external curl** (Molecule e2e-local Verify task on
  the VM, NOT delegate_to runner) — reads VIP via
  `kubernetes.core.k8s_info` against workload kubeconfig, then
  `ansible.builtin.uri url=http://[<VIP>]:80/` from the VM. Packet
  path: VM → `ext6-ra-peer` (`2001:db8:42:100::1/64`) → `br-ext6`
  → eth1 speaker leader → kube-proxy DNAT → backend Pod → 200 OK
  body `ok`. This closes Gate A by proving production-path L2
  reachability from outside the cluster.

**HA pair contract §2.12 — MetalLB-specific deviation:** upstream
`metallb` chart 0.15.3 does NOT expose `controller.replicas`
(controller is a singleton by upstream design — allocates VIPs from
the pool and validates CRs, no state partitioning). HA on this chart
is delivered through the **speaker DaemonSet** (one replica per
worker, leader-elected per-VIP via memberlist gossip). This is
sufficient for the failover guarantee §2.12 cares about: when a
speaker leader fails, another speaker re-announces the VIP within
seconds. Acceptance criteria for §17.6 therefore omits the
`controller.replicas==2 + podAntiAffinity` clause from the workload
cluster acceptance template (§17.4) — speaker DaemonSet rollout +
`metallb-controller` Deployment Available is the §2.12 floor for
MetalLB on this chart version.

Demo backend image choice — `nginx:1.27-alpine` (Service
`ipFamilies: [IPv6]` requires v6-listening backend; alpine's base
busybox lacks `httpd` applet, and nginx default config has only
`listen 80;` v4 — chart driver splices `listen [::]:80;` next to
the v4 listen via inline `sed`, keeping the rest of nginx default
intact). Memory rule "Never use bitnami images" — nginx Inc.
official image, not bitnami.

Acceptance:

* both helm releases applied without errors;
* Service `status.loadBalancer.ingress[0].ip` ∈ `pool.rangeV6`;
* chart-side `helm test metallb-config` exits 0 (8/8 phases green);
* verify-side `ansible.builtin.uri` returns HTTP 200 with body
  matching `^ok` from the VM;
* §2.12 HA contract satisfied via speaker DS (controller deviation
  documented above).

### Step 14 acceptance status (2026-04-27)

End-to-end зелёный на свежем workload-кластере, провизионированном
через ClusterClass 0.5.0 + workload-cluster 0.5.0 + cni-calico
0.2.0 + metallb 0.1.0 + metallb-config 0.1.3. Прогон последовательностью
`make -C tests/molecule e2e-local-vagrant-converge` →
`make -C tests/molecule e2e-local-vagrant-verify`:

* converge — `failed=0 ok=318 changed=7`. Цепочка задач: existing
  substrate + bootstrap + ClusterClass + workload + Calico → новый
  блок MetalLB delivery (read Chart.yaml → helm dep update + helm
  package on runner → copy .tgz to VM → helm install on VM via
  `kubernetes.core.helm`). Два helm install'а: upstream metallb
  wrapper (`metallb-system` namespace, `create_namespace: true`),
  затем metallb-config wrapper (`create_namespace: false` — namespace
  уже создан upstream wrapper'ом).
* verify — `failed=0 ok=20 changed=5`. Три helm test'а зелёные:
  workload chart (10 фаз), cni-calico (6 фаз), metallb-config (8 фаз).
  Compact-state debug строка:
  `metallb VIP=2001:db8:42:100::200 external_status=200`. Полный
  Gate A path: external curl от VM → `ext6-ra-peer` → bridge
  `br-ext6` → eth1 speaker leader → kube-proxy → backend nginx Pod
  → 200 OK body "ok\n".

Memory rules применённые в Step 14:
* `feedback_chart_required_values_hardcoded.md` — IPAddressPool /
  L2Advertisement substrate-required fields в шаблонах
  (interfaces=eth1, nodeSelectors excludes control-plane);
* `feedback_no_bitnami_images.md` — alpine для driver Pod, nginx
  для backend (нет bitnami);
* `feedback_test_artifact_naming.md` — `k8s-lab-metallb-demo-*`
  prefix для демо Deployment/Service;
* `feedback_pause_before_role_test.md` — chart code сделан, тестирование
  на live кластере выявило два separate fixes (nginx v4-only listen,
  hairpin avoidance), оба применены в chart 0.1.x bumps;
* `feedback_plan_is_fallible.md` — single-wrapper precedent
  (cni-calico) пытался apply здесь, но архитектура metallb subchart
  CRDs (templates/crds/, не Helm crds/) требует two-release split.
  PLAN §17.1 был прав в исходном дизайне, повторно подтверждено
  через runtime evidence (Helm 3 pre-apply validation fails on
  bundled CRDs+CRs).

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
