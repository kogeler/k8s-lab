# 02 — Architecture

This chapter describes the architecture in increasing depth: the
single-host model, the dual-NIC node design, the canonical
bootstrap-and-pivot flow, and the strict ownership split between
Ansible, Terraform, and Helm.

For the *why* behind each decision, see plan `§2`–`§6`.

---

## 1. The one-host model

Every component of a k8s-lab deployment runs on a single Debian 13
bare-metal host:

- **The host itself** runs only LXD (installed via snap) and a Linux
  bridge for the external IPv6 segment. No Docker, no host-level
  Kubernetes, no node agent on the host.
- **All Kubernetes nodes are unprivileged LXC system containers**
  inside one LXD project (`capi-lab`).
- **The bootstrap management cluster** is a single-node `k3s` instance
  running inside *another* LXC container; it lives only long enough to
  bring up the self-hosted management cluster, then is torn down.
- **Cluster networking** uses two host-side network planes:
  `br-ext6` (external IPv6 ingress) and `capi-int` (internal
  dual-stack control / egress). Each Kubernetes node gets one
  interface on each plane.

The single host is the failure domain. The architecture does **not**
attempt to provide HA across hosts — that is outside the model.

---

## 2. Two clusters, not one

Although the project is called "k8s-lab" (singular), every running
deployment ends up with **two** Kubernetes clusters on the same host:

| Cluster | Role | Default size | Lifetime |
|---------|------|-------------|----------|
| `mgmt-1` | Self-hosted CAPI **management** cluster — runs the CAPI / CABPK / KCP / CAPN controllers that provision and reconcile the workload cluster. | 1 CP + 2 worker (default) | Long-lived. Created during canonical flow, destroyed on full teardown. |
| `lab-default` (default name) | **Workload** cluster — the cluster where you actually run user workloads. | 3 CP + 2 worker (default) | Created on `make deploy-workload` (or in canonical e2e). May be destroyed and recreated independently. |

The mgmt cluster is *self-hosted*: after pivot it manages itself plus
all workload clusters. There can be **multiple workload clusters**
managed by the same mgmt — see [`11-operations.md`](11-operations.md).

The bootstrap k3s LXC instance (`capi-bootstrap-0`) is **not** a third
cluster; it is transient scaffolding that exists only between
`bootstrap_clusterctl` and `cleanup_bootstrap`.

---

## 3. The canonical flow

The plan fixes a single linear flow with **no dispatch branches**, no
"with/without pivot" toggle. Bootstrap k3s exists only to host the
mgmt-1 Cluster CR long enough for `clusterctl init` and `clusterctl
move` to migrate management responsibility onto mgmt-1. After that the
bootstrap LXC is destroyed.

### 3.1. The nine steps

