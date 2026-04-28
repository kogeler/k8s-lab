Этот файл владеет §19: Phase 8 — destroy contract. Нумерация §N сквозная
по всем plan-файлам; перекрёстные ссылки вида `§<номер>` валидны без
указания имени файла — см. `PLAN-stage1-common.md` header для полного
file lineup. Атомарный scope этого шарда — реверс всех create-paths
Stage 1 в чистое состояние, чтобы coding-agent мог работать над
cleanup-ролью и phase-контрактом независимо от forward-paths.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (Phases 5 + 5.05 CAPI topology via Helm)
PLAN-stage1-4.md ................. §17      (Phases 5.1 + 5.2 + 5.3 Helm add-ons + in-cluster tests)
PLAN-stage1-5.md ................. §18      (Phases 6 + 7 pivot + workload clusters)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)                             <-- этот файл
PLAN-stage1-7.md ................. §20..§22 (Stage 1 meta: out-of-scope, self-review, recommendation)
```

---

# 19. Phase 8 — Destroy contract

Этот раздел описывает destroy role (§19.1) и phase (§19.2), которые
должны уметь откатить Stage-1 create-paths в чистое локальное
состояние.

## 19.1. Role: `cleanup_bootstrap`

**Статус: выполнено в Step 9 (2026-04-24).**

Удаляет:

* bootstrap LXC — `capi-bootstrap-0` в проекте `capi-lab` через
  `community.general.lxd_container state=absent` с
  `force_stop: true`. Instance-level proxy-device `k3s-api`,
  которым `lxd_bootstrap_instance_devices` публикует bootstrap API на
  `<vagrant>:16443`, уходит вместе с инстансом — отдельного шага
  для publication нет.
* runner-side artifacts root — опционально, путь берётся из
  `cleanup_bootstrap_artifacts_root` (default empty = skip). Удаление
  через `ansible.builtin.file state=absent` с `delegate_to: localhost`
  и `become: false`, потому что `export_artifacts` писал в тот же
  путь на раннере, не в VM. Preflight блокирует `/` и `//` чтобы
  конфиг-ошибка не снесла runner FS.

### Implementation notes (Step 9)

* **Нет meta-deps по дизайну** (`meta/main.yml dependencies: []`).
  Cleanup — reverse-motion: если substrate уже частично снесён, роль
  должна оставаться no-op, а не re-install'ить LXD/project/pool
  только чтобы удалить один инстанс. Phase 8 orchestrator (§19.2)
  сам секвенсит cleanup-роли в нужном порядке.
* **Probe-then-delete для полной идемпотентности.**
  Первый шаг — `ansible.builtin.uri GET /1.0/instances/<name>?project=<project>`
  с `status_code: [200, 404]` + `failed_when: false` + `changed_when: false`.
  Guard покрывает все три состояния substrate'а (daemon absent /
  project absent / instance absent) одной проверкой; второй запуск
  подряд даёт `changed=0` (plan §2.6.1 требование).
* **Healthcheck guard `when: status in [200, 404]`** — если substrate
  полностью снесён, даже healthcheck assert skipped (нечего
  валидировать). Если substrate reachable, ассерт 404 после delete.
* **Scenario-local artifacts path** в Molecule
  (`tests/molecule/cleanup-bootstrap/host_vars/k8slab-host.yml`):
  `{{ repo }}/.artifacts-cleanup-bootstrap-test` — чтобы
  cleanup-тест не затирал реальный `.artifacts/` от
  `export_artifacts` сценария/full e2e path.
* **Prepare стратегия.** Поскольку meta-deps нет, pre-converge
  инстанс создаётся в `prepare.yml` через
  `ansible.builtin.include_role name: lxd_bootstrap_instance` — он
  тянет весь substrate chain транзитивно. В prepare runner-side
  секция `delegate_to: localhost` создаёт sentinel-файл в
  scenario-local artifacts root, чтобы verify мог доказать
  реальное удаление (exists=false после cleanup), а не ситуацию
  "пути никогда не было".

### Verify

Molecule сценарий `tests/molecule/cleanup-bootstrap/` прогон
end-to-end (`make -C tests/molecule cleanup-bootstrap-delegated-test`,
2026-04-24):

* converge: `ok=17 changed=2 failed=0` (instance delete + artifacts
  delete);
* **idempotence: `ok=16 changed=0 failed=0`** — probe возвращает
  404 → delete skipped, artifacts уже absent, healthcheck 404 →
  assert pass;
* verify (6 asserts): `ok=6 changed=0 failed=0` — instance 404,
  instance отсутствует в project-level `/1.0/instances?project=...`
  list (belt-and-braces защита от ложного 404 при отсутствующем
  проекте), scenario-local artifacts root `exists=false` на раннере.

## 19.2. Phase 8 — Destroy

**Статус: выполнено в Step 18 (2026-04-28) — Makefile destroy/clean
graph причёсан в две явные оси (`destroy-*` для running infra,
`clean-*` для file-only deletes), каждый destroy auto-cascade'ит
clean-* которые он invalidate'ит, два compound supertarget'а покрывают
типовые operator workflows. Operator не отслеживает manual cleanup
после ни одного из destroy-шагов — следующий forward target работает
без касаний.**

Reverse-ordered chain в исходной форме:

1. **`make destroy-workload`** — `terraform destroy` на §16.5
   fixture (`tests/fixtures/terraform/workload-clusters/lab-default/`).
   TF разворачивает helm_release цепочку §16.4 module'а в обратном
   порядке: metallb-config → metallb → cni-calico → workload Cluster
   CR (CAPI/CAPN delete LXC instances + workload kubeconfig Secret)
   → per-workload ClusterClass. **Cascade: `clean-tfstate` +
   `clean-workload-kubeconfig`** — TF state в фикстуре + любая
   материализованная workload kubeconfig копия в
   `.artifacts/clusters/` смысла не имеют после destroy.
2. **Per-workload artefacts cleanup** — module §16.4 не пишет
   файлы (§16.4 architectural fence). Молекулярные debug-копии в
   `.artifacts/clusters/<name>.kubeconfig` (написанные
   `make workload-kubeconfig` consumer-side wrapper'ом) — wiped
   шагом 1 cascade'ом.
3. **`pivot_clusterctl_move` reverse** (если был pivot, §18.1) —
   опционально, scope Stage 2;
4. **`cleanup_bootstrap` Ansible role** (§19.1) — снимает bootstrap
   publication (LXD proxy device), удаляет bootstrap LXC instance,
   очищает `capi-lab` project assets. **Локально на Vagrant flow
   шаг (4) и (5) совпадают** — VM teardown subsumes bootstrap
   cleanup; роль остаётся отдельным testable Molecule scenario
   (`tests/molecule/cleanup-bootstrap/`) для production paths где
   substrate persistent.
5. **Vagrant/libvirt cleanup** — `make destroy-vm` возвращает
   harness в чистое состояние. **Cascade: `clean-bootstrap-bundle`
   + `clean-workload-kubeconfig` + `clean-tfstate`** — после
   wipe'а VM ВСЕ runner-side артефакты (handoff bundle + workload
   kubeconfig + workload TF state) указывают на призраков.

### Naming convention (Step 18)

* **`destroy-*`** — operate on running infra (TF state, helm
  releases, VM, libvirt domains). Каждый каскадирует `clean-*`
  что сделал stale. После любого `destroy-*` следующий forward
  target (`deploy-workload`, `vagrant up`, …) работает без manual
  intermediate cleanup.
* **`clean-*`** — file/directory deletes only. Idempotent против
  отсутствующего state (безопасно запускать на repo без infra).
* **compound** — operator-facing supertarget'ы:
  * **`make clean-local`** (≈30s) — «start over» fast reset:
    `destroy-vm + clean-molecule`. VM destruction subsumes
    bootstrap cleanup transitively; не упражняет
    `terraform destroy` на live workload'е.
  * **`make reset-all`** (≈3-5min) — полная PLAN §19.2
    reverse chain: `destroy-workload → destroy-vm + clean-molecule`.
    Упражняет каждый destroy-step на живой infra (helm uninstall
    + Cluster CR cascade delete + LXC teardown via CAPN, потом
    VM wipe). Используется когда operator хочет валидировать
    destroy contract end-to-end перед next test cycle.

### Cascade graph

```
destroy-workload  ─→  clean-tfstate
                  └→  clean-workload-kubeconfig

destroy-vm        ─→  clean-bootstrap-bundle
                  └→  clean-workload-kubeconfig
                  └→  clean-tfstate

clean-local       ─→  destroy-vm  (← which cascades the cleans above)
                  └→  clean-molecule

reset-all         ─→  destroy-workload  (← cascades clean-tfstate + clean-workload-kubeconfig)
                  └→  destroy-vm        (← cascades clean-bootstrap-bundle + clean-workload-kubeconfig + clean-tfstate)
                  └→  clean-molecule
```

### Контракт

* shared external bridge не трогаем, если его не создавал harness
  (production-mirror — bridge обычно живёт за пределами repo);
* operator вызывает шаги ТОЛЬКО через root-level Makefile target'ы
  (memory `feedback_makefile_only`); direct `terraform destroy`
  или `vagrant destroy` не invoке'ятся;
* `tests/vagrant/debian13/Makefile destroy` после Step 18 операует
  ТОЛЬКО на VM + libvirt orphans — `.artifacts/*` cleanup owned
  root Makefile'ом через cascade. Stand-alone
  `make -C tests/vagrant/debian13 destroy` оставляет `.artifacts/`
  нетронутым (operator's call использовать `destroy-vm` если
  cascade нужен).

### Acceptance

Все три критерия зелёные (Step 18 verification, 2026-04-28):

* `make destroy-workload` на 5/5 Ready cluster'е → TF destroy
  снёс 7 ресурсов, cascade очистил `.terraform/`, `terraform.tfstate*`,
  `.artifacts/clusters/lab-default.kubeconfig`. Сразу следом
  `make deploy-workload` поднял свежий cluster zero-touch
  (без manual cleanup между destroy и deploy);
* `terraform destroy` идемпотентен — повторный destroy на
  empty state'е (после первого destroy + до cascade-wipe'а) no-op'ит
  с `Resources: 0 destroyed`;
* `cleanup_bootstrap` Molecule scenario зелёный (§19.1 shipped в
  Step 9; подтверждение что role-level reverse path работает на
  isolated test substrate).

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
