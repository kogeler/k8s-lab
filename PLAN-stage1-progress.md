# PLAN-stage1 — Progress

Документ фиксирует, что уже сделано по `PLAN-stage1.md`, какие версии
зафиксированы, и все осознанные отклонения от плана.

## Stage 1 — Step 1 (2026-04-21)

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

## Stage 1 — Step 2 (2026-04-21)

### Scope

* **Консолидация Phase 1 / Phase 2 границы**: `lxd_snap` и
  `lxd_network_ext_bridge` мерджены в одну роль `lxd_host`; `binary_fetch`
  отодвинут ближе к Phase 4, т.к. kubectl/clusterctl/k3s не потребляются
  до bootstrap cluster.
* **Phase 1, часть 2/2** — роль `lxd_host` + Molecule scenario
  `lxd-host`.
* Новые контракты в плане: §2.6.5 «Role dependencies contract» и §8.3
  переписан под объединённую `lxd_host`.
* Vagrantfile оптимизации: 5 пошагово проверенных, 1 отклонённая как
  ломающая boot.
* Makefile `tests/vagrant/debian13`: устойчивый destroy (чистит orphan
  libvirt домены/тома/vagrant state при SIGKILL).

Не сделано в этой сессии: `binary_fetch`, Phase 2 (`lxd_project`,
`lxd_storage_pools`, `lxd_network_int_managed`, `lxd_profiles`), всё
что после.

### Что сделано

#### Переструктурирование Phase 1 / Phase 2

* `lxd_snap` (host-side: snap install + channel + refresh policy) и
  `lxd_network_ext_bridge` (host-side: Linux bridge `br-ext6` + uplink)
  **объединены в одну роль `lxd_host`**. Границу оставили: всё
  host-level — в `lxd_host`; entities *внутри* LXD (projects, pools,
  managed networks, profiles, instances) — отдельные роли.
* `binary_fetch` **исключён из Phase 1** в шорт-листе ближайших ролей.
  Он кладёт kubectl/clusterctl/k3s, которые впервые нужны только на
  Phase 4. Вертикальный срез `lxd_host → Phase 2 LXD substrate` раньше
  вскрывает substrate-риски и разблокирует следующие фазы.
* В плане обновлено §7 (file tree), §8 (§8.3 переписан, §8.6-§8.18
  перенумерованы после удаления `lxd_network_ext_bridge`), §10
  (`host.lxd_snap_*` → `host.lxd_host_snap_*`), §11.4 (список scenarios),
  §12 Phase 1/2 (состав ролей).
* Удалены пустые скелеты `ansible/roles/lxd_snap/`,
  `ansible/roles/lxd_network_ext_bridge/`, `tests/molecule/lxd-snap/`,
  `tests/molecule/lxd-network-ext-bridge/`. `tests/molecule/Makefile`
  `SCENARIOS` обновлён.

#### Роль `lxd_host` (Phase 1 role 2/2)

Полная имплементация по §2.6:

* `defaults/main.yml` с секциями General / Snap install / Refresh
  policy / Daemon readiness / External bridge / Flow control. Все
  публичные переменные префиксом `lxd_host_*`, внутренние
  `_lxd_host_*`.
* `meta/main.yml` с `dependencies: [{role: base_system}]` +
  one-line `# why` комментарий (см. §2.6.5).
* `tasks/main.yml` — dispatcher-only, include_tasks с `apply.tags`,
  coarse `lxd_host_flow_control_{snap,refresh,bridge}`.
* `tasks/preflight.yml` — assertion по OS, snap inputs, refresh mode,
  bridge (включая «uplink обязателен если bridge enabled» как contract
  guard от случайного моста mgmt NIC).
* `tasks/install.yml` — `community.general.snap` для пакета +
  `ansible.builtin.systemd` для snapd socket + **native** ожидание
  seed'а через polling `snapd.seeded.service` (не shell'ом `snap wait`).
* `tasks/refresh.yml` — documented shell fallback: `snap get/set system
  refresh.{hold,timer}` (Ansible-модуля нет), идемпотентность через
  предварительное чтение текущего значения.