```
┌─[ host substrate ]────────────────────────────────────────────┐
│                                                                │
│ 1. Substrate + bootstrap k3s                                   │
│    base_system → lxd_host → lxd_project → lxd_storage_pools    │
│    → lxd_network_int_managed → lxd_profiles                    │
│    → lxd_bootstrap_instance → binary_fetch → bootstrap_k3s     │
│    → bootstrap_clusterctl → bootstrap_capn_secret              │
│    → export_artifacts                                          │
│                                                                │
│ 2. mgmt-1 Cluster CR on bootstrap                              │
│    helm install capi-cluster-class + capi-workload-cluster     │
│    (mgmt-topology values) on bootstrap k3s                     │
│    CAPN provisions LXC nodes and a haproxy LB instance         │
│                                                                │
│ 3. CNI + MetalLB on mgmt-1                                     │
│    helm install cni-calico → poll Nodes Ready                  │
│    → helm install metallb + metallb-config                     │
│                                                                │
│ 4. Gate A/B helm tests on mgmt-1                               │
│    helm test on three releases — gate before pivot             │
│                                                                │
│ 5. Pivot: clusterctl init + move bootstrap → mgmt-1            │
│    pivot_clusterctl_move role                                  │
│                                                                │
│ 6. Re-emit .artifacts/mgmt.kubeconfig                          │
│    second include of export_artifacts on mgmt-1 creds          │
│                                                                │
│ 7. cleanup_bootstrap                                           │
│    destroy capi-bootstrap-0                                    │
│                                                                │
│ 8. Workload Cluster + add-ons on mgmt-1                        │
│    same helm releases, workload-topology values, against       │
│    self-hosted mgmt-1                                          │
│                                                                │
│ 9. Gate A/B helm tests on workload                             │
│    final acceptance — chart-side helm tests + external curl    │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

After step 9: bootstrap k3s is gone, mgmt-1 is self-hosted with CAPI
controllers + Calico + MetalLB, and `lab-default` runs as a workload
under mgmt-1's management. See plan `§3.1` for the verbatim
specification.

### 3.2. Driver

End-to-end, the canonical flow is implemented as a single Molecule
scenario `tests/molecule/e2e-local/converge.yml` + `verify.yml`,
driven by `make test-local-e2e`. There are **no standalone Make
targets** for individual phases of the canonical flow; each stage is
either an `include_role:` of an existing role
(`export_artifacts`, `pivot_clusterctl_move`, `cleanup_bootstrap`) or
a native `kubernetes.core.helm` task in the playbook.

`make deploy-workload` is a **separate Terraform-driven path** that
creates *additional* workload clusters on an already-self-hosted
mgmt-1. It does *not* run bootstrap → pivot → cleanup; that sequence
is exclusively the e2e-local Molecule scenario or a consumer-repo
playbook with the same role chain. See plan `§3.2`.

### 3.3. Why pivot is mandatory

Helm release storage (`sh.helm.release.v1.<release>.v1` Secrets)
**does not move with `clusterctl move`**. Only CAPI CRs move. If a
workload Cluster CR were created on bootstrap, its helm storage would
stay on bootstrap and disappear with `cleanup_bootstrap`, leaving an
orphaned Cluster CR on the target mgmt with no owning helm release.
`terraform destroy` and `helm uninstall` after that fail with `release
not found`.

Solution: **never create workload Cluster CRs on bootstrap**. The
only CR on bootstrap is the mgmt-1 Cluster CR itself, which is
transient and lives entirely within the bootstrap → pivot →
cleanup window. All workload clusters are created **after** pivot,
on the self-hosted mgmt-1, where helm storage and the Cluster CR
share the same cluster.

`clusterctl init` and `clusterctl move` are the official CAPI
bootstrap-and-pivot flow. See plan `§3.3`.

### 3.4. Network surface asymmetry between bootstrap and self-hosted

A subtle but load-bearing detail: the network surface of the CAPI
controllers **changes** between bootstrap and self-hosted.

- On bootstrap, CAPI / CAPN controllers run as **k3s server processes
  in host-network mode**. Their source IP is the bootstrap LXC
  container's `eth0` IPv6 in `capi-int`.
- On mgmt-1, the same controllers run as **Pods**. Their source IP is
  a Calico-managed Pod IPv6 in `fd42:77:2::/56`.

Any feature that depends on outbound reachability from the controller
to the substrate (LXD daemon HTTPS, haproxy LB instance) must work in
*both* network contexts. The canonical example is Pod→substrate IPv6
SNAT (`natOutgoing: Enabled` in the Calico Installation), which is
invisible pre-pivot and required post-pivot. This is why the
canonical flow **always exercises pivot** — it is not optional.

See plan `§3.3` "Network surface asymmetry".

---

## 4. Two-NIC node design

Each Kubernetes node has two interfaces, with strict role separation:

```
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes node (LXC system container)                      │
│                                                             │
│  eth0 = internal             eth1 = external               │
│  ────────────────             ──────────────                │
│   • dual-stack                 • IPv6-only                  │
│   • kubelet --node-ip          • global IPv6 from RA        │
│   • default route              • NOT default route          │
│   • pod/CP/admin/egress        • ingress-only               │
│   • Pod CIDR underlay          • NodePort + MetalLB VIP     │
│   • on capi-int                • on br-ext6                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 4.1. Why split

Mixing ingress and egress on the same NIC creates two operational
risks:

1. The external NIC could become "the main lifeline network" —
   kubelet, kube-proxy, regular pod egress would route through the
   provider's IPv6 segment, which is wrong for both bandwidth and
   security.
2. NodePort and MetalLB VIPs would land on the wrong interface (the
   internal one), breaking external reachability.

By making `eth0` the underlay (default route, kubelet node IP,
egress) and `eth1` the dedicated ingress NIC, both problems disappear.

