Этот файл владеет §15: Phases 3.5 + 4 — bootstrap management cluster.
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
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)  <-- этот файл
PLAN-stage1-3.md ................. §16      (Phases 5 + 5.05 CAPI topology via Helm)
PLAN-stage1-4.md ................. §17      (Phases 5.1 + 5.2 + 5.3 Helm add-ons + in-cluster tests)
PLAN-stage1-5.md ................. §18      (Phases 6 + 7 pivot + workload clusters)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 meta: out-of-scope, self-review, recommendation)
```

---

# 15. Phases 3.5 + 4 — Bootstrap management cluster

Этот раздел группирует всё, что нужно для standing up bootstrap
management cluster в LXC: роли (§15.1..§15.6) и сами phases — 3.5
(binary_fetch, отодвинутый из Phase 1) и 4 (k3s + clusterctl + CAPN
identity secret + API publish + artifacts export).

## 15.1. Role: `binary_fetch`

**Статус: выполнено в Step 4 (2026-04-22) — полное описание, deviation
notes и checksum-style breakdown живут в §13.8.**

Скачивает в `/opt/capi-lab/bin`:

* `kubectl`
* `clusterctl`
* `k3s`
* optional `jq`, `yq` (отложено — потребители не запросили)

Требования:

* version pinning (трекают §8a verified version log)
* checksum verification (см. §13.8 implementation note про три
  checksum styles: `plain`/`manifest`/`pinned`)
* no custom apt repos
* owner/group/mode deterministic

## 15.2. Role: `bootstrap_k3s`

**Статус: выполнено в Step 4 (2026-04-22) — полное описание,
substrate-required hardcoded флаги, execution-model rationale
(`lxc exec` shell вместо `community.general.lxd` connection plugin)
и end-to-end verify живут в §13.9. Step 4 также потребовал
substrate-расширений в §13.3 / §13.6 (interception=allow,
unix-char=allow, `/dev/kmsg` device, syscalls.intercept.*,
raw.lxc apparmor=unconfined, restart-on-profile-change) — см.
их Step 4 deviation секции.**

Внутри bootstrap LXC:

* раскладывает `k3s` (kubectl / clusterctl остаются на host'е,
  потребляются `bootstrap_clusterctl` §15.3 в следующих Step'ах);
* стартует `k3s server` с:

  * `--disable-cloud-controller` (substrate-required, hardcoded)
  * `--kubelet-arg=feature-gates=KubeletInUserNamespace=true`
    (substrate-required, hardcoded)
  * `--disable=servicelb` (default)
  * `--disable=traefik` (default)
  * `--tls-san <host IP/FQDN>` опционально через
    `bootstrap_k3s_tls_san: []`
  * `--cluster-cidr` / `--service-cidr` опционально (Step 4 не
    требовал — k3s defaults достаточно)
  * `--disable=local-storage` отложено (см. §15.6 export_artifacts —
    локальный storage может потребоваться pivot'у)

K3s docs и FAQ explicitly support disabling packaged components like `traefik` and `servicelb`, and `server` docs support `--tls-san`. ([K3s][18])

## 15.3. Role: `bootstrap_clusterctl`

**Статус: выполнено в Step 6 (2026-04-23) — полное описание,
implementation notes (k8s_info native-first, idempotence pre-check
на existing CAPN deployment, async clusterctl init, server URL
rewrite в host-side kubeconfig, jsonpath quirk для CAPI Provider CR
top-level fields), substrate-required values в `vars/main.yml`
живут в §13.10.**

Делает:

* кладёт pinned `clusterctl.yaml`;
* выполняет `clusterctl init --infrastructure incus[:version]`;
* включает `CLUSTER_TOPOLOGY=true`, если используем CAPN default
  ClusterClass/topology;
* материализует host-side kubeconfig из in-container `k3s.yaml` с
  переписанным `clusters[].cluster.server` под container-eth0 IPv4.

`clusterctl init` automatically installs core, kubeadm bootstrap and kubeadm control-plane providers; clusterctl config file supports repository and cert-manager overrides. ([main.cluster-api.sigs.k8s.io][7])

## 15.4. Role: `bootstrap_capn_secret`

**Статус: выполнено в Step 6 (2026-04-23) — полное описание,
deviation notes (PEM→base64 DER strip для LXD trust API, async PATCH
core.https_address с readiness poll, restriction-drift assertion на
existing trust entries) и substrate-required values в `vars/main.yml`
живут в §13.11.**

Создаёт Secret с:

* `server`
* `server-crt`
* `client-crt`
* `client-key`
* `project`
* label `clusterctl.cluster.x-k8s.io/move: "true"` если `k8s_lab_pivot_enabled=true`

CAPN identity secret format это прямо описывает. ([capn.linuxcontainers.org][19])

Дополнительно к собственно Secret-материализации, роль владеет двумя
host/LXD-уровневыми операциями (минимально-инвазивный scope, не
пересекается с lxd_host's snap/socket-ownership):

* PATCH `core.https_address: <bridge-ipv4>:8443` на LXD daemon —
  binding только на `capi-int` LXD-managed bridge IP, чтобы CAPN
  внутри bootstrap LXC мог дотянуться до `/1.0/...` через project
  internal subnet, а на host'овые внешние NIC ничего не торчало;
* регистрация client TLS cert как `restricted: true + projects:
  [capi-lab]` trust entry — CAPN не сможет коснуться чужих проектов
  (даже если будут операторские LXD-сущности вне `capi-lab`).

Public defaults `bootstrap_capn_secret_name` и
`bootstrap_capn_secret_pivot_enabled` sourced из плана §8 globals
(`k8s_lab_infrastructure_secret_name` и `k8s_lab_pivot_enabled`
соответственно), что обеспечивает single-source-of-truth для
координации с Phase 5+ Cluster CR's `identityRef` и `clusterctl move`
workflow.

## 15.5. Публикация bootstrap API (LXD proxy device, не отдельная роль)

Ранее Stage 1 содержал отдельную роль `bootstrap_api_publish`,
которая разворачивала nftables DNAT + ACL поверх хостового файрвола.
Это решение removed в Step 7 (2026-04-23) по двум причинам:

* **Host firewall — вне scope этого repo** (см. §11.4). В проде
  хостовой файрвол — собственность оператора; роль не имеет права
  писать в distro-owned nftables tables, даже в изолированную
  `table inet k8slab_api_publish`.
* **Source-IP ACL избыточен поверх mTLS** kubeconfig'а. Bootstrap
  API всегда требует клиентский cert; дополнительная IP-фильтрация
  не даёт полезной защиты и удваивает поверхность ошибок.

Публикация TCP-порта bootstrap-контейнера наружу (если оператор
хочет прокинуть API, например, для Terraform с dev-машины)
реализуется **декларативно через LXD proxy device**, управляемый
уже существующей ролью `lxd_bootstrap_instance` (§13.7). Роль
прокидывает любой словарь `lxd_bootstrap_instance_devices` в
нативный модуль `community.general.lxd_container`, который
patch'ит live config инстанса через LXD REST.

Пример host_vars публикации k3s API на `<host>:16443`:

```yaml
lxd_bootstrap_instance_devices:
  k3s-api:
    type:    proxy
    listen:  "tcp:0.0.0.0:16443"
    connect: "tcp:127.0.0.1:6443"
    bind:    host    # LXD daemon слушает на хосте, forward в контейнер
