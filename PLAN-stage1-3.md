Этот файл владеет §16: Phases 5 + 5.05 — Terraform CAPI pass + export
target kubeconfig. Нумерация §N сквозная по всем plan-файлам;
перекрёстные ссылки вида `§<номер>` валидны без указания имени файла —
см. `PLAN-stage1-common.md` header для полного file lineup. Атомарный
scope этого шарда — Terraform modules и CAPI-only test fixtures плюс
phases, которые применяют CAPI pass и материализуют target kubeconfig
(без Helm add-ons — они живут в §17).

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (Phases 5 + 5.05 Terraform CAPI + kubeconfig) <-- этот файл
PLAN-stage1-4.md ................. §17      (Phases 5.1 + 5.2 + 5.3 Helm add-ons + in-cluster tests)
PLAN-stage1-5.md ................. §18      (Phases 6 + 7 pivot + workload clusters)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 meta: out-of-scope, self-review, recommendation)
```

---

# 16. Phases 5 + 5.05 — Terraform CAPI + kubeconfig export

Terraform modules в этом repo являются **единственным владельцем**:

* Cluster API objects;
* machine templates и bootstrap data;
* guest networking configuration CAPN-managed nodes;
* kube-proxy policy;
* cluster add-ons и cluster-scoped manifests.

## 16.1. Terraform modules ownership context

`manifests/*`, `networkd/*`, `kube-proxy/*`, `kubeadm-patches/*` здесь считаются reusable inputs для Terraform modules, а не самостоятельным ownership layer.

## 16.2. Module: `modules/capi_cluster_class`

Содержит:

* ClusterClass contract;
* `KubeadmControlPlaneTemplate`;
* `KubeadmConfigTemplate` для workers;
* общие variables:

  * secretRef
  * loadBalancer
  * instance config
  * Kubernetes version
  * image refs
  * profiles/devices
  * node bootstrap/networking policy references

Это модуль, который собирает bootstrap/control-plane contract и связывает его с infrastructure templates. CABPK даёт для этого `files`, `preKubeadmCommands`, `postKubeadmCommands`, `kubeletExtraArgs` и patch delivery mechanisms. ([20], [29], [28])

## 16.3. Module: `modules/capi_lxc_templates`

Содержит:

* `LXCClusterTemplate`
* `LXCMachineTemplate` для CP
* `LXCMachineTemplate` для workers

В templates должны параметризоваться:

* `instanceType: container`
* `profiles`
* `devices`
* `image`
* `installKubeadm`
* target/flavor

Этот модуль отвечает только за **infrastructure templates** и не владеет kubeadm/bootstrap contents. CAPN API и default template это поддерживают. ([capn.linuxcontainers.org][21])

## 16.4. Module: `modules/capi_management_cluster`

Содержит:

* target self-hosted management cluster;
* default topology = `k8s_lab_management_controlplane_count` (1)
  + `k8s_lab_management_worker_count` (1) — см. §8 контракт
  переменных. Это **single-CP + single-worker** footprint, минимально
  жизнеспособный для self-hosted CAPI: один controller на каждой роли,
  достаточно квоты в LXD под bootstrap-LXC, никакого HA;
* Cluster topology instantiation на базе shared ClusterClass.

Не содержит Helm releases и не является владельцем add-ons pass.

## 16.5. Module: `modules/capi_workload_cluster`

Содержит:

* любой lab/workload cluster;
* default topology = `k8s_lab_workload_controlplane_count` (2)
  + `k8s_lab_workload_worker_count` (2) — см. §8 контракт
  переменных. Это **multi-CP + multi-worker** footprint: 2 CP-ноды
  заставляют kubeadm-control-plane controller реально проходить
  multi-CP reconciliation (etcd quorum, leader-election на CP), а 2
  worker-ноды дают MetalLB / Calico failover-плоскость для §17.x add-on
  тестов;
* dual-stack params;
* Cluster topology instantiation на базе shared ClusterClass;
* wiring к shared templates/class variables.

Не содержит Helm releases и не является владельцем add-ons pass.

## 16.6. Test fixtures — CAPI

Test root modules в этом repo допускаются **только как test fixtures**
под локальный harness. Ниже — CAPI-only subset (Helm add-ons fixtures
живут в §17.2). Реальные environment root modules должны жить в
отдельных private repos.

### `tests/fixtures/terraform/management-cluster/capi`

Используется только если `k8s_lab_pivot_enabled=true` в local e2e или integration test.
Provider:

* `kubernetes` via `.artifacts/bootstrap.kubeconfig`

Назначение:

* создать target management cluster через CAPI objects;
* не ставить add-ons.

### `tests/fixtures/terraform/workload-clusters/lab-default/capi`

В MVP:

* provider = bootstrap cluster kubeconfig
  В Stage 2:
* provider = `.artifacts/mgmt.kubeconfig`

Назначение:

* создать workload cluster через CAPI objects;
* не ставить add-ons.

Terraform provider configuration for `kubernetes`/`helm` требует live API access уже на этапе plan/apply, поэтому bootstrap or target kubeconfig must exist before the corresponding Terraform pass starts. ([25])

## 16.7. Phase 5 — Terraform against bootstrap cluster

### MVP

Terraform CAPI test root:

* `tests/fixtures/terraform/workload-clusters/lab-default/capi`

### Stage 2

Terraform CAPI test root:

* `tests/fixtures/terraform/management-cluster/capi`

Acceptance:

* Terraform CAPI fixtures create Cluster API objects successfully
* target cluster control plane is reachable enough to export kubeconfig

## 16.8. Phase 5.05 — Export target kubeconfig

Сделать:

* дождаться доступности target cluster API;
* экспортировать kubeconfig в `.artifacts/clusters/<cluster>.kubeconfig`;
* зафиксировать artifact path для последующего Helm add-ons pass.

Acceptance:

* target cluster kubeconfig materialized on runner
* next Terraform pass can use Helm provider against target cluster

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
