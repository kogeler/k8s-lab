Этот файл содержит общие разделы плана, применимые ко всем stage-
специфичным документам. Здесь — project-wide contract, architecture,
networking, gates, repo layout, typed variables, test harness, local
workflows, secrets policy и risk catalog.

Нумерация §1..§23 **сквозная по всем plan-файлам** и разделена так,
чтобы каждый файл оставался атомарным по scope и перекрёстные ссылки
внутри `§<номер>` были валидными без указания имени файла:

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phase 2.5 external L2 gate)
PLAN-stage1-3.md ................. §16      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-4.md ................. §17      (Phases 5 + 5.05 Terraform CAPI + kubeconfig)
PLAN-stage1-5.md ................. §18      (Phases 5.1 + 5.2 + 5.3 Helm add-ons + CNI / MetalLB gates)
PLAN-stage1-6.md ................. §19      (Phases 6 + 7 pivot + workload clusters)
PLAN-stage1-7.md ................. §20      (Phase 8 destroy)
PLAN-stage1-8.md ................. §21..§23 (Stage 1 meta: out-of-scope, self-review, recommendation)
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
    - §2.6.1. Native-first policy
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
- §14. Выполненные phases
  - §14.1. Phase 0 — repo skeleton и local harness
  - §14.2. Phase 1 — host bootstrap
  - §14.3. Phase 2 — LXD substrate
  - §14.4. Phase 3 — bootstrap instance
  - §14.5. Phase 3.5 — `binary_fetch` (Step 4)
  - §14.6. Phase 4 — bootstrap management cluster (Step 4 partial)

### PLAN-stage1-2.md — §15 (Phase 2.5 external L2 gate)

- §15. Phase 2.5 — External L2 viability gate
  - §15.1. Role: `gate_ext_l2`
  - §15.2. Phase 2.5 execution

### PLAN-stage1-3.md — §16 (Phases 3.5 + 4 bootstrap management cluster)

- §16. Phases 3.5 + 4 — Bootstrap management cluster
  - §16.1. Role: `binary_fetch`
  - §16.2. Role: `bootstrap_k3s`
  - §16.3. Role: `bootstrap_clusterctl`
  - §16.4. Role: `bootstrap_capn_secret`
  - §16.5. Role: `bootstrap_api_publish`
  - §16.6. Role: `export_artifacts`
  - §16.7. Phase 3.5 execution
  - §16.8. Phase 4 execution

### PLAN-stage1-4.md — §17 (Phases 5 + 5.05 Terraform CAPI + kubeconfig)

- §17. Phases 5 + 5.05 — Terraform CAPI + kubeconfig export
  - §17.1. Terraform modules ownership context
  - §17.2. Module: `capi_cluster_class`
  - §17.3. Module: `capi_lxc_templates`
  - §17.4. Module: `capi_management_cluster`
  - §17.5. Module: `capi_workload_cluster`
  - §17.6. Test fixtures — CAPI
  - §17.7. Phase 5 execution
  - §17.8. Phase 5.05 execution

### PLAN-stage1-5.md — §18 (Phases 5.1 + 5.2 + 5.3 Helm add-ons + gates)

- §18. Phases 5.1 + 5.2 + 5.3 — Helm add-ons + CNI gate + MetalLB smoke
  - §18.1. Module: `cluster_addons_helm`
  - §18.2. Test fixtures — Helm add-ons
  - §18.3. Role: `gate_cni`
  - §18.4. Phase 5.1 execution
  - §18.5. Phase 5.2 execution
  - §18.6. Phase 5.3 execution

### PLAN-stage1-6.md — §19 (Phases 6 + 7 pivot + workload clusters)

- §19. Phases 6 + 7 — Optional pivot + workload cluster creation
  - §19.1. Role: `pivot_clusterctl_move`
  - §19.2. Phase 6 execution
  - §19.3. Phase 7 execution

### PLAN-stage1-7.md — §20 (Phase 8 destroy)

- §20. Phase 8 — Destroy contract
  - §20.1. Role: `cleanup_bootstrap`
  - §20.2. Phase 8 execution

### PLAN-stage1-8.md — §21..§23 (Stage 1 meta)

- §21. Stage 1 — Explicitly out of scope for v1.0
- §22. Stage 1 — Саморевью контракта
- §23. Stage 1 — Финальная рекомендация

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
  * shared manifests/templates,
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

### 2.6.1. Native-first policy

Для разработки ролей Ansible вводится жёсткое правило:

* **строго запрещено** использовать shell-скрипты, `shell`, `command`, `script` или `raw` там, где задача решается:

  * native Ansible module из `ansible.builtin`,
  * модулем из внешней Ansible collection.

Порядок выбора implementation path:

1. сначала native module;
2. затем подходящий module из внешней collection;
3. только если подходящего модуля нет или он объективно не покрывает нужное поведение, допускается fallback на shell/command/script.

Любой fallback на shell-based execution должен:

* быть явно обоснован в коде роли;
* сохранять idempotency;
* иметь корректные `changed_when`/`creates`/`removes`/`failed_when`, где это применимо;
* не подменять собой уже существующие declarative modules.

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
  1. global contract переменные без role-префикса (§8, типа
     `opt_root`, `uplink_interface`), которые являются stable
     inter-role interface;
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
* `tests/fixtures/*` не должны содержать ad hoc manifests или one-off implementation, отсутствующую в `ansible/roles`, `terraform/modules` или `manifests/`.

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

## 2.9. Политика по Terraform delivery для cluster add-ons

Все cluster add-ons и cluster-scoped Kubernetes resources в этом плане доставляются через **Helm charts**, управляемые Terraform.

Зафиксировано:

* Terraform использует `hashicorp/helm`;
* для `v1.0` базовый pinned provider version = **`3.1.1`**, это latest version в официальном Terraform Registry на дату этого плана; ([25])
* Terraform применяет add-ons только через `helm_release`;
* upstream add-ons ставятся из их **официальных Helm chart sources**:

  * Flannel: `flannel/flannel`; ([38], [39])
  * Calico: `projectcalico/tigera-operator`; ([26])
  * MetalLB: `metallb/metallb`; ([27])
* cluster-specific Kubernetes resources, которые не покрываются upstream values достаточно точно, должны доставляться через **локальные wrapper charts** этого repo, а не через ad hoc manifests и не через Ansible post-apply.

Следствие:

* `Flannel`, `Calico` и `MetalLB` не ставятся через `kubernetes_manifest`;
* test fixtures должны запускать отдельный Terraform add-ons pass после того, как появился kubeconfig target cluster;
* chart versions должны быть pinned в variable contract и обновляться осознанно.

## 2.10. Политика по образам нод

Для `v1.0` зафиксирована следующая image strategy:

* local harness по умолчанию использует CAPN pre-built kubeadm images с default simplestreams server, например `capi:kubeadm/VERSION`; ([16], [20])
* `INSTALL_KUBEADM=true` не является частью поддерживаемого `v1.0` path, потому что CAPN documentation прямо описывает этот режим как development-oriented fallback; ([20])
* consumer repos для реальных окружений должны иметь возможность переопределять image refs на свои custom images с pinning по версии/alias/fingerprint.

Следствие:

* в этом repo agent должен строить код вокруг prebuilt kubeadm image path;
* `install_kubeadm` по умолчанию должен быть `false`;
* риск использования evaluation-oriented CAPN images должен быть явно отмечен и не маскироваться под production-ready supply path.

## 2.11a. Политика «тестируй до коммита»

Строгое и базовое требование. Ни один commit не допустим до тех пор,
пока код не был **реально выполнен** в локальном Vagrant/libvirt-контуре
этого repo и не прошёл соответствующую acceptance-проверку:

* для любой новой или изменённой Ansible-роли — Molecule-сценарий этой
  роли прогоняется end-to-end против shared Vagrant VM (минимум
  `converge → idempotence → verify`), а не против podman/docker-driver;
