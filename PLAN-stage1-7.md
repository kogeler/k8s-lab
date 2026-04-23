Этот файл владеет §20..§22: Stage-1-wide meta — out-of-scope fence
(§20), self-review против исходного контракта (§21) и финальная
рекомендация execution order'а (§22). Нумерация §N сквозная по всем
plan-файлам; перекрёстные ссылки вида `§<номер>` валидны без указания
имени файла — см. `PLAN-stage1-common.md` header для полного file
lineup. Атомарный scope этого шарда — framing, которое применяется ко
**всему Stage 1** независимо от того, какой implementation-chunk
(§15..§19) сейчас в работе, поэтому coding-agent'у удобно держать эти
три секции отдельно от выполненной работы (§13..§14) и от ещё не
реализованных phases.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (Phases 5 + 5.05 Terraform CAPI + kubeconfig)
PLAN-stage1-4.md ................. §17      (Phases 5.1 + 5.2 + 5.3 Helm add-ons + in-cluster tests)
PLAN-stage1-5.md ................. §18      (Phases 6 + 7 pivot + workload clusters)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 meta: out-of-scope, self-review, recommendation)  <-- этот файл
```

---

# 20. Stage 1 — Explicitly out of scope for v1.0

Чтобы self-review был честным, это **не входит в v1.0**:

* inventories / host_vars / group_vars для реальных окружений;
* root orchestration/playbooks для deploy/destroy реальных окружений;
* environment-specific Terraform root modules;
* реальные secrets, tfvars, FQDN, IP allocations и LXD trust materials;
* remote Terraform backend;
* hosted CI path without local runner;
* backup/restore of etcd;
* automated Kubernetes upgrades through CAPI rollout;
* full day-1 addon suite beyond MetalLB/CNI;
* privileged CAPN container fallback as supported implementation;
* ingress controller selection;
* storage provisioner selection;
* cert-manager / public TLS;
* BGP/routed external design;
* production-grade observability;
* Stage 2 pivot as mandatory default.

---

# 21. Stage 1 — Саморевью контракта

Ниже — полный контрольный список.

## Учтено из исходного плана

* один bare metal host;
* LXC/LXD containers as Kubernetes nodes;
* Cluster API provider for Incus/LXD;
* Ansible + Terraform split;
* Infrastructure as Code only;
* почти ноль ручных шагов;
* возможность многократного recreate;
* modular roles/modules;
* локальное тестирование через Vagrant + Libvirt + Molecule;
* граница shared repo vs private consumer repos;
* жёсткий ownership split: Ansible = host/bootstrap/harness, Terraform = cluster objects/add-ons/guest networking, fixtures = thin wrappers;
* unprivileged CAPN container path fixed for v1.0;
* bootstrap cluster inside isolated LXC;
* no Docker on host;
* no long-lived host-level k8s;
* binaries downloaded by roles into `/opt`;
* Debian 13;
* Btrfs pool on a dedicated block device (см. §13.4 deviation — Step 3 отказался от path-based source из-за snap-confinement);
* two-NIC network design;
* external IPv6-only ingress NIC;
* internal dual-stack default-route NIC;
* MetalLB L2 as base LB;
* no public IPv4 on nodes;
* default route only on internal NIC;
* policy to suppress external RA default route;
* kubelet node identity on internal NIC;
* explicit validation and risks;
* accepted review fixes: external L2 validation через Helm test hook, CNI validation через Helm test hook, destroy contract, secrets story, LXD API path, CAPN profile baseline, optional pivot, typed vars, out-of-scope section, snap refresh policy.

## Добавлено по новому требованию

* local libvirt mock external IPv6 /64 network;
* mocked DHCPv6/RA delivery on second NIC in local VM;
* probe endpoint on same mocked external network for NodePort/MetalLB tests.
* shared repo contains only roles/modules/manifests/scripts/test harness;
* real environment composition moved to separate private repos;
* Terraform root modules in this repo exist only as test fixtures under `tests/fixtures`.
* validation gates (CNI, external L2) встроены в Helm test hooks на соответствующих chart release'ах и выполняются на реальном data plane, а не через research spikes.
* cluster add-ons are delivered through Terraform `helm_release` with pinned official/provider versions.

Libvirt network XML officially supports IPv6 virtual networks, DHCPv6 ranges and Router Advertisement–based default route behavior, which makes it suitable to emulate the future provider-facing external segment in the local lab. ([Libvirt][23])

## Осознанно не включено

* full day-1 app stack
* remote CI/backends
* backup/recovery/upgrades
* BGP/routed redesign

---

# 22. Stage 1 — Финальная рекомендация

Для coding agents я рекомендую именно такой execution order:

1. **не кодить весь мир сразу**;
2. сначала поднять **local libvirt harness**;
3. затем сделать **host bootstrap** и **LXD substrate** (включая
   `lxd_profiles` cloud-init baseline для worker/controlplane
   профилей — §13.6);
4. собрать **bootstrap cluster**, применить **Terraform CAPI fixture**,
   экспортировать kubeconfig target cluster и только затем применить
   **Terraform Helm add-ons fixture** (CNI chart + MetalLB chart, со
   встроенными Helm test hook'ами которые закрывают CNI и external L2
   acceptance в `helm_release` lifecycle — §17.5, §17.6);
5. только потом идти в optional pivot / post-pivot workload path;
6. MVP считать готовым, когда:

   * bootstrap cluster живёт в LXC;
   * workload cluster создаётся Terraform CAPI fixture’ом;
   * cluster add-ons ставятся отдельным Terraform Helm pass;
   * two-NIC contract соблюдается;
   * MetalLB VIP reachable externally;
   * `make clean-local` возвращает local harness в чистое состояние.

Это уже **полный рабочий план**, а не патч и не намерение.

Следующим сообщением я могу сделать уже **scaffold для реализации**:

* skeleton `Makefile`,
* skeleton `defaults/main.yml` по ролям,
* skeleton Terraform `modules/*` и `tests/fixtures/*`,
* skeleton Molecule scenarios / Vagrant harness / scripts,
* и список файлов в том порядке, в каком агент должен начать кодить.

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
