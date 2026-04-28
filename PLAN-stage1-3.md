Этот файл владеет §16: Phase 5 — единый workload cluster delivery
module. Нумерация §N сквозная по всем plan-файлам; перекрёстные
ссылки вида `§<номер>` валидны без указания имени файла — см.
`PLAN-stage1-common.md` header для полного file lineup. Атомарный
scope этого шарда — два уже shipped Helm-чарта
(`charts/capi-cluster-class/` + `charts/capi-workload-cluster/`),
один Terraform module `workload_cluster/` который ставит весь
functional workload-кластер от ClusterClass до cluster add-ons +
acceptance helm test'ов одним `terraform apply`, один test fixture
root и Makefile target.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (Phase 5 — workload_cluster TF module: CAPI topology + add-ons + acceptance) <-- этот файл
PLAN-stage1-4.md ................. §17      (Helm test contracts — Gate A + Gate B chart-side specs)
PLAN-stage1-5.md ................. §18      (Phase 6 + 7 — optional pivot)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 meta: out-of-scope, self-review, recommendation)
```

---

# 16. Phase 5 — workload cluster delivery via single Terraform module

## 16.1. Ownership и delivery model

Один TF module `terraform/modules/workload_cluster/` ставит **весь
functional workload-кластер за один `terraform apply`**: ClusterClass
+ Cluster CR + CNI + MetalLB + acceptance helm test'ы. Module
self-contained — каждый module invocation создаёт свой независимый
ClusterClass (per-workload), что позволяет параллельно держать
несколько workloads с разными Kubernetes versions / configs / tunings
на одном management cluster без cross-coupling.

Внутри module — **chain из 5 helm_release'ов** + **acceptance
null_resource'ы**, провайдеры разрешаются runtime-style:

1. `helm_release.capi_cluster_class` — chart `charts/capi-cluster-class/`
   (§16.2), provider = `helm` aliased на mgmt kubeconfig (input
   `var.mgmt_kubeconfig`). Per-workload ClusterClass, имя выводится
   из `var.cluster_name + chart-version` (slug-формула чарта).
2. `helm_release.capi_workload_cluster` — chart
   `charts/capi-workload-cluster/` (§16.3), provider = mgmt.
   `depends_on` на (1). Создаёт Cluster CR в namespace
   `capi-clusters/<cluster_name>`.
3. **Wait + read workload kubeconfig** — `kubernetes_resources` data
   source (provider = mgmt) polling до появления Secret
   `<cluster_name>-kubeconfig` в `capi-clusters`. `data.value` (b64)
   декодируется в local; rewritten в local (replace internal
   capi-int IPv6 → `https://<lxd_host_address>:<api_proxy_port>` +
   inject `tls-server-name`); используется как inline config для
   workload helm provider. **На filesystem не пишется** — output
   sensitive, consumer'у нужен файл — `terraform output -raw
   kubeconfig` (см. §16.7 + architectural fence в §16.4 epilogue).
4. `helm_release.cni_calico` — chart `charts/cni-calico/`, provider =
   `helm` aliased на workload kubeconfig (получен из шага 3).
   `depends_on` на (2) + workload kubeconfig data.
5. `null_resource.helm_test_cni_calico` — `local-exec` вызывает
   `helm test cni-calico --kubeconfig <workload>` (см. §17.2 Gate B).
   `depends_on` на (4). Failure валит TF apply.
6. `helm_release.metallb` — chart `charts/metallb/` (subchart
   wrapper), provider = workload. `depends_on` на (5) — CNI должен
   быть зелёным до того как MetalLB controller / speaker DS
   запустится (Pod networking требуется для memberlist gossip).
7. `helm_release.metallb_config` — chart `charts/metallb-config/`,
   provider = workload. `depends_on` на (6) — CRDs зарегистрированы
   первой metallb-release-ой; разделение из-за CRDs-via-templates
   pattern upstream metallb chart'а (§17.3 split rationale).
8. `null_resource.helm_test_metallb_config` — `local-exec` вызывает
   `helm test metallb-config --kubeconfig <workload>` (см. §17.3
   Gate A). `depends_on` на (7). Failure валит TF apply.

**Acceptance gate как часть apply**: TF apply не возвращается
успешно пока обе helm test'а не зелёные. Это превращает Helm test
hook'и (Gate A + Gate B) из «ручного шага после deploy'а» в
**обязательную часть deploy'а**. Failure любого helm test'а →
`null_resource` returns non-zero → TF apply фейлится → state помечен
tainted, повторный apply пере-провайдеры тот же helm test (idempotent
re-run).

Ownership разделение:

* **Controllers** (CAPI core + CABPK + KubeadmControlPlane + CAPN
  infrastructure + cert-manager на mgmt cluster) — принесены
  `bootstrap_clusterctl` через `clusterctl init --infrastructure
  incus` (§13.10). Phase 4 закрыта; Phase 5 controllers не трогает и
  сама их не переустанавливает.
* **CRDs** (ClusterClass, Cluster, KubeadmControlPlaneTemplate,
  KubeadmConfigTemplate, LXCClusterTemplate, LXCMachineTemplate) —
  тоже принесены `clusterctl init`. Чарты §16.2/§16.3 **не содержат
  CRDs**, только CR-инстансы. CRDs для add-ons (calico, metallb)
  приходят через subchart-pattern (см. чарт-status'ы и §17.3
  metallb split note).
* **Cluster-side resources** (CAPI Cluster CR + ClusterClass +
  Templates + CNI Installation CR + MetalLB IPAddressPool /
  L2Advertisement) — single-owner: Helm-чарты этого репо.
* **Helm test acceptance** (Gate A external L2 + Gate B CNI) —
  single-owner: chart-side hooks (см. §17.1 invocation contract +
  §17.2 Gate B + §17.3 Gate A specs), invoke'ятся TF module через
  `null_resource` в том же apply.

Никаких `kubernetes_manifest`, `kubectl apply -f`, Ansible
post-apply на CAPI/CNI/MetalLB CR'ы. `kubernetes` TF provider
допустим только на read-side (data lookups, status polling — например
шаг 3 wait для kubeconfig Secret). Любой create/update CR идёт через
`helm_release`.

## 16.2. Chart: `charts/capi-cluster-class/`

**Статус: выполнено в Step 10 (2026-04-24, version 0.1.0 baseline) +
Step 11 (2026-04-26, bumped to 0.3.0) substrate-required доработки:
`loadBalancer.lxc.instanceSpec.profiles: [capi-base]` baseline (без
него CAPN падает на `Failed getting root disk`),
`KubeadmControlPlaneTemplate` + `KubeadmConfigTemplate` всегда эмитят
`kubeletExtraArgs: [feature-gates=KubeletInUserNamespace=true]`
baseline (kubelet's oomWatcher /dev/kmsg open в unprivileged userns —
permission-denied; gate говорит kubelet игнорировать failure).
Verified `loadBalancer.lxc` shape против live CAPN v0.8.5 CRD —
`instanceSpec` wrapper, не плоская структура. `helm install` обоих
charts чистый, ClusterClass+5 *Template'ов в `capi-system`,
`RefVersionsUpToDate=True`, `VariablesReady=True`, `Paused=False`.
**Step 12 (2026-04-26) — bumped to 0.4.2** под dual-stack
acceptance close-out (open issue из §16.6 Step 11 Acceptance
status): KCPT хардкодит `apiServer.bind-address: "::"` +
`controllerManager.allocate-node-cidrs: "true"`; обе kubeadm-
template'ы хардкодят `kubeletExtraArgs.provider-id: lxc:///{{
v1.local_hostname }}` + динамический dual-stack `node-ip` через
substrate `preKubeadmCommands` (LXD DHCP/SLAAC); ClusterClass
`patches` propagate'ит `Cluster.spec.clusterNetwork.{pods,
services}` в kubeadm `service-cluster-ip-range` /
`cluster-cidr` через CAPI v1beta2 `valueFrom.template`;
`LXCClusterTemplate.customHAProxyConfigTemplate` зашит как
substrate-required dual-bind v4+v6 frontend (CAPN default haproxy.cfg
биндится только на v4) и убран из values.yaml; reserved-arg
guards отбивают consumer-override на substrate-managed args
(`bind-address`, `service-cluster-ip-range`, `allocate-node-cidrs`,
`cluster-cidr`, `feature-gates`, `node-ip`, `provider-id`). Полная
acceptance evidence — §16.6 Step 12 Acceptance status.**
**Step 13 (2026-04-26) — bumped to 0.5.0** под native-nftables
migration пары с charts/cni-calico (§17.2 Calico
`linuxDataplane: Nftables`): `KubeadmControlPlaneTemplate.
preKubeadmCommands` appendит KubeProxyConfiguration документ к
`/run/kubeadm/kubeadm.yaml` до `kubeadm init`. Substrate-required
hardcoded:
* `kind: KubeProxyConfiguration`, `apiVersion:
  kubeproxy.config.k8s.io/v1alpha1`, `mode: nftables` — Calico
  nftables data-plane требует kube-proxy в nftables mode
  (Calico docs формулируют это как контракт).
* `conntrack.maxPerCore: 0`, `conntrack.min: 0` — отключают
  kube-proxy'ный conntrack tuning. Default
  (`maxPerCore: 32768, min: 131072`) приводит к попытке записать
  `/sys/module/nf_conntrack/parameters/hashsize`, которая в
  unprivileged-LXC user-namespace отбивается permission denied.
  Без отключения kube-proxy crashlooping'ит.
* Init-only gating: блок выполняется только когда
  `kubeadm.yaml` есть и `kubeadm-join-config.yaml` нет.
  KubeProxyConfiguration honoured только `kubeadm init`'ом; CP
  joins и worker joins читают populated kube-system/kube-proxy
  ConfigMap.

Это даёт single-source-of-truth для kube-proxy mode на свежем
cluster bring-up'е через kubeadm init. Live patch ConfigMap'а на
running кластере (ad-hoc) ломает conntrack state на лету — proper
declarative path только через kubeadm init.**

**Step 15 (2026-04-28) — bumped to 0.6.3** ships eth1 RA reception
baseline as `KubeadmConfigSpec.files` on both
`KubeadmControlPlaneTemplate` and `KubeadmConfigTemplate`. Two files
per node:

* `/etc/sysctl.d/99-capi-ra.conf` — `net.ipv6.conf.eth1.{disable_ipv6=0,
  accept_ra=2, accept_ra_defrtr=1}`. `accept_ra=2` is required because
  workload nodes run with `forwarding=1` for k8s pod networking, and
  the default `accept_ra=1` ignores RA when forwarding is on.
* `/etc/systemd/network/30-capi-ext.network` — `[Match] Name=eth1
  [Network] DHCP=no LinkLocalAddressing=ipv6 IPv6AcceptRA=yes`.

Paired `preKubeadmCommands` run `sysctl --load=/etc/sysctl.d/99-capi-ra.conf`
+ `networkctl reload` so the config is live before kubelet,
kube-proxy, and MetalLB speaker come up. Effect: eth1 SLAAC's a
global IPv6 from the upstream RA, which MetalLB speaker uses as
the source IP for NDP replies on announced VIPs.

The CAPN haproxy LB instance does **not** receive an LXD proxy
device through the topology API — `LXCCluster.spec.loadBalancer.lxc
.instanceSpec` is a closed CRD schema (only `{profiles, image,
flavor, target}`), no `devices` field. The proxy device is
attached post-CAPI by `charts/capi-workload-cluster/`'s own Helm
hook Jobs (`templates/api-proxy-{attach,detach}-job.yaml`) which
PATCH the LXD HTTPS REST API directly with mTLS material from the
`incus-identity` Secret; see §16.7 for the runner-reachability
flow.

Memory rules applied in Step 15:
* `feedback_chart_required_values_hardcoded.md` — files block hardcoded
  in template (substrate-required, not values-tunable);
* `feedback_active_provisioning_monitor.md` — substrate state monitor
  alongside test stdout caught CRD admission errors live in the
  `TopologyReconciled` condition.

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
из общего values-блока (`clusterClass.chartVersion`). Terraform module
(§16.4) экспортирует rendered name через `cluster_class_name` output
и пробрасывает его в workload chart внутри той же helm_release chain
напрямую — фикстура (§16.5) не пересчитывает формулу.

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
"Chart-required values are hardcoded"):** запечены в templates,
не доступны через `values.yaml`:

* `unprivileged: true`, `skipDefaultKubeadmProfile: true`,
  `cloudProviderNodePatch: false`, `instanceType: container`,
  `format: cloud-config` — по substrate- и MVP-policy (§2.8 / §3.1 /
  §13.6).
* LXD profile baseline для трёх типов instance'ов CAPN спавнит:
  * **CP machine** = `capi-base` + `capi-controlplane` + consumer
    `profilesExtra.controlplane`;
  * **worker machine** = `capi-base` + `capi-worker` + consumer
    `profilesExtra.worker`;
  * **`loadBalancer.lxc` haproxy instance** = `capi-base` + consumer
    `loadBalancer.lxc.profilesExtra` — substrate-required: без
    `capi-base` (root-disk device + internal-net NIC) CAPN падает
    при создании LB instance с «Failed getting root disk: No root
    device could be found». Все три baseline'а consumer убрать НЕ
    может; `profilesExtra.*` только append'ятся.
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
* `§16.3` / `§16.4` / `§16.5` / `§16.6` — input-контракты module +
  fixture обновлены под новый public interface чарта (без `project`,
  без `install_kubeadm`, profiles/devices с `_extra` суффиксом,
  `spec.topology.classRef.name` в Acceptance block'е §16.6).
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
  остаётся scope §16.3 + §16.4 + §16.5 + §16.6 — в Step 10
  не прогонялся.

## 16.3. Chart: `charts/capi-workload-cluster/`

**Статус: выполнено в Step 11 (2026-04-26, version 0.3.0 baseline) +
Step 12 (2026-04-26, bumped to 0.4.2) — `templates/tests/cluster-
ready.yaml` Helm test hook расширен до 10-фазной dual-stack
acceptance драйвер (см. ниже Step 12 расширения). `Chart.yaml`
annotation `k8s-lab.io/capi-cluster-class-chart-version` повторяет
chart версию (rotation pin). End-to-end acceptance: `helm install`
обоих чартов + `helm test` через bootstrap k3s даёт ровно
`controlPlane.replicas` CP + `workers.replicas` worker нод, dual-
stack `InternalIP`/`podCIDR`'ы у каждой, `providerID =
lxc:///<node>`, и `RequireDualStack` ClusterIP allocator выдаёт
оба `clusterIPs` (v4 + v6).
**Step 13 (2026-04-26) — bumped to 0.5.0** в паре с
charts/capi-cluster-class 0.5.0 (rotation contract). Никаких
template-changes в этом чарте — bump чисто под coupling rotation
(chart annotation `k8s-lab.io/capi-cluster-class-chart-version` →
`"0.5.0"`). Causal: charts/capi-cluster-class 0.5.0 добавил
KubeProxyConfiguration в KCPT (§16.2 Step 13), что в name-versioning
формуле ротирует ClusterClass / *Template имена на `capn-default-0-5-0`
— любой workload Cluster CR, ссылающийся на ClusterClass через
classRef.name, должен резолвить новое имя. Annotation pin держит
этот invariant.**

