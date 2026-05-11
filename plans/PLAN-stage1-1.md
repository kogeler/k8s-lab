This file owns §13..§14: completed Ansible roles (§13) and
completed phases (§14). Stage 1 closure + self-review + final
recommendation live in PLAN-stage1-7.md (§20..§22). The §N numbering
is continuous across all plan files; cross-references of the form
`§<number>` are valid without naming the file — see the
`PLAN-stage1-common.md` header for the full file lineup.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)  <-- this file
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (workload_cluster TF module)
PLAN-stage1-4.md ................. §17      (Helm test contracts — Gate A + Gate B chart-side specs)
PLAN-stage1-5.md ................. §18      (pivot mgmt-1 → self-hosted)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 closure + self-review + recommendation)
```

---

# 13. Completed Ansible roles

This section covers the Stage 1 Ansible roles that are already implemented and
have been run end-to-end in the local Vagrant/libvirt loop as of
Step 17 (2026-04-28). Step 16/17 did not introduce new Ansible roles and did not
modify existing ones — Step 16 shipped the Phase 5 TF module + fixture,
Step 17 cleaned the module of bash scripts by moving readiness gating into a
chart hook (see §14.7 / §16.3 / §16.4 / §16.5 / §16.6):

* §13.1 `base_system` (Step 1 + Step 5 required-values refactor);
* §13.2 `lxd_host` (Step 2);
* §13.3 `lxd_project` (Step 3 + Step 4 substrate extension + Step 7
  `restricted.devices.proxy` allow + **Step 11 `restricted.devices.disk:
  allow` + `restricted.devices.disk.paths: /boot` for kubeadm
  SystemVerification under unprivileged-LXC**);
* §13.4 `lxd_storage_pools` (Step 3 + Step 5 required-config refactor);
* §13.5 `lxd_network_int_managed` (Step 3 + Step 5 required-config refactor);
* §13.6 `lxd_profiles` (Step 3 lean baseline + Step 4 full CAPN
  unprivileged kubeadm baseline + **Step 11 `host-boot` disk device
  on capi-controlplane (read-only `/boot` for kubeadm
  SystemVerification on unprivileged-LXC nodes) + Step 12 the same
  `host-boot` device on capi-worker — `kubeadm join` preflight on
  the worker reads `/boot/config-<uname-r>` from the same code branch as
  `kubeadm init` on the CP + Step 13 extension of
  `linux.kernel_modules` on capi-controlplane/capi-worker:
  added `nf_tables` (kube-proxy `mode: nftables` + Calico
  `linuxDataplane: Nftables` write rules through the nf_tables kernel API) and
  `vxlan` (Calico Installation pinned VXLAN encapsulation on both
  pod IPPools — IPIP is IPv4-only, there is no BGP infra on the lab substrate,
  VXLAN is the only dual-stack-capable mode)**);
* §13.7 `lxd_bootstrap_instance` (Step 3 + Step 5 required-profiles
  refactor + **Step 9 image alias → `debian/13/cloud`**);
* §13.8 `binary_fetch` (Step 4 — deferred Phase 1.5 / §15.1);
* §13.9 `bootstrap_k3s` (Step 4 + Step 5 required-disables refactor +
  **Step 11 dual-stack pod CNI: cluster-cidr/service-cidr/cluster-dns
  v4+v6, `--flannel-ipv6-masq`, `--disable-network-policy` under
  unprivileged-LXC kube-router-incompat, `--node-ip=v4,v6` via
  an ExecStart wrapper-launcher**);
* §13.10 `bootstrap_clusterctl` (Step 6 — Phase 4 continuation, §15.3);
* §13.11 `bootstrap_capn_secret` (Step 6 — Phase 4 continuation, §15.4 +
  **Step 11 namespace fanout: the Secret is materialised in every ns from
  `k8s_lab_capn_identity_namespaces` (per-cluster), instead of the previously
  mistaken capn-system; CAPN reads the Secret from the LXCCluster CR's
  namespace, cross-ns lookup is not supported in v1alpha2**);
* §13.12 `export_artifacts` (Step 8 — Phase 4 closure, §15.6 +
  **Step 11 `k8s_lab_workload_controlplane_count` default 2 → 3**:
  CAPI's KCP webhook rejects an even CP replicas count under stacked etcd —
  min HA = 3).

The Phase 8 destroy role `cleanup_bootstrap` (§19.1) is implemented in Step 9 —
the only Stage 1 role in the reverse direction, lives in PLAN-stage1-6.md
together with the §19.2 Phase 8 orchestrator.

Stage 1 roles not yet completed live in subsequent shards (§15..§19)
together with their phases.

**Step 5 (2026-04-22) — sweeping audit per the rule
`feedback_required_values_hardcoded.md`** (which Step 3 already applied
to `lxd_profiles` and Step 4 — to `lxd_project`): every substrate-required
value — package, sysctl, kernel module, profile, LXD config key —
has been moved out of `defaults/main.yml` into `vars/main.yml` under
the `_<role>_required_*` prefix and is no longer available for consumer override.
Public defaults remain only for tunable parameters +
`*_extra_*` extension points that merge on top of the baseline (required
keys always win the merge). No regressions appeared — all 9
scenarios passed `converge → idempotence → verify` on a clean Vagrant
VM (`.artifacts/regression-logs/SUMMARY.txt`).

**Step 6 (2026-04-23) — Phase 4 continuation + native-first
collection upgrade.** The two missing Phase 4 roles have been implemented:
`bootstrap_clusterctl` (§13.10) and `bootstrap_capn_secret` (§13.11). Along
the way an end-to-end tooling upgrade was performed for the roles that
talk to the Kubernetes API: the `kubernetes.core` collection (≥
6.0.0; resolved 6.4.0) was added to `ansible/requirements.yml` and the
`python3-kubernetes` package (Debian Trixie 30.1.0-2) to shared Molecule
prepare. All cluster API calls have been moved from `kubectl` commands to
native `kubernetes.core.k8s` / `k8s_info` (server-side apply,
structured responses instead of jsonpath parsing — a whole class of
fragile string-matching bugs eliminated). Similarly, the openssl shell
has been replaced with `community.crypto.x509_certificate_info` for extracting
the SHA-256 fingerprint of the client cert. After the review fixes were applied
(see below), both scenarios are green end-to-end (converge + idempotence +
verify, changed=0 on repeat passes).

**Step 6 review fixes (applied before the commit):**
* `bootstrap_capn_secret_name` was made a public default, sourced from
  the global `k8s_lab_infrastructure_secret_name` (the plan's §8 contract)
  — Phase 5+ Cluster CR's `identityRef.name` and the Secret name now
  change via a single global variable, with no silent disconnect;
* `bootstrap_capn_secret_pivot_enabled` defaults to `true` — pivot is
  mandatory in canonical flow §3, the label
  `clusterctl.cluster.x-k8s.io/move=true` is always propagated, so that
  `clusterctl move` carries the Secret to the target mgmt-1;
* §9.4 role-level scenarios list extended with the two new scenarios;
* `requirements.yml` comment clarified: Python `kubernetes` is needed on the
  executor node (the target VM), not on the controller;
* empty `handlers/` directories removed from both roles.

**Step 11 (2026-04-26) — Phase 5 chart-level acceptance driver +
substrate fixes for the unprivileged-LXC kubeadm path.** Chart
`charts/capi-workload-cluster/` (§16.3, new) is implemented, chart
`charts/capi-cluster-class/` is refined to the verified CAPN v0.8.5 CRD
shape (`loadBalancer.lxc.instanceSpec.profiles: [capi-base]`,
`KubeadmControlPlaneTemplate` + `KubeadmConfigTemplate` carry
the substrate-required `kubeletExtraArgs: [feature-gates=KubeletInUserNamespace=true]`
for the unprivileged-LXC oomWatcher), bumped 0.1.0 → 0.3.0. Helm install
of both charts against bootstrap k3s is green, `TopologyReconciled=True`
on the first apply. Helm test (CAPN-driven full provisioning of 3 CP +
2 workers) **remains not green** on dual-stack apiserver bind +
admin.conf endpoint family mismatch — an open issue, scope Step 12+
(see §16.6 Acceptance status note).

**Step 12 (2026-04-26) — closure of the dual-stack acceptance gap from Step
11 + e2e_local Molecule driver.** Both charts bumped to 0.4.2.

* `charts/capi-cluster-class/` — substrate-required dual-stack
  hardening (see §16.2 Step 12 extensions for details):
  * `KubeadmControlPlaneTemplate` always emits
    `clusterConfiguration.apiServer.extraArgs.bind-address: "::"` and
    `controllerManager.extraArgs.allocate-node-cidrs: "true"` —
    apiserver listens on both families, KCM hands out podCIDR per-Node.
  * Hardcoded `kubeletExtraArgs.provider-id: lxc:///{{ v1.local_hostname }}`
    in both kubeadm templates (`KubeadmControlPlaneTemplate` and
    `KubeadmConfigTemplate` worker) — without it nodes register
    with an empty `Node.spec.providerID` and CCM-style features break.
  * Substrate `preKubeadmCommands` on both templates patches
    `/run/kubeadm/kubeadm.yaml` (init / join config) to
    `kubeletExtraArgs[node-ip]=<v4>,<v6>` from eth0; LXD hands out DHCP/
    SLAAC addresses dynamically, you can't bake them statically into the
    template.
  * The ClusterClass `patches` block propagates
    `Cluster.spec.clusterNetwork.{pods,services}` into kubeadm
    `apiServer.extraArgs.service-cluster-ip-range`,
    `controllerManager.extraArgs.{cluster-cidr,service-cluster-ip-range}`
    via CAPI v1beta2 `valueFrom.template`. clusterNetwork stays a
    Cluster-CR field (§16.3); ClusterClass does not duplicate it.
  * `LXCClusterTemplate.customHAProxyConfigTemplate` is baked in as a
    substrate-required dual-bind v4+v6 frontend (CAPN v0.8.x default
    haproxy.cfg binds only on v4; a working dual-stack endpoint
    requires a manual template). The field is removed from `values.yaml` —
    no longer consumer-tunable.
  * Reserved-arg guards: `apiServerExtraArgs` rejects
    `bind-address`, `service-cluster-ip-range`;
    `controllerManagerExtraArgs` rejects `allocate-node-cidrs`,
    `cluster-cidr`, `service-cluster-ip-range`; `kubeletExtraArgs`
    rejects `feature-gates`, `node-ip`, `provider-id`. A consumer's
    attempt to override any of these keys produces a `helm
    template fail` with an explicit message.
* `charts/capi-workload-cluster/` — `templates/tests/cluster-ready.yaml`
  Helm test hook extended 7 → 10 phases (details in §16.3 Step 12
  extensions):
  * Phase 1 now additionally asserts that the LXCCluster has
    materialised the dual-bind v4/v6 HAProxy template (regression
    guard for the Step 12 chart-side hardcode);
  * Phase 2 waits for `Cluster.spec.controlPlaneEndpoint` to be materialised,
    does a workload API `/livez` smoke via the chosen endpoint
    (proves haproxy LB → CP serving works on both families),
    confirms per-Node `providerID = lxc:///<node>`, dual-stack
    `InternalIP` and `podCIDR`s, plus a runtime probe — creates
    a `Service` with `ipFamilyPolicy: RequireDualStack` and verifies that
    the allocator hands out both `clusterIPs` (v4 + v6). Replica counts
    moved from `>=` to `==` — exact topology.
* `ansible/roles/lxd_profiles/vars/main.yml` — the capi-worker profile
  got a `host-boot` read-only `/boot` mount (see §13.6 — Step 11
  closed the CP, Step 12 closed the worker, the previous plan description
  was ahead of the code).
* `tests/molecule/lxd-profiles/verify.yml` extended:
  asserts the `host-boot` device on both profiles; the universal
  device-equality predicate gained `source` and `readonly` checks
  for disk devices.
* `tests/molecule/e2e-local/` — new Full E2E Molecule scenario
  (§9.4 last bullet, §10.2 driver). `converge.yml` includes
  `export_artifacts` (the entire Phase 0..4 chain), then natively
  installs both charts via `kubernetes.core.helm`.
  `verify.yml` runs the workload chart `helm test` (35-min budget),
  takes a CAPI snapshot via `kubernetes.core.k8s_info`,
  materialises the workload kubeconfig from the bootstrap Secret via
  `k8s_info` + `ansible.builtin.copy`, and takes a workload-side
  `kubectl get nodes -o wide` via a short-lived Pod
  (`kubernetes.core.k8s` → `k8s_info` polling → `k8s_log` →
  `k8s state: absent`); the workload API endpoint lives on
  the LXD-bridge IPv6, unreachable from the runner, so an in-cluster
  jump-pod is the only path. The only shell is `helm
  test` (no native equivalent); `changed_when: false` is NOT
  set, because `helm test` creates ephemeral pods.
* `scripts/molecule_run.py` — the `destroy` action now
  short-circuits `make up` + `vagrant ssh-config` discovery
  (you can run destroy on stale state without a live VM).
* Root `Makefile` — fixed a typo in the `test-local-e2e` target
  (`e2e_local-vagrant-*` → `e2e-local-vagrant-*`); `clean-local`
  no longer invokes the `destroy-all` Molecule wrapper (it itself
  falls over without a live VM on the new scenarios), instead inline
  `find $HOME/.ansible/tmp -name 'molecule.*' -exec rm -rf {} +`.

End-to-end result: `make -C tests/molecule e2e-local-vagrant-converge`
→ `failed=0`; `make -C tests/molecule e2e-local-vagrant-verify` →
`failed=0`, helm test prints `cp=3/3 worker=2/2 total=5/5 ALL
TOPOLOGY CHECKS PASSED`. Nodes are visible through the workload kubeconfig,
each has a dual-stack `InternalIP` (v4+v6), `providerID
lxc:///<node>`, dual-stack `podCIDR`s (`10.244.x.x/24` +
`fd42:77:2:x::/64`); the workload allocator hands out a dual-stack
ClusterIP (`10.96.x.x` + `fd42:77:3:x::`). Nodes remain
`NotReady` — the CNI is installed by the §16.4 module as a separate `helm_release`
further down the chain, that is expected.

In the process the chart-level test discovered and closed a series of
substrate-required deviations:

* `bootstrap_capn_secret` (§13.11) — **namespace fanout**: CAPN
  v1alpha2 LXCCluster.spec.secretRef has no namespace field; the Secret
  must live in the LXCCluster CR's namespace (i.e. the workload Cluster CR
  namespace). The role is extended with a loop over a new §8 global
  `k8s_lab_capn_identity_namespaces` (default `["capi-clusters"]`).
  The old `_required_namespace: capn-system` substrate value is removed —
  CAPN does not read the Secret from its controller namespace.
* §8 `k8s_lab_workload_controlplane_count` default `2 → 3` — CAPI's
  KubeadmControlPlane webhook rejects an even CP replicas count under
  stacked etcd (split-brain risk), min HA = 3.
