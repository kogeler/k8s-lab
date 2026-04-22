Этот файл владеет §18: Phases 5.1 + 5.2 + 5.3 — Terraform Helm
add-ons pass + CNI gate + early MetalLB smoke. Нумерация §N сквозная
по всем plan-файлам; перекрёстные ссылки вида `§<номер>` валидны без
указания имени файла — см. `PLAN-stage1-common.md` header для полного
file lineup. Атомарный scope этого шарда — всё, что касается cluster
add-ons layer поверх уже существующего target kubeconfig (см. §17.8)
плюс два connected gate'а (CNI viability и MetalLB VIP reachability),
чтобы coding-agent мог взять его в контекст отдельно от CAPI pass'а.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phase 2.5 external L2 gate)
PLAN-stage1-3.md ................. §16      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-4.md ................. §17      (Phases 5 + 5.05 Terraform CAPI + kubeconfig)
PLAN-stage1-5.md ................. §18      (Phases 5.1 + 5.2 + 5.3 Helm add-ons + CNI / MetalLB gates)  <-- этот файл
PLAN-stage1-6.md ................. §19      (Phases 6 + 7 pivot + workload clusters)
PLAN-stage1-7.md ................. §20      (Phase 8 destroy)
PLAN-stage1-8.md ................. §21..§23 (Stage 1 meta: out-of-scope, self-review, recommendation)
```

---

# 18. Phases 5.1 + 5.2 + 5.3 — Helm add-ons + CNI gate + MetalLB smoke

Этот раздел группирует Helm add-ons module (§18.1), его test fixtures
(§18.2), harness-only CNI gate role (§18.3), и три phases: 5.1
(apply Helm add-ons pass), 5.2 (CNI gate на первом Terraform-created
cluster) и 5.3 (early MetalLB smoke).

## 18.1. Module: `modules/cluster_addons_helm`

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

## 18.2. Test fixtures — Helm add-ons

Test root modules в этом repo допускаются **только как test fixtures**
под локальный harness. Ниже — Helm add-ons subset (CAPI-only fixtures
живут в §17.6).

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

## 18.3. Role: `gate_cni`

Harness-only validation role.

Делает:

* запускает проверку первого Terraform-created cluster;
* валидирует, что CNI, guest networking, kube-proxy policy и cluster add-ons, установленные Terraform CAPI + Helm passes, работают как ожидается;
* не устанавливает CNI и cluster add-ons самостоятельно.

## 18.4. Phase 5.1 — Helm add-ons pass

Terraform add-ons test root:

* `tests/fixtures/terraform/workload-clusters/lab-default/addons`
* или `tests/fixtures/terraform/management-cluster/addons` для Stage 2

Сделать:

* использовать `hashicorp/helm` provider `3.1.1`;
* поставить выбранный CNI через официальный chart source:
  * `flannel/flannel` для known-good unprivileged baseline,
  * либо `projectcalico/tigera-operator` для experimental advanced path;
* поставить MetalLB через официальный chart source;
* поставить локальный wrapper Helm chart для MetalLB configuration CRs, если он нужен для `IPAddressPool`/`L2Advertisement`.

Acceptance:

* Helm releases applied successfully to target cluster
* cluster add-ons delivered only through Terraform Helm path
* repeated Terraform apply/plan for the same add-ons pass is expected to be no-op

## 18.5. Phase 5.2 — CNI gate

Сделать:

* first Terraform-created cluster through the selected fixture path
* selected CNI delivered by Terraform Helm add-ons module, not by Ansible
* validate Pod/Service networking for the address-family contract claimed by the chosen CNI path
* if `calico` fails on unprivileged path, only controlled fallback to `flannel` through module inputs is allowed
* fallback to privileged LXC is explicitly forbidden

Acceptance:

* first Terraform-created cluster usable with chosen CNI
* result stored as module/contract decision, not as ad hoc test note

## 18.6. Phase 5.3 — Early MetalLB smoke

Install MetalLB on first usable cluster stage and verify:

* `IPAddressPool`
* `L2Advertisement`
* VIP allocation
* external reachability from probe endpoint

Acceptance:

* LoadBalancer service gets IPv6 VIP
* VIP reachable on `ext6-mock` / equivalent external segment model

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