**Step 15 (2026-04-28) — bumped to 0.7.2** в паре с
charts/capi-cluster-class 0.6.3 (rotation contract). Изменения в
этом чарте:

* **Per-workload deterministic API proxy port** — helper
  `capi-workload-cluster.apiProxyPort` computeит port из имени
  кластера через **Adler-32 hash** (Sprig `adler32sum`, returns
  decimal string parseable через `atoi`):
  `add 20000 (mod (atoi (adler32sum .Values.cluster.name)) 10000)`.
  Pure function — same name → same port across re-installs.
  Range 20000-29999 (10k bucket'ов; collision rate <1% на 10
  workload'ах). Override через `loadBalancer.lxc.proxyApiPort`
  (integer, default 0 = use hash).
* **Cluster CR.metadata.annotations** — добавляется
  `k8s-lab.io/api-proxy-port: "<computed>"` (string-quoted decimal).
  **Single source of truth** для downstream consumers (Molecule
  verify.yml, future TF `workload_cluster` module): port читается
  из CR-аннотации, не вычисляется заново.
* **Helm-only LXD `proxy` device delivery** — chart ships two hook
  Jobs (`templates/api-proxy-{attach,detach}-job.yaml`) which patch
  the haproxy LB instance through the **LXD HTTPS REST API**:
  - `post-install,post-upgrade` Job (`api-proxy-attach`): waits for
    CAPN to materialise `<cluster>-<suffix>-lb` LXC instance, then
    `PATCH /1.0/instances/<lb>?project=<p>` body
    `{"devices":{"api-proxy":{"type":"proxy","listen":"tcp:0.0.0.0:<port>","connect":"tcp:127.0.0.1:6443","bind":"host"}}}`
    — LXD merge-on-PATCH adds the device without disturbing the
    instance's other devices (root disk, NICs).
  - `pre-delete` Job (`api-proxy-detach`): symmetric inverse —
    `PATCH` with `{"devices":{"api-proxy":null}}` removes the key.
  Image: `alpine:3.21`, runtime `apk add curl jq` (no incus/lxc CLI
  binary). Driven against the LXD daemon URL + mTLS material from
  the `incus-identity` Secret (same Secret CAPN itself reads —
  owned by role `bootstrap_capn_secret`). New values knobs:
  `apiProxy.image`, `apiProxy.infrastructureSecretName`,
  `apiProxy.lbWaitTimeoutSeconds`.

  **Why a hook Job rather than ClusterClass topology patch:** CAPN
  v1alpha2 declares `LXCCluster.spec.template.spec.loadBalancer.lxc
  .instanceSpec` as a closed CRD schema (only `profiles/image/
  flavor/target` — no `devices` field). A JSON patch through the
  ClusterClass topology API to add the `devices` block fails at
  admission with `field not declared in schema`. A post-install
  Helm hook is the only declarative path that keeps the device
  attach inside chart-owned lifecycle (every consumer — Molecule,
  TF, manual `helm install` — gets it for free).
* Annotation pin bumped `k8s-lab.io/capi-cluster-class-chart-version`
  → `"0.6.3"`. ClusterClass / *Template имена ротируются на
  `capn-default-0-6-3`.

Memory rules applied in Step 15:
* `feedback_chart_required_values_hardcoded.md` — port computation
  formula hardcoded in helper, override only via legitimate optional
  values knob;
* `feedback_test_artifact_naming.md` — annotation prefix
  `k8s-lab.io/` for project-owned annotation key;
* `feedback_helm_first_no_raw_manifests.md` — runner-reachability
  delivered through the chart's own hook Jobs, not through inline
  shell in Molecule / `null_resource` in TF;
* `feedback_no_bitnami_images.md` — alpine + apk for hook Job
  image, no vendored client tooling.**

**Step 17 (2026-04-28) — bumped to 0.8.0** — chart забирает full
workload-cluster readiness gating себе, чтобы TF module §16.4
не вёл собственные wait-петли через bash скрипты. Изменения в
`templates/api-proxy-attach-job.yaml` (single `post-install`
hook Job + минимальная Role/RoleBinding на `<release>-api-proxy-hook`
SA с `get` на `secrets/<cluster>-kubeconfig` в `.Release.Namespace`):

* **Gate 1** — wait LB instance materialised в LXD (был в 0.7.2);
* **Gate 2** — wait `<cluster>-kubeconfig` Secret present (NEW);
  пробит через mounted SA token + `kubernetes.default.svc` REST API,
  без `kubectl` в hook image (alpine + curl + jq баланс сохранён);
* **Gate 3** — wait LB instance LXD `Running` state + idempotent
  PATCH api-proxy device (был в 0.7.2; добавлено polling Running);
* **Gate 4** — probe `https://<lb-capi-int-ipv4>:6443/livez` через
  bootstrap-LXC-side curl до 200/401/403 (NEW). Доказательство, что
  haproxy → CP backend chain на самом деле serving, не просто что
  LXD entity exists.

`helm install --wait` блокирует release deployed status до
прохождения всех 4 gates. Downstream chart installs (CNI, MetalLB)
сразу могут talk to workload API. **Memory rule
`feedback_chart_required_values_hardcoded` applied:** chart owns
весь readiness contract сам, TF потребитель.

Annotation pin `k8s-lab.io/capi-cluster-class-chart-version`
остаётся `"0.6.3"` — coupling с capi-cluster-class не изменился.

Содержит один Cluster CR (`cluster.x-k8s.io/v1beta2`), который
ссылается на ClusterClass из §16.2 через `spec.topology.classRef`,
плюс `spec.clusterNetwork` dual-stack CIDR'ы для pod/service (это
поле — единственное место, где сетевые CIDR'ы задаются декларативно
в topology-режиме). ClusterClass `patches` блок (§16.2) propagate'ит
эти `pods` / `services` CIDR'ы в kubeadm `apiServer.extraArgs.
service-cluster-ip-range` и `controllerManager.extraArgs.
{cluster-cidr,service-cluster-ip-range}` через CAPI v1beta2
`valueFrom.template`. Per-cluster ConfigMap/Secret'ы для custom
cloud-init extra-data чарт не содержит — MVP baseline такого не
требует.

`Chart.yaml.appVersion` трекает CAPI core (Cluster CR — CAPI-core
type), не CAPN.

### Cluster-class compatibility pin (annotation, not values)

Chart рендерит `spec.topology.classRef.name` по той же slug-формуле,
что §16.2 использует для `metadata.name` ClusterClass'а
(`Chart.Version | replace "." "-"`). **Версия cluster-class chart'а,
с которой workload-cluster совместим, pinned в `Chart.yaml`:**

```yaml
# charts/capi-workload-cluster/Chart.yaml
annotations:
  k8s-lab.io/capi-cluster-class-chart-version: "0.4.2"
