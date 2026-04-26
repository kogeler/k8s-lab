Этот файл содержит общие разделы плана, применимые ко всем stage-
специфичным документам. Здесь — project-wide contract, architecture,
networking, gates, repo layout, typed variables, test harness, local
workflows, secrets policy и risk catalog.

Нумерация §1..§22 **сквозная по всем plan-файлам** и разделена так,
чтобы каждый файл оставался атомарным по scope и перекрёстные ссылки
внутри `§<номер>` были валидными без указания имени файла:

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (Phases 5 + 5.05 CAPI topology via Helm)
PLAN-stage1-4.md ................. §17      (Phases 5.1 + 5.2 + 5.3 Helm add-ons + in-cluster tests)
PLAN-stage1-5.md ................. §18      (Phases 6 + 7 pivot + workload clusters)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 meta: out-of-scope, self-review, recommendation)
```

Будущие stage-файлы подцепляются к этой же сквозной нумерации как
следующие §N+ блоки.

## Оглавление

### PLAN-stage1-common.md — §1..§12 (project-wide contract)

- §1. Цель и границы плана
- §2. Зафиксированный контракт
  - §2.1. Платформа
  - §2.2. Политика по пакетам и бинарникам
  - §2.3. Политика по изоляции
  - §2.4. Политика по bootstrap management cluster
  - §2.5. Политика по границе репозитория
  - §2.6. Политика разработки Ansible roles
    - §2.6.1. Native-first policy и идемпотентность fallback-шагов
    - §2.6.2. Variables contract и layout
    - §2.6.3. Naming, tags, registers и flow control
    - §2.6.4. Handlers contract
    - §2.6.5. Role dependencies contract
    - §2.6.6. Комментарии, README и проверяемость
  - §2.7. Ownership model между слоями
  - §2.8. Политика по режиму LXC-нód
  - §2.9. Политика по Terraform delivery для cluster add-ons
  - §2.10. Политика по образам нод
  - §2.11a. Политика «тестируй до коммита»
  - §2.11. Политика по версиям зависимостей
  - §2.11b. Политика «план — live-документ; отдельного progress-файла нет»
- §3. Архитектурная модель: два режима
  - §3.1. MVP / v1.0
  - §3.2. Stage 2 / advanced
- §4. Итоговая сетевая архитектура
- §5. Networking contract
- §6. Gate-фазы
- §7. Репозиторий
- §8. Типизированный контракт переменных
  - §8a. Verified version log
- §9. Локальная разработка и тестирование
- §10. One-command local workflows
- §11. Secrets, artifacts и state
- §12. Риски и mitigation

### PLAN-stage1-1.md — §13..§14 (completed work)

- §13. Выполненные Ansible-роли
  - §13.1. `base_system` (Step 1)
  - §13.2. `lxd_host` (Step 2)
  - §13.3. `lxd_project` (Step 3 + Step 4 substrate расширение)
  - §13.4. `lxd_storage_pools` (Step 3)
  - §13.5. `lxd_network_int_managed` (Step 3)
  - §13.6. `lxd_profiles` (Step 3 lean baseline + Step 4 full CAPN baseline)
  - §13.7. `lxd_bootstrap_instance` (Step 3)
  - §13.8. `binary_fetch` (Step 4)
  - §13.9. `bootstrap_k3s` (Step 4)
  - §13.10. `bootstrap_clusterctl` (Step 6)
  - §13.11. `bootstrap_capn_secret` (Step 6)
  - §13.12. `export_artifacts` (Step 8 — Molecule pending)
- §14. Выполненные phases
  - §14.1. Phase 0 — repo skeleton и local harness
  - §14.2. Phase 1 — host bootstrap
  - §14.3. Phase 2 — LXD substrate
  - §14.4. Phase 3 — bootstrap instance
  - §14.5. Phase 3.5 — `binary_fetch` (Step 4)
  - §14.6. Phase 4 — bootstrap management cluster (Step 4 partial)

### PLAN-stage1-2.md — §15 (Phases 3.5 + 4 bootstrap management cluster)

- §15. Phases 3.5 + 4 — Bootstrap management cluster
  - §15.1. Role: `binary_fetch`
  - §15.2. Role: `bootstrap_k3s`
  - §15.3. Role: `bootstrap_clusterctl`
  - §15.4. Role: `bootstrap_capn_secret`
  - §15.5. Публикация bootstrap API (LXD proxy device, не отдельная роль)
  - §15.6. Role: `export_artifacts`
  - §15.7. Phase 3.5 execution
  - §15.8. Phase 4 execution

### PLAN-stage1-3.md — §16 (Phases 5 + 5.05 CAPI topology via Helm)

- §16. Phases 5 + 5.05 — CAPI topology via Helm + kubeconfig export
  - §16.1. Ownership и delivery model
  - §16.2. Chart: `charts/capi-cluster-class/`
  - §16.3. Chart: `charts/capi-workload-cluster/`
  - §16.4. Module: `terraform/modules/capi_cluster_class/`
  - §16.5. Module: `terraform/modules/capi_workload_cluster/`
  - §16.6. Test fixture: `tests/fixtures/terraform/workload-clusters/lab-default/capi`
  - §16.7. Phase 5 — Apply CAPI topology
  - §16.8. Phase 5.05 — Export target kubeconfig на runner

### PLAN-stage1-4.md — §17 (Phases 5.1 + 5.2 + 5.3 Helm add-ons + in-cluster tests)

- §17. Phases 5.1 + 5.2 + 5.3 — Helm add-ons + in-cluster validation
  - §17.1. Module: `cluster_addons_helm` (Calico CNI, MetalLB; CNI swap через `cni_chart_path` input)
  - §17.2. Test fixture: `tests/fixtures/terraform/workload-clusters/lab-default/addons`
  - §17.3. Helm test hooks contract (CNI + external L2 validation)
  - §17.4. Phase 5.1 — Helm add-ons apply (`make deploy-workload-addons`)
  - §17.5. Phase 5.2 — CNI Helm test (Gate B)
  - §17.6. Phase 5.3 — MetalLB Helm test (Gate A)

### PLAN-stage1-5.md — §18 (Phases 6 + 7 pivot + workload clusters)

- §18. Phases 6 + 7 — Optional pivot + workload cluster creation
  - §18.1. Role: `pivot_clusterctl_move`
  - §18.2. Phase 6 execution
  - §18.3. Phase 7 execution

### PLAN-stage1-6.md — §19 (Phase 8 destroy)

- §19. Phase 8 — Destroy contract
  - §19.1. Role: `cleanup_bootstrap`
  - §19.2. Phase 8 execution

### PLAN-stage1-7.md — §20..§22 (Stage 1 meta)

- §20. Stage 1 — Explicitly out of scope for v1.0
- §21. Stage 1 — Саморевью контракта
- §22. Stage 1 — Финальная рекомендация

---

Ниже — **полный объединённый master-plan v1.0** для coding agents. Он уже:

* включает весь исходный замысел;
* учитывает сетевую двухинтерфейсную архитектуру;
* учитывает все принятые замечания из ревью;
* выстроен в **правильной последовательности реализации**;
* содержит **MVP path** и **Stage 2 path**;
* добавляет **локальную разработку и тестирование через Molecule + Vagrant + Libvirt**, включая **mock DHCPv6/RA с /64 для второго интерфейса**;
* отделяет **обязательные gate-проверки** от основной реализации;
* фиксирует, что именно делается **Ansible**, что именно делает **Terraform**, и что считается **out of scope**.

---

# 1. Цель и границы плана

Это план реализации **лабораторной инфраструктуры Kubernetes на одном bare metal host**, где:

* Kubernetes-ноды — это **LXC/LXD system containers**;
* управление нодами идёт через **Cluster API provider Incus (CAPN)**, который **официально поддерживает Incus, Canonical LXD и Canonical MicroCloud**; для нашего проекта выбор зафиксирован как **Canonical LXD через snap** с жёстким pinning versions/images. ([capn.linuxcontainers.org][1])
* host — **Debian 13 Trixie**;
* локальная тестовая VM — тоже **Debian 13 Trixie**;
* на host **нет Docker** и нет постоянного host-level Kubernetes;
* все нестандартные бинарники скачиваются **ролями Ansible** и кладутся под **`/opt/capi-lab`**;
* сетевой дизайн — **двухинтерфейсный**:

  * `eth0` internal dual-stack = default route / node identity / обычный egress;
  * `eth1` external IPv6-only = ingress-only / MetalLB / NodePort. ([Ubuntu Documentation][2])

В этом документе описывается уже **полная система**, но основной фокус — инфраструктурный bootstrap и networking для этой схемы.

Отдельно фиксируется граница **текущего репозитория разработки**:

* этот repo содержит только **reusable implementation code**:

  * Ansible roles,
  * Terraform modules,
  * Helm charts (`charts/`, §2.9 + §16..§17) — единственный носитель
    Kubernetes CR-content'а,
  * Molecule/Vagrant/libvirt test harness,
  * `Makefile` и scripts для полного локального тестирования;
* этот repo **не содержит** прямой конфигурации реальных окружений:

  * inventories,
  * host/group vars,
  * secrets,
  * environment-specific tfvars,
  * root modules под конкретные площадки,
  * `make deploy TARGET=...`/`make destroy ...` для production-like окружений;
* concrete environment composition должна жить в **отдельных private consumer repos**, которые импортируют/подключают код из этого repo.

---

# 2. Зафиксированный контракт

## 2.1. Платформа

Зафиксировано следующее:

* target host: **Debian 13 Trixie**;
* local dev/test VM: **Debian 13 Trixie**;
* LXD ставится **через snap**, потому что это официальный рекомендуемый способ установки LXD на Linux, включая Debian; snap tracks/channels должны быть pinned. ([Ubuntu Documentation][3])

## 2.2. Политика по пакетам и бинарникам

На Debian host:

* допускаются только **системные APT-пакеты**;
* **запрещены** custom APT repositories;
* **запрещена** установка нестандартных инструментов через APT;
* все нестандартные инструменты должны:

  * скачиваться ролями Ansible,
  * быть version-pinned,
  * проверяться по checksum,
  * раскладываться под `/opt/capi-lab/bin`.
    LXD snap уже сам тянет свои зависимости, а snap updates надо отдельно контролировать через `snap refresh --hold` или `refresh.timer`. ([Ubuntu Documentation][3])

## 2.3. Политика по изоляции

Весь lab живёт в отдельном **LXD project** — например, `capi-lab`, чтобы не задеть уже существующие вручную поднятые LXC/LXD контейнеры и их сети. LXD projects изолируют instances, а при включённых feature-флагах — также profiles, images и другие сущности. При `restricted=true` можно точечно разрешить нужные sensitive features вроде nesting. ([Ubuntu Documentation][4])

Доступ CAPN к LXD API должен идти через **restricted TLS certificate**, ограниченный только project `capi-lab`. LXD documentation прямо поддерживает restricted TLS certificates с project confinement. ([Ubuntu Documentation][5])

## 2.4. Политика по bootstrap management cluster

Bootstrap management cluster:

* должен жить **в отдельном LXC system container**;
* не должен жить в host namespace;
* не должен использовать Docker/kind;
* должен следовать той же isolation policy: bootstrap container по умолчанию тоже считается **unprivileged LXC**, а privileged bootstrap container не является допустимым shortcut;
* для нашей схемы поднимается как **single-node k3s** внутри bootstrap-container.
  K3s — fully compliant lightweight Kubernetes distribution, распространяемый как single binary; `k3s server` поддерживает `--tls-san`, `--disable=servicelb`, `--disable=traefik` и config file. ([K3s][6])

## 2.5. Политика по границе репозитория

В этом repo:

* разрешены только reusable роли/модули и local test harness;
* разрешены test fixtures, которые нужны для Molecule/Vagrant/libvirt e2e;
* запрещены любые environment-specific данные реальных площадок:

  * реальные IP/FQDN,
  * inventories и host targeting,
  * plaintext secrets,
  * реальные LXD trust materials,
  * root orchestration для deploy/destroy в конкретные окружения.

Следствие: orchestration layer для реальных окружений считается **внешним consumer layer** и не проектируется как часть этого repo.

## 2.6. Политика разработки Ansible roles

Style contract для ролей этого repo должен сознательно следовать образцам `mini-pig-ansible-collection/roles/init` и `mini-pig-ansible-collection/roles/naive_proxy`, но без слепого копирования их предметной логики. Из этих ролей берётся именно engineering style: структура defaults, naming variables/tasks/handlers/tags, dispatcher-only `tasks/main.yml`, обязательный `preflight`, практичные комментарии, короткие handlers, сильный `README.md` и реалистичная верификация. ([30], [31], [32], [33])

Reference links, на которые агенту разрешено и полезно ориентироваться напрямую:

* `init` role: [30]
* `naive_proxy` role: [31]
* `naive_proxy` Molecule harness: [32]
* `naive_proxy` README: [33]

### 2.6.1. Native-first policy и идемпотентность fallback-шагов

Для разработки ролей Ansible следуем Ansible best practices. Под любую задачу в первую очередь ищется native-модуль; императивные вызовы (shell и HTTP-mutation через `uri`) допустимы только как последнее средство и обязаны иметь отдельную обёртку на идемпотентность.

**Порядок выбора implementation path (жёсткий):**

1. сначала native module из `ansible.builtin.*`;
2. затем подходящий module из внешней Ansible collection (`community.general`, `ansible.posix`, `kubernetes.core`, `community.crypto` и т.д.);
3. только если подходящего модуля нет или он объективно не покрывает нужное поведение — допускается fallback на `shell` / `command` / `script` / `raw`, либо `ansible.builtin.uri` с mutating method (`POST` / `PUT` / `PATCH` / `DELETE`).

**Запрещено** использовать shell-скрипты, `shell`, `command`, `script` или `raw` там, где задача решается существующим native- или collection-модулем. `ansible.builtin.uri` для HTTP API формально относится к native-модулям (см. §13.4/§13.5 — LXD REST через unix_socket), но с mutating method имеет ту же императивную семантику, что и shell fallback, и подчиняется одинаковым требованиям к идемпотентности.

**Любой fallback-шаг обязан:**

* быть явно обоснован коротким комментарием в коде роли (почему native-модуль не подходит);
* быть реально идемпотентным: второй запуск подряд — no-op;
* честно репортить `changed` — `true` ⇔ state мутирован, `false` ⇔ ничего не сделано;
* добиваться идемпотентности и честного `changed` через **дополнительную обёртку в самой таске** — одним из механизмов:
  * pre-check (GET / `stat` / `getent` / query API) → `set_fact` с diff → `when:` guard на мутирующем шаге, чтобы в steady state он просто не запускался;
  * `creates:` / `removes:` для `shell`/`command` (Ansible сам скипает step и корректно работает с `--check`);
  * парсинг stdout/rc через `failed_when:` и `changed_when:` на основе содержимого вывода, а не на константе;
  * PUT с полным desired body вместо POST, если API поддерживает idempotent upsert;
  * register before/after и `changed_when:` по реальному diff;
* не подменять собой уже существующие declarative modules.

**Запрещённый паттерн:** маскировать always-changed мутирующий шаг через `changed_when: false` ради того, чтобы Molecule idempotence-гейт стал зелёным. Это не идемпотентность, а её симуляция: одновременно ломает Molecule idempotence-гейт, `ansible-playbook --check` (ложноотрицательный no-op при реальной мутации) и drift detection в steady-state кластере. `changed_when: false` легитимен **только** на read-only шагах (`GET` / `show` / `list` / `stat` / assertion).

Canonical pattern fallback'а через `uri`: `ansible/roles/lxd_storage_pools/tasks/pools.yml` — GET → derive existing → POST с `when: item.name not in existing` и `changed_when: true`; PATCH только при обнаруженном diff. Canonical shell fallback: `ansible/roles/lxd_host/tasks/refresh.yml` — pre-read текущего значения через read-only `snap get`, затем `set` только при diff с честным `changed_when`.

### 2.6.2. Variables contract и layout

Каждая роль этого repo должна соблюдать следующий contract:

* публичные переменные живут в `defaults/main.yml` и имеют строгий role prefix вида `<role_name>_*`;
* внутренние/приватные переменные, derived facts, helper paths, unit names и `register` values должны иметь leading underscore prefix вида `_<role_name>_*`;
* запрещены безликие имена вроде `enabled`, `config`, `result`, `packages`, `service_name` без role prefix;
* boolean-переменные и feature toggles должны называться утвердительно и предметно: `<role_name>_enabled`, `<role_name>_flow_control_*`, `<role_name>_update_*`, а не `do_*`, `with_*`, `run_*`;
* `defaults/main.yml` группируется по осмысленным секциям и содержит только практичные комментарии про поведение, trade-offs и caveats;
* секции в `defaults/main.yml` оформляются в читаемом стиле вроде `# -- General --`, `# -- Network --`, `# -- Paths --`, если это помогает быстро считывать contract роли;
* если у роли есть публичный contract, у неё обязан быть собственный `README.md` с purpose, requirements, variables, tags, examples, testing notes и known caveats;
* `tasks/main.yml` должен быть dispatcher-only файлом, который оркестрирует короткие тематические `include_tasks`, а не длинным “скриптом на YAML”;
* файлы задач должны называться по предметной области (`preflight.yml`, `install.yml`, `config.yml`, `services.yml`, `healthchecks.yml`), а не по случайным внутренним шагам;
* входные инварианты и обязательные параметры проверяются в отдельном `preflight.yml` через `ansible.builtin.assert` до начала mutating tasks;
* `handlers/main.yml` допускается только для реально реактивного поведения и должен оставаться коротким и предсказуемым;
* `templates/`, `files/`, `vars/`, `meta/` добавляются только по реальной необходимости, а не шаблонно “на всякий случай”.

