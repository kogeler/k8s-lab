Этот файл владеет §16: Phases 5 + 5.05 — CAPI topology delivery через
Helm charts из монорепы + export target kubeconfig'а на runner.
Нумерация §N сквозная по всем plan-файлам; перекрёстные ссылки вида
`§<номер>` валидны без указания имени файла — см.
`PLAN-stage1-common.md` header для полного file lineup. Атомарный
scope этого шарда — Helm-чарты `charts/capi-cluster-class/` и
`charts/capi-workload-cluster/`, их Terraform-обёртки, Makefile-
wrapper для `terraform apply`, и export kubeconfig'а первого
CAPI-created cluster'а на runner.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (Phases 5 + 5.05 CAPI topology via Helm) <-- этот файл
PLAN-stage1-4.md ................. §17      (Phases 5.1 + 5.2 + 5.3 Helm add-ons + in-cluster tests)
PLAN-stage1-5.md ................. §18      (Phases 6 + 7 pivot + workload clusters)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 meta: out-of-scope, self-review, recommendation)
```

---

# 16. Phases 5 + 5.05 — CAPI topology via Helm + kubeconfig export

## 16.1. Ownership и delivery model

Всё, что связано с CAPI topology первого workload-кластера (ClusterClass,
Kubeadm/CP/Config templates, LXC infrastructure templates, Cluster CR
instance, sidecar ConfigMap/Secret'ы для cluster-specific config),
доставляется **как Helm-чарты из монорепы** (`charts/capi-cluster-class/`
+ `charts/capi-workload-cluster/`), устанавливаемые Terraform-ом через
`hashicorp/helm` provider против bootstrap kubeconfig'а.

Разделение ответственности:

* **Controllers** (CAPI core + CABPK + KubeadmControlPlane + CAPN
  infrastructure + cert-manager) — принесены `bootstrap_clusterctl`
  через `clusterctl init --infrastructure incus` (§13.10). Phase 4
  закрыта; Phase 5 controllers не трогает и сама их не переустанавливает.
* **CRDs** (ClusterClass, Cluster, KubeadmControlPlaneTemplate,
  KubeadmConfigTemplate, LXCClusterTemplate, LXCMachineTemplate, etc.) —
  тоже принесены `clusterctl init`. Helm-чарты из §16.2..§16.3 **не
  содержат CRDs**, только CR-инстансы. Helm 3 игнорирует `crds/`-папку
  на upgrade, мы её и не создаём.
* **CR-данные** (всё выше) — single-owner: Helm-чарты этого репо. Нет
  `kubernetes_manifest`, нет `kubectl apply -f`, нет Ansible post-apply
  на CAPI-CR'ы.

`kubernetes` Terraform provider допустим только на read-side (data
lookups, status polling). Любой create/update/apply CR идёт через
`helm_release`.

## 16.2. Chart: `charts/capi-cluster-class/`

**Статус: выполнено в Step 10 (2026-04-24) — Phase 5 preparation. Real
`helm install` против bootstrap k3s с CAPI v1.12.5 + CAPN v0.8.5
зелёный: 6 CR'ов материализованы в `capi-system`, ClusterClass
получил `RefVersionsUpToDate=True`, `VariablesReady=True`,
`Paused=False` от CAPI controller'а; `helm uninstall` чистый.**

Содержит реусабельный CAPI topology-контракт для CAPN unprivileged
kubeadm path. Целевой API-surface зафиксирован на:

* CAPI core `cluster.x-k8s.io/v1beta2` (Cluster, ClusterClass);
* Kubeadm providers `controlplane.cluster.x-k8s.io/v1beta2` +
  `bootstrap.cluster.x-k8s.io/v1beta2`;
* CAPN `infrastructure.cluster.x-k8s.io/v1alpha2` (LXCClusterTemplate,
  LXCMachineTemplate).

Рендерится 6 CR'ов:

* `ClusterClass` — связывает infrastructure + controlPlane +
  workers/machineDeployments по `templateRef` (apiVersion + kind +
  name). Не содержит `clusterNetwork` — это поле Cluster CR и лежит
  в §16.3 чарте.
* `LXCClusterTemplate` — CAPN infrastructure. `secretRef.name` =
  §8 `k8s_lab_infrastructure_secret_name`. LXD project не является
  полем CR в CAPN v1alpha2 — scope лежит внутри identity Secret'а
  (см. §15.4 + §13.11). `loadBalancer` — обязательное поле CRD,
  ровно один режим из `{lxc,oci,ovn,kubeVIP,external}`; MVP default
  `{lxc: {}}` поднимает haproxy-LXC внутри того же LXD проекта.
  Substrate-required hardcoded: `unprivileged: true`,
  `skipDefaultKubeadmProfile: true`, `cloudProviderNodePatch: false`
  — не user-tunable (см. memory-правило
  "Chart-required values are hardcoded").
* `LXCMachineTemplate` ×2 (control-plane + worker) — image refs из
  §8 `k8s_lab_images_{controlplane,worker}` +
  `_fingerprint`; CAPN подставляет литерал `VERSION` в ref на machine
  kubernetes version. Profiles = substrate-required baseline
  (`capi-base` + `capi-controlplane` / `capi-worker`, owned by role
  `lxd_profiles` §13.6) + консумерские extras через
  `profilesExtra.*`. Devices — CAPN v1alpha2 требует `[]string` CSV
  формата (`"eth1,type=nic,network=br-ext6"`); опциональные overrides
  через `devicesExtra.*`. Substrate-required hardcoded:
  `instanceType: container`.
* `KubeadmControlPlaneTemplate` — чистый tuning-контракт:
  `featureGates`, `*ExtraArgs` (v1beta2 `[{name, value}]` формат,
  `minItems: 1` на CRD-уровне → эмитится только под non-empty
  override), `kubeletExtraArgs`, `preKubeadmCommands`,
  `postKubeadmCommands`. MVP default — пустой (kubeadm defaults).
* `KubeadmConfigTemplate` (worker) — аналогичный tuning-контракт
  для join-стороны.

### Name-versioning contract

CAPI webhook запрещает менять большинство полей `ClusterClass` и
`*Template` CR'ов после того, как на них сослался Cluster. Значит
любая правка `values.yaml` / шаблона = bump `Chart.yaml.version` =
новый набор объектов с новыми именами; старые Cluster CR-ы
продолжают указывать на прежний ClusterClass до контролируемого
переключения.

Реализация — Helm-helper `capi-cluster-class.classFullName`:

```gotemplate
{{- define "capi-cluster-class.versionSlug" -}}
{{- .Chart.Version | replace "." "-" | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "capi-cluster-class.classFullName" -}}
{{- printf "%s-%s" .Values.clusterClass.name
     (include "capi-cluster-class.versionSlug" .)
     | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

Точки в chart-версии заменяются на `-` для DNS-1123-subdomain-safe
имён (иначе стрикт downstream validators фейлят `0.1.0` в
`metadata.name`). Каждый сабобъект (`LXCClusterTemplate`,
`LXCMachineTemplate` CP/worker, KCPT, KCT) дополнительно получает
role-суффикс (`-infra`, `-cp`, `-md0`, `-kcp`, `-md0-bootstrap`)
поверх `classFullName`, так что bump chart-версии ротирует их
синхронно.

`capi-workload-cluster` чарт (§16.3) собирает имя ClusterClass'а в
`spec.topology.classRef.name` по той же `replace "." "-"` формуле
из общего values-блока (`clusterClass.chartVersion`). Terraform
обёртка (§16.4) экспортирует rendered name через
`cluster_class_name` output, и §16.5 модуль его пробрасывает в
workload чарт напрямую — фикстура не пересчитывает формулу.

Отдельной §8-переменной для revision'а не заводим — единственный
источник истины `Chart.yaml.version`, через `.Chart.Version` он
доступен обоим чартам.

### Values layout (public interface chart'а)

Правило «Chart-required values are hardcoded» (см. memory) держит
substrate-обязательные CR-поля вне `values.yaml`. Consumer не может
переопределить `unprivileged`, `skipDefaultKubeadmProfile`,
`cloudProviderNodePatch`, `instanceType`, apiVersion выборы, или
required-baseline profiles — всё это зашито в `templates/*.yaml`.

```yaml
# charts/capi-cluster-class/values.yaml — структурная схема
clusterClass:
  name: capn-default           # prefix; итоговое имя = "{name}-{chart-version-slug}"
kubernetes:
  version: ""                  # §8 k8s_lab_kubernetes_version
capn:
  infrastructureSecretName: "" # §8 k8s_lab_infrastructure_secret_name
images:
  controlplane:
    ref: "capi:kubeadm/VERSION"   # §8 k8s_lab_images_controlplane
    fingerprint: ""               # §8 k8s_lab_images_controlplane_fingerprint
  worker:
    ref: "capi:kubeadm/VERSION"   # §8 k8s_lab_images_worker
    fingerprint: ""               # §8 k8s_lab_images_worker_fingerprint
loadBalancer:                 # ровно один режим; см. values.yaml note
  lxc: {}
profilesExtra:                # добавляется поверх substrate baseline
  controlplane: []            # §8 k8s_lab_controlplane_profiles_extra
  worker: []                  # §8 k8s_lab_worker_profiles_extra
devicesExtra:                 # CAPN v1alpha2 []string CSV формат
  controlplane: []            # §8 k8s_lab_controlplane_devices_extra
  worker: []                  # §8 k8s_lab_worker_devices_extra
controlPlane:
  featureGates: {}
  apiServerExtraArgs: []      # v1beta2 [{name,value}] формат
  controllerManagerExtraArgs: []
  schedulerExtraArgs: []
  kubeletExtraArgs: []
  preKubeadmCommands: []
  postKubeadmCommands: []
worker:
  featureGates: {}
  kubeletExtraArgs: []
  preKubeadmCommands: []
  postKubeadmCommands: []
kubeProxy:
  nodePortAddresses: []       # §8 k8s_lab_kube_proxy_nodeport_addresses
```

`values.schema.json` ассертит required keys
(`clusterClass.name` matches DNS-1123, `kubernetes.version` matches
`^v\d+\.\d+\.\d+(\+.+)?$`, `capn.infrastructureSecretName` non-empty,
`loadBalancer` exactly 1 property, `devicesExtra.*` items match CSV
pattern) — chart fails на `helm template` стадии если wiring не
сошёлся из tfvars.

### CRD readiness guards

Каждый template-файл gate'ится по CAPI/CAPN API availability через
Helm-хелпер с `fail` семантикой (not silent skip):

```gotemplate
{{- define "capi-cluster-class.requireCAPN" -}}
{{- if not (.Capabilities.APIVersions.Has
       "infrastructure.cluster.x-k8s.io/v1alpha2/LXCClusterTemplate") -}}
{{- fail "CAPN v1alpha2 is not served. Run `clusterctl init --infrastructure incus` first." -}}
{{- end -}}
{{- end -}}
```

Три парных хелпера: `requireCAPI` (cluster.x-k8s.io/v1beta2),
`requireCAPN` (v1alpha2), `requireKubeadm` (controlplane + bootstrap
v1beta2). Если `clusterctl init` не завершился или не тот
infrastructure provider активен, `helm install` падает с
информативной ошибкой до стадии admission, а не тихо рендерит
zero CR'ов.

### Implementation notes (Step 10, 2026-04-24)

**Файлы чарта:** `Chart.yaml` (0.1.0, `appVersion: 0.8.5`), `values.yaml`,
`values.schema.json`, `templates/_helpers.tpl` (хелперы + API-gate
`fail` functions), `templates/cluster-class.yaml`,
`templates/lxc-cluster-template.yaml`,
`templates/lxc-machine-template-controlplane.yaml`,
`templates/lxc-machine-template-worker.yaml`,
`templates/kubeadm-control-plane-template.yaml`,
`templates/kubeadm-config-template-worker.yaml`.

**Deviations от initial §16.2 design (все зафиксированы против
verified CRD schemas CAPI v1.12.5 / CAPN v0.8.5):**

* CAPI storage version = `v1beta2`. `Cluster.spec.topology` в v1beta2
  использует `classRef.name` (не `class`), references в ClusterClass
  ходят через `templateRef` (не `ref`), а `*ExtraArgs` /
  `kubeletExtraArgs` — `[]{name,value}` list с `minItems: 1` на
  CRD-уровне (не `map[string]string`). Все рендер-пути эмитят блок
  только под non-empty override.
* CAPN v1alpha2 `LXCClusterSpec` **не имеет** поля `project` — scope
  задаётся внутри identity Secret'а (поле `project` в payload Secret'а
  из §13.11). Чарт не пытается передать project через CR.
* `installKubeadm` **не является полем CR** в CAPN v1alpha2.
  Install-kubeadm-at-runtime моделируется через
  `controlPlane.preKubeadmCommands` / `worker.preKubeadmCommands` в
  values, MVP default пустой (prebuilt `capi:kubeadm/*` образы).
* `LXCMachineSpec.devices` — `[]string` в CAPN CSV-формате
  (`"eth0,type=nic,network=my-net"`), не map. Values key =
  `devicesExtra.{controlplane,worker}` с pattern-check в
  `values.schema.json`.
* `LXCClusterTemplate.loadBalancer` — **REQUIRED field** на CRD-уровне
  с `exactly one of {lxc, oci, ovn, kubeVIP, external}`; "none" не
  принимается. MVP default = `{lxc: {}}` (haproxy-LXC инстанс внутри
  того же LXD проекта). Mode switching требует явного nullify
  default'а (`lxc: null`) из-за Helm deep-merge семантики — описано
  в values.yaml inline.
* `KubeadmControlPlaneTemplate.spec.template.spec.kubeadmConfigSpec` +
  все вложенные `clusterConfiguration.{apiServer,controllerManager,
  scheduler}`, `initConfiguration.nodeRegistration`,
  `joinConfiguration.nodeRegistration` — каждый имеет
  `minProperties: 1` на CRD-уровне (webhook validation, НЕ видна
  на `helm install --dry-run=server`). Шаблоны полностью опускают
  пустые блоки; substrate-required literal `format: cloud-config` в
  `kubeadmConfigSpec` удовлетворяет `minProperties` и одновременно
  зашивает правильный substrate-выбор (CAPN consumes cloud-init,
  ignition-path не поддерживается).

**Chart-required hardcoded baseline (memory rule
"Chart-required values are hardcoded"):** из public `values.yaml`
убраны и запечены в templates:

* `unprivileged: true`, `skipDefaultKubeadmProfile: true`,
  `cloudProviderNodePatch: false`, `instanceType: container`,
  `format: cloud-config` — по substrate- и MVP-policy (§2.8 / §3.1 /
  §13.6).
* LXD profile baseline (`capi-base` + `capi-controlplane` для CP,
  `capi-base` + `capi-worker` для worker) — consumer добавляет поверх
  через `profilesExtra.*`, но убрать базовые из CR не может.
* `apiVersion` выборы (CAPI `v1beta2`, CAPN `v1alpha2`) зашиты в
  шаблонах; API-readiness проверяется через
  `.Capabilities.APIVersions.Has` + `fail` хелперы.

**Cross-artifact правки, вызванные этим Step:**

* `bootstrap_capn_secret` (§13.11) — `lxd_project` и
  `internal_network_name` defaults теперь `bind`'ятся к §8 globals
  (`k8s_lab_project_name` / `k8s_lab_internal_network_name`). Причина
  — project scope нельзя передать через CR (см. deviation выше),
  значит Secret payload ОБЯЗАН атомарно трекать project-name global.
  Детали — §13.11 Step 10 расширения.
* `§8` (PLAN-stage1-common.md): `k8s_lab_install_kubeadm` удалён
  (не CR-поле), `k8s_lab_{controlplane,worker}_profiles` →
  `..._profiles_extra` (list of strings), `k8s_lab_{controlplane,
  worker}_devices` → `..._devices_extra` (list of CSV strings под
  CAPN v1alpha2 shape). `k8s_lab_infrastructure_secret_name` default
  выровнен на CAPN upstream `"incus-identity"`.
* `§2.10` (политика по образам нод) — install-kubeadm-at-runtime
  перекласифицирован с «CR-поля с default false» на
  «preKubeadmCommands extension point в KCPT/KCT» (поскольку
  `installKubeadm` не существует в CAPN v1alpha2 API).
* `§12.9` mitigation (CAPN pre-built images are evaluation-oriented)
  — bullet про `k8s_lab_install_kubeadm=true` переписан под
  `preKubeadmCommands` vector (тот же Semantik, правильное название).
* `§12.10` mitigation (CAPI CR immutability) — slug-формула
  `Chart.Version | replace "." "-"` зафиксирована явно в name-versioning
  pattern; `spec.topology.class` → `spec.topology.classRef.name` per
  v1beta2.
* `§16.3` / `§16.4` / `§16.5` / `§16.6` / `§16.7` — input-контракты и
  примеры main.tf обновлены под новый public interface чарта (без
  `project`, без `install_kubeadm`, profiles/devices с `_extra`
  суффиксом, `spec.topology.classRef.name` в Acceptance block'е §16.7).
* Memory rule `feedback_chart_required_values_hardcoded.md` — новая
  Helm-симметрия Ansible rule `feedback_required_values_hardcoded`;
  policy, которая обязывает substrate-required CR-поля запекать в
  templates, а не выставлять через `values.yaml`.

**Test evidence:**

* `helm lint` + `helm template --api-versions=...` под минимальные
  required values + богатый override (kubeVIP mode, featureGates,
  extraArgs, preKubeadmCommands, profilesExtra, devicesExtra CSV) —
  оба path'а зелёные; schema rejects known-bad overrides (missing
  required, invalid k8s-version pattern, empty loadBalancer,
  uppercase cluster name, non-CSV device entry).
* `helm install cluster-class-test charts/capi-cluster-class
  --namespace capi-system` против bootstrap kubeconfig'а — `STATUS:
  deployed`; все 6 CR'ов в `capi-system`, ClusterClass reconciled с
  тремя положительными conditions (`RefVersionsUpToDate`,
  `VariablesReady`, `Paused=False`). `helm uninstall` чистый, 0
  остаточных объектов.
* Первый real-install прогон поймал CRD-уровневые `minProperties: 1`
  нарушения, которые dry-run пропустил; фикс описан в deviations
  выше. Regression защищена тем, что `format: cloud-config` +
  полный omit пустых блоков — hardcoded в templates, не через
  values.
* `bootstrap_capn_secret` molecule полный цикл зелёный:
  `converge ok=283 changed=45 failed=0`,
  `idempotence ok=271 changed=0 failed=0`,
  `verify ok=14 changed=0 failed=0` (все 14 assertions про
  project/server/trust/TLS round-trip прошли, что подтверждает
  §13.11 Step 10 расширение).
* `export_artifacts` molecule полный цикл зелёный:
  `converge ok=298 changed=3 failed=0`,
  `idempotence ok=298 changed=0 failed=0`,
  `verify ok=16 changed=0 failed=0`;
  `.artifacts/bootstrap.kubeconfig` +
  `.artifacts/bootstrap.auto.tfvars.json` материализованы на runner'е.
* Workload-side E2E (реальный Cluster CR + LXC-ноды на substrate'е)
  остаётся scope §16.3 + §16.4 + §16.5 + §16.6 + §16.7 — в Step 10
  не прогонялся.

## 16.3. Chart: `charts/capi-workload-cluster/`

Содержит один Cluster CR (`cluster.x-k8s.io/v1beta2`), который
ссылается на ClusterClass из §16.2 по rendered name через
`spec.topology.classRef.name`, плюс `spec.clusterNetwork` dual-stack
CIDR'ы для pod/service (это поле — единственное место, где сетевые
CIDR'ы задаются декларативно в topology-режиме). Per-cluster
ConfigMap/Secret'ы для custom cloud-init extra-data чарт не
содержит — MVP baseline такого не требует.

### Values layout

```yaml
# charts/capi-workload-cluster/values.yaml — структурная схема
cluster:
  name: ""                     # §8 k8s_lab_workload_cluster_name
  namespace: capi-clusters     # fixed default; можно override в values
clusterClass:
  name: capn-default           # bind на §16.2 clusterClass.name
  chartVersion: ""             # bind на рендеренную версию §16.2 чарта
kubernetes:
  version: ""                  # §8 k8s_lab_kubernetes_version
topology:
  controlPlane:
    replicas: 2                # §8 k8s_lab_workload_controlplane_count
  workers:
    replicas: 2                # §8 k8s_lab_workload_worker_count
    deploymentName: md-0       # matches ClusterClass workers.machineDeployments[0].class
clusterNetwork:
  pods:
    cidrBlocks: []             # dual-stack: [v4, v6]
  services:
    cidrBlocks: []             # dual-stack: [v4, v6]
```

`spec.topology.classRef.name` рендерится по той же slug-формуле,
что §16.2 использует для `metadata.name` ClusterClass'а:

```gotemplate
{{- define "capi-workload-cluster.clusterClassName" -}}
{{- $slug := .Values.clusterClass.chartVersion | replace "." "-" | lower -}}
{{- printf "%s-%s" .Values.clusterClass.name $slug | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

Обе стороны координируют rotation через один знак
(`clusterClass.chartVersion` передаётся в оба helm_release из
Terraform-уровня — см. §16.5).

### Namespace

Cluster CR живёт в namespace `capi-clusters` (по умолчанию; тоже
доставляется этим же чартом через `kind: Namespace` с
`helm.sh/hook: pre-install`). Отделяет CR от `capi-system` /
`capn-system` / `kube-system` → чище cleanup, отдельный RBAC при
масштабировании на несколько workload-кластеров.

## 16.4. Module: `terraform/modules/capi_cluster_class/`

Тонкая обёртка над `helm_release` для §16.2 чарта. Inputs mirror
public interface чарта 1:1 — substrate-required CR-поля в чарт не
принимаются (они hardcoded), сюда приходят только tunables:

* `chart_path` (default `${path.module}/../../../charts/capi-cluster-class`);
* `chart_version` — прокидывается как `helm_release.version` и
  одновременно возвращается в `cluster_class_chart_version` output
  для §16.5 модуля;
* `namespace = capi-system` (куда CAPI controllers ожидают
  ClusterClass; override допустим);
* `class_prefix` — bind на `clusterClass.name` в чарте (default
  `capn-default`);
* `kubernetes_version` — §8 `k8s_lab_kubernetes_version`;
* `infrastructure_secret_name` — §8
  `k8s_lab_infrastructure_secret_name`;
* `image_controlplane_ref` + `image_controlplane_fingerprint`;
* `image_worker_ref` + `image_worker_fingerprint`;
* `load_balancer` (map — прокидывается как
  `loadBalancer` values блок; consumer может выбрать один из
  CAPN режимов, по умолчанию `{lxc = {}}`);
* `controlplane_profiles_extra` / `worker_profiles_extra` — list of
  strings, добавляются к substrate baseline (required-baseline
  hardcoded в чарте);
* `controlplane_devices_extra` / `worker_devices_extra` — list of
  strings в CAPN CSV формате (`"eth1,type=nic,network=..."`);
* `control_plane_tuning` / `worker_tuning` — объекты с
  `feature_gates`, `api_server_extra_args`,
  `controller_manager_extra_args`, `scheduler_extra_args`,
  `kubelet_extra_args`, `pre_kubeadm_commands`,
  `post_kubeadm_commands` (v1beta2 `[{name,value}]` list формат для
  `*_extra_args`);
* `kube_proxy_node_port_addresses` (list of strings).

Outputs:

* `cluster_class_name` — rendered `"{class_prefix}-{slug}"` по той же
  `replace "." "-"` slug-формуле, что хелпер чарта;
* `cluster_class_chart_version` — echo input'а для §16.5;
* `release_id` — для downstream `depends_on`.

`helm_release.wait = true` (default в `hashicorp/helm` 3.x) — ждёт
admission controller'ы + CAPI controller reconcile до ready. Без
этого гонка на первом apply: Cluster CR из §16.5 долетает до
ClusterClass-webhook'а до того, как тот полностью загружен.

`helm_release.atomic = true` — при partial fail откатывает release.
`force_update = false` (default) — не ломает SSA ownership CAPI
controller'а.

## 16.5. Module: `terraform/modules/capi_workload_cluster/`

Тонкая обёртка над `helm_release` для §16.3 чарта. Inputs:

* `chart_path` (default `${path.module}/../../../charts/capi-workload-cluster`);
* `cluster_name`, `cluster_namespace`;
* `kubernetes_version`;
* `cluster_class_name` и `cluster_class_chart_version` — обязательные
  входы, принимаются из output'ов §16.4 модуля;
* `controlplane_count`, `worker_count`;
* `pod_cidrs` (list, 2 элемента для dual-stack), `service_cidrs`
  (list, 2 элемента).

`depends_on = [helm_release.cluster_class]` на уровне module wiring
или через явный input `cluster_class_release_id`. `wait = true`,
`atomic = true`, `force_update = false`.

## 16.6. Test fixture: `tests/fixtures/terraform/workload-clusters/lab-default/capi`

Единственный MVP test root для Phase 5. Shape:

```
tests/fixtures/terraform/workload-clusters/lab-default/capi/
  providers.tf
  variables.tf
  main.tf
  outputs.tf
```

### providers.tf

```hcl
terraform {
  required_version = ">= 1.9"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"            # §8 k8s_lab_helm_provider_version
    }
    kubernetes = {                   # read-only: data lookups, status poll
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = var.k8s_lab_bootstrap_kubeconfig_path
  }
}

provider "kubernetes" {
  config_path = var.k8s_lab_bootstrap_kubeconfig_path
}
```

### variables.tf

Принимает `k8s_lab_*` ключи из §8. `.artifacts/bootstrap.auto.tfvars.json`
(emitted `export_artifacts` §13.12) auto-load'ится Terraform-ом и
заполняет их без ручного tfvars. Единственная переменная, которую
fixture **добавляет поверх**: `capi_cluster_class_chart_version`
(default tracks `charts/capi-cluster-class/Chart.yaml`; явный input
чтобы fixture мог pin'нуть конкретную ревизию без edit'а chart'а).

### main.tf

```hcl
module "cluster_class" {
  source = "../../../../../terraform/modules/capi_cluster_class"

  chart_path    = "${path.module}/../../../../../charts/capi-cluster-class"
  chart_version = var.capi_cluster_class_chart_version

  kubernetes_version             = var.k8s_lab_kubernetes_version
  infrastructure_secret_name     = var.k8s_lab_infrastructure_secret_name
  image_controlplane_ref         = var.k8s_lab_images_controlplane
  image_controlplane_fingerprint = var.k8s_lab_images_controlplane_fingerprint
  image_worker_ref               = var.k8s_lab_images_worker
  image_worker_fingerprint       = var.k8s_lab_images_worker_fingerprint
  load_balancer                  = { lxc = {} }
  controlplane_profiles_extra    = var.k8s_lab_controlplane_profiles_extra
  worker_profiles_extra          = var.k8s_lab_worker_profiles_extra
  controlplane_devices_extra     = var.k8s_lab_controlplane_devices_extra
  worker_devices_extra           = var.k8s_lab_worker_devices_extra
  kube_proxy_node_port_addresses = var.k8s_lab_kube_proxy_nodeport_addresses
}

module "workload_cluster" {
  source = "../../../../../terraform/modules/capi_workload_cluster"

  chart_path = "${path.module}/../../../../../charts/capi-workload-cluster"

  cluster_name                = var.k8s_lab_workload_cluster_name
  cluster_namespace           = "capi-clusters"
  kubernetes_version          = var.k8s_lab_kubernetes_version
  cluster_class_name          = module.cluster_class.cluster_class_name
  cluster_class_chart_version = module.cluster_class.cluster_class_chart_version
  controlplane_count          = var.k8s_lab_workload_controlplane_count
  worker_count                = var.k8s_lab_workload_worker_count
  pod_cidrs                   = [var.k8s_lab_workload_pod_cidr_v4,
                                 var.k8s_lab_workload_pod_cidr_v6]
  service_cidrs               = [var.k8s_lab_workload_service_cidr_v4,
                                 var.k8s_lab_workload_service_cidr_v6]

  depends_on = [module.cluster_class]
}
```

### outputs.tf

* `cluster_name`, `cluster_namespace` — для Phase 5.05 kubeconfig
  discovery (`<cluster_name>-kubeconfig` Secret в
  `<cluster_namespace>`);
* `kubeconfig_secret_name = "${var.k8s_lab_workload_cluster_name}-kubeconfig"`
  — CAPI kubeadm-CP контроллер автоматически создаёт этот Secret
  после того, как CP стал reachable.

## 16.7. Phase 5 — Apply CAPI topology

Orchestration — `make deploy-workload-capi` (target в корневом
`Makefile`):

```makefile
deploy-workload-capi:
	cd tests/fixtures/terraform/workload-clusters/lab-default/capi \
	  && terraform init -upgrade \
	  && terraform apply -auto-approve
```

Контракт:

* `terraform` предполагается **уже установленным** на runner'е (dev
  машина или CI-агент); Ansible/Phase 4 его не ставят;
* оператор / агент вызывает target вручную после того, как Phase 4
  зелёная и `.artifacts/bootstrap.kubeconfig` + `.artifacts/bootstrap.auto.tfvars.json`
  материализованы;
* целевой kubeconfig — bootstrap; CAPI controllers + CAPN живут там,
  они принимают ClusterClass + Cluster CR-ы и поднимают LXC-ноды
  workload-кластера в том же LXD substrate'е, что и bootstrap (project
  `capi-lab`).

Acceptance:

1. `helm_release.cluster_class` успешно применён: ClusterClass +
   все *Template'ы existуют в `capi-system` с именами
   `{prefix}-{chart-version}`; webhook их провалидировал.
2. `helm_release.workload_cluster` успешно применён: Cluster CR
   в `capi-clusters/<cluster-name>` с `spec.topology.classRef.name`
   указывающий на правильный ClusterClass-имя.
3. CAPI kubeadm-CP и CAPN infrastructure controllers подхватили
   Cluster CR, создали LXCCluster/LXCMachine'ы, CP-LXC-ноды запустились,
   kubeadm init на первой CP-ноде прошёл.
4. Через CAPN observer видно Ready=True на Cluster CR (Terraform
   wait through `kubernetes_resource` data block или `time_sleep` +
   `data.kubernetes_resources` polling — точный mechanism зафиксировать
   в impl-step'е).

## 16.8. Phase 5.05 — Export target kubeconfig на runner

Продолжение Ansible-роли `export_artifacts` (§13.12) через новую
task-file `tasks/mgmt_kubeconfig.yml` плюс public toggle
`export_artifacts_target_kubeconfigs_enabled` (default `false`; Phase
5.05 включает).

Когда включено:

* читает из bootstrap API список Secret'ов вида
  `<cluster>-kubeconfig` в namespace `capi-clusters` через
  `kubernetes.core.k8s_info` (server-side, нативный, без `kubectl`);
* для каждого кластера извлекает `data.value` (base64-encoded
  kubeconfig), декодирует, materialize'ит в
  `.artifacts/clusters/<cluster>.kubeconfig` с mode 0600 через
  `ansible.builtin.copy` + `delegate_to: localhost, become: false,
  run_once: true` (тот же pattern, что §13.12 уже использует для
  bootstrap kubeconfig'а);
* server URL в kubeconfig'е CAPI kubeadm-CP контроллер кладёт под
  control-plane endpoint, который в MVP = internal bridge-IPv4 CP-ноды
  (reachable изнутри VM / bootstrap LXC, но не с dev-машины);
* opt-in rewrite `clusters[].cluster.server` на runner-reachable URL
  через `export_artifacts_target_api_server_url` (один URL; multi-cluster
  case откладывается до Stage 2). Публикация API workload CP наружу —
  через LXD proxy device на CP-LXC, аналогично §15.5 для bootstrap;
  proxy-device wiring владеется §16.2 chart'ом через
  `LXCMachineTemplate.spec.instance.devices`, чтобы публикация была
  declarative-свойством ClusterClass'а, а не side-effect-ом Ansible.

Substrate-required значения (filenames, directory layout, file mode)
остаются в `export_artifacts` `vars/main.yml` под
`_export_artifacts_required_*` prefix (§13.12 контракт). Public defaults
расширяются двумя toggle'ами: `export_artifacts_target_kubeconfigs_enabled`
и `export_artifacts_target_api_server_url`.

Acceptance:

* `.artifacts/clusters/<workload-cluster>.kubeconfig` present на
  runner'е, mode 0600;
* `kubernetes.core.k8s_info kind=Node` через этот kubeconfig (с
  `delegate_to: localhost` внутри verify) возвращает все CP + worker
  ноды workload-кластера Ready (доказательство, что Phase 5.1 helm
  add-ons pass поедет);
* путь зафиксирован для §17 (Helm add-ons): fixture
  `tests/fixtures/terraform/workload-clusters/lab-default/addons`
  читает его через `k8s_lab_target_kubeconfig_path` tfvar (эмиттится
  `export_artifacts` в `.artifacts/bootstrap.auto.tfvars.json` на том
  же прогоне).

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
