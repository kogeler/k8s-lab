# Stage 2 — backlog

List of features that may be implemented on top of the working
substrate of the repo. Each item is opt-in, independent of the others,
and requires its own design step + implementation + lint/test cycle.

Stage 2 file lineup (§N is assigned when a backlog item is
implemented as a numbered Step, not before):

```
PLAN-stage2-common.md ............ backlog (this file)
PLAN-stage2-1.md ................. §23  (Step 18 — hosted CI path)
```

Forbidden:
* to regress substrate invariants fixed in the repo code
  (unprivileged-only LXC, helm-first delivery of K8s objects, mandatory
  CAPI bootstrap-and-pivot flow, dual-stack networking baseline,
  CAPI/CAPN version pins) — these are closed architectural decisions,
  not switchable options;
* to implement a backlog item "quickly" without a separate design step,
  its own Step N marker, plan rewrite and Molecule e2e regression
  on a fresh VM.

Items have no fixed order of implementation.

## Completed Stage 2 items

* Step 18 — **Hosted CI path on GitHub Actions** (`§23`, see
  `PLAN-stage2-1.md`). Closes the *"Hosted CI path without local
  runner"* item that previously lived in this backlog.

---

## Pod IPv6 routing — Calico BGP route advertisement

**Goal.** Replace the current Pod→substrate IPv6 SNAT (`natOutgoing:
Enabled` for the IPv6 pool in `charts/cni-calico/templates/installation.yaml`)
with honest Layer-3 routing, in order to bring back per-Pod traceability in
substrate-side access logs (haproxy LB on capi-int, LXD daemon HTTPS).

**What changes.**
* `charts/cni-calico/templates/installation.yaml`: flip
  `calicoNetwork.bgp` from `Disabled` to `Enabled` + `natOutgoing:
  Disabled` for the IPv6 pool;
* add `BGPConfiguration` + `BGPPeer` CRs to the chart, peering with the
  capi-int LXD bridge gateway IPv6 (`fd42:77:1::1`);
* on the host bring up a BGP daemon (FRR / Bird / GoBGP) that accepts
  advertisements from the Pod CIDR `fd42:77:2::/56` and installs matching
  kernel routes on the capi-int bridge.

**Trade-off.** Brings back per-Pod traceability at the cost of:
* a BGP infrastructure dependency on the host, which is currently absent
  from substrate policy ("no BGP infra on the CAPN/LXD lab");
* an additional host-level service (BGP daemon) that must be kept
  alive operationally.

**Prerequisite.** Does not block any other backlog items; fully
independent.

---

## e2e-local HA pair assertions extension

**Goal.** Extend `tests/molecule/e2e-local/verify.yml` with explicit
assertions verifying the HA pair contract end-to-end — currently
verify only covers `helm test` of the charts and runner-side `kubectl
get nodes`, not the replicas themselves / leader election.

**What is added to verify.yml.**
* For each Deployment / StatefulSet / DaemonSet with `replicas >= 2`
  (calico-kube-controllers, calico-apiserver, calico-typha, metallb-
  speaker DS on multi-worker setups):
  * `kubectl get deploy/ds <X> -o jsonpath='{.status.readyReplicas}'`
    == `.status.replicas`;
  * `kubectl get pods -l <selector> -o jsonpath='{range .items[*]}
    {.spec.nodeName}{"\n"}{end}' | sort -u | wc -l` == 2 (replicas on
    different worker nodes);
* for leader-elected components (metallb-controller singleton by
  upstream design, calico-kube-controllers HA-eligible) — exactly
  one holder lease via `coordination.k8s.io/v1 Lease` CRs or
  parsing logs/leader-config, the second pod in standby.

**Trade-off.** Verify becomes longer (~10-15 additional tasks),
but this is honest acceptance instead of implicit-trust in the charts'
`helm test`s.

**Prerequisite.** Replica counts + pod-anti-affinity are already baked
into chart templates / values; this item only **verifies** that the declared
contract is actually honored at runtime.

---

## Multi-MachineDeployment topology in charts

**Goal.** Support multiple `MachineDeployment`s on the Cluster
CR — heterogeneous worker pools (CPU vs GPU passthrough vs storage-
heavy), per-pool scaling, per-pool kubernetes version overrides for
rolling cluster upgrades.

**What changes.**
* `charts/capi-cluster-class/`: `clusterClass.workers.machineDeployments`
  becomes a list-of-objects instead of a single hardcoded `class: md-0`,
  each class brings its own `KubeadmConfigTemplate` +
  `LXCMachineTemplate` (or shares them, if a pool differs only in
  topology values);