```

Helper читает её через `.Chart.Annotations[...]`:

```gotemplate
{{- define "capi-workload-cluster.classFullName" -}}
{{- $v := index .Chart.Annotations "k8s-lab.io/capi-cluster-class-chart-version" -}}
{{- $slug := $v | replace "." "-" | lower | trunc 63 | trimSuffix "-" -}}
{{- printf "%s-%s" .Values.clusterClass.name $slug | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

Rotation contract: bump cluster-class `Chart.version` (например,
`0.4.2 → 0.5.0`) требует парного bump'а annotation **и**
workload-cluster `Chart.version` (traceability). Consumer
(Terraform fixture или standalone `helm install`) **не передаёт**
cluster-class version — coupling объявлен в Chart.yaml, не в
values.yaml.

### Values layout

```yaml
# charts/capi-workload-cluster/values.yaml — структурная схема
cluster:
  name: lab-default                # §8 k8s_lab_workload_cluster_name
clusterClass:
  name: capn-default               # bind на §16.2 clusterClass.name
  namespace: ""                    # см. ниже про cross-ns classRef
kubernetes:
  version: "v1.35.0"               # chart's own latest-stable pin
                                   # (verified upstream stable.txt
                                   # 2026-04-25; §8 k8s_lab_kubernetes_version
                                   # переопределяет через Phase 5 fixture)
topology:
  controlPlane:
    replicas: 3                    # §8 k8s_lab_workload_controlplane_count
                                   # CAPI invariant: must be odd под stacked etcd
  workers:
    replicas: 2                    # §8 k8s_lab_workload_worker_count
clusterNetwork:
  pods:
    cidrBlocks: ["10.244.0.0/16", "fd42:77:2::/56"]   # dual-stack [v4, v6]
  services:
    cidrBlocks: ["10.96.0.0/16", "fd42:77:3::/112"]   # dual-stack [v4, v6]
tests:
  image: "alpine:3.21"             # см. ниже про helm test hook
  nodesUpTimeoutSeconds: 1200      # 20 min — реалистичный budget для CAPN
                                   # provisioning 3CP+2W LXC под cold cache
```

Все default'ы трекают §8 reference deployment, чтобы:

* `helm v4 lint` проходил без `-f overrides.yaml` (helm v4 строго
  валидирует `values.yaml` против `values.schema.json`);
* standalone `helm install charts/capi-workload-cluster` рендерил
  рабочий Cluster CR без хуков от operator'а (chart self-validating
  как documentation).

CAPI invariant (`controlPlane.replicas` odd для stacked etcd) **не
enforced в schema** — schema допускает 1+; разработчик может
осознанно поставить `2` для unit-теста на CAPI rejection. Default
`3` и inline-комментарий покрывают рабочую дорогу.

Substrate-required (chart-required, hardcoded в templates, не
exposed в values per memory `feedback_chart_required_values_hardcoded`):

* `apiVersion: cluster.x-k8s.io/v1beta2` + `kind: Cluster`;
* `spec.topology.workers.machineDeployments[0].class: md-0` — должно
  совпадать с тем, что §16.2 ClusterClass запекает в
  `workers.machineDeployments[].class`. Совпадение — chart-level
  invariant, не consumer-tunable;
* `spec.topology.workers.machineDeployments[0].name: md-0` — для
  single-MD MVP. Multi-MD scenario — out of scope для v1.0.

### Namespace ownership: ВНЕ scope чарта

Workload Cluster CR живёт в `.Release.Namespace` (`metadata.namespace`
рендерится из `helm install --namespace ...`). **Сам namespace чарт НЕ
поставляет.** Owner namespace lifecycle — Phase 5 Terraform fixture
через `helm_release.create_namespace = true` (или operator руками
для chart-level smoke).

Причины архитектурного выбора (verified Step 11):

* `helm.sh/hook: pre-install` для namespace ломается на втором
  install: дефолтная `helm.sh/hook-delete-policy: before-hook-creation`
  удаляет существующий namespace со всеми CR'ами внутри перед
  re-creation. Альтернативные delete-policy либо удаляют по success,
  либо только при failed — все три варианта incompatible с долгим
  жизненным циклом cluster namespace'а;
* multi-cluster scenario: `capi-clusters` (или fleet of namespaces из
  `k8s_lab_capn_identity_namespaces`) рассчитан на N workload Cluster
  CR'ов. Если per-cluster chart owns namespace, второй install
  ломается на ownership conflict (`resource already exists outside
  the release`).

Per-cluster RBAC (`ServiceAccount` + `Role` + `RoleBinding` для helm
test pod'а — см. ниже) ВСЕ scope'ятся к `.Release.Namespace` и
шипяттся как regular Helm-managed resources, garbage-collected на
`helm uninstall`.

### Cross-namespace ClusterClass reference

`clusterClass.namespace: ""` (default) → `spec.topology.classRef.namespace`
omitted → CAPI defaults к `Cluster.metadata.namespace` (same-ns
pattern). Set explicitly (e.g. `"capi-system"`) для cross-namespace
ClusterClass reference — CAPI v1beta2 поддерживает это нативно через
`ClusterClassRef.namespace`.

Phase 5 reference deployment: ClusterClass installed в `capi-system`,
workload Cluster CR — в `capi-clusters` → `clusterClass.namespace:
"capi-system"`.

### CAPN identity Secret prerequisite

Chart **не** материализует identity Secret. Owner — §13.11
`bootstrap_capn_secret`, который через `k8s_lab_capn_identity_namespaces`
fanout'ит Secret в каждую workload-cluster namespace ДО того, как
chart устанавливается.

Архитектурный invariant (verified Step 11 против CAPN v0.8.5 controller):
CAPN не читает identity Secret из своей controller namespace
(`capn-system`). LXCCluster.spec.secretRef в v1alpha2 не имеет
namespace-поля; CAPN ищет Secret в namespace LXCCluster CR'а (т.е.
в `Cluster.metadata.namespace`). Поэтому Secret должен лежать в той
же namespace'е, что и Cluster CR. См. §13.11 cleanup contract.

### Helm test hook — chart-level acceptance

`charts/capi-workload-cluster/templates/tests/` shippy:

* `rbac.yaml` — `ServiceAccount` + `Role` + `RoleBinding` (regular
  Helm-managed). Read scope:
  * `secrets` (resourceNames-restricted на `<cluster.name>-kubeconfig`);
  * `cluster.x-k8s.io/{clusters,machinedeployments,machines}` (get/list/watch);
  * `controlplane.cluster.x-k8s.io/kubeadmcontrolplanes` (get/list/watch);
  * `infrastructure.cluster.x-k8s.io/{lxcclusters,lxcmachines}` (get/list/watch).
* `cluster-ready.yaml` — Pod с `helm.sh/hook: test` +
  `helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded`.

Test pod использует `alpine:3.21` базу + downloads upstream kubectl
binary в runtime через busybox `wget` из
`https://dl.k8s.io/release/<kubernetes.version>/bin/linux/amd64/kubectl`
(memory rules: «no bitnami», «latest stable»).

Two-phase test logic в одном Pod'е (один `helm test` вызов, один
PASS/FAIL); 10 step'ов на проверку:

* **Phase 1 — bootstrap-side shape (~2 min):**
  * `[1/10]` Cluster CR present в `.Release.Namespace`;
  * `[2/10]` `kubectl wait Cluster --for=condition=TopologyReconciled=True`
    (CAPI accepted topology + spawned owned objects);
  * `[3/10]` owned `KubeadmControlPlane` materialised (label
    `cluster.x-k8s.io/cluster-name=<cluster.name>`);
  * `[4/10]` owned `MachineDeployment` materialised;
  * `[5/10]` owned `LXCCluster` materialised;
  * `[6/10]` LXCCluster carries dual-bind v4+v6
    `customHAProxyConfigTemplate` (regression-guard на §16.2 Step 12
    chart-side hardcode — без него LB слушает только на v4).
* **Phase 2 — workload-side authoritative dual-stack check (~20 min default):**
  * `[7/10]` poll до появления `Cluster.spec.controlPlaneEndpoint`
    (CAPN auto-derives из haproxy LB instance IP; на single-node
    LXD substrate'е это IPv6 capi-int address на :6443);
  * `[8/10]` poll до появления `<cluster.name>-kubeconfig` Secret в
    `.Release.Namespace` (KCP controller emits его post-init первой
    CP-ноды); decode Secret → `/tmp/wl.kubeconfig`;
  * `[9/10]` workload API `/livez` succeeds через выбранный
    control-plane endpoint — proves haproxy LB → CP serving работает
    на обоих family'ах (apiserver `--bind-address=::` + dual-bind LB
    template, см. §16.2 Step 12);
  * `[10/10]` count `Node` объектов через workload kubeconfig:
    * по label `node-role.kubernetes.io/control-plane=` → должно быть
      **ровно** `topology.controlPlane.replicas`;
    * по label `!node-role.kubernetes.io/control-plane` → должно быть
      **ровно** `topology.workers.replicas`;
  * **per-Node ассерты на dual-stack contract'ы (Step 12):**
    `spec.providerID == "lxc:///<node-name>"` (substrate-required
    хардкод из §16.2), `status.addresses` содержит ровно один IPv4
    и хотя бы один global IPv6 `InternalIP`, `spec.podCIDRs`
    содержит обе family'ы (`10.244.x.x/24` + `fd42:77:2:x::/64`);
  * **runtime probe (Step 12):** apply `Service` с
    `ipFamilyPolicy: RequireDualStack` в default namespace и
    проверяем, что allocator выдал оба `spec.clusterIPs` —
    подтверждает, что kube-controller-manager раздаёт service-CIDR
    из обоих family'ов; cleanup через `trap EXIT` на `kubectl
    delete service`;
  * **`Node.Ready=True` НЕ требуется** — CNI ставит §16.4 module
    отдельным `helm_release`-ом ниже по chain; workers будут
    NotReady до тех пор.
    «Came up» == «registered with API server» (kubeadm join
    completed) — это authoritative signal от API server'а, что
    нода реально вошла в кластер.

### Step 12 расширения (2026-04-26)

Step 11 helm test hook кончался на counting `Node`'ов через
workload kubeconfig, был `>=` (а не `==`), и не подтверждал ни
dual-stack endpoint family selection, ни per-Node providerID/
InternalIP/podCIDR shape, ни service-CIDR allocator behaviour.
Step 12 chart-side dual-stack hardening (§16.2 KCPT
`bind-address: "::"` + ClusterClass `patches` для service/pod
CIDR'ов + LXCCluster dual-bind HAProxy template) необходим, но
helm test без runtime подтверждения свободно проглядывает
регрессию: например, ClusterClass `patches` блок мог бы не
рендерить служебные CIDR'ы (CAPI v1beta2 `valueFrom.template`
типизация довольно тонкая), и кластер встал бы криво — без
runtime check этого не видно.

10-фазная форма закрывает этот gap:

* `/livez` через CAPN-выбранный endpoint доказывает, что LB
  биндится на оба family и apiserver слушает на оба family
  (ENOREACH на любом из этих условий → `[9/10]` фейлит до того,
  как мы дошли до Node-count'а);
* per-Node `providerID = lxc:///<node>` — substrate invariant
  чарта (§16.2 хардкод); регрессия в `kubeletExtraArgs`-merge
  логике в KCPT/KCT поломает пустым providerID'ом будущие
  CCM-style features (последующие add-ons release'ы внутри §16.4);
* per-Node dual-stack `InternalIP` + `podCIDR` — доказательство
  end-to-end чейна: kubelet `--node-ip=v4,v6`
  (substrate `preKubeadmCommands` patch'ит kubeadm config'у),
  kube-controller-manager `--allocate-node-cidrs=true` (KCPT
  hardcode), Cluster.spec.clusterNetwork.pods CIDR'ы (via
  ClusterClass `patches` пробрасываются в KCM
  `--cluster-cidr=v4,v6`);
* `RequireDualStack` ClusterIP service probe — runtime подтверждение,
  что kube-apiserver service-CIDR allocator сбандлен с обеими
  family'ами и оба отдаются на одном Service object'e;
* Replica counts с `>=` на `==` — `>=` молчит при «лишних»
  registered Node'ах (orphan Machines, например), `==`
  отбивает любую drift'у топологии.

Substrate fix Step 12 (LXD profile `host-boot` device на
capi-worker — §13.6) парный, без него preflight на worker'е
валится до того, как нода зарегистрируется (то есть до
counting'а `[10/10]`).

Helm-3-only features (TF helm provider 3.1.x совместимость):

* `helm.sh/hook: test` (helm 3+);
* `helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded`
  (helm 3+);
* `.Chart.Annotations` доступ (helm 3+);
* JSON Schema draft 2020-12 (helm 3.9+).

Никаких helm 4-only features. Чарт работает с любым helm 3 SDK,
который TF provider бандлит.

### CRD readiness gate

`requireCAPI` (`cluster.x-k8s.io/v1beta2/Cluster`) — единственный
gate. CAPN/Kubeadm gates **избыточны** в этом чарте: Cluster CR
ссылается только на ClusterClass; CAPN/kubeadm-typed templateRefs
живут в той ClusterClass'е (§16.2 chart owns те gates). Если
ClusterClass отсутствует или её *Templates кривые — CAPI webhook
отбивает Cluster admission с внятной ошибкой.

## 16.4. Module: `terraform/modules/workload_cluster/`

**Статус: выполнено в Step 16 (2026-04-28) — module shipped end-to-end
на live Vagrant substrate'е через `make deploy-workload`. Файлы:
`versions.tf`, `providers.tf` (mgmt + workload helm/kubernetes aliases,
workload helm provider parses kubeconfig fields inline — host /
cluster_ca / client_cert / client_key из распарсенного Secret'а, без
config_path и без write на FS), `variables.tf` (validation на odd CP
count, dual-stack [v4,v6] arrays, k8s version regex, non-empty
lxd_host_address), `locals.tf` (slug формула совпадает с chart-side,
все 5 chart-values маппинги, kubeconfig parse + endpoint rewrite +
inject `tls-server-name: kubernetes.default.svc`), `main.tf` (chain
из шагов 1..10), `outputs.tf`, `scripts/wait_for_secret.sh`,
`scripts/wait_for_workload_api.sh` (deviation, см. ниже),
`scripts/helm_test.sh`. End-to-end timing на cold Vagrant substrate'е
(существующий bootstrap из Step 15): ClusterClass 14s + workload
chart 14s + wait_for_kubeconfig_secret 0s + workload_api wait
~5min (kubeadm init на 3 CPs + API serving) + CNI install 14s +
Gate B 1m43s + MetalLB 32s + MetalLB-config 1s + Gate A 19s ≈ ~9
мин total.**

**Step 17 (2026-04-28) — full readiness gating перенесён внутрь
chart `capi-workload-cluster` 0.8.0 hook Job** (см. §16.3 Step 17).
Module Step 16 содержал два null_resource'а с bash-скриптами
(`wait_for_secret.sh` + `wait_for_workload_api.sh`) для покрытия
gap'а между Secret-existence (KCP cert generation) и фактическим
apiserver /livez serving. Step 17 двигает контракт «I'm fully
ready» на правильного владельца — chart's post-install hook —
и module сводится к чистой TF-only orchestration:

* `scripts/` директория удалена полностью (3 файла); `helm_test`
  driver inline'ом heredoc в `provisioner "local-exec"` обоих
  null_resource'ов helm-test'ов;
* `null_resource.wait_for_kubeconfig_secret` и
  `null_resource.wait_for_workload_api` удалены — chart's hook
  блокирует helm install via 4 gate'а (LB materialised → Secret
  emitted → LB Running + proxy attached → apiserver /livez
  reachable). После `helm install --wait` retraверс'а workload
  API готов из коробки;
* variables `wait_for_kubeconfig_secret_timeout_seconds` и
  `wait_for_workload_api_timeout_seconds` удалены;
* `helm_release.capi_workload_cluster.timeout = 1500` (25 min)
  даёт hook generous budget на cold-cache CAPN provisioning.

Module теперь **полностью без `.sh` файлов** — все 6 файлов это
`*.tf` + один `.terraform.lock.hcl`. Memory rule
`feedback_chart_required_values_hardcoded` honored: chart owns
свой full-readiness contract.

Единственный TF module проекта. Один `terraform apply` поднимает
полнофункциональный workload-кластер: ClusterClass + Cluster CR +
CNI + MetalLB + acceptance helm test'ы. Module self-contained —
каждый invocation ставит свой независимый ClusterClass (per-workload),
несколько workloads с разными configs/versions могут сосуществовать
на одном mgmt cluster'е без cross-coupling.

Module имеет **два provider scope'а** — mgmt (CAPI controllers
кластер) и workload (только что созданный workload cluster). Helm
provider'ы конфигурируются как aliased instances; vasallage shape
из §16.1.

