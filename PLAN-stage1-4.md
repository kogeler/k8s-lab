Этот файл владеет §17: chart-side acceptance contracts для Gate A
(external L2) и Gate B (CNI viability) из §6, плюс контракт
invocation'а helm test'ов из единого `workload_cluster` TF module'а
(§16.4). Нумерация §N сквозная по всем plan-файлам; перекрёстные
ссылки вида `§<номер>` валидны без указания имени файла — см.
`PLAN-stage1-common.md` header для полного file lineup. Атомарный
scope этого шарда — **только chart contracts + acceptance гейты**;
TF module structure + Phase 5 orchestration живут в §16.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (Phase 5 — workload_cluster TF module)
PLAN-stage1-4.md ................. §17      (Helm test acceptance contracts — Gate A + Gate B chart-side specs)  <-- этот файл
PLAN-stage1-5.md ................. §18      (Phase 6 + 7 — optional pivot)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 meta: out-of-scope, self-review, recommendation)
```

---

# 17. Helm test acceptance contracts — Gate A + Gate B chart-side specs

Acceptance Gate A (external L2 viability) и Gate B (CNI viability)
из §6 реализованы как **chart-side `helm.sh/hook: test` Pod'ы**,
шипящиеся вместе с теми чартами, которые ставят соответствующий
компонент:

* Gate B — `charts/cni-calico/templates/tests/cni-ready.yaml` (Step
  13);
* Gate A — `charts/metallb-config/templates/tests/metallb-vip.yaml`
  (Step 14).

Обе хук'и invoke'ятся **изнутри single TF module'а** §16.4
(`terraform/modules/workload_cluster/`) через `null_resource` +
`local-exec helm test <release> --kubeconfig <workload> --logs
--timeout 15m` после соответствующего `helm_release`. Failure
helm test'а валит `null_resource` с non-zero exit → TF apply
фейлится → state помечен tainted; повторный apply re-runs тест
после необходимого fix'а. Это превращает acceptance gate из
«ручного шага после deploy'а» в обязательную часть deploy'а.

Никаких отдельных probe-чартов (`charts/cni-probe/`,
`charts/metallb-probe/`) не shipped — chart-side hook'и живут
внутри тех же chart'ов, что владеют компонентами. Если в будущем
потребуется CNI-agnostic probe (для swap'а на Cilium / kube-router),
отдельный `charts/cni-probe/` можно ввести как chart-independent;
сейчас это DRY-нарушение без пользы.

## 17.1. Helm test invocation contract

`null_resource.helm_test_<gate>` каждого хука внутри §16.4 module:

```hcl
resource "null_resource" "helm_test_cni_calico" {
  triggers = {
    chart_version = var.cni_calico_chart_version
    release_id    = helm_release.cni_calico.id
    kubeconfig_sha = sha256(local.workload_kubeconfig)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      KUBECONFIG_FILE=$(mktemp)
      trap 'rm -f "$KUBECONFIG_FILE"' EXIT
      printf '%s' "$WORKLOAD_KUBECONFIG" > "$KUBECONFIG_FILE"
      chmod 0600 "$KUBECONFIG_FILE"
      helm test cni-calico \
        --namespace tigera-operator \
        --kubeconfig "$KUBECONFIG_FILE" \
        --logs --timeout 15m
    EOT
    environment = {
      WORKLOAD_KUBECONFIG = local.workload_kubeconfig
    }
  }

  depends_on = [helm_release.cni_calico]
}
```

Контракт:

* `helm` бинарь обязан быть на runner'е (где запускается `terraform
  apply`); module не пытается его установить — это responsibility
  consumer'а / CI image'а;
* `triggers` map включает chart version + release ID + kubeconfig
  hash, что заставляет null_resource перевыполниться при любой из
  трёх изменений (chart bump, release re-create, kubeconfig
  rotation). Idempotent re-run на зелёном кластере проходит
  быстро (helm test re-creates Pod через `before-hook-creation`
  политику);
* kubeconfig пишется в `mktemp` файл с mode 0600 и обязательно
  убирается на trap EXIT — keeps runner FS clean при любом исходе;
* `--timeout 15m` запас сверху самого щедрого chart-side timeout'а
  (Gate B `nodesReadyTimeoutSeconds: 600` + buffer);
* `--logs` гарантирует вывод тестового Pod'а в TF apply log на
  failure → диагностика не требует ручного `kubectl logs`.

Memory rule `feedback_ansible_native_first.md` симметрична для TF:
helm test через `local-exec` — единственный portable way (helm
provider 3.x не имеет `helm_test` resource); idempotency обеспечена
через `triggers` + chart-side `hook-delete-policy`.

## 17.2. Gate B — CNI viability acceptance

**Статус: shipped в Step 13 (2026-04-26, `charts/cni-calico/`
version 0.2.0).** Local wrapper над upstream
`projectcalico/tigera-operator` v3.31.5 через `Chart.yaml`
`dependencies:`. Substrate-required hardcoded'ы в Installation CR
(`templates/installation.yaml`):

* `cni.type: Calico`, `ipam.type: Calico` — chart-level invariant;
* `calicoNetwork.bgp: Disabled` — нет BGP infra на CAPN/LXD
  substrate;
* `calicoNetwork.linuxDataplane: Nftables` — native nf_tables, без
  iptables compat layer; пара с kube-proxy `mode: nftables` через
  KubeProxyConfiguration в `charts/capi-cluster-class` KCPT (§16.2
  Step 13). Calico docs формулируют это как контракт: kube-proxy
  должен match'ить dataplane mode;
* `calicoNetwork.ipPools[*].encapsulation: VXLAN` — IPIP IPv4-only,
  BGP infra нет, VXLAN единственный dual-stack-capable mode;
* `calicoNetwork.ipPools[*].nodeSelector: all()` — single-tier
  лаба, per-pool node tagging не нужен;
* `controlPlaneReplicas: 2` — HA pair §2.12 contract для
  calico-kube-controllers + calico-apiserver (operator gives them
  2 replicas + built-in podAntiAffinity).

Subchart toggle'ы (`tigera-operator` dependency): `installation.
enabled: false` (рендерим свою Installation CR), `apiServer.
enabled: true` (нужен для projectcalico.org aggregated APIs),
`goldmane: false` / `whisker: false` (observability extras —
optional, off в лаб-footprint'е). Typha остаётся auto-deployed
operator'ом.

### Acceptance hook shape

Helm test hook `templates/tests/cni-ready.yaml` — chart-level
acceptance драйвер. Single Pod, 6 фаз PASS/FAIL:

1. install kubectl from dl.k8s.io (alpine + busybox `wget`);
2. tigera-operator Deployment Available;
3. calico-system rollouts + Pods Ready;
4. workload Nodes Ready=True;
5. dual-stack `podCIDRs` per-Node (`spec.podCIDRs` содержит и v4
   и v6 CIDR);
6. live pod-to-pod ICMP4 + ICMP6 across two workers — driver Pod
   создаёт через `kubectl apply` две ephemeral probe Pod'ы
   (`k8s-lab-cni-probe-a/-b`) на разных worker'ах через
   podAntiAffinity + nodeAffinity NotIn control-plane, потом
   `kubectl exec` ping/ping -6 от одного к другому.

Image: alpine:3.21 + busybox `wget` для kubectl fetch + busybox
`ping` (-6 supported в alpine 3.21).

### RBAC / hook-policy substrate-required choices

* Test SA + ClusterRole + ClusterRoleBinding в
  `templates/tests/rbac.yaml` — **regular release resources**, НЕ
  `helm.sh/hook: test`. Hook-annotated не-Pod resources ломают
  `helm test --logs` non-zero exit'ом ("unable to get pod logs for
  <SA-name>"); helm walks the hook list and tries to fetch logs
  for each kind. SA/Role/Binding installed at `helm install` time,
  торнутся только на `helm uninstall`. ClusterRole grants:
  `core/{nodes,namespaces}` (get,list), `core/pods` (get,list,
  create,delete), `core/pods/exec` (create), `apps/{deployments,
  daemonsets}` (get,list,watch — для kubectl rollout status / wait
  gating).
* Test Pod hook-delete-policy = `before-hook-creation` only, НЕ
  `before-hook-creation,hook-succeeded`. Race между `Phase:
  Succeeded` и `helm test --logs` log-fetch step'ом: при коротком
  тесте (~15s) hook-succeeded реапает Pod до того как helm дойдёт
  до log pull, exit 1 c "pods not found". Test Pod выживает после
  Succeeded, реапается через before-hook-creation на следующем
  `helm test` или на `helm uninstall`.

### Step 13 acceptance status (2026-04-26)

End-to-end зелёный на свежем workload-кластере, провизионированном
через ClusterClass 0.5.0 (kube-proxy `mode: nftables` baked
declarative-style at kubeadm init, см. §16.2 Step 13). Прогон
последовательностью `make clean-local` → `make up` → `make -C
tests/molecule e2e-local-vagrant-converge` → `e2e-local-vagrant-verify`:

* converge — `failed=0 ok=307 changed=4`. Цепочка задач: substrate
  + bootstrap k3s → ClusterClass 0.5.0 + workload-cluster 0.5.0
  → helm CLI install on VM, Chart.yaml slurp, `helm dependency
  update` + `helm package` на runner'е, copy .tgz на VM, poll
  `<cluster>-kubeconfig` Secret в bootstrap, materialize workload
  kubeconfig в `/opt/capi-lab/etc/<cluster>.kubeconfig` на VM,
  `helm install cni-calico` на VM. Все chart helm tasks через
  `kubernetes.core.helm`.
* verify — `failed=0 ok=14 changed=4`. Workload-chart `helm test`
  10-фазный → `cp=3/3 worker=2/2 ALL TOPOLOGY CHECKS PASSED`,
  `classRef=capn-default-0-5-0`, AVAILABLE=True. cni-calico
  `helm test` 6-фазный → `Phase: Succeeded`: tigera-operator
  Available, calico-node DS + calico-kube-controllers rolled out,
  все Pods в calico-system Ready, все 5 workload Nodes
  Ready=True, dual-stack `podCIDRs` per-Node, dual-stack
  ICMP4/ICMP6 между ephemeral probe Pod'ами на разных worker-нодах
  через `kubectl exec`.

Chart-level live evidence на freshly-bootstrapped кластере:
kube-proxy ConfigMap содержит `mode: nftables` +
`conntrack.{maxPerCore: 0, min: 0}` напрямую от kubeadm init (без
ConfigMap patch'ей), все 5 kube-proxy Pods Running 0 restarts.

TF module §16.4 ещё не реализован; chart-side acceptance закрыт,
TF wrapper integration — Step 15+.

## 17.3. Gate A — External L2 viability acceptance

**Статус: shipped в Step 14 (2026-04-27, `charts/metallb-config/`
version 0.1.3 + `charts/metallb/` version 0.1.0).**

Two-release pair (см. §16.4 module helm_release chain):

* `charts/metallb/` — minimal subchart wrapper над upstream
  `metallb/metallb` 0.15.3 ([27]). Pin upstream version в Chart.yaml
  `dependencies:` block (§8 `k8s_lab_metallb_chart_version`).
  values.yaml хардкодит substrate-required toggles
  (`crds.enabled: true`, `frrk8s.enabled: false`,
  `speaker.frr.enabled: false`, `speaker.tolerateMaster: true`).
  Wrapper-owned templates: none — chart существует только чтобы
  ship upstream subchart с pinned values per memory rule
  "Chart-required values are hardcoded";
* `charts/metallb-config/` — wrapper-owned IPAddressPool +
  L2Advertisement CRs + helm test driver Pod (Gate A acceptance).
  bind'ит §8 `k8s_lab_metallb_vip_range_v6` +
  `k8s_lab_metallb_interface` +
  `k8s_lab_metallb_node_selector_labels`. No subchart deps.

Two-release split rationale: upstream metallb 0.15.3 ships CRDs
как regular `templates/crds/` (sub-dependency), не Helm
`crds/`-folder mechanism. Single-release wrapper с CRDs+CRs валит
Helm 3 pre-apply manifest validation с `no matches for kind
"IPAddressPool"`. Split разделяет CRDs registration (релиз 1) от
CR reconciliation (релиз 2).

**HA pair contract §2.12 deviation specific to MetalLB:** upstream
`metallb` chart 0.15.3 НЕ выставляет `controller.replicas` —
controller singleton by upstream design (allocates VIPs from pool
+ validates CRs, no state partitioning). HA delivered through
**speaker DaemonSet** (один replica per worker, leader-elected
per-VIP via memberlist gossip).

### Acceptance hook shape

Helm test hook `metallb-config/templates/tests/metallb-vip.yaml` —
chart-level acceptance драйвер. Single Pod, 8 фаз PASS/FAIL:

1. install kubectl from dl.k8s.io;
2. metallb controller Deployment Available (label-selector
   `app.kubernetes.io/component=controller`, release-name agnostic);
3. metallb speaker DaemonSet rolled out;
4. tear down stale demo Deployment + Service from prior run
   (idempotent re-runs);
5. apply demo Deployment (nginx-on-alpine, dual-family `listen 80;
   listen [::]:80;` через inline `sed` на default.conf) + Service
   type=LoadBalancer, `ipFamilies: [IPv6]` single-stack;
6. backend Pod Ready;
7. `Service.status.loadBalancer.ingress[0].ip` allocated AND
   in-pool (string-prefix sanity vs `pool.rangeV6`);
8. in-cluster HTTP probe FROM driver Pod (`wget [VIP]:80`).
   **Non-hairpin path**: driver Pod не endpoint Service'а;
   kube-proxy nftables DNAT short-circuits через
   `mark-for-masquerade`+DNAT в `endpoint-...` chain.
   `kubectl exec backend-pod -- wget VIP` вариант был бы hairpin
   (Calico default veth filter дропит backend-to-self-via-Service).

### Demo backend image rationale

`nginx:1.27-alpine` (не alpine + busybox httpd) — потому что:

1. alpine's base busybox build не включает httpd applet (живёт в
   `busybox-extras` package — потребовал бы apk-add at boot,
   flaky на fresh clusters со slow egress);
2. Service `ipFamilies: [IPv6]` требует v6-listening backend;
   nginx default config имеет только `listen 80;` (v4); chart
   driver добавляет `listen [::]:80;` через inline `sed` на
   default.conf, keeping rest intact.

Memory rule "Never use bitnami images" — nginx Inc. official, не
bitnami.

### External-segment acceptance (verify-side)

Chart-side hook закрывает только in-cluster path до VIP. Полный
Gate A path — **external curl от endpoint снаружи кластера** —
закрывается **fixture-side / consumer-side**:

* В local Vagrant harness: Molecule e2e-local verify task на VM
  (НЕ delegate_to runner) делает `ansible.builtin.uri
  url=http://[<VIP>]:80/` через `ext6-ra-peer`
  (`2001:db8:42:100::1/64`) → bridge `br-ext6` → eth1 speaker
  leader → kube-proxy DNAT → backend Pod;
