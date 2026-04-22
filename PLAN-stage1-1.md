Этот файл владеет §13..§14: выполненные Ansible-роли (§13) и
выполненные phases (§14). Stage-1-wide meta (out-of-scope fence,
self-review, final recommendation) переехала в PLAN-stage1-8.md
(§21..§23). Нумерация §N сквозная по всем plan-файлам; перекрёстные
ссылки вида `§<номер>` валидны без указания имени файла — см.
`PLAN-stage1-common.md` header для полного file lineup. Атомарный scope
этого шарда — «только уже выполненная имплементация Stage 1, без
stage-wide meta», чтобы coding-agent, который смотрит «что сделано»,
не тратил контекст на фильтрацию framing-секций.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)  <-- этот файл
PLAN-stage1-2.md ................. §15      (Phase 2.5 external L2 gate)
PLAN-stage1-3.md ................. §16      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-4.md ................. §17      (Phases 5 + 5.05 Terraform CAPI + kubeconfig)
PLAN-stage1-5.md ................. §18      (Phases 5.1 + 5.2 + 5.3 Helm add-ons + CNI / MetalLB gates)
PLAN-stage1-6.md ................. §19      (Phases 6 + 7 pivot + workload clusters)
PLAN-stage1-7.md ................. §20      (Phase 8 destroy)
PLAN-stage1-8.md ................. §21..§23 (Stage 1 meta: out-of-scope, self-review, recommendation)
```

---

# 13. Выполненные Ansible-роли

Этот раздел охватывает Ansible-роли Stage 1, которые уже реализованы и
прогнаны end-to-end в локальном Vagrant/libvirt-контуре по состоянию на
Step 4 (2026-04-22):

* §13.1 `base_system` (Step 1);
* §13.2 `lxd_host` (Step 2);
* §13.3 `lxd_project` (Step 3 + Step 4 substrate расширение);
* §13.4 `lxd_storage_pools` (Step 3);
* §13.5 `lxd_network_int_managed` (Step 3);
* §13.6 `lxd_profiles` (Step 3 lean baseline + Step 4 full CAPN unprivileged kubeadm baseline);
* §13.7 `lxd_bootstrap_instance` (Step 3 — первая роль Phase 3);
* §13.8 `binary_fetch` (Step 4 — отложенная Phase 1.5 / §16.1);
* §13.9 `bootstrap_k3s` (Step 4 — первая роль Phase 4).

Ещё не выполненные Stage-1-роли живут в последующих шардах (§15..§20)
вместе со своими phases.

## 13.1. `base_system`

**Статус: выполнено в Step 1 (2026-04-21).**

Ставит только system packages, которые допустимы:

* `snapd`
* `python3`
* `python3-apt`
* `ca-certificates`
* `curl`
* `tar`
* `gzip`
* `xz-utils`
* `btrfs-progs` если используется Btrfs pool

Для Btrfs LXD explicitly requires `btrfs-progs`. ([Ubuntu Documentation][3])

Дополнительно к §13.1-packages scope роль владеет **btrfs pool contract**
(добавлено в Step 1 по запросу оператора для реалистичной target
architecture): public vars `base_system_btrfs_pool_required`,
`base_system_btrfs_pool_mountpoint`, `base_system_btrfs_pool_label`,
`base_system_btrfs_pool_fstype`. Форматирование и монтирование диска
остаётся вне роли (Molecule shared prepare в тестах, installer image в
prod); роль только **asserts contract** при `required: true` — путь
смонтирован и действительно btrfs. Это не ломает ownership model
§2.7 (Ansible owns host bootstrap): disk-provisioning остаётся
prerequisite, роль только enforces contract.

Роль также инициализирует `/opt/capi-lab/{bin,etc}` и добавляет
sysctl baseline (inotify, fs.file-max, net.ipv6.forwarding,
ipv4.ip_forward) + обязательные kernel modules (`overlay`,
`br_netfilter`, `nf_conntrack`) через persistent `modprobe` —
предусловие для LXD/containerd/kubelet downstream.

## 13.2. `lxd_host`

**Статус: выполнено в Step 2 (2026-04-21).**

Единая роль host-side подготовки LXD/LXC окружения. Объединяет то,
что в ранних редакциях было раздроблено на `lxd_snap` и
`lxd_network_ext_bridge`. Критерий консолидации: роль владеет
**всем, что не является LXD entity** (т.е. всем, что живёт на уровне
host OS / snap / host networking), и ничем, что уже является объектом
внутри LXD (projects, storage pools, managed networks, profiles,
instances — у них свои роли).

Делает:

* install `lxd` via snap;
* pin snap channel;
* apply snap refresh policy:

  * `snap refresh --hold=<duration>` или
  * `refresh.timer`;
* ensure LXD daemon is `waitready`;
* ensure initial trust/socket-side access is sane for subsequent roles;
* создаёт host-side Linux bridge `br-ext6` (это обычный host-bridge, не
  LXD-managed network), аттачит uplink interface, гарантирует, что
  firewall/bridge sysctl не ломает ingress;
* не трогает чужие host bridges и не пересекается с LXD-managed
  networks.

Snap docs подтверждают, что auto-refresh включён по умолчанию, а `snap refresh --hold` и scheduling controls поддерживаются официально. ([Snapcraft][15])

Implementation notes (зафиксированы в Step 2):

* host-side bridge `br-ext6` собирается через **systemd-networkd
  drop-ins** (`/etc/systemd/network/3{0,1}-br-ext6*.{netdev,network}`),
  не через shell `ip link add` / `brctl`. Это позволяет обновлять
  конфигурацию декларативно через `networkctl reload` без disruption
  существующих интерфейсов.
* `networking.service` (ifupdown) **не трогается** — другие NIC'и
  (mgmt) могут оставаться под ним. Match-паттерны всегда явные
  `Name=<iface>`, без wildcards.
* В Step 2 зафиксирован channel `6/stable` (feature-stable), а не
  Canonical-рекомендованный LTS `5.21/stable` — trade-off в пользу
  плана §2.11 «latest stable» политики. Если Gate B или раньше
  всплывёт несовместимость с CAPN — даунгрейдимся обратно.
* 3 documented shell fallbacks остались (нет native-модуля):
  `snap set/get system refresh.*`, `/snap/bin/lxd waitready`,
  `snap list lxd`. Остальные пути нативные
  (`community.general.snap`, `ansible.builtin.systemd`,
  `ansible.builtin.copy`).

## 13.3. `lxd_project`

**Статус: выполнено в Step 3 (2026-04-22).**

Делает:

* create `capi-lab`
* enable feature isolation (см. deviation ниже по `features.networks`)
* set `restricted=true`
* allow needed restricted features:

  * nesting
  * unprivileged container privilege (hard-lock §2.8)
  * managed disk devices
  * low-level config (для `linux.kernel_modules` на kubeadm
    профилях)
  * **NIC devices: `allow`, не `managed`** — см. ниже

LXD project restrictions support exactly this model. ([Ubuntu Documentation][4])

### Deviations / implementation notes (Step 3)

* **`features.networks=false` + `features.networks.zones=false`.** LXD
  документированно НЕ поддерживает `bridge`-type сети в non-default
  проектах: попытка `POST /1.0/networks?project=capi-lab` с
  `type=bridge` падает "Network type does not support non-default
  projects". Поэтому `features.networks=false` — capi-lab наследует
  default-проектовые сети read-only. `features.networks.zones` должен
  быть consistent по парности. `capi-int` создаётся в default проекте
  (см. §13.5) и резолвится из профилей в capi-lab через inheritance.
  (§13.5 original хотел «managed bridge в capi-lab», но LXD это
  архитектурно не разрешает для bridge-type; альтернатива — OVN или
  physical — избыточна для MVP.)
* **`restricted.devices.nic=allow`**, не `managed`. LXD определяет
  «managed nic» как NIC, ссылающийся на LXD-managed network через
  `network:` key. Kubernetes-плоскость §4–5 прикрепляет eth1 к
  host-level Linux bridge `br-ext6` (owned by lxd_host), который LXD
  классифицирует как «unmanaged». Под `managed` POST инстанса падает
  "Only managed network devices are allowed". Альтернатива —
  обернуть `br-ext6` в LXD managed bridge через
  `bridge.external_interfaces` — допустима, но отложена до отдельной
  итерации; для Stage 1 держим `allow`.
* **`restricted.containers.lowlevel=allow`** — `linux.kernel_modules`
  на профилях `capi-controlplane` / `capi-worker` классифицируется
  LXD как low-level config, который under `restricted=true`
  по дефолту запрещён. Нужен для CAPN unprivileged kubeadm baseline.
  Допустимые значения ключа: только `allow` / `block`.
* **Implementation переехала с `community.general.lxd_project` на
  `ansible.builtin.uri`** прямо к LXD REST API
  (`/1.0/projects`, `POST` / `PATCH`). Community-модуль молча
  сбрасывает transitions `features.*` (accepted через
  `lxc project set` и raw REST, но модуль возвращает `changed=0` и
  PATCH не уходит на проводе). `ansible.builtin.uri` — тоже native
  module (§2.6.1), и даёт полный контроль над payload'ом. Решение
  задокументировано в `roles/lxd_project/tasks/project.yml`
  header-комментарии и в role README caveats.

### Step 4 расширения (2026-04-22)

Driver: подъём `bootstrap_k3s` в unprivileged LXC потребовал двух
дополнительных restricted-ключей в проекте + перерефактора публичного
интерфейса по правилу «role-required values are hardcoded» (memory
`feedback_required_values_hardcoded.md`).

* **`restricted.containers.interception=allow`** — без этого ключа
  LXD отбивает `security.syscalls.intercept.mknod` /
  `security.syscalls.intercept.setxattr` на профилях с "Container
  syscall interception is forbidden". Эти intercepts требуются
  containerd внутри bootstrap-LXC (см. §13.6 deviation для деталей).
* **`restricted.devices.unix-char=allow`** — без этого LXD отбивает
  `kmsg` device на capi-bootstrap/controlplane/worker профилях с
  "Unix character devices are forbidden". `/dev/kmsg` passthrough в
  контейнер нужен kubelet'овскому oomWatcher; security trade-off
  обсуждается в §13.6 deviation.
* **Refactor: substrate baseline → `vars/main.yml`.** Раньше
  `lxd_project_features`, `lxd_project_restricted` и
  `lxd_project_restrictions` были user-overridable defaults. Это
  позволяло consumer'у «случайно» убрать обязательный ключ и
  получить нерабочую substrate. Step 4 переносит весь baseline в
  `_lxd_project_required_features` / `_lxd_project_required_restricted`
  / `_lxd_project_required_restrictions` (role-internal,
  не-public). Defaults теперь экспонируют только
  `lxd_project_extra_restrictions: {}` для consumer'ских
  *дополнительных* restrictions поверх baseline. Tasks мержат
  required + extras в один payload.

## 13.4. `lxd_storage_pools`

**Статус: выполнено в Step 3 (2026-04-22).**

Делает:

* create storage pools;
* support `driver=btrfs`;
* support `source=<path>` / loop / device;
* support `btrfs.mount_options`;
* support custom volumes

Btrfs storage driver docs support these options explicitly. ([capn.linuxcontainers.org][16])

### Deviations / implementation notes (Step 3)

* **`source` семантика: block device, не mounted path.** Snap LXD
  AppArmor-confined и не имеет доступа к произвольным host-путям вне
  `/var/snap/lxd/common/` (`system-files` plug не подключён по
  умолчанию). Попытка `source=/var/lib/k8slab/lxd-pool` фейлится
  "cannot access /var/lib/snapd/hostfs/...". Контракт в репо:
  `source=/dev/disk/by-id/<id>` — LXD получает чистое блочное
  устройство, форматирует его (`mkfs.btrfs` без `-f` ⇒ требует
  signature-free disk) и монтирует в свой namespace. Molecule
  scenario вытирает signatures через
  `tests/molecule/shared/tasks/prepare-clean-disk.yml` перед
  converge. Production-хосты ответственны за clean disk через
  installer image.
* **`source` — one-time creation parameter.** LXD заменяет
  `config.source` на btrfs UUID после первого mount'а, а
  оригинальный путь сохраняет в `config.volatile.initial_source`.
  Role healthcheck сравнивает declared source с
  `volatile.initial_source`; PATCH drift skips `source` (сравнение
  desired vs live всегда было бы false).
* **Implementation — `ansible.builtin.uri`**, потому что
  `community.general` ships only `lxd_storage_pool_info` (read-only),
  без CREATE-модуля. `uri` + REST соответствует native-first
  (§2.6.1) — это native module, не shell fallback.

## 13.5. `lxd_network_int_managed`

**Статус: выполнено в Step 3 (2026-04-22).**

Делает:

* create `capi-int` managed bridge;
* set IPv4/IPv6 DHCP/RA/NAT parameters;
* ensure dual-stack defaults

LXD managed bridge provides DHCP, IPv6 RAs and DNS via dnsmasq and does NAT by default. ([Ubuntu Documentation][2])

### Deviations / implementation notes (Step 3)

* **Bridge живёт в `default` проекте, не в `capi-lab`.** Сквозная
  причина та же, что в §13.3: LXD отказывает на bridge-type сетях в
  non-default проектах ("Network type does not support non-default
  projects"). `capi-lab` видит `capi-int` через inheritance (owner
  — default project), что возможно потому что `lxd_project`
  выставляет `features.networks=false`. Профили в capi-lab
  корректно резолвят `parent: capi-int` nic device'ов — проверено в
  scenario verify.
* **Implementation — `ansible.builtin.uri`** (тот же паттерн, что в
  §13.4): `POST /1.0/networks` + `PATCH /1.0/networks/<n>` для
  drift. Native CREATE-модуля в `community.general` нет.
* **RA всегда on, если `ipv6.address` задан.** Отдельного ключа
  `ipv6.ra` в LXD нет; единственный способ подавить RA — не ставить
  `ipv6.address`. В нашем default dual-stack контракт это не
  ограничение, но зафиксировано в README роли.

## 13.6. `lxd_profiles`

**Статус: выполнено в Step 3 (2026-04-22) — lean subset baseline;
доведено до полного CAPN unprivileged kubeadm baseline в Step 4
(2026-04-22) после того как `bootstrap_k3s` (§13.9) определил
точные requirements. `boot-dir` disk mapping `/boot` всё ещё отложен
до Phase 5+ (CAPN reference profile упоминает его для kubeadm-init,
но `bootstrap_k3s` его не требует).**

Обязательные profiles:

* `capi-base`
* `capi-bootstrap`
* `capi-controlplane`
* `capi-worker`

**Важно:** `capi-controlplane` и `capi-worker` должны строиться от **CAPN kubeadm profile baseline**, а не придумывать настройки с нуля. CAPN reference kubeadm profile explicitly lists required kernel modules, `raw.lxc`, `security.nesting`, `security.privileged`, `/dev/kmsg`; для Canonical LXD у unprivileged path есть отдельный LXD-specific variant. ([capn.linuxcontainers.org][17])

Для `v1.0` этот repo реализует только **Canonical LXD unprivileged baseline** для Kubernetes nodes:

* `capi-controlplane` и `capi-worker` используют unprivileged CAPN kubeadm profile variant;
* `security.nesting=true` включается только там, где он нужен для Kubernetes node path;
* `security.idmap.isolated=true` должен быть частью hardened profile contract, если конкретный validated workload не требует иного;
* privileged kubeadm profile intentionally не кодируется в основном path. ([17], [24], [34])

### Implementation notes (Step 3)

* Stage-1 baseline:
  * `capi-base` — root disk на `capi-fast` + eth0 на `capi-int`.
  * `capi-bootstrap` — `security.nesting=true`,
    `security.privileged=false`, `security.idmap.isolated=true`.
  * `capi-controlplane` / `capi-worker` — всё то же плюс
    `linux.kernel_modules=br_netfilter,ip_vs,nf_conntrack,overlay`
    и eth1 на `br-ext6`.
* Native CRUD через `community.general.lxd_profile` работает надёжно
  (в отличие от `lxd_project` диф-регрессии — см. §13.3). Uri остаётся
  только в healthchecks для чтения live-state.
* **Ansible НЕ templates dict-keys при загрузке YAML defaults.**
  Попытка использовать `"{{ role_var }}"` как ключ в devices dict
  даёт литеральную строку `{{ ... }}` на проводе, LXD отбивает
  "Name can only contain alphanumeric, …". В defaults мы держим
  **статические** имена device-ключей (`eth0`, `eth1`) — в LXD это
  «LXD-side device name» (произвольный label), guest-side interface
  name идёт через `name:` attribute, который templated нормально.
* Device-level healthchecks **coarse**: проверяются `type` +
  headline-поля (path+pool для disk, nictype+parent для nic). LXD
  иногда нормализует optional keys (`security.devlxd`, hwaddr), full
  dict-equality давал бы ложный drift.

### Step 4 расширения (2026-04-22)

Driver: `bootstrap_k3s` (§13.9) на debian/13 LXD image потребовал
полного CAPN unprivileged baseline + специфичных для k3s расширений.

* **`capi-bootstrap` baseline расширен** до того же набора, что
  `capi-controlplane` / `capi-worker`: `security.syscalls.intercept.mknod=true`,
  `security.syscalls.intercept.setxattr=true` (containerd внутри без
  них не unpack'ит images и не создаёт device nodes — symptom:
  `poststarthook/rbac/bootstrap-roles failed` + endless k3s
  crashloop), `linux.kernel_modules=br_netfilter,ip_vs,nf_conntrack,overlay`
  (kube-proxy / containerd / overlayfs). `capi-controlplane` и
  `capi-worker` так же получили эти ключи (планом было «отложено до
  inner Kubernetes»; inner Kubernetes — это k3s — теперь
  определил).
* **`raw.lxc: lxc.apparmor.profile=unconfined`** на всех трёх
  kubeadm-профилях. Default LXD apparmor profile в unprivileged
  containers блокирует доступ к `/dev/kmsg` и часть iptables/netlink
  ops kube-proxy'а. Документированный recipe для k3s-в-LXC (Proxmox
  forum, discuss.linuxcontainers.org/t/7539, triangletodd gist).
  Plan §2.8 hard-lock unprivileged по-прежнему держится — снимается
  только AppArmor-confinement, не сами user-namespace boundaries.
* **`/dev/kmsg` device passthrough (`unix-char`)** на всех трёх
  kubeadm-профилях. Без него kubelet's oomWatcher падает на
  `open /dev/kmsg: no such file or directory` (даже с
  `--kubelet-arg=feature-gates=KubeletInUserNamespace=true`,
  потому что файл физически не создан в unprivileged LXC). Source
  read-only по сути: write в /dev/kmsg блокируется host-kernel
  CAP_SYSLOG check, который у unprivileged container нет в
  host-namespace. Risk model: information disclosure (host kernel
  log виден контейнеру) — для local lab acceptable; production
  consumer должен пере-оценить (см. ресерч в conversation log).
* **Refactor: substrate baseline → `vars/main.yml`.** Раньше
  `lxd_profiles_profiles` был user-overridable list со всем содержимым
  каждого из 4 профилей. Permissive override → consumer мог "случайно"
  убрать substrate-required ключ. Step 4 переносит полный per-profile
  спек в `_lxd_profiles_catalog` (vars/main.yml, role-internal).
  Defaults экспонируют только shared inputs (storage_pool, ifnames)
  + per-profile `lxd_profiles_capi_<role>_extra_config / _extra_devices`
  для тюнинга поверх baseline. Новый `tasks/compose.yml` строит
  `_lxd_profiles_effective` из catalog + extras; profiles.yml и
  healthchecks.yml итерируют над ним.
* **Restart-on-profile-change**. По LXD docs ([instance_options ref][lxd-options])
  большинство substrate-required keys (`security.privileged`,
  `security.idmap.isolated`, `security.syscalls.intercept.*`,
  `raw.lxc`) имеют `Live update: no` — LXD принимает PATCH профиля
  но не propagate-ит на running instances. Без рестарта profile
  changes молча drift'ят. Step 4 добавляет в `tasks/profiles.yml`
  логику: после apply вычисляется список изменившихся профилей,
  list'ятся running instances в проекте, рестартятся те, у которых
  изменившийся профиль в `profiles[]`. Restart через
  `community.general.lxd_container state=restarted`. Caveat
  (документирован в README): если первый apply прошёл (changed=true)
  но restart упал, на re-run профиль уже matches (changed=false) →
  restart не повторяется → instance остаётся в drift до операторского
  вмешательства. Robust drift detector (сравнение
  `expanded_config` instance vs profile baseline) отложен.
* **Verify scenario доказывает restart-on-change** end-to-end:
  `tests/molecule/bootstrap-k3s/verify.yml` после основных assert'ов
  захватывает init PID контейнера, дёргает `lxd_profiles` с
  `lxd_profiles_capi_bootstrap_extra_config: {user.k8slab-restart-test: ...}`
  (марker заставляет `lxd_profile` отчитать `changed=true`),
  захватывает PID после, ассертит PID changed. После теста marker
  снимается через `ansible.builtin.uri` PUT (PUT — единственный
  способ удалить config key в LXD; PATCH с `merge_profile=true`
  только добавляет/обновляет, удалить нельзя), чтобы downstream
  scenarios на той же VM не видели pollution.

[lxd-options]: https://documentation.ubuntu.com/lxd/latest/reference/instance_options/

## 13.7. `lxd_bootstrap_instance`

**Статус: выполнено в Step 3 (2026-04-22) — Phase 3 первая роль.**

Создаёт:

* `capi-bootstrap-0`
* в project `capi-lab`
* с нужным profile
* с networking attachment
* с nesting

### Implementation notes (Step 3)

* Native `community.general.lxd_container` — полноценный CRUD-модуль
  с project-scoping, profiles, image source, state machine. Диф-
  регрессия `lxd_project`-модуля на этом пути не всплыла; uri
  здесь не понадобилось.
* Default image source — **Canonical LXD simplestreams remote**
  `https://images.lxd.canonical.com`, alias `debian/13`. URL
  изменился относительно общеизвестного
  `https://images.linuxcontainers.org` после раскола LXD/Incus в
  2023 — `images:` remote в стоковом LXD snap'е теперь указывает
  на Canonical-хостинг, и `debian/13` fingerprint в Incus-каталоге
  отсутствует. Консумеры на Incus могут переопределить
  `lxd_bootstrap_instance_image_server` обратно.