* §8 `k8s_lab_kubernetes_version` `v1.35.3 → v1.35.0` — pin
  constrained by the CAPN simplestreams image set
  (https://images.linuxcontainers.org/capn/), not upstream
  dl.k8s.io/release/stable.txt; on 2026-04-25 the actual latest =
  `v1.35.0`. Inline rationale in §8a.
* §13.3 `lxd_project` — `restricted.devices.disk: managed → allow`
  + `restricted.devices.disk.paths: /boot`. Only `allow` mode
  supports path-based bind-mount whitelists; `block` blocks
  everything including pool-backed root disks, `managed` ignores the `paths`
  whitelist. The `/boot` whitelist is needed for the §13.6 `host-boot` device
  (see below).
* §13.6 `lxd_profiles` — **`host-boot` disk device** on
  `capi-controlplane`/`capi-worker` (NOT on `capi-bootstrap` — k3s
  does not do kubeadm preflight). Read-only mount of the host's `/boot` into
  the container — kubeadm SystemVerification reads
  `/boot/config-<uname-r>` to check CONFIG_NAMESPACES, CGROUPS,
  NETFILTER, etc. Debian 13 kernel built without CONFIG_IKCONFIG —
  `/proc/config.gz` physically does not exist, `modprobe configs` in
  unprivileged-LXC unconditionally fails. Architectural fix instead of
  `--ignore-preflight-errors=SystemVerification` in KCPT.
* §13.9 `bootstrap_k3s` — **dual-stack pod CNI**:
  `--cluster-cidr=10.42.0.0/16,fd42:77:42::/56`,
  `--service-cidr=10.43.0.0/16,fd42:77:43::/112`,
  `--cluster-dns=10.43.0.10,fd42:77:43::a`, `--flannel-ipv6-masq`,
  `--disable-network-policy` (kube-router IPv6 init crash under
  unprivileged-LXC even after correct node-ip registration).
  `--node-ip=v4,v6` is injected via a wrapper script
  `/usr/local/sbin/k3s-server-launcher` on ExecStart — `ip -o addr
  show eth0` inside the container resolves both families at the moment
  of k3s start, exec's `k3s server --node-ip=<v4>,<v6> "$@"` on top of
  all systemd flags. EnvironmentFile-based approaches do not work
  (systemd loads the env block BEFORE ExecStartPre); the wrapper does not depend
  on per-instance IP pinning, multi-bootstrap setups work without
  collision. Trigger: workload-cluster CR's `Cluster.spec.controlPlaneEndpoint`
  under dual-stack capi-int picks the IPv6 family — CAPI controllers in
  bootstrap k3s pods MUST have IPv6-reachable pod CNI to reach the workload LB
  endpoint.
* §16.2 `charts/capi-cluster-class` — bumped 0.1.0 → 0.3.0; four
  substrate-required hardcoded additions:
  * `loadBalancer.lxc.instanceSpec.profiles: [capi-base]` baseline
    — without it CAPN falls over on `Failed getting root disk: No root
    device could be found` when creating the haproxy LB instance
    (LXD requires NIC + root disk; `capi-base` profile carries both).
  * `KubeadmControlPlaneTemplate.spec.template.spec.kubeadmConfigSpec.
    initConfiguration/joinConfiguration.nodeRegistration.kubeletExtraArgs`
    always emits `feature-gates=KubeletInUserNamespace=true`
    baseline (consumer extras append) — kubelet's oomWatcher
    constructor opens `/dev/kmsg`, in unprivileged userns this is
    permission-denied; the KubeletInUserNamespace gate tells kubelet
    to ignore the failure and start.
  * `KubeadmConfigTemplate` (worker) — the same in
    `joinConfiguration`.
  * `loadBalancer.lxc` shape under CAPN v0.8.5 CRD — `instanceSpec`
    wrapper (instead of the previously assumed flat structure);
    consumer-tunable knobs: `image`, `flavor`, `target`,
    `customHAProxyConfigTemplate`, `disableHealthzCheck`,
    `profilesExtra`. Verified against the live LXCClusterTemplate CRD.
* §16.3 `charts/capi-workload-cluster` — **new chart** (full
  contract description below in §16.3). Cluster CR + helm test hook
  (RBAC + alpine + upstream kubectl wget) for in-cluster topology
  validation. Helm-3-only features (TF helm provider compat).
  ClusterClass version coupling via `Chart.yaml.annotations`,
  not values — the consumer / TF fixture doesn't pass the version manually.

§16.4/§16.5 Terraform module contracts updated: input
`cluster_class_chart_version` removed (annotation-pinned now),
`cluster_class_namespace` input added (cross-ns ClusterClass
support, since the workload Cluster CR lives in `capi-clusters`,
and the ClusterClass — in `capi-system`).

Memory rules introduced in this Step (see `MEMORY.md`):
* `feedback_test_artifact_naming.md` — k8s-lab* prefix for test
  artifacts instead of generic placeholders;
* `feedback_no_bitnami_images.md` — bitnami/* banned, alpine + apk
  / upstream binary fetch for test pods;
* `feedback_no_ad_hoc_fixes.md` — hard rule: after root-cause —
  fix architecturally + the whole chain, no manual kubectl
  apply / sed-yaml / hand-copy;
* `feedback_active_provisioning_monitor.md` — on long CAPN
  tests, raise a second monitor on controller logs + CR status,
  don't wait for a passive timeout on test pod stdout;
* `feedback_per_role_molecule_sequence.md` — on a clean VM,
  run Molecule scenarios in turn for every changed
  role (dep-graph order), continue the chain through the credential-
  producing role (`export_artifacts`).

Test evidence Step 11 (per-role sequential scenarios on a fresh
Vagrant VM):
* `bootstrap-k3s` — `converge ok=209 changed=34 / idempotence ok=199
  changed=0 / verify ok=156 changed=4 / failed=0`;
* `bootstrap-capn-secret` — `converge ok=274 changed=14 / idempotence
  ok=271 changed=0 / verify ok=12 changed=0 / failed=0` (all 12
  multi-namespace asserts: Secret in `capi-clusters` with 5 keys + correct
  pivot label + LXD trust + HTTPS endpoint);
* `export-artifacts` — `converge ok=298 changed=3 / idempotence ok=298
  changed=0 / verify ok=16 changed=0 / failed=0`;
* Chart-level — `helm install` cluster-class + workload-cluster applied
  cleanly, `TopologyReconciled=True`, owned KCP/MD/LXCCluster
  materialized, CAPN provisions LB + the first CP LXC instance
  (cloud-init passes preflight, kubeadm generates certs, static
  pods (etcd/apiserver/cm/scheduler) come up healthy);
* Chart-level **not green** in Step 11 — `helm test` fails on
  the `kubeadm upload-config/kubeadm` phase (`client rate limiter Wait
  returned an error: context deadline exceeded` when creating the admin
  ClusterRoleBinding). Root cause: kube-apiserver listens `*:6443`
  (IPv4 wildcard, kubeadm default `--bind-address=0.0.0.0`), but
  admin.conf and `Cluster.spec.controlPlaneEndpoint` (CAPN
  auto-derived) point to the IPv6 endpoint of the CP node (or LB) —
  family mismatch. **Closed in Step 12** (apiserver
  `--bind-address=::` + dual-bind v4/v6 HAProxy template +
  patches propagate service/pod CIDRs from the Cluster CR into
  kubeadm; see §16.6 Step 12 Acceptance status).

Test evidence Step 12 (chart-level acceptance + Full E2E Molecule
scenario on the same VM):
* `e2e-local` converge — `failed=0`, both charts apply
  idempotently via `kubernetes.core.helm`;
* `e2e-local` verify — `failed=0`, `helm test` (10 phases) passes
  end-to-end: `cp=3/3 worker=2/2 ALL TOPOLOGY CHECKS PASSED`,
  workload `/livez` responds via the chosen CP endpoint,
  per-Node `providerID = lxc:///<node>`, dual-stack
  `InternalIP`/`podCIDR`s, and a `RequireDualStack` ClusterIP
  Service gets both addresses (v4 + v6).

**Step 13 (2026-04-26) — CNI delivery + native nftables migration on
the workload cluster.** Chart `charts/cni-calico/` delivered (new,
§17.2) — a local wrapper over upstream `projectcalico/tigera-operator`
v3.31.5 with substrate-required hardcoded fields in the `Installation` CR
(`cni.type: Calico`, `bgp: Disabled`, `linuxDataplane: Nftables`,
dual-stack VXLAN ipPools, `controlPlaneReplicas: 2` as an HA pair §2.12
for calico-kube-controllers + calico-apiserver). Helm test hook
is the chart-level acceptance driver (alpine + dl.k8s.io kubectl,
6 phases: tigera-operator Available → calico-system rollout +
Pods Ready → workload Nodes Ready=True → dual-stack `podCIDRs` per-Node →
2 ephemeral probe Pods on different workers via podAntiAffinity
+ nodeAffinity NotIn control-plane → ICMP4/ICMP6 via `kubectl exec`).

The paired chart-side change in `charts/capi-cluster-class/` (bumped
0.4.2 → 0.5.0): `KubeadmControlPlaneTemplate.preKubeadmCommands`
appends a KubeProxyConfiguration document to `/run/kubeadm/kubeadm.yaml`
before `kubeadm init`. Calico nftables data-plane requires that
kube-proxy is also in `mode: nftables` — Calico docs phrase this
as a contract. Additional substrate-required hardcodes:
* `KubeProxyConfiguration.conntrack.{maxPerCore: 0, min: 0}` —
  disables kube-proxy's conntrack tuning. The default
  (`maxPerCore: 32768, min: 131072`) leads to an attempted write to
  `/sys/module/nf_conntrack/parameters/hashsize`, which in
  unprivileged-LXC user-namespace is rejected with permission denied
  (the path is host-global, requires CAP_SYS_ADMIN on the host). Without
  disabling, kube-proxy crashloops.
* The whole block is init-only (gated on the presence of `kubeadm.yaml` + absence of
  `kubeadm-join-config.yaml`) — KubeProxyConfiguration is honoured
  only by `kubeadm init`; CP joins and worker joins read the
  populated `kube-system/kube-proxy` ConfigMap.

`charts/capi-workload-cluster/` chart bumped in pair: 0.4.2 → 0.5.0 +
annotation pin `k8s-lab.io/capi-cluster-class-chart-version: "0.5.0"`.
No template changes in it — the bump is purely under the coupling rotation
contract (§16.3).

`ansible/roles/lxd_profiles/vars/main.yml` — extended
`linux.kernel_modules` for capi-controlplane / capi-worker:
added `nf_tables` (kube-proxy nftables mode + Calico Nftables
mode write rules through the nf_tables kernel API) and `vxlan` (Calico
Installation pinned VXLAN encapsulation on both pod IPPools — IPIP
IPv4-only, no BGP infra on the substrate, VXLAN the only
dual-stack-capable mode). LXD pre-loads the modules before instance
start, fallback on kernel auto-load remains.
`tests/molecule/lxd-profiles/verify.yml` asserts the new list.

**Architectural decision vs `Iptables` mode**:
* On Debian 13 system iptables = `iptables-nft` shim → writes to
  nf_tables. Calico in `Iptables` mode auto-detects the host backend and on
  our substrate uses iptables-nft binding — i.e. the
  kernel-level effect is the same as Nftables mode, through the iptables
  compat layer.
* `Iptables` mode is the mature default; `Nftables` is GA in Calico v3.30+ for
  single-stack, in v3.31 — for dual-stack. Less production-mileage,
  but a cleaner rule set, no iptables compat layer.
* Operator API enum `LinuxDataplane = {Iptables, BPF, VPP, Nftables}`
  — one of four, switching is total (no mixed mode).
* `Nftables` chosen for consistency: a single kernel API path
  (kube-proxy + Calico both write through nf_tables), easier to observe
  via `nft list ruleset`, future-proof (iptables-legacy
  deprecating).

Memory rules applied in Step 13 (no new ones):
* `feedback_chart_required_values_hardcoded.md` — Installation CR
  substrate-required fields in templates, not values.yaml;
* `feedback_no_bitnami_images.md` — alpine + busybox + dl.k8s.io
  kubectl wget;
* `feedback_test_artifact_naming.md` — `k8s-lab-*` prefix for probe
  Pod names;
* `feedback_pause_before_role_test.md` — chart code finished, testing
  on a live cluster revealed substrate-fragility (see below).

**Step 13 follow-up — e2e-local integration of CNI + lab-VM resource
bump.** After the chart-level changes were assembled, it turned out
that the Vagrant lab-VM (6 GB RAM from the Vagrantfile) under constant load
(bootstrap k3s + 5 workload LXC instances + LB + Calico add-ons)
went into OOM-thrash (`free=114Mi swap=0 load=142`), which crashed the LXD
daemon transactions ("transaction has already been committed or
rolled back" / "Only running operations can be connected") and led
to intermittent bootstrap + workload API outages. RAM bumped
6144 MB → 12288 MB in `tests/vagrant/debian13/Vagrantfile` (env
override `K8SLAB_MEM_MB`) removed the OOM pressure (`free=11Gi load<5`),
after `make clean-local` + `make up` all subsequent operations
work normally.

`tests/molecule/e2e-local/` extended to the full CNI chain —
converge installs ClusterClass + workload-cluster + Calico, verify
runs both helm tests:
* converge.yml — 7 new tasks after workload-cluster install:
  * `ansible.builtin.unarchive` — install helm CLI v3.20.0 into
    `/opt/capi-lab/bin/helm` (idempotent via `creates:`);
  * `ansible.builtin.slurp` + `set_fact` — derive cni-calico chart
    version from Chart.yaml (single-source-of-truth for the following
    tasks);
  * `helm dependency update` + `helm package` on the runner
    (`delegate_to: localhost`) — the packaged .tgz is emitted into
    `.artifacts/cni-calico-<version>.tgz`;
  * `ansible.builtin.copy` — moves the .tgz into
    `/opt/capi-lab/etc/cni-calico-<version>.tgz` on the VM;
  * `kubernetes.core.k8s_info` polling (`delegate_to: localhost`,
    bootstrap kubeconfig) — waits for the `<cluster>-kubeconfig` Secret;
  * `ansible.builtin.copy` (on the VM) — materialises the workload
    kubeconfig in `/opt/capi-lab/etc/<cluster>.kubeconfig` mode 0600;
  * `kubernetes.core.helm` (on the VM, without `delegate_to: localhost`) —
    install Calico on the workload cluster via the VM-side helm.
    The workload API endpoint is runner-unreachable (capi-int IPv6
    bridge), so helm has to run on the VM.
* verify.yml — added task `run cni-calico helm test` after
  the existing workload-chart helm test (ansible.builtin.command
  on the VM, `become: true` to read the root-owned kubeconfig);
* shared `inventory/group_vars/k8slab_host.yml` — added
  substrate globals per the §8 contract: `k8s_lab_workload_pod_cidr_v4`
  (default `10.244.0.0/16`), `_v6` (`fd42:77:2::/56`),
  `k8s_lab_workload_service_cidr_v4/_v6`. Previously these keys lived
  only as defaults in chart values; converge now reads them
  from inventory and forwards them into the Calico Installation CR
  (`calicoNetwork.ipPools.cidr`) — a guarantee of match with
  the workload Cluster CR's `spec.clusterNetwork`.

`charts/cni-calico/` refined — bumped 0.1.0 → 0.2.0 (see §17.2
Step 13 status block; the bump is required for `kubernetes.core.helm`
upgrade-detection: the module silently skips upgrade on identical
chart name+version+digest, manual `helm upgrade` always works
but automation requires a version bump on every templates/values
change). Substrate-required RBAC/hook policy refinements:
* `templates/tests/rbac.yaml` — SA + ClusterRole + ClusterRoleBinding
  no longer carry the `helm.sh/hook: test` annotation; they are regular
  release resources, installed at `helm install` time, reaped
  only on `helm uninstall`. Reason: `helm test --logs` tries to
  fetch pod logs for every resource with this annotation, and
  fails non-zero on non-Pod kinds (a cosmetic helm bug that
  breaks CI gating). The ClusterRole is also extended: added read on
  `core/namespaces` (gating on calico-system existence) and
  `apps/{deployments,daemonsets}` (kubectl rollout status / wait
  on tigera-operator + calico-system workloads);
* `templates/tests/cni-ready.yaml` — hook delete policy
  `before-hook-creation,hook-succeeded` → `before-hook-creation`
  only. Reason: race condition between `Phase: Succeeded` and
  the `helm test --logs` log-fetch step — on a short test (~15s)
  hook-succeeded deletes the Pod before helm reaches the log
  pull, exit 1 with "pods not found". The test Pod now lives after
  Succeeded, is reaped on the next `helm test` via
  before-hook-creation or on `helm uninstall`.

End-to-end result:
`make clean-local` → `make up` (12 GB VM) →
`make -C tests/molecule e2e-local-vagrant-converge` → `failed=0
ok=307 changed=4` →
`make -C tests/molecule e2e-local-vagrant-verify` → `failed=0
ok=14 changed=4`. Compact-state debug:
* workload chart `helm test` (10 phases): `cluster=lab-default
classRef=capn-default-0-5-0 AVAILABLE=True cp=3/3 worker=2/2
ALL TOPOLOGY CHECKS PASSED`;
* cni-calico `helm test` (6 phases): `Phase: Succeeded` —
  tigera-operator Available, calico-node DaemonSet + calico-kube-
  controllers Deployment rolled out, calico-system Pods Ready,
  all 5 workload Nodes Ready=True, dual-stack `podCIDRs`
  per-Node, dual-stack ICMP4/ICMP6 between the two ephemeral probe
  Pods on different worker nodes.

A live check on the fresh cluster confirmed the architectural
declarative path: kube-proxy ConfigMap rendering on the workload
showed `mode: nftables` + `conntrack.{maxPerCore: 0, min: 0}`,
all 5 kube-proxy pods Running 0 restarts (without the crashloops
that occurred on attempts at live patching on a degraded Step-12 cluster
— see PLAN-1 Test evidence Step 13 follow-up resource bump
paragraph above).

**Step 14 (2026-04-27) — MetalLB delivery + Gate A acceptance.**
Two local wrapper charts delivered (§17.3):

* `charts/metallb/` (new, version 0.1.0) — a minimal subchart-wrapper
  over upstream `metallb/metallb` 0.15.3. No templates of its own; values.yaml
  pins substrate-required toggles (`crds.enabled=true`,
  `frrk8s.enabled=false`, `speaker.frr.enabled=false`,
  `speaker.tolerateMaster=true`); values.schema.json validates them as
  `const` over the subchart values surface;
* `charts/metallb-config/` (new, version 0.1.3) — wrapper-owned
  IPAddressPool (v6 single-stack pool, autoAssign=true) +
  L2Advertisement (interfaces=[$.l2.interface], substrate-required
  hardcoded nodeSelector with `node-role.kubernetes.io/control-plane:
  DoesNotExist` — VIPs announced ONLY from worker nodes; consumer
  `extraNodeSelectors` stack on top). Helm test hook
  `templates/tests/metallb-vip.yaml` — chart-side acceptance driver
  (alpine + busybox wget + dl.k8s.io kubectl, 8 phases): controller
  Available → speaker DS rolled out → demo Deployment + Service
  type=LoadBalancer (`ipFamilies: [IPv6]`) applied → backend Pod
  Ready → VIP allocated AND in-pool (string-prefix sanity) →
  in-cluster HTTP probe from the driver Pod (non-hairpin: driver is not
  an endpoint of the Service; kube-proxy nftables DNAT short-circuits via
  `mark-for-masquerade`+DNAT in the `endpoint-...` chain). Memory rules:
  `feedback_no_bitnami_images.md` (alpine + busybox for the driver,
  nginx-on-alpine for the backend — the busybox base lacks the httpd applet),
  `feedback_test_artifact_naming.md` (`k8s-lab-metallb-demo` prefix
  for the demo stack).

**Two-release split rationale (architectural).** Initially attempted
single-wrapper design (mirror cni-calico Step 13 precedent) failed
runtime: upstream metallb 0.15.3 ships CRDs as sub-dependency
`templates/crds/`, NOT the Helm `crds/`-folder mechanism. Helm 3
pre-apply manifest validation rejected `kind IPAddressPool` because
metallb.io/v1beta1 was not yet served at validation time. PLAN §17.3
two-release design was correct from the start, validated again by
runtime evidence — split into `charts/metallb/` (subchart only,
registers CRDs + workloads) followed by `charts/metallb-config/`
(custom resources + helm test hook). Memory rule
`feedback_plan_is_fallible.md` cuts both ways: the precedent test
flagged single-wrapper as the right shape, the runtime test
overruled.

**HA pair contract §2.12 deviation (MetalLB-specific).** Upstream
`metallb` chart 0.15.3 does NOT expose `controller.replicas` —
controller is a singleton by upstream design (allocates VIPs from
the pool and validates CRs, no state partitioning). HA on this chart
is delivered through the **speaker DaemonSet** (one replica per
worker, leader-elected per-VIP via memberlist gossip). When a
speaker leader fails, another speaker re-announces the VIP within
seconds. Documented inline in `charts/metallb/values.yaml` +
`charts/metallb-config/values.yaml` + §17.3.

**Backend image follow-up (Step 14 in-flight fix).** Service is IPv6
single-stack (`ipFamilies: [IPv6]`) — kube-proxy DNATs to the Pod's
v6 IP. Initial backend was alpine + busybox httpd, but alpine's base
busybox lacks the httpd applet. Switched to nginx-on-alpine
(`nginx:1.27-alpine`); however nginx default config has only
`listen 80;` (v4). Driver Pod's apply step now splices an extra
`listen [::]:80;` next to the existing v4 listen via inline `sed`,
keeping the rest of nginx default.conf intact. Memory rule
"Never use bitnami images" — nginx Inc. official image, not bitnami.

**`tests/molecule/e2e-local/` extended to MetalLB chain.** converge.yml
adds packaging+install for both MetalLB wrappers after CNI install
(same pattern as cni-calico: read Chart.yaml on runner → helm dep
update + helm package on runner → copy .tgz to VM → install via
`kubernetes.core.helm` on VM with workload kubeconfig). verify.yml
adds three new tasks after the existing helm tests:
1. `helm test metallb-config` on VM (chart-side 8-phase driver Pod);
2. `kubernetes.core.k8s_info` reading `Service.status.loadBalancer.
   ingress[0].ip` against workload kubeconfig (Gate A external VIP);
3. `ansible.builtin.uri url=http://[<VIP>]:80/` from the VM (NOT
   `delegate_to: localhost`) — packet path: VM →
   `ext6-ra-peer 2001:db8:42:100::1` → veth → `br-ext6` → eth1
   speaker leader → kube-proxy nftables DNAT → backend nginx Pod →
   200 OK body matches `^ok`. This closes Gate A.

**`k8s_lab_external_probe_address` removed from §8.** The original
plan reserved this var for an outbound-probe Gate A design (worker
hostNetwork Pod ping6's external probe endpoint). Step 14 redesign
of Gate A uses an inbound-probe shape (external curl from VM to
MetalLB-allocated VIP through production-path L2) — semantically
stronger because it tests the full external→Service→Pod chain, not
just outbound L2 reachability. The variable is no longer wired
anywhere in shipped code.

End-to-end result:
`make -C tests/molecule e2e-local-vagrant-converge` → `failed=0
ok=318 changed=7` →
`make -C tests/molecule e2e-local-vagrant-verify` → `failed=0
ok=20 changed=5`. Compact-state debug:
* workload chart `helm test` (10 phases): `cluster=lab-default
  classRef=capn-default-0-5-0 AVAILABLE=True cp=3/3 worker=2/2
  ALL TOPOLOGY CHECKS PASSED`;
* cni-calico `helm test` (6 phases): `Phase: Succeeded` (see Step 13
  evidence above);
* metallb-config `helm test` (8 phases): `Phase: Succeeded` —
  `===> ALL METALLB CHECKS PASSED`, `===> VIP=2001:db8:42:100::200`;
* verify-side curl: `metallb VIP=2001:db8:42:100::200
  external_status=200`. End-to-end Gate A green: production-path
  external L2 reaches the announced VIP through the speaker leader and
  kube-proxy DNAT to the backend Pod.

**Step 15 (2026-04-28) — runner-reachable workload API endpoint.**
CAPN auto-derives the workload `controlPlaneEndpoint` from the LB
instance's capi-int IPv6, which is reachable only from inside the
VM. To let the runner talk to the workload kube-apiserver directly
(`kubectl`, TF data sources, future `workload_cluster` module),
Step 15 adds a deterministic per-workload LXD proxy device on the
CAPN haproxy LB instance and rewrites the workload kubeconfig
accordingly:

* `charts/capi-cluster-class/` (0.5.0 → 0.6.3): both
  `KubeadmControlPlaneTemplate` and `KubeadmConfigTemplate` now
  ship `kubeadmConfigSpec.files` + `preKubeadmCommands` for the
  eth1 RA reception baseline — `/etc/sysctl.d/99-capi-ra.conf`
  with `accept_ra=2 accept_ra_defrtr=1` (workload nodes have
  forwarding=1 for k8s pod networking, which makes the default
  `accept_ra=1` ignore RA), and `/etc/systemd/network/30-capi-ext.network`
  with `IPv6AcceptRA=yes`. preKubeadm runs `sysctl --load` +
  `networkctl reload` so the config is live before MetalLB speaker
  comes up. The CAPN haproxy LB instance receives an LXD `proxy`
  device post-CAPI through the workload chart's own Helm hook
  Jobs (see capi-workload-cluster bump below) — CAPN's
  `LXCCluster.loadBalancer.lxc.instanceSpec` is a closed CRD
  schema with no `devices` field, so the device cannot ride the
  topology API.

* `charts/capi-workload-cluster/` (0.5.0 → 0.7.2): paired bump.
  `templates/_helpers.tpl` adds `capi-workload-cluster.apiProxyPort`
  — `add 20000 (mod (atoi (adler32sum cluster.name)) 10000)`,
  pure function, same cluster name → same port across re-installs.
  Override via `loadBalancer.lxc.proxyApiPort` values
  (default 0 = use hash). `templates/cluster.yaml` writes the
  computed port to `Cluster.metadata.annotations["k8s-lab.io/api-proxy-port"]`
  — the single source of truth read by Molecule verify and the
  future TF `workload_cluster` module.

  **Helm-only LXD `proxy` device delivery** —
  `templates/api-proxy-attach-job.yaml` (post-install/post-upgrade
  hook) and `templates/api-proxy-detach-job.yaml` (pre-delete
  hook) drive the LXD HTTPS REST API directly with mTLS material
  from the `incus-identity` Secret. The attach Job waits for
  CAPN to materialise `<cluster>-<suffix>-lb`, then `PATCH`-es
  `/1.0/instances/<lb>?project=<p>` body
  `{"devices":{"api-proxy":{"type":"proxy","listen":"tcp:0.0.0.0:<port>","connect":"tcp:127.0.0.1:6443","bind":"host"}}}`
  — LXD merge-on-PATCH adds the device without disturbing the
  instance's other devices. Detach Job is the symmetric inverse
  on `helm uninstall <workload>`. Image is `alpine:3.21` +
  runtime `apk add curl jq` (no incus/lxc CLI binary). New values
  knobs: `apiProxy.image`, `apiProxy.infrastructureSecretName`,
  `apiProxy.lbWaitTimeoutSeconds`. Memory rules applied:
  `feedback_helm_first_no_raw_manifests`,
  `feedback_no_bitnami_images`. Consequence: `helm install --wait`
  blocks until the device is wired, so converge.yml / TF apply
  return only when `<host>:<port>` is ready to forward.

* `tests/molecule/e2e-local/converge.yml`: simplified — no inline
  LXD device add, no LB instance discovery, no `lxc` shell-out.
  `helm install` of the workload chart blocks on the post-install
  hook Job (chart-side), so by the time helm returns the proxy
  device is already attached. Converge then reads the
  `k8s-lab.io/api-proxy-port` annotation, rewrites the workload
  kubeconfig server URL to `https://<vagrant-vm>:<port>` + injects
  `tls-server-name`, writes
  `.artifacts/clusters/<cluster>.kubeconfig`, polls `/livez`
  through the runner-reachable endpoint, and installs
  `cni-calico` / `metallb` / `metallb-config` runner-side via
  `kubernetes.core.helm` with `delegate_to: localhost`. No more
  helm CLI on the VM, no chart .tgz copies, no VM-side workload
  kubeconfig materialisation.

* `tests/molecule/e2e-local/verify.yml`: every helm test runs
  runner-side via the rewritten kubeconfig (workload chart goes
  through the bootstrap kubeconfig as before). External HTTP GET
  to the MetalLB demo VIP still runs on the VM (correct egress
  through `ext6-ra-peer`). Final acceptance —
  `kubernetes.core.k8s_info kind=Node` (delegate_to localhost)
  asserts all `(controlplane_count + worker_count)` Nodes
  Ready=True through the rewritten kubeconfig.

* `ansible/roles/lxd_profiles`: removed the
  `capi-external-vendor-data.yaml.j2` template, the compose-time
  vendor-data render, the `_external_vendor_data` markers on the
  catalog, the verify-side byte-for-byte assertion, and the README
  section. Cloud-init's `cc_write_files` reads only user-data
  (`cloud-config.txt`); vendor-data write_files would never apply
  on a kubeadm-bootstrapped node where CAPI/CABPK owns user-data
  exclusively. The verify scenario now asserts both
  `cloud-init.user-data` and `cloud-init.vendor-data` slots stay
  empty on every profile this role manages. §8 lost the
  now-unused `k8s_lab_external_ra_accept` /
  `k8s_lab_external_ra_use_gateway` knobs.

* `tests/molecule/shared/inventory/group_vars/k8slab_host.yml`:
  added explicit `k8s_lab_workload_controlplane_count: 3` +
  `k8s_lab_workload_worker_count: 2` so the verify play sees them
  outside any role's defaults.

* `tests/molecule/shared/tasks/ext6-ra-source.yml`: comment-only
  refresh — references `KubeadmConfigSpec.files` (charts/capi-cluster-class)
  as the home of eth1 RA reception baseline now that vendor-data
  is gone.

* `ansible/roles/lxd_bootstrap_instance/defaults/main.yml`:
  comment-only refresh — `debian/13/cloud` image alias is now
  required because every CAPN-spawned workload node runs
  `KubeadmConfigSpec.files` write-files via cloud-init (CABPK
  user-data path), not because `lxd_profiles` ships vendor-data.

* `.yamllint`: added `charts/**/templates/` to the ignore list.
  Helm template syntax (`{{- … -}}`) is not parseable as YAML,
  so yamllint can never lint chart templates correctly; previously
  every render-time artefact in `templates/` failed `make lint-yaml`,
  the new ignore makes the pipeline match what `helm lint` already
  validates.

End-to-end evidence on a clean Vagrant VM (`make clean-local` →
`make -C tests/molecule e2e-local-vagrant-converge` →
`e2e-local-vagrant-verify`) with `capi-workload-cluster` 0.7.2:
* converge — `failed=0 ok=307 changed=5`. Helm install of the
  workload chart returned in 9.17 s (post-install hook Job
  matched LB instance, PATCH-ed LXD `proxy` device, exited);
  `/livez` runner-side probe through the rewritten kubeconfig
  endpoint succeeded after 31.96 s (kubeadm rolling).
* verify — `failed=0 ok=12 changed=3`:
  * three helm tests green (workload chart 11.21 s, cni-calico
    29.41 s, metallb-config 18.09 s) — all runner-side via the
    rewritten `.artifacts/clusters/lab-default.kubeconfig`;
  * Gate A external HTTP GET to MetalLB demo VIP from the VM
    returned 200 (1.68 s);
  * runner-side `k8s_info` through the rewritten kubeconfig
    sees all 3 CP + 2 worker Nodes Ready=True;
  * confirmation on the LXD host:
    `lxc --project=capi-lab config device get
    lab-default-swtr2-deb12-lb api-proxy listen` →
    `tcp:0.0.0.0:26818` (matches the Adler-32 hash port written
    to the Cluster CR annotation).

Memory rules applied in Step 15:
* `feedback_chart_required_values_hardcoded.md` — port computation
  formula hardcoded in helper, override only via legitimate
  optional values knob;
* `feedback_test_artifact_naming.md` — annotation prefix
  `k8s-lab.io/api-proxy-port`;
* `feedback_no_ad_hoc_fixes.md` — eth1 SLAAC wired
  declaratively through `KubeadmConfigSpec.files` (no live patches),
  LXD `proxy` device delivery owned by the chart's own Helm hook
  Jobs (no inline shell in Molecule, no `null_resource` in TF),
  and the dead vendor-data surface in `lxd_profiles` was removed
  end-to-end (template + compose + markers + verify + README +
  plan vars);
* `feedback_active_provisioning_monitor.md` — second monitor on
  Cluster phase + LXC count caught a CRD reject error before
  converge timeout (`field not declared in schema` came
  through in the TopologyReconciled condition).

## 13.1. `base_system`

**Status: done in Step 1 (2026-04-21).**

Installs only system packages that are allowed:

* `snapd`
* `python3`
* `python3-apt`
* `ca-certificates`
* `curl`
* `tar`
* `gzip`
* `xz-utils`
* `btrfs-progs` if a Btrfs pool is used

For Btrfs LXD explicitly requires `btrfs-progs`. ([Ubuntu Documentation][3])

In addition to the §13.1-packages scope the role owns the **btrfs pool contract**
(added in Step 1 at the operator's request for a realistic target
architecture): public vars `base_system_btrfs_pool_required`,
`base_system_btrfs_pool_mountpoint`, `base_system_btrfs_pool_label`,
`base_system_btrfs_pool_fstype`. Formatting and mounting of the disk
remain outside the role (Molecule shared prepare in tests, installer image in
prod); the role only **asserts the contract** when `required: true` — that the path
is mounted and is actually btrfs. This does not break the §2.7
ownership model (Ansible owns host bootstrap): disk provisioning remains a
prerequisite, the role only enforces the contract.

The role also initialises `/opt/capi-lab/{bin,etc}` and adds a
sysctl baseline (inotify, fs.file-max, net.ipv6.forwarding,
ipv4.ip_forward) + mandatory kernel modules (`overlay`,
`br_netfilter`, `nf_conntrack`) via persistent `modprobe` —
a precondition for LXD/containerd/kubelet downstream.

### Step 5 extensions (2026-04-22)

Refactor per the rule `feedback_required_values_hardcoded.md`. Previously
the entire substrate minimum lived in public defaults
(`base_system_packages_required`, `base_system_btrfs_packages`,
`base_system_sysctl_values`, `base_system_kernel_modules`),
which allowed a consumer to accidentally overwrite them to `[]`/`{}` —
preflight only checked `is sequence`/`is mapping` and skipped
an empty value, and the role silently installed nothing while downstream roles
(lxd_host, kube-proxy, containerd) failed with obscure symptoms.
Step 5 moves all substrate-required values into `vars/main.yml`:

* `_base_system_required_packages` — `snapd`, `python3`, `python3-apt`,
  `ca-certificates`, `curl`, `tar`, `gzip`, `xz-utils`.
* `_base_system_btrfs_required_packages` — `btrfs-progs`.
* `_base_system_required_sysctl` — inotify + file-max + ipv4/ipv6
  forwarding (kube-proxy hard-requires forwarding; inotify limits
  hit by kubelet/containerd/CNI in unprivileged LXC).
* `_base_system_required_kernel_modules` — `overlay`, `br_netfilter`,
  `nf_conntrack` (cross-reference with `lxd_profiles` `linux.kernel_modules`
  assertion, §13.6).

Defaults now expose only tunables and `*_extra_*`:
`base_system_extra_packages`, `base_system_btrfs_extra_packages`,
`base_system_extra_sysctl`, `base_system_extra_kernel_modules` — all
`[]`/`{}` by default, merged on top of required. For sysctl the merge
direction = `extras | combine(required)` ⇒ required keys win
on collision, so `base_system_extra_sysctl:
{net.ipv4.ip_forward: 0}` cannot silently disable forwarding.
Healthchecks assert against `_required_*`, not against the public
extras — the contract is checked against the baseline, not against what
the consumer happened to keep.

## 13.2. `lxd_host`

**Status: done in Step 2 (2026-04-21).**

A single role for host-side preparation of the LXD/LXC environment. It consolidates
what in earlier revisions was split into `lxd_snap` and
`lxd_network_ext_bridge`. The consolidation criterion: the role owns
**everything that is not an LXD entity** (i.e. everything that lives at the level of
host OS / snap / host networking), and nothing that is already an object
inside LXD (projects, storage pools, managed networks, profiles,
instances — they have their own roles).

Does:

* install `lxd` via snap;
* pin snap channel;
* apply snap refresh policy:

  * `snap refresh --hold=<duration>` or
  * `refresh.timer`;
* ensure LXD daemon is `waitready`;
* ensure initial trust/socket-side access is sane for subsequent roles;
* creates a host-side Linux bridge `br-ext6` (this is a regular host-bridge, not
  an LXD-managed network), attaches the uplink interface, ensures
  firewall/bridge sysctl does not break ingress;
* does not touch foreign host bridges and does not overlap with LXD-managed
  networks.

Snap docs confirm that auto-refresh is on by default, and `snap refresh --hold` and scheduling controls are officially supported. ([Snapcraft][15])

Implementation notes (recorded in Step 2):

* host-side bridge `br-ext6` is assembled via **systemd-networkd
  drop-ins** (`/etc/systemd/network/3{0,1}-br-ext6*.{netdev,network}`),
  not via shell `ip link add` / `brctl`. This lets you update
  the configuration declaratively via `networkctl reload` without disruption
  of existing interfaces.
* `networking.service` (ifupdown) is **not touched** — other NICs
  (mgmt) may remain under it. Match patterns are always explicit
  `Name=<iface>`, without wildcards.
* In Step 2 channel `6/stable` (feature-stable) is pinned, not the
  Canonical-recommended LTS `5.21/stable` — trade-off in favour of
  the plan's §2.11 "latest stable" policy. If Gate B or earlier
  surfaces incompatibility with CAPN — we downgrade back.
* 3 documented shell fallbacks remain (no native module):
  `snap set/get system refresh.*`, `/snap/bin/lxd waitready`,
  `snap list lxd`. The other paths are native
  (`community.general.snap`, `ansible.builtin.systemd`,
  `ansible.builtin.copy`).

## 13.3. `lxd_project`

**Status: done in Step 3 (2026-04-22) + Step 7 extension
(`restricted.devices.proxy: allow`) + Step 11 extension
(`restricted.devices.disk: allow` + `restricted.devices.disk.paths:
/boot`).**

Does:

* create `capi-lab`
* enable feature isolation (see deviation below on `features.networks`)
* set `restricted=true`
* allow needed restricted features:

  * nesting
  * unprivileged container privilege (hard-lock §2.8)
  * managed disk devices
  * low-level config (for `linux.kernel_modules` on kubeadm
    profiles)
  * **NIC devices: `allow`, not `managed`** — see below

LXD project restrictions support exactly this model. ([Ubuntu Documentation][4])

### Deviations / implementation notes (Step 3)

* **`features.networks=false` + `features.networks.zones=false`.** LXD
  documented does NOT support `bridge`-type networks in non-default
  projects: an attempted `POST /1.0/networks?project=capi-lab` with
  `type=bridge` fails with "Network type does not support non-default
  projects". So `features.networks=false` — capi-lab inherits
  default-project networks read-only. `features.networks.zones` must
  be consistent in parity. `capi-int` is created in the default project
  (see §13.5) and is resolved from profiles in capi-lab via inheritance.
  (§13.5 original wanted "managed bridge in capi-lab", but LXD does not
  architecturally allow this for bridge-type; the alternative — OVN or
  physical — is excessive for the MVP.)
* **`restricted.devices.nic=allow`**, not `managed`. LXD defines
  a "managed nic" as a NIC referencing an LXD-managed network via
  the `network:` key. The Kubernetes plane §4–5 attaches eth1 to
  the host-level Linux bridge `br-ext6` (owned by lxd_host), which LXD
  classifies as "unmanaged". Under `managed` the instance POST fails
  with "Only managed network devices are allowed". The alternative —
  wrap `br-ext6` in an LXD managed bridge via
  `bridge.external_interfaces` — is acceptable but deferred to a separate
  iteration; for Stage 1 we keep `allow`.
* **`restricted.containers.lowlevel=allow`** — `linux.kernel_modules`
  on profiles `capi-controlplane` / `capi-worker` is classified
  by LXD as low-level config, which under `restricted=true`
  is forbidden by default. Needed for the CAPN unprivileged kubeadm baseline.
  Permitted values of the key: only `allow` / `block`.
* **Implementation moved from `community.general.lxd_project` to
  `ansible.builtin.uri`** directly to the LXD REST API
  (`/1.0/projects`, `POST` / `PATCH`). The community module silently
  drops `features.*` transitions (accepted via
  `lxc project set` and raw REST, but the module returns `changed=0` and
  the PATCH never goes on the wire). `ansible.builtin.uri` — also a native
  module (§2.6.1), and gives full control over the payload. The decision
  is documented in `roles/lxd_project/tasks/project.yml`
  header comments and in the role README caveats.

### Step 4 extensions (2026-04-22)

Driver: bringing up `bootstrap_k3s` in an unprivileged LXC required two
additional restricted keys in the project + a refactor of the public
interface per the rule "role-required values are hardcoded" (memory
`feedback_required_values_hardcoded.md`).

* **`restricted.containers.interception=allow`** — without this key
  LXD rejects `security.syscalls.intercept.mknod` /
  `security.syscalls.intercept.setxattr` on profiles with "Container
  syscall interception is forbidden". These intercepts are required by
  containerd inside the bootstrap LXC (see §13.6 deviation for details).
* **`restricted.devices.unix-char=allow`** — without this LXD rejects
  the `kmsg` device on the capi-bootstrap/controlplane/worker profiles with
  "Unix character devices are forbidden". `/dev/kmsg` passthrough into
  the container is needed by kubelet's oomWatcher; the security trade-off
  is discussed in the §13.6 deviation.
* **Refactor: substrate baseline → `vars/main.yml`.** Previously
  `lxd_project_features`, `lxd_project_restricted` and
  `lxd_project_restrictions` were user-overridable defaults. This
  let a consumer "accidentally" remove a mandatory key and
  end up with a non-working substrate. Step 4 moves the entire baseline into
  `_lxd_project_required_features` / `_lxd_project_required_restricted`
  / `_lxd_project_required_restrictions` (role-internal,
  not public). Defaults now expose only
  `lxd_project_extra_restrictions: {}` for consumer
  *additional* restrictions on top of the baseline. Tasks merge
  required + extras into one payload.

### Step 7 extensions (2026-04-23)

* **`restricted.devices.proxy=allow`** added to
  `_lxd_project_required_restrictions`. The default LXD policy for a
  restricted project blocks proxy devices with the error "Proxy
  devices are forbidden", which breaks the canonical publish
  path of plan §15.5 (an optional proxy device on the bootstrap
  instance, forwarded via `lxd_bootstrap_instance_devices`).
  Rationale in vars/main.yml header + §15.5. The verify scenario
  `lxd-project` is extended with an assert on this key. The other
  substrate restrictions are unchanged; the security trade-off is moderate
  — the host firewall is owned by the operator, the LXD proxy listener starts
  only if the consumer explicitly added a device into host_vars.
* **`restricted.devices.disk: allow` + `restricted.devices.disk.paths:
  "/boot"`** in `_lxd_project_required_restrictions`. Per LXD docs the three
  modes for `restricted.devices.disk` are mutually exclusive:
  * `block` — forbids EVERY disk except root (our `host-boot`
    bind-mount is also blocked);
  * `managed` — only pool-backed (`pool=...`); path-based disks
    are forbidden, the `paths` whitelist is ignored;
  * `allow` — all disk types are permitted; security is provided by
    the `restricted.devices.disk.paths` whitelist of source-prefixes
    for path-based disks (pool-backed disks without a source key — do not
    fall under the whitelist gate).

  This is the only combination that simultaneously permits pool-backed
  root disks AND specific path-based bind-mounts. Substrate-required
  whitelist:
  * `/boot` — for the `host-boot` device on capi-controlplane /
    capi-worker profiles (§13.6); read-only mount gives kubeadm
    access to `/boot/config-<uname-r>` for SystemVerification preflight
    without bypass flags.

  Future host-share devices add a prefix to the comma-separated
  list `restricted.devices.disk.paths` instead of relaxing to
  `allow`-without-whitelist.

## 13.4. `lxd_storage_pools`

**Status: done in Step 3 (2026-04-22).**

Does:

* create storage pools;
* support `driver=btrfs`;
* support `source=<path>` / loop / device;
* support `btrfs.mount_options`;
* support custom volumes

Btrfs storage driver docs support these options explicitly. ([capn.linuxcontainers.org][16])

### Deviations / implementation notes (Step 3)

* **`source` semantics: block device, not mounted path.** The snap LXD
  is AppArmor-confined and has no access to arbitrary host paths outside
  `/var/snap/lxd/common/` (`system-files` plug is not enabled by
  default). An attempted `source=/var/lib/k8slab/lxd-pool` fails
  with "cannot access /var/lib/snapd/hostfs/...". The contract in the repo:
  `source=/dev/disk/by-id/<id>` — LXD receives a clean block
  device, formats it (`mkfs.btrfs` without `-f` ⇒ requires
  a signature-free disk) and mounts it in its namespace. The Molecule
  scenario wipes signatures via
  `tests/molecule/shared/tasks/prepare-clean-disk.yml` before
  converge. Production hosts are responsible for clean disk via
  the installer image.
* **`source` — one-time creation parameter.** LXD replaces
  `config.source` with the btrfs UUID after the first mount, and
  saves the original path in `config.volatile.initial_source`.
  The role healthcheck compares the declared source with
  `volatile.initial_source`; PATCH drift skips `source` (comparison
  of desired vs live would always be false).
* **Implementation — `ansible.builtin.uri`**, because
  `community.general` ships only `lxd_storage_pool_info` (read-only),
  without a CREATE module. `uri` + REST matches native-first
  (§2.6.1) — this is a native module, not a shell fallback.

### Step 5 extensions (2026-04-22)

Refactor per the rule `feedback_required_values_hardcoded.md`. Previously
the default `lxd_storage_pools_pools` entry put
`btrfs.mount_options: user_subvol_rm_allowed` directly into the public
defaults — a consumer overriding the list as a whole could accidentally lose
this key, and kubelet garbage-collection inside CAPN nodes would start
silently failing (unprivileged namespace cannot delete a
read-protected subvolume without `user_subvol_rm_allowed`, the disk fills
within a day from image churn).

Step 5 introduces a **driver-keyed required config baseline** in
`vars/main.yml`:

```yaml
_lxd_storage_pools_driver_required_config:
  btrfs:
    btrfs.mount_options: "user_subvol_rm_allowed"
  dir: {}
  lvm: {}
  zfs: {}
```

`tasks/pools.yml` builds `_lxd_storage_pools_effective_pools` in a compose
step: for each entry in the public list it merges
`item.config | combine(_driver_required_config[item.driver] | default({}))`.
Required wins at the LXD config merge level. POST / PATCH / healthchecks
iterate over the effective list, so required keys make it into live LXD
and are validated by verification. The public default entry now contains
only `source: ""` (required override, as before) —
`btrfs.mount_options` is not separately needed, it comes from the baseline.

Molecule fixtures (`tests/molecule/lxd-storage-pools/`,
`lxd-profiles/`, `lxd-bootstrap-instance/`, `bootstrap-k3s/`) updated:
they no longer duplicate `btrfs.mount_options` in host_vars overrides, only
`source` — which was the main regression point had the refactor been
reverted.

## 13.5. `lxd_network_int_managed`

**Status: done in Step 3 (2026-04-22).**

Does:

* create `capi-int` managed bridge;
* set IPv4/IPv6 DHCP/RA/NAT parameters;
* ensure dual-stack defaults

LXD managed bridge provides DHCP, IPv6 RAs and DNS via dnsmasq and does NAT by default. ([Ubuntu Documentation][2])

### Deviations / implementation notes (Step 3)

* **The bridge lives in the `default` project, not in `capi-lab`.** The end-to-end
  reason is the same as in §13.3: LXD refuses bridge-type networks in
  non-default projects ("Network type does not support non-default
  projects"). `capi-lab` sees `capi-int` via inheritance (owner
  — default project), which is possible because `lxd_project`
  sets `features.networks=false`. Profiles in capi-lab
  correctly resolve `parent: capi-int` nic devices — verified in the
  scenario verify.
* **Implementation — `ansible.builtin.uri`** (the same pattern as in
  §13.4): `POST /1.0/networks` + `PATCH /1.0/networks/<n>` for
  drift. There is no native CREATE module in `community.general`.
* **RA is always on if `ipv6.address` is set.** There is no separate key
  `ipv6.ra` in LXD; the only way to suppress RA is not to set
  `ipv6.address`. In our default dual-stack contract this is not
  a limitation, but it is recorded in the role README.

### Step 5 extensions (2026-04-22)

Refactor per the rule `feedback_required_values_hardcoded.md`. Previously
the default `capi-int` entry included `ipv4.nat`, `ipv4.dhcp`, `ipv6.nat`,
`ipv6.dhcp` directly in the public `config` — a consumer overriding
`lxd_network_int_managed_networks` could accidentally drop NAT (nodes
lose egress through the host, plan §4.1) or DHCP/RA (profiles with internal
nic come up without IP, §5.2). Preflight only checked
`ipv4.address | ipv6.address` (that at least one address family
is configured), there were no assertions on the NAT/DHCP keys.

Step 5 moves the substrate-required NAT/DHCP quartet into `vars/main.yml`:

```yaml
_lxd_network_int_managed_required_config:
  ipv4.nat:  "true"
  ipv4.dhcp: "true"
  ipv6.nat:  "true"
  ipv6.dhcp: "true"
```

`tasks/networks.yml` introduces a compose step (per the same pattern as
`lxd_storage_pools` in Step 5): for each entry it merges
`item.config | default({}) | combine(_required_config)` into
`_lxd_network_int_managed_effective_networks`. POST/PATCH/healthchecks
iterate over the effective list. The public default entry now holds
only address keys (`ipv4.address`, `ipv6.address`) + `name` /
`type` / `description` — everything the consumer can tune; NAT/DHCP
come from the baseline.

## 13.6. `lxd_profiles`

**Status: done in Step 3 (2026-04-22) — lean subset baseline;
brought to full CAPN unprivileged kubeadm baseline in Step 4;
**Step 11 (2026-04-26) read-only `host-boot` disk device (host's
`/boot` mount-in) on capi-controlplane for kubeadm
SystemVerification access to `/boot/config-<uname-r>` on
unprivileged-LXC; Step 12 (2026-04-26) extended the same
`host-boot` device to capi-worker** — `kubeadm join` preflight
runs the same `SystemVerification` branch as `kubeadm init`,
and without the `/boot` mount-in fails on the missing kernel
build-config file (Debian 13 kernel built without `CONFIG_IKCONFIG`,
`/proc/config.gz` physically does not exist). **Step 13 (2026-04-26)
extended `linux.kernel_modules` on capi-controlplane / capi-worker:
added `nf_tables` (kube-proxy `mode: nftables` via
KubeProxyConfiguration in KubeadmControlPlaneTemplate + Calico
`linuxDataplane: Nftables` in charts/cni-calico Installation CR — both
write rules through the nf_tables kernel API directly) and `vxlan` (Calico
Installation pinned VXLAN encapsulation on both pod IPPools — IPIP
IPv4-only, no BGP infra on the substrate, VXLAN the only
dual-stack-capable mode; calico-node creates a vxlan device in the LXC
host-netns on start). LXD pre-loads the modules before instance start,
fallback to kernel auto-load remains as a safety belt.** Eth1 RA
reception baseline (sysctl + systemd-networkd drop-in) lives in
`charts/capi-cluster-class` via `KubeadmConfigSpec.files` (Step
15, see PLAN §16.2 / §16.3) — this role does not carry profile-level
cloud-init.**

Mandatory profiles:

* `capi-base`
* `capi-bootstrap`
* `capi-controlplane`
* `capi-worker`

**Important:** `capi-controlplane` and `capi-worker` must be built on the **CAPN kubeadm profile baseline**, not invent settings from scratch. The CAPN reference kubeadm profile explicitly lists required kernel modules, `raw.lxc`, `security.nesting`, `security.privileged`, `/dev/kmsg`; for Canonical LXD the unprivileged path has a separate LXD-specific variant. ([capn.linuxcontainers.org][17])

For `v1.0` this repo implements only the **Canonical LXD unprivileged baseline** for Kubernetes nodes:

* `capi-controlplane` and `capi-worker` use the unprivileged CAPN kubeadm profile variant;
* `security.nesting=true` is enabled only where it is needed for the Kubernetes node path;
* `security.idmap.isolated=true` must be part of the hardened profile contract, unless a specific validated workload requires otherwise;
* the privileged kubeadm profile is intentionally not coded into the main path. ([17], [24], [34])

### Implementation notes (Step 3)

* Stage-1 baseline:
  * `capi-base` — root disk on `capi-fast` + eth0 on `capi-int`.
  * `capi-bootstrap` — `security.nesting=true`,
    `security.privileged=false`, `security.idmap.isolated=true`.
  * `capi-controlplane` / `capi-worker` — all of the above plus
    `linux.kernel_modules=br_netfilter,ip_vs,nf_conntrack,overlay`
    and eth1 on `br-ext6`.
* Native CRUD via `community.general.lxd_profile` works reliably
  (unlike the `lxd_project` diff-regression — see §13.3). Uri remains
  only in healthchecks for reading live state.
* **Ansible does NOT template dict-keys when loading YAML defaults.**
  An attempt to use `"{{ role_var }}"` as a key in the devices dict
  yields the literal string `{{ ... }}` on the wire, LXD rejects with
  "Name can only contain alphanumeric, …". In defaults we keep
  **static** names for device keys (`eth0`, `eth1`) — in LXD this is
  the "LXD-side device name" (an arbitrary label), the guest-side interface
  name goes through the `name:` attribute, which templates normally.
* Device-level healthchecks are **coarse**: `type` +
  headline fields (path+pool for disk, nictype+parent for nic) are checked. LXD
  sometimes normalises optional keys (`security.devlxd`, hwaddr), full
  dict-equality would give false drift.

### Step 4 extensions (2026-04-22)

Driver: `bootstrap_k3s` (§13.9) on the debian/13 LXD image required
the full CAPN unprivileged baseline + k3s-specific extensions.

* **`capi-bootstrap` baseline extended** to the same set as
  `capi-controlplane` / `capi-worker`: `security.syscalls.intercept.mknod=true`,
  `security.syscalls.intercept.setxattr=true` (containerd inside
  without them does not unpack images and does not create device nodes —
  symptom: `poststarthook/rbac/bootstrap-roles failed` + endless k3s
  crashloop), `linux.kernel_modules=br_netfilter,ip_vs,nf_conntrack,overlay`
  (kube-proxy / containerd / overlayfs). `capi-controlplane` and
  `capi-worker` also got these keys (the plan said "deferred to
  inner Kubernetes"; inner Kubernetes — which is k3s — has now
  defined it).
* **`raw.lxc: lxc.apparmor.profile=unconfined`** on all three
  kubeadm profiles. The default LXD apparmor profile in unprivileged
  containers blocks access to `/dev/kmsg` and part of the iptables/netlink
  ops of kube-proxy. Documented recipe for k3s-in-LXC (Proxmox
  forum, discuss.linuxcontainers.org/t/7539, triangletodd gist).
  Plan §2.8 hard-lock unprivileged still holds — only
  AppArmor confinement is removed, not the user-namespace boundaries themselves.
* **`/dev/kmsg` device passthrough (`unix-char`)** on all three
  kubeadm profiles. Without it kubelet's oomWatcher falls over on
  `open /dev/kmsg: no such file or directory` (even with
  `--kubelet-arg=feature-gates=KubeletInUserNamespace=true`,
  because the file is physically absent in the unprivileged LXC). Source
  is essentially read-only: write to /dev/kmsg is blocked by the host kernel's
  CAP_SYSLOG check, which an unprivileged container does not have in
  the host namespace. Risk model: information disclosure (host kernel
  log visible to the container) — acceptable for the local lab; a production
  consumer must re-evaluate (see research in the conversation log).
* **`host-boot` disk device** (`source: /boot`, `path: /boot`,
  `readonly: true`) on `capi-controlplane` and `capi-worker` (NOT on
  `capi-bootstrap` — bootstrap k3s does not do kubeadm preflight).
  kubeadm SystemVerification reads kernel build config (`CONFIG_*`
  for cgroups, namespaces, netfilter) and looks for the file in the order:
  `/proc/config.gz` → `/boot/config-<uname-r>` →
  `/usr/src/linux-<uname-r>/.config` →
  `/lib/modules/<uname-r>/config`. Debian 13 kernel built without
  `CONFIG_IKCONFIG`, so `/proc/config.gz` physically does not
  exist, and `modprobe configs` inside unprivileged-LXC
  unconditionally fails with `Module configs not found in directory ...`
  (no `configs.ko` module even on the host, nothing to load). The read-only
  bind-mount of host `/boot` makes the second lookup path (`/boot/config-<uname-r>`)
  available inside the container — kubeadm reads it directly and passes
  preflight without bypasses. Inside the LXC `uname -r` returns the host
  kernel, so the paths match. Risk model: information disclosure
  (host kernel image, initrd, grub config visible to the container in read-
  only) — acceptable for the local lab + workload Cluster path; a production
  consumer can restrict the single-file mount via an ansible-templated
  device path with `uname -r` lookup, but the kernel config by itself is not
  a secret.
* **Refactor: substrate baseline → `vars/main.yml`.** Previously
  `lxd_profiles_profiles` was a user-overridable list with the entire content
  of each of the 4 profiles. Permissive override → a consumer could "accidentally"
  remove a substrate-required key. Step 4 moves the full per-profile
  spec into `_lxd_profiles_catalog` (vars/main.yml, role-internal).
  Defaults expose only shared inputs (storage_pool, ifnames)
  + per-profile `lxd_profiles_capi_<role>_extra_config / _extra_devices`
  for tuning on top of the baseline. A new `tasks/compose.yml` builds
  `_lxd_profiles_effective` from catalog + extras; profiles.yml and
  healthchecks.yml iterate over it.
* **Restart-on-profile-change**. Per LXD docs ([instance_options ref][lxd-options])
  most substrate-required keys (`security.privileged`,
  `security.idmap.isolated`, `security.syscalls.intercept.*`,
  `raw.lxc`) have `Live update: no` — LXD accepts the PATCH of the profile
  but does not propagate to running instances. Without restart, profile
  changes silently drift. Step 4 adds logic to `tasks/profiles.yml`:
  after apply the list of changed profiles is computed, running instances
  in the project are listed, those whose changed profile is in
  `profiles[]` are restarted. Restart via
  `community.general.lxd_container state=restarted`. Caveat
  (documented in README): if the first apply went through (changed=true)
  but the restart failed, on re-run the profile already matches (changed=false) →
  the restart is not repeated → the instance stays in drift until operator
  intervention. A robust drift detector (comparison of
  instance `expanded_config` vs profile baseline) is deferred.
* **Verify scenario proves restart-on-change** end-to-end:
  `tests/molecule/bootstrap-k3s/verify.yml` after the main asserts
  captures the container's init PID, hits `lxd_profiles` with
  `lxd_profiles_capi_bootstrap_extra_config: {user.k8slab-restart-test: ...}`
  (the marker forces `lxd_profile` to report `changed=true`),
  captures the PID after, asserts the PID changed. After the test the marker
  is removed via `ansible.builtin.uri` PUT (PUT — the only
  way to remove a config key in LXD; PATCH with `merge_profile=true`
  only adds/updates, cannot remove), so that downstream
  scenarios on the same VM do not see pollution.

### Step 9 extensions — cloud-init substrate baseline

**Status: superseded in Step 15 (2026-04-28).** Step 9 previously put
substrate-required cloud-init `vendor-data` into `capi-controlplane` and
`capi-worker` LXD profiles for the eth1 RA reception baseline. Step 15
moved this baseline into `charts/capi-cluster-class` via
`KubeadmConfigSpec.files` + `preKubeadmCommands` (see PLAN §16.2 /
§16.3 — on a kubeadm-bootstrapped node CABPK owns user-data
exclusively, and the `cc_write_files` module does not merge vendor-data
write_files into the combined cloud-config). Profile-level cloud-init
slots are now empty on all profiles of this role; the verify scenario
asserts the absence of `cloud-init.user-data` / `cloud-init.vendor-data`.

[lxd-options]: https://documentation.ubuntu.com/lxd/latest/reference/instance_options/

## 13.7. `lxd_bootstrap_instance`

**Status: done in Step 3 (2026-04-22) — the first role of Phase 3.
Step 5 (2026-04-22) moved required profiles into vars/main.yml +
moved the readiness gate into tasks/wait_ready.yml. Step 9 (2026-04-24)
switched the default image alias `debian/13` → `debian/13/cloud` —
see "Step 9 extensions" below.**

Creates:

* `capi-bootstrap-0`
* in project `capi-lab`
* with the right profile
* with networking attachment
* with nesting

### Implementation notes (Step 3)

* Native `community.general.lxd_container` — a full-featured CRUD module
  with project scoping, profiles, image source, state machine. The diff
  regression of the `lxd_project` module did not surface on this path; uri
  was not needed here.
* The default image source — **Canonical LXD simplestreams remote**
  `https://images.lxd.canonical.com`, alias `debian/13`. The URL
  changed relative to the widely known
  `https://images.linuxcontainers.org` after the LXD/Incus split in
  2023 — the `images:` remote in the stock LXD snap now points
  to Canonical hosting, and the `debian/13` fingerprint is absent
  from the Incus catalog. Consumers on Incus can override
  `lxd_bootstrap_instance_image_server` back.
* Profiles: `[capi-base, capi-bootstrap]` (root disk, internal nic,
  nesting, unprivileged, idmap isolated).
* `state: started`, `wait_for_container: true` — the module blocks
  the task on the LXD operation (image pull + start). **Note (Step 5):**
  `wait_for_ipv4_addresses: true` was used initially but removed in the
  Step 5 readiness-gate refactor (§13.7 Step 5 section below) — the module
  would wait for IPv4 on **all** non-lo interfaces, and k3s-inside-the-container
  in Step 4 brings up veth pairs without IPv4 → infinite poll.
  Readiness has been moved to `tasks/wait_ready.yml`, which checks **one**
  `readiness_ifname` (default `eth0`).
* `ignore_volatile_options: true` — silences false drift on
  `volatile.*` (macs, last-state timestamps).
* **LXD does NOT replicate inherited profile devices into
  `instance.devices`** — only instance-level overrides appear
  there. Verify of the bootstrap container checks eth0 via runtime
  `state.network` (host-side bridge port bound), and parent/nictype
  correctness stays in the `lxd_profiles` scenario verify.

### Step 5 extensions (2026-04-22)

Refactor per the rule `feedback_required_values_hardcoded.md`. Previously
`lxd_bootstrap_instance_profiles: [capi-base, capi-bootstrap]` was a
public default — a consumer overriding it to `[capi-base]`
(or `["default"]`) could remove the mandatory `capi-bootstrap` profile,
causing the bootstrap container to lose all substrate-required keys
(nesting, idmap isolation, kmsg passthrough, syscall intercepts),
and then k3s fell over with obscure symptoms inside.

Step 5 moves the required chain into `vars/main.yml`:

```yaml
_lxd_bootstrap_instance_required_profiles:
  - "capi-base"
  - "capi-bootstrap"
```

The public variable becomes `lxd_bootstrap_instance_extra_profiles: []`
for *additional* profiles on top of required. In
`instance.yml`/`healthchecks.yml` composition is inline:
`_required_profiles + lxd_bootstrap_instance_extra_profiles` — no
separate set_fact. In other Step 5 refactors (storage_pools /
network_int_managed) set_fact is needed because merge is done in a loop
with an accumulator; here the list is built by trivial concatenation,
the inline variant is shorter and tag-safe (does not depend on whether
the consumer ran the preflight tag before healthchecks).

#### Readiness gate refactor (Step 5)

The first regression run after the required-profiles refactor (Step 5)
showed an anomaly unrelated to profiles: the idempotence step of the
`bootstrap-k3s` scenario hung for exactly 300 s on the task
`lxd-bootstrap-instance | instance | ensure bootstrap container`,
although the converge step finished in ~1.6 s, and the container was already in
`Running` state with IPv4 on eth0. A pre-existing problem that
Step 4 scope did not touch but the regression run of Step 5 exposed.

**Cause.** The role delegated readiness semantics to the
`community.general.lxd_container` flag `wait_for_ipv4_addresses: true`.
The module interprets it as "poll state.network until
every non-`lo` interface has a non-link-local IPv4". Before
Step 4 the bootstrap container had **only eth0** — and the DHCP lease
appeared within fractions of a second. After Step 4 inside the container
k3s starts, which through embedded CNI brings up `cni0`,
`flannel.1` and three veth pairs (`vethXXXX`) for the pod network. The veths
have no IPv4 and will not — these are link-local endpoints. The module, seeing
them on the idempotence run, enters an infinite poll until
`wait_timeout` (120 s by default, 300 s in the molecule override).

A recurrence of this problem in any future role that
creates a container with an inner stack (CAPN workload nodes in Phase 5+,
Docker-containers under a registry, VM-in-container variants) is guaranteed.
So Step 5 treats not the symptom, but the contract.

**Architectural fix — variant C.** Role owns readiness, module
owns CRUD:

1. **Module — only LXD CRUD.** From the call
   `community.general.lxd_container` removed `wait_for_ipv4_addresses`.
   `wait_for_container: true` kept — it blocks the module on the
   image-pull/start operation (needed on cold-cache converge), but
   **does not** touch network state.
2. **New `tasks/wait_ready.yml`** — role-owned readiness gate.
   Polls `GET /1.0/instances/<name>/state?project=<proj>` with an
   `until:` condition checking one specific interface:
   ```jinja
   (state.network | dict2items
    | selectattr('key','equalto', lxd_bootstrap_instance_readiness_ifname)
    | ... | selectattr('family','equalto','inet')
    | rejectattr('scope','equalto','local') | list | length > 0)
   ```
   `retries = wait_timeout // 4`, `delay = 4 s`. On idempotence eth0
   already has a lease → the first poll passes → `changed_when: false`.
   On the first converge — we wait for the DHCP lease on eth0 (usually <5 s after
   `wait_for_container` returns control).
3. **Dispatcher** (`tasks/main.yml`): the order is now
   `preflight → instance → wait_ready → healthchecks`. Gate with
   its own tag `lxd_bootstrap_instance_wait_ready`.
4. **Contract in `defaults/main.yml`:**
   - `lxd_bootstrap_instance_wait_ipv4` → renamed to
     `lxd_bootstrap_instance_wait_ready` (semantic clarification —
     it is now a **role-owned gate**, not a module flag);
   - added `lxd_bootstrap_instance_readiness_ifname: "eth0"` —
     an explicit extension point (`k8s_lab_guest_internal_ifname` from plan §5.3);
   - `lxd_bootstrap_instance_wait_timeout: 120` — shared wall-clock
     budget for both the module's `wait_for_container` and the readiness poll.

**Advantages over a point fix:**
- The role's readiness contract is **EXPLICIT** in code (`tasks/wait_ready.yml`),
  not hidden inside a module heuristic;
- Immune to any inner-container network growth: k3s CNI, Docker,
  sidecar containers, future CAPN node agents;
- The pattern is reused in future container-creating roles
  (Phase 5+ CAPN workload machine templates);
- Fast on idempotence (first poll exits immediately);
- Consistent with the §2.7 ownership model: ansible (Stage 1 scope) —
  host/LXD bootstrap; inside the container there are no rulesets, only
  observability via REST.

**Regression verification** (`.artifacts/regression-logs/SUMMARY.txt`,
2026-04-22T21:20:33):

| Scenario | Before Step 5 wait_ready | After |
|---|---|---|
| bootstrap-k3s | **496 s** (300 s idempotence hang) | **197 s** |
| lxd-bootstrap-instance | 180 s | 147 s |
| other 7 | unchanged | unchanged |

Savings of ~5 minutes on a full 9-scenario run (1471 s → 1132 s). All 9
scenarios PASS.

### Step 9 extensions (2026-04-24)

The default `lxd_bootstrap_instance_image_alias` is switched from
`debian/13` to `debian/13/cloud`. Any image that goes into the capi-lab
project must be cloud-init-capable — `KubeadmConfigSpec.files`
from `charts/capi-cluster-class` (PLAN §16.2 / §16.3) delivers the eth1
RA reception baseline via user-data `write_files` on every
CAPN-spawned node. The bootstrap k3s instance is layered only with
`capi-base` + `capi-bootstrap` (cloud-init slots are empty), but we
keep the same image for the whole surface: LXD caches a
single rootfs, diagnostics are predictable, switching the worker
path to a custom image in a consumer overlay does not require refactoring
the bootstrap path.

The alias `debian/13/cloud` exists in Canonical's
`https://images.lxd.canonical.com` simplestreams remote (verified
`lxc image list images: debian/13/cloud`) and weighs ~130 MiB versus
~96 MiB for `debian/13` — 34 MiB extra for cloud-init + dependencies,
acceptable for the dev harness.

No regressions on the existing scenarios `lxd-bootstrap-instance` /
`bootstrap-k3s` / `bootstrap-clusterctl` / `bootstrap-capn-secret` /
`export-artifacts` are expected — cloud-init inside the bootstrap
container quietly finishes as a no-op (cloud-init slots on the
profiles are empty), k3s starts as before.

## 13.8. `binary_fetch`

**Status: done in Step 4 (2026-04-22) — Phase 3.5 (deferred
from Phase 1, see §14.2 / §15.7).**

Downloads into `/opt/capi-lab/bin` (host-side):

* `kubectl`
* `clusterctl`
* `k3s`

Each binary is a pinned version (tracks §8a verified version log) +
checksum verification via `ansible.builtin.get_url checksum:
sha256:<digest>`. Owner/group/mode is derived from
`base_system`-owned `/opt/capi-lab/bin` (root:root 0755).

### Implementation notes (Step 4)

* **Three checksum styles**, one per upstream:
  * `plain` (kubectl) — GET `<url>.sha256`, the file = a single line of hex.
  * `manifest` (k3s) — GET `sha256sum-<arch>.txt` in `sha256sum(1)`
    format (`<hex>  <name>` per line), parsed via
    `regex_findall(multiline=true)` by `checksum_entry` =
    asset name.
  * `pinned` (clusterctl) — upstream cluster-api releases do NOT
    publish a sha256 file (verified 2026-04-22 on v1.12.5 — the release
    asset list contains only raw clusterctl-*-* binaries and yaml
    manifests, no sha256). The hash is kept directly in
    `defaults/main.yml` next to the version pin
    (`binary_fetch_clusterctl_checksum_sha256`); audited via
    `sha256sum` on the control node on each version bump.
    The verification date marker goes inline there.
* **`ansible.builtin.get_url` is idempotent**: on re-run it
  compares the destination sha256 with the one in `checksum:`,
  skipping the download if they match.
* **Native-first path** (plan §2.6.1) — no shell wrappers,
  no `install.sh` from upstream. `uri` for the checksum file +
  `get_url` for the binary.
* Healthchecks run every binary via `--version` (or
  `version --client --output=yaml` for kubectl, `version --output=yaml`
  for clusterctl) and match the self-reported version against the pinned —
  catches silent download corruption.

## 13.9. `bootstrap_k3s`

**Status: done in Step 4 (2026-04-22) — the first role of Phase 4 +
Step 5 substrate-required disables refactor + Step 11 dual-stack pod
CNI (`--cluster-cidr`/`--service-cidr`/`--cluster-dns` v4+v6,
`--flannel-ipv6-masq`, `--disable-network-policy`, `--node-ip=v4,v6`
via an ExecStart wrapper-launcher script).**

Inside the bootstrap LXC:

* lays out `k3s` (host `/opt/capi-lab/bin/k3s` → container
  `/usr/local/bin/k3s`);
* renders and pushes the systemd unit + env file;
* starts `k3s.service` with `--disable=traefik --disable=servicelb`
  + substrate-required hardcoded flags (see below);
* polls kube-apiserver via `kubectl get nodes` until Ready.

### Implementation notes (Step 4)

* **Execution model: shell-via-`lxc exec` / `lxc file push`,
  not the `community.general.lxd` connection plugin.** In the Molecule harness
  the controller (my dev machine) is NOT an LXD host — the host is the
  Vagrant VM. The `community.general.lxd` connection plugin shells out
  `lxc` locally on the controller, which is not appropriate. Pure SSH→host→`lxc`
  shell — the same boundary as `lxd_bootstrap_instance` uses
  via REST. A documented shell fallback (plan §2.6.1).
* **`lxc` CLI — absolute path `/snap/bin/lxc`** via
  `bootstrap_k3s_lxc_cli`. The LXD snap puts `lxc` in `/snap/bin/`,
  which is not on the default PATH in non-interactive SSH sessions.
* **Idempotent binary push**: stat host k3s → sha256sum via
  `lxc exec` inside the container → push only if the digests differ.
* **Idempotent unit/env push**: render via `template` into a
  persistent staging path (`/opt/capi-lab/etc/bootstrap_k3s/`),
  read in-container content via `lxc exec cat`, compute the drift
  flag, push only on drift. Persistent staging path (and not /tmp)
  so that the template itself is idempotent on rerun.
* **Hardcoded substrate-required flags in `templates/k3s.service.j2`**
  (memory rule `feedback_required_values_hardcoded.md` —
  "if the role does not work without it, hardcode in the template, not
  a variable"):
  * **`--disable-cloud-controller`** — k3s embedded
    cloud-controller-manager in unprivileged LXC hits a RBAC
    race condition (k3s-io/k3s#7328): CCM tries to read the
    `extension-apiserver-authentication` configmap before
    `poststarthook/rbac/bootstrap-roles` creates a
    RoleBinding for it. CCM exits → k3s shutdown → systemd Restart=always
    → endless crashloop. k3s-lab has no cloud integration to lose, so
    CCM is fully disabled.
  * **`--kubelet-arg=feature-gates=KubeletInUserNamespace=true`** —
    kubelet in an unprivileged container opens `/dev/kmsg` from
    oomWatcher; without this gate (or a physically mounted
    `/dev/kmsg`, which we also added in profile §13.6)
    kubelet falls over at start. Defense-in-depth — we do both
    fixes.
  * Consumers can add *additional* kubelet feature
    gates via `bootstrap_k3s_extra_kubelet_feature_gates: []`
    (rendered into the same `--kubelet-arg=feature-gates=<csv>` on top of the
    required gate, you cannot remove it).
  * **Dual-stack pod / service network** —
    `--cluster-cidr=10.42.0.0/16,fd42:77:42::/56`
    `--service-cidr=10.43.0.0/16,fd42:77:43::/112`
    `--cluster-dns=10.43.0.10,fd42:77:43::a`
    `--flannel-ipv6-masq`. Source — substrate-required values in
    `vars/main.yml` (`_bootstrap_k3s_required_{cluster_cidr,service_cidr,cluster_dns}_v[46]`,
    `_bootstrap_k3s_required_flannel_ipv6_masq`), not consumer-tunable.
    Why: §16.3 workload-cluster CR + LXCCluster get an IPv6 endpoint
    via CAPN auto-derivation on capi-int (LXD-managed dual-stack
    network, §5.2). CAPI controllers live as pods in bootstrap k3s and
    must have IPv6 reachability via pod CNI to reach the workload LB
    endpoint — otherwise `Cluster.spec.controlPlaneEndpoint`
    stays unreachable, KCP does not get Machine.nodeRef and the cluster
    never reaches Ready. IPv4 portions = k3s upstream defaults
    (10.42/16, 10.43/16); IPv6 ULAs from `fd42:77::/48` family,
    distinct from capi-int (`fd42:77:1::/64`) and workload pod/service
    CIDRs (`fd42:77:2::/56` / `fd42:77:3::/112`).
    `--flannel-ipv6-masq` is mandatory — without it pod-originated IPv6
    leaves from a non-routable pod-CIDR and the packet is dropped at the first
    hop.
  * **`--disable-network-policy` (kube-router off)** —
    `_bootstrap_k3s_required_disable_network_policy: true`. k3s
    embeds kube-router as the NetworkPolicy controller. Under dual-stack
    `--cluster-cidr` inside the unprivileged LXC bootstrap container
    kube-router's IPv6-init phase fails with `Shutdown request
    received: failed to start networking: unable to initialize
    network policy controller: IPv6 was enabled, but no IPv6 address
    was found on the node` — even when kubelet correctly registers
    both families in `Node.status.addresses` (visible via
    the `k3s.io/node-args` annotation). Bootstrap k3s — a single-node mgmt
    cluster for CAPI/CAPN controllers; NetworkPolicy enforcement is a
    multi-tenant concern that does not apply here. Workload
    clusters get their own CNI + policy via the §16.4 module
    (Calico + MetalLB add-ons) — a separate network plane.
  * **`--node-ip` via wrapper-launcher on ExecStart.** kubelet
    auto-detects exactly ONE address from the default route (IPv4); under dual-
    stack k3s this is not enough and the network-policy controller falls over with
    "IPv6 was enabled, but no IPv6 address was found on the node" in a
    Restart=always loop. The addresses of the bootstrap container are assigned by
    LXD (DHCPv4 + SLAAC/DHCPv6) — the specific values are not known at
    template-render time. Solution: the role delivers a short
    POSIX-shell wrapper `/usr/local/sbin/k3s-server-launcher` into the container (template
    `k3s-server-launcher.sh.j2`), which is called by systemd as
    `ExecStart`. The wrapper INSIDE the container on every
    `systemctl start k3s` resolves the global-scope IPv4 + IPv6 on
    `eth0` via `ip -o addr show` and `exec`s
    `k3s server --node-ip=<v4>,<v6> "$@"`, forwarding all other
    flags from the systemd unit (write-kubeconfig-mode, disable-cloud-controller,
    cluster-cidr, service-cidr, etc.) as positional arguments.
    `exec` passes PID and Type=notify signals further on to k3s, systemd
    sees k3s as Main PID normally. EnvironmentFile-based approaches do NOT
    work: systemd loads the EnvironmentFile ONCE at unit
    startup, BEFORE any Exec* starts — `${K3S_NODE_IP}`,
    written by ExecStartPre, would stay empty at the moment of substitution
    in ExecStart. Without §8 globals, without cross-role coupling, without an IP
    pin to a specific bootstrap LXC — multiple bootstrap-shaped
    instances work without collisions. Source of truth — `vars/main.yml`
    constants: `_bootstrap_k3s_required_node_iface: "eth0"`,
    `_bootstrap_k3s_required_launcher_path:
    "/usr/local/sbin/k3s-server-launcher"`. Idempotence — drift-compare
    staged-vs-live (the same pattern as for unit/env file); push
    triggers the handler restart k3s.
* **`Type=notify` is kept**, as in upstream
  `github.com/k3s-io/k3s/blob/master/k3s.service`. After all the
  substrate fixes k3s correctly delivers sd_notify READY=1 and
  systemd transitions to `active` (previously with a broken substrate it hung in
  `activating`); the tests strictly require `active`.
* **Healthcheck — `kubectl get nodes` retry loop**, not systemd
  state. Real cluster readiness = node Ready, not systemd transition.
  Defaults: 60 retries × 4s = 240s; in the Molecule scenario extended to
  90 × 4 = 360s on cold-image-pull.
* **Verify scenario** checks: container Running, in-container
  k3s sha256 == host k3s sha256, `systemctl is-active k3s.service ==
  "active"`, `kubectl get nodes` ready, `/etc/rancher/k3s/k3s.yaml`
  existing + non-empty. Plus end-to-end test for restart-on-profile-change
  behaviour of `lxd_profiles` (see §13.6 Step 4 deviation).

### Step 5 extensions (2026-04-22)

Refactor per the rule `feedback_required_values_hardcoded.md`. Previously
`bootstrap_k3s_disable_components: [traefik, servicelb]` was a public
default. For this lab both disables are substrate-required (plan
§2.9 / §5.5 deliver ingress and LoadBalancer via Terraform Helm
releases; bundled klipper-LB and traefik would come up in a race with
the add-ons pass and break the cluster). A consumer override to `[]`
passed `is sequence` preflight and silently killed the substrate.

Step 5 moves the required list into `vars/main.yml`:

```yaml
_bootstrap_k3s_required_disable_components:
  - "traefik"
  - "servicelb"
```

The public variable is `bootstrap_k3s_extra_disable_components: []`
for *additional* disables (e.g. `metrics-server`). The Jinja
template `k3s.service.j2` now iterates
`(_required + extra)` — required is always rendered, the consumer can
only add. The template header comment has been updated to list ALL
substrate-required ExecStart flags (pre-existing
hardcoded `--disable-cloud-controller` and
`--kubelet-arg=feature-gates=KubeletInUserNamespace=true` are now
mentioned alongside vars-sourced disables).

## 13.10. `bootstrap_clusterctl`

**Status: done in Step 6 (2026-04-23) — Phase 4 continuation, §15.3.
Step 8 (2026-04-23) added the pin `tls-server-name: kubernetes.default.svc`
in the rewritten kubeconfig (see Step 8 extensions below) — one kubeconfig
now works from any vantage point without an IP in the cert.**

Turns a bare bootstrap k3s cluster into a CAPI management cluster:

* materialises a host-side kubeconfig: `lxc file pull
  /etc/rancher/k3s/k3s.yaml` from the container + rewrites
  `clusters[].cluster.server` from `https://127.0.0.1:6443` to
  `https://<container-eth0-ipv4>:6443` (k3s default — 127.0.0.1, which
  is useless for host-side clusterctl);
* renders a pinned `clusterctl.yaml` with the CAPN `incus` provider (URL
  `github.com/lxc/cluster-api-provider-incus/releases/<ver>/infrastructure-components.yaml`);
* `clusterctl init --infrastructure incus:<ver>` with
  `CLUSTER_TOPOLOGY=true` env (plan §8 `k8s_lab_cluster_topology_enabled`);
* `--wait-providers` + role-side `kubernetes.core.k8s_info` polling until
  Available on cert-manager + 4 CAPI/CAPN deployments.

### Implementation notes (Step 6)

* **Native-first execution.** All calls to the bootstrap cluster —
  via `kubernetes.core.k8s_info` (probe + healthcheck-poll +
  Provider CRs list). `kubectl` commands are absent. The only
  commands: `clusterctl init` (no native wrapper) and `lxc file pull`
  (controller≠LXD host, by the same logic as bootstrap_k3s, see §13.9).
* **Idempotence model.** clusterctl init is not idempotent —
  re-invocation against an initialised cluster fails with "already an
  instance of <provider>". Pre-check: `k8s_info` for
  `capn-system/capn-controller-manager` Deployment; if found →
  the init task is skipped (clusterctl init is all-or-nothing — the presence
  of one indicates the presence of all). On repeat converges the
  PLAY RECAP gives `changed=0`.
* **CAPI Provider CR quirk.** `providers.clusterctl.cluster.x-k8s.io`
  CRD has `type` and `providerName` on the TOP-LEVEL of the object (not
  `spec.type` / `spec.providerName`). A regression that was caught: jsonpath
  `{.spec.type}` in the first version returned `/\n/\n/\n/` — empty fields.
  Fixed to `{.type}/{.providerName}` (and after the migration to
  `k8s_info` an assert via `selectattr` directly).
* **Server-URL rewrite via map+combine recursive.** The Jinja construct
  `clusters | map('combine', {'cluster': {'server': '...'}},
  recursive=True)` correctly covers every `clusters[]` (k3s writes
  one, but the pattern will survive if the CR is multi-cluster).
* **Substrate-required in `vars/main.yml`** (rule
  `feedback_required_values_hardcoded.md`):
  - `_bootstrap_clusterctl_required_provider_name: "incus"` — provider
    name, hardcoded by the upstream CAPN registry;
  - `_bootstrap_clusterctl_required_deployments` (4 CAPI/CAPN) +
    `_bootstrap_clusterctl_required_cert_manager_deployments` (3
    cert-manager) — the list of Deployments the role waits on;
  - `_bootstrap_clusterctl_lxd_socket: "/var/snap/lxd/common/lxd/unix.socket"`
    + `_bootstrap_clusterctl_lxc_cli: "/snap/bin/lxc"` — snap-LXD
    invariants;
  - `_bootstrap_clusterctl_container_kubeconfig_path: "/etc/rancher/k3s/k3s.yaml"`
    — k3s always writes there.
* **Public defaults — only tunables:** `capn_version` (sourced from
  the global `k8s_lab_capn_provider_version`), `capn_provider_url`
  (overridable for airgap mirror),
  `bootstrap_clusterctl_cluster_topology_enabled`, extras-knobs (extra
  providers / init flags / wait deployments), timeouts/retries, paths
  owned by the role itself.
* **`async + poll` for clusterctl init.** Cold-cache image pulls
  (cert-manager + 4 providers) may take ~3 min; foreground SSH
  timeouts on shared molecule runs would abort. async with poll=5s,
  budget = `bootstrap_clusterctl_init_timeout` (default 600s).

### Step 8 extensions (2026-04-23)

Driver: `export_artifacts` (§13.12) ships the kubeconfig to the runner, and
the runner must actually reach the bootstrap API through the LXD proxy
device (§15.5). If the server URL in the kubeconfig points to
`https://<proxy_endpoint>:<port>`, and the client does TLS verify by
the host part of the URL, then `<proxy_endpoint>` **must** be in the SAN of the k3s
cert — otherwise TLS fail. Previously this meant either `--tls-san <host_ip>`
(bound to an IP → fragile; breaks on host IP change), or
`insecure-skip-tls-verify` (security trade-off).

Step 8 introduces a cryptographically correct third way: pin
`tls-server-name: kubernetes.default.svc` in `clusters[].cluster`
of the rewritten kubeconfig. `kubernetes.default.svc` — the standard
Kubernetes internal service DNS name, **always** embedded as a DNS
SAN in the k3s (and any conformant distribution) server cert by
default. Kubectl/client-go/terraform-kubernetes-provider natively
support `tls-server-name` — it overrides SNI + hostname
match to this value, **not** to the host part of the URL. Result: one
kubeconfig works byte-for-byte from any vantage point
(in-container, LXD host, dev machine via LXD proxy, production
runner via the same proxy) — without an IP in the cert, without `--tls-san`
overrides, without `insecure-skip-tls-verify`. Fix in one line:
`tasks/kubeconfig.yml` adds `tls-server-name` to the combine-rewrite
on top of the `server` rewrite.

* **Substrate-required added:**
  - `_bootstrap_clusterctl_required_tls_server_name: "kubernetes.default.svc"`
    — k8s standard, baked-in SAN of the k3s cert.
* **Regression-safe for `bootstrap_capn_secret`** (§13.11): its
  k8s_info calls use the same kubeconfig; TLS match moves
  from `IP:10.77.0.176` to `DNS:kubernetes.default.svc` — both are in the SAN
  list, both valid. The idempotence of `bootstrap_capn_secret`
  is preserved (proven by the Step 8 regression run: changed=0 on
  repeat converges).

## 13.11. `bootstrap_capn_secret`

**Status: done in Step 6 (2026-04-23) + Step 10 §8 global binding
for project/network + Step 11 namespace fanout (the Secret is materialised
in every ns from `k8s_lab_capn_identity_namespaces`, the former
`_required_namespace: capn-system` substrate value is removed — CAPN does not
read the Secret from its controller namespace).**

Materialises the CAPN identity Secret in the bootstrap k3s cluster + adjacent
host/LXD-level preconditions without which the Secret could not get
a working endpoint and trust entry. Owner of three cross-cutting obligations:

* **host LXD HTTPS listener.** PATCH `/1.0` via REST: sets
  `core.https_address: <bridge-ipv4>:8443`, where `<bridge-ipv4>` —
  the IP of the `capi-int` LXD-managed bridge (gateway as seen from inside the bootstrap LXC).
  Auto-resolve via `GET /1.0/networks/<network>/state →
  state.addresses[]`. The listener is reachable only from the capi-int subnet
  (CAPN inside the bootstrap LXC) — on external NICs of the host nothing is
  exposed.
* **client TLS keypair + LXD trust.** `community.crypto.openssl_privatekey`
  → `openssl_csr` (with `extended_key_usage: [clientAuth]`) →
  `x509_certificate` (provider=selfsigned). SHA-256 fingerprint via
  `community.crypto.x509_certificate_info` (native, not shell openssl).
  Probe trust store via REST `/1.0/certificates/<fingerprint>`
  (200/404), POST only on absence. **`restricted: true +
  projects: ["{{ k8s_lab_project_name }}"]`** — CAPN cannot
  touch foreign projects.
* **K8s Secret apply — fanout across the namespaces of workload Cluster
  CRs.** `kubernetes.core.k8s` with `apply: true, state: present`
  (server-side apply), 5 substrate-required keys (`server`,
  `server-crt`, `client-crt`, `client-key`, `project`) per CAPN
  identity-secret spec. Loop `loop:
  k8s_lab_capn_identity_namespaces` (§8 default
  `["capi-clusters"]`) — the Secret is materialised in **every**
  namespace where workload Cluster CRs (§16.3) will live.
  The label `clusterctl.cluster.x-k8s.io/move: "true"` is present by
  default (canonical flow §3, pivot mandatory), so that `clusterctl
  move` carries the Secret to the target mgmt-1.

Intentionally outside the CAPN controller namespace (`capn-system`): CAPN
v1alpha2 `LXCCluster.spec.secretRef` looks for the Secret in the LXCCluster CR's
namespace, the `namespace` field in secretRef is absent. Cross-ns
lookup is not supported. Therefore the identity Secret must lie in the
namespace of every workload Cluster CR, not in the controller's
namespace.

### Implementation notes

* **Native-first execution.** No command/shell. LXD REST via
  `ansible.builtin.uri`, cert pipeline via `community.crypto.*`,
  Secret via `kubernetes.core.k8s` + `k8s_info`.
* **PEM→base64 DER strip for the LXD trust API.** POST `/1.0/certificates`
  accepts pure base64 without BEGIN/END markers and whitespace. Pipeline:
  PEM → `regex_replace` chain (BEGIN, END, `\\s+` → `''`) → POST body.
* **HTTPS listener async PATCH.** PATCH `/1.0` is asynchronous from the
  kernel's point of view: daemon rebind, a subsequent immediate request
  may fall into the gap. The role polls the unix socket `/1.0` until
  `core.https_address` in the response matches the target.
* **Idempotence on edge cases.**
  - HTTPS listener: drift-compare current vs target, PATCH only on
    drift;
  - Cert pipeline: `community.crypto` modules are file-state idempotent
    (existing valid cert satisfies criteria → does not recreate);
  - LXD trust: probe by fingerprint, skip POST if found; **assert
    drift on restriction shape** — if a cert in the trust store is without
    `restricted=true` or without `k8s_lab_project_name` in `projects[]`,
    fail loudly (the operator apparently relaxed scope by hand);
  - Secret apply (per target ns): server-side apply + byte-stable
    manifest body → `unchanged` on repeat runs. Pivot label
    flip via `bootstrap_capn_secret_pivot_enabled` propagates
    cleanly (server-side apply field-manager correctly stamps/removes
    the label) — in parallel across all target namespaces.
* **Substrate-required in `vars/main.yml`:**
  - `_bootstrap_capn_secret_required_lxd_https_port: 8443` —
    a CAPN-wide convention (CAPN identityRef.server, host firewall
    rules in §15.5 — all expect this port);
  - `_bootstrap_capn_secret_required_keys` — 5 keys per CAPN
    identity-secret spec;
  - `_bootstrap_capn_secret_required_trust_type: "client"` —
    the only trust type that honours `restricted: true +
    projects:`;
  - `_bootstrap_capn_secret_lxd_socket` +
    `_bootstrap_capn_secret_lxd_server_cert_path` — snap-LXD
    invariants.
* **Public defaults — sourced from the §8 contract:**
  - `bootstrap_capn_secret_name ← k8s_lab_infrastructure_secret_name`
    — Phase 5+ Cluster CR `identityRef.name` and Secret name change
    via a single global variable (no silent disconnect);
  - `bootstrap_capn_secret_namespaces ← k8s_lab_capn_identity_namespaces`
    — list of target namespaces; an empty list → the Secret task
    short-circuits (HTTPS listener + LXD trust still
    run, since they are substrate, not per-cluster);
  - `bootstrap_capn_secret_pivot_enabled` — defaults `true`
    (canonical flow §3 pivot mandatory). Override to `false` only
    for ad-hoc substrate-only test runs;
  - `bootstrap_capn_secret_lxd_project ← k8s_lab_project_name` —
    the single source of truth for CAPN project-scoping (CAPN
    v1alpha2 `LXCClusterSpec` does not have a `project` field — scope lies
    inside the Secret payload, key `project`);
  - `bootstrap_capn_secret_internal_network_name ←
    k8s_lab_internal_network_name` — auto-resolve
    `core.https_address`.
* **Public defaults — tunable:** cert metadata (CN/country/org/
  validity/key size+type), staging paths, auto-resolve override
  (`bootstrap_capn_secret_lxd_https_bind_address`), wait timing.
* **Ownership note.** `core.https_address` is conceptually host-level
  (could have lived in `lxd_host`), but is really needed only under CAPN —
  the local scope in `bootstrap_capn_secret` is minimally invasive and
  does not overlap with lxd_host's snap/socket ownership.
* **Cleanup contract.** Phase 8 destroy (§19.x `cleanup_bootstrap`)
  must remove the Secret from **every** namespace listed in
  `k8s_lab_capn_identity_namespaces` — otherwise stale Secrets will leak and
  on the next bootstrap will conflict with the server-side apply
  field-manager (especially when the client TLS pair changes).

### Acceptance

* HTTPS listener: `core.https_address` matches the auto-resolved
  bridge IPv4 + `:8443`; idempotent re-run → no PATCH;
* LXD trust: exactly one entry with `name=k8slab-capn`, `restricted=true`,
  `projects=[k8s_lab_project_name]`; idempotent re-run → no POST;
* Secret(s): for every ns from `k8s_lab_capn_identity_namespaces`
  there exists a `<infrastructure_secret_name>` Secret with 5 substrate-
  required keys + `project = k8s_lab_project_name`; pivot label
  `clusterctl.cluster.x-k8s.io/move=true` present by default
  (`bootstrap_capn_secret_pivot_enabled=true`, canonical flow §3);
* TLS round-trip: HTTPS endpoint reachable from the bootstrap LXC via
  client cert + `incus-identity` Secret payload; `GET /1.0/projects`
  returns only the project from the payload (proves confinement);
* Empty-list edge case: `k8s_lab_capn_identity_namespaces: []` →
  HTTPS + trust performed, no Secret created, the role
  finishes without errors.

## 13.12. `export_artifacts`

**Status: done in Step 8 (2026-04-23) — Phase 4 closure, §15.6.
End-to-end run on the Vagrant VM green (`converge ok=296 changed=4`,
`idempotence ok=296 changed=0`, `verify ok=16 changed=0 failed=0`);
`kubectl --kubeconfig=.artifacts/mgmt.kubeconfig get nodes` from the
dev machine returns a Ready control-plane node.**

Closes Phase 4: ships a handoff bundle from the LXD host to the runner in
`.artifacts/`:

* **`.artifacts/mgmt.kubeconfig`** — admin kubeconfig for the active
  management cluster. On the first include of the role (via the meta chain)
  the file points to bootstrap k3s — source host-side
  `/opt/capi-lab/etc/bootstrap_clusterctl/bootstrap.kubeconfig`
  (materialised by `bootstrap_clusterctl` with the server URL already rewritten
  to the container-eth0 IPv4 and `tls-server-name:
  kubernetes.default.svc`). On the second include of the role with
  `export_artifacts_run_meta_chain: false` + source override to
  the pivot host-side staging — the same runner-side file
  is overwritten in place with mgmt-1 creds (canonical flow §3).
  Runner-side consumers (TF workload fixtures, Molecule e2e-local)
  keep one path through the whole lifecycle.
* **`.artifacts/mgmt.auto.tfvars.json`** — TF-native `*.auto.tfvars.json`
  handoff for Phase 5 roots (Terraform auto-loads files by
  glob, the `-var-file` flag is not needed). Keys mirror the §8 `k8s_lab_*`
  globals 1:1 (project_name, management/workload cluster names,
  topology counts, kubernetes_version, capn_provider_version,
  infrastructure_secret_name, topology_enabled, unprivileged_nodes)
  + the derived `k8s_lab_mgmt_kubeconfig_path` and
  `k8s_lab_mgmt_api_server_url`. The API URL is derived from the shipped
  kubeconfig (a second LXD REST probe is not needed).
* **`.artifacts/clusters/`** — an empty subdir, reserved for
  Molecule e2e-local debug artefacts (verify.yml writes there
  a raw workload kubeconfig for operator inspection, not consumed
  downstream). The TF module §16.4 **does not write** into this subdir — it
  keeps the kubeconfig only in state and emits it via `output -raw
  kubeconfig` (§16.4 architectural fence). The subdir is still
  pre-created by `export_artifacts` for predictability of the Molecule
  debug copy path.

### Implementation notes (Step 8)

* **Execution model: `delegate_to: localhost, become: false, run_once:
  true`** on artefact-write tasks. The role runs on the LXD host
  via the meta-dep chain (bootstrap_capn_secret transitively pulls the whole
  Phase 4), reads the source kubeconfig as root (via `slurp`, bypassing
  `/opt/capi-lab/etc/bootstrap_clusterctl/` mode 0750), and then flips
  to the controller user for `copy` — the files land with the runner's UID and
  mode 0600 (§11.1). Controller-side `sudo` is not required.
* **`export_artifacts_root` — mandatory public input.** Plan
  §11.1 fixes the `.artifacts/` contract (gitignore, mode 0600, owner
  = runner), but not the path — the policy decision is left to the consumer.
  Auto-guess via `playbook_dir` would be fragile (depends on where
  the operator runs the playbook), so the role fails preflight
  without this variable. Preflight also strips `..`/`.` segments —
  the path must be canonical (regression of the first iteration of Step 8:
  the scenario passed `MOLECULE_PROJECT_DIRECTORY/../../.artifacts` →
  an ugly path landed in tfvars; fixed to
  `MOLECULE_PROJECT_DIRECTORY | dirname | dirname + /.artifacts`).
* **Runner-reach via LXD proxy + `tls-server-name`.** The runner
  (dev machine for the harness, server for production) must
  reach the mgmt API, but in the k3s cert there is no SAN for the host IP.
  Solved via:
  - `bootstrap_clusterctl` pins `tls-server-name: kubernetes.default.svc`
    (standard k8s SAN, always in the k3s cert) — see §13.10;
  - `export_artifacts` optionally rewrites `clusters[].cluster.server`
    to a runner-reachable URL via the public
    `export_artifacts_mgmt_api_server_url` (default empty = keep
    host-side URL); `tls-server-name` stays `as-is` from source,
    already pinned by bootstrap_clusterctl;
  - `lxd_bootstrap_instance_devices.k3s-api` (LXD proxy
    `bind: host, listen: tcp:0.0.0.0:16443, connect: tcp:127.0.0.1:6443`)
    — publishes the API on the host of the VM.
  The kubeconfig works byte-for-byte from any vantage point (in-container,
  LXD host, dev machine via proxy, production runner with network reach)
  — no IP in the cert. `insecure-skip-tls-verify` is not used.
* **Substrate-required in `vars/main.yml`** (memory rule
  `feedback_required_values_hardcoded.md`):
  - `_export_artifacts_required_mgmt_kubeconfig_filename: "mgmt.kubeconfig"`
    — Phase 5 fixtures hardcode exactly this name; the same path
    is overwritten in place at pivot (§3.1 / §18 — there is no separate
    `bootstrap.kubeconfig` entity);
  - `_export_artifacts_required_tfvars_filename: "mgmt.auto.tfvars.json"`
    — Terraform auto-load glob;
  - `_export_artifacts_required_clusters_subdir: "clusters"`;
  - `_export_artifacts_required_file_mode: "0600"` +
    `_export_artifacts_required_dir_mode: "0700"` — §11.1 secret
    contract.
* **Public defaults — tunable:** whole-role toggle
  (`export_artifacts_enabled`), per-artefact toggles
  (`export_artifacts_mgmt_kubeconfig_enabled`,
  `export_artifacts_tfvars_enabled`), source path
  on the host (`export_artifacts_mgmt_kubeconfig_source`,
  defaulting to the host-side
  `/opt/capi-lab/etc/bootstrap_clusterctl/bootstrap.kubeconfig` —
  internal staging file of the `bootstrap_clusterctl` role, not the runner-side
  name),
  `export_artifacts_mgmt_api_server_url: ""` (empty → keep
  source URL; non-empty → rewrite `clusters[].cluster.server` in the
  shipped kubeconfig — runner-reach handle),
  `export_artifacts_tfvars_extra: {}` — merge-on-top dict for
  environment-specific additions (baseline keys always win
  on collision; if you need to shadow a baseline — change the §8 global,
  not the role extras).
* **Idempotence.** `slurp` + `copy` compares bytes on the destination
  → skip write on match. `to_nice_json(sort_keys=True)` gives a
  deterministic body for identical inputs → tfvars rewrite
  byte-stable. `ansible.builtin.file state=directory` — no-op on
  matching mode.
* **Healthchecks** stat both files on the runner, check mode 0600
  and basic size bounds. Extra: parse tfvars as JSON and
  assert the presence of baseline keys (`k8s_lab_project_name`,
  `k8s_lab_infrastructure_secret_name`, `k8s_lab_capn_provider_version`,
  `k8s_lab_mgmt_kubeconfig_path`, `k8s_lab_mgmt_api_server_url`)
  + that `k8s_lab_mgmt_api_server_url` starts with `https://` and
  does not contain `127.0.0.1`.
* **Scenario `export-artifacts`** asserts the same on the runner
  (`delegate_to: localhost`): mode 0600 for both files, the shipped
  kubeconfig is parseable YAML with server URL == scenario-provided URL and
  `tls-server-name == kubernetes.default.svc`, tfvars JSON with baseline
  `k8s_lab_*` keys, the API URL in tfvars matches the kubeconfig's server URL.
  Plus an end-to-end smoke: `kubernetes.core.k8s_info kind=Node` via the
  shipped kubeconfig with `delegate_to: localhost` — the dev machine actually
  connects to the bootstrap API via the LXD proxy device, TLS verify by
  `kubernetes.default.svc`, gets at least one Ready node. This
  smoke proves end-to-end for the Phase 5 TF: if the runner sees the API
  in verify, Terraform Kubernetes/Helm provider with the same kubeconfig
  will go along the same path. `ansible_python_interpreter: "{{ ansible_playbook_python }}"`
  per-task for delegated tasks pins the runner-side Python to the venv
  (there `python3-kubernetes` is already present — installed for molecule).
* **Ownership note.** The role explicitly does NOT interfere with
  trust material or cluster state — it only **reads** already
  materialised artefacts (kubeconfig, §8 globals in Ansible memory)
  and **writes** them into `.artifacts/`. An idempotent
  snapshot-only role, not state-changing.

### Adjacent debug artefacts (outside the scope of this role)

* **`.artifacts/clusters/<cluster>.kubeconfig`** — runner-reachable
  rewritten kubeconfigs for mgmt-1 and workload, written by
  e2e-local converge.yml (§10.2) by parsing the kubeconfig Secrets on
  bootstrap/mgmt-1 and substituting the server URL with
  `https://<lxd_host>:<api-proxy-port>` + `tls-server-name`. The TF
  module §16.4 does not write into this subdir (§16.4 architectural fence);
  the module keeps the rewritten kubeconfig in TF state and emits it via
  `terraform output -raw kubeconfig`. The subdir is created by the
  `export_artifacts` role on its first include.

## 13.13. `pivot_clusterctl_move` (Step 17)

**Status: done in Step 18 (2026-04-29).**

Role drives the canonical CAPI bootstrap-and-pivot flow on the LXD
host: materialise runner-reachable kubeconfig for the target mgmt
cluster, `clusterctl init --infrastructure incus:<ver>` on target,
`clusterctl move --to-kubeconfig` to relocate every CAPI CR from
bootstrap to target. Pivot is mandatory in canonical flow §3 — the
role gates only on `pivot_clusterctl_move_enabled` (default `true`).

Full role contract — `ansible/roles/pivot_clusterctl_move/README.md`.
Plan-side detail — §18.2.

**Cross-role coupling discipline (§2.6.5 verified):**

* No reads of `<other_role>_*` prefix. Bootstrap kubeconfig path is
  duplicated as a value with a comment pointing at
  `bootstrap_clusterctl_kubeconfig_path` upstream default.
* Single meta-dep on `bootstrap_clusterctl` with `# why` comment;
  transitively pulls full Phase 0..4 substrate chain.
* Substrate-required values (CAPN provider name `incus`,
  `tls-server-name: kubernetes.default.svc`, api-proxy-port
  annotation key `k8s-lab.io/api-proxy-port`, required Deployment
  list) live in `vars/main.yml` under
  `_pivot_clusterctl_move_required_*` per memory rule
  `feedback_required_values_hardcoded.md`.

**Idempotence (§2.6.1):** every mutating step gated on a read-only
probe before a fallback shell tool fires:

* `init.yml` — probe target for `capn-controller-manager`
  Deployment via `kubernetes.core.k8s_info`; skip when present
  (clusterctl init is all-or-nothing).
* `move.yml` — guarded by `target_kubeconfig.yml`'s
  `_pivot_clusterctl_move_target_on_bootstrap` fact (set from a
  Cluster CR query on bootstrap). False ⇒ move already happened,
  skip.

**Acceptance proven by role healthchecks (`tasks/healthchecks.yml`),
no separate Molecule scenario:**

* cert-manager + 4 CAPI/CAPN provider Deployments Available on
  target;
* 4 Provider CRs (Core/Bootstrap/ControlPlane/Infrastructure=`incus`)
  present on target;
* target Cluster CR is on target;
* bootstrap holds zero Cluster CRs in target namespace.

**Acceptance:**

* mgmt-1 cluster (1 CP + 2 worker, all Ready, dual-stack pod CIDRs);
* CAPI providers freshly installed by clusterctl init on target,
  4/4 Available;
* Cluster CR `mgmt-1` lives on target post-move;
* `capi-bootstrap-0` LXC container absent — `cleanup_bootstrap`
  chained in the same play removed it idempotently.

**Bootstrap retirement chained in same play:**

Bootstrap deletion is owned by the existing `cleanup_bootstrap`
role (§19.1), invoked as the third role in the e2e-local converge
play (after `pivot_clusterctl_move` and the second `export_artifacts`
re-emit include). Runner-side `.artifacts/mgmt.kubeconfig` is not
wiped — it is overwritten in place with mgmt-1 creds by the second
`export_artifacts` include immediately before `cleanup_bootstrap`
runs.

---

# 14. Completed phases

This section lists the phases that have already passed end-to-end in the local
Vagrant/libvirt loop as of Step 6 (2026-04-23):

* §14.1 Phase 0 — repo skeleton and local harness (Step 1);
* §14.2 Phase 1 — host bootstrap (Steps 1–2; `binary_fetch` deferred and
  done in Phase 3.5 / §14.5);
* §14.3 Phase 2 — LXD substrate (Step 3);
* §14.4 Phase 3 — bootstrap instance (Step 3);
* §14.5 Phase 3.5 — `binary_fetch` (Step 4);
* §14.6 Phase 4 — bootstrap management cluster (Steps 4 + 6 + 8;
  the phase is closed end-to-end): `bootstrap_k3s` ready since Step 4;
  `bootstrap_clusterctl` + `bootstrap_capn_secret` ready since Step 6;
  the separate role `bootstrap_api_publish` removed in Step 7 — API
  publication moved to the LXD proxy device on top of `lxd_bootstrap_instance`,
  see §15.5; `export_artifacts` implemented + Molecule cycle run in
  Step 8 / §13.12.

Step 5 — **sweeping refactor without new phases**: substrate-required
values in `base_system` / `lxd_storage_pools` / `lxd_network_int_managed`
/ `lxd_bootstrap_instance` / `bootstrap_k3s` moved to `vars/main.yml`
(§13.1 / §13.4 / §13.5 / §13.7 / §13.9 respectively). The contract
of all five phases (Phase 0..4) re-verified end-to-end by a Molecule
run on a clean Vagrant VM — 9 scenarios PASS in sequence, `.artifacts/
regression-logs/SUMMARY.txt`. Step 5 does not add new phases and does not
expand Stage 1 scope; the only observable change for
consumers — a narrower public defaults contract (see per-role
Step 5 sections in §13).

Step 6 (2026-04-23) — Phase 4 continuation and native-first
collection upgrade. Two missing Phase 4 roles implemented
(`bootstrap_clusterctl` §13.10, `bootstrap_capn_secret` §13.11),
their Molecule scenarios brought up (see §9.4 list). Repo-level
changes: `kubernetes.core ≥6.0.0` (resolved 6.4.0) added to
`ansible/requirements.yml`, `python3-kubernetes 30.1.0-2` (Debian
Trixie) added to shared Molecule prepare. All Kubernetes API
calls of the new roles go via `kubernetes.core.k8s` / `k8s_info`
(native, server-side apply), without `kubectl` commands. Substrate-
required values in both roles moved into `vars/main.yml` under the
`_<role>_required_*` prefix per the rule
`feedback_required_values_hardcoded.md`. Public defaults sourced from
plan §8 globals (`k8s_lab_infrastructure_secret_name` →
`bootstrap_capn_secret_name`); `bootstrap_capn_secret_pivot_enabled`
defaults to `true` (canonical flow §3, pivot mandatory). A single global
flip keeps the Phase 5+ Cluster CR identityRef and the pivot move-label synchronised
without silent disconnect. Step 6 does not close Phase 4 entirely —
`bootstrap_api_publish` (§15.5) and `export_artifacts`
(§15.6) remain, both addressed in Step 7.

Step 7 (2026-04-23) — repo-wide naming refactor + rethink of the
bootstrap API publication. Adds no new phases, but
noticeably changes the public contract.

* **Repo-wide global variable rename.** All §8 project-wide variables
  got the prefix `k8s_lab_*` (`opt_root` → `k8s_lab_opt_root`,
  `k3s_version` → `k8s_lab_k3s_version`, `api_publish_port` →
  `k8s_lab_api_publish_port`, etc., §8 rewritten in full). Naked
  globals without the prefix are forbidden — the rule is encoded in memory
  `feedback_global_var_prefix.md` and §2.6.5. Role-scoped variables
  with a role prefix (`lxd_host_*`, `bootstrap_clusterctl_*`) were not
  touched. The rename ran via sed with `\b` word boundaries (177
  files in `ansible/roles/` + `tests/molecule/` + `scripts/`);
  surviving references to naked names — historical deprecation
  notes + a single explanatory example in the §2.6.5 rule itself.
* **Host firewall out-of-project-scope.** A separate role
  `bootstrap_api_publish` (planned in §15.5 as nftables DNAT
  + source-IP ACL on the host) is removed as overengineered: mTLS of the
  kubeconfig already protects the API, source-IP ACL on top gives no
  measurable benefit, and edits in distro-owned nftables tables can
  override operator-managed rules in prod. §11.4 rewritten —
  host firewall is formally declared outside the scope of the repo; port
  publication is now done via a native LXD proxy device
  (`type: proxy, bind: host`), forwarded through
  `lxd_bootstrap_instance_devices` of the already existing §13.7 role.
  The rule is encoded in memory `feedback_host_firewall_scope.md`.
* **Project policy extended.** `lxd_project` got
  the substrate-required `restricted.devices.proxy: "allow"` in
  `vars/main.yml` — without it LXD rejects a proxy device in a
  restricted project, breaking the canonical publish path. See §13.3
  Step 7 deviation section.
* **Artefacts removed from the repo.**
  `ansible/roles/bootstrap_api_publish/` + the whole scenario
  `tests/molecule/bootstrap-api-publish/` removed completely together
  with all tasks, templates, handlers, meta-deps and README. The entry
  from `tests/molecule/Makefile` SCENARIOS removed. Globals
  `k8s_lab_api_publish_port` / `k8s_lab_api_publish_acl_mode` /
  `k8s_lab_allowed_source_ips` removed from §8 (never made it
  into the stable contract — they were renamed at the start of Step 7 and
  removed at its end). Plan §15.5 rewritten as a one-page
  explanation of the canonical publish path via the LXD proxy device.
* **Test coverage of publication.** End-to-end test for the LXD proxy
  device lives in the scenario `bootstrap-k3s`: its `molecule.yml`
  host_vars sets `lxd_bootstrap_instance_devices.k3s-api`, and
  verify.yml asserts the device in live instance config, TCP probe
  `127.0.0.1:16443` and getting a Node list via kubernetes.core.k8s_info
  by the published endpoint.
* **Memory housekeeping.** Two new rules added
  (`feedback_global_var_prefix.md`, `feedback_host_firewall_scope.md`,
  `feedback_pause_before_role_test.md`). One-off instructions
  applied and completed in previous steps removed from
  memory (policy-rules remained).

**Step 8 extensions — harness refactor + Vagrantfile fixes.**

* **Shared inventory architecture** (§9.5). Before Step 8 every
  `molecule.yml` duplicated substrate host_vars. Incident:
  the `export-artifacts` scenario did not set
  `lxd_bootstrap_instance_devices`, the role reconciled the proxy
  device to `{}` on converge, runner-reach broke. Fix:
  move all substrate into `tests/molecule/shared/inventory/group_vars/k8slab_host.yml`,
  scenarios attach via `inventory.links.group_vars:
  ../shared/inventory/group_vars`. Scenario-local overrides — in real
  files `<scenario>/host_vars/k8slab-host.yml` (not via
  `molecule.yml inventory.host_vars`, which silently drops when
  `links` is present — molecule provisioner/ansible.py:442
  all-or-nothing). The target role is determined in `shared/converge.yml`
  from the `MOLECULE_SCENARIO_NAME` env var; contract
  `scenario.name == role dir name`. Full description — §9.5.
  `shared/vars/common.yml` removed, 24 `prepare.yml`/`verify.yml`
  lost the `vars_files:` reference.
* **Vagrantfile self-sufficiency.** `config.trigger.before :up`
  defines + starts libvirt networks via `virsh` if they
  are missing — bare `vagrant up` now works standalone (before
  this it crashed with `undefined method 'to_range' for nil` on a pristine
  system, you needed a `make networks` wrapper).
  `config.vm.synced_folder ".", "/vagrant", disabled: true` — removed
  the useless rsync of the whole repo into the guest (no references to
  `/vagrant` in `ansible/` or `tests/molecule/`); saved
  ~2 min on `make up` first-boot + `apt install rsync` in the guest.
* **End-to-end regression (2026-04-23, pristine VM).** All 12
  ready scenarios passed full-cycle sequentially (create →
  prepare → converge → idempotence → verify → destroy):

  | Scenario | Duration |
  |---|---|
  | base-system | 183s |
  | binary-fetch | 67s |
  | lxd-host | 107s |
  | lxd-project | 75s |
  | lxd-storage-pools | 77s |
  | lxd-network-int-managed | 80s |
  | lxd-profiles | 101s |
  | lxd-bootstrap-instance | 118s |
  | bootstrap-k3s | 213s |
  | bootstrap-clusterctl | 225s |
  | bootstrap-capn-secret | 199s |
  | export-artifacts | 211s |
  | **Total** | **~1656s (~27.6 min)** |

  `export-artifacts` verify includes live
  `kubernetes.core.k8s_info kind=Node` via the shipped kubeconfig with
  `delegate_to: localhost` — the dev machine actually reaches
  the bootstrap API via the LXD proxy with TLS verify by
  `kubernetes.default.svc`. Proof that Phase 5 TF
  Kubernetes/Helm provider with the same kubeconfig will go.
* **Memory.** Added a new rule `feedback_makefile_only.md`:
  always go through Makefile entry points, never directly
  vagrant/virsh/molecule — otherwise harness bugbugs stay
  unnoticed.
* **Regression prove.** Sequential Molecule runner (`/tmp/
  run_all_scenarios.sh`) on a freshly created Vagrant VM passed all 11
  remaining ready scenarios (base-system, binary-fetch, lxd-host,
  lxd-project, lxd-storage-pools, lxd-network-int-managed,
  lxd-profiles, lxd-bootstrap-instance, bootstrap-k3s,
  bootstrap-clusterctl, bootstrap-capn-secret) — the rename did not
  break anything, proxy publish works via bootstrap-k3s verify.

Step 7 leaves Phase 4 not fully closed —
`export_artifacts` (§15.6) is moved to the next Step.

Step 8 (2026-04-23) — closure of Phase 4 + architectural fix
of runner-reach. `export_artifacts` (§13.12 / §15.6) implemented +
Molecule scenario `export-artifacts`. `bootstrap_clusterctl` got
the substrate-localised pin `tls-server-name: kubernetes.default.svc`
in the rewritten kubeconfig (§13.10 Step 8 deviation) — this cryptographically
decouples TLS verify from the connection URL: the runner can hit
any proxy-device endpoint, the TLS handshake matches against the DNS SAN
`kubernetes.default.svc`, which k3s puts into the server cert by
default (k8s standard, no `--tls-san` needed). No IPs in the cert.

Architectural conclusion of Step 8: the handoff bundle is useless without the
runner (= dev machine for the harness, = server for production) being able
to actually reach the cluster API. Plan §15.5 anticipated this
— publish via a native LXD proxy device on the bootstrap instance
(`bind: host, listen: tcp:0.0.0.0:16443, connect: tcp:127.0.0.1:6443`),
no host-firewall workarounds (§11.4 hard-lock). The combination of proxy +
`tls-server-name` pin gives a fully portable kubeconfig: one
file works from inside the VM (server=10.77.x:6443), from the VM's host
(127.0.0.1:16443), from the dev machine (192.168.121.35:16443), from any
runner with network reach to the host — the TLS identity is the same everywhere.

`export_artifacts` publishes on the runner:

* `.artifacts/mgmt.kubeconfig` — via `slurp`+`copy` with
  `delegate_to: localhost, become: false, run_once: true` (the §11.1
  contract: file mode 0600, owner=runner user). Optional rewrite of
  `clusters[].cluster.server` via the public `export_artifacts_mgmt_api_server_url`
  (empty → keep host-side URL; non-empty → substitute into the shipped
  kubeconfig). `tls-server-name` is preserved `as-is` from source —
  bootstrap_clusterctl already pins it. After pivot the same file
  is overwritten in place by the second include of the role with
  `export_artifacts_run_meta_chain: false` + source-override on the
  pivot host-side staging (canonical flow §3 / §18).
* `.artifacts/mgmt.auto.tfvars.json` — TF-native auto-load
  template for Phase 5 fixture roots; keys mirror §8 `k8s_lab_*`
  globals 1:1 (project_name, cluster names, topology counts,
  kubernetes_version, capn_provider_version, infrastructure_secret_name,
  etc.) + the derived `k8s_lab_mgmt_kubeconfig_path`,
  `k8s_lab_mgmt_api_server_url` (derived from the already shipped
  kubeconfig — a second LXD REST probe is not needed).
* `.artifacts/clusters/` — empty subdir, reserved for
  per-workload debug copies (Molecule e2e-local verify writes there
  a raw kubeconfig for operator inspection).

Substrate-required values (filenames `mgmt.kubeconfig` /
`mgmt.auto.tfvars.json`, subdir `clusters/`, file mode 0600 / dir
mode 0700) — in `vars/main.yml` under the `_export_artifacts_required_*`
prefix. Public defaults expose only toggles, source path
on the host, the `tfvars_extra` merge-on-top extension point and
`export_artifacts_mgmt_api_server_url` for runner-reach override;
`export_artifacts_root` — a mandatory consumer input (plan §11.1
fixes the contract, not the path; preflight strips `..`/`.` segments for
canonical form). Meta-deps: `bootstrap_capn_secret` (closes
the Phase 4 substrate chain — transitively everything up to `base_system`).

The `export-artifacts` scenario in the Makefile SCENARIOS is registered
after `bootstrap-capn-secret`; passes the proxy device + URL override
in host_vars **temporarily** — pending §9.5.1 (the harness
refactoring backlog: move common substrate host_vars into
shared inventory group_vars, so the proxy device lives in one place
for all scenarios as in the production inventory).

**End-to-end run (2026-04-23) on the Vagrant VM green:**
`converge ok=296 changed=4 failed=0` → `idempotence ok=296 changed=0`
→ `verify ok=16 changed=0 failed=0`. Verify does a live k8s_info
via the shipped kubeconfig with `delegate_to: localhost` — the dev machine
reaches the bootstrap API via the LXD proxy on `192.168.121.35:16443`,
TLS verification by `kubernetes.default.svc`, one Ready control-plane
node is returned. `kubectl --kubeconfig=.artifacts/mgmt.kubeconfig
get nodes` from the dev machine also works — Phase 5 Terraform
`kubernetes`/`helm` provider will go out-of-the-box. Phase 4
is formally **closed**.

**Step 8 — side changes:**
* `bootstrap_clusterctl` (§13.10) — one line in
  `tasks/kubeconfig.yml` (`tls-server-name` in the combine-rewrite) + 1
  substrate-key in `vars/main.yml`. Regression-safe for
  `bootstrap_capn_secret` — its k8s_info calls go via the same
  kubeconfig, `tls-server-name: kubernetes.default.svc` matches
  against the same SAN that was previously matched via IP; the `bootstrap_capn_secret`
  scenario passes unchanged (re-run of Step 8 on the same VM —
  idempotent).
* §9.5.1 harness refactoring backlog added (see common.md §9.5) —
  describes moving common host_vars into shared inventory group_vars;
  `lxd_bootstrap_instance_devices.k3s-api` and all other duplicates
  will go there; scenario-level override in export-artifacts will disappear.
  Scheduled **before the start of Phase 5 scenarios** so as not to multiply
  tech-debt when adding them.

The phases not yet completed live in §15..§19.

## 14.1. Phase 0 — repo skeleton and local harness

**Status: done in Step 1 (2026-04-21); Step 9 (2026-04-24)
removed the `k8slab-ext6-mock` libvirt network (did not emit RA, see §9.2
Step 9 pivot) + disabled `synced_folder`.** Tree per §7, all three
Makefiles, `ansible/ansible.cfg` + `requirements.yml`, Vagrant VM
`tests/vagrant/debian13/` (after Step 9 — 2 NICs: default management +
mgmt-nat; external RA source — in-VM veth + radvd from shared prepare,
see §9.2; dedicated LXD pool disk 40 GiB with serial `k8slab-lxdpool`).
Active libvirt networks: `k8slab-mgmt-nat` (and dormant
`k8slab-probe-ext6` under `K8SLAB_PROBE=1`). Molecule 26.x delegated-mode
harness via `scripts/molecule_run.py` (brings up the VM, exports
`K8SLAB_HOST_*` env, execvpe's molecule). Auto-invalidation
of Molecule state by VM UUID (`.artifacts/harness-vm-id`).

To do:

* tree
* `Makefile`
* `ansible.cfg`
* Vagrant/libvirt VM
* Molecule delegated

Acceptance:

* `make lint`
* `make test-local-harness`

## 14.2. Phase 1 — host bootstrap

**Status: done in Steps 1–2 (`base_system` in Step 1,
`lxd_host` in Step 2). `binary_fetch` deferred to Phase 3.5.**

Roles (in order of implementation):

* `base_system` — Step 1.
* `lxd_host` — Step 2.
* `binary_fetch` (moved closer to Phase 4 — kubectl/clusterctl/k3s
  are not consumed earlier; see §15.1 and §15.7).

Acceptance:

* Debian 13 host prepared
* LXD daemon installed, snap channel pinned, refresh policy applied
* host-side external bridge `br-ext6` created with the uplink attached
* binaries in `/opt/capi-lab/bin` (when the phase with `binary_fetch` has been executed)
* no custom apt repos

## 14.3. Phase 2 — LXD substrate (entities inside LXD)

**Status: done in Step 3 (2026-04-22).**

Roles:

* `lxd_project`
* `lxd_storage_pools`
* `lxd_network_int_managed`
* `lxd_profiles`

Acceptance:

* `capi-lab` project exists
* Btrfs pool exists
* internal managed network exists (**in the default project** —
  see §13.5 deviation)
* profiles exist
* no damage to foreign containers

## 14.4. Phase 3 — bootstrap instance

**Status: done in Step 3 (2026-04-22).**

Role:

* `lxd_bootstrap_instance`

Acceptance:

* `capi-bootstrap-0` exists
* proper profile attached
* starts cleanly

## 14.5. Phase 3.5 — `binary_fetch` (deferred from Phase 1)

**Status: done in Step 4 (2026-04-22). Matches §15.7.**

Role:

* `binary_fetch` (see §13.8).

Acceptance:

* `kubectl`, `clusterctl`, `k3s` in `/opt/capi-lab/bin` with
  deterministic owner/group/mode `root:root 0755`;
* the sha256 of each binary matches the upstream-published checksum
  (for clusterctl — with the pinned digest next to the version pin, see
  §13.8 implementation note);
* each binary runs and self-reports a version matching the pinned
  value from §8a.

## 14.6. Phase 4 — bootstrap management cluster

**Status: done in Step 4 + Step 6 + Step 8 (2026-04-23).** In
Step 4 (2026-04-22) `bootstrap_k3s` is ready; in Step 6 (2026-04-23)
`bootstrap_clusterctl` (§13.10) and `bootstrap_capn_secret`
(§13.11) added. Step 7 (2026-04-23): the separate role `bootstrap_api_publish`
removed from Phase 4 (§15.5) — port publication moved to the LXD
proxy device on top of `lxd_bootstrap_instance`; the host-side firewall
is declared outside the scope of the repo (§11.4). Step 8 (2026-04-23): the
closing role `export_artifacts` (§13.12 / §15.6) implemented + architectural
fix of runner-reach through LXD proxy + `tls-server-name: kubernetes.default.svc`
pin in `bootstrap_clusterctl` (§13.10 Step 8 deviation). End-to-end
run green, Phase 4 closed.

Done in Step 4:

* `bootstrap_k3s` (see §13.9) brings up single-node k3s server in
  `capi-bootstrap-0` LXC. This required substrate extensions in
  §13.3 (`restricted.containers.interception`,
  `restricted.devices.unix-char`) and §13.6 (full CAPN unprivileged
  kubeadm baseline + `/dev/kmsg` passthrough + `raw.lxc` apparmor
  override + restart-on-profile-change).

Done in Step 6:

* `bootstrap_clusterctl` (see §13.10) turns a bare bootstrap
  k3s cluster into a CAPI management cluster: pulls the in-container kubeconfig
  and rewrites the server URL to the container-eth0 IPv4, renders
  a pinned `clusterctl.yaml` with the CAPN provider entry, runs
  `clusterctl init --infrastructure incus:<ver>` with CLUSTER_TOPOLOGY
  =true, waits for Available on 7 Deployments (cert-manager + 4
  CAPI/CAPN), asserts the `Provider` CR list via k8s_info.
* `bootstrap_capn_secret` (see §13.11) materialises the CAPN identity
  Secret. Triplet: PATCH `core.https_address: <bridge-ipv4>:8443` on the
  LXD daemon (reachable only from the capi-int subnet), generation of a client
  cert/key via `community.crypto`, registration of the cert as a
  `restricted: true + projects: [capi-lab]` trust entry, server-side
  apply of the Secret into `capn-system` (5 keys of the CAPN identity-secret spec).
  `bootstrap_capn_secret_name` sourced from the global
  `k8s_lab_infrastructure_secret_name` (§8 contract); the pivot label
  is always added (`bootstrap_capn_secret_pivot_enabled` defaults
  `true` — canonical flow §3, pivot mandatory).
* Repo-wide native-first upgrade: `kubernetes.core ≥6.0.0` (resolved
  6.4.0) + `python3-kubernetes` (Debian Trixie). All Kubernetes API
  calls of the new roles via `kubernetes.core.k8s` / `k8s_info`
  (server-side apply, structured responses) — no kubectl
  shells.

Acceptance of the Step 4 part (proven by verify scenarios):

* `k3s.service` reaches `active` (not `activating`) — substrate
  correct;
* `kubectl get nodes` reports `capi-bootstrap-0` Ready;
* `/etc/rancher/k3s/k3s.yaml` exists and is non-empty;
* in-container k3s sha256 == host k3s sha256 (push without corruption);
* restart-on-profile-change behaviour in `lxd_profiles` fires
  (the container's init PID changes on profile-mod) — see §13.6 Step 4
  verify deviation.

Acceptance of the Step 6 part (proven by verify scenarios):

* bootstrap_clusterctl scenario: host-side kubeconfig present (mode
  0600, server URL rewritten from 127.0.0.1 to the capi-int IP), cluster
  Ready via kubeconfig, all 7 Deployments (cert-manager + 4
  CAPI/CAPN) Available, all 4 ProviderCR-tuple
  (Core/cluster-api, Bootstrap/kubeadm, ControlPlane/kubeadm,
  Infrastructure/incus) present, `ClusterTopology=true` feature
  gate in capi-controller-manager Deployment args;
* bootstrap_capn_secret scenario: LXD `core.https_address` bound to
  the capi-int IP (10.77.x.x:8443), exactly one client cert in the trust store
  with `restricted=true + projects=[capi-lab]`, Secret in `capn-system`
  with 5 correct data keys (server URL starts with `https://10.77.`
  and ends with `:8443`, project=capi-lab, all cert/key in correct
  PEM format), `server-crt` Secret key byte-equal with live
  `/var/snap/lxd/common/lxd/server.crt`, pivot move-label
  `clusterctl.cluster.x-k8s.io/move=true` present
  (canonical flow §3 default).

Done in Step 8:

* `export_artifacts` (see §13.12) closes the runner-side handoff:
  `.artifacts/mgmt.kubeconfig` (shipped from the host to the runner, mode
  0600 per §11.1; optional rewrite of `clusters[].cluster.server` to a
  runner-reachable URL via `export_artifacts_mgmt_api_server_url`)
  + `.artifacts/mgmt.auto.tfvars.json` (§8 globals mirrored 1:1,
  Terraform auto-loads the file in Phase 5 fixture roots).
  `.artifacts/clusters/` subdir created for per-workload debug copies.
* `bootstrap_clusterctl` (see §13.10 Step 8 deviation) pins
  `tls-server-name: kubernetes.default.svc` in the rewritten kubeconfig —
  one kubeconfig works from any point of reach without an IP in the cert.
* `lxd_bootstrap_instance_devices.k3s-api` proxy device is passed
  through scenario host_vars as a temporary workaround — it will move into
  shared inventory in the §9.5.1 refactoring.

Acceptance of the Step 8 part — **proven end-to-end**
(2026-04-23, `converge ok=296 changed=4, idempotence ok=296 changed=0,
verify ok=16 changed=0 failed=0`):

* both files present on the runner with mode 0600;
* shipped kubeconfig: `server=https://<vagrant_vm_ip>:16443`
  (runner-reachable via the LXD proxy), `tls-server-name=kubernetes.default.svc`;
* tfvars parses as JSON, contains baseline `k8s_lab_*` keys,
  `k8s_lab_mgmt_api_server_url` matches
  `clusters[].cluster.server` from the shipped kubeconfig;
* `kubernetes.core.k8s_info kind=Node` via the shipped kubeconfig with
  `delegate_to: localhost` returns a Ready control-plane node —
  proof that the Phase 5 Terraform Kubernetes/Helm provider
  will go along the same path;
* bonus: `kubectl --kubeconfig=.artifacts/mgmt.kubeconfig
  get nodes` from the dev machine also works.

Acceptance of all of Phase 4 — **closed** (2026-04-23):

* bootstrap API reachable from runner                ✓ (Step 8 — §13.12)
* `clusterctl init` done                             ✓ (Step 6 — §13.10)
* providers healthy                                  ✓ (Step 6 — §13.10)
* LXD identity secret present                        ✓ (Step 6 — §13.11)
* handoff bundle shipped to `.artifacts/`            ✓ (Step 8 — §13.12)

## 14.7. Workload cluster delivery via Terraform module (Step 16)

**Status: done in Step 16 (2026-04-28) — see §16.4 / §16.5 / §16.6
Step 16 status headers + Acceptance status (Step 16) for the full
file/timing/deviation breakdown.** One TF root
`tests/fixtures/terraform/workload-clusters/lab-default/` invokes
`terraform/modules/workload_cluster/`; `make deploy-workload`
brings up the workload cluster end-to-end through a chain of 5 helm_release
+ 2 wait null_resources + 2 helm-test null_resources in ~9 min
on cold cache.

Done in Step 16:

* TF module `terraform/modules/workload_cluster/` — versions/providers/
  variables/locals/main/outputs.tf + 3 bash helpers
  (`wait_for_secret.sh`, `wait_for_workload_api.sh`, `helm_test.sh`).
  Module owns the mgmt + workload helm/kubernetes provider configs inside
  (the fixture does not override them). The workload helm provider parses
  kubeconfig fields (host/CA/client-cert/client-key) from the parsed
  Secret and passes them inline — nothing is written to the FS (memory rule
  "module does not write to .artifacts/" honored).
* Test fixture root `tests/fixtures/terraform/workload-clusters/lab-default/` —
  defaults track §8 reference deployment; derives `lxd_host_address`
  from the `k8s_lab_mgmt_api_server_url` host component via regex
  + coalesce (supports both `[ipv6]:port` and `host:port`); 7
  unused declared vars silently consume mgmt-side keys from
  auto-tfvars.
* Root `Makefile` — targets `deploy-workload`,
  `workload-kubeconfig`, `destroy-workload` added. All three thread
  `-var-file=$(REPO_ROOT)/.artifacts/mgmt.auto.tfvars.json`
  + a preflight check on the presence of the file (TF auto-load only
  works from the fixture cwd, and the handoff bundle lies at repo-root —
  the symlink alternative was rejected as hidden filesystem coupling).
* §16.4 design deviation — a new step 5b
  `null_resource.wait_for_workload_api` added between the data source workload
  kubeconfig Secret and the first workload-side helm_release. The probe
  goes to the rewritten URL `<lxd_host>:<api_proxy_port>/livez` until
  HTTP 200/401/403. Without it the first CNI install falls over with `EOF` —
  KCP emits the kubeconfig Secret before the kube-apiserver static
  pod actually starts serving (cert generation ≠ ready).
* §16.4 secondary ergonomic deviation — `kubectl --kubeconfig
  <(terraform output -raw kubeconfig)` via process substitution
  does not work (kubectl seeks the kubeconfig file, FIFO seek is not
  supported). Workaround in Makefile target `workload-kubeconfig` —
  materialises the output into `.artifacts/clusters/<cluster>.kubeconfig`
  via a consumer-side wrapper with umask 077.

Memory rules applied in Step 16:

* `feedback_helm_first_no_raw_manifests` — all CRs via
  `helm_release` (mgmt-side capi-cluster-class + capi-workload-cluster,
  workload-side cni-calico + metallb + metallb-config); zero
  `kubernetes_manifest`, zero `kubectl apply`;
* `feedback_chart_required_values_hardcoded` — the module passes
  only legitimate optional tunables; substrate-required CR fields
  remain hardcoded in chart templates;
* `feedback_makefile_only` — e2e via `make deploy-workload`,
  no direct `terraform apply`;
* `feedback_active_provisioning_monitor` — a second Monitor on top of
  CAPI/CAPN controller logs + Cluster CR conditions caught a
  `Kubernetes cluster unreachable: EOF` failure live; root-cause
  diagnosed without timeout-wait; the fix (wait_for_workload_api)
  landed in the module owner;
* `feedback_no_ad_hoc_fixes` — the root cause of the CNI install failure (Secret
  existence ≠ API serving) was fixed in the module owner (TF), not as a
  workaround in Molecule / shell script.

Done in Step 17 (the same 2026-04-28, follow-up to Step 16):

* **Refactor**: `terraform/modules/workload_cluster/scripts/` removed
  entirely (3 bash files — `wait_for_secret.sh`,
  `wait_for_workload_api.sh`, `helm_test.sh`). The module now contains
  exactly `*.tf` + `.terraform.lock.hcl`, zero scripts.
* **Chart `capi-workload-cluster` 0.7.2 → 0.8.0** — the hook Job
  `api-proxy-attach` takes the full workload-cluster readiness
  contract for itself (see §16.3 Step 17 extensions):
  * Gate 1 — LB instance materialised in LXD
  * Gate 2 — `<cluster>-kubeconfig` Secret emitted by KCP (NEW;
    SA token + REST API call to `kubernetes.default.svc`, without
    kubectl in the hook image; minimal Role +
    RoleBinding on `secrets/get` resourceNames-restricted to a single name added)
  * Gate 3 — LB Running + idempotent PATCH api-proxy device
  * Gate 4 — apiserver `/livez` via `<lb-capi-int-ipv4>:6443`
    answers 200/401/403 (NEW; proves haproxy → CP backend
    chain serving, not just that the LXD entity exists)
* **TF module** drops the `wait_for_kubeconfig_secret` +
  `wait_for_workload_api` null_resources (the chart's hook subsumes
  them); helm test driver inline as a heredoc in
  `provisioner "local-exec"` with `interpreter = ["/usr/bin/env",
  "bash", "-c"]` — no scripts on the FS.
* **Deviation (noted)**: `interpreter = ["bash"]` without `-c`
  treats command-text as a filename. The `-c` flag is mandatory for
  inline-script execution. Discovered end-to-end (helm test
  failed with `: No such file or directory`), fixed in both
  null_resources.

Acceptance Step 17 — **green end-to-end**: `make destroy-workload`
+ `make deploy-workload` fresh cycle, helm test cni-calico
`Phase: Succeeded` in ~2 min, helm test metallb-config
`Phase: Succeeded` in 28s, all 5 Nodes Ready, demo Service
receives VIP `2001:db8:42:100::200`. Module final layout — 6
`.tf` files, zero `.sh`.

Acceptance of the workload TF route — **closed** (2026-04-28):

* `terraform apply` green                            ✓ (Step 16)
* ClusterClass + 5 *Templates applied                ✓ (Step 16)
* Cluster CR + KCP + MD reconciled                   ✓ (Step 16)
* 3 CP + 2 worker LXC instances kubeadm-joined       ✓ (Step 16)
* Workload kubeconfig Secret materialised            ✓ (Step 16)
* Workload API serving via LXD proxy + haproxy LB    ✓ (Step 16)
* CNI Calico — all 5 Nodes Ready=True                ✓ (Step 16)
* Gate B (helm test cni-calico)                      ✓ (Step 16 — 1m43s)
* MetalLB controller + speakers                      ✓ (Step 16)
* MetalLB IPAddressPool + L2Advertisement reconciled ✓ (Step 16)
* Gate A (helm test metallb-config) — VIP allocated  ✓ (Step 16 — 19s)
* Runner-side `kubectl get nodes` via
  rewritten kubeconfig                               ✓ (Step 16)

## 14.8. Pivot mgmt-1 → self-hosted (Step 18)

**Status: implemented in Step 18 (2026-04-29). See §18
(PLAN-stage1-5.md) for the full contract (mgmt-1 helm install
shape, role tasks, re-emit + cleanup chain).**

Composition:

* **Role** `pivot_clusterctl_move` (§13.13) — host-side driver for
  `clusterctl init` on target + `clusterctl move` from bootstrap.
  Pivot mandatory in canonical flow §3 — gates only on
  `pivot_clusterctl_move_enabled` (default `true`).
* **e2e-local Molecule scenario** `tests/molecule/e2e-local/`
  inlines pivot as a mandatory stage: `pivot_clusterctl_move`
  → second include of `export_artifacts` (re-emit, `run_meta_chain:
  false`) → `cleanup_bootstrap`. Acceptance verified by the
  role's own healthchecks plus post-pivot workload helm tests
  in verify.yml.
* **§8 default.** `k8s_lab_management_worker_count` = `2` because
  the cni-calico chart's helm test phase 6 enforces pod
  anti-affinity that requires 2 distinct worker nodes; ≥2 workers
  is the chart-required floor. §2.12 mgmt HA note: replica-contract
  on mgmt activates automatically through the existing
  `var.worker_count >= 2` Terraform condition; CP-side HA still
  requires explicit `k8s_lab_management_controlplane_count = 3` opt-in.

Memory rules applied:

* `feedback_role_dependencies.md` — single meta-dep
  `bootstrap_clusterctl` with `# why` comment; no transitive deps
  enumerated;
* `feedback_required_values_hardcoded.md` — substrate-required
  values (CAPN provider name, tls-server-name, api-proxy-port
  annotation key, required Deployment list) live in `vars/main.yml`
  under `_pivot_clusterctl_move_required_*` prefix;
* `feedback_global_var_prefix.md` — globals are only `k8s_lab_*`
  (`k8s_lab_management_cluster_name`,
  `k8s_lab_capn_provider_version`, `k8s_lab_lxd_host_address`,
  `k8s_lab_opt_root`); role-scoped vars are
  `pivot_clusterctl_move_*`;
* `feedback_ansible_native_first.md` — every `kubectl`/`clusterctl`
  shell-out gated by a read-only `kubernetes.core.k8s_info` probe
  for honest `changed` reporting and idempotent re-runs;
* `feedback_no_ad_hoc_fixes.md` — when the cni-calico helm test
  failed on probe-b Pending (pod-anti-affinity vs single-worker
  topology), root cause was traced to chart-required worker_count
  floor, fix landed in §8 default (chart owner's contract surface)
  + `export_artifacts` tfvars baseline default — not as a
  manual `kubectl scale` or scenario-local `worker_count` override.

Acceptance pivot stage — **green end-to-end** (2026-04-29):

* mgmt-1 helm install green (cluster-class + capi-workload-cluster
  with mgmt-topology values)                          ✓ (Step 18)
* mgmt-1 ClusterClass + Cluster CR + 1 CP + 2 worker  ✓ (Step 18)
* CNI Calico — all 3 Nodes Ready=True                ✓ (Step 18)
* Gate B (helm test cni-calico)                      ✓ (Step 18)
* MetalLB IPAddressPool + L2Advertisement reconciled ✓ (Step 18)
* Gate A (helm test metallb-config)                  ✓ (Step 18)
* `clusterctl init` on target — 4 Provider CRs Available  ✓ (Step 18)
* `clusterctl move` — Cluster CR moved to target     ✓ (Step 18)
* bootstrap source flushed (zero Cluster CRs)        ✓ (Step 18)
* `cleanup_bootstrap` — capi-bootstrap-0 absent      ✓ (Step 18)
* Re-converge idempotence (probes skip mutating steps)  ✓ (Step 18)

Post-pivot workload creation on self-hosted mgmt-1 happens inline in
e2e-local converge (canonical flow §3 / §10.2). Additional
workloads on top of the existing mgmt-1 — via `make deploy-workload`
(TF route, §16.6) against `.artifacts/mgmt.kubeconfig` (now
points to mgmt-1) without overrides.

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
