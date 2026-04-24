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
PLAN-stage1-3.md ................. §16      (Phases 5 + 5.05 Terraform CAPI + kubeconfig)
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

Содержит:

* Terraform `helm_release` resources for cluster add-ons;
* pinned `hashicorp/helm` provider contract;
* official upstream Helm charts for:

  * Flannel `flannel/flannel`; ([38], [39])
  * Calico `projectcalico/tigera-operator`; ([26])
  * MetalLB `metallb/metallb`; ([27])
* local wrapper Helm charts when cluster-specific CRs/policies are not cleanly expressible through upstream chart values alone.

Этот модуль применяется **только после** того, как у runner уже есть kubeconfig целевого кластера. Он является единственным владельцем:

* selected CNI installation (`Flannel` baseline or `Calico` advanced path);
* `MetalLB` installation;
* MetalLB configuration CR delivery via Helm-managed wrapper charts where needed.

Важно:

* `kube-proxy` policy остаётся Terraform-owned, но задаётся через kubeadm/bootstrap path, а не через Helm;
* Helm add-ons pass intentionally отделён от CAPI cluster creation pass, потому что provider configuration требует уже существующий kubeconfig target cluster.

## 17.2. Test fixtures — Helm add-ons

Test root modules в этом repo допускаются **только как test fixtures**
под локальный harness. Ниже — Helm add-ons subset (CAPI-only fixtures
живут в §16.6).

### `tests/fixtures/terraform/management-cluster/addons`

Provider:

* `helm` via `.artifacts/clusters/<management-cluster>.kubeconfig`

Назначение:

* поставить selected CNI/MetalLB и связанные Helm-managed cluster add-ons в target management cluster.

### `tests/fixtures/terraform/workload-clusters/lab-default/addons`

Provider:

* `helm` via `.artifacts/clusters/<workload-cluster>.kubeconfig`

Назначение:

* поставить selected CNI/MetalLB и связанные Helm-managed cluster add-ons в workload cluster.

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

Terraform add-ons test root:

* `tests/fixtures/terraform/workload-clusters/lab-default/addons`
* или `tests/fixtures/terraform/management-cluster/addons` для Stage 2

Сделать:

* использовать `hashicorp/helm` provider `3.1.1`;
* поставить выбранный CNI через официальный chart source:
  * `flannel/flannel` для known-good unprivileged baseline,
  * либо `projectcalico/tigera-operator` для experimental advanced path;
* поставить MetalLB через официальный chart source;
* поставить локальный wrapper Helm chart для MetalLB configuration
  CRs, если он нужен для `IPAddressPool`/`L2Advertisement`;
* применить **HA replica contract** (§2.12) ко всему, что
  ставится в workload cluster: каждый multi-replica-capable
  Deployment / StatefulSet → `replicas: 2` с antiaffinity на
  `kubernetes.io/hostname`. Если выбран Calico path —
  `calico-typha` с `replicas: 2`; MetalLB controller с
  `replicas: 2`. DaemonSet-компоненты (MetalLB speaker, Calico
  node, Flannel agent) автоматически получают по одной реплике
  на каждый worker — отдельный override не нужен.

Acceptance:

* Helm releases applied successfully to target cluster;
* cluster add-ons delivered only through Terraform Helm path;
* repeated Terraform apply/plan for the same add-ons pass is expected
  to be no-op;
* **HA pair contract (§2.12) выполнен:** для каждого workload-cluster
  Deployment / StatefulSet с replicas≥2 ассерт'ятся
  `status.readyReplicas == status.replicas` и
  `status.availableReplicas == status.replicas`; пара Pod'ов реально
  на двух разных worker-нодах (`spec.nodeName` уникален); для
  leader-elected компонентов (MetalLB controller, cert-manager если
  есть) ровно один holder lease, второй pod в standby.

## 17.5. Phase 5.2 — CNI Helm test

CNI release из §17.4 автоматически включает `helm.sh/hook: test` Job
(шейп в §17.3 — CNI probe Job). Phase 5.2 — это `helm test <cni-release>`
после `terraform apply`, который прогоняет этот Job и закрывает
acceptance Gate B из §6.

Сделать:

* первый Terraform-created cluster через selected fixture path;
* CNI delivered Terraform Helm add-ons module'ом (§17.1);
* `helm test` прогон: CNI probe Job валидирует Pod/Service networking
  для address-family контракта выбранного CNI;
* если `calico` провалил unprivileged path — controlled fallback на
  `flannel` через module inputs; fallback на privileged LXC запрещён
  (§2.8).

Acceptance:

* первый Terraform-created cluster usable с выбранным CNI;
* CNI probe Job завершается exit=0;
* результат зафиксирован как module/contract decision, не ad hoc test
  note.

## 17.6. Phase 5.3 — MetalLB Helm test (covers external L2 acceptance)

MetalLB release из §17.4 автоматически включает `helm.sh/hook: test`
Job (шейп в §17.3 — MetalLB probe Job). Phase 5.3 — это
`helm test <metallb-release>` после `terraform apply`, который закрывает
acceptance Gate A из §6 (external L2 viability) плюс smoke-тест MetalLB
VIP allocation.

Install MetalLB + prove:

* `IPAddressPool` и `L2Advertisement` применены;
* VIP allocation работает: LoadBalancer Service получает IPv6 VIP из
  `k8s_lab_metallb_vip_range_v6`;
* MetalLB probe Job завершается exit=0, что означает все четыре
  acceptance criteria Gate A выполнены (multiple MAC, RA reception,
  NDP, inbound from probe — §6);
* **HA pair контракт для MetalLB на workload cluster (§2.12):**
  `metallb-controller` Deployment имеет 2 ready replicas на разных
  worker-нодах, ровно один из них держит leader-election lease;
  `metallb-speaker` DaemonSet работает на обоих worker'ах. Failover-
  smoke допустим, но не обязателен на этой phase: достаточно
  доказать что обе реплики активно участвуют (один — active leader,
  второй — hot standby с up-to-date config).

Acceptance:

* LoadBalancer service gets IPv6 VIP;
* VIP reachable на external segment model (в local harness — bridge
  `br-ext6` внутри Vagrant VM после Step 9 pivot, см. §9.2;
  equivalent в prod — provider external L2 segment); доказывается
  ping'ом от external probe endpoint'а;
* Gate A четырёхкритериевая acceptance (§6) зелёная;
* HA pair контракт §2.12 для MetalLB выполнен.

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
