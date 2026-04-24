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

Содержит реусабельный CAPI topology-контракт для CAPN unprivileged
kubeadm path:

* `ClusterClass` (dual-stack podCIDRs/serviceCIDRs baseline);
* `KubeadmControlPlaneTemplate` — CP bootstrap contract (feature gates,
  kubelet args, kube-proxy policy, preKubeadm/postKubeadm commands);
* `KubeadmConfigTemplate` — worker bootstrap contract (совместимый
  kubelet config, node labels);
* `LXCClusterTemplate` — infrastructure-уровень для Cluster CR
  (secretRef на §8 `k8s_lab_infrastructure_secret_name`, loadBalancer
  = none для MVP, project = §8 `k8s_lab_project_name`);
* `LXCMachineTemplate` для CP — profiles = §8 `k8s_lab_controlplane_profiles`,
  devices = §8 `k8s_lab_controlplane_devices`, image ref = §8
  `k8s_lab_images_controlplane` + `k8s_lab_images_controlplane_fingerprint`,
  `installKubeadm = k8s_lab_install_kubeadm` (default `false`,
  §2.10), `instanceType = container`, unprivileged userns per
  `k8s_lab_unprivileged_nodes = true`;
* `LXCMachineTemplate` для workers — аналогично, с worker-профилями
  (`capi-worker` несёт eth1 RA cloud-init vendor-data из §13.6).

### Name-versioning contract

CAPI webhook запрещает менять большинство полей `ClusterClass` и
`*Template` CR'ов после того, как на них сослался Cluster. Значит
любая правка `values.yaml` / шаблона = новая версия чарта = новый
набор объектов с новыми именами; старые Cluster CR-ы продолжают
указывать на старый ClusterClass до контролируемого переключения.

Реализация — одна строка в каждом `metadata.name`:

```yaml
metadata:
  name: {{ include "capi-cluster-class.fullname" . }}-{{ .Chart.Version }}
```

`capi-workload-cluster` чарт (§16.3) собирает имя ClusterClass'а в
`spec.topology.class` по той же самой формуле из общего values
блока (`clusterClass.chartVersion`). Bump `Chart.yaml.version` →
helm upgrade создаёт новый ClusterClass + новые Template'ы, не
трогая существующие. Без этого любой `helm upgrade` падает с
`admission webhook denied: field is immutable` при первом же
реальном edit'е.

Отдельной §8-переменной для revision'а не заводим — единственный
источник истины `Chart.yaml.version`, через `.Chart.Version` он
доступен обоим чартам.

### Values layout (public interface chart'а)

```yaml
# charts/capi-cluster-class/values.yaml — структурная схема
clusterClass:
  name: capn-default           # prefix; итоговое имя = "{name}-{chart-version}"
kubernetes:
  version: ""                  # bind из §8 k8s_lab_kubernetes_version
capn:
  infrastructureSecretName: "" # bind из §8 k8s_lab_infrastructure_secret_name
  project: ""                  # bind из §8 k8s_lab_project_name
images:
  controlplane:
    ref: ""                    # §8 k8s_lab_images_controlplane
    fingerprint: ""            # §8 k8s_lab_images_controlplane_fingerprint
  worker:
    ref: ""                    # §8 k8s_lab_images_worker
    fingerprint: ""            # §8 k8s_lab_images_worker_fingerprint
installKubeadm: false          # §8 k8s_lab_install_kubeadm
profiles:
  controlplane: []             # §8 k8s_lab_controlplane_profiles
  worker:       []             # §8 k8s_lab_worker_profiles
devices:
  controlplane: {}             # §8 k8s_lab_controlplane_devices
  worker:       {}             # §8 k8s_lab_worker_devices
kubeProxy:
  nodePortAddresses: []        # §8 k8s_lab_kube_proxy_nodeport_addresses
clusterNetwork:
  pods:
    cidrBlocks: []             # dual-stack: [v4, v6] по §5
  services:
    cidrBlocks: []             # dual-stack: [v4, v6] по §5
```

`values.schema.json` ассертит required поля (chart fails на
`helm template` стадии если wiring не сошёлся из tfvars).

### CRD readiness guards

Каждый template-файл gate'ится по CAPI API availability:

```gotemplate
{{- if .Capabilities.APIVersions.Has "infrastructure.cluster.x-k8s.io/v1alpha2/LXCClusterTemplate" }}
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha2
kind: LXCClusterTemplate
...
{{- end }}
```