* `tasks/waitready.yml` — documented shell fallback: `/snap/bin/lxd
  waitready` (absolute path — /snap/bin не в non-interactive SSH
  PATH).
* `tasks/bridge.yml` — `ansible.builtin.copy` для
  systemd-networkd .netdev + две .network drop-ins (priority 30/31);
  `ansible.builtin.systemd` для enable+start; handler через
  `ansible.builtin.systemd state: reloaded` (**native**, без
  `networkctl reload` shell).
* `tasks/healthchecks.yml` — реальная проверка state: `snap list lxd`
  (channel), `lxd waitready` (10s timeout), /sys/class/net/<bridge>,
  /sys/class/net/<bridge>/brif members.
* `handlers/main.yml` — один реактивный handler (systemd-networkd
  reload) при изменении .netdev/.network файлов.
* `README.md` с purpose, requirements, role variables (всеми), tags,
  example, testing notes, caveats (граница с systemd.networking.service,
  snap refresh через shell, channel deviation).

Отдельно зафиксировано в `meta/main.yml`: `lxd_host` не использует
переменных с префиксом `base_system_*` у себя в tasks/defaults —
соблюдается §2.6.5 rule "no cross-role prefix reads".

Shell-команды по итогу (минимизированы):
- 3 documented exceptions без native alternative: `snap set/get system
  refresh.*`, `/snap/bin/lxd waitready`, `snap list lxd`.
- 2 заменены на native: seed wait (systemd unit poll), networkd reload
  (systemd reloaded).

#### Molecule scenario `lxd-host`

* `molecule.yml` — тот же шаблон что у `base-system` (delegated + env
  var contract). `_shared_target_role: lxd_host`, единственный override
  host_vars — `lxd_host_ext_bridge_uplink: "eth2"`.
* `prepare.yml` — **только** test-harness bootstrap (shared apt/rsync).
  НЕ включает `base_system` явно — это теперь hidden contract, который
  пошёл в meta-dep ролёй `lxd_host` (§2.6.5).
* `verify.yml` — runtime assertion: snap channel, refresh.hold=forever,
  `lxd waitready`, bridge in /sys, uplink bridge member, systemd-networkd
  active+enabled. Expected-values параметризованы из тех же host_vars,
  что и converge (чтобы verify не дрейфовал от фактической
  конфигурации).

#### Новые контракты в плане

* **§2.6.5 Role dependencies contract**: любая зависимость роли
  объявляется в `meta/main.yml` dependent-роли, не эмулируется снаружи;
  `prepare.yml` Molecule — только для test-harness bootstrap; запрещены
  транзитивные meta-deps; каждая meta-dep запись обязана иметь
  one-line `# why`; запрещено читать `<other_role>_*` переменные (только
  global contract без префикса или published facts). Нумерация
  подразделов §2.6: старый §2.6.5 → §2.6.6.
* **§8.3 `lxd_host`** переписан как объединённая роль с явным
  критерием границы: host-level vs LXD entity.

#### Vagrantfile оптимизации — пошаговая верификация

По требованию user пересобрал `tests/vagrant/debian13/Vagrantfile` с
dev-loop tuning. Каждое изменение проверено отдельно (destroy → make up
→ "Machine booted and ready!").

| # | Оптимизация | Статус |
| --- | --- | --- |
| — | `K8SLAB_VCPUS` default `4` → `8` | ✅ |
| 1 | `memballoon_enabled: true`, `memballoon_model: "virtio"` | ✅ |
| 2 | `graphics_type: "none"` | ❌ **Подтверждённо ломает** boot на debian/trixie64 box: vagrant-libvirt drops video device, kernel зависает pre-userspace (TX=0 на всех NIC 4+ мин). Проверено дважды, в т.ч. после фикса orphan-volume issue, чтобы исключить false-positive |
| 3 | `random model: "random"` (virtio-rng от /dev/urandom) | ✅ |
| 4 | qemu-guest-agent channel (`virtio`, `org.qemu.guest_agent.0`) | ✅ |
| 5 | `disk_driver cache: "unsafe", io: "threads", discard: "unmap", detect_zeroes: "unmap"` (root + LXD pool disk) | ✅ |
| 6 | `libvirt__driver_queues: vcpus` на каждом NIC (virtio-net multiqueue) | ✅ |