* В TF module §16.4: chart-side helm test через `null_resource` —
  это in-cluster gate; consumer'у который хочет внешнюю проверку,
  module эмиттит `output "metallb_vip"` который consumer может
  curl'нуть через свой external probe endpoint.

Демо Deployment + Service driver-managed (создаются driver Pod'ом
через `kubectl apply`, не аннотированы `helm.sh/hook: test`) —
переживают `Phase: Succeeded` и доступны для external probe'а.
Реапаются на следующем `helm test` (driver Pod's фаза [4/8]
cleanup) или на `helm uninstall`.

### Step 14 acceptance status (2026-04-27)

End-to-end зелёный на свежем workload-кластере, провизионированном
через ClusterClass 0.5.0 + workload-cluster 0.5.0 + cni-calico
0.2.0 + metallb 0.1.0 + metallb-config 0.1.3.

Прогон `make -C tests/molecule e2e-local-vagrant-converge` →
`make -C tests/molecule e2e-local-vagrant-verify`:

* converge — `failed=0 ok=318 changed=7`. Цепочка задач: existing
  substrate + bootstrap + ClusterClass + workload + Calico → новый
  блок MetalLB delivery (read Chart.yaml → helm dep update + helm
  package on runner → copy .tgz to VM → helm install on VM via
  `kubernetes.core.helm`). Два helm install'а: upstream metallb
  wrapper (`metallb-system` namespace, `create_namespace: true`),
  затем metallb-config wrapper (`create_namespace: false`).