Если `clusterctl init` не завершился или не тот infrastructure provider
активен, `helm install` падает с информативной ошибкой `no resources
matched` вместо тихого `helm install` без CR'ов.

## 16.3. Chart: `charts/capi-workload-cluster/`

Содержит один Cluster CR, который ссылается на ClusterClass из
§16.2 по rendered name (`{classPrefix}-{classChartVersion}`), плюс
любые per-cluster ConfigMap/Secret'ы, которых не покрывает
ClusterClass (например, custom cloud-init extra-data; MVP baseline
такого не требует).

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
    deploymentName: md-0
clusterNetwork:
  pods:
    cidrBlocks: []             # dual-stack: [v4, v6]
  services:
    cidrBlocks: []             # dual-stack: [v4, v6]
```

`spec.topology.class` рендерится как `{{ .Values.clusterClass.name
}}-{{ .Values.clusterClass.chartVersion }}` — тот же формат, что
§16.2 использует для своего `metadata.name`. Обе стороны координируют
rotation через один знак (`clusterClass.chartVersion` передаётся в
оба helm_release из Terraform-уровня — см. §16.5).

### Namespace

Cluster CR живёт в namespace `capi-clusters` (по умолчанию; тоже
доставляется этим же чартом через `kind: Namespace` с
`helm.sh/hook: pre-install`). Отделяет CR от `capi-system` /
`capn-system` / `kube-system` → чище cleanup, отдельный RBAC при
масштабировании на несколько workload-кластеров.

## 16.4. Module: `terraform/modules/capi_cluster_class/`

Тонкая обёртка над `helm_release`. Inputs:

* путь к чарту (`chart_path`, default ссылается на
  `${path.module}/../../../charts/capi-cluster-class`);
* `chart_version` — прокидывается как `helm_release.version` и в
  `values.clusterClass.chartVersion` (нужно workload-модулю);
* плоский набор переменных, mirror'ящих §8 `k8s_lab_*` контракт
  (kubernetes version, infrastructure secret name, project name,
  image refs, profiles, devices, pod/service CIDRs);
* `namespace = capi-system` (куда CAPI controllers ожидают
  ClusterClass; можно override).

Outputs:

* `cluster_class_name` — rendered `{prefix}-{chart-version}` для
  workload-модуля;
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
  project_name                   = var.k8s_lab_project_name
  image_controlplane_ref         = var.k8s_lab_images_controlplane
  image_controlplane_fingerprint = var.k8s_lab_images_controlplane_fingerprint
  image_worker_ref               = var.k8s_lab_images_worker
  image_worker_fingerprint       = var.k8s_lab_images_worker_fingerprint
  install_kubeadm                = var.k8s_lab_install_kubeadm
  controlplane_profiles          = var.k8s_lab_controlplane_profiles
  worker_profiles                = var.k8s_lab_worker_profiles
  controlplane_devices           = var.k8s_lab_controlplane_devices
  worker_devices                 = var.k8s_lab_worker_devices
  kube_proxy_nodeport_addresses  = var.k8s_lab_kube_proxy_nodeport_addresses
  pod_cidrs                      = [var.k8s_lab_workload_pod_cidr_v4,
                                    var.k8s_lab_workload_pod_cidr_v6]
  service_cidrs                  = [var.k8s_lab_workload_service_cidr_v4,
                                    var.k8s_lab_workload_service_cidr_v6]
}

module "workload_cluster" {
  source = "../../../../../terraform/modules/capi_workload_cluster"

  chart_path = "${path.module}/../../../../../charts/capi-workload-cluster"

  cluster_name               = var.k8s_lab_workload_cluster_name
  cluster_namespace          = "capi-clusters"
  kubernetes_version         = var.k8s_lab_kubernetes_version
  cluster_class_name         = module.cluster_class.cluster_class_prefix
  cluster_class_chart_version = var.capi_cluster_class_chart_version
  controlplane_count         = var.k8s_lab_workload_controlplane_count
  worker_count               = var.k8s_lab_workload_worker_count
  pod_cidrs                  = [var.k8s_lab_workload_pod_cidr_v4,
                                var.k8s_lab_workload_pod_cidr_v6]
  service_cidrs              = [var.k8s_lab_workload_service_cidr_v4,
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
   в `capi-clusters/<cluster-name>` с `spec.topology.class` указывающий
   на правильный ClusterClass-имя.
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
