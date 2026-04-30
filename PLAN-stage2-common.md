# Stage 2 — backlog

Список features, которые могут быть реализованы поверх работающего
substrate'а repo. Каждый item — opt-in, независим от остальных,
требует своего design step + implementation + lint/test cycle.

Запрещено:
* регрессировать substrate-инварианты, зафиксированные в коде repo
  (unprivileged-only LXC, helm-first delivery K8s-объектов, mandatory
  CAPI bootstrap-and-pivot flow, dual-stack networking baseline,
  CAPI/CAPN version pins) — это закрытые архитектурные решения,
  не переключаемые опции;
* реализовывать backlog item «по-быстрому» без отдельного design step,
  собственного Step N маркера, plan rewrite и Molecule e2e regression
  на свежей VM.

Items не имеют фиксированного порядка реализации.

---

## Pod IPv6 routing — Calico BGP route advertisement

**Цель.** Заменить текущий Pod→substrate IPv6 SNAT (`natOutgoing:
Enabled` для IPv6 pool в `charts/cni-calico/templates/installation.yaml`)
на честный Layer-3 routing, чтобы вернуть per-Pod traceability в
substrate-side access logs (haproxy LB на capi-int, LXD daemon HTTPS).

**Что меняется.**
* `charts/cni-calico/templates/installation.yaml`: flip
  `calicoNetwork.bgp` с `Disabled` на `Enabled` + `natOutgoing:
  Disabled` для IPv6 pool;
* добавить `BGPConfiguration` + `BGPPeer` CR'ы в чарт, peering к
  capi-int LXD bridge gateway IPv6 (`fd42:77:1::1`);
* на host'е поднять BGP daemon (FRR / Bird / GoBGP), принимающий
  advertise'ы от Pod CIDR `fd42:77:2::/56` и устанавливающий matching
  kernel routes на capi-int bridge.

**Trade-off.** Возвращает per-Pod traceability ценой:
* BGP infrastructure dependency на host'е, которая сейчас substrate-
  policy-wise отсутствует («no BGP infra на CAPN/LXD lab»);
* дополнительный host-level service (BGP daemon), который нужно
  жизненно поддерживать.

**Прерeq.** Никаких других backlog item'ов не блокирует; полностью
независимый.

---

## e2e-local HA pair assertions extension

**Цель.** Расширить `tests/molecule/e2e-local/verify.yml` явными
assertion'ами, проверяющими HA pair contract end-to-end — пока
verify покрывает только `helm test` chart'ов и runner-side `kubectl
get nodes`, не сами реплики / leader election.

**Что добавляется в verify.yml.**
* Для каждого Deployment / StatefulSet / DaemonSet с `replicas >= 2`
  (calico-kube-controllers, calico-apiserver, calico-typha, metallb-
  speaker DS на multi-worker'ах):
  * `kubectl get deploy/ds <X> -o jsonpath='{.status.readyReplicas}'`
    == `.status.replicas`;
  * `kubectl get pods -l <selector> -o jsonpath='{range .items[*]}
    {.spec.nodeName}{"\n"}{end}' | sort -u | wc -l` == 2 (реплики на
    разных worker-нодах);
* для leader-elected компонентов (metallb-controller singleton по
  upstream дизайну, calico-kube-controllers HA-eligible) — ровно
  один holder lease через `coordination.k8s.io/v1 Lease` CR'ы или
  parsing logs/leader-config, второй pod в standby.