Ещё одна отвергнутая: `libvirt.cpu_topology sockets: N, cores: M,
threads: 1` — плагин vagrant-libvirt текущей версии не принимает
kwargs на этом методе, падает с `ArgumentError: wrong number of
arguments (given 1, expected 0)` при парсинге Vagrantfile.

#### Makefile: устойчивый destroy

Добавил в `tests/vagrant/debian13/Makefile` safety-net: если `vagrant
destroy` ничего не сделал (а такое бывает, когда сам `vagrant up` был
убит SIGKILL'ом — его state tracker пропал, но libvirt домен остался),
цель `destroy` дополнительно:

* `virsh destroy + undefine` известных доменов (`k8slab_host`,
  `k8slab_probe`);
* `virsh vol-delete` известных томов (`k8slab_host.img`,
  `k8slab_host-vdb.qcow2`, и probe equivalents) из pool `default`;
* `rm -rf` `.vagrant/machines/*/libvirt` если cached UUID больше не
  соответствует живому domain.

Это был root cause «плавающих vagrant up hang'ов» между сменами
Vagrantfile — следующий `vagrant up` падал мгновенно с `Volume for
domain is already created. Please run 'vagrant destroy' first`.

#### .ansible-lint

Добавлены в `skip_list`:
* `name[casing]` — task names начинаются с lowercase role префикса
  (плановая §2.6.3 конвенция `<role> | <section> | <action>`), что
  конфликтует с дефолтом ansible-lint'а «All names should start with
  an uppercase letter».
* `yaml[colons]` — `.yamllint` этого репо авторитативно разрешает
  column-aligned values (`max-spaces-after: -1`) для читаемости
  defaults; ansible-lint re-применяет собственные дефолты yamllint.

#### base_system — точечные правки

* README.md, meta/main.yml и defaults/main.yml: ссылки `lxd_snap` →
  `lxd_host`, ссылка на §8.8 refs kernel modules → §8.7 после
  renumbering.
* Поведение роли не изменилось.

### Результаты тестирования (policy §2.11a)

`make -C tests/molecule lxd-host-delegated-test` **полностью зелёный**
после всех фиксов:

| Фаза | ok | changed | failed |
| --- | --- | --- | --- |
| Prepare (shared apt/rsync only) | 5 | 1 | 0 |
| Converge (base_system via meta-dep + lxd_host) | 59 | 13 | 0 |
| Idempotence | 57 | **0** | 0 |
| Verify | 14 | 0 | 0 |

Meta-dep отрабатывает корректно: `include_role: lxd_host` в shared
converge автоматически подтягивает `base_system` без glue в prepare.yml.

До финального зелёного прогона были два промежуточных фейла, оба
исправлены:

1. `lxd waitready` падал с `Errno 2 No such file or directory`: `/snap/bin`
   не в Ansible non-interactive SSH `$PATH`. Во всех местах (`tasks/
   waitready.yml`, `tasks/healthchecks.yml`, `tests/molecule/lxd-host/
   verify.yml`) хардкод на `/snap/bin/lxd`.
2. Verify assertion падал на «expected eth1 to be a member of bridge»,
   а в scenario uplink установлен `eth2`: в `verify.yml` hardcoded
   expected values заменены на ссылки на те же host_vars, что
   потребляет роль (`lxd_host_ext_bridge_{name,uplink}`).

### Принятые решения и отклонения от плана

1. **lxd_host merge** — консолидация по запросу user: host-side роль
   должна быть одна, чтобы не плодить thin роли без собственной
   бизнес-логики. Плановая граница между §8.3 и §8.6 была размыта
   (обе роли ничего не ставят внутрь LXD). Запись в memory:
   `project_vagrant_optimizations_candidate.md` (перечень tuning
   knobs) и `feedback_vertical_ordering.md` (доделывать vertical slice,
   а не listing order плана).

2. **`binary_fetch` отложен** — та же логика vertical slice: его
   output (kubectl/clusterctl/k3s binaries) впервые нужен только на
   Phase 4 (`bootstrap_k3s`). Запись в §12 Phase 1 с примечанием «ближе
   к Phase 4».

3. **§2.6.5 Role dependencies contract (новая)** — user поднял, что
   я не объявил `base_system` в `lxd_host/meta/main.yml` и вместо
   этого runq'ил base_system явно в scenario's `prepare.yml`. Это
   hidden contract. Правило зафиксировано в плане и в memory
   (`feedback_role_dependencies.md`):
   * зависимость всегда в `meta/main.yml` dependent-роли;
   * `prepare.yml` — только test-harness bootstrap;
   * запрет transitive meta-deps (каждая роль указывает только
     прямого deps, дальше — граф разбирается Ansible'ом);
   * запрет чтения `<other_role>_*` из defaults/conditions другой
     роли (cross-role коммуникация через §10 global contract vars без
     префикса или через published facts с `_<role>_<section>_<fact>`
     naming).

4. **`graphics_type: "none"` отвергнут как unsafe** — два независимых
   чистых прогона (с корректным destroy) подтвердили: guest зависает
   pre-userspace. В Vagrantfile стоит явный `# do NOT set` комментарий.
   Сохранил как negative result, чтобы следующая сессия не попыталась
   снова.

5. **Vagrantfile optimizations — pairing with NIC multiqueue** — для
   `libvirt__driver_queues: vcpus` использую переменную `vcpus` в
   outer scope Vagrantfile; сам `libvirt.cpus = vcpus` тоже её читает.
   Это единый источник правды для count'а.

6. **Shell-fallback reduction в `lxd_host`** — по запросу user
   доработал install.yml (seed wait на `ansible.builtin.systemd` вместо
   `snap wait`) и handlers/main.yml (`state: reloaded` вместо
   `networkctl reload`). 3 оставшиеся shell-вызова в роли задокументированы
   как «Ansible-модуля нет».

7. **Makefile destroy safety-net** — вместо правила «всегда destroy'ить
   через vagrant» добавил belt-and-braces для случая SIGKILL. Запись в
   комментарии Makefile с why.

### Что НЕ сделано в этом шаге

* `binary_fetch` — отложен к Phase 3.5 (ближе к Phase 4).
* Вся Phase 2: `lxd_project`, `lxd_storage_pools`,
  `lxd_network_int_managed`, `lxd_profiles`.
* Всё, что после Phase 2.

### Как проверить текущее состояние локально

Prerequisite: venv активен (`source /media/data/app/python/venv3/bin/activate`).

```bash
# 1. Установить Ansible collections
make deps

# 2. Поднять libvirt networks + VM
make test-local-harness

# 3. Прогнать base_system (пред. step) — должен быть зелёным
make -C tests/molecule base-system-delegated-test

# 4. Прогнать lxd_host (этот step) — должен быть зелёным, meta-dep
#    подтянет base_system на converge автоматически
make -C tests/molecule lxd-host-delegated-test

# 5. Чистка
make clean-local
```

`make test-local-e2e` по-прежнему не зелёный — он запускает Phase 2+,
ещё не реализованные.

### Следующая сессия — план

1. **Phase 2 роль `lxd_project`** — create/configure `capi-lab` LXD
   project with restrictions/features. Meta-dep: `lxd_host`. Scenario:
   `tests/molecule/lxd-project/`.
2. **Phase 2 роль `lxd_storage_pools`** — create `capi-fast` btrfs
   pool pointing at `/dev/disk/by-id/virtio-k8slab-lxdpool`. Meta-dep:
   `lxd_project` (транзитивно тянет `lxd_host` и `base_system`).
3. **Phase 2 роль `lxd_network_int_managed`** — `capi-int` managed
   bridge + DHCP/RA/NAT. Meta-dep: `lxd_project`.
4. **Phase 2 роль `lxd_profiles`** — `capi-base` / `capi-bootstrap` /
   `capi-controlplane` / `capi-worker` profiles со ссылкой на
   `capi-fast` pool + `capi-int` network + host-side `br-ext6`.
   Meta-deps: `lxd_storage_pools`, `lxd_network_int_managed`.
5. Коммит после каждой зелёной роли.