### 2.6.3. Naming, tags, registers и flow control

Для единообразия repo фиксируются такие правила:

* canonical display-name роли в task/handler names должен быть в kebab-case, даже если directory name роли в repo остаётся snake_case;
* для переменных, facts и register names используется именно snake_case role prefix из имени директории роли, например `base_system_*` и `_base_system_*`, а не display-name в kebab-case;
* имена tasks строятся по схеме `<role> | <section> | <action>`;
* имена handlers строятся по схеме `<role> | handlers | <action>`;
* `tasks/main.yml` использует `include_tasks` с `apply.tags`, а вызывающий task повторяет тот же набор `tags`;
* `preflight` должен быть первым include в `tasks/main.yml`, если роль вообще что-то меняет на target host;
* coarse-grained flow control допустим только на уровне роли или крупного subfeature, например `<role>_enabled` и `<role>_flow_control_*`;
* запрещены микропереключатели “по таске”, которые размывают contract роли и затрудняют тестирование;
* у публичных tags должен быть минимум role-level tag и section-level tag; если для роли существует и underscore, и hyphen spelling, допустимо поддерживать оба алиаса;
* `register` names и `set_fact` names должны оставаться scoped и читаемыми: `_<role_name>_<section>_<purpose>_register` или `_<role_name>_<section>_<fact>`;
* временные loop vars, helper vars и computed vars не должны утекать в глобально-общие имена.
* **Non-Ansible naming** (Make targets, Molecule scenario directories под
  `tests/molecule/`, shell helpers, scripts) используют **kebab-case**.
  Смешение `_` и `-` в именах Make targets (например `base_system-delegated-test`)
  запрещено как лишний источник боли на командной строке. Scenario
  directory `tests/molecule/<name>/` не является role directory и не
  подпадает под snake_case контракт ролей — её имя всегда kebab-case, а
  ссылка на применяемую роль идёт через поле `_shared_target_role` в
  scenario's `molecule.yml`.

### 2.6.4. Handlers contract

Подход к handlers в этом repo тоже фиксируется явно:

* handlers существуют только для реактивных действий после изменений: `restart`, `reload`, `daemon-reload`, `recreate`, `reissue`, а не для основной business logic роли;
* handler не должен заниматься input validation, discovery, вычислением переменных, template rendering или побочным orchestration, которое должно быть обычной задачей;
* если нужно каскадное поведение, допускается bounded `notify` chain внутри роли, как в `naive_proxy`, но зависимость должна быть читаемой и конечной;
* в handlers нужно предпочитать module-based actions, например `ansible.builtin.systemd`/`service`; shell fallback допустим только как документированное исключение;
* если handler вынужден использовать shell/command ради tool-gap, он обязан сохранять предсказуемую семантику `changed` и не создавать ложную “постоянную изменённость” роли;
* handler names должны быть достаточно конкретны, чтобы их можно было вызывать через `notify` без коллизий между ролями.

### 2.6.5. Role dependencies contract

Любая зависимость между ролями в этом repo должна быть объявлена **в
`meta/main.yml` зависимой роли**, а не эмулироваться снаружи:

* если роль `B` не будет корректно работать без того, что ставит роль
  `A` (пакеты, kernel knobs, artefacts на диске, daemons), `A` обязана
  лежать в `dependencies:` роли `B`;
* консамерам (playbook `roles:`, другой role's meta, Molecule converge
  через `include_role`) НЕ разрешается вручную «выстраивать порядок» —
  meta-deps обязаны делать это автоматически;
* `prepare.yml` в Molecule-сценарии отвечает только за **test-harness
  bootstrap** (apt cache, test deps, mock assets), но **не** запускает
  другие роли «потому что мы знаем, что они нужны»: это маскирует
  missing dependency в самой роли;
* зависимость, реализованная только в prepare-шаге, считается багом
  contract'а роли и подлежит миграции в `meta/main.yml`;
* meta-deps являются единственным supported способом автоматического
  ordering — использовать `pre_tasks` / `ansible.builtin.import_role`
  из playbook'а для подмены этой семантики запрещено.

Дополнительная дисциплина оформления meta-deps (обязательна начиная с
Phase 2):

* **Each meta dep MUST carry a one-line `# why` comment** в
  `meta/main.yml`. Без why-комментария будущий reviewer не сможет
  отличить обязательную зависимость от случайно оставшейся, и при
  cleanup-рефакторинге dep будет молча удалён, а регрессия появится
  позже и без понятной привязки к коммиту.
* **Do not declare transitive meta deps.** Если `lxd_profiles` требует
  `lxd_host`, а `lxd_host` уже задекларирован как dep у
  `lxd_project`, в `lxd_profiles/meta/main.yml` пишется только
  `lxd_project`. Перечислять всю цепочку вручную запрещено — это
  раздувает граф и превращает любую будущую перестановку в
  merge-conflict.
* **A role MUST NOT read or condition on variables using another
  role's `<other_role>_*` prefix.** Кросс-ролевая коммуникация идёт
  только через:
  1. global contract переменные с проектным префиксом `k8s_lab_*`
     (§8, напр. `k8s_lab_opt_root`, `k8s_lab_uplink_interface`),
     которые являются stable inter-role interface. Naked globals без
     `k8s_lab_` префикса запрещены (memory
     `feedback_global_var_prefix.md`, 2026-04-23) — см. также §2.6.2;

  2. facts, публикуемые через `set_fact` + корректное именование
     `_<role>_<section>_<fact>`, если требуется передать runtime
     значение;
  чтение чужого `<role>_*` в своих defaults/conditions создаёт
  implicit coupling, невидимое из контракта обеих ролей.

Нарушение этих правил приводит к «скрытым» зависимостям, которые
молча работают в одном Molecule-сценарии и ломаются в другом.

### 2.6.6. Комментарии, README и проверяемость

Роли этого repo не должны быть “самодокументируемыми” только по мнению автора:

* нетривиальные defaults, conditionals и operational caveats должны иметь короткий, предметный комментарий;
* `README.md` роли должен объяснять не только “что ставится”, но и runtime model, managed artifacts, service units/timers, security/runtime notes и примеры реального использования;
* verify-path должен проверять не только синтаксис и idempotence, но и реальное поведение роли;
* использование `command`/`shell` в verify допустимо только если модульного эквивалента нет или он не позволяет проверить нужный runtime path; такое исключение должно быть явно помечено и не должно вносить изменения в систему.

## 2.7. Ownership model между слоями

В этом плане source of truth делится жёстко и без overlap:

* **Ansible roles** владеют только:

  * host bootstrap,
  * LXD substrate,
  * bootstrap management cluster,
  * local harness и validation orchestration;
* **Terraform modules** владеют всем, что становится:

  * Cluster API objects,
  * Kubernetes objects внутри management/workload clusters,
  * machine templates,
  * guest networking configuration CAPN-managed nodes,
  * kube-proxy configuration,
  * cluster add-ons вроде `Calico` и `MetalLB`;
* **test fixtures** не реализуют отдельную логику и не становятся ещё одним ownership layer:

  * они только связывают reusable roles/modules,
  * подают synthetic values,
  * запускают локальную проверку контракта.

Следствие:

* Ansible **не** является владельцем guest networking внутри CAPN-managed nodes;
* Ansible **не** ставит `Calico`, `MetalLB` и cluster-scoped manifests в workload/target management clusters;
* `tests/fixtures/*` не должны содержать ad hoc manifests или one-off implementation, отсутствующую в `ansible/roles`, `terraform/modules` или `charts/`.

## 2.8. Политика по режиму LXC-нód

Для `v1.0` и для всего local harness зафиксирован **единственный поддерживаемый path**:

* control-plane и worker nodes запускаются как **unprivileged LXC containers**;
* `privileged` path не является частью поддерживаемого implementation scope для `v1.0` и не считается допустимым fallback.

Причины:

* LXD documentation рекомендует использовать unprivileged containers по умолчанию и отдельно предупреждает, что privileged containers не являются root-safe; для усиления изоляции LXD также рекомендует `security.idmap.isolated=true` там, где контейнерам не нужен shared UID/GID mapping. ([34])
* CAPN официально поддерживает unprivileged containers для `instanceType: container`; для этого path нужно выставлять `PRIVILEGED=false` / `.spec.unprivileged=true`, а pre-built kubeadm images с нужной настройкой runtime доступны начиная с `v1.32.4`. ([24], [17])
* для Canonical LXD CAPN публикует отдельный **unprivileged LXD kubeadm profile**: он использует `linux.kernel_modules`, требует `security.nesting=true`, монтирует host `/boot` в `/usr/lib/ostree-boot` и дополнительно отключает внутри guest `snapd` и `apparmor` systemd units. ([17])
* Kubernetes user-namespaces docs требуют idmap-capable filesystems и runtime support; `containerd 2.0+` поддерживает user namespaces для containers, а `KubeletInUserNamespace` по состоянию на Kubernetes `v1.35` всё ещё имеет статус `Alpha`. ([35], [36], [37])

Следствие:

* `lxd_profiles` для `capi-controlplane` и `capi-worker` в `v1.0` строятся от **CAPN Canonical LXD unprivileged kubeadm baseline**, а не от privileged profile;
* для Kubernetes node containers надо включать `security.idmap.isolated=true`, если этому не мешает конкретный verified workload contract;
* `security.nesting=true` допускается только на тех profiles, где это действительно нужно для Kubernetes node/CRI path, а не как project-wide default;
* privileged LXC не должен использоваться как “быстрый обход” для проблем с kubelet, containerd, CNI или add-ons;
* если unprivileged path не проходит gate, допустимы только такие решения:
  * поменять CNI / сузить feature scope на этом же unprivileged substrate,
  * либо перейти на VM-based nodes;
* агент не должен тратить время на параллельную реализацию privileged и unprivileged режимов.

## 2.9. Политика по Terraform + Helm delivery для Kubernetes-объектов

Все Kubernetes-объекты, которые этот repo создаёт на bootstrap /
management / workload кластерах, доставляются **как Helm charts**,
устанавливаемые Terraform-ом через `hashicorp/helm` provider.

Зафиксировано:

* Terraform использует `hashicorp/helm` provider, pinned в §8
  `k8s_lab_helm_provider_version` (версия + дата проверки — §8a);
* единственный путь apply любых K8s CR-ов — `helm_release`. `kubectl
  apply -f`, `kubernetes_manifest`, raw YAML под `manifests/*`-подачей,
  Ansible post-apply через `kubernetes.core.k8s` с state=present —
  запрещены для create/update/apply. `kubernetes.core.k8s_info` и
  `hashicorp/kubernetes` provider допустимы **только на read-side**:
  data lookups, status polling, verify-assertions;
* upstream-компоненты ставятся из их **официальных Helm chart sources**,
  завёрнутых в локальные wrapper charts (`charts/cni-calico/`,
  `charts/metallb-config/`) через `Chart.yaml` dependencies:

  * workload CNI: `projectcalico/tigera-operator` ([26]) — shipped
    реализация; swap на другую CNI — через `cni_chart_path` input
    §17.1, не toggle;
  * MetalLB: `metallb/metallb` ([27]);