**Trade-off.** Verify становится длиннее (~10-15 дополнительных
тасков), но это honest acceptance вместо implicit-trust в `helm
test'ах chart'ов.

**Прерeq.** Replica counts + pod-anti-affinity уже зашиты в chart
templates / values; этот item только **верифицирует**, что declared
контракт реально соблюдается на runtime'е.

---

## Multi-MachineDeployment topology в charts

**Цель.** Поддержать множественные `MachineDeployment`'ы на Cluster
CR — heterogeneous worker pools (CPU vs GPU passthrough vs storage-
heavy), per-pool scaling, per-pool kubernetes version overrides для
rolling cluster upgrades.

**Что меняется.**
* `charts/capi-cluster-class/`: `clusterClass.workers.machineDeployments`
  становится list-of-objects вместо single hardcoded `class: md-0`,
  каждый class приносит свой `KubeadmConfigTemplate` +
  `LXCMachineTemplate` (или shares, если pool отличается только
  topology values);
* `charts/capi-workload-cluster/`: `topology.workers.machineDeployments`
  — list с per-class metadata (replicas, optional version override,
  optional taints/labels);
* substrate-required hardcoded guard (имя class'а `md-0` сейчас
  жёстко зашито как chart-level invariant) переезжает на per-class
  basis с `values.schema.json` validation;
* `terraform/modules/workload_cluster/`: новые input'ы для multi-MD
  declaration (вероятно, `workers_pools = [{class, replicas,
  image_ref, ...}]` list).

**Use case'ы.** GPU-passthrough workers (CAPN device passthrough);
storage-heavy workers (extra block device attached, large root);
per-pool kubernetes version (rolling upgrade pool A first, then B);
per-pool taints/labels для nodeSelector'а в workload Pods.

**Прерeq.** Полностью additive — single-MD path остаётся default
(один class `md-0`, замапленный на список из одного объекта).

---

## Day-1 addons backlog

**Цель.** Базовые production addons за пределами CNI + MetalLB.
Каждый — отдельный sub-backlog item; реализуется независимо как
новый chart wrapper в `charts/`.

* **Ingress controller** — выбор upstream (ingress-nginx / cilium-
  ingress / traefik) через новый chart `charts/ingress-<impl>/`.
  Substrate prereq: MetalLB `IPAddressPool` для ingress VIP уже есть.
* **Storage provisioner** — для PVC'ов в workload cluster'ах.
  Кандидаты: topolvm (LVM-backed), local-path-provisioner (single-
  node lab path), rook-ceph (overengineered для lab но canonical).
* **cert-manager + public TLS** — для ingress'ов. cert-manager уже
  установлен как dependency CAPI (`clusterctl init`); этот item =
  expose cert-manager API + ClusterIssuer'ы для consumer'ских
  workload'ов, не для CAPI internal use.
* **Production observability stack** — Prometheus / VictoriaMetrics +
  Grafana + Loki / Vector. Отдельный Helm chart bundle. Включает
  scrape configuration для CAPI controllers, MetalLB metrics, Calico
  Felix metrics, etc.

**Trade-off.** Каждый addon усложняет helm test scope (нужно
проверять что новый chart Pods могут schedule + reach upstream
services).

---

## Cluster lifecycle ops

**Цель.** Day-2 ops для workload и mgmt cluster'ов, выходящие за
пределы create / destroy.

* **etcd backup / restore** — для self-hosted mgmt cluster'а (CP
  etcd содержит CAPI state — потеря = потеря всех Cluster CR'ов
  невосстановимо). Кандидаты подхода:
  * external etcd snapshot job (cron CronJob внутри cluster'а с
    PVC offload через storage provisioner);
  * etcdadm-controller / etcd-backup-restore upstream chart;
  * CAPI's own clusterctl backup feature (если выйдет в release
    branch'е к моменту реализации).
* **Automated Kubernetes upgrades через CAPI rollout** — rolling
  KCP upgrades + MachineDeployment per-pool version bumps. CAPI
  v1beta2 ClusterClass поддерживает `topology.version` per-Cluster
  + per-MD overrides; пользователю нужно только bump kubernetes
  version pin + chart `Chart.yaml.version` → rolling upgrade
  автоматически. Step item = test scenario scripted upgrade path
  (with rollback на gate failure).

**Trade-off.** Backup/restore требует storage provisioner (см. Day-1
addons выше) — upgrades полностью независимы.

---

## Hosted CI path без local runner

**Цель.** Запуск e2e-local в hosted CI environment (GitHub Actions /
GitLab CI / etc.), не требуя оператора с physical Vagrant + libvirt
host'ом.

**Подход.**
* nested virtualization: host runner поднимает KVM nested → Vagrant
  libvirt provider. GitHub Actions Linux runners поддерживают KVM
  через `setup-kvm` action или manual `apt install qemu-kvm`. Cost:
  e2e цикл ~30 мин, что приемлемо для PR validation;
* alternative: bare LXD host в hosted-CI runner (запуск всего
  substrate + bootstrap k3s + workload без promiscuous mode и без
  libvirt) — меньше overhead, но требует privileged host access
  который GitHub Actions runners не дают.

**Trade-off.** Sustained CI cost (CPU minutes + KVM setup time on
cold runner). Гарантия: каждый PR проходит full e2e перед merge.

---

## BGP/routed external network design

**Цель.** Полная пересборка external network plane (eth1 / br-ext6
сегмент, MetalLB delivery model) с BGP peering к upstream ISP / DC
fabric вместо текущего radvd-mock external IPv6 segment'а.

**Что меняется.**
* `ansible/roles/lxd_host/`, `ansible/roles/lxd_network_int_managed/`,
  `ansible/roles/lxd_profiles/` — eth1 bridge/uplink configuration
  переезжает на BGP-routed model;
* MetalLB `BGPAdvertisement` вместо `L2Advertisement` (или mix);
* возможно отдельный BGP daemon на host'е если CAPN doesn't have
  native BGP integration;
* test harness `tests/molecule/shared/tasks/ext6-ra-source.yml`
  переписывается под BGP peer instead of radvd (или пара paths,
  consumer выбирает).

**Trade-off.** Существенно больше operational complexity, но
canonical для real DC deployment'ов; lab остаётся на radvd-mock
для simplicity.

**Зависимости.** Перекрывается с *Pod IPv6 routing — Calico BGP*
выше: если оба item'а реализуются, BGP infra консолидируется в один
host-level daemon.