### 4.2. Internal plane (`eth0` / `capi-int`)

- LXD-managed bridge `capi-int`.
- Dual-stack: IPv4 `10.77.0.0/24` + IPv6 ULA `fd42:77:1::/64`.
- `dnsmasq` for DHCP, DNS, IPv6 RA (stateful for guests that need it).
- NAT44/NAT66 via the host. Container egress to the outside Internet
  goes here.
- `kubelet --node-ip=<v4>,<v6>` is set explicitly to avoid the
  dual-stack node-IP autodetection ambiguity (plan `§5.3`).

### 4.3. External plane (`eth1` / `br-ext6`)

- Linux bridge `br-ext6` on the host, attached to the host's uplink.
- Carries the operator-provided **external IPv6 /64**.
- Provider router sends IPv6 RA on this segment; node `eth1` accepts
  RA and SLAACs a global IPv6 — but **does not** import the default
  route (`UseGateway=no` in systemd-networkd).
- `NodePort` accepts only on these external IPv6 addresses
  (`kube-proxy --nodeport-addresses=<external IPv6 CIDR>`).
- MetalLB IPv6 VIPs are announced on `eth1` only
  (`L2Advertisement.spec.interfaces: [eth1]` + node selectors).

### 4.4. RA reception baseline (delivered by `charts/capi-cluster-class`)

Every CAPN-spawned node needs `eth1` configured **before** kubelet,
kube-proxy, and MetalLB speaker start. This is delivered through
`KubeadmConfigSpec.files` + `preKubeadmCommands` (so it lands as
cloud-init `write_files` on first boot):

- `/etc/sysctl.d/99-capi-ra.conf` — `net.ipv6.conf.eth1.{disable_ipv6=0,
  accept_ra=2, accept_ra_defrtr=1}`. `accept_ra=2` is required because
  workload nodes run `forwarding=1` for pod networking, and the kernel
  default `accept_ra=1` ignores RAs on a forwarding host.
- `/etc/systemd/network/30-capi-ext.network` — `[Match] Name=eth1
  [Network] DHCP=no LinkLocalAddressing=ipv6 IPv6AcceptRA=yes`.
- `preKubeadmCommands` runs `sysctl --load` + `networkctl reload` so
  the configuration is alive before kubeadm starts.

This is why **every consumer image must be cloud-init capable** — see
plan `§2.10`.

### 4.5. Local-harness substitute for the upstream RA

In the local Vagrant lab there is no provider router sending RAs.
Instead, an in-VM `radvd` listens on a veth peer
(`ext6-ra-peer`) attached to `br-ext6` and announces
`2001:db8:42:100::/64`. This is delivered by
`tests/molecule/shared/tasks/ext6-ra-source.yml` — see plan `§9.2`
(Step 9 pivot section). The RA reception baseline on the node side is
identical between local and prod; only the RA *source* differs.

---

## 5. Layer ownership — Ansible / Terraform / Helm

The plan fixes ownership boundaries with no overlap (plan `§2.7` and
`§2.9`):

```
┌──────────────┬─────────────────────────────────────────────────────┐
│ Ansible      │ Host bootstrap, LXD substrate, bootstrap k3s,      │
│  (roles)     │ clusterctl init, CAPN identity Secret,             │
│              │ artefact export, pivot orchestration,              │
│              │ cleanup. NEVER touches Kubernetes objects on       │
│              │ workload/mgmt clusters in create/update mode       │
│              │ (read-side k8s_info is allowed).                   │
├──────────────┼─────────────────────────────────────────────────────┤
│ Terraform    │ The Terraform helm provider drives every helm      │
│  (modules)   │ release that creates a CR on a Kubernetes cluster: │
│              │ ClusterClass, Cluster CR, Calico, MetalLB,         │
│              │ MetalLB config + Gate A/B helm tests. Single       │
│              │ module (`workload_cluster`) installs the whole     │
│              │ stack in one apply.                                │
├──────────────┼─────────────────────────────────────────────────────┤
│ Helm         │ All Kubernetes objects live in `charts/`:          │
│  (charts)    │ capi-cluster-class, capi-workload-cluster,         │
│              │ cni-calico, metallb, metallb-config. No raw YAML   │
│              │ under any `manifests/` directory; no               │
│              │ `kubectl apply -f`; no `kubernetes_manifest`.      │
└──────────────┴─────────────────────────────────────────────────────┘
```

