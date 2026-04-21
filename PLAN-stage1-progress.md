# PLAN-stage1 — Progress

Документ фиксирует, что уже сделано по `PLAN-stage1.md`, какие версии
зафиксированы, и все осознанные отклонения от плана.

## Сессия 1 (2026-04-21)

### Scope

* **Phase 0** — полный repo skeleton и local test harness.
* **Phase 1, часть 1/3** — роль `base_system` + Molecule scenario для
  неё как reference implementation стиля §2.6.
* Политика «актуальные stable-версии» добавлена в план как новая §2.11.

Остальные роли Phase 1 (`binary_fetch`, `lxd_snap`), а также Phase 2–8,
остаются в очереди на следующие сессии.

### Что сделано

#### Phase 0 — skeleton

* Создано дерево каталогов по плану §7 (ansible/roles/*, terraform/modules/*,
  tests/molecule/*, tests/fixtures/*, manifests/*, charts/, scripts/,
  clusterctl/, .artifacts/).
* `README.md`, `.gitignore`, `.yamllint`, `.ansible-lint`, `.artifacts/.gitkeep`.
* `ansible/ansible.cfg` и `ansible/requirements.yml`.
* Top-level `Makefile` с targets `lint` / `test-local-harness` /
  `test-local-e2e` / `clean-local` / `deps`.
* `tests/molecule/Makefile` с pattern-rule схемой
  `<scenario>-<driver>-<action>` (плана §11.4).
* `tests/molecule/shared/` — общие `converge.yml` / `verify.yml` /
  prepare-задачи (включая `prepare-btrfs-pool.yml`), shared vars
  (`vars/common.yml`).
* `tests/vagrant/debian13/` — Vagrantfile (3 NIC: mgmt + ext6 +
  management default, dedicated LXD pool disk 40 GiB с serial
  `k8slab-lxdpool`), libvirt networks `mgmt-nat` / `ext6-mock` /
  `probe-ext6` (dual-stack XML — см. deviation ниже), `Makefile` с
  lifecycle (up / destroy / wipe / networks / ssh), `inventory.py`
  (Python).
* `scripts/` — все местные хуки на Python:
  * `molecule_run.py` — wrapper: поднимает VM через `make up`, запрашивает
    `vagrant ssh-config`, экспортирует `K8SLAB_HOST_*` env и execvpe'ит
    molecule. Auto-invalidates Molecule state при смене VM UUID.
  * `_harness.py` — общий helper (парсинг ssh-config, пути).
  * `render_kubeconfig.py`, `export_bootstrap_facts.py` — стабы с `exit 2`
    до Phase 4/5.
  * `wait_for_cluster.sh` — тонкий kubectl wrapper.

#### Phase 1 — роль `base_system`

Полная имплементация по стилю §2.6:

* `defaults/main.yml` с prefixed публичным контрактом (`base_system_*`),
  секциями `General / Packages / Kernel / Flow control / LXD Btrfs pool contract`
  и комментариями про trade-offs.
* `meta/main.yml` с galaxy info.
* `tasks/main.yml` — dispatcher-only с правильными `include_tasks`,
  `apply.tags`, coarse-grained `base_system_flow_control_*`.
* `tasks/preflight.yml` — `ansible.builtin.assert` по OS family, public
  inputs, package lists, kernel inputs и btrfs pool contract.
* `tasks/install.yml` — `ansible.builtin.apt` (required + btrfs-progs),
  никаких custom repos.
* `tasks/modules.yml` — `community.general.modprobe` с
  `persistent: present` (load + persist одним вызовом, native-first).
* `tasks/sysctl.yml` — `ansible.posix.sysctl` в `/etc/sysctl.d/60-k8slab-base-system.conf`.
* `tasks/config.yml` — `/opt/capi-lab/{bin,etc}` с детерминированным ownership.
* `tasks/healthchecks.yml` — internal assertions (packages installed, opt root ok).
* `handlers/main.yml` — pure placeholder (у роли нет асинхронных reload-ов).
* `README.md` с purpose, requirements, variables table, tags, example,
  testing, caveats.

#### Molecule scenario `base_system`

* `molecule.yml` — Molecule 26.x `driver: default` + `managed: false`,
  shared converge, scenario-local `prepare.yml` и `verify.yml`. `host_vars`
  читают connection-поля из env vars (`K8SLAB_HOST_*`), которые
  выставляет `scripts/molecule_run.py`.
* `prepare.yml` — сначала shared prepare (apt deps, `/opt/capi-lab`),
  затем `prepare-btrfs-pool.yml` (форматирование + монтирование
  dedicated disk `/dev/disk/by-id/virtio-k8slab-lxdpool`).
* `verify.yml` — проверяет реальное runtime-поведение: apt package
  index, `/proc/modules` для loaded kernel modules, live `/proc/sys/*`
  для sysctl, layout `/opt/capi-lab/`, и что LXD pool mount
  действительно btrfs.

#### Тестирование end-to-end через make (policy §2.11a)

По требованию пользователя в план добавлена §2.11a «тестируй до
коммита». До финализации этапа прогнал **два независимых цикла**
destroy → recreate → full scenario test под финальной версией кода:

| Цикл | prepare | converge | idempotence | verify | auto-invalidation |
| --- | --- | --- | --- | --- | --- |
| 1 | ok=14 changed=5 | ok=29 changed=5 | ok=29 changed=0 | ok=16 changed=0 | `d2b858c7… → 73f03905…`, wiped 1 dir |
| 2 | ok=14 changed=5 | ok=29 changed=5 | ok=29 changed=0 | ok=16 changed=0 | `73f03905… → 251e26ee…`, wiped 1 dir |

Оба цикла идентичны; idempotence = 0 changed подтверждает, что роль
по-настоящему идемпотентна на повторном converge. Лог прогона лежит в
`/tmp/k8slab-2cycles-v3.log` (локально у runner-а, в репо не хранится).

Команды, которыми прогонял (всё через `make`, без прямых `vagrant` /
`virsh` / `molecule` вызовов):

```bash
# для каждого цикла:
make -C tests/vagrant/debian13 destroy
make test-local-harness
make -C tests/molecule base-system-delegated-test
```

### Версии зафиксированы (verified 2026-04-21)

Источник для каждой — `GET /repos/<owner>/<repo>/releases/latest` через
GitHub API, либо `snap info` / vendor docs.

| Компонент | Версия | Где используется |
| --- | --- | --- |
| Kubernetes | `v1.35.3` | `kubernetes_version` в shared vars и в плане §10 |
| k3s | `v1.35.3+k3s1` | `k3s_version` (bootstrap cluster) |
| kubectl | `v1.35.3` | `kubectl_version` (bootstrap и runner) |
| Cluster API (clusterctl) | `v1.12.5` | `clusterctl_version` |
| CAPN (cluster-api-provider-incus) | `v0.8.5` | `capn_provider_version` |
| LXD snap channel | `6/stable` | `lxd_snap_channel`; **deviation** от плана 5.21/stable — см. ниже |
| Flannel chart | `v0.28.4` | `addons.flannel_chart_version` |
| Calico (tigera-operator) chart | `v3.31.5` | `addons.calico_chart_version` (было v3.31.4) |
| MetalLB chart | `0.15.3` | `addons.metallb_chart_version` |
| Terraform helm provider | `3.1.1` | `addons.helm_provider_version` |
| ansible.posix collection | `>=2.1.0` | `ansible/requirements.yml` (было `<2.0.0` — stale-pin) |
| community.general collection | `>=12.6.0` | `ansible/requirements.yml` (было `<12.0.0` — stale-pin) |
| community.crypto collection | `>=3.2.0` | `ansible/requirements.yml` (было `<3.0.0` — stale-pin) |

### Принятые решения и отклонения от плана

1. **Политика «latest stable» (нова §2.11)**
   Пользователь явно потребовал не использовать старые safe-defaults.
   Добавлена новая секция в `PLAN-stage1.md` (§2.11): при pin-е любой
   зависимости агент обязан сверять актуальный upstream release перед
   фиксацией и записывать дату проверки в этот документ.
   Любой pin вида `>=X,<X+1` считается stale по определению.

1a. **Политика «тестируй до коммита» (новая §2.11a)**
   Добавлена новая секция в `PLAN-stage1.md` (§2.11a): любой commit
   допустим только после реально пройденного end-to-end прогона через
   Makefile-target-ы против shared Vagrant VM. `make lint` зелёный —
   необходимое, но не достаточное условие. Если prerequisite недоступен
   (libvirt down / KVM выключен), агент обязан остановиться, а не
   переключаться на более слабый driver.

2. **LXD snap channel: `6/stable` вместо плановых `5.21/stable`**
   Canonical официально рекомендует LTS (5.21) для production.
   Мы трактуем пользовательский «latest stable» буквально и ставим
   feature-stable track `6/stable`. Trade-off: риск регрессий выше,
   CAPN ещё не декларировал совместимость с LXD 6.x явно. Если на Gate
   B или раньше всплывёт несовместимость — даунгрейдимся на
   `5.21/stable` и фиксируем это здесь же.

3. **`base_system` владеет btrfs pool contract (отклонение от §8.1)**
   План §8.1 скопировал `base_system` узко как «только пакеты». По
   запросу пользователя, для реалистичности target architecture, в
   роль добавлен **контрактный** блок (без мутирующих действий):
   * новые public vars `base_system_btrfs_pool_required`,
     `base_system_btrfs_pool_mountpoint`, `base_system_btrfs_pool_label`,
     `base_system_btrfs_pool_fstype` (по умолчанию `required: false`);
   * preflight assertion, что при `required: true` путь уже смонтирован
     и действительно btrfs.
   Само форматирование и монтирование остаётся вне base_system:
   * в тестах — Molecule shared prepare (`prepare-btrfs-pool.yml`);
   * в проде — installer image / operator до запуска Ansible.
   Это не ломает plan §2.7 ownership model (Ansible owns host bootstrap):
   формально disk-provisioning остаётся prerequisite, а role только
   enforces contract.

4. **Stub-скрипты `render_kubeconfig.py` / `export_bootstrap_facts.py`**
   Эти скрипты в плане §7 перечислены, но их полная реализация завязана
   на Phase 4/5. Сейчас они существуют как стабы, которые завершаются
   с `exit 2` и понятным сообщением про TODO. Это снижает шанс, что
   CI случайно «позеленеет» на пустой реализации.

5. **Molecule harness: Python wrapper + env-var connection contract**
   Molecule 26.x `driver: default` с `managed: false` не умеет сам
   поднимать Vagrant VM и запрашивать ssh-config. Вместо навороченных
   YAML create/destroy хуков с шеллом внутри, делаем всё иначе:
   * `scripts/molecule_run.py` — единственная точка входа, которую
     вызывает `tests/molecule/Makefile` pattern-rule. Он делает
     `make -C tests/vagrant/debian13 up`, запрашивает
     `vagrant ssh-config`, экспортирует `K8SLAB_HOST_ADDR/USER/PORT/KEY`
     и `MOLECULE_GLOB`, и `os.execvpe`'ит molecule — без промежуточных
     YAML-обёрток и shell-скриптов.
   * `molecule.yml host_vars.<host>.ansible_*` читает эти env через
     чистый `lookup('env', 'K8SLAB_HOST_ADDR')` — без
     `lookup('file', …) | from_yaml` гимнастики.
   * `_harness.py` — общий helper для парсинга ssh-config; используется
     и `molecule_run.py`, и `tests/vagrant/debian13/inventory.py`.
   Итог: ни одного bash-скрипта в lifecycle harness-а, никаких YAML
   Jinja-прослоек вокруг временных файлов, весь флоу помещается в
   голове.

6. **Auto-invalidation Molecule state по VM UUID**
   Scenario state Molecule (`~/.ansible/tmp/molecule.*/state.yml`)
   кеширует «prepare/converge уже прошли», а сам Molecule ничего не
   знает про жизнь Vagrant VM. Пересоздал VM — state стал ложной
   правдой, prepare пропускается, converge падает на свежем диске.
   **Автоматическое решение, не требующее внимания оператора:**
   * Vagrant libvirt пишет live domain UUID в
     `.vagrant/machines/host/libvirt/id` и удаляет файл на destroy.
   * `scripts/molecule_run.py` кеширует последнее виденное значение в
     `.artifacts/harness-vm-id` (gitignored) и сверяет на каждом
     запуске. При расхождении — wipe всех
     `~/.ansible/tmp/molecule.*` dirs.
   * В логе пишет `[molecule_run] VM identity changed (OLD → NEW);
     invalidating N Molecule scenario state dir(s)` — оператор видит,
     что это произошло автоматически.
   * `make -C tests/vagrant/debian13 destroy` оставлен **минимальным**
     (только `vagrant destroy`) — чтобы не было двух дублирующих
     механизмов чистки state. Единственный источник правды —
     `molecule_run.py`.

7. **Второй NIC test VM (`ext6-mock`) — dual-stack isolated libvirt net**
   Plan §11.2 описывал IPv6-only external segment. На практике
   vagrant-libvirt's `private_network` плагин падает на pure-IPv6 сети
   с `undefined method 'to_range' for nil`, потому что пытается
   посчитать DHCPv4 range. Для обхода в XML `ext6-mock` добавлен
   минимальный RFC 5737 TEST-NET-1 `/30` (`192.0.2.0/30`); он не несёт
   реального трафика, но позволяет плагину корректно завершить
   `private_network` validation. Внешний ingress и MetalLB VIP всё
   равно остаются IPv6-only — это политика аллокации, а не
   ограничение L2 сегмента. Оставляю isolated (без `<forward/>`),
   чтобы RA/NDP/multiple MAC сигналы не смешивались с IPv4 трафиком
   mgmt-сети. Деталь задокументирована в комментариях XML.

8. **Vagrant LXD pool disk: dedicated qcow2 через `serial`**
   Вместо безликого `/dev/vdb` Vagrantfile аттачит диск с serial
   `k8slab-lxdpool`, что даёт стабильный path
   `/dev/disk/by-id/virtio-k8slab-lxdpool` независимо от probe order.
   Все task-файлы Molecule и defaults роли пользуются этим стабильным
   путём.

9. **Libvirt bridge names ≤15 chars (IFNAMSIZ)**
   Первоначальные имена bridge `virbr-k8slab-mgmt` (17 chars) и
   `virbr-k8slab-ext6` (17 chars) превышали Linux `IFNAMSIZ=15` и
   падали с `error creating bridge interface: Numerical result out of
   range`. Переименованы в `k8slab-mgmt`, `k8slab-ext6`, `k8slab-probe`
   (все ≤12 chars), комментарий в XML объясняет ограничение.

10. **Vagrantfile IPv6-only NIC — `type: dhcp`**
    Плагин vagrant-libvirt пытается auto-конфигурировать гостевой NIC и
    вываливается на сети без IPv4 config. В Vagrantfile для внешнего
    NIC указан `type: "dhcp"` — это документированный флаг, который
    говорит плагину «IP придёт через DHCP, не пытайся сам считать».

11. **Makefile recipe: `SHELL := /bin/bash` (не `/usr/bin/env bash`)**
    GNU make трактует `SHELL := /usr/bin/env bash` как путь целиком
    («No such file or directory»), а не как команду с аргументом. На
    всех трёх Makefile-ах (`Makefile`, `tests/molecule/Makefile`,
    `tests/vagrant/debian13/Makefile`) исправлено.

12. **Pipefail + `grep -q` = SIGPIPE в `networks` target**
    Make recipe `virsh net-info | grep -q 'Active:.*yes'` под
    `SHELLFLAGS -eu -o pipefail -c` давал rc=141 (SIGPIPE): grep
    закрывает pipe после первой удачи, virsh получает SIGPIPE,
    pipefail эскалирует. Переписано на «один раз считать
    `virsh net-list --name`, membership-тест через bash pattern
    match» — без pipe вообще.

13. **Molecule 26.x `MOLECULE_GLOB` для custom scenario layout**
    Наша директория `tests/molecule/<scenario>/` не совпадает с
    дефолтным `molecule/<scenario>/` glob'ом. `molecule_run.py`
    устанавливает `MOLECULE_GLOB` в абсолютный путь перед execvpe.

14. **`community.general.yaml` callback удалён в 12.0**
    Molecule по дефолту генерит `stdout_callback: community.general.yaml`,
    но в community.general 12.0 этот callback удалён в пользу
    `ansible.builtin.default` + `result_format: yaml`. В `molecule.yml`
    переопределено.

15. **Scenario directories — kebab-case (новая конвенция в §2.6.3)**
    Пользователь справедливо заметил, что смешение `_` и `-` в Make
    target names (`base_system-delegated-test`) создаёт лишнюю боль на
    командной строке. В §2.6.3 плана добавлено правило: все non-Ansible
    имена (Make targets, Molecule scenario directories, shell helpers)
    используют kebab-case. Scenario directory `tests/molecule/<name>/`
    переименованы в kebab (`base-system/`, `binary-fetch/`, …); ссылка
    на применяемую роль по-прежнему идёт через `_shared_target_role`
    внутри scenario's `molecule.yml` и использует snake_case имя role
    directory (`base_system`). Pattern rule в `tests/molecule/Makefile`
    упростился до `$(call _molecule,$*,action)` без разбивки stem'а.

16. **Ansible collections — project-local под `ansible/collections/`**
    По требованию пользователя коллекции ставятся локально в проект
    (gitignored), не в `~/.ansible/collections/`. Makefile target `deps`
    делает `ansible-galaxy collection install --force -p ansible/collections`
    (флаг `--force` — чтобы коллекции, уже присутствующие в
    bundled site-packages venv, ложились и в проектный путь тоже).
    `ansible.cfg` + `ANSIBLE_COLLECTIONS_PATH` env var направляют все
    invocations к локальному пути.

### Что НЕ сделано в этой сессии

Всё остальное по плану. Ближайшее:

* `binary_fetch` — fetch kubectl/clusterctl/k3s/etc в `/opt/capi-lab/bin`
  с checksum verification (Phase 1, роль 2/3).
* `lxd_snap` — установка LXD через snap с pinning канала `6/stable` и
  refresh policy (Phase 1, роль 3/3).
* Molecule сценарии `binary_fetch` и `lxd_snap`.
* Phase 2 — весь LXD substrate (project / pools / networks / profiles).
* Всё остальное из `PLAN-stage1.md` §12.

### Как проверить текущее состояние локально

Prerequisite: активировать проектный venv (он не хардкодится в коде):

```bash
source /media/data/app/python/venv3/bin/activate
```

Далее:

```bash
# 1. Установить Ansible collections в project-local ansible/collections/
make deps

# 2. Поднять libvirt networks + тестовую VM (mgmt + ext6 + dedicated LXD pool disk)
make test-local-harness

# 3. Прогнать scenario (dependency → prepare → converge → idempotence → verify)
make -C tests/molecule base-system-delegated-test

# 4. Чистка
make clean-local
```

Полный E2E (`make test-local-e2e`) пока не будет зелёным — он запускает
фазы Phase 2+, которые ещё не реализованы.

Авто-инвалидация Molecule state при пересоздании VM проверена: два
независимых цикла destroy→recreate→test показывают
`[molecule_run] VM identity changed (OLD → NEW); invalidating …` и оба
прогоняются зелёно без ручного вмешательства.

### Следующая сессия — план

1. `binary_fetch` (role + molecule scenario) с проверенной версией
   kubectl `v1.35.3`, clusterctl `v1.12.5`, k3s `v1.35.3+k3s1`.
2. `lxd_snap` (role + molecule scenario) с каналом `6/stable` и refresh
   policy.
3. Первый e2e-линк между ролями: собрать их через shared converge.
4. Коммит в main в конце каждой роли, а не одним большим дампом.