* CR-ы, которых нет в upstream chart'ах, доставляются через **локальные
  wrapper / owned charts** этого repo в директории `charts/`. Это
  покрывает два класса объектов:

  * **CAPI topology** (ClusterClass, Kubeadm/CP/Config templates,
    LXC*Template'ы, Cluster CR-ы) — §16.2 / §16.3;
  * **Add-ons configuration + validation** (MetalLB IPAddressPool /
    L2Advertisement, CNI + external L2 probe Job'ы через
    `helm.sh/hook: test`) — §17.1 / §17.3.

### CAPI CR immutability и revision pattern

CAPI admission webhook запрещает менять большинство полей `ClusterClass`
и `*Template` CR-ов после того, как Cluster сослался на них. Любой
edit values.yaml = новая версия chart'а = новый набор объектов с
новыми именами; старые продолжают жить до контролируемого переключения.

Реализация — одна строка в `metadata.name` каждого подобного CR-а:

```yaml
metadata:
  name: {{ include "<chart>.fullname" . }}-{{ .Chart.Version }}
```

Chart, который ссылается на ClusterClass (workload-cluster chart на
cluster-class chart), собирает то же имя по той же формуле из общего
values-блока (`clusterClass.chartVersion` передаётся из Terraform
module на оба release'а одновременно). Bump `Chart.yaml.version` →
`helm upgrade` создаёт новую пару ClusterClass + Template'ов и ссылку
на них из Cluster CR, старые живут до осознанного cleanup'а. Без
этого любой live-edit падает на `admission webhook denied: field is
immutable`.

### Ordering и webhook readiness

Порядок helm_release'ов внутри одного Terraform apply'а задаётся
явным `depends_on`:

* CAPI controllers (принесены `bootstrap_clusterctl` через `clusterctl
  init`, §13.10) — **не** helm_release этого repo, но обязательный
  предок любого Phase 5+ apply'а; Phase 4 закрывается перед тем, как
  Phase 5 стартует;
* `helm_release.cluster_class` — создаёт ClusterClass + *Template'ы;
* `helm_release.workload_cluster` (`depends_on = [cluster_class]`) —
  создаёт Cluster CR, который ссылается на ClusterClass;
* `helm_release.<cni>` / `helm_release.metallb` / probe charts — на
  target-кластере, отдельный Phase 5.1 apply через свой kubeconfig.

`helm_release.wait = true` (default в `hashicorp/helm` 3.x) +
`atomic = true` обязательны на всех release'ах CR-данных: без
`wait` admission webhook'и CAPI/CAPN могут не успеть принять трафик
до того, как следующий release в depends_on-цепочке дойдёт до apply'а;
без `atomic` partial failures оставляют кластер в неконсистентном
состоянии.

`force_update` должен оставаться `false` (default) — включение
ломает SSA ownership CAPI/CAPN controller'ов, приводит к flip-flop
reconciliation.

### Test fixtures и orchestration

* `tests/fixtures/terraform/workload-clusters/lab-default/capi` —
  Phase 5 fixture, provider = bootstrap kubeconfig, ставит CAPI
  topology chart'ы (§16);
* `tests/fixtures/terraform/workload-clusters/lab-default/addons` —
  Phase 5.1+ fixture, provider = workload kubeconfig, ставит CNI +
  MetalLB + probe charts (§17);
* chart versions pinned в §8 variable contract и обновляются
  осознанно (каждый bump — запись в §8a verified version log);
* in-cluster validation (CNI viability, external L2 viability) —
  часть этой же delivery policy, реализована как `helm.sh/hook: test`
  Job'ы в probe chart'ах (§17.3), запускается тем же `terraform
  apply`. Failed hook фейлит `helm_release` → фейлит `terraform
  apply`. Валидация не вне policy, а внутри неё. Отдельных Ansible-
  ролей для сетевой валидации нет;
* Terraform предполагается уже установленным на runner'е; Ansible
  его не ставит. Оператор / агент вызывает Phase 5+ через Makefile-
  target вручную (`make deploy-workload-capi`, `make deploy-workload-addons`
  — §16.7 / §17.4).

## 2.10. Политика по образам нод

Для `v1.0` зафиксирована следующая image strategy:

* local harness по умолчанию использует CAPN pre-built kubeadm images с default simplestreams server, например `capi:kubeadm/VERSION`; ([16], [20])
* `INSTALL_KUBEADM=true` не является частью поддерживаемого `v1.0` path, потому что CAPN documentation прямо описывает этот режим как development-oriented fallback; ([20])
* consumer repos для реальных окружений должны иметь возможность переопределять image refs на свои custom images с pinning по версии/alias/fingerprint.

Следствие:

* в этом repo agent должен строить код вокруг prebuilt kubeadm image path;
* install-kubeadm-at-runtime режим не является CR-полем в CAPN v1alpha2 API — он моделируется добавлением `preKubeadmCommands` в KCPT/KCT (chart §16.2 принимает их через `controlPlane.preKubeadmCommands` / `worker.preKubeadmCommands`, consumer-facing default — пустой список). Substrate-required `preKubeadmCommand` (dual-stack `node-ip` patch для kubeadm config'а — см. §16.2) рендерится всегда отдельно от consumer values, consumer'у его трогать не нужно. MVP path использует prebuilt образы и пустой consumer-список;
* риск использования evaluation-oriented CAPN images должен быть явно отмечен и не маскироваться под production-ready supply path;
* **cloud-init-capability — substrate-required для любого образа**,
  идущего в `k8s_lab_images_controlplane` / `k8s_lab_images_worker`.
  `capi-worker` и `capi-controlplane` LXD profile'ы несут
  `cloud-init.vendor-data` (§13.6 Step 9) который конфигурирует
  eth1 RA reception на first boot. CAPN-prebuilt `capi:kubeadm/*`
  образы это гарантируют; custom-образ консумера без cloud-init'а
  = неработающий external L2 plane на всех worker'ах.

## 2.11a. Политика «тестируй до коммита»

Строгое и базовое требование. Ни один commit не допустим до тех пор,
пока код не был **реально выполнен** в локальном Vagrant/libvirt-контуре
этого repo и не прошёл соответствующую acceptance-проверку:

* для любой новой или изменённой Ansible-роли — Molecule-сценарий этой
  роли прогоняется end-to-end против shared Vagrant VM (минимум
  `converge → idempotence → verify`), а не против podman/docker-driver;
* для любого нового или изменённого `Makefile`-target — target
  реально исполняется против того же harness;
* для любого нового или изменённого Helm chart'а (upstream values
  override, local wrapper chart, probe chart) — chart ставится
  Terraform'ом в интеграционный scenario (`cluster-addons-helm`)
  против real target cluster в локальном harness, `helm test
  <release>` должен вернуть exit=0. Probe chart'ы (§17.3) тоже
  подпадают — Gate A/Gate B acceptance доказывается live прогоном,
  не static review;
* для любого plan-deviation, добавляющего новое проверяемое поведение
  (например, btrfs pool contract из stage 1) — verify должен **реально
  срабатывать на настоящем state**, а не просто парситься;
* static checks (`yamllint`, `ansible-lint`, `terraform fmt`) — это
  необходимое, но **не достаточное** условие. «Lint зелёный» не
  считается доказательством работоспособности;
* если prerequisite недоступен (libvirt down, KVM модули не загружены,
  Vagrant отсутствует), агент обязан остановиться и сообщить об этом
  пользователю, а не понижать planku до более слабого драйвера;
* commit происходит **только после** того, как пользователь видел
  passing run, либо явно авторизовал автономную работу по задаче;
* исключения фиксируются прямо в этом документе как отдельные
  deviation-пункты под соответствующей секцией (роль / phase /
  variable) с обоснованием — see §2.11b о workflow «правим план по
  ходу разработки».

Эту политику нельзя «временно снять» ради ускорения сессии: она
существует, потому что пройденный lint-этап слишком часто маскирует
runtime-баги в Ansible / Molecule / Vagrant, а локальный harness уже
достаточно воспроизводим для честного end-to-end прогона.

## 2.11. Политика по версиям зависимостей

Отдельная обязательная политика, без которой остальной контракт теряет смысл:

* все внешние зависимости — Kubernetes, k3s, CAPI/`clusterctl`, CAPN,
  LXD snap channel, Helm charts (Calico/MetalLB), Terraform
  providers, Ansible collections, base OS images, container runtimes,
  CLI-инструменты — должны быть зафиксированы на **актуальную stable
  upstream версию на момент обновления**;
* «стабильный безопасный default» из старой документации или из памяти
  модели **не считается** валидным выбором: перед pin-ом агент обязан
  сверить upstream (`GET /repos/<o>/<r>/releases/latest`, vendor snap
  info, registry index) и зафиксировать проверенное значение;
* в `requirements.yml` / provider blocks / Helm chart references нельзя
  использовать нижние границы, которые запирают будущие major-релизы:
  любая запись вида `>=X,<X+1` считается stale-pin и подлежит снятию
  на момент обновления;
* каждая зафиксированная версия и дата проверки фиксируются **inline
  рядом с pin'ом в §8** и дополнительно сводятся в таблицу §8a,
  чтобы отличать осознанный pin от устаревшего;
* conflict resolution: если vendor official guidance (например, LXD
  Canonical recommendation для LTS 5.21 вместо feature track `6`)
  расходится с «самой новой stable upstream», по умолчанию берём
  наиболее свежий feature-stable и явно фиксируем trade-off в §8a
  (секция deviation);
* единственное исключение: upstream ещё не выпустил stable и есть
  только prereleases — тогда временно допустим предыдущий stable, с
  явной пометкой в §8a и задачей на апгрейд при первом stable-
  релизе.

Следствие:

* любой code change, который вводит или меняет version pin, обязан
  сопровождаться sync-ом §8 inline-комментария и, при необходимости,
  строки в §8a table;
* default-значения в `defaults/main.yml`, `variables.tf` и shared
  Molecule vars должны соответствовать той же самой актуальной
  версии, что и запись в таблице;
* CI/lint-этап (когда появится) должен уметь подсвечивать stale pins
  против upstream.

## 2.11b. Политика «план — live-документ; отдельного progress-файла нет»

Набор файлов `PLAN-stage1-common.md` + `PLAN-stage1-1.md` ..
`PLAN-stage1-7.md` (и аналогичный набор `PLAN-stage<N>-*.md` для
будущих stage'ей) является **единственным источником истины** и по
замыслу, и по статусу выполнения плана. Актуальная карта file lineup
с §N-диапазонами и названиями под-секций живёт в
`## Оглавление` в `PLAN-stage1-common.md` (см. начало файла) — при
добавлении/расщеплении шардов она обновляется там. Нумерация §N
сквозная по всем этим файлам (см. header в `PLAN-stage1-common.md`), и
перекрёстные ссылки формата `§<номер>` валидны без указания имени
файла. Отдельного `PLAN-*-progress.md` / `CHANGELOG.md` или любого
внешнего трекера репо **не ведёт** — все дополнения, пометки о
выполнении, отклонения от плана и implementation notes живут прямо
в этих файлах под соответствующими пунктами (роль / phase /
variable). Общие политики / contract / architecture — в
`PLAN-stage1-common.md`; stage-specific роли, modules, phase order —
в соответствующих `PLAN-stage<N>-*.md` шардах (атомарная нарезка
по смысловым блокам, чтобы минимизировать context-weight отдельного
шарда для coding-agent'а).

Что обязан делать агент **по ходу разработки**:

* когда реализация раскрывает, что ранее записанный пункт плана не
  работает как заявлено (упёрлись в ограничение платформы,
  архитектурная деталь всплыла только на тесте), агент обязан
  **исправить сам пункт плана** и рядом зафиксировать deviation с
  датой (`Статус: выполнено в Step N (YYYY-MM-DD)` + пояснение —
  см. §13.3, §13.5 как reference);
* любая полезная архитектурная деталь или implementation note,
  которая не видна из итогового кода (почему выбран модуль X, чем
  не подошёл Y, какая операционная ловушка стреляет), добавляется
  инлайн в соответствующий §13.X / Phase-секцию;
* каждый выполненный пункт плана помечается строкой
  `**Статус: выполнено в Step N (YYYY-MM-DD).**` в начале
  соответствующего подраздела. «Step N» — это номер крупной
  итерации разработки, которую агент фиксирует в git-коммит-логе и
  о которой согласовался с оператором;
* перечисленные изменения плана должны быть согласованы с
  оператором (conversation-level), когда они меняют поведение или
  scope; корректировки мелкого характера (формулировка, пометка
  выполнения, добавление implementation note без смены контракта)
  агент вносит без запроса.

Что запрещено:

* возрождать отдельный progress-файл в любой форме;
* хранить «что сделано» в external-системах (GitHub wiki, Notion,
  memory-заметки агента) как замену этим файлам — memory агента
  остаётся для preferences и устойчивых workflow-хинтов, а не для
  дублирующего реестра выполненных пунктов;
* оставлять несоответствие между фактическим поведением кода и
  текстом плана дольше одной сессии — если расхождение замечено,
  либо код приводится в соответствие с планом, либо план
  пересматривается в рамках той же сессии.

## 2.12. Политика HA для workload cluster add-ons

`k8s_lab_workload_controlplane_count` и `k8s_lab_workload_worker_count`
по умолчанию = `2` именно для того, чтобы workload cluster был
полноценной HA-площадкой, а не «1+1 расширенным single-node». Из
этого следует обязательный контракт для всего, что Phase 5.1
(§17.4) ставит в workload cluster через Terraform Helm pass:

* **Replica contract.** Любой компонент, чья архитектура допускает
  multi-replica active/active либо leader-elected active/standby
  (т.е. `Deployment` / `StatefulSet` controllers), разворачивается с
  `replicas: 2` по умолчанию. Это касается, в частности:
  * MetalLB controller (`metallb-controller` Deployment) — leader-
    elected, два replicas корректны;
  * Calico Typha (`calico-typha` Deployment) — официально supported
    multi-replica с автоконфигом via Typha discovery service;
  * MetalLB speaker (`metallb-speaker`) и Calico node агент
    (`calico-node`) — это `DaemonSet`'ы; их replicas «авто-2»
    приходит из факта `k8s_lab_workload_worker_count = 2`, отдельный
    override не нужен;
  * любой ingress-controller / cert-manager / external-dns /
    metrics-server / etc., если будет добавлен в этот pass — `replicas: 2`
    по умолчанию + `topologySpreadConstraints` или
    `podAntiAffinity` на `kubernetes.io/hostname`, чтобы реплики
    реально оказывались на двух разных worker-нодах.
* **Когда HA НЕ применяется.** Если у компонента архитектурно
  единственный singleton (например, какой-нибудь stateful operator
  без leader-election) — допускается `replicas: 1` с явным
  inline-комментарием в Terraform `helm_release` values, объясняющим
  почему. Это исключение, а не норма.
* **Test contract — обе реплики работают в тандеме.** §17.4
  acceptance НЕ ограничивается `kubectl wait deployment <X>
  --for=condition=Available`: condition=Available разрешает
  `availableReplicas >= maxUnavailable`, что для `replicas: 2 +
  maxUnavailable: 1` даёт зелёный сигнал даже когда работает только
  одна. Тесты Phase 5.1 должны явно ассертить:
  * `status.readyReplicas == 2` и `status.availableReplicas == 2`
    на каждом таком Deployment / StatefulSet;
  * пара Pod'ов реплик действительно на разных нодах
    (`spec.nodeName` уникален по списку Pod'ов компонента);
  * leader-elected компоненты имеют ровно одного активного leader'а
    и второй pod в standby (для MetalLB controller — через лог
    `acquired lease`; для cert-manager — `kube-system` lease object;
    каждый компонент проверяется по тому identity-механизму, который
    у него документирован).
* **Распространение на mgmt cluster.** Mgmt cluster в default-
  топологии — `1+1`, поэтому HA-контракт там НЕ применяется
  автоматически. Если оператор поднимает mgmt с
  `k8s_lab_management_worker_count >= 2`, тот же replica-contract
  активируется через Terraform-условие на `var.worker_count >= 2`.

Этот контракт документируется и enforce'ится в §17.4 acceptance, и
зеркалится конкретными assertion'ами в §9.4 Integration / Full E2E
test scope.

---

# 3. Архитектурная модель: два режима

После ревью архитектура фиксируется как **два поддерживаемых режима**.

## 3.1. MVP / v1.0

`k8s_lab_pivot_enabled = false` по умолчанию.

Схема:

* Ansible поднимает bootstrap LXC;
* внутри него запускается `k3s server`;
* `clusterctl init --infrastructure incus` превращает его в management cluster;
* Terraform pass A из runner подключается к bootstrap cluster API и декларативно создаёт **workload cluster** через Cluster API CRDs;
* после появления target kubeconfig Ansible/scripts экспортируют его в `.artifacts/clusters/<cluster>.kubeconfig`;
* Terraform pass B подключается уже к target cluster и ставит cluster add-ons через `helm_release`;
* bootstrap cluster остаётся постоянным management cluster для lab.

Это даёт:

* меньше moving parts;
* проще destroy path;
* меньше phase coupling;
* уже настоящий CAPI lifecycle для workload clusters.
  `clusterctl init` официально превращает Kubernetes cluster в management cluster и автоматически ставит core provider + kubeadm bootstrap/control-plane providers, если вы инициализируете infrastructure provider. ([main.cluster-api.sigs.k8s.io][7])

## 3.2. Stage 2 / advanced

`k8s_lab_pivot_enabled = true`.

Схема:

* bootstrap cluster временный;
* Terraform pass A создаёт **target self-hosted management cluster**;
* после появления target kubeconfig Terraform pass B ставит add-ons в target management cluster;
* Ansible делает `clusterctl init` на target;
* Ansible делает `clusterctl move`;
* bootstrap container удаляется.

Важно: **pivot здесь не про HA**. На одном физическом хосте отказоустойчивости он не даёт. Он нужен только для:

* lifecycle symmetry;
* тренировки canonical bootstrap-and-pivot flow Cluster API;
* self-hosted management plane как learning goal.
  Cluster API docs прямо описывают `clusterctl move` как bootstrap & pivot механизм и отдельно предупреждают, что target management cluster должен уже иметь providers и минимум один worker node, иначе controllers некуда будет расписать. ([Cluster API][8])

---

# 4. Итоговая сетевая архитектура

## 4.1. Общая схема

На bare metal host есть две сетевые плоскости:

### External plane

* Linux bridge, например `br-ext6`;
* связан с uplink/WAN interface host;
* на этом сегменте идёт внешний IPv6 /64;
* по нему проходят RA и NDP;
* на него подключаются **external NIC** всех Kubernetes-нód;
* он используется только для:

  * внешнего IPv6 нód,
  * NodePort ingress,
  * MetalLB IPv6 VIP.
    LXD `bridged` NIC uses an existing bridge on the host and creates a veth pair; managed and unmanaged bridge attachments are both supported. ([Ubuntu Documentation][9])

### Internal plane

* LXD managed bridge, например `capi-int`;
* dual-stack;
* local L2 segment;
* `dnsmasq` для DHCP/DNS/IPv6 RA;
* NAT44/NAT66 через host;
* весь обычный control-plane/admin/node-to-node/egress traffic идёт здесь.
  LXD bridge documentation прямо говорит, что bridge создаёт L2 segment, запускает `dnsmasq` для DHCP/IPv6 RAs/DNS и по умолчанию выполняет NAT. Для IPv6 на LXD bridge рекомендуется /64. ([Ubuntu Documentation][2])

## 4.2. Роль интерфейсов внутри ноды

### `eth0` = internal

* dual-stack;
* kubelet/node identity;
* `--node-ip`;
* default route;
* pod/node/control-plane underlay;
* весь обычный egress.

### `eth1` = external

* IPv6-only;
* global IPv6 на внешнем сегменте;
* ingress only;
* не default route;
* NodePort и MetalLB ingress.

Для Kubernetes dual-stack cluster docs explicitly require a dual-stack-capable CNI and recommend `kubelet --node-ip=<IPv4>,<IPv6>` for bare-metal dual-stack nodes. ([Kubernetes][10])

## 4.3. Почему ingress и egress разделены

Ingress и egress разделяются специально:

* external NIC не должен стать “основной жизненной сетью” ноды;
* internal NIC несёт обычную underlay-логику;
* внешний сегмент остаётся узкоспециализированным north-south path;
* проще контролировать kubelet/node IP и default route.
  Это соответствует вашей целевой роли интерфейсов и снижает риск, что kubelet, kube-proxy или обычный системный egress внезапно уйдут через внешний IPv6 ingress NIC. ([Kubernetes][10])

---

# 5. Networking contract

## 5.1. External addressing

Пример:

* внешний префикс: `2001:db8:1200:3400::/64`
* host: `2001:db8:1200:3400::1`
* node ext IPv6 range: `::10-::3f`
* MetalLB VIP range: `::200-::2ff`

Это **логическое резервирование** внутри одного /64, а не разбиение на разные routed subnets. MetalLB `IPAddressPool` умеет использовать ranges/CIDR внутри IPv6 prefix. ([metallb.io][11])

## 5.2. Internal addressing

Пример:

* IPv4: `10.77.0.0/24`
* IPv6 ULA: `fd42:77:1::/64`

Рекомендуемый baseline для `capi-int`:

* `ipv4.address=10.77.0.1/24`
* `ipv4.dhcp=true`
* `ipv4.nat=true`
* `ipv6.address=fd42:77:1::1/64`
* `ipv6.dhcp=true`
* `ipv6.dhcp.stateful=true`
* `ipv6.nat=true`

LXD supports `ipv6.dhcp.stateful`, и static IPv6 assignment для instance NIC возможен только если parent managed network имеет `ipv6.dhcp.stateful=true`. ([Ubuntu Documentation][12])

## 5.3. Guest-side route policy

Для Debian 13 guest выбирается **systemd-networkd**.

Эта политика для CAPN-managed nodes должна попадать в машины через Terraform-owned machine bootstrap data/templates, а не через Ansible post-config внутри workload/management clusters.

Конкретный delivery mechanism тоже фиксируется:

* `KubeadmControlPlaneTemplate` и `KubeadmConfigTemplate` через CABPK являются единственным supported path;
* network files должны попадать в ноды через `KubeadmConfigSpec.files`;
* команды включения/reload `systemd-networkd` и related pre-bootstrap actions должны идти через `preKubeadmCommands`;
* kubelet flags вроде `--node-ip` должны задаваться через `nodeRegistration.kubeletExtraArgs`;
* kubeadm/kubelet patches должны доставляться через `files` + `patches.directory`, где это уместно. ([7], [28], [29])

### `eth1` (external)

* `IPv6AcceptRA=yes`
* `[IPv6AcceptRA] UseGateway=no`

Это позволяет:

* принять RA;
* получить on-link reachability / адресацию;
* **не** импортировать default route в main table.
  systemd-networkd manpage официально поддерживает `IPv6AcceptRA=` и `UseGateway=` для RA. ([Kubernetes][10])

### `eth0` (internal)

* обычный dual-stack config;
* default route;
* kubelet node IP.

## 5.4. kube-proxy NodePort policy

Так как по контракту NodePort должен приниматься **только** на external IPv6 адресах ноды, `--nodeport-addresses=<external IPv6 CIDR>` или эквивалентное поле в kube-proxy config является **обязательным**. Эта настройка должна приходить через Terraform-owned cluster configuration, а не через Ansible. Kubernetes docs прямо описывают, что `nodePortAddresses` ограничивает, на каких local node IP принимаются NodePort connections. ([Kubernetes][13])

## 5.5. MetalLB policy

MetalLB L2 остаётся базовым решением.

MetalLB manifests и policy должны применяться Terraform modules как частью cluster-scoped configuration.

Если upstream MetalLB chart values недостаточны для точной доставки `IPAddressPool` и `L2Advertisement` с нужными `interfaces`/`nodeSelectors`, эти CRs должны поставляться отдельным локальным wrapper Helm chart этого repo, установленным тем же `helm_release`, а не ad hoc manifest apply.

Нужно:

* `IPAddressPool` из external IPv6 range;
* `L2Advertisement` с:

  * `interfaces: [eth1]`
  * `nodeSelectors` на ноды с external NIC

MetalLB docs отдельно предупреждают, что `interfaces` selector сам по себе **не влияет на leader election**, поэтому его нужно сочетать с `nodeSelectors`, иначе VIP может быть выбран на ноде без нужного интерфейса. В L2 mode only one node announces a given VIP. ([metallb.io][11])

---

# 6. Validation gates — in-cluster через Helm test hooks

Validation gates (CNI viability, external L2 viability) реализуются
как **Helm test hooks** на тех Helm release'ах, которые в steady-state
path и так ставят соответствующий компонент: CNI-chart (shipped —
`charts/cni-calico/`, swap через §17.1 `cni_chart_path`) в Phase 5.1,
MetalLB-chart в Phase 5.3. Валидация встроена в `helm_release`
lifecycle и запускается одним `terraform apply`; провалившийся test
Job фейлит Terraform apply и останавливает пайплайн.

Доктрина:

* **Production-path mirror.** Worker-ноды создаются CAPN'ом через
  manifest change → CAPN controller → LXD API → cloud-init внутри
  контейнера. Валидация идёт через тот же механизм — Helm test Job
  запускается как Pod на real worker-нод'е, использует production
  LXD profile и cloud-init-сконфигурированный eth1.
* **One-tool pipeline.** Phase 5.x управляется через Terraform
  (`helm_release` provider). Helm нативно поддерживает test hooks
  (`helm.sh/hook: test` annotation на Job), Terraform запускает их
  как часть release lifecycle без переключения инструмента.
* **Real data plane.** Helm test Job с `hostNetwork: true` и
  anti-affinity по worker-нодам использует те же самые eth1 /
  br-ext6 / LXD profiles, что и production workload. RA/NDP/
  multi-MAC/ingress проверяются на реальном data plane.

## Gate A — External L2 viability

Реализация: Helm test hook на `metallb` release'е (§17.6 Phase 5.3).
MetalLB сам является единственным consumer'ом внешней L2 capability
(NDP для IPv6 VIP announcement), поэтому логично валидировать L2
именно там, где она впервые реально нужна.

Acceptance criteria (Job завершается exit=0 если все выполнены):

1. **multiple MAC pass** — 2 worker-нод'ы на разных хостах держат
   eth1 на br-ext6 с distinct MAC, host bridge форвардит оба;
2. **RA reception** — eth1 каждой worker-нод'ы получил global IPv6
   через SLAAC из rev-advertised `k8s_lab_external_ipv6_prefix`;
3. **NDP works** — Pod с `hostNetwork: true` на одной worker-нод'е
   ping6'ит eth1 другой worker-нод'ы через br-ext6 (NDP
   resolution обязан отработать);
4. **inbound IPv6 from probe endpoint** — тот же hostNetwork Pod
   ping6'ит `k8s_lab_external_probe_address` (§8, в local harness —
   in-VM `ext6-ra-peer` `2001:db8:42:100::1` от Step 9 harness RA
   source, см. §9.2; в consumer'ском prod — border router или probe
   VM в том же L2-сегменте). Значение прокидывается в MetalLB test
   Job через Helm chart values.

Если test hook Job проваливается — Terraform `helm_release` фейлится,
Phase 5.3 не проходит, дальнейшая реализация останавливается (MetalLB
без рабочего L2 бесполезен). Fallback ветка (routed / proxy-NDP) —
consumer'ская decision point, не часть Stage 1 scope.

Важно: local pass валидирует **reusable code path и in-VM harness
RA/segment model** (§9.2 Step 9), но не доказывает свойства
конкретного реального uplink/switch/provider. Consumer repo для
реального окружения обязан прогнать эквивалентный Helm test на
actual external segment — это уже тот же chart, те же профили,
только другой probe_address и RA приходит от настоящего
провайдерского роутера вместо in-VM radvd.

## Gate B — CNI compatibility

Реализация: Helm test hook на CNI release'е (shipped — Calico через
`charts/cni-calico/`), §17.5 Phase 5.2. Это первый Helm release
после Terraform CAPI pass, и без рабочего CNI остальные add-ons
даже не поедут — поэтому валидация именно здесь.

Acceptance criteria:

* **nodes become Ready** — все контрольные и worker-нод'ы в состоянии
  Ready после CNI install (test hook читает `kubectl get nodes`);
* **pod-to-pod works** — test hook разворачивает 2 Pod'а на разных
  worker-нод'ах, проверяет прямой pod-IP reachability в том наборе
  address families, который заявляет выбранный CNI;
* **Service networking works** — test hook создаёт Service тип
  ClusterIP, проверяет что trafффик через Service endpoint доходит;
* **не упираемся в nested LXC restrictions** — CNI bringup не падает
  на отсутствии каких-либо kernel features; если падает — gate
  фейлит с понятным сообщением;
* **MetalLB preparation** — iptables/ipvs chains выглядят так, как
  ожидает MetalLB (не проверяется напрямую здесь, валидация в
  Phase 5.3 Gate A покрывает).

### Принятое решение (CNI-baseline, не зависит от test-механизма)

* **unprivileged LXC substrate фиксируется заранее и не подлежит торгу из-за удобства CNI**
* **workload CNI = Calico** — single shipped реализация в repo
  (`charts/cni-calico/`). Обеспечивает NetworkPolicy, dual-stack IPAM
  и eBPF-option, которые нужны целевой архитектуре §4/§5.
* **нет alternative-path bundle'а в repo** и **нет toggle-переменной**
  для автоматического переключения CNI на другую реализацию. §17.1
  module принимает `cni_chart_path` как input; swap на другой CNI —
  явное дизайн-решение (новый wrapper chart в `charts/cni-<whatever>/`
  + правка fixture), не runtime-flag.
* **privileged LXC запрещён как workaround для CNI-проблем**

Почему так:

* целевая архитектура §4/§5 — dual-stack IPv4+IPv6 с NetworkPolicy-
  enforcement'ом. Calico закрывает оба требования одной реализацией;
* Calico documentation для стандартной Kubernetes installation
  описывает некоторые capabilities, поэтому Gate B (§17.5) на
  нашем unprivileged LXC substrate'е обязателен — acceptance live
  probe, не static review ([26]);
* если Gate B фейлит — это сигнал, что выбранная CNI-реализация
  несовместима с unprivileged LXC substrate. Решение о swap'е CNI
  (новый wrapper chart) — отдельный дизайн-step, после честного
  анализа root cause, а не автоматический fallback без понимания
  почему Calico не поехал. Unprivileged LXC substrate остаётся
  зафиксированным; CNI — переменная величина;
* поэтому для `v1.0` приоритет такой:
  * сначала сохранить host-level isolation через unprivileged LXC,
  * затем использовать Calico как target CNI,
  * Gate B проходит — план выполнен; не проходит — stop, root-cause
    анализ + замена wrapper chart'а в отдельном step'е.

## Substrate предусловие — `capi-worker` / `capi-controlplane` cloud-init

Для того чтобы gate Helm test'ы в Phase 5.2/5.3 вообще имели работающий
eth1 на worker-нод'ах — external nic должен быть сконфигурирован
**до первого Helm install'а**. В production-path этим владеет CAPN
cloud-init; в рамках этого repo substrate-baseline задаётся на уровне
LXD-профилей:

* `capi-worker` и `capi-controlplane` профили (§13.6 extended spec)
  несут `cloud-init.vendor-data` ключ в substrate-required конфиге
  (`vars/main.yml`);
* vendor-data содержит systemd-networkd drop-in для eth1
  (`IPv6AcceptRA=yes`, `LinkLocalAddressing=ipv6`) + sysctl.d файл с
  kernel knob'ами (`disable_ipv6=0`, `accept_ra=2`, `accept_ra_defrtr=1`);
* `vendor-data` (а не `user-data`) выбран намеренно: CAPN на Phase 5+
  ставит собственный `cloud-init.user-data` на instance-level для
  kubeadm bootstrap, и LXD replaces (не merges) user-data на
  instance-level. `vendor-data` — отдельный cloud-init slot, который
  cloud-init применяет **вместе** с user-data из любого источника;
* любой инстанс, созданный с этим профилем — CAPN'ом через Machine
  template, оператором руками через `lxc launch`, Helm test probe
  Job'ом в cluster'е — получает идентичную baseline-конфигурацию
  eth1 на first boot через cloud-init;
* consumer `k8s_lab_images_controlplane` / `k8s_lab_images_worker`
  **обязан** быть cloud-init-capable (CAPN-prebuilt `capi:kubeadm/*`
  образы это уже обеспечивают, см. §8a).

Это закрывает «кто настраивает eth1 на эфимерных worker'ах» без
Ansible-mutation внутри контейнера: профиль, привязанный к инстансу
при создании, — производственный mechanism, работающий одинаково для
gate-теста и реального worker'а.

---

# 7. Репозиторий

```text
repo/
  Makefile
  README.md

  ansible/
    ansible.cfg
    roles/
      base_system/
      binary_fetch/
      lxd_host/
      lxd_project/
      lxd_storage_pools/
      lxd_network_int_managed/
      lxd_profiles/
      lxd_bootstrap_instance/
      bootstrap_k3s/
      bootstrap_clusterctl/
      bootstrap_capn_secret/
      pivot_clusterctl_move/
      cleanup_bootstrap/
      export_artifacts/

  clusterctl/
    clusterctl.yaml

  charts/
    capi-cluster-class/    # §16.2 ClusterClass + Kubeadm*/LXC* templates
    capi-workload-cluster/ # §16.3 Cluster CR instance
    cni-calico/            # §17.1 wrapper over projectcalico/tigera-operator (shipped CNI)
    metallb-config/        # §17.1 MetalLB IPAddressPool + L2Advertisement
    cni-probe/             # §17.3/§17.5 Helm test hook Job — Gate B (CNI viability)
    metallb-probe/         # §17.3/§17.6 Helm test hook Job — Gate A (external L2)

  terraform/
    modules/
      capi_cluster_class/
      capi_workload_cluster/
      cluster_addons_helm/

  tests/
    molecule/
      Makefile
      shared/
        converge.yml
        verify.yml
        vars/
        tasks/
          prepare.yml
          wait-services.yml
      # scenario directory names are kebab-case (Molecule / Make target
      # convention) — they reference the snake_case Ansible role via
      # `_shared_target_role` inside molecule.yml; see §2.6.3.
      base-system/
      binary-fetch/
      lxd-host/
      lxd-project/
      lxd-storage-pools/
      lxd-network-int-managed/
      lxd-profiles/
      lxd-bootstrap-instance/
      bootstrap-k3s/
      bootstrap-clusterctl/
      bootstrap-capn-secret/
      export-artifacts/
      cleanup-bootstrap/
      pivot/
      e2e-local/
    fixtures/
      terraform/
        workload-clusters/
          lab-default/
            capi/
              main.tf
              variables.tf
              providers.tf
              outputs.tf
            addons/
              main.tf
              variables.tf
              providers.tf
              outputs.tf
    vagrant/
      debian13/
        Vagrantfile
        inventory.sh
        libvirt-networks/
          mgmt-nat.xml
          probe-ext6.xml  # dormant, K8SLAB_PROBE=1 gated

  scripts/
    render_kubeconfig.py
    export_bootstrap_facts.py
    wait_for_cluster.sh
    molecule_create.sh
    molecule_destroy.sh

  .artifacts/
    .gitkeep
```

Принципиально:

* в repo **нет** `inventories/prod`, `inventories/local` и top-level deploy playbooks для реальных окружений;
* в repo **нет** environment root modules под конкретные площадки;
* `tests/fixtures/terraform/*` существуют только как **test consumers** для локального e2e и проверки module contract;
* `tests/molecule/*` — это общий repo-level harness, но по operational style он должен повторять лучшие практики `naive_proxy`: shared prepare/verify logic, унифицированный wrapper `Makefile`, явные workarounds для `molecule + vagrant-libvirt`;
* `tests/fixtures/*` не содержат отдельную implementation logic, а только вызывают reusable роли/модули с synthetic inputs;
* каждая роль должна иметь собственный `README.md`, `defaults/main.yml`, dispatcher `tasks/main.yml` и split task files по крупным подтемам;
* **все Kubernetes-объекты доставляются через Helm** (§2.9). `charts/`
  — единственный source of truth для CR-контента, применяется только
  Terraform `helm_release`-ом. `manifests/`-директории как отдельного
  ownership-слоя нет; raw YAML под apply, `kubectl apply -f`,
  `kubernetes_manifest`, `kubernetes.core.k8s state=present` —
  запрещены для create/update;
* **Makefile — единственный entry point** для всех orchestration-
  операций (правило `feedback_makefile_only.md`). Phase 0..4
  тестируются через Molecule-сценарии (`make -C tests/molecule
  <scenario>-delegated-test`), Phase 5+ проигрываются через TF-
  target'ы корневого Makefile'а (`make deploy-workload-capi`,
  `make deploy-workload-addons`, §16.7 / §17.4). Terraform предполагается
  уже установленным на runner'е; Ansible его не ставит. `vagrant` /
  `virsh` / `molecule` / `terraform` напрямую не вызываются;
* боевые consumer repos должны сами собирать inventories/playbooks/root modules вокруг этих roles/modules.

Ansible roles — стандартная reusable единица для orchestration; Terraform modules — standard reusable composition unit; Molecule delegated driver позволяет самим управлять lifecycle VM через Vagrant/libvirt. ([ansible.readthedocs.io][14])

---

# 8. Типизированный контракт переменных

Ниже — основное. В коде это должно лечь в `defaults/main.yml` и `variables.tf`.

Это именно **public interface contract** reusable ролей и модулей.

* test fixtures внутри этого repo могут использовать synthetic values;
* concrete values для реальных окружений, secrets, overlays и tfvars должны задаваться в отдельных private consumer repos.

Naming rule (memory `feedback_global_var_prefix.md`, 2026-04-23):
every project-wide global carries the `k8s_lab_` prefix. Role-scoped
variables keep their `<role_name>_*` prefix per §2.6.2. There is no
third naming category — naked globals like `opt_root` or
`api_publish_port` are banned because they collide silently with
unrelated vars inherited from wider inventory.

Variables are grouped below by logical section for readability
(these are NOT namespaces in Ansible — the `_section_` fragment is
part of the flat variable name; `k8s_lab_storage_pool_name` is a
single identifier, not `k8s_lab.storage.pool_name`).

```yaml
# ---- global ----
k8s_lab_opt_root: {type: string, default: "/opt/capi-lab"}
k8s_lab_project_name: {type: string, default: "capi-lab"}
k8s_lab_pivot_enabled: {type: bool, default: false}

# ---- capi ----
k8s_lab_infrastructure_secret_name: {type: string, default: "incus-identity"}  # matches CAPN upstream identity-secret default name
k8s_lab_cluster_topology_enabled: {type: bool, default: true}
k8s_lab_unprivileged_nodes: {type: bool, default: true}

# ---- host ----
k8s_lab_host_distro: {type: string, default: "debian-13"}
# lxd_host_* inputs are consumed by role lxd_host (plan §13.2) and
# already carry the role prefix — they are NOT globals and therefore
# do NOT take a k8s_lab_ prefix.
lxd_host_snap_channel: {type: string, default: "6/stable"}          # verified 2026-04-21; plan §2.11 — newest feature-stable track
lxd_host_snap_refresh_mode: {type: string, default: "hold"}         # hold|timer
lxd_host_snap_refresh_timer: {type: string, default: "fri,03:00-04:00"}

# ---- storage ----
k8s_lab_storage_pool_name: {type: string, default: "capi-fast"}
k8s_lab_storage_driver: {type: string, default: "btrfs"}
# `source` это путь к блочному устройству (/dev/disk/by-id/...),
# а не к mounted filesystem. LXD snap AppArmor-confined и не имеет
# доступа к произвольным host-путям вне /var/snap/lxd/common/.
# Для btrfs-driver'а LXD форматирует устройство через mkfs.btrfs
# без -f, поэтому device должен быть signature-free на первый
# converge — см. §13.4 implementation notes.
k8s_lab_storage_source: {type: string, required: true}
k8s_lab_storage_btrfs_mount_options: {type: string, default: "user_subvol_rm_allowed"}

# ---- networking ----
k8s_lab_uplink_interface: {type: string, required: true}
k8s_lab_external_bridge_name: {type: string, default: "br-ext6"}
k8s_lab_internal_network_name: {type: string, default: "capi-int"}
k8s_lab_internal_ipv4_subnet: {type: string, default: "10.77.0.0/24"}
k8s_lab_internal_ipv6_subnet: {type: string, default: "fd42:77:1::/64"}
k8s_lab_internal_ipv4_nat: {type: bool, default: true}
k8s_lab_internal_ipv6_nat: {type: bool, default: true}
k8s_lab_external_ipv6_prefix: {type: string, required: true}
k8s_lab_external_node_ipv6_range: {type: string, required: true}
k8s_lab_external_probe_address: {type: string, required: true}   # IPv6 внутри external prefix — потребляет MetalLB Helm test hook §17.6
k8s_lab_metallb_vip_range_v6: {type: string, required: true}
k8s_lab_guest_internal_ifname: {type: string, default: "eth0"}
k8s_lab_guest_external_ifname: {type: string, default: "eth1"}
k8s_lab_external_ra_accept: {type: bool, default: true}
k8s_lab_external_ra_use_gateway: {type: bool, default: false}
k8s_lab_guest_network_backend: {type: string, default: "systemd-networkd"}

# ---- bootstrap ----
k8s_lab_bootstrap_instance_name: {type: string, default: "capi-bootstrap-0"}
# Defaults track current upstream stable per plan §2.11; every bump
# records its verification date inline next to the pin. See §8a.
k8s_lab_k3s_version: {type: string, default: "v1.35.3+k3s1"}         # verified 2026-04-21
k8s_lab_kubectl_version: {type: string, default: "v1.35.3"}          # verified 2026-04-21
k8s_lab_clusterctl_version: {type: string, default: "v1.12.5"}       # verified 2026-04-21
k8s_lab_capn_provider_version: {type: string, default: "v0.8.5"}     # verified 2026-04-21
# Внешняя публикация bootstrap API cluster'а, если нужна, делается
# через LXD proxy device на инстансе bootstrap LXC — см. §15.5 + role
# lxd_bootstrap_instance (parameter `lxd_bootstrap_instance_devices`).
# Отдельных глобалов для этого не заведено: listen/connect/bind
# передаются консумером в host_vars той роли, потому что это свойство
# КОНКРЕТНОГО инстанса, а не project-wide контракт. Source-IP ACL на
# хостовом файрволе в scope этого repo не входит (§11.4).

# ---- images ----
# Контракт: оба образа ОБЯЗАНЫ быть cloud-init-capable. Профили
# capi-controlplane / capi-worker несут `cloud-init.vendor-data` в
# substrate-required config (§13.6), который задаёт eth1 RA reception
# на каждом инстансе. Vendor-data (slot отдельный от user-data)
# применяется cloud-init'ом вместе с CAPN'ским instance-level
# user-data (который CAPN шлёт через Machine template для kubeadm) —
# оба применяются на first boot без конфликта. CAPN-prebuilt
# `capi:kubeadm/*` образы это гарантируют; custom-образ консумера
# должен сохранять cloud-init в том же виде.
k8s_lab_images_controlplane: {type: string, default: "capi:kubeadm/VERSION"}
k8s_lab_images_worker: {type: string, default: "capi:kubeadm/VERSION"}
k8s_lab_images_source_policy: {type: string, default: "capn-prebuilt"}   # capn-prebuilt|consumer-custom
k8s_lab_images_controlplane_fingerprint: {type: string, default: ""}
k8s_lab_images_worker_fingerprint: {type: string, default: ""}

# ---- templates ----
# LXCMachineTemplate public contract (см. §16.2). Substrate-required
# baselines (`capi-base` + `capi-controlplane` / `capi-worker` из роли
# `lxd_profiles` §13.6; `instanceType: container`;
# `unprivileged: true`; `skipDefaultKubeadmProfile: true`) зашиты
# в самом чарте по memory-правилу "Chart-required values are
# hardcoded". Переменные ниже — только consumer-extras поверх baseline.
k8s_lab_controlplane_profiles_extra: {type: list(string), default: []}
k8s_lab_worker_profiles_extra: {type: list(string), default: []}
# Devices accepted в CAPN v1alpha2 []string CSV формате, например
# `"eth1,type=nic,network=br-ext6"` — это overrides поверх LXD
# profile'ов, не замена им.
k8s_lab_controlplane_devices_extra: {type: list(string), default: []}
k8s_lab_worker_devices_extra: {type: list(string), default: []}
k8s_lab_idmap_isolated: {type: bool, default: true}
k8s_lab_network_files_strategy: {type: string, default: "cabpk-files"}
k8s_lab_patch_delivery_strategy: {type: string, default: "cabpk-files-plus-patches"}

# ---- cni ----
# Default workload CNI = Calico. Shipped в repo единственной
# wrapper-реализацией (`charts/cni-calico/`), потребляется §17.1
# module'ем через явный `cni_chart_path` input в fixture. Swap на
# другую CNI-реализацию (Cilium, kube-router, etc.) — добавить новый
# wrapper chart в `charts/cni-<whatever>/`, поменять `cni_chart_path`
# в fixture'е (§17.1 Extensibility); toggle-переменной в §8 нет по
# дизайну — однократный дизайн-решение, а не runtime-flag.
# Privileged LXC как workaround CNI-проблем запрещён (§2.8).

# ---- addons ----
# Defaults track current upstream stable per plan §2.11. Verification
# dates inline — §8a below compiles a single table. Только shipped
# upstream-зависимости перечислены; CNI wrapper chart path — §17.1
# input без §8 селектора, pin upstream-версии внутри chart'а
# `charts/cni-calico/Chart.yaml` (k8s_lab_calico_chart_version — pin
# зависимости в `Chart.yaml` wrapper'а).
k8s_lab_helm_provider_version: {type: string, default: "3.1.1"}                                           # verified 2026-04-21
k8s_lab_calico_chart_repository: {type: string, default: "https://docs.tigera.io/calico/charts"}
k8s_lab_calico_chart_name: {type: string, default: "tigera-operator"}
k8s_lab_calico_chart_version: {type: string, default: "v3.31.5"}                                          # verified 2026-04-21
k8s_lab_metallb_chart_repository: {type: string, default: "https://metallb.github.io/metallb"}
k8s_lab_metallb_chart_name: {type: string, default: "metallb"}
k8s_lab_metallb_chart_version: {type: string, default: "0.15.3"}                                          # verified 2026-04-21
k8s_lab_kube_proxy_nodeport_addresses: {type: list(string), default: []}  # derive from external IPv6 policy if empty
k8s_lab_metallb_enabled: {type: bool, default: true}
k8s_lab_metallb_interface: {type: string, default: "eth1"}
k8s_lab_metallb_node_selector_labels: {type: map(string), default: {}}
k8s_lab_metallb_wrapper_chart_path: {type: string, default: "charts/metallb-config"}

# ---- clusters ----
k8s_lab_management_cluster_name: {type: string, default: "mgmt-1"}
k8s_lab_workload_cluster_name: {type: string, default: "lab-default"}
# Workload/mgmt Kubernetes version. NOT a free-form "latest upstream
# stable" pick (memory rule §2.11) — CAPN consumes prebuilt LXC images
# from `https://images.linuxcontainers.org/capn/`, and that
# simplestreams server publishes only a curated subset (typically the
# `.0` of each minor + occasional patches). Workload Cluster CRs that
# request a version absent from simplestreams fail at LXCMachine
# provisioning time with `Failed getting image: The requested image
# couldn't be found for fingerprint "kubeadm/<ver>"`.
#
# Therefore this pin tracks "latest stable kubeadm image available on
# CAPN simplestreams", verified by:
#   curl https://images.linuxcontainers.org/capn/streams/v1/images.json
# (separate from k3s/kubectl pins, which target dl.k8s.io binaries
# and have no such constraint).
k8s_lab_kubernetes_version: {type: string, default: "v1.35.0"}           # verified 2026-04-25 against CAPN simplestreams
# Topology defaults for the two CAPN-provisioned clusters.
#
# Hard CAPI invariant: kubeadm-based KubeadmControlPlane with stacked
# etcd (the only topology this repo supports — external etcd is out of
# scope for v1.0) REJECTS even controlPlane.replicas at the webhook
# level (split-brain risk under partition). Therefore CP counts MUST
# be odd: 1 (no HA), 3 (minimum HA), 5 (HA with maintenance margin).
# Workload default = 3 → real multi-CP kubeadm reconciliation +
# Calico/MetalLB failover paths get exercised in §17.x.
# Mgmt default = 1 → small footprint, add-ons + TF state live on runner
# anyway. Bumping mgmt to 3 is operator's call once Stage 2 pivot lands.
#
# Worker counts are unconstrained by the etcd quorum rule; defaults
# track v1.0 lab footprint (1 worker mgmt, 2 workers workload). All
# four counts are tunable via Terraform vars on the corresponding
# fixture roots (§16.6).
k8s_lab_management_controlplane_count: {type: int, default: 1}
k8s_lab_management_worker_count:       {type: int, default: 1}
k8s_lab_workload_controlplane_count:   {type: int, default: 3}   # CAPI invariant: must be odd
k8s_lab_workload_worker_count:         {type: int, default: 2}

# ---- CAPN identity Secret target namespaces ----
# Architectural truth (verified Step 11 against CAPN v0.8.5 controller
# behaviour): CAPN does NOT read the LXD identity Secret from its own
# controller namespace (`capn-system`). It looks the Secret up by
# `LXCCluster.spec.secretRef.name` in the **same namespace as the
# LXCCluster CR**. CAPN v1alpha2 LXCCluster.spec.secretRef has no
# `namespace` field — cross-namespace lookup is not supported.
#
# Therefore the identity Secret must live in EVERY namespace where
# workload Cluster CRs (and thus LXCCluster CRs created by the
# capi-cluster-class chart on Cluster reconcile) will be created.
# §13.11 `bootstrap_capn_secret` materialises the Secret in each
# namespace listed here; §19.x Phase 8 destroy removes it from the
# same list.
#
# Default = ["capi-clusters"] matches the workload-cluster chart's
# default Release.Namespace (§16.3). Multi-cluster scenarios (e.g.
# fleet of per-tenant Cluster CRs across namespaces) extend this list.
# The list MAY be empty for runs that do not (yet) need workload
# Cluster CRs — the role short-circuits the Secret task and only
# materialises HTTPS listener + LXD trust entry.
k8s_lab_capn_identity_namespaces: {type: list(string), default: ["capi-clusters"]}

# ---- cluster networking (dual-stack, §5) ----
# Pod / Service CIDR'ы для workload-кластера задаются dual-stack'ом
# (IPv4 + IPv6 в обоих кластерных диапазонах, §4/§5). Значения bind'ятся
# в charts/capi-cluster-class/values.yaml (spec.clusterNetwork.*) и
# charts/capi-workload-cluster/values.yaml — обе стороны должны
# совпадать, иначе kubeadm и CAPI топология рассогласуются.
# IPv4 диапазоны — ULA-style стандартные (k3s defaults-compatible);
# IPv6 — ULA из `fd42:77::/48` family, consistent c §8
# k8s_lab_internal_ipv6_subnet naming.
k8s_lab_workload_pod_cidr_v4:     {type: string, default: "10.244.0.0/16"}
k8s_lab_workload_pod_cidr_v6:     {type: string, default: "fd42:77:2::/56"}
k8s_lab_workload_service_cidr_v4: {type: string, default: "10.96.0.0/16"}
k8s_lab_workload_service_cidr_v6: {type: string, default: "fd42:77:3::/112"}

# ---- helm charts (local, этого репо) ----
# Версии локальных chart'ов pinned; bump версии = новое имя
# ClusterClass/*Template через name-versioning pattern (§2.9).
k8s_lab_capi_cluster_class_chart_version:    {type: string, default: "0.4.2"}
k8s_lab_capi_workload_cluster_chart_version: {type: string, default: "0.4.2"}
```

## 8a. Verified version log

Per §2.11, каждый pin внешней зависимости фиксируется с датой
проверки upstream. Таблица компилируется из inline-комментариев в §8;
если inline-дата расходится с таблицей — inline источник истины, а
таблицу надо пересобрать при следующем review.

| Компонент | Версия | Где используется | Дата проверки |
| --- | --- | --- | --- |
| Kubernetes (workload/mgmt) | `v1.35.0` | `k8s_lab_kubernetes_version` | 2026-04-25 |
| k3s (bootstrap) | `v1.35.3+k3s1` | `k8s_lab_k3s_version` | 2026-04-21 |
| kubectl | `v1.35.3` | `k8s_lab_kubectl_version` | 2026-04-21 |
| Cluster API (clusterctl) | `v1.12.5` | `k8s_lab_clusterctl_version` | 2026-04-21 |
| CAPN | `v0.8.5` | `k8s_lab_capn_provider_version` | 2026-04-21 |
| LXD snap channel | `6/stable` | `lxd_host_snap_channel` | 2026-04-21 |
| Calico (tigera-operator) chart | `v3.31.5` | `k8s_lab_calico_chart_version` | 2026-04-21 |
| MetalLB chart | `0.15.3` | `k8s_lab_metallb_chart_version` | 2026-04-21 |
| Terraform helm provider | `3.1.1` | `k8s_lab_helm_provider_version` | 2026-04-21 |
| ansible.posix collection | `>=2.1.0` | `ansible/requirements.yml` | 2026-04-21 |
| community.general collection | `>=12.6.0` | `ansible/requirements.yml` | 2026-04-21 |
| community.crypto collection | `>=3.2.0` | `ansible/requirements.yml` | 2026-04-21 |
| kubernetes.core collection | `>=6.0.0` (resolved 6.4.0) | `ansible/requirements.yml` | 2026-04-23 |
| python3-kubernetes (Debian Trixie) | `30.1.0-2` | `tests/molecule/shared/tasks/prepare.yml` | 2026-04-23 |

Deviation (зафиксировано в Step 1, актуально на 2026-04-22):
Canonical рекомендует LXD LTS `5.21/stable` для production; мы
трактуем §2.11 «latest stable» буквально и ставим feature-stable
track `6/stable`. Trade-off: риск регрессий выше, CAPN не заявил
явную совместимость с LXD 6.x. Если на Gate B или раньше всплывёт
несовместимость — даунгрейдимся на `5.21/stable` и фиксируем это в
логе изменений плана.

Constraint (зафиксировано Step 11, 2026-04-25): `k8s_lab_kubernetes_version`
ограничен набором prebuilt `capi:kubeadm/<ver>` images, опубликованных
на upstream CAPN simplestreams (`https://images.linuxcontainers.org/capn/`).
Сервер минтит образы только под выбранные релизы (типично `<minor>.0`
плюс редкие patch'и) — попытка задать `kubernetes.version` для
которой нет образа упирается в CAPN runtime ошибку
`Failed getting image: The requested image couldn't be found for
fingerprint "kubeadm/<ver>"` уже на стадии создания первого
LXCMachine. По состоянию на 2026-04-25 simplestreams отдаёт
`kubeadm/v1.33.0`, `kubeadm/v1.33.5`, `kubeadm/v1.34.0`,
`kubeadm/v1.35.0` (и их `/ubuntu`-варианты). `v1.35.0` — latest
актуальный для нашего pin'а; upstream `dl.k8s.io/release/stable.txt`
показывает свежее (`v1.35.4`/`v1.36.0`), но для этого репо они
нерелевантны до момента, когда CAPN опубликует matching образ. Pin
обновляется только после re-проверки `streams/v1/images.json`.

---

# 9. Локальная разработка и тестирование

## 9.1. Базовый локальный контур

Runner — локальная Linux машина разработчика.

Локально поднимается **одна Debian 13 VM через Vagrant + libvirt**, которая имитирует target Debian host. Vagrant-libvirt is a Vagrant plugin that adds a Libvirt provider and supports the normal `up`, `destroy`, `provision`, `ssh`, `reload` lifecycle. ([vagrant-libvirt.github.io][22])

Molecule используется в **delegated mode**: разработчик сам реализует `create`/`destroy`, а Molecule отвечает за `prepare/converge/idempotence/verify`. Delegated is the default driver in Molecule and explicitly expects developer-supplied create/destroy logic. ([ansible.readthedocs.io][14])

Для текущего repo это **основной и обязательный способ верификации**. Проверка реальных окружений и wiring consumer configuration сюда не входят.
`tests/fixtures/*` при этом остаются thin wrapper layer и не должны содержать альтернативную implementation logic.
Local pass не заменяет consumer-side validation на реальном external segment.

Operational style локального harness тоже фиксируется заранее:

* repo-level `tests/molecule/Makefile` должен давать унифицированные targets вида `<scenario>-<driver>-<action>`;
* даже если у сценария пока один driver, имя driver остаётся в target для стабильной схемы вызова;
* допускается и ожидается явная прокладка environment quirks для `molecule + vagrant-libvirt`, а не надежда на “магическое” autodiscovery.

## 9.2. Как смоделировать второй интерфейс и IPv6 /64

> **Step 9 (2026-04-24) pivot.** Раздел ниже описывает оригинальный
> Step 1 design через libvirt `ext6-mock` network. Он **не сработал**:
> libvirt не включил RA в dnsmasq, `tcpdump` на `br-ext6` 0 пакетов.
> Текущая архитектура — RA source внутри Vagrant VM через veth-пару
> `ext6-ra` ↔ `ext6-ra-peer` + radvd; libvirt-сторона упрощена до
> единственного NIC `k8slab-mgmt-nat`. Детали и rationale — в секции
> "Step 9 pivot: RA source переехал внутрь VM" ниже. Оригинальный
> текст §9.2 оставлен как историческая справка по попыткам Step 1.

Это теперь обязательное требование.

### Локальная схема libvirt

Нужно создать **две libvirt network**:

1. **`mgmt-nat`** — обычная management/SSH сеть до test VM.
2. **`ext6-mock`** — отдельная IPv6-сеть, которая эмулирует “провайдерский внешний сегмент”.

`ext6-mock` должен быть определён через libvirt network XML так, чтобы он:

* был отдельным L2 сегментом для второго интерфейса test VM;
* поднимал IPv6 `/64`;
* выдавал IPv6 через встроенный DHCPv6/RA;
* по возможности не смешивался с management NAT сетью.

Libvirt network XML officially supports:

* IPv6 addressing on virtual networks,
* DHCPv6 ranges,
* Router Advertisement for IPv6 default route,
* isolated and NAT networks,
* bridge mode using an existing host bridge. It also documents that for IPv6 the default route is established via Router Advertisement. ([Libvirt][23])

### Практический local design

Для `ext6-mock` в local lab рекомендую:

* **isolated IPv6 network** или **NAT network with IPv6 enabled**, но без зависимости от внешнего реального провайдера;
* address, например:

  * `2001:db8:42:100::1/64`
* DHCPv6 range внутри этого /64.

Пример идеи XML:

```xml
<network ipv6='yes'>
  <name>ext6-mock</name>
  <bridge name='virbr-ext6'/>
  <ip family='ipv6' address='2001:db8:42:100::1' prefix='64'>
    <dhcp>
      <range start='2001:db8:42:100::100' end='2001:db8:42:100::1ff'/>
    </dhcp>
  </ip>
</network>
```

Это даст вам **mocked RA/DHCPv6 /64**, который увидит второй NIC Debian test VM. Затем уже **внутри самой VM** роль `lxd_host` создаст host-side bridge `br-ext6` и привяжет к нему этот второй NIC так, как это будет требоваться consumer-окружению. ([Libvirt][23])

### Deviations зафиксированные в Step 1

* **Реально используемые имена libvirt networks:** `k8slab-mgmt-nat`
  и (на Step 1) `k8slab-ext6-mock` / `k8slab-probe-ext6` (префикс
  `k8slab-`, чтобы не конфликтовать с пользовательскими сетями в
  default-namespace libvirt). Название `ext6-mock` / `mgmt-nat` выше
  — логическое обозначение в тексте плана.
* **Имена host-bridge'ей libvirt-сетей ≤15 chars (Linux IFNAMSIZ).**
  Изначальные `virbr-k8slab-mgmt` (17 chars) и `virbr-k8slab-ext6`
  (17 chars) падают с "error creating bridge interface: Numerical
  result out of range". Используем `k8slab-mgmt`, `k8slab-ext6`,
  `k8slab-probe` (все ≤12). XML-комментарии объясняют ограничение
  для будущих правок.
* **`ext6-mock` XML — dual-stack isolated** (не pure-IPv6).
  vagrant-libvirt `private_network` плагин падает на чистых
  IPv6-сетях (`undefined method 'to_range' for nil`, плагин пытается
  посчитать DHCPv4 range). Workaround: в XML добавлен минимальный
  RFC 5737 TEST-NET-1 `192.0.2.0/30` — трафика не несёт, нужен только
  чтобы плагин дошёл до конца `private_network` validation.
  Внешний ingress и MetalLB VIP всё равно остаются IPv6-only
  (политика аллокации, а не ограничение L2 сегмента). Сеть
  **isolated** (без `<forward/>`), чтобы RA/NDP/multiple-MAC сигналы
  не смешивались с IPv4-трафиком mgmt-сети.
* **IPv6-only NIC в Vagrantfile — `type: "dhcp"`**. vagrant-libvirt
  плагин пытается auto-конфигурировать гостевой NIC и вываливается
  на сетях без IPv4 config. `type: "dhcp"` на `private_network` —
  документированный флаг плагина, который говорит «IP придёт через
  DHCP, не считай сам».

### Step 9 pivot: RA source переехал внутрь VM (2026-04-24)

**Проблема.** Libvirt-mock `k8slab-ext6-mock` серверил DHCPv6 через
dnsmasq, но **не слал Router Advertisements**: libvirt не
auto-добавляет `--enable-ra` к dnsmasq (в отличие от LXD-managed
сетей типа `capi-int`, где `dnsmasq --enable-ra --dhcp-range
::,constructor:...,ra-stateless` стартует автоматически). Проверка
ad hoc на Step 9: `rdisc6 -1 -w 3000 eth2` на Vagrant VM — нет
ответа; `tcpdump -i br-ext6 'icmp6 && (ip6[40] >= 133 && ip6[40] <= 136)'`
15 сек — 0 пакетов. Таким образом архитектурный контракт §13.6
Step 9 (container eth1 получает global IPv6 по SLAAC через RA от
external-сегмента) **никогда не мог пройти end-to-end** против
libvirt-mock — vendor-data на профиле только включал
`IPv6AcceptRA=yes`, принимать было нечего.

**Решение.** RA source переехал **внутрь Vagrant VM**. Новый
harness-task `tests/molecule/shared/tasks/ext6-ra-source.yml`
(подключён через `tests/molecule/shared/tasks/prepare.yml` →
применяется в prepare каждого сценария) создаёт:

* veth-пару `ext6-ra` ↔ `ext6-ra-peer` через systemd-networkd
  `.netdev` с `Kind=veth` + `[Peer]` блоком;
* `ext6-ra` enslave'ится в `br-ext6` через тот самый
  `30-br-ext6-uplink.network` production-роли `lxd_host` (в
  shared host_vars pin `lxd_host_ext_bridge_uplink: ext6-ra`);
* `ext6-ra-peer` получает global IPv6 `2001:db8:42:100::1/64`;
* `radvd` слушает на `ext6-ra-peer` и шлёт RA для
  `2001:db8:42:100::/64` (`AdvSendAdvert on`, `AdvAutonomous on`,
  `AdvOnLink on`).

RA multicast, отправленный radvd на `ext6-ra-peer`, идёт через
veth на `ext6-ra`, flood'ится bridge'ом `br-ext6` на все порты,
включая `eth1` любого контейнера, привязанного через
`capi-worker` / `capi-controlplane` профили с `nictype=bridged
parent=br-ext6`. Внутри контейнера cloud-init vendor-data уже
включил `IPv6AcceptRA=yes` → systemd-networkd SLAAC'ит global IPv6
в префиксе.

**Что удалено из Vagrant/libvirt-схемы:**

* `tests/vagrant/debian13/libvirt-networks/ext6-mock.xml` (не слал
  RA, был workaround'ом для проблемы, которую так и не решал);
* второй `private_network` блок в Vagrantfile (был eth2, тянул в
  VM dormant-интерфейс без carrier);
* `k8slab-ext6-mock` в `Makefile NETS` и в `network_xmls` в
  Vagrantfile;
* `synced_folder "/vagrant"` уехал в `disabled: true` — NFS export
  требовал interactive sudo на хосте и ломал `make up`. Никакие
  скрипты на VM `/vagrant` всё равно не читают (Ansible рулит по
  SSH).

`k8slab-probe-ext6` libvirt-сеть и probe VM (`K8SLAB_PROBE=1`
gated) оставлены dormant — они потребуют отдельного редизайна для
работы с in-VM RA архитектурой, scope за рамками Step 9.

**End-to-end доказательство (Step 9 manual test):** поднято два
контейнера `capi-test-worker-0` + `capi-test-cp-0` из
`images:debian/13/cloud` с профайлами `capi-base + capi-worker` и
`capi-base + capi-controlplane` соответственно. После cloud-init
`status: done`:

* `/etc/sysctl.d/99-capi-ra.conf` — byte-match с rendered
  template;
* `/etc/systemd/network/30-capi-ext.network` — byte-match;
* `ip -6 -br addr show dev eth1` — global IPv6 в
  `2001:db8:42:100::/64` (EUI-64 от MAC контейнера);
* `ip -6 route show default` — default route
  `via fe80::<ext6-ra-peer LLA> dev eth1 proto ra`.

Runtime `net.ipv6.conf.eth1.accept_ra = 0` — ожидаемое поведение
systemd-networkd (при `IPv6AcceptRA=yes` он обрабатывает RA в
user-space через Nettle, kernel sysctl держит 0 чтобы не
дублировать); global IPv6 на интерфейсе — прямое доказательство,
что RA принимаются, просто через другой codepath.

**Побочное (не Step 9 scope):** default route сейчас
дублируется — и на eth1 (наш harness radvd), и на eth0
(LXD-managed `capi-int` dnsmasq с `ra-stateless` тоже шлёт
`default via me`). Production §5.3 Guest-side route policy
требует egress **только через eth1**. Отдельный долг будущей
итерации (вероятно, `lxd_network_int_managed` — выключить
default-advert на internal-bridge dnsmasq).

## 9.3. Как проверить внешний ingress локально

Для полноценного e2e test нужен ещё **probe endpoint** на том же
external L2 сегменте (после Step 9 pivot — это bridge `br-ext6` внутри
Vagrant VM, не libvirt-сеть):

* либо отдельная probe VM, подключённая в `br-ext6` через veth из
  хоста (аналог `k8slab-probe-ext6` в Step 1 design — потребует
  редизайна под новую архитектуру);
* либо отдельный netns внутри Vagrant VM, привязанный к `br-ext6`
  через вторую veth-пару;
* либо сам `ext6-ra-peer` (Step 9 harness RA source) — у него уже
  есть global IPv6 в префиксе и он видит bridge, минимальная
  установка для dev-scope probe.

Он будет играть роль “внешнего клиента” для проверки:

* внешнего IPv6 reachability нód;
* NodePort;
* MetalLB VIP;
* NDP/failover.

## 9.4. Что должно тестироваться в Molecule

### Role-level

Минимально обязательные отдельные scenarios:

* `base_system`
* `binary_fetch`
* `lxd_host`
* `lxd_project`
* `lxd_storage_pools`
* `lxd_network_int_managed`
* `lxd_profiles`
* `lxd_bootstrap_instance`
* `bootstrap_k3s`
* `bootstrap_clusterctl` — Step 6 §13.10. Прогон scenario поднимает
  всю Phase 0..3.5 цепочку через meta-deps + сам bootstrap_k3s, затем
  применяет bootstrap_clusterctl converge → idempotence → verify.
  Verify ассертит host kubeconfig (mode 0600, server URL переписан с
  127.0.0.1 на capi-int IP), kubectl Ready node через kubeconfig, 7
  Deployments (cert-manager + 4 CAPI/CAPN) Available, 4 ProviderCR-
  пары через `kubernetes.core.k8s_info`, ClusterTopology=true в
  capi-controller-manager args.
* `bootstrap_capn_secret` — Step 6 §13.11. Прогон scenario поднимает
  Phase 0..4-частично цепочку через meta-deps (включая
  bootstrap_clusterctl), затем применяет роль и verify-ит: LXD
  `core.https_address` bound на capi-int subnet, ровно один client
  cert в trust store с restricted=true + projects=[capi-lab], Secret
  с 5 правильными data keys (server URL = `https://10.77.x.x:8443`,
  project=capi-lab, корректные PEM bodies), `server-crt` byte-equal
  с live `/var/snap/lxd/common/lxd/server.crt`, отсутствие pivot
  label при `k8s_lab_pivot_enabled=false` (default).
* `export_artifacts` — Step 8 §13.12 (Molecule-цикл ещё не прогон).
  Прогон поднимает всю Phase 4 цепочку через meta-deps (включая
  bootstrap_capn_secret), затем применяет роль и verify-ит
  runner-side: `.artifacts/bootstrap.kubeconfig` + `.auto.tfvars.json`
  present с mode 0600, kubeconfig server не 127.0.0.1,
  tfvars содержит baseline `k8s_lab_*` ключи, API server URL в
  tfvars совпадает с cluster[].server в shipped kubeconfig,
  `kubernetes.core.k8s_info kind=Node` через shipped kubeconfig
  видит Ready ноду (Phase 5 smoke-тест).

### Integration-level

* `bootstrap_cluster`
* `cluster_addons_helm` — помимо проверки факта установки Helm
  releases, отвечает за прогон **Helm test hooks** (§6, §17.3),
  реализующих Gate A (§17.6, external L2) и Gate B (§17.5, CNI
  viability). Также ассертит **HA pair contract §2.12** для каждого
  workload-cluster компонента с `replicas >= 2`:
  * `kubectl get deploy <X> -o jsonpath='{.status.readyReplicas}'`
    и `availableReplicas` равны `.status.replicas`
    (condition=Available недостаточен — см. §2.12 Test contract);
  * `kubectl get pods -l <selector> -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l`
    == 2 (реплики на разных worker-нодах);
  * для leader-elected компонентов — ровно один holder lease,
    второй pod в standby (механизм проверяется по типу компонента:
    логи, lease object, leader-election config map — см. §2.12).
* `pivot` (optional)

### Full E2E

* `e2e_local` — полный путь, включая повторение HA pair assertions
  §2.12 на финальном workload cluster после pivot (если
  `k8s_lab_pivot_enabled=true`). **Статус: первая итерация
  выполнена в Step 12 (2026-04-26)** — covers Phase 0..5
  (substrate → bootstrap k3s → CAPI ClusterClass + workload
  Cluster) на одной VM. `converge.yml` инклюдит роль
  `export_artifacts` (вся Phase 0..4 цепочка через её meta-deps)
  и устанавливает оба chart'а через `kubernetes.core.helm`;
  `verify.yml` гоняет `helm test` workload chart'а (10-фазная
  dual-stack acceptance драйвер из §16.3), снимает CAPI
  snapshot через `kubernetes.core.k8s_info`, материализует
  workload kubeconfig из bootstrap Secret через `k8s_info` +
  `ansible.builtin.copy`, и снимает `kubectl get nodes` с
  workload-стороны через короткоживущий Pod в bootstrap
  cluster'е (`kubernetes.core.k8s` → `k8s_info` polling →
  `k8s_log` → `k8s state: absent`); workload API endpoint
  живёт на LXD-bridge IPv6, недоступном с runner'а, поэтому
  in-cluster jump-pod единственный путь. Единственный shell
  fallback — `helm test` (нет нативного эквивалента в
  `kubernetes.core`). Расширения сценария на Phase 5.1+ (CNI
  + add-ons + pivot + HA pair assertions §2.12) — последующие
  Step'ы.

### Molecule harness style contract

Для этого repo Molecule/Vagrant/libvirt harness должен следовать практическому стилю `naive_proxy`, адаптированному к multi-role repo:

* общий wrapper `Makefile` в `tests/molecule/` обязан предоставлять targets по схеме `<scenario>-<driver>-<action>`;
* harness **никогда не вызывается напрямую** (`vagrant`, `virsh`,
  `molecule`, `ansible-playbook`) — только через Makefile entry
  points (§10). Исключение — read-only диагностика (`vagrant status`,
  `virsh net-list`). Обоснование в памяти
  `feedback_makefile_only.md`.
* общие `converge.yml`, `verify.yml` helper и tasks выносятся в
  `tests/molecule/shared/`, чтобы role-level и integration-level
  scenarios не дублировали boilerplate;
* **substrate host_vars живут в едином shared group_vars файле**
  (`tests/molecule/shared/inventory/group_vars/k8slab_host.yml`) и
  распространяются через `inventory.links.group_vars` в каждом
  `molecule.yml` — полная архитектура и rationale в §9.5;
* scenario-local overrides живут в real inventory файле
  `<scenario>/host_vars/k8slab-host.yml` + `inventory.links.host_vars:
  host_vars` в `molecule.yml` (см. §9.5.2 — `inventory.host_vars` в
  `molecule.yml` молча теряется при наличии `links`);
* **target role для shared converge** определяется из
  `MOLECULE_SCENARIO_NAME` env var, **не** через host_vars
  `_shared_target_role` (follows from above molecule limitation);
  контракт: `scenario.name == role directory name`;
* для `vagrant-libvirt` нужно явно прокидывать `ANSIBLE_LIBRARY` из `molecule_plugins.vagrant` или эквивалентный plugin modules path, если версия Molecule не делает это сама;
* допускается `GIT_DIR=/dev/null` или эквивалентный shim, если он нужен, чтобы Molecule не ошибался режимом role/collection из-за layout этого repo;
* workarounds для driver-specific caveats должны быть зафиксированы в коде harness, а не оставлены в голове разработчика: пример — безопасное редактирование `/etc/hosts` на non-podman targets через `lineinfile`, когда atomic rename может конфликтовать с bind-mount semantics;
* `prepare` должен пользоваться native modules для установки test dependencies и загрузки test artifacts;
* `verify` обязан проверять реальные runtime outcomes: readiness, rendered configs, file ownership/mode, systemd state, сетевой data path, retries/until для асинхронных состояний;
* сценарий считается недостаточным, если он проверяет только `converge + idempotence`, но не проверяет полезное поведение роли;
* `command`/`shell` в `verify` разрешён только как явно документированное исключение, когда нужно проверить конкретный runtime path без адекватного module-equivalent.

Порядок:

1. `vagrant up`
2. host bootstrap
3. LXD substrate (включая расширенный `lxd_profiles` cloud-init
   baseline для worker/controlplane профилей — §13.6)
4. bootstrap cluster
5. apply first Terraform CAPI fixture
6. export target kubeconfig
7. apply first Terraform Helm add-ons fixture (CNI chart + MetalLB
   chart, каждый со своим Helm test hook'ом — §17.5 / §17.6 покрывают
   CNI и external L2 acceptance)
8. optional pivot / post-pivot workload create + kubeconfig export + add-ons apply
9. verify
10. destroy

## 9.5. Shared inventory architecture

**Статус: выполнено в Step 8 (2026-04-23).** До Step 8 каждый
`tests/molecule/<scenario>/molecule.yml` дублировал substrate
host_vars (uplink, storage pool spec, wait budgets, LXD proxy device,
ansible-connection env-lookup'ы, etc.), и scenario мог молча
отклониться от остальных. Step 8 инцидент (`export-artifacts`
забыл `lxd_bootstrap_instance_devices`, роль reconciliate'ила proxy
device к `{}` на converge) обнажил рой этой проблемы. Production
плейбуки так не работают — там один host_vars файл, все роли читают
одни и те же значения; harness обязан это имитировать.

### §9.5.1. Layout

```
tests/molecule/shared/inventory/
└── group_vars/
    └── k8slab_host.yml    ← весь prod-like substrate (один файл)

tests/molecule/<scenario>/
├── molecule.yml           ← только inventory.links + scenario meta
└── host_vars/             ← опционально, только если нужен
    └── k8slab-host.yml      scenario-local override
```

`shared/inventory/group_vars/k8slab_host.yml` держит:

* ansible-connection env-lookup'ы (`ansible_host/user/port/key/common_args`);
* `k8s_lab_*` globals (бывший `shared/vars/common.yml` — устранён);
* `lxd_host_ext_bridge_uplink: "eth2"`;
* `lxd_storage_pools_pools` (capi-fast btrfs на Vagrant-диске);
* `lxd_bootstrap_instance_wait_timeout`;
* `lxd_bootstrap_instance_devices.k3s-api` (LXD proxy
  `bind: host, listen: tcp:0.0.0.0:16443, connect: tcp:127.0.0.1:6443`) —
  **единственное место, где proxy device живёт**; runner-side reach
  работает для всех scenario'ев, что доходят до `capi-bootstrap-0`;
* `bootstrap_k3s_wait_retries` / `wait_delay`;
* `bootstrap_clusterctl_init_timeout` / `wait_retries` / `wait_delay`;
* `base_system_btrfs_pool_required: true` (prod-like default —
  installer provisions btrfs mount);
* `export_artifacts_root` + `export_artifacts_bootstrap_api_server_url`
  (runner-path + publish URL — derivatives of scenario env vars).

### §9.5.2. Scenario wiring

`<scenario>/molecule.yml` несёт канонически только:

```yaml
provisioner:
  inventory:
    links:
      group_vars: ../shared/inventory/group_vars
      host_vars:  host_vars         # only if scenario-local file exists
```

Target role определяется в `shared/converge.yml` через
`MOLECULE_SCENARIO_NAME` env var (молекула выставляет его перед
`ansible-playbook`). Контракт: `scenario.name` в molecule.yml
совпадает с именем директории роли под `ansible/roles/`. Всё, что
scenario добавляет — истинно scenario-local overrides, живущие в
real файле `<scenario>/host_vars/k8slab-host.yml`.

**Почему не `provisioner.inventory.host_vars` в molecule.yml.**
Molecule's `provisioner/ansible.py:442` решает all-or-nothing: если
`inventory.links` не пустой, `_add_or_update_vars` (которая
материализует `inventory.host_vars`) скипается, и содержимое молча
теряется. Поэтому scenario-local overrides нужны через real inventory
file + отдельный `links.host_vars`.

### §9.5.3. Scenario-local overrides в репе

По состоянию на Step 8 (2026-04-23) реально используются:

| Scenario | Override | Rationale |
|---|---|---|
| `binary-fetch` | `base_system_btrfs_pool_required: false` | Target role не тестирует btrfs contract; prepare не форматирует pool disk |
| `lxd-storage-pools` | `base_system_btrfs_pool_required: false` | prepare-clean-disk.yml wipe'ает pool → LXD owns disk; base_system btrfs check не применим |
| `lxd-network-int-managed` | то же | LXD уже владеет диском от предыдущих прогонов |
| `lxd-profiles` | то же | |
| `lxd-bootstrap-instance` | то же | |
| `bootstrap-k3s` | то же | |
| `bootstrap-clusterctl` | то же | |
| `bootstrap-capn-secret` | то же | |
| `export-artifacts` | то же | |

`base-system` scenario единственный тестирует контракт end-to-end с
`required: true` (наследует от shared default без override'а).

### §9.5.4. Acceptance

* shared group_vars файл — **один**; изменение substrate-ключа =
  правка ровно одного места;
* `molecule.yml` каждого scenario не превышает ~65 строк
  (scenario-local config только — driver, platforms, provisioner
  links, scenario name);
* end-to-end регрессия Step 8 (2026-04-23, pristine VM):
  все 12 готовых scenario'ев прошли full-cycle последовательно
  (create → prepare → converge → idempotence → verify → destroy).

---

# 10. One-command local workflows

В этом repo **не должно быть** `make deploy TARGET=...` или других entrypoints для реальных окружений. Их предоставляют private consumer repos.

## 10.1. Local harness smoke

```bash
make test-local-harness
```

Должно делать:

1. поднять/проверить Vagrant + libvirt test VM;
2. подготовить Molecule delegated prerequisites;
3. проверить, что Vagrant inventory/scripts/fixtures готовы к локальным сценариям.

## 10.2. Local full E2E

```bash
make test-local-e2e
```

Должно делать:

1. `vagrant up --provider=libvirt`
2. Molecule delegated create/prepare
3. host/bootstrap/substrate phases through local VM
4. apply the selected Terraform CAPI fixture path
5. export target kubeconfig artifact
6. apply the selected Terraform Helm add-ons fixture path — Helm
   test hooks на CNI и MetalLB chart'ах отрабатывают as part of
   `helm_release` lifecycle и закрывают CNI + external L2
   acceptance (§6, §17.5, §17.6)
7. optional pivot / post-pivot workload create + kubeconfig export
   + add-ons apply (если `k8s_lab_pivot_enabled=true`)
8. destroy

## 10.3. Local cleanup

```bash
make clean-local
```

Должно выполнять local destroy contract, описанный выше:

* снять test fixtures;
* убрать временные `.artifacts`;
* уничтожить Vagrant/libvirt ресурсы, созданные harness.

---

# 11. Secrets, artifacts и state

## 11.1. `.artifacts/`

Содержит:

* bootstrap kubeconfig для local tests
* target mgmt kubeconfig для local tests
* workload/target cluster kubeconfigs under `.artifacts/clusters/*.kubeconfig`
* generated tfvars handoff для test fixtures

Правила:

* `.gitignore`
* file mode `0600`
* owner = runner user

## 11.2. LXD trust material

В этом repo:

* допускаются только ephemeral/synthetic материалы для local harness;
* plaintext cert/key для реальных окружений не коммитятся;
* реальные trust materials и vault data должны жить в private consumer repos.

Для MVP local tests:

* допускается хранить encrypted test material в `ansible-vault`, если без этого нельзя воспроизвести harness;
* предпочтительно генерировать trust material на лету.

## 11.3. Terraform state

Для MVP текущего repo:

* локальный state на runner только для test fixtures
* state не считается source of truth для реальных окружений

Backend strategy для реальных окружений определяется consumer repos и не входит в этот repo.

## 11.4. Bootstrap API auth

Защита bootstrap Kubernetes API опирается на два уровня, оба находятся
В SCOPE этого repo:

* **Kubernetes API mTLS / kubeconfig** — API-server k3s всегда
  требует клиентский сертификат. `.artifacts/bootstrap.kubeconfig`
  несёт admin-cert, доступен только runner-у (mode 0600, gitignore).
* **LXD API auth** — отдельно, через restricted TLS secret
  (`capi-lab` project-scoped client cert). Реализует
  `bootstrap_capn_secret` (§15.4); подтверждён CAPN identity-secret
  format. ([capn.linuxcontainers.org][19])

**Host firewall — ВНЕ scope этого repo.** Решения:

* В проде хостовой файрвол — собственность оператора (уже настроен
  по корпоративным политикам); роль не имеет права туда писать, чтобы
  не переопределить правила окружения и не оставить дыр при
  destroy-фазе.
* Любая внешняя публикация TCP-портов bootstrap-контейнера делается
  через **LXD proxy device** типа `host` (userspace listener LXD
  daemon'а на хосте → socket внутри инстанса). Этот механизм LXD
  владеет полностью: создаётся через declarative
  `lxd_bootstrap_instance_devices` (§13.7 `lxd_bootstrap_instance`),
  удаляется при `lxc delete`, не оставляет висящих rules в
  distro-owned nftables-таблицах.
* Source-IP ACL на хостовом файрволе, если оператору нужен — это
  задача внешних ролей consumer-repo (vendor-specific firewall
  management), а не Stage 1 substrate.
* Kubernetes API mTLS + LXD restricted TLS secret — достаточная
  защита без source-IP фильтра: kubeconfig карается 0600 и не
  коммитится; LXD identity secret scope'ится на project `capi-lab`,
  даже скомпрометированный клиент не дотягивается до чужих
  инстансов.

---

# 12. Риски и mitigation

## 12.1. External L2 may fail

Mitigation:

* Phase 5.3 external L2 Helm test hook (§6 Gate A → §17.6)
  валит `terraform apply` до того, как MetalLB pretends to serve VIPs
  на нерабочем L2 сегменте; CAPN workers всё равно уже созданы но
  кластерный data plane не выпускается в production-like state до
  прохождения теста.

## 12.2. Unprivileged LXC node path may fail on userns/runtime/CNI edges

Mitigation:

* pin CAPN-tested unprivileged kubeadm image path (`v1.32.4+`)
* Phase 5.2 CNI Helm test hook (§6 Gate B → §17.5) на первом
  Terraform-created cluster после Helm add-ons pass валит
  `terraform apply` если CNI bring-up сломался
* keep unprivileged substrate fixed and vary CNI inside that constraint
* shipped CNI = Calico (`charts/cni-calico/`). Swap на другую
  реализацию при Gate B фейле — отдельный design-step (новый
  wrapper chart + правка `cni_chart_path` в fixture), не runtime-
  toggle. §17.1 module не содержит branch-логики по выбору CNI —
  extensibility через single `cni_chart_path` input
* never switch to privileged LXC as silent fallback

## 12.3. Default route may land on external NIC

Mitigation:

* systemd-networkd
* `UseGateway=no`
* route validation in verify

## 12.4. kubelet may pick wrong node IP

Mitigation:

* explicit `--node-ip`
* validate `kubectl get nodes -o wide`

## 12.5. Snap auto-refresh may destabilize LXD

Mitigation:

* snap channel pin
* hold or maintenance window

## 12.6. Stage 2 pivot adds complexity without HA gain

Mitigation:

* `k8s_lab_pivot_enabled=false` by default

## 12.7. CAPN + Canonical LXD drift risk

Mitigation:

* pin versions
* maintain compatibility matrix
* do not auto-upgrade substrate casually

## 12.8. Secrets leakage through artifacts

Mitigation:

* vault
* gitignore
* mode 0600
* no plaintext certs in repo

## 12.9. CAPN pre-built images are evaluation-oriented

Mitigation:

* local harness may use `capi:kubeadm/VERSION` images for reproducibility
* consumer repos should support custom image override and pinning
* install-kubeadm-at-runtime через `preKubeadmCommands` не становится неявным workaround path — он допустим только как осознанный выбор consumer'а, а не MVP default

## 12.10. CAPI CR immutability блокирует `helm upgrade` in place

После того как Cluster сослался на ClusterClass + `*Template`-ы, admission
webhook запрещает edit большинства их полей. Тихий `helm upgrade` с
изменёнными values падает на `admission webhook denied: field is immutable`
и оставляет release в broken-состоянии.

Mitigation:

* name-versioning pattern в обоих chart'ах §16.2 / §16.3:
  `metadata.name = "{prefix}-{slug(Chart.Version)}"`, где
  `slug = Chart.Version | replace "." "-"` для DNS-1123-safe имён;
* Cluster CR собирает rendered ClusterClass name из той же формулы
  (`spec.topology.classRef.name: "{prefix}-{class_chart_version_slug}"`),
  обе версии приходят из Terraform module'а одним знаком;
* bump chart version = новая пара объектов с новыми именами; старые
  живут до осознанного cleanup'а; zero in-place edit.

## 12.11. Webhook + CR race на первом apply'е

Cluster CR может долететь до ClusterClass-webhook'а до того, как тот
fully reconciled; результат — `failed calling webhook ... connection
refused` либо transient validation error.

Mitigation:

* `helm_release.wait = true` (default `hashicorp/helm` 3.x) на всех
  release'ах, owning CR'ы, — ждём Ready на всех resources в release'е
  до того, как return в Terraform graph;
* explicit `depends_on = [helm_release.cluster_class]` на workload-
  release'е;
* `helm_release.atomic = true` — rollback broken release чтобы не
  оставлять кластер в неконсистентном состоянии. `force_update` держим
  `false` (default), иначе SSA ownership CAPI controller'ов слетает
  (flip-flop reconciliation).

---

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
