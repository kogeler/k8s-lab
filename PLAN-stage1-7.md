Этот файл владеет §20..§22: Stage 1 closure — финальный статус
(§20), self-review против исходного контракта (§21) и итоговая
рекомендация execution order'а для consumer'ов (§22). Нумерация §N
сквозная по всем plan-файлам; перекрёстные ссылки вида `§<номер>`
валидны без указания имени файла — см. `PLAN-stage1-common.md` header
для полного file lineup.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (workload_cluster TF module)
PLAN-stage1-4.md ................. §17      (Helm test contracts — Gate A + Gate B chart-side specs)
PLAN-stage1-5.md ................. §18      (pivot mgmt-1 → self-hosted)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 closure + self-review + recommendation)  <-- этот файл
```

---

# 20. Stage 1 — Closure

Stage 1 v1.0 — **закрыт**. Все §22 acceptance criteria выполнены
end-to-end; canonical flow §3 прогоняется зелёным через единый
Molecule scenario `tests/molecule/e2e-local/` (`make test-local-e2e`).

Repo-boundary (concrete environment composition — inventories,
host_vars, secrets, FQDN, env-specific TF root modules, TF backends
для реальных площадок) **по дизайну вне scope этого repo** — это
обязанность отдельных private consumer repos. См. §2.5 как
authoritative source contract границы.

---

# 21. Stage 1 — Саморевью контракта

Финальный контрольный список против исходного замысла.

## Реализовано

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
* жёсткий ownership split: Ansible = host/bootstrap/harness,
  Terraform = cluster objects/add-ons/guest networking, fixtures =
  thin wrappers;
* unprivileged CAPN container path — substrate-инвариант (см. §2.8);
* bootstrap cluster inside isolated LXC;
* no Docker on host;
* no long-lived host-level k8s;
* binaries downloaded by roles into `/opt`;
* Debian 13;
* Btrfs pool on a dedicated block device (см. §13.4 deviation —
  Step 3 отказался от path-based source из-за snap-confinement);
* two-NIC network design;
* external IPv6-only ingress NIC;
* internal dual-stack default-route NIC;
* MetalLB L2 as base LB;
* no public IPv4 on nodes;
* default route only on internal NIC;
* policy to suppress external RA default route;
* kubelet node identity on internal NIC;
* explicit validation and risks;
* canonical CAPI bootstrap-and-pivot flow (§3) — pivot mandatory,
  workload-cluster создаётся ТОЛЬКО на self-hosted mgmt-1
  post-pivot;
* helm-first delivery (§2.9): все K8s-объекты через Terraform
  `helm_release` или Molecule `kubernetes.core.helm`, никаких
  raw manifests;
* validation gates через chart-side `helm.sh/hook: test` Pod'ы
  (Gate A external L2 + Gate B CNI viability), invoked в e2e-local
  converge перед pivot и в verify post-workload;
* dual-stack networking (IPv4 + IPv6 pod/service CIDR'ы) с Calico
  VXLAN encap, kube-proxy в nftables mode, MetalLB IPv6 VIP'ы.

## Local harness

* libvirt mock external IPv6 /64 segment через in-VM radvd на
  veth-паре `ext6-ra` ↔ `ext6-ra-peer` (§9.2 Step 9 pivot);
* mocked DHCPv6/RA delivery на eth1 контейнерных нод через тот же
  in-VM radvd source (cloud-init applies sysctl + systemd-networkd
  drop-in через `KubeadmConfigSpec.files`);
* probe endpoint для NodePort/MetalLB external curl tests'ов — сам
  `ext6-ra-peer` (имеет global IPv6 в external prefix, Gate A
  out-of-cluster acceptance ходит через него).

## Repo policy

* shared repo содержит только roles / modules / charts / scripts /
  test harness;
* real environment composition уехал в private consumer repos;
* Terraform root modules в этом repo существуют только как test
  fixtures под `tests/fixtures/`.

## Validation

* Gate A external L2 (`charts/metallb-config/templates/tests/...`) +
  Gate B CNI viability (`charts/cni-calico/templates/tests/...`) —
  in-cluster acceptance драйверы на live data plane, не research
  spikes.
* Gate A external curl out-of-cluster proof — ходит из VM через
  `ext6-ra-peer` на MetalLB-allocated VIP.

## Cluster add-ons

* Cluster add-ons делают Helm `helm_release` (TF route) или
  `kubernetes.core.helm` (Molecule e2e) с pinned official/wrapper
  versions (§8a verified version log).

---

# 22. Stage 1 — Финальная рекомендация для consumer'ов

Для consumer'а, который собирает свою concrete-environment composition
поверх этого reusable repo:

1. подключить `ansible/roles/`, `terraform/modules/workload_cluster/`,
   `charts/*` как git submodule / ansible-collection / vendored
   Terraform module — НЕ копировать содержимое, чтобы можно было
   pull bug fixes из upstream;
2. написать concrete inventory + host_vars / group_vars в private
   repo (§2.5);
3. подключить `make test-local-e2e` flow (если consumer сохраняет
   Vagrant harness) или эквивалент с реальным Debian 13 host'ом
   (CI runner / dedicated lab box) для regression testing на каждый
   bump charts / role versions;
4. для production deploy реального workload'а:
   * single deploy = bootstrap → mgmt-1 helm install → pivot →
     workload helm install. Canonical sequence §3.1; в скрипте
     consumer'а это playbook поверх ролей этого repo (или прямой
     copy `tests/molecule/e2e-local/converge.yml` под consumer'ские
     vars);
   * additional workload'ы поверх уже-self-hosted mgmt-1 — через
     `tests/fixtures/terraform/workload-clusters/lab-default/`
     fixture root style (TF apply на existing mgmt.kubeconfig).

Stage 1 v1.0 — **полный рабочий substrate** для Kubernetes-в-LXC
лаба с canonical CAPI bootstrap-and-pivot flow, dual-stack networking
и helm-first delivery model. Готов к copy-and-customize в consumer
repo's.

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