* для любого нового или изменённого `Makefile`-target — target
  реально исполняется против того же harness;
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
  LXD snap channel, Helm charts (Flannel/Calico/MetalLB), Terraform
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
`PLAN-stage1-8.md` (и аналогичный набор `PLAN-stage<N>-*.md` для
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

`clusters.workload_controlplane_count` и `clusters.workload_worker_count`
по умолчанию = `2` именно для того, чтобы workload cluster был
полноценной HA-площадкой, а не «1+1 расширенным single-node». Из
этого следует обязательный контракт для всего, что Phase 5.1
(§18.4) ставит в workload cluster через Terraform Helm pass:

* **Replica contract.** Любой компонент, чья архитектура допускает
  multi-replica active/active либо leader-elected active/standby
  (т.е. `Deployment` / `StatefulSet` controllers), разворачивается с
  `replicas: 2` по умолчанию. Это касается, в частности:
  * MetalLB controller (`metallb-controller` Deployment) — leader-
    elected, два replicas корректны;
  * Calico Typha (`calico-typha` Deployment), если выбран Calico path
    — официально supported multi-replica с автоконфигом via Typha
    discovery service;
  * MetalLB speaker (`metallb-speaker`) и Calico node агент
    (`calico-node`), Flannel agent — это `DaemonSet`'ы; их replicas
    «авто-2» приходит из факта `workload_worker_count = 2`,
    отдельный override не нужен;
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
* **Test contract — обе реплики работают в тандеме.** §18.4
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
  `management_worker_count >= 2`, тот же replica-contract
  активируется через Terraform-условие на `var.worker_count >= 2`.

Этот контракт документируется и enforce'ится в §18.4 acceptance, и
зеркалится конкретными assertion'ами в §9.4 Integration / Full E2E
test scope.

---

# 3. Архитектурная модель: два режима

После ревью архитектура фиксируется как **два поддерживаемых режима**.

## 3.1. MVP / v1.0

`pivot_enabled = false` по умолчанию.

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

`pivot_enabled = true`.

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

# 6. Gate-фазы, обязательные как checkpoint-ы в основном implementation path

Эти gate-фазы:

* **не** являются отдельными research spikes;
* **не** разрешают временный ad hoc substrate;
* должны выполняться через те же reusable roles/modules/manifests/test fixtures, которые останутся в repo как production-like implementation path.

## Gate A — External L2 viability

Это теперь **обязательный gate**, а не “риск на потом”.

Он должен запускаться только после того, как в local harness уже есть минимально рабочий host/LXD substrate через реальные роли `base_system`, `binary_fetch`, `lxd_host`, `lxd_project`, `lxd_storage_pools`, `lxd_network_int_managed`, `lxd_profiles`.

Нужно автоматизировать validation scenario, который:

1. поднимает `br-ext6` на test environment;
2. поднимает 2 test LXC, подключённые к `br-ext6`;
3. проверяет:

   * multiple MAC на uplink;
   * RA reception;
   * NDP;
   * внешний IPv6 ingress;
   * не ломается ли bridge/filtering/firewall.

Если этот gate провален, текущий external L2 design должен быть остановлен, и начинается отдельная fallback ветка (routed/proxy-NDP/etc.). MetalLB L2 для IPv6 завязан на NDP и корректном L2 behavior, поэтому без этого gate продолжать нельзя. ([metallb.io][11])

Важно: local pass этого gate валидирует **reusable code path и mocked segment model**, но не доказывает свойства конкретного реального uplink/switch/provider. Поэтому consumer repo для реального окружения обязан прогонять эквивалентный gate повторно на actual external segment перед тем, как считать дизайн пригодным.

## Gate B — CNI compatibility

Нужно заранее выбрать и проверить CNI.

Этот gate должен валидировать **первый кластер, созданный теми же Terraform modules и test fixtures**, которые останутся в steady-state path. Отдельные ad hoc manifests для gate запрещены.

Проверка должна идти уже после:

* Terraform CAPI pass, который создал target cluster;
* export target kubeconfig;
* Terraform Helm add-ons pass, который поставил выбранный CNI.

### Принятое решение

* **unprivileged LXC substrate фиксируется заранее и не подлежит торгу из-за удобства CNI**
* **official known-good baseline для unprivileged/userns path: kube-flannel с backend `vxlan`**
* **Calico остаётся целевым advanced-variant, но для unprivileged LXC считается experimental до прохождения Gate B на том же самом substrate**
* **privileged LXC запрещён как workaround для CNI-проблем**

Почему так:

* CAPN прямо указывает, что при unprivileged containers похожие ограничения могут затрагивать CNI, и что `kube-flannel` с `vxlan` является known-good вариантом; ([24])
* upstream Kubernetes rootless/userns documentation тоже отдельно предупреждает, что некоторые CNI plugins могут не работать, а `Flannel (VXLAN)` известен как working option; ([37])
* Calico documentation для стандартной Kubernetes installation требует `CAP_SYS_ADMIN` и прямо говорит, что самый простой путь — privileged/root deployment; это не делает Calico автоматически непригодным внутри unprivileged LXC node, но означает, что этот путь нельзя считать доказанным без явного gate на нашем substrate. ([26])
* поэтому для `v1.0` приоритет такой:
  * сначала сохранить host-level isolation через unprivileged LXC,
  * затем выбрать минимально достаточный CNI,
  * и только потом расширять feature set вроде richer policy/data-plane behavior.

Что проверять в gate:

* nodes become Ready;
* pod-to-pod works на том наборе address families, который заявляет выбранный CNI path;
* Service networking works на том наборе address families, который заявляет выбранный CNI path;
* не упираемся в nested LXC restrictions;
* не ломается дальнейшая интеграция с MetalLB.

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
      bootstrap_api_publish/
      pivot_clusterctl_move/
      cleanup_bootstrap/
      export_artifacts/
      gate_ext_l2/
      gate_cni/

  clusterctl/
    clusterctl.yaml

  charts/
    metallb-config/

  terraform/
    modules/
      capi_cluster_class/
      capi_lxc_templates/
      capi_management_cluster/
      capi_workload_cluster/
      cluster_addons_helm/

  manifests/
    metallb/
    calico/
    cloud-init/
    networkd/
    kube-proxy/
    kubeadm-patches/

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
      gate-ext-l2/
      gate-cni/
      bootstrap-cluster/
      cluster-addons-helm/
      pivot/
      e2e-local/
    fixtures/
      terraform/
        management-cluster/
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
          ext6-mock.xml
          mgmt-nat.xml
          probe-ext6.xml

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
* локальные Helm wrapper charts допускаются только как reusable implementation asset, который ставится Terraform `helm_release`, а не как отдельный ручной слой;
* боевые consumer repos должны сами собирать inventories/playbooks/root modules вокруг этих roles/modules.

Ansible roles — стандартная reusable единица для orchestration; Terraform modules — standard reusable composition unit; Molecule delegated driver позволяет самим управлять lifecycle VM через Vagrant/libvirt. ([ansible.readthedocs.io][14])

---

# 8. Типизированный контракт переменных

Ниже — основное. В коде это должно лечь в `defaults/main.yml` и `variables.tf`.

Это именно **public interface contract** reusable ролей и модулей.

* test fixtures внутри этого repo могут использовать synthetic values;
* concrete values для реальных окружений, secrets, overlays и tfvars должны задаваться в отдельных private consumer repos.

```yaml
global:
  opt_root: {type: string, default: "/opt/capi-lab"}
  project_name: {type: string, default: "capi-lab"}
  pivot_enabled: {type: bool, default: false}

capi:
  infrastructure_secret_name: {type: string, default: "capn-identity"}
  cluster_topology_enabled: {type: bool, default: true}
  unprivileged_nodes: {type: bool, default: true}

host:
  distro: {type: string, default: "debian-13"}
  # host.* lxd_host_* inputs are consumed by role lxd_host (plan §13.2).
  lxd_host_snap_channel: {type: string, default: "6/stable"}          # verified 2026-04-21; plan §2.11 — newest feature-stable track
  lxd_host_snap_refresh_mode: {type: string, default: "hold"}         # hold|timer
  lxd_host_snap_refresh_timer: {type: string, default: "fri,03:00-04:00"}

storage:
  pool_name: {type: string, default: "capi-fast"}
  driver: {type: string, default: "btrfs"}
  # `source` это путь к блочному устройству (/dev/disk/by-id/...),
  # а не к mounted filesystem. LXD snap AppArmor-confined и не имеет
  # доступа к произвольным host-путям вне /var/snap/lxd/common/.
  # Для btrfs-driver'а LXD форматирует устройство через mkfs.btrfs
  # без -f, поэтому device должен быть signature-free на первый
  # converge — см. §13.4 implementation notes.
  source: {type: string, required: true}
  btrfs_mount_options: {type: string, default: "user_subvol_rm_allowed"}

networking:
  uplink_interface: {type: string, required: true}
  external_bridge_name: {type: string, default: "br-ext6"}
  internal_network_name: {type: string, default: "capi-int"}
  internal_ipv4_subnet: {type: string, default: "10.77.0.0/24"}
  internal_ipv6_subnet: {type: string, default: "fd42:77:1::/64"}
  internal_ipv4_nat: {type: bool, default: true}
  internal_ipv6_nat: {type: bool, default: true}
  external_ipv6_prefix: {type: string, required: true}
  external_node_ipv6_range: {type: string, required: true}
  metallb_vip_range_v6: {type: string, required: true}
  guest_internal_ifname: {type: string, default: "eth0"}
  guest_external_ifname: {type: string, default: "eth1"}
  external_ra_accept: {type: bool, default: true}
  external_ra_use_gateway: {type: bool, default: false}
  guest_network_backend: {type: string, default: "systemd-networkd"}

bootstrap:
  instance_name: {type: string, default: "capi-bootstrap-0"}
  # Defaults track current upstream stable per plan §2.11; every bump
  # records its verification date inline next to the pin. See §8a.
  k3s_version: {type: string, default: "v1.35.3+k3s1"}         # verified 2026-04-21
  kubectl_version: {type: string, default: "v1.35.3"}          # verified 2026-04-21
  clusterctl_version: {type: string, default: "v1.12.5"}       # verified 2026-04-21
  capn_provider_version: {type: string, default: "v0.8.5"}     # verified 2026-04-21
  api_publish_port: {type: int, default: 16443}
  api_publish_acl_mode: {type: string, default: "strict"}   # strict|local_harness_auto
  allowed_source_ips: {type: list(string), default: []}     # required when api_publish_acl_mode=strict

images:
  controlplane: {type: string, default: "capi:kubeadm/VERSION"}
  worker: {type: string, default: "capi:kubeadm/VERSION"}
  source_policy: {type: string, default: "capn-prebuilt"}   # capn-prebuilt|consumer-custom
  controlplane_fingerprint: {type: string, default: ""}
  worker_fingerprint: {type: string, default: ""}

templates:
  install_kubeadm: {type: bool, default: false}
  controlplane_profiles: {type: list(string), default: ["capi-base", "capi-controlplane"]}
  worker_profiles: {type: list(string), default: ["capi-base", "capi-worker"]}
  controlplane_devices: {type: map(any), default: {}}
  worker_devices: {type: map(any), default: {}}
  idmap_isolated: {type: bool, default: true}
  network_files_strategy: {type: string, default: "cabpk-files"}
  patch_delivery_strategy: {type: string, default: "cabpk-files-plus-patches"}

cni:
  workload_default: {type: string, default: "flannel"}   # flannel|calico
  flannel_backend: {type: string, default: "vxlan"}
  fallback_allowed: {type: bool, default: true}

addons:
  # Defaults track current upstream stable per plan §2.11. Verification
  # dates inline — §8a below compiles a single table.
  helm_provider_version: {type: string, default: "3.1.1"}                                           # verified 2026-04-21
  flannel_chart_repository: {type: string, default: "https://flannel-io.github.io/flannel"}
  flannel_chart_name: {type: string, default: "flannel"}
  flannel_chart_version: {type: string, default: "v0.28.4"}                                         # verified 2026-04-21
  calico_chart_repository: {type: string, default: "https://docs.tigera.io/calico/charts"}
  calico_chart_name: {type: string, default: "tigera-operator"}
  calico_chart_version: {type: string, default: "v3.31.5"}                                          # verified 2026-04-21
  metallb_chart_repository: {type: string, default: "https://metallb.github.io/metallb"}
  metallb_chart_name: {type: string, default: "metallb"}
  metallb_chart_version: {type: string, default: "0.15.3"}                                          # verified 2026-04-21
  kube_proxy_nodeport_addresses: {type: list(string), default: []}  # derive from external IPv6 policy if empty
  metallb_enabled: {type: bool, default: true}
  metallb_interface: {type: string, default: "eth1"}
  metallb_node_selector_labels: {type: map(string), default: {}}
  metallb_wrapper_chart_path: {type: string, default: "charts/metallb-config"}

clusters:
  management_cluster_name: {type: string, default: "mgmt-1"}
  workload_cluster_name: {type: string, default: "lab-default"}
  # Per plan §2.11: latest stable at time of pin. Workload/mgmt K8s version
  # is separate from k3s bootstrap version because they solve different jobs.
  kubernetes_version: {type: string, default: "v1.35.3"}           # verified 2026-04-21
  # Topology defaults for the two CAPN-provisioned clusters. The mgmt
  # cluster runs a 1+1 (single CP, single worker) — small footprint
  # since add-ons + Terraform state live elsewhere on the runner. The
  # workload cluster runs a 2+2 (HA control plane, two workers) so the
  # local lab actually exercises multi-CP kubeadm reconciliation and
  # MetalLB / Calico failover paths in §18.x. All four counts are
  # tunable via Terraform vars on the corresponding fixture roots
  # (§17.6) — they are NOT substrate-required.
  management_controlplane_count: {type: int, default: 1}
  management_worker_count:       {type: int, default: 1}
  workload_controlplane_count:   {type: int, default: 2}
  workload_worker_count:         {type: int, default: 2}
```

## 8a. Verified version log

Per §2.11, каждый pin внешней зависимости фиксируется с датой
проверки upstream. Таблица компилируется из inline-комментариев в §8;
если inline-дата расходится с таблицей — inline источник истины, а
таблицу надо пересобрать при следующем review.

| Компонент | Версия | Где используется | Дата проверки |
| --- | --- | --- | --- |
| Kubernetes (workload/mgmt) | `v1.35.3` | `clusters.kubernetes_version` | 2026-04-21 |
| k3s (bootstrap) | `v1.35.3+k3s1` | `bootstrap.k3s_version` | 2026-04-21 |
| kubectl | `v1.35.3` | `bootstrap.kubectl_version` | 2026-04-21 |
| Cluster API (clusterctl) | `v1.12.5` | `bootstrap.clusterctl_version` | 2026-04-21 |
| CAPN | `v0.8.5` | `bootstrap.capn_provider_version` | 2026-04-21 |
| LXD snap channel | `6/stable` | `host.lxd_host_snap_channel` | 2026-04-21 |
| Flannel chart | `v0.28.4` | `addons.flannel_chart_version` | 2026-04-21 |
| Calico (tigera-operator) chart | `v3.31.5` | `addons.calico_chart_version` | 2026-04-21 |
| MetalLB chart | `0.15.3` | `addons.metallb_chart_version` | 2026-04-21 |
| Terraform helm provider | `3.1.1` | `addons.helm_provider_version` | 2026-04-21 |
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

* **Реально используемые имена libvirt networks:** `k8slab-mgmt-nat`,
  `k8slab-ext6-mock`, `k8slab-probe-ext6` (с префиксом `k8slab-`,
  чтобы не конфликтовать с возможными пользовательскими сетями в
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

## 9.3. Как проверить внешний ingress локально

Для полноценного e2e test нужен ещё **probe endpoint** на `ext6-mock`:

* либо вторая маленькая VM на этой libvirt network,
* либо отдельный netns/VM, подключённый туда же.

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
  label при `pivot_enabled=false` (default).

### Integration-level

* `gate_ext_l2`
* `gate_cni`
* `bootstrap_cluster`
* `cluster_addons_helm` — обязан, помимо проверки факта установки
  Helm releases, ассертить **HA pair contract §2.12** для каждого
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
  `pivot_enabled=true`).

### Molecule harness style contract

Для этого repo Molecule/Vagrant/libvirt harness должен следовать практическому стилю `naive_proxy`, адаптированному к multi-role repo:

* общий wrapper `Makefile` в `tests/molecule/` обязан предоставлять targets по схеме `<scenario>-<driver>-<action>`;
* общие `prepare.yml`, `converge.yml`, `verify.yml`, shared vars и helper tasks выносятся в `tests/molecule/shared/`, чтобы role-level и integration-level scenarios не дублировали boilerplate;
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
3. LXD substrate
4. external L2 gate
5. bootstrap cluster
6. apply first Terraform CAPI fixture
7. export target kubeconfig
8. apply first Terraform Helm add-ons fixture
9. CNI gate
10. MetalLB smoke
11. optional pivot / post-pivot workload create + kubeconfig export + add-ons apply
12. verify
13. destroy

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
6. apply the selected Terraform Helm add-ons fixture path
7. run gate checks and verify
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

Не “голый порт”, а:

* source-IP ACL на host,
* Kubernetes API mTLS/kubeconfig,
* LXD API auth отдельно через restricted TLS secret.

Правило интерпретации ACL:

* `allowed_source_ips=[]` не означает allow-all;
* при `bootstrap.api_publish_acl_mode=strict` пустой список должен приводить к explicit failure;
* auto-discovery источника допускается только в local harness mode и всё равно должна материализовать явный ACL.

CAPN identity secret format and LXD restricted TLS auth support this exact model. ([capn.linuxcontainers.org][19])

---

# 12. Риски и mitigation

## 12.1. External L2 may fail

Mitigation:

* Phase 2.5 gate before дальнейшим продвижением по cluster path

## 12.2. Unprivileged LXC node path may fail on userns/runtime/CNI edges

Mitigation:

* pin CAPN-tested unprivileged kubeadm image path (`v1.32.4+`)
* Phase 5.2 gate on first Terraform-created cluster after Helm add-ons pass
* keep unprivileged substrate fixed and vary CNI inside that constraint
* use `kube-flannel` `vxlan` as known-good baseline; promote `Calico` only if the gate passes on the same substrate
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

* `pivot_enabled=false` by default

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
* `install_kubeadm=true` does not become the implicit workaround path

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