```

Семантика proxy device bind=host:

* LXD daemon поднимает userspace listener на `<listen>` на хосте,
  принимает соединения, делает `connect()` в контейнер по
  `<connect>`. Никаких правил в distro-owned nftables.
* При `lxc delete` контейнера или `lxc config device remove`
  listener гасится автоматически. Rollback — zero-code.
* Source-IP filter, если всё-таки нужен в конкретном окружении, —
  задача внешнего хостового файрвола consumer repo (например
  `iptables`/`ufw`-based роль оператора), а не Stage 1 substrate.

LXD proxy device также поддерживает `bind: instance` (listener
внутри контейнера) и `nat: true` (LXD сам ставит kernel DNAT в
СВОЕЙ изолированной nftables table). Для Stage 1 lab нам достаточно
простейшего `bind: host`.

## 15.6. Role: `export_artifacts`

**Статус: выполнено в Step 8 (2026-04-23) — полное описание,
execution model (`delegate_to: localhost` с `become: false + run_once:
true` для runner-side файлов), substrate-required filename
conventions + file mode контракт, идемпотентный slurp+copy паттерн,
optional server URL rewrite (runner-reach handling через публичный
`export_artifacts_bootstrap_api_server_url`), Phase 5 smoke-test через
`kubernetes.core.k8s_info` из verify scenario'а — живут в §13.12.
End-to-end прогон зелёный (2026-04-23).**

Stage 1 MVP-скоуп (Step 8):

* `.artifacts/bootstrap.kubeconfig` — shipped с host'а (материализован
  `bootstrap_clusterctl` §15.3), mode 0600 на runner'е;
* `.artifacts/bootstrap.auto.tfvars.json` — fact-bundle для Phase 5
  Terraform fixture'ов (TF auto-load'ит `*.auto.tfvars.json` glob'ом);
  ключи зеркалят §8 `k8s_lab_*` globals 1:1 + производные
  `k8s_lab_bootstrap_kubeconfig_path` / `_api_server_url`;
* `.artifacts/clusters/` — пустой subdir, зарезервирован для Phase
  5.05 per-cluster kubeconfig'ов.

Отложено до Phase 5+:

* `.artifacts/mgmt.kubeconfig` — зависит от target self-hosted
  management cluster'а (Phase 6+ / §18); роль расширяется новой
  `tasks/mgmt_kubeconfig.yml` без breaking change для Phase 4 caller'ов.
* `.artifacts/clusters/<cluster>.kubeconfig` — Phase 5.05 / §16.8.

## 15.7. Phase 3.5 — binary_fetch (отложен из Phase 1)

**Статус: выполнено в Step 4 (2026-04-22) — см. §14.5.**

Перенесён из Phase 1 в Step 2 — kubectl / clusterctl / k3s впервые
нужны только на Phase 4 (`bootstrap_k3s`). См. §15.1 / §13.8.

Сделано:

* скачаны pinned версии `kubectl`, `clusterctl`, `k3s` в
  `/opt/capi-lab/bin` с checksum verification;
* `jq` / `yq` отложены — на Step 4 потребители не запросили; могут
  быть добавлены позже без breaking-change ролей через
  `binary_fetch_*_enabled` toggles или новый бинарь в каталоге.

Acceptance: достигнуто (см. §14.5).

## 15.8. Phase 4 — bootstrap management cluster

**Статус: выполнено в Step 4 + Step 6 + Step 8 — см. §14.6.**
`bootstrap_k3s` готов с Step 4; `bootstrap_clusterctl` +
`bootstrap_capn_secret` готовы с Step 6. Отдельная роль для публикации
API (§15.5) removed в Step 7 (2026-04-23) — заменена LXD proxy device
поверх `lxd_bootstrap_instance`. В Step 8 реализована `export_artifacts`
(§13.12 / §15.6) + `tls-server-name` pin в `bootstrap_clusterctl`
(§13.10 Step 8 deviation) — runner теперь реально дотягивается до
API через LXD proxy на VM host'е с криптографически чистым TLS
identity (без IP в cert'е, без `insecure-skip-tls-verify`).

Роли:

* `bootstrap_k3s` ✓ (Step 4 — §13.9)
* `bootstrap_clusterctl` ✓ (Step 6 + Step 8 — §13.10)
* `bootstrap_capn_secret` ✓ (Step 6 — §13.11)
* ~~`bootstrap_api_publish`~~ — removed, §15.5
* `export_artifacts` ✓ (Step 8 — §13.12)

Acceptance (целая phase) — **закрыта** 2026-04-23:

* `clusterctl init` done                          ✓ (Step 6)
* providers healthy                               ✓ (Step 6)
* LXD identity secret present                     ✓ (Step 6)
* bootstrap API reachable из runner'а             ✓ (Step 8 — LXD
  proxy device + shipped kubeconfig с runner-reachable URL +
  `tls-server-name` pin)
* handoff bundle shipped на runner (`.artifacts/bootstrap.kubeconfig`
  + `.artifacts/bootstrap.auto.tfvars.json`) ✓ (Step 8 — §13.12)

Acceptance Step 4 + Step 6 + Step 8 частей (доказано verify
scenario'ями, end-to-end smoke через `kubernetes.core.k8s_info` с
`delegate_to: localhost`) — см. §14.6.

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