### 5.1. Read-side exceptions

The strict "no Kubernetes mutation from Ansible" rule has read-side
exceptions:

- `kubernetes.core.k8s_info` — used in role `bootstrap_clusterctl` to
  poll Provider CRs and Deployments while waiting for `clusterctl
  init` to settle, and in `pivot_clusterctl_move` for similar polling.
- `kubernetes.core.k8s` with `state=present` — **forbidden** for
  Kubernetes objects in create/update mode. The exception is the CAPN
  identity `Secret` (created by `bootstrap_capn_secret`), which is a
  cross-cluster identity artefact, not a deployment object.
- The `hashicorp/kubernetes` Terraform provider — allowed only for
  data lookups (`kubernetes_resources`, `kubernetes_resource`), never
  for mutating resources.

### 5.2. Why so strict

This rule eliminates an entire class of bugs that surface only on
re-apply:

- Two delivery paths competing for the same object → SSA ownership
  flip-flop.
- Ansible-applied values overwritten by the Helm controller →
  drift the next time `helm upgrade` runs.
- `clusterctl move` cannot follow ad-hoc objects that are not in the
  CAPI graph → orphaned resources after pivot.

By insisting on Helm as the only mutation channel, every
post-deployment object can be rolled forward by `helm upgrade` and
rolled back by `helm uninstall`. CAPI immutability is handled
separately via the chart-version-as-CR-name pattern (see §6 below).

---

## 6. Chart-version-as-CR-name pattern

CAPI's admission webhook forbids mutating most fields of a referenced
`ClusterClass` or `*Template` CR. A naïve `helm upgrade` with changed
values fails on `admission webhook denied: field is immutable`.

The pattern that solves this (plan `§2.9`, `§12.10`):

```yaml
# charts/capi-cluster-class/templates/clusterclass.yaml
metadata:
  name: {{ include "capi-cluster-class.fullname" . }}-{{ .Chart.Version | replace "." "-" }}
```

- Bumping `Chart.Version` → new chart version → new CR names →
  Helm creates a fresh ClusterClass + *Templates and a new
  Cluster CR reference.
- The old objects continue to live until a deliberate cleanup.
- `helm rollback` to the previous chart version restores the previous
  object set.

The workload-cluster chart references the ClusterClass through the
same formula by reading
`Chart.yaml.annotations.k8s-lab.io/capi-cluster-class-chart-version`;
the Terraform module only reproduces the slug for its
`cluster_class_name` output.

---

## 7. Bootstrap → mgmt-1 → workload — concrete object lifecycle

This section traces what objects exist where, and when, so that the
pivot is not magic.

### 7.1. After Phase 4 (substrate + bootstrap k3s + clusterctl init)

```
host (Debian 13)
├── /opt/capi-lab/bin/{kubectl,clusterctl,k3s}        # binaries
├── /var/snap/lxd/common/lxd/                          # LXD data dir
└── LXD project "capi-lab"
    └── capi-bootstrap-0   (LXC instance)
        ├── k3s server                 listening on 6443
        ├── CAPI controllers           ns=capi-system
        ├── CABPK controllers          ns=capi-kubeadm-bootstrap-system
        ├── KCP controllers            ns=capi-kubeadm-control-plane-system
        └── CAPN controller            ns=capn-system
```

The runner has `.artifacts/mgmt.kubeconfig` pointing at
`https://<bootstrap-eth0-ipv4>:6443` (or via LXD proxy at
`https://<host-ip>:16443`).

### 7.2. After Phase 5 (mgmt-1 helm install + Gate A/B)

```
host (Debian 13)
└── LXD project "capi-lab"
    ├── capi-bootstrap-0    (still alive)
    │   └── (same as above)
    │   PLUS Cluster CR mgmt-1 in ns=capi-clusters
    │
    ├── mgmt-1-CP-0         (LXC, kubeadm CP)
    ├── mgmt-1-W-0          (LXC, kubeadm worker)
    ├── mgmt-1-W-1          (LXC, kubeadm worker)
    └── mgmt-1-LB-0         (LXC, haproxy for kube-apiserver)
```