* verify — `failed=0 ok=20 changed=5`. Три helm test'а зелёные:
  workload chart (10 фаз), cni-calico (6 фаз), metallb-config
  (8 фаз). Compact-state debug:
  `metallb VIP=2001:db8:42:100::200 external_status=200`. Полный
  Gate A path: external curl от VM → `ext6-ra-peer` → bridge
  `br-ext6` → eth1 speaker leader → kube-proxy → backend nginx Pod
  → 200 OK body "ok\n".

Memory rules применённые в Step 14:
* `feedback_chart_required_values_hardcoded.md` — IPAddressPool /
  L2Advertisement substrate-required fields в шаблонах;
* `feedback_no_bitnami_images.md` — alpine для driver Pod, nginx
  для backend (нет bitnami);
* `feedback_test_artifact_naming.md` — `k8s-lab-metallb-demo-*`
  prefix для demo stack;
* `feedback_pause_before_role_test.md` — chart code сделан, тесты
  выявили nginx v4-only listen + hairpin avoidance fixes;
* `feedback_plan_is_fallible.md` — single-wrapper precedent
  пытался apply здесь, но архитектура metallb subchart CRDs
  (templates/crds/, не Helm crds/) требует two-release split.
  PLAN был прав в исходном two-release дизайне; повторно
  подтверждено через runtime evidence.

TF module §16.4 ещё не реализован; chart-side + verify-side
acceptance закрыт, TF wrapper integration — Step 15+.

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