### Inputs

Module не принимает substrate-required CR-поля (они hardcoded в
чартах §16.2 / §16.3 / §17 charts). Сюда приходят только tunables:

* **Mgmt-side connection**:
  * `mgmt_kubeconfig_path` (string, required) — path до kubeconfig'а
    mgmt cluster'а. Pre-pivot = `.artifacts/bootstrap.kubeconfig`,
    post-pivot = `.artifacts/mgmt.kubeconfig`. Module не выбирает
    между ними — это decision callsite (см. §16.5 fixture, §18
    Phase 7);

* **Cluster identity + sizing**:
  * `cluster_name` (string, required) — bind на §8
    `k8s_lab_workload_cluster_name`;
  * `cluster_namespace` (string, default `capi-clusters`) — должен
    присутствовать как одно из значений §8
    `k8s_lab_capn_identity_namespaces` (CAPN читает identity Secret
    из Cluster CR namespace'а, §13.11);
  * `kubernetes_version` (string, required) — §8
    `k8s_lab_kubernetes_version`. Pinned to CAPN simplestreams set
    (§8a Constraint Step 11);
  * `controlplane_count`, `worker_count` (int) — §8
    `k8s_lab_workload_controlplane_count` / `_worker_count`;

* **Per-workload ClusterClass identity**:
  * `cluster_class_chart_version` — `helm_release.version` для
    `charts/capi-cluster-class/`. Tracks §8
    `k8s_lab_capi_cluster_class_chart_version`;
  * `cluster_class_namespace` (string, default `capi-clusters`) —
    same-namespace c Cluster CR; per-workload ClusterClass live'ит
    рядом с Cluster CR, не в shared `capi-system`. Это позволяет
    несколько concurrent workloads с разными configs;
  * `class_prefix` (string, default `capn-default`) — bind на
    `clusterClass.name` values чарта; module ложит финальное имя
    как `"{class_prefix}-{cluster_name}-{slug-of-version}"`,
    гарантируя per-workload uniqueness;

* **CAPI cluster networking** (consumed by §16.2 + §16.3 charts):
  * `pod_cidrs` (list(string), 2 элемента) — §8
    `k8s_lab_workload_pod_cidr_v4` + `_v6`;
  * `service_cidrs` (list(string), 2 элемента) — §8
    `k8s_lab_workload_service_cidr_v4` + `_v6`;

* **Substrate template extras** (passthrough на §16.2 chart):
  * `infrastructure_secret_name` — §8;
  * `image_controlplane_ref` + `image_controlplane_fingerprint`,
    `image_worker_ref` + `image_worker_fingerprint`;
  * `load_balancer` (map; default `{lxc = {}}`);
  * `controlplane_profiles_extra` / `worker_profiles_extra`;
  * `controlplane_devices_extra` / `worker_devices_extra`;
  * `control_plane_tuning` / `worker_tuning` (объекты с
    `feature_gates`, `*_extra_args`, `pre_kubeadm_commands`,
    `post_kubeadm_commands`);
  * `kube_proxy_node_port_addresses`;

* **Add-ons chart versions**:
  * `cni_calico_chart_version` — `helm_release.version` для
    `charts/cni-calico/`. Tracks chart Chart.yaml version;
  * `metallb_chart_version` — `helm_release.version` для
    `charts/metallb/` (subchart wrapper). Tracks chart Chart.yaml
    version (separate от §8 `k8s_lab_metallb_chart_version` который
    pin'ит upstream subchart внутри Chart.yaml dependency);
  * `metallb_config_chart_version` — `helm_release.version` для
    `charts/metallb-config/`;

* **MetalLB pool / advertisement** (consumed by §17.3 metallb-config
  chart):
  * `metallb_vip_range_v6` — §8 `k8s_lab_metallb_vip_range_v6`;
  * `metallb_interface` (string, default `eth1`) — §8
    `k8s_lab_metallb_interface`;
  * `metallb_extra_node_selectors` (map(string), default `{}`) —
    stacked поверх substrate-required CP-exclusion (§17.3 chart).

* **Workload kubeconfig endpoint rewrite**:
  * `lxd_host_address` (string, required) — runner-reachable
    адрес LXD host'а (для local Vagrant — Vagrant VM IP, для prod
    — public IP / DNS name LXD host'а). Используется для
    kubeconfig server URL rewrite (см. §16.7).
  * Module **не пишет kubeconfig в файл**. Workload kubeconfig
    живёт в TF state (sensitive); inline конфигурирует workload
    helm provider; экспортируется через `output "kubeconfig"
    { sensitive = true }`. Если consumer хочет файл — это
    consumer-side concern: `terraform output -raw kubeconfig >
    path.kubeconfig` или wrapped Makefile target. Подробности —
    §16.7 + architectural fence ниже.

### Internals (helm_release chain)

Все 5 release'ов используют `wait = true`, `atomic = true`,
`force_update = false`:

1. `helm_release.capi_cluster_class` — provider mgmt. Ставит
   `charts/capi-cluster-class/` в `var.cluster_class_namespace`;
   chart рендерит ClusterClass + 5 Templates с per-workload именами
   (см. `class_prefix` rendering выше);
2. `helm_release.capi_workload_cluster` — provider mgmt. Ставит
   `charts/capi-workload-cluster/` в `var.cluster_namespace`.
   `depends_on = [helm_release.capi_cluster_class]`;
3. **Wait for workload kubeconfig Secret** — Step 17 update: чёрный
   ящик внутри `helm_release.capi_workload_cluster` hook'а. Chart's
   post-install Job blocks helm install completion до тех пор, пока
   Secret `<cluster_name>-kubeconfig` не materialized + LB Running
   + apiserver /livez serving. Поэтому `data.kubernetes_resource`
   с `depends_on = helm_release.capi_workload_cluster` гарантированно
   читает Secret сразу после helm Creation complete — отдельный
   `null_resource` polling shim не требуется;
4. **Decode + rewrite kubeconfig**: `data.kubernetes_resource`
   (после wait) читает Secret. `local.workload_kubeconfig_raw =
   base64decode(...)`. `local.workload_kubeconfig` — rewritten
   копия с server URL заменённым на
   `https://<lxd_host_address>:<api_proxy_port>` (port читается
   из Cluster CR's `metadata.annotations["k8s-lab.io/api-proxy-port"]`)
   + inject `tls-server-name: kubernetes.default.svc`. **На
   filesystem не пишется** — никаких `local_file` resource'ов;
5. `provider "helm"` aliased на workload — конфигурируется через
   `kubernetes { host=… cluster_ca_certificate=… client_certificate=…
   client_key=… tls_server_name="kubernetes.default.svc" }` —
   индивидуальные fields из распарсенного kubeconfig'а (Step 16:
   helm provider 3.x не имеет `kubernetes.config` inline-content
   field, только `config_path`; парсинг yamldecode + base64decode
   в `local.workload_helm_kubernetes` keep'ит module hermetic).
   Workload kubeconfig живёт только в TF state (sensitive=true).
   **Step 17 update**: chart 0.8.0 post-install hook сам блокирует
   шаг (2) до full readiness (LB + Secret + Running + /livez), so
   шаги (3)+(4) data sources гарантированно успешны без отдельных
   wait null_resource'ов;
6. `helm_release.cni_calico` — provider workload. Ставит
   `charts/cni-calico/` в namespace `tigera-operator` (chart owns
   namespace). `depends_on` на (4);
7. `null_resource.helm_test_cni_calico` — `local-exec` вызывает
   `helm test cni-calico --kubeconfig <tmpfile> --namespace
   tigera-operator --timeout 15m --logs`. Failure → TF apply fails
   с понятным выводом (`triggers` includes chart version + release
   ID, поэтому повторный apply re-runs тест на upgrade);
8. `helm_release.metallb` — provider workload. Ставит
   `charts/metallb/` (subchart wrapper над upstream) в
   `metallb-system`. `depends_on = [null_resource.helm_test_cni_calico]`
   — CNI зелёный → MetalLB можно ставить;
9. `helm_release.metallb_config` — provider workload. Ставит
   `charts/metallb-config/` в `metallb-system`. `depends_on =
   [helm_release.metallb]` — split rationale §17.3 (CRDs first,
   CRs second);
10. `null_resource.helm_test_metallb_config` — `local-exec` вызывает
    `helm test metallb-config --kubeconfig <tmpfile> --namespace
    metallb-system --timeout 15m --logs`. Failure → TF apply fails.

`null_resource` для helm test'ов использует `triggers` мап с
`{chart_version, release_id, kubeconfig_hash}` — re-runs test'а на
chart bump или kubeconfig rotation. Внутри `local-exec`
скрипт пишет workload kubeconfig в `mktemp` файл, выполняет helm
test, очищает temp файл в любом исходе (trap EXIT). Это keeps
in-cluster apply hermetic relative to runner FS state.

### Outputs

* `cluster_name`, `cluster_namespace` — echo input'ов для downstream
  consumers (e.g. cleanup orchestration);
* `cluster_class_name` — rendered final ClusterClass name (для
  introspection / debug);
* `kubeconfig` (sensitive) — workload kubeconfig content (string).
  Consumer может писать это сам через `output` block или TF data
  pass через `terraform output -raw kubeconfig > path`;
* `metallb_vip_range_v6` — echo input'а; consumer'у может быть
  полезно для downstream services;
* `helm_releases` (map(object)) — `{ capi_cluster_class, capi_workload_cluster,
  cni_calico, metallb, metallb_config }`, каждый с `id`, `name`,
  `namespace`, `chart_version`. Используется fixtures'ами для
  `terraform output | jq` smoke checks.

### Multi-workload usage

Несколько workloads = несколько module invocation'ов с разными
`cluster_name`. ClusterClass per-workload изолирован (одно из
проявлений: bump KubeadmControlPlaneTemplate в одном workload не
требует bump'а в другом). `cluster_class_namespace = cluster_namespace`
default keeps each workload self-contained.

### Architectural fence: TF module имеет zero filesystem coupling с Molecule artefacts

Это hard contract:

* **TF module §16.4 не пишет ни в `.artifacts/clusters/`, ни в
  любую другую path под `.artifacts/`.** Никаких `local_file`
  resource'ов, никаких `provisioner "local-exec"` пишущих файлы.
  Workload kubeconfig живёт только в TF state (sensitive=true) и
  inline в helm provider config'е.
* **TF module не читает файлы из `.artifacts/`** (за исключением
  `var.mgmt_kubeconfig_path` который указывает на bootstrap
  kubeconfig — но это input, не assumption о Molecule pipeline).
* **Molecule e2e-local artefacts в `.artifacts/clusters/<cluster>.kubeconfig`**
  — debug-копия workload kubeconfig (raw Secret content, internal
  capi-int IPv6 endpoint — НЕ rewritten) для operator inspection.
  Никакая TF / Ansible / Helm task этот файл не consume'ит.
* **Если consumer хочет workload kubeconfig как файл** — это его
  concern вне module'а:
  * `terraform output -raw kubeconfig > path.kubeconfig` в
    consumer-side wrapper Makefile;
  * или просто `kubectl --context=<...>` через kubeconfig merger
    из output stream.

Этот fence гарантирует:
* TF apply воспроизводим с zero state на runner'е (никаких
  pre-existing файлов кроме `mgmt_kubeconfig_path`);
* Molecule harness и TF flow остаются independent — каждый владеет
  своими debug-артефактами;
* Multiple TF workspaces / multiple Molecule scenarios могут
  сосуществовать без stomp'инга друг друга.

### CAPI invariants module enforces

* `controlplane_count` validation: должен быть нечётным (CAPI KCP
  webhook отбивает чётные replicas под stacked etcd). Module
  валидирует через `validation` block: `controlplane_count % 2 == 1`;
* `pod_cidrs` / `service_cidrs` length: ровно 2 элемента (dual-stack
  invariant §8). Validation block;
* `kubernetes_version` ∈ supported set (CAPN simplestreams); pinned
  default §8 actual; module не валидирует этот set runtime — это
  responsibility consumer'а через §8 default.

## 16.5. Test fixture: `tests/fixtures/terraform/workload-clusters/lab-default/`

**Статус: выполнено в Step 16 (2026-04-28) — fixture root + Makefile
target'ы `deploy-workload` / `workload-kubeconfig` / `destroy-workload`
работают end-to-end из repo root. Файлы: `providers.tf` (только
`required_providers` без provider configs — module owns aliases),
`variables.tf` (defaults матчат §8 reference deployment + 7 unused
declared vars для silently consuming mgmt-side keys из auto-tfvars),
`main.tf` (derives `lxd_host_address` из `k8s_lab_bootstrap_api_server_url`
host component через regex с двумя capture groups + `coalesce` —
поддерживает оба `[ipv6]:port` и `host:port` формы), `outputs.tf`
(passthrough всех module outputs).**

**Step 16 deviation от исходного §16.5 design'а: `.artifacts/bootstrap.auto.tfvars.json`
**не auto-load'ится** Terraform-ом из cwd фикстуры.** TF auto-loads
`*.auto.tfvars.json` только из своего working directory; репозиторий
держит handoff bundle на repo-root (`.artifacts/`), а fixture cwd —
`tests/fixtures/terraform/workload-clusters/lab-default/`. Makefile
target `deploy-workload` threading'ит файл явно через
`-var-file=$(REPO_ROOT)/.artifacts/bootstrap.auto.tfvars.json` +
preflight check на наличие файла. Альтернативный путь — committed
symlink в фикстуре — отвергнут как hidden filesystem coupling.

Единственный TF root этого репо. Invokes module `workload_cluster/`
с дефолтными §8 значениями для local Vagrant/libvirt контура.

Shape:

```
tests/fixtures/terraform/workload-clusters/lab-default/
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
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
```

Сами provider configurations module определяет внутри (mgmt + workload
aliases), fixture их не переопределяет.

### variables.tf

Принимает `k8s_lab_*` ключи из §8. `.artifacts/bootstrap.auto.tfvars.json`
(emitted `export_artifacts` §13.12) auto-load'ится Terraform-ом и
заполняет их без ручного tfvars. Поверх §8 fixture добавляет:

* `mgmt_kubeconfig_path` (default `${path.module}/../../../../../.artifacts/bootstrap.kubeconfig`)
  — pre-pivot path к bootstrap k3s kubeconfig'у. Post-pivot (см.
  §18.3) consumer переключает на `.artifacts/mgmt.kubeconfig`
  через tfvar override. Это **input** module'у, не assumption о
  Molecule pipeline — fixture default просто tracks reference
  layout `export_artifacts` role'а;
* `cluster_class_chart_version` (default tracks §8
  `k8s_lab_capi_cluster_class_chart_version`);
* `cluster_workload_chart_version` (default tracks §8
  `k8s_lab_capi_workload_cluster_chart_version`). Bump этой переменной
  должен совпадать с `capi-workload-cluster/Chart.yaml`
  `annotations["k8s-lab.io/capi-cluster-class-chart-version"]` —
  coupling check внутри chart'а через `Chart.Annotations`-helper;
* `cni_calico_chart_version` (default = `charts/cni-calico/Chart.yaml`
  version);
* `metallb_chart_version` (default = `charts/metallb/Chart.yaml`
  version);
* `metallb_config_chart_version` (default = `charts/metallb-config/Chart.yaml`
  version).

### main.tf

```hcl
module "workload_cluster" {
  source = "../../../../../terraform/modules/workload_cluster"

  mgmt_kubeconfig_path = var.mgmt_kubeconfig_path
  lxd_host_address     = var.k8s_lab_lxd_host_address

  cluster_name        = var.k8s_lab_workload_cluster_name
  cluster_namespace   = "capi-clusters"
  kubernetes_version  = var.k8s_lab_kubernetes_version
  controlplane_count  = var.k8s_lab_workload_controlplane_count
  worker_count        = var.k8s_lab_workload_worker_count

  cluster_class_chart_version  = var.cluster_class_chart_version
  cluster_workload_chart_version = var.cluster_workload_chart_version
  cni_calico_chart_version     = var.cni_calico_chart_version
  metallb_chart_version        = var.metallb_chart_version
  metallb_config_chart_version = var.metallb_config_chart_version

  pod_cidrs     = [var.k8s_lab_workload_pod_cidr_v4,
                   var.k8s_lab_workload_pod_cidr_v6]
  service_cidrs = [var.k8s_lab_workload_service_cidr_v4,
                   var.k8s_lab_workload_service_cidr_v6]

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

### outputs.tf

* `cluster_name`, `cluster_namespace` — passthrough (для cleanup
  orchestration §19.2);
* `cluster_class_name` — passthrough;
* `kubeconfig` (sensitive) — rewritten workload kubeconfig content
  как string. Consumer'у нужен файл — `terraform output -raw
  kubeconfig > path.kubeconfig` через consumer-side wrapper
  Makefile target. Module не пишет файл сам (см. §16.4
  architectural fence);
* `api_proxy_port` — passthrough Cluster annotation
  `k8s-lab.io/api-proxy-port` для downstream consumers
  (например, kubectl wrapper'ов с `--server` override);
* `helm_releases` — passthrough (smoke-check fixture).

## 16.6. Phase 5 — Apply workload cluster

Orchestration — `make deploy-workload` (target в корневом
`Makefile`):

```makefile
deploy-workload:
	cd tests/fixtures/terraform/workload-clusters/lab-default \
	  && terraform init -upgrade \
	  && terraform apply -auto-approve
```

Контракт:

* `terraform` предполагается **уже установленным** на runner'е (dev
  машина или CI-агент); Ansible/Phase 4 его не ставят;
* оператор / агент вызывает target вручную после того, как Phase 4
  зелёная и `.artifacts/bootstrap.kubeconfig` +
  `.artifacts/bootstrap.auto.tfvars.json` материализованы;
* `helm` CLI — нужен на runner'е для helm test'ов внутри module
  (`null_resource` + `local-exec`); версия pinned chart-providers
  совместимая (Helm 3.20+);
* первый apply поднимает workload-кластер с нуля (CAPI provisioning
  + LXC instances + kubeadm init/join + CNI + MetalLB +
  helm test'ы); типично 8-12 минут на cold cache;
* повторный apply — no-op (idempotent helm_release'ы; helm test'ы
  re-run потому что `null_resource.triggers` включает chart version,
  но они быстры если cluster уже зелёный).

Acceptance:

1. `helm_release.capi_cluster_class` применён: ClusterClass +
   все 5 *Template'ов existуют в `<cluster_namespace>` с именами
   `{class_prefix}-{cluster_name}-{chart-version-slug}`; webhook
   провалидировал.
2. `helm_release.capi_workload_cluster` применён: Cluster CR в
   `capi-clusters/<cluster_name>` с `spec.topology.classRef.name`
   указывающий на правильный per-workload ClusterClass.
3. CAPI kubeadm-CP + CAPN controllers подхватили Cluster CR,
   создали LXCCluster + LXCMachine'ы, kubeadm init/join прошли,
   workload kubeconfig Secret `<cluster_name>-kubeconfig` появился
   в `<cluster_namespace>`.
4. `helm_release.cni_calico` применён: tigera-operator + calico-node
   DaemonSet rolled out, все workload Nodes Ready.
5. **Gate B зелёный** (`null_resource.helm_test_cni_calico`) —
   chart-side acceptance (см. §17.2): tigera-operator Available,
   calico-system Pods Ready, dual-stack `podCIDRs` per-Node, ICMP4/
   ICMP6 pod-to-pod через kubectl exec.
6. `helm_release.metallb` + `helm_release.metallb_config` применены:
   metallb controller + speaker DS rolled out, IPAddressPool +
   L2Advertisement reconciled.
7. **Gate A зелёный** (`null_resource.helm_test_metallb_config`) —
   chart-side acceptance (см. §17.3): demo Service получил VIP из
   pool, in-cluster HTTP probe от driver Pod к VIP returns 200.
8. `terraform output -raw kubeconfig` возвращает рабочий
   workload kubeconfig (строкой) с rewritten server URL
   (`https://<lxd_host_address>:<api_proxy_port>` + injected
   `tls-server-name`). Module **не пишет kubeconfig в файл** — это
   consumer-side concern (см. §16.4 architectural fence).
9. Acceptance smoke: `kubectl --kubeconfig <(terraform output -raw
   kubeconfig) get nodes` с runner'а возвращает все workload-nodes
   Ready. Это runner-side verification что LXD proxy device + TLS
   chain работают end-to-end (без in-cluster jump-pod, как было в
   pre-Step-15 Molecule e2e-local).

Failure любого acceptance criterion → TF apply фейлится; state
помечен tainted; повторный apply re-runs только failed resource'ы
(helm_release upgrade-no-op для зелёных).

Acceptance status history split — Step 11/12 относятся к исходным
acceptance criteria (1)-(4) которые вырастали в (1)-(8) в Step 13/14
по мере добавления CNI и MetalLB chart'ов. Step 13/14 evidence —
chart-side зелёный через Molecule e2e-local; TF module wrapper ещё
не реализован, реализация — Step 15+.

### Acceptance status (Step 11, 2026-04-26)

(1) и (2) **зелёные** — `helm install` обоих чартов чисто применился,
ClusterClass `capn-default-0-3-0` + 5 *Template'ов в `capi-system`,
Cluster CR в `capi-clusters/lab-default` с `spec.topology.classRef.name=
capn-default-0-3-0` и `classRef.namespace=capi-system` (cross-ns
reference). `TopologyReconciled=True (ReconcileSucceeded)` на первом
apply.

(3) **частично зелёные**: CAPI/CAPN controllers подхватили Cluster CR,
создали `LXCCluster` + первый `LXCMachine` (CP) + `MachineDeployment` с
2 worker `Machine`'ами; LXC instance haproxy LB поднялся; CP LXC instance
запустился, kubeadm preflight прошёл (после §13.6 host-boot device fix),
certs сгенерированы, static pods (etcd, kube-apiserver, kube-controller-
manager, kube-scheduler) поднялись healthy внутри CP. **kubeadm init
exit'нул не до конца** — phase `upload-config/kubeadm` валится на
создании admin ClusterRoleBinding с `client rate limiter Wait returned
an error: context deadline exceeded`. Root cause:

* `kube-apiserver` listens `*:6443` (IPv4 wildcard, kubeadm default
  `--bind-address=0.0.0.0`);
* `Cluster.spec.controlPlaneEndpoint` (CAPN auto-derived from LXCCluster
  status) и `admin.conf.clusters[].cluster.server` указывают на IPv6
  endpoint CP-ноды/LB (capi-int dual-stack picks IPv6);
* family mismatch → connection refused → kubeadm не доходит до
  bootstrap-token / admin RBAC создания.

(4) **не зелёный** — Cluster.status.phase зависает на `Provisioning`,
`AVAILABLE=False`, `nodeRef` не populated, нет workload kubeconfig
Secret для последующих фаз.

**Open issue scope Step 12+:** dual-stack kubeadm 1.35.x +
CAPI/CAPN haproxy LB endpoint family selection. Запланирован deep
research на reference dual-stack patterns:

* `clusterConfiguration.apiServer.extraArgs.bind-address: "::"`
  hardcoded в KCPT (вместе с possible
  `controllerManager.extraArgs.bind-address` / `scheduler.extraArgs.
  bind-address` для healthz endpoints);
* CAPN `loadBalancer.lxc` haproxy.cfg dual-stack frontend (нужно
  проверить шипит ли CAPN в default config бинд на оба family или
  только один);
* `Cluster.spec.controlPlaneEndpoint` family-priority контроль
  (CAPN auto-derive vs explicit override);
* возможно — kube-vip / external LB вместо CAPN's lxc haproxy для
  cleaner dual-stack семантик.

Substrate fixes Step 11 (см. §13.x Step 11 entries) необходимы
независимо от dual-stack solution и переезжают в Step 12 как-есть.

### Acceptance status (Step 12, 2026-04-26)

Все четыре acceptance критерия **зелёные**. Step 12 — close-out
dual-stack research блока выше.

(1) и (2) — без изменений по сути, но bumped chart-версии
0.3.0 → 0.4.2 (см. §16.2 / §16.3 status header'ы): ClusterClass
`capn-default-0-4-2` + 5 *Template'ов в `capi-system`, Cluster CR
в `capi-clusters/lab-default` с `spec.topology.classRef.name=
capn-default-0-4-2`, `TopologyReconciled=True`.

(3) **зелёный** — kubeadm init на CP проходит до конца, admin
ClusterRoleBinding создаётся, kubeadm join на 2 CP + 2 worker
LXC instance'ах проходит. Реализованные fixes (chart-side, см.
§16.2 Step 12 разъяснение):

* `KubeadmControlPlaneTemplate.clusterConfiguration.apiServer.
  extraArgs.bind-address: "::"` hardcoded — kube-apiserver слушает
  на оба family;
* `LXCClusterTemplate.spec.template.spec.loadBalancer.lxc.
  customHAProxyConfigTemplate` зашит как dual-bind v4+v6 frontend
  template (CAPN v0.8.x default haproxy.cfg биндится только на
  v4);
* `controllerManager.extraArgs.allocate-node-cidrs: "true"`
  hardcoded в KCPT (без него kube-controller-manager не раздаёт
  podCIDR'ы на Node объекты, dual-stack или нет);
* ClusterClass `patches` блок propagate'ит
  `Cluster.spec.clusterNetwork.{pods,services}` из Cluster CR'а в
  kubeadm `apiServer.extraArgs.service-cluster-ip-range` +
  `controllerManager.extraArgs.{cluster-cidr,service-cluster-ip-
  range}` (используется CAPI v1beta2 `valueFrom.template`);
* `kubeletExtraArgs.provider-id: lxc:///{{ v1.local_hostname }}`
  hardcoded в обоих kubeadm template'ах + dynamic dual-stack
  `node-ip` через substrate `preKubeadmCommands` (LXD DHCP/SLAAC
  выдаёт адреса динамически — статически не зашьёшь);

CAPI auto-derived `Cluster.spec.controlPlaneEndpoint` остаётся
single-family (IPv6 в этом substrate'е) — это fine, потому что
обе ноды-стороны (apiserver listener + LB frontend) теперь
биндятся на оба family и принимают `admin.conf.clusters[].cluster.
server` любой family.

(4) **зелёный** — Cluster.status.phase = Provisioned (на
CNI-less кластере не выйдет в Ready без CNI; это by design —
Phase 5.1 деливерит Calico как отдельный Helm release), `helm
test` (10-фазная dual-stack acceptance драйвер из §16.3)
проходит до конца: `cp=3/3 worker=2/2 ALL TOPOLOGY CHECKS
PASSED`. Acceptance evidence: `make -C tests/molecule
e2e-local-vagrant-converge` → `failed=0`, `make -C tests/molecule
e2e-local-vagrant-verify` → `failed=0`. Полный путь — `e2e_local`
Molecule сценарий (§9.4 Full E2E + §10.2 driver) — реализован
тем же Step'ом (см. PLAN-stage1-1.md Step 12 prose).

Substrate-side fix Step 12 парный (см. §13.6 lxd_profiles):
capi-worker LXD profile получил `host-boot` read-only `/boot`
mount — `kubeadm join` preflight `SystemVerification` валится
без него на той же причине, что Step 11 уже решил для
capi-controlplane (`/proc/config.gz` физически не существует на
Debian 13 kernel — `CONFIG_IKCONFIG=n`).

### Acceptance status (Step 16, 2026-04-28)

Все 9 acceptance criteria из §16.6 выше **зелёные** на live Vagrant
substrate'е (LXD host = 192.168.121.95, инициализированный через
Step 15 chain). End-to-end run: `make deploy-workload` → `Apply
complete! Resources: 6 added, 0 changed, 0 destroyed` за ~9 мин.

(1)-(2) ✓ — `helm_release.capi_cluster_class` ставит
`capn-default-0-6-3` ClusterClass + 5 *Templates в `capi-clusters`
namespace (cluster_class_namespace defaults к cluster_namespace —
per-workload self-contained, без cross-ns reference). Cluster CR
`lab-default` в той же namespace, `spec.topology.classRef.name=
capn-default-0-6-3`, `TopologyReconciled=True (ReconcileSucceeded)`.

(3)-(4) ✓ — CAPN провижится 3 CP + 2 worker LXC instances + LB
instance `lab-default-j8hvk-deb12-lb` за ~5 мин; kubeadm init/join
проходят на всех; KCP `r=3 u=3 r=3`; workload kubeconfig Secret
`lab-default-kubeconfig` материализуется в `capi-clusters`. CNI
Calico installation (тот же `helm_release.cni_calico` через
workload-aliased helm provider) — все 5 Nodes Ready=True (3 CP +
2 worker), calico-node DS 5/5 ready, calico-typha 3 replicas,
calico-apiserver + calico-kube-controllers up.

(5) ✓ Gate B — `null_resource.helm_test_cni_calico` зелёный за
1m43s; chart-side hook (§17.2) подтверждает tigera-operator
Available, calico-system Pods Ready, dual-stack `podCIDRs` per-Node,
ICMP4/ICMP6 pod-to-pod через два worker'а.

(6)-(7) ✓ Gate A — `helm_release.metallb` (subchart wrapper) +
`helm_release.metallb_config` оба deployed. metallb controller +
5 speaker DS replicas Running. IPAddressPool `metallb-config-v6`
с range `2001:db8:42:100::200-2001:db8:42:100::2ff` reconciled.
L2Advertisement `metallb-config-v6` указывает на eth1.
`null_resource.helm_test_metallb_config` зелёный за 19s; chart-side
hook (§17.3) поднимает demo Service `k8s-lab-metallb-demo` (nginx
backend) — controller выделяет VIP `2001:db8:42:100::200` из pool;
in-cluster HTTP probe возвращает 200.

(8) ✓ — `terraform output -raw kubeconfig` эмитит rewritten
kubeconfig: `server: https://192.168.121.95:26818` (lxd_host_address
+ Adler-32-derived port из Cluster annotation
`k8s-lab.io/api-proxy-port`), `tls-server-name: kubernetes.default.svc`
(injected, decouple'ит TLS identity от runner-reachable URL),
полный CA + client cert/key из Secret'а. Module ничего не пишет
на FS — output остаётся sensitive в TF state.

(9) ✓ Acceptance smoke — после `make workload-kubeconfig`
(materialise `terraform output -raw kubeconfig` в
`.artifacts/clusters/lab-default.kubeconfig` через consumer-side
wrapper, umask 077), `kubectl --kubeconfig <path> get nodes -o wide`
с runner'а возвращает все 5 workload Nodes Ready на v1.35.0,
ContainerRuntime containerd 2.2.0. Это доказывает, что LXD proxy
device (Helm hook on chart) + haproxy LB → CP backends + apiserver
TLS chain работают end-to-end из external runner'а.

**Step 16 secondary deviation для consumer ergonomics**: попытка
`kubectl --kubeconfig <(terraform output -raw kubeconfig)` через
process substitution **не работает** — kubectl делает `seek()` на
kubeconfig file для refresh credentials, FIFO от `<(...)` не
support'ит seek и API errors на `localhost:8080` (defaults). Module
fence (§16.4 architectural fence) сохранён: TF не пишет файл; для
consumer convenience Makefile target `workload-kubeconfig`
materialise'ит output в `.artifacts/clusters/<cluster>.kubeconfig`
с `umask 077`. Subdir уже предсоздан Phase 4 `export_artifacts`
(§15.6).

Step 16 НЕ потребовал substrate-side fixes — chart-side и role-side
contract'ы Step 11/12/13/15 покрывают provisioning chain полностью;
TF module — declarative orchestrator поверх готовых компонентов без
«своих» CR'ов или manifest'ов (memory rule
`feedback_helm_first_no_raw_manifests` honored: ноль
`kubernetes_manifest`, ноль `kubectl apply -f`, все CR'ы через
`helm_release`).

## 16.7. Workload kubeconfig pipeline (in-state) + API endpoint rewrite

Workload kubeconfig pipeline — **internal step §16.4 module'а**, не
отдельная Phase, **никогда не пишется в файл**. Module:

1. ждёт Secret `<cluster_name>-kubeconfig` в `<cluster_namespace>`
   через `null_resource` + `kubectl get secret -w --timeout=20m`
   (mgmt kubeconfig);
2. читает Secret через `data.kubernetes_resource` (server-side,
   нативный TF), декодирует `data.value` (base64) в local;
3. читает Cluster CR'а annotation
   `k8s-lab.io/api-proxy-port` (которую `charts/capi-workload-cluster/`
   пишет — см. §16.3 Step 15) — это computed Adler-32 hash port на
   LXD haproxy LB instance;
4. **rewrite'ит kubeconfig server URL** в local: replace
   `server: https://[<internal-v6>]:6443` →
   `server: https://<lxd_host_address>:<api-proxy-port>`. Также
   inject'ит `tls-server-name: kubernetes.default.svc` в каждый
   `clusters[].cluster` если ещё не задан, чтобы избежать
   x509 SAN mismatch (workload kubeadm SANs не знают про rewrite'ed
   host);
5. конфигурирует workload-aliased helm provider inline через
   `kubernetes { config = local.workload_kubeconfig_rewritten }`;
6. эмитирует через `output "kubeconfig" { sensitive = true }`
   sensitive string. Никаких `local_file` resource'ов.

Consumer'у видим rewritten kubeconfig — **только через TF output**:

```bash
terraform output -raw kubeconfig > /path/to/kubeconfig
```

Это consumer-side concern. Для local-harness operator может
завернуть в Makefile target (`make workload-kubeconfig`); для CI
— pipeline step после `terraform apply`. Module не предполагает
куда / нужно ли вообще писать.

API endpoint reachability path — production-mirror:

* Inside cluster: workload pods → workload kube-apiserver через CAPN-
  managed haproxy LB → CP backends. CAPN haproxy LB binds на capi-int
  IPv6 (`fd42:77:1::/64`); это substrate-managed, не наш scope;
* Outside cluster (runner / consumer's TF apply / kubectl): traffic
  → `<lxd_host_address>:<api-proxy-port>` → LXD `proxy` device на LB
  instance (`bind=host` listener) → 127.0.0.1:6443 внутри LB
  instance → haproxy → CP backends.

LXD `proxy` device delivery — **owned by `charts/capi-workload-cluster/`
through Helm hook Jobs**, not by Terraform / Molecule:

* `post-install,post-upgrade` Job
  (`templates/api-proxy-attach-job.yaml`) waits for CAPN to
  materialise the haproxy LB LXC instance and then `PATCH`-es
  `/1.0/instances/<lb>?project=<p>` over the LXD HTTPS REST API to
  add the `api-proxy` device. PATCH semantics merge top-level
  `devices` so the LB's pre-existing devices (root disk, NICs)
  stay untouched.
* `pre-delete` Job (`templates/api-proxy-detach-job.yaml`) is the
  symmetric inverse on `helm uninstall <workload>`: `PATCH` with
  `{"devices":{"api-proxy":null}}` removes the key. Best-effort
  (`exit 0` if LB instance has already been torn down by CAPN).
* Image: `alpine:3.21` + `apk add curl jq` at runtime — no incus/
  lxc CLI binary, no vendored client tooling. Driven by the same
  `incus-identity` Secret that CAPN consumes (`server`,
  `client-crt`, `client-key`, `server-crt`, `project` fields per
  CAPN docs); Job mounts it read-only.
* `helm install --wait` blocks on hook Job completion by default,
  so by the time the helm release is reported success the LB
  instance is provisioned AND the proxy device is wired — no race
  window where downstream chart installs see a half-ready cluster.

**Why a Helm hook rather than a ClusterClass topology patch:** CAPN
v1alpha2 declares `LXCCluster.spec.template.spec.loadBalancer.lxc
.instanceSpec` as a closed CRD schema (only `profiles/image/flavor/
target` — no `devices` field). A JSON patch through the
ClusterClass topology API to add the `devices` block fails at
admission with `field not declared in schema`. The proxy device
must therefore be attached post-CAPI on the live LB instance; a
Helm hook Job in the workload chart is the only declarative path
that keeps the device attach inside chart-owned lifecycle.

Несколько workload clusters на одном LXD host'е получают **разные
ports** через Adler-32 hash от cluster name → не конфликтуют.
Collision на 10 workload'ах <1%; conflict resolution через
`loadBalancer.lxc.proxyApiPort` override в values chart'а
`charts/capi-workload-cluster/`.

### Co-existence с Molecule e2e-local kubeconfig pipeline

Molecule e2e-local converge.yml + verify.yml owns свой собственный
kubeconfig pipeline — **независимый от TF module pipeline'а**.
Reuses те же chart artefacts (Cluster CR annotation
`k8s-lab.io/api-proxy-port` + post-install hook attach Job which
wires the LXD `proxy` device on the LB instance) и делает rewrite
через Ansible-native pipeline:

1. `kubernetes.core.helm` ставит `capi-workload-cluster` chart;
   `helm install --wait` блокирует до тех пор, пока chart's
   post-install hook Job не завершит attach LXD `proxy` device —
   на этом этапе runner-reachability для `<host>:<port>` уже
   готова;
2. `kubernetes.core.k8s_info` читает Cluster CR's annotation +
   workload kubeconfig Secret (через bootstrap kubeconfig);
3. Ansible-side rewrite через `regex_replace` — заменяет
   `server: https://...:6443` на `https://<K8SLAB_HOST_ADDR>:<api-proxy-port>`
   + inject `tls-server-name: kubernetes.default.svc`;
4. `ansible.builtin.copy` пишет результат в
   `.artifacts/clusters/<cluster>.kubeconfig`. Этот файл —
   единственный kubeconfig, через который Molecule converge.yml
   ставит cluster add-ons (cni-calico, metallb, metallb-config) с
   runner-side `kubernetes.core.helm` (`delegate_to: localhost`);
5. Runner-side acceptance test через `kubernetes.core.k8s_info
   kind=Node` против rewritten kubeconfig'а — assert все workload
   Nodes Ready=True.

Этот файл и TF-module's `terraform output -raw kubeconfig` — **два
независимых артефакта** живущих параллельно:
* Molecule artefact = debug + runner-side acceptance test, rewritten
  endpoint, written by Ansible Verify pipeline;
* TF output = production-path delivery, rewritten endpoint, in TF
  state только.

**TF module ни читает, ни пишет в `.artifacts/clusters/`** (см.
§16.4 architectural fence). Каждый flow владеет своим pipeline'ом
для kubeconfig endpoint rewrite — Ansible regex_replace в Molecule,
TF locals в module. Никакого shared filesystem coupling.

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
