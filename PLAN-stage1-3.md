Этот файл владеет §16: Phases 3.5 + 4 — bootstrap management cluster.
Нумерация §N сквозная по всем plan-файлам; перекрёстные ссылки вида
`§<номер>` валидны без указания имени файла — см.
`PLAN-stage1-common.md` header для полного file lineup. Атомарный scope
этого шарда — всё, что нужно, чтобы из голого LXC-bootstrap-инстанса
получить работающий management cluster с CAPN provider (binaries
фетч, k3s, clusterctl init, CAPN identity secret, API publishing,
артефакты).

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phase 2.5 external L2 gate)
PLAN-stage1-3.md ................. §16      (Phases 3.5 + 4 bootstrap management cluster)  <-- этот файл
PLAN-stage1-4.md ................. §17      (Phases 5 + 5.05 Terraform CAPI + kubeconfig)
PLAN-stage1-5.md ................. §18      (Phases 5.1 + 5.2 + 5.3 Helm add-ons + CNI / MetalLB gates)
PLAN-stage1-6.md ................. §19      (Phases 6 + 7 pivot + workload clusters)
PLAN-stage1-7.md ................. §20      (Phase 8 destroy)
PLAN-stage1-8.md ................. §21..§23 (Stage 1 meta: out-of-scope, self-review, recommendation)
```

---

# 16. Phases 3.5 + 4 — Bootstrap management cluster

Этот раздел группирует всё, что нужно для standing up bootstrap
management cluster в LXC: роли (§16.1..§16.6) и сами phases — 3.5
(binary_fetch, отодвинутый из Phase 1) и 4 (k3s + clusterctl + CAPN
identity secret + API publish + artifacts export).

## 16.1. Role: `binary_fetch`

Скачивает в `/opt/capi-lab/bin`:

* `kubectl`
* `clusterctl`
* `k3s`
* optional `jq`, `yq`

Требования:

* version pinning
* checksum verification
* no custom apt repos
* owner/group/mode deterministic

## 16.2. Role: `bootstrap_k3s`

Внутри bootstrap LXC:

* раскладывает `k3s`, `kubectl`, `clusterctl`;
* стартует `k3s server` с:

  * `--tls-san <host IP/FQDN>`
  * `--disable=servicelb`
  * `--disable=traefik`
  * при необходимости `--disable=local-storage`

K3s docs и FAQ explicitly support disabling packaged components like `traefik` and `servicelb`, and `server` docs support `--tls-san`. ([K3s][18])

## 16.3. Role: `bootstrap_clusterctl`

Делает:

* кладёт pinned `clusterctl.yaml`;
* выполняет `clusterctl init --infrastructure incus[:version]`;
* включает `CLUSTER_TOPOLOGY=true`, если используем CAPN default ClusterClass/topology

`clusterctl init` automatically installs core, kubeadm bootstrap and kubeadm control-plane providers; clusterctl config file supports repository and cert-manager overrides. ([main.cluster-api.sigs.k8s.io][7])

## 16.4. Role: `bootstrap_capn_secret`

Создаёт Secret с:

* `server`
* `server-crt`
* `client-crt`
* `client-key`
* `project`
* label `clusterctl.cluster.x-k8s.io/move: "true"` если `pivot_enabled=true`

CAPN identity secret format это прямо описывает. ([capn.linuxcontainers.org][19])

## 16.5. Role: `bootstrap_api_publish`

Публикует bootstrap API наружу на host, например:

* `16443/tcp -> capi-bootstrap-0:6443`

Требования:

* source-IP restricted
* rollback support
* no permanent exposure after pivot/destroy
* `allowed_source_ips` не может трактоваться как allow-all
* при `bootstrap.api_publish_acl_mode=strict` пустой список `allowed_source_ips` должен приводить к fail
* auto-derivation ACL допускается только в local harness mode

## 16.6. Role: `export_artifacts`

Создаёт:

* `.artifacts/bootstrap.kubeconfig`
* `.artifacts/mgmt.kubeconfig`
* `.artifacts/clusters/<cluster>.kubeconfig`
* `.artifacts/*.auto.tfvars.json`

## 16.7. Phase 3.5 — binary_fetch (отложен из Phase 1)

**Статус: не выполнено.**

Перенесён из Phase 1 в Step 2 — kubectl / clusterctl / k3s впервые
нужны только на Phase 4 (`bootstrap_k3s`). См. §16.1.

Сделать:

* скачать pinned версии `kubectl`, `clusterctl`, `k3s` в
  `/opt/capi-lab/bin` с checksum verification;
* опционально — `jq`, `yq`.

Acceptance:

* файлы присутствуют, checksum верифицированы, owner/group/mode
  детерминированы.

## 16.8. Phase 4 — bootstrap management cluster

**Статус: не выполнено.**

Роли:

* `bootstrap_k3s`
* `bootstrap_clusterctl`
* `bootstrap_capn_secret`
* `bootstrap_api_publish`

Acceptance:

* bootstrap API reachable from runner
* `clusterctl init` done
* providers healthy
* LXD identity secret present

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