* Profiles: `[capi-base, capi-bootstrap]` (root disk, internal nic,
  nesting, unprivileged, idmap isolated).
* `state: started`, `wait_for_container: true`,
  `wait_for_ipv4_addresses: true` — блокирует роль до появления
  IPv4 на всех nic'ах контейнера, чтобы Phase 4 мог сразу начинать
  работать.
* `ignore_volatile_options: true` — глушит ложный drift по
  `volatile.*` (mac'и, last-state timestamps).
* **LXD НЕ реплицирует inherited profile devices в
  `instance.devices`** — только instance-level overrides появляются
  там. Verify bootstrap-контейнера проверяет eth0 через runtime
  `state.network` (host-side bridge port bound), а parent/nictype
  корректность остаётся в `lxd_profiles`-scenario verify.

## 13.8. `binary_fetch`

**Статус: выполнено в Step 4 (2026-04-22) — Phase 3.5 (отложенная
из Phase 1, см. §14.2 / §16.7).**

Скачивает в `/opt/capi-lab/bin` (host-side):

* `kubectl`
* `clusterctl`
* `k3s`

Каждый бинарь — pinned version (трекает §8a verified version log) +
checksum verification через `ansible.builtin.get_url checksum:
sha256:<digest>`. Owner/group/mode деривируются от
`base_system`-owned `/opt/capi-lab/bin` (root:root 0755).

### Implementation notes (Step 4)

* **Три checksum styles**, по одному на upstream:
  * `plain` (kubectl) — GET `<url>.sha256`, файл = одна строка hex.
  * `manifest` (k3s) — GET `sha256sum-<arch>.txt` в `sha256sum(1)`
    формате (`<hex>  <name>` per line), парсим через
    `regex_findall(multiline=true)` по `checksum_entry` =
    имя ассета.
  * `pinned` (clusterctl) — upstream cluster-api releases НЕ
    публикуют sha256-файл (verified 2026-04-22 на v1.12.5 — release
    asset list содержит только raw clusterctl-*-* binaries и yaml
    манифесты, никаких sha256). Hash хранится прямо в
    `defaults/main.yml` рядом с version pin
    (`binary_fetch_clusterctl_checksum_sha256`); audit'ится через
    `sha256sum` на control node при каждом version-bump'е.
    Пометка даты проверки идёт inline там же.
* **`ansible.builtin.get_url` идемпотентный**: при повторном
  прогоне сравнивает sha256 destination'а с тем что в `checksum:`,
  пропускает download если совпало.
* **Native-first путь** (плана §2.6.1) — никаких shell wrappers,
  никаких `install.sh` от upstream'а. `uri` для checksum file +
  `get_url` для binary.
* Healthchecks запускают каждый бинарь через `--version` (или
  `version --client --output=yaml` для kubectl, `version --output=yaml`
  для clusterctl) и матчат self-reported version против pinned —
  отлавливает silent download corruption.

## 13.9. `bootstrap_k3s`

**Статус: выполнено в Step 4 (2026-04-22) — Phase 4 первая роль.**

Внутри bootstrap LXC:

* раскладывает `k3s` (host `/opt/capi-lab/bin/k3s` → container
  `/usr/local/bin/k3s`);
* рендерит и пушит systemd unit + env file;
* запускает `k3s.service` с `--disable=traefik --disable=servicelb`
  + substrate-required hardcoded флагами (см. ниже);
* поллит kube-apiserver через `kubectl get nodes` до Ready.

### Implementation notes (Step 4)

* **Execution model: shell-via-`lxc exec` / `lxc file push`,
  не `community.general.lxd` connection plugin.** В Molecule harness
  controller (моя dev-машина) НЕ является LXD host'ом — host это
  Vagrant VM. `community.general.lxd` connection plugin shell'ит
  `lxc` локально на controller'е, что не подходит. Pure SSH→host→`lxc`
  shell — та же boundary, что `lxd_bootstrap_instance` использует
  через REST. Документированный shell fallback (плана §2.6.1).
* **`lxc` CLI — абсолютным путём `/snap/bin/lxc`** через
  `bootstrap_k3s_lxc_cli`. Snap LXD кладёт `lxc` в `/snap/bin/`,
  который не на default PATH в non-interactive SSH session'ах.
* **Идемпотентный binary push**: stat host k3s → sha256sum через
  `lxc exec` внутри контейнера → push только если digests различаются.
* **Идемпотентный unit/env push**: render через `template` в
  persistent staging path (`/opt/capi-lab/etc/bootstrap_k3s/`),
  read in-container content через `lxc exec cat`, compute drift
  flag, push только при drift. Persistent staging path (а не /tmp)
  чтобы template сам по себе был idempotent на rerun.
* **Hardcoded substrate-required флаги в `templates/k3s.service.j2`**
  (правило memory `feedback_required_values_hardcoded.md` —
  «если без этого роль не работает, hardcode in template, не
  переменная»):
  * **`--disable-cloud-controller`** — k3s embedded
    cloud-controller-manager в unprivileged LXC попадает в RBAC
    race condition (k3s-io/k3s#7328): CCM пытается прочитать
    `extension-apiserver-authentication` configmap до того как
    `poststarthook/rbac/bootstrap-roles` создаст для него
    RoleBinding. CCM exits → k3s shutdown → systemd Restart=always
    → endless crashloop. У k3s-lab нет cloud integration to lose, так
    что CCM выключен полностью.
  * **`--kubelet-arg=feature-gates=KubeletInUserNamespace=true`** —
    kubelet в unprivileged container открывает `/dev/kmsg` из
    oomWatcher; без этого gate (или физически смонтированного
    `/dev/kmsg`, который мы тоже добавили в profile §13.6)
    kubelet падает на старте. Defense-in-depth — мы делаем оба
    fix'а.
  * Consumer'ы могут добавлять *дополнительные* kubelet feature
    gates через `bootstrap_k3s_extra_kubelet_feature_gates: []`
    (rendered в тот же `--kubelet-arg=feature-gates=<csv>` поверх
    required gate, нельзя его убрать).
* **`Type=notify` оставлен**, как в upstream
  `github.com/k3s-io/k3s/blob/master/k3s.service`. После всех
  substrate-fix'ов k3s корректно доставляет sd_notify READY=1 и
  systemd переходит в `active` (раньше с broken substrate висел в
  `activating`); тесты строго требуют `active`.
* **Healthcheck — `kubectl get nodes` retry-loop**, не systemd
  state. Real cluster readiness = node Ready, не systemd transition.
  Defaults: 60 retries × 4s = 240s; в Molecule scenario разогнан до
  90 × 4 = 360s на cold-image-pull.
* **Verify scenario** проверяет: container Running, in-container
  k3s sha256 == host k3s sha256, `systemctl is-active k3s.service ==
  "active"`, `kubectl get nodes` ready, `/etc/rancher/k3s/k3s.yaml`
  existing + non-empty. Плюс end-to-end test для restart-on-profile-change
  поведения `lxd_profiles` (см. §13.6 Step 4 deviation).

---

# 14. Выполненные phases

Этот раздел перечисляет phases, уже прошедшие end-to-end в локальном
Vagrant/libvirt-контуре по состоянию на Step 4 (2026-04-22):

* §14.1 Phase 0 — repo skeleton и local harness (Step 1);
* §14.2 Phase 1 — host bootstrap (Steps 1–2; `binary_fetch` отложен и
  выполнен в Phase 3.5 / §14.5);
* §14.3 Phase 2 — LXD substrate (Step 3);
* §14.4 Phase 3 — bootstrap instance (Step 3);
* §14.5 Phase 3.5 — `binary_fetch` (Step 4);
* §14.6 Phase 4 — bootstrap management cluster (Step 4 — частично:
  `bootstrap_k3s` готов; `bootstrap_clusterctl` / `bootstrap_capn_secret`
  / `bootstrap_api_publish` остаются в §16.3..§16.5).

Ещё не выполненные phases живут в §15..§20.

## 14.1. Phase 0 — repo skeleton и local harness

**Статус: выполнено в Step 1 (2026-04-21).** Tree по §7, все три
Makefile'а, `ansible/ansible.cfg` + `requirements.yml`, Vagrant VM
`tests/vagrant/debian13/` (3 NIC: mgmt + ext6 + management default,
dedicated LXD pool disk 40 GiB с serial `k8slab-lxdpool`), libvirt
networks `k8slab-mgmt-nat` / `k8slab-ext6-mock` / `k8slab-probe-ext6`,
Molecule 26.x delegated-mode harness через
`scripts/molecule_run.py` (поднимает VM, экспортирует `K8SLAB_HOST_*`
env, execvpe'ит molecule). Auto-invalidation Molecule state по VM
UUID (`.artifacts/harness-vm-id`).

Сделать:

* tree
* `Makefile`
* `ansible.cfg`
* Vagrant/libvirt VM
* Molecule delegated

Acceptance:

* `make lint`
* `make test-local-harness`

## 14.2. Phase 1 — host bootstrap

**Статус: выполнено в Steps 1–2 (`base_system` в Step 1,
`lxd_host` в Step 2). `binary_fetch` отложен к Phase 3.5.**

Роли (в порядке реализации):

* `base_system` — Step 1.
* `lxd_host` — Step 2.
* `binary_fetch` (отодвинут ближе к Phase 4 — kubectl/clusterctl/k3s
  не потребляются раньше; см. §16.1 и §16.7).

Acceptance:

* Debian 13 host prepared
* LXD daemon installed, snap channel pinned, refresh policy applied
* host-side external bridge `br-ext6` создан с привязанным uplink
* binaries в `/opt/capi-lab/bin` (когда фаза с `binary_fetch` исполнена)
* no custom apt repos

## 14.3. Phase 2 — LXD substrate (entities inside LXD)

**Статус: выполнено в Step 3 (2026-04-22).**

Роли:

* `lxd_project`
* `lxd_storage_pools`
* `lxd_network_int_managed`
* `lxd_profiles`

Acceptance:

* `capi-lab` project exists
* Btrfs pool exists
* internal managed network exists (**в default проекте** —
  см. §13.5 deviation)
* profiles exist
* no damage to foreign containers

## 14.4. Phase 3 — bootstrap instance

**Статус: выполнено в Step 3 (2026-04-22).**

Роль:

* `lxd_bootstrap_instance`

Acceptance:

* `capi-bootstrap-0` exists
* proper profile attached
* starts cleanly

## 14.5. Phase 3.5 — `binary_fetch` (отложенная из Phase 1)

**Статус: выполнено в Step 4 (2026-04-22). Соответствует §16.7.**

Роль:

* `binary_fetch` (см. §13.8).

Acceptance:

* `kubectl`, `clusterctl`, `k3s` в `/opt/capi-lab/bin` с
  deterministic owner/group/mode `root:root 0755`;
* sha256 каждого бинаря сходится с upstream-published checksum
  (для clusterctl — с pinned digest рядом с version pin, см.
  §13.8 implementation note);
* каждый бинарь runs и self-reports версию, совпадающую с pinned
  значением из §8a.

## 14.6. Phase 4 — bootstrap management cluster (частично)

**Статус: частично выполнено в Step 4 (2026-04-22) — `bootstrap_k3s`
готов; `bootstrap_clusterctl` / `bootstrap_capn_secret` /
`bootstrap_api_publish` / `export_artifacts` остаются в §16.3..§16.6
и будут реализованы в следующих Step'ах.**

Сделано в Step 4:

* `bootstrap_k3s` (см. §13.9) поднимает single-node k3s server в
  `capi-bootstrap-0` LXC. Это потребовало substrate-расширений в
  §13.3 (`restricted.containers.interception`,
  `restricted.devices.unix-char`) и §13.6 (полный CAPN unprivileged
  kubeadm baseline + `/dev/kmsg` passthrough + `raw.lxc` apparmor
  override + restart-on-profile-change).

Acceptance Step 4 части (доказано verify scenario'ями):

* `k3s.service` достигает `active` (не `activating`) — substrate
  правильный;
* `kubectl get nodes` reports `capi-bootstrap-0` Ready;
* `/etc/rancher/k3s/k3s.yaml` существует и непустой;
* in-container k3s sha256 == host k3s sha256 (push без corruption);
* restart-on-profile-change поведение в `lxd_profiles` срабатывает
  (init PID контейнера меняется при profile-mod) — см. §13.6 Step 4
  verify deviation.

Acceptance целой Phase 4 (после остальных ролей §16.3..§16.6):

* bootstrap API reachable from runner
* `clusterctl init` done
* providers healthy
* LXD identity secret present

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