Helm releases on bootstrap k3s:

- `mgmt-1-class` (ClusterClass + *Templates; rendered CR names carry the chart-version slug)
- `mgmt-1` (Cluster CR)
- `cni-calico` on mgmt-1
- `metallb` + `metallb-config` on mgmt-1

### 7.3. After Phase 7 (pivot + cleanup_bootstrap)

```
host (Debian 13)
└── LXD project "capi-lab"
    ├── mgmt-1-CP-0         (now SELF-HOSTING the CAPI controllers)
    ├── mgmt-1-W-0
    ├── mgmt-1-W-1
    └── mgmt-1-LB-0
```

The bootstrap LXC is gone. Helm releases that ran on bootstrap k3s are
gone too; CAPI CRs migrated to mgmt-1 via `clusterctl move`. Helm
releases on mgmt-1 (Calico, MetalLB) are still there because they were
created against mgmt-1's API, not bootstrap's.

The runner's `.artifacts/mgmt.kubeconfig` was rewritten in place by
the second `export_artifacts` include and now points at mgmt-1's
kube-apiserver.

### 7.4. After Phase 9 (workload helm install)

```
host (Debian 13)
└── LXD project "capi-lab"
    ├── mgmt-1-CP-0          (self-hosted mgmt)
    ├── mgmt-1-W-{0,1}
    ├── mgmt-1-LB-0
    │
    ├── lab-default-CP-{0,1,2}     (workload CPs)
    ├── lab-default-W-{0,1}        (workload workers)
    └── lab-default-LB-0           (workload haproxy)
```

Helm releases on mgmt-1 (in addition to its own Calico + MetalLB):

- `lab-default-class`  (workload ClusterClass; rendered CR names carry the chart-version slug)
- `lab-default`        (workload Cluster CR)

Helm releases on `lab-default`:

- `cni-calico`
- `metallb`
- `metallb-config`

This is the steady state of a fully deployed lab.

---

## 8. The acceptance gates A and B

Two gates fail the deploy fast if the data plane is not viable. The
chart-side parts are implemented as `helm.sh/hook: test` Pods. The
Terraform workload path invokes them through `null_resource` +
`local-exec helm test`; the Ansible e2e path invokes the same hooks
with explicit `helm test` commands.

### 8.1. Gate B — CNI viability

Lives in `charts/cni-calico/templates/tests/cni-ready.yaml`. After the
Calico install, the hook runs a probe pair on two distinct workers
(via `requiredDuringScheduling` pod-anti-affinity) and asserts:

- nodes become `Ready`;
- pod-to-pod direct reachability works in both address families;
- ClusterIP service routing works.

If Gate B fails, `terraform apply` fails. The fallback is **not** a
runtime CNI swap (this is closed by design); the operator must
investigate the root cause and, if necessary, design a swap to a
different CNI as a deliberate change.

### 8.2. Gate A — External L2 viability

Lives in `charts/metallb-config/templates/tests/metallb-vip.yaml` plus
a verify-side external curl. Acceptance is dual: a chart-side helm
test PASS *and* an external HTTP GET to the announced VIP from a
host-side / probe-side endpoint. The chart-side hook deploys a real
nginx demo Service `type=LoadBalancer` (`ipFamilies: [IPv6]`),
asserts the VIP is allocated and in-pool, and runs an in-cluster HTTP
probe. The external curl runs from the Vagrant VM via `ext6-ra-peer`
in local mode, or from an external probe in production.

If Gate A fails, the deploy is stopped. MetalLB without working L2
NDP is useless; the alternative routes (BGP, proxy-NDP) are consumer
decisions, not Stage 1 scope.

---

## 9. Where to read more

| Architectural topic | Plan section |
|---------------------|--------------|
| Single canonical flow | `§3` |
| Network architecture | `§4` |
| Networking contract  | `§5` |
| Validation gates     | `§6` |
| Repository layout    | `§7` |
| Typed variables      | `§8` |
| Local development    | `§9` |
| Ownership rules      | `§2.7` |
| LXC mode (unprivileged-only) | `§2.8` |
| Helm-first delivery  | `§2.9` |
| Image policy         | `§2.10` |
| Risks & mitigation   | `§12` |

The plan files live at `plans/PLAN-stage1-*.md` (English).