* `charts/capi-workload-cluster/`: `topology.workers.machineDeployments`
  — a list with per-class metadata (replicas, optional version override,
  optional taints/labels);
* the substrate-required hardcoded guard (the class name `md-0` is currently
  hardcoded as a chart-level invariant) moves to a per-class
  basis with `values.schema.json` validation;
* `terraform/modules/workload_cluster/`: new inputs for multi-MD
  declaration (probably `workers_pools = [{class, replicas,
  image_ref, ...}]` list).

**Use cases.** GPU-passthrough workers (CAPN device passthrough);
storage-heavy workers (extra block device attached, large root);
per-pool kubernetes version (rolling upgrade pool A first, then B);
per-pool taints/labels for nodeSelector in workload Pods.

**Prerequisite.** Fully additive — the single-MD path remains the default
(one class `md-0`, mapped to a list of one object).

---

## Day-1 addons backlog

**Goal.** Base production addons beyond CNI + MetalLB.
Each is a separate sub-backlog item; implemented independently as
a new chart wrapper in `charts/`.

* **Ingress controller** — choice of upstream (ingress-nginx / cilium-
  ingress / traefik) via a new chart `charts/ingress-<impl>/`.
  Substrate prerequisite: a MetalLB `IPAddressPool` for the ingress VIP is already in place.
* **Storage provisioner** — for PVCs in workload clusters.
  Candidates: topolvm (LVM-backed), local-path-provisioner (single-
  node lab path), rook-ceph (overengineered for a lab but canonical).
* **cert-manager + public TLS** — for ingresses. cert-manager is already
  installed as a CAPI dependency (`clusterctl init`); this item =
  expose the cert-manager API + ClusterIssuers for consumer
  workloads, not for CAPI internal use.
* **Production observability stack** — Prometheus / VictoriaMetrics +
  Grafana + Loki / Vector. A separate Helm chart bundle. Includes
  scrape configuration for CAPI controllers, MetalLB metrics, Calico
  Felix metrics, etc.

**Trade-off.** Each addon expands helm test scope (it is necessary to
verify that the new chart's Pods can schedule + reach upstream
services).

---

## Cluster lifecycle ops

**Goal.** Day-2 ops for workload and mgmt clusters, going beyond
create / destroy.

* **etcd backup / restore** — for the self-hosted mgmt cluster (the CP
  etcd contains CAPI state — loss = irrecoverable loss of all Cluster CRs).
  Candidate approaches:
  * external etcd snapshot job (a cron CronJob inside the cluster with
    PVC offload via the storage provisioner);
  * etcdadm-controller / etcd-backup-restore upstream chart;
  * CAPI's own clusterctl backup feature (if it ships in a release
    branch by the time of implementation).
* **Automated Kubernetes upgrades via CAPI rollout** — rolling
  KCP upgrades + MachineDeployment per-pool version bumps. CAPI
  v1beta2 ClusterClass supports `topology.version` per-Cluster
  + per-MD overrides; the user only needs to bump the kubernetes
  version pin + chart `Chart.yaml.version` → rolling upgrade
  happens automatically. The Step item = a test scenario with a scripted upgrade path
  (with rollback on gate failure).

**Trade-off.** Backup/restore requires a storage provisioner (see Day-1
addons above) — upgrades are fully independent.

---

## BGP/routed external network design

**Goal.** Complete rebuild of the external network plane (eth1 / br-ext6
segment, MetalLB delivery model) with BGP peering to the upstream ISP / DC
fabric instead of the current radvd-mock external IPv6 segment.

**What changes.**
* `ansible/roles/lxd_host/`, `ansible/roles/lxd_network_int_managed/`,
  `ansible/roles/lxd_profiles/` — eth1 bridge/uplink configuration
  moves to a BGP-routed model;
* MetalLB `BGPAdvertisement` instead of `L2Advertisement` (or a mix);
* possibly a separate BGP daemon on the host if CAPN does not have
  native BGP integration;
* the test harness `tests/molecule/shared/tasks/ext6-ra-source.yml`
  is rewritten for a BGP peer instead of radvd (or a pair of paths,
  the consumer chooses).

**Trade-off.** Significantly more operational complexity, but
canonical for real DC deployments; the lab stays on radvd-mock
for simplicity.

**Dependencies.** Overlaps with *Pod IPv6 routing — Calico BGP*
above: if both items are implemented, the BGP infra consolidates into a single
host-level daemon.
