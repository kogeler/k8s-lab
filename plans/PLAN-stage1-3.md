This file owns §16: the single workload cluster delivery module.
The §N numbering is continuous across all plan files; cross-references
of the form `§<number>` are valid without naming the file — see
`PLAN-stage1-common.md` header for the full file lineup. The atomic
scope of this shard is two already shipped Helm charts
(`charts/capi-cluster-class/` + `charts/capi-workload-cluster/`),
one Terraform module `workload_cluster/` that stands up the entire
functional workload cluster from ClusterClass to cluster add-ons +
acceptance helm tests in a single `terraform apply`, one test fixture
root and Makefile target. The TF route is the operator-facing /
production-oriented alternative to the e2e-local Molecule converge
(§10.2); both use the same charts, different delivery mechanisms.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (workload_cluster TF module: CAPI topology + add-ons + acceptance) <-- this file
PLAN-stage1-4.md ................. §17      (Helm test contracts — Gate A + Gate B chart-side specs)
PLAN-stage1-5.md ................. §18      (pivot mgmt-1 → self-hosted)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 closure + self-review + recommendation)
```

---

# 16. Workload cluster delivery via single Terraform module

## 16.1. Ownership and delivery model

A single TF module `terraform/modules/workload_cluster/` stands up
**the entire functional workload cluster in a single `terraform apply`**:
ClusterClass + Cluster CR + CNI + MetalLB + acceptance helm tests.
The module is self-contained — each module invocation creates its own
independent ClusterClass (per-workload), which makes it possible to
run several workloads with different Kubernetes versions / configs /
tunings on the same management cluster in parallel without
cross-coupling.

Inside the module is a **chain of 5 helm_release's** + **acceptance
null_resource's**, providers are resolved runtime-style:

1. `helm_release.capi_cluster_class` — chart `charts/capi-cluster-class/`
   (§16.2), provider = `helm` aliased on the mgmt kubeconfig (input
   `var.mgmt_kubeconfig`). Per-workload ClusterClass, the name is
   derived from `var.cluster_name + chart-version` (the chart's slug
   formula).
2. `helm_release.capi_workload_cluster` — chart
   `charts/capi-workload-cluster/` (§16.3), provider = mgmt.
   `depends_on` on (1). Creates a Cluster CR in namespace
   `capi-clusters/<cluster_name>`.
3. **Wait + read workload kubeconfig** — `kubernetes_resources` data
   source (provider = mgmt) polling until the Secret
   `<cluster_name>-kubeconfig` appears in `capi-clusters`. `data.value`
   (b64) is decoded into a local; rewritten in the local (replace
   the internal capi-int IPv6 → `https://<lxd_host_address>:<api_proxy_port>` +
   inject `tls-server-name`); used as the inline config for the
   workload helm provider. **Not written to the filesystem** — the
   output is sensitive; if the consumer needs a file — `terraform
   output -raw kubeconfig` (see §16.7 + architectural fence in §16.4
   epilogue).
4. `helm_release.cni_calico` — chart `charts/cni-calico/`, provider =
   `helm` aliased on the workload kubeconfig (obtained in step 3).
   `depends_on` on (2) + workload kubeconfig data.
5. `null_resource.helm_test_cni_calico` — `local-exec` invokes
   `helm test cni-calico --kubeconfig <workload>` (see §17.2 Gate B).
   `depends_on` on (4). Failure fails TF apply.
6. `helm_release.metallb` — chart `charts/metallb/` (subchart
   wrapper), provider = workload. `depends_on` on (5) — CNI must be
   green before the MetalLB controller / speaker DS comes up (Pod
   networking is required for memberlist gossip).
7. `helm_release.metallb_config` — chart `charts/metallb-config/`,
   provider = workload. `depends_on` on (6) — CRDs are registered
   first by the metallb release; the split is due to the
   CRDs-via-templates pattern of the upstream metallb chart (§17.3
   split rationale).
8. `null_resource.helm_test_metallb_config` — `local-exec` invokes
   `helm test metallb-config --kubeconfig <workload>` (see §17.3
   Gate A). `depends_on` on (7). Failure fails TF apply.

**Acceptance gate as part of apply**: TF apply does not return
successfully until both helm tests are green. This turns the Helm
test hooks (Gate A + Gate B) from "a manual step after deploy" into
a **mandatory part of the deploy**. Failure of any helm test →
`null_resource` returns non-zero → TF apply fails → state is marked
tainted, a repeat apply re-provisions the same helm test (idempotent
re-run).

Ownership split:

* **Controllers** (CAPI core + CABPK + KubeadmControlPlane + CAPN
  infrastructure + cert-manager on the mgmt cluster) — delivered by
  `bootstrap_clusterctl` via `clusterctl init --infrastructure
  incus` (§13.10). On the bootstrap they only exist until pivot; on
  mgmt-1 (after canonical flow §3 / §18) they are installed by
  `pivot_clusterctl_move`'s `clusterctl init`. Module §16.4 does not
  touch the controllers and does not reinstall them on its own.
* **CRDs** (ClusterClass, Cluster, KubeadmControlPlaneTemplate,
  KubeadmConfigTemplate, LXCClusterTemplate, LXCMachineTemplate) —
  also delivered by `clusterctl init`. Charts §16.2/§16.3 **do not
  contain CRDs**, only CR instances. CRDs for add-ons (calico,
  metallb) come in via the subchart pattern (see chart statuses and
  §17.3 metallb split note).
* **Cluster-side resources** (CAPI Cluster CR + ClusterClass +
  Templates + CNI Installation CR + MetalLB IPAddressPool /
  L2Advertisement) — single-owner: this repo's Helm charts.
* **Helm test acceptance** (Gate A external L2 + Gate B CNI) —
  single-owner: chart-side hooks (see §17.1 invocation contract +
  §17.2 Gate B + §17.3 Gate A specs), invoked by the TF module via
  `null_resource` in the same apply.

No `kubernetes_manifest`, `kubectl apply -f`, Ansible post-apply on
CAPI/CNI/MetalLB CRs. The `kubernetes` TF provider is allowed only
on the read side (data lookups, status polling — e.g. step 3 wait
for the kubeconfig Secret). Any create/update CR goes through
`helm_release`.

## 16.2. Chart: `charts/capi-cluster-class/`

**Status: done in Step 10 (2026-04-24, version 0.1.0 baseline) +
Step 11 (2026-04-26, bumped to 0.3.0) substrate-required revisions:
`loadBalancer.lxc.instanceSpec.profiles: [capi-base]` baseline
(without it CAPN fails at `Failed getting root disk`),
`KubeadmControlPlaneTemplate` + `KubeadmConfigTemplate` always emit
`kubeletExtraArgs: [feature-gates=KubeletInUserNamespace=true]`
baseline (kubelet's oomWatcher `/dev/kmsg` open in an unprivileged
userns is permission-denied; the gate tells kubelet to ignore the
failure). Verified `loadBalancer.lxc` shape against live CAPN v0.8.5
CRD — `instanceSpec` wrapper, not a flat structure. `helm install`
of both charts is clean, ClusterClass + 5 *Templates land in
`capi-system`, `RefVersionsUpToDate=True`, `VariablesReady=True`,
`Paused=False`.
**Step 12 (2026-04-26) — bumped to 0.4.2** under the dual-stack
acceptance close-out (open issue from §16.6 Step 11 Acceptance
status): KCPT hardcodes `apiServer.bind-address: "::"` +
`controllerManager.allocate-node-cidrs: "true"`; both kubeadm
templates hardcode `kubeletExtraArgs.provider-id: lxc:///{{
v1.local_hostname }}` + dynamic dual-stack `node-ip` via
substrate `preKubeadmCommands` (LXD DHCP/SLAAC); ClusterClass
`patches` propagates `Cluster.spec.clusterNetwork.{pods,
services}` into kubeadm `service-cluster-ip-range` /
`cluster-cidr` via CAPI v1beta2 `valueFrom.template`;
`LXCClusterTemplate.customHAProxyConfigTemplate` is baked in as a
substrate-required dual-bind v4+v6 frontend (CAPN default
haproxy.cfg binds only on v4) and removed from values.yaml;
reserved-arg guards reject consumer overrides on substrate-managed
args (`bind-address`, `service-cluster-ip-range`,
`allocate-node-cidrs`, `cluster-cidr`, `feature-gates`, `node-ip`,
`provider-id`). Full acceptance evidence — §16.6 Step 12 Acceptance
status.**
**Step 13 (2026-04-26) — bumped to 0.5.0** under native-nftables
migration paired with charts/cni-calico (§17.2 Calico
`linuxDataplane: Nftables`): `KubeadmControlPlaneTemplate.
preKubeadmCommands` appends a KubeProxyConfiguration document to
`/run/kubeadm/kubeadm.yaml` before `kubeadm init`. Substrate-required
hardcoded:
* `kind: KubeProxyConfiguration`, `apiVersion:
  kubeproxy.config.k8s.io/v1alpha1`, `mode: nftables` — the Calico
  nftables data-plane requires kube-proxy in nftables mode
  (Calico docs phrase this as a contract).
* `conntrack.maxPerCore: 0`, `conntrack.min: 0` — disables
  kube-proxy's conntrack tuning. The default
  (`maxPerCore: 32768, min: 131072`) leads to an attempt to write
  `/sys/module/nf_conntrack/parameters/hashsize`, which in an
  unprivileged-LXC user-namespace gets permission denied. Without
  the disable, kube-proxy crashloops.
* Init-only gating: the block runs only when
  `kubeadm.yaml` is present and `kubeadm-join-config.yaml` is not.
  KubeProxyConfiguration is honoured only by `kubeadm init`; CP
  joins and worker joins read the populated kube-system/kube-proxy
  ConfigMap.

This gives a single-source-of-truth for kube-proxy mode on a fresh
cluster bring-up through kubeadm init. A live patch of the ConfigMap
on a running cluster (ad-hoc) breaks conntrack state on the fly —
the proper declarative path is only through kubeadm init.**

**Step 15 (2026-04-28) — bumped to 0.6.3** ships eth1 RA reception
baseline as `KubeadmConfigSpec.files` on both
`KubeadmControlPlaneTemplate` and `KubeadmConfigTemplate`. Two files
per node:

* `/etc/sysctl.d/99-capi-ra.conf` — `net.ipv6.conf.eth1.{disable_ipv6=0,
  accept_ra=2, accept_ra_defrtr=1}`. `accept_ra=2` is required because
  workload nodes run with `forwarding=1` for k8s pod networking, and
  the default `accept_ra=1` ignores RA when forwarding is on.
* `/etc/systemd/network/30-capi-ext.network` — `[Match] Name=eth1
  [Network] DHCP=no LinkLocalAddressing=ipv6 IPv6AcceptRA=yes`.

Paired `preKubeadmCommands` run `sysctl --load=/etc/sysctl.d/99-capi-ra.conf`
+ `networkctl reload` so the config is live before kubelet,
kube-proxy, and MetalLB speaker come up. Effect: eth1 SLAAC's a
global IPv6 from the upstream RA, which MetalLB speaker uses as
the source IP for NDP replies on announced VIPs.

The CAPN haproxy LB instance does **not** receive an LXD proxy
device through the topology API — `LXCCluster.spec.loadBalancer.lxc
.instanceSpec` is a closed CRD schema (only `{profiles, image,
flavor, target}`), no `devices` field. The proxy device is
attached post-CAPI by `charts/capi-workload-cluster/`'s own Helm
hook Jobs (`templates/api-proxy-{attach,detach}-job.yaml`) which
PATCH the LXD HTTPS REST API directly with mTLS material from the
`incus-identity` Secret; see §16.7 for the runner-reachability
flow.

Memory rules applied in Step 15:
* `feedback_chart_required_values_hardcoded.md` — files block hardcoded
  in template (substrate-required, not values-tunable);
* `feedback_active_provisioning_monitor.md` — substrate state monitor
  alongside test stdout caught CRD admission errors live in the
  `TopologyReconciled` condition.

Contains a reusable CAPI topology contract for the CAPN unprivileged
kubeadm path. The target API surface is fixed at:

* CAPI core `cluster.x-k8s.io/v1beta2` (Cluster, ClusterClass);
* Kubeadm providers `controlplane.cluster.x-k8s.io/v1beta2` +
  `bootstrap.cluster.x-k8s.io/v1beta2`;
* CAPN `infrastructure.cluster.x-k8s.io/v1alpha2` (LXCClusterTemplate,
  LXCMachineTemplate).

Renders 6 CRs:

* `ClusterClass` — wires infrastructure + controlPlane +
  workers/machineDeployments via `templateRef` (apiVersion + kind +
  name). Does not contain `clusterNetwork` — that is a Cluster CR
  field and lives in the §16.3 chart.
* `LXCClusterTemplate` — CAPN infrastructure. `secretRef.name` =
  §8 `k8s_lab_infrastructure_secret_name`. The LXD project is not a
  CR field in CAPN v1alpha2 — scope lives inside the identity Secret
  (see §15.4 + §13.11). `loadBalancer` is a required CRD field,
  exactly one mode from `{lxc,oci,ovn,kubeVIP,external}`; the MVP
  default `{lxc: {}}` brings up an haproxy-LXC inside the same LXD
  project. Substrate-required hardcoded: `unprivileged: true`,
  `skipDefaultKubeadmProfile: true`, `cloudProviderNodePatch: false`
  — not user-tunable (see the memory rule "Chart-required values are
  hardcoded").
* `LXCMachineTemplate` ×2 (control-plane + worker) — image refs from
  §8 `k8s_lab_images_{controlplane,worker}` +
  `_fingerprint`; CAPN substitutes the literal `VERSION` in the ref
  with the machine's kubernetes version. Profiles = substrate-required
  baseline (`capi-base` + `capi-controlplane` / `capi-worker`, owned
  by role `lxd_profiles` §13.6) + consumer extras through
  `profilesExtra.*`. Devices — CAPN v1alpha2 requires a `[]string`
  CSV format (`"eth1,type=nic,network=br-ext6"`); optional overrides
  through `devicesExtra.*`. Substrate-required hardcoded:
  `instanceType: container`.
* `KubeadmControlPlaneTemplate` — a pure tuning contract:
  `featureGates`, `*ExtraArgs` (v1beta2 `[{name, value}]` format,
  `minItems: 1` at the CRD level → emitted only under a non-empty
  override), `kubeletExtraArgs`, `preKubeadmCommands`,
  `postKubeadmCommands`. MVP default — empty (kubeadm defaults).
* `KubeadmConfigTemplate` (worker) — an analogous tuning contract
  for the join side.

### Name-versioning contract

The CAPI webhook forbids changing most fields of `ClusterClass` and
`*Template` CRs once a Cluster has referenced them. Therefore any
edit to `values.yaml` / templates = bump `Chart.yaml.version` = a
new set of objects with new names; old Cluster CRs continue to
point at the previous ClusterClass until a controlled cutover.

Implementation — Helm helper `capi-cluster-class.classFullName`:

```gotemplate
{{- define "capi-cluster-class.versionSlug" -}}
{{- .Chart.Version | replace "." "-" | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "capi-cluster-class.classFullName" -}}
{{- printf "%s-%s" .Values.clusterClass.name
     (include "capi-cluster-class.versionSlug" .)
     | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

Dots in the chart version are replaced with `-` for DNS-1123-subdomain-safe
names (otherwise strict downstream validators fail `0.1.0` in
`metadata.name`). Each subobject (`LXCClusterTemplate`,
`LXCMachineTemplate` CP/worker, KCPT, KCT) additionally gets a
role suffix (`-infra`, `-cp`, `-md0`, `-kcp`, `-md0-bootstrap`)
on top of `classFullName`, so a chart-version bump rotates them
in sync.

The `capi-workload-cluster` chart (§16.3) assembles the ClusterClass
name in `spec.topology.classRef.name` by the same `replace "." "-"`
formula from a shared values block (`clusterClass.chartVersion`).
The Terraform module (§16.4) exports the rendered name through the
`cluster_class_name` output and threads it into the workload chart
inside the same helm_release chain directly — the fixture (§16.5)
does not recompute the formula.

We do not introduce a separate §8 variable for the revision — the
single source of truth is `Chart.yaml.version`, accessible to both
charts via `.Chart.Version`.

### Values layout (public chart interface)

The "Chart-required values are hardcoded" rule (see memory) keeps
substrate-mandatory CR fields out of `values.yaml`. The consumer
cannot override `unprivileged`, `skipDefaultKubeadmProfile`,
`cloudProviderNodePatch`, `instanceType`, apiVersion choices, or
required-baseline profiles — all of this is baked into
`templates/*.yaml`.

```yaml
# charts/capi-cluster-class/values.yaml — structural schema
clusterClass:
  name: capn-default           # prefix; final name = "{name}-{chart-version-slug}"
kubernetes:
  version: ""                  # §8 k8s_lab_kubernetes_version
capn:
  infrastructureSecretName: "" # §8 k8s_lab_infrastructure_secret_name
images:
  controlplane:
    ref: "capi:kubeadm/VERSION"   # §8 k8s_lab_images_controlplane
    fingerprint: ""               # §8 k8s_lab_images_controlplane_fingerprint
  worker:
    ref: "capi:kubeadm/VERSION"   # §8 k8s_lab_images_worker
    fingerprint: ""               # §8 k8s_lab_images_worker_fingerprint
loadBalancer:                 # exactly one mode; see values.yaml note
  lxc: {}
profilesExtra:                # added on top of the substrate baseline
  controlplane: []            # §8 k8s_lab_controlplane_profiles_extra
  worker: []                  # §8 k8s_lab_worker_profiles_extra
devicesExtra:                 # CAPN v1alpha2 []string CSV format
  controlplane: []            # §8 k8s_lab_controlplane_devices_extra
  worker: []                  # §8 k8s_lab_worker_devices_extra
controlPlane:
  featureGates: {}
  apiServerExtraArgs: []      # v1beta2 [{name,value}] format
  controllerManagerExtraArgs: []
  schedulerExtraArgs: []
  kubeletExtraArgs: []
  preKubeadmCommands: []
  postKubeadmCommands: []
worker:
  featureGates: {}
  kubeletExtraArgs: []
  preKubeadmCommands: []
  postKubeadmCommands: []
kubeProxy:
  nodePortAddresses: []       # §8 k8s_lab_kube_proxy_nodeport_addresses
```

`values.schema.json` asserts required keys
(`clusterClass.name` matches DNS-1123, `kubernetes.version` matches
`^v\d+\.\d+\.\d+(\+.+)?$`, `capn.infrastructureSecretName` non-empty,
`loadBalancer` exactly 1 property, `devicesExtra.*` items match the
CSV pattern) — the chart fails at the `helm template` stage if the
wiring does not come together from tfvars.

### CRD readiness guards

Each template file is gated by CAPI/CAPN API availability through a
Helm helper with `fail` semantics (not silent skip):

```gotemplate
{{- define "capi-cluster-class.requireCAPN" -}}
{{- if not (.Capabilities.APIVersions.Has
       "infrastructure.cluster.x-k8s.io/v1alpha2/LXCClusterTemplate") -}}
{{- fail "CAPN v1alpha2 is not served. Run `clusterctl init --infrastructure incus` first." -}}
{{- end -}}
{{- end -}}
```

Three paired helpers: `requireCAPI` (cluster.x-k8s.io/v1beta2),
`requireCAPN` (v1alpha2), `requireKubeadm` (controlplane + bootstrap
v1beta2). If `clusterctl init` did not complete or a different
infrastructure provider is active, `helm install` fails with an
informative error before the admission stage rather than silently
rendering zero CRs.

### Implementation notes (Step 10, 2026-04-24)

**Chart files:** `Chart.yaml` (0.1.0, `appVersion: 0.8.5`), `values.yaml`,
`values.schema.json`, `templates/_helpers.tpl` (helpers + API-gate
`fail` functions), `templates/cluster-class.yaml`,
`templates/lxc-cluster-template.yaml`,
`templates/lxc-machine-template-controlplane.yaml`,
`templates/lxc-machine-template-worker.yaml`,
`templates/kubeadm-control-plane-template.yaml`,
`templates/kubeadm-config-template-worker.yaml`.

**Deviations from the initial §16.2 design (all fixed against the
verified CRD schemas of CAPI v1.12.5 / CAPN v0.8.5):**

* CAPI storage version = `v1beta2`. `Cluster.spec.topology` in
  v1beta2 uses `classRef.name` (not `class`), references in
  ClusterClass go via `templateRef` (not `ref`), and `*ExtraArgs` /
  `kubeletExtraArgs` are `[]{name,value}` lists with `minItems: 1`
  at the CRD level (not `map[string]string`). All render paths emit
  the block only under a non-empty override.
* CAPN v1alpha2 `LXCClusterSpec` **has no** `project` field — scope
  is set inside the identity Secret (the `project` field in the
  Secret payload from §13.11). The chart does not attempt to pass
  the project through the CR.
* `installKubeadm` **is not a CR field** in CAPN v1alpha2.
  Install-kubeadm-at-runtime is modelled via
  `controlPlane.preKubeadmCommands` / `worker.preKubeadmCommands` in
  values, MVP default empty (prebuilt `capi:kubeadm/*` images).
* `LXCMachineSpec.devices` is `[]string` in CAPN CSV format
  (`"eth0,type=nic,network=my-net"`), not a map. The values key is
  `devicesExtra.{controlplane,worker}` with a pattern check in
  `values.schema.json`.
* `LXCClusterTemplate.loadBalancer` is a **REQUIRED field** at the
  CRD level with `exactly one of {lxc, oci, ovn, kubeVIP, external}`;
  "none" is not accepted. MVP default = `{lxc: {}}` (an haproxy-LXC
  instance inside the same LXD project). Mode switching requires
  explicit nullification of the default (`lxc: null`) due to Helm
  deep-merge semantics — described inline in values.yaml.
* `KubeadmControlPlaneTemplate.spec.template.spec.kubeadmConfigSpec` +
  all nested `clusterConfiguration.{apiServer,controllerManager,
  scheduler}`, `initConfiguration.nodeRegistration`,
  `joinConfiguration.nodeRegistration` — each has
  `minProperties: 1` at the CRD level (webhook validation, NOT
  visible on `helm install --dry-run=server`). Templates fully omit
  empty blocks; the substrate-required literal `format: cloud-config`
  in `kubeadmConfigSpec` satisfies `minProperties` and at the same
  time bakes in the correct substrate choice (CAPN consumes
  cloud-init, the ignition path is not supported).

**Chart-required hardcoded baseline (memory rule
"Chart-required values are hardcoded"):** baked into templates,
not available via `values.yaml`:

* `unprivileged: true`, `skipDefaultKubeadmProfile: true`,
  `cloudProviderNodePatch: false`, `instanceType: container`,
  `format: cloud-config` — substrate policy (§2.8 / §13.6).
* LXD profile baseline for the three types of instance CAPN spawns:
  * **CP machine** = `capi-base` + `capi-controlplane` + consumer
    `profilesExtra.controlplane`;
  * **worker machine** = `capi-base` + `capi-worker` + consumer
    `profilesExtra.worker`;
  * **`loadBalancer.lxc` haproxy instance** = `capi-base` + consumer
    `loadBalancer.lxc.profilesExtra` — substrate-required: without
    `capi-base` (root-disk device + internal-net NIC) CAPN fails to
    create the LB instance with "Failed getting root disk: No root
    device could be found". The consumer CANNOT remove any of these
    three baselines; `profilesExtra.*` is append-only.
* `apiVersion` choices (CAPI `v1beta2`, CAPN `v1alpha2`) are baked
  into templates; API readiness is checked via
  `.Capabilities.APIVersions.Has` + `fail` helpers.

**Cross-artifact changes triggered by this Step:**

* `bootstrap_capn_secret` (§13.11) — `lxd_project` and
  `internal_network_name` defaults now `bind` to §8 globals
  (`k8s_lab_project_name` / `k8s_lab_internal_network_name`). The
  reason: the project scope cannot be passed through the CR (see
  deviation above), so the Secret payload MUST atomically track the
  project-name global. Details — §13.11 Step 10 extensions.
* `§8` (PLAN-stage1-common.md): `k8s_lab_install_kubeadm` removed
  (not a CR field), `k8s_lab_{controlplane,worker}_profiles` →
  `..._profiles_extra` (list of strings), `k8s_lab_{controlplane,
  worker}_devices` → `..._devices_extra` (list of CSV strings under
  CAPN v1alpha2 shape). `k8s_lab_infrastructure_secret_name` default
  aligned to CAPN upstream `"incus-identity"`.
* `§2.10` (node image policy) — install-kubeadm-at-runtime
  reclassified from "a CR field with default false" to
  "a preKubeadmCommands extension point in KCPT/KCT" (since
  `installKubeadm` does not exist in the CAPN v1alpha2 API).
* `§12.9` mitigation (CAPN pre-built images are evaluation-oriented)
  — the bullet about `k8s_lab_install_kubeadm=true` was rewritten in
  terms of the `preKubeadmCommands` vector (same semantics, correct
  name).
* `§12.10` mitigation (CAPI CR immutability) — the slug formula
  `Chart.Version | replace "." "-"` is fixed explicitly in the
  name-versioning pattern; `spec.topology.class` →
  `spec.topology.classRef.name` per v1beta2.
* `§16.3` / `§16.4` / `§16.5` / `§16.6` — module + fixture input
  contracts updated under the new public chart interface (no
  `project`, no `install_kubeadm`, profiles/devices with `_extra`
  suffix, `spec.topology.classRef.name` in the Acceptance block of
  §16.6).
* Memory rule `feedback_chart_required_values_hardcoded.md` — a new
  Helm symmetry of the Ansible rule `feedback_required_values_hardcoded`;
  a policy that obligates substrate-required CR fields to be baked
  into templates rather than exposed via `values.yaml`.

**Test evidence:**

* `helm lint` + `helm template --api-versions=...` under the minimal
  required values + a rich override (kubeVIP mode, featureGates,
  extraArgs, preKubeadmCommands, profilesExtra, devicesExtra CSV) —
  both paths are green; the schema rejects known-bad overrides
  (missing required, invalid k8s-version pattern, empty
  loadBalancer, uppercase cluster name, non-CSV device entry).
* `helm install cluster-class-test charts/capi-cluster-class
  --namespace capi-system` against the bootstrap kubeconfig —
  `STATUS: deployed`; all 6 CRs in `capi-system`, ClusterClass
  reconciled with three positive conditions (`RefVersionsUpToDate`,
  `VariablesReady`, `Paused=False`). `helm uninstall` is clean, 0
  residual objects.
* The first real-install run caught CRD-level `minProperties: 1`
  violations that dry-run skipped; the fix is described in the
  deviations above. The regression is protected by hardcoding
  `format: cloud-config` + the full omit of empty blocks in
  templates, not through values.
* `bootstrap_capn_secret` molecule full cycle green:
  `converge ok=283 changed=45 failed=0`,
  `idempotence ok=271 changed=0 failed=0`,
  `verify ok=14 changed=0 failed=0` (all 14 assertions about
  project/server/trust/TLS round-trip passed, which confirms
  the §13.11 Step 10 extension).
* `export_artifacts` molecule full cycle green:
  `converge ok=298 changed=3 failed=0`,
  `idempotence ok=298 changed=0 failed=0`,
  `verify ok=16 changed=0 failed=0`;
  `.artifacts/mgmt.kubeconfig` +
  `.artifacts/mgmt.auto.tfvars.json` materialised on the runner.
* Workload-side E2E (real Cluster CR + LXC nodes on the substrate)
  remains in the scope of §16.3 + §16.4 + §16.5 + §16.6 — was not
  exercised in Step 10.

## 16.3. Chart: `charts/capi-workload-cluster/`

**Status: done in Step 11 (2026-04-26, version 0.3.0 baseline) +
Step 12 (2026-04-26, bumped to 0.4.2) — `templates/tests/cluster-
ready.yaml` Helm test hook extended into a 10-phase dual-stack
acceptance driver (see below for Step 12 extensions). `Chart.yaml`
annotation `k8s-lab.io/capi-cluster-class-chart-version` mirrors the
chart version (rotation pin). End-to-end acceptance: `helm install`
of both charts + `helm test` through bootstrap k3s yields exactly
`controlPlane.replicas` CP + `workers.replicas` worker nodes,
dual-stack `InternalIP`/`podCIDR`s on each, `providerID =
lxc:///<node>`, and the `RequireDualStack` ClusterIP allocator hands
out both `clusterIPs` (v4 + v6).
**Step 13 (2026-04-26) — bumped to 0.5.0** paired with
charts/capi-cluster-class 0.5.0 (rotation contract). No
template changes in this chart — the bump is purely under the
coupling rotation (chart annotation `k8s-lab.io/capi-cluster-class-chart-version` →
`"0.5.0"`). Causal: charts/capi-cluster-class 0.5.0 added
KubeProxyConfiguration to the KCPT (§16.2 Step 13), which under the
name-versioning formula rotates the ClusterClass / *Template names
to `capn-default-0-5-0` — any workload Cluster CR that references
the ClusterClass through classRef.name must resolve the new name.
The annotation pin keeps that invariant.**

**Step 15 (2026-04-28) — bumped to 0.7.2** paired with
charts/capi-cluster-class 0.6.3 (rotation contract). Changes in
this chart:

* **Per-workload deterministic API proxy port** — helper
  `capi-workload-cluster.apiProxyPort` computes the port from the
  cluster name via an **Adler-32 hash** (Sprig `adler32sum`, returns
  a decimal string parseable through `atoi`):
  `add 20000 (mod (atoi (adler32sum .Values.cluster.name)) 10000)`.
  Pure function — same name → same port across re-installs.
  Range 20000-29999 (10k buckets; collision rate <1% across 10
  workloads). Override via `loadBalancer.lxc.proxyApiPort`
  (integer, default 0 = use hash).
* **Cluster CR.metadata.annotations** — adds
  `k8s-lab.io/api-proxy-port: "<computed>"` (string-quoted decimal).
  **Single source of truth** for downstream consumers (Molecule
  verify.yml, future TF `workload_cluster` module): the port is
  read from the CR annotation, not recomputed.
* **Helm-only LXD `proxy` device delivery** — chart ships two hook
  Jobs (`templates/api-proxy-{attach,detach}-job.yaml`) which patch
  the haproxy LB instance through the **LXD HTTPS REST API**:
  - `post-install,post-upgrade` Job (`api-proxy-attach`): waits for
    CAPN to materialise `<cluster>-<suffix>-lb` LXC instance, then
    `PATCH /1.0/instances/<lb>?project=<p>` body
    `{"devices":{"api-proxy":{"type":"proxy","listen":"tcp:0.0.0.0:<port>","connect":"tcp:127.0.0.1:6443","bind":"host"}}}`
    — LXD merge-on-PATCH adds the device without disturbing the
    instance's other devices (root disk, NICs).
  - `pre-delete` Job (`api-proxy-detach`): symmetric inverse —
    `PATCH` with `{"devices":{"api-proxy":null}}` removes the key.
  Image: `alpine:3.21`, runtime `apk add curl jq` (no incus/lxc CLI
  binary). Driven against the LXD daemon URL + mTLS material from
  the `incus-identity` Secret (same Secret CAPN itself reads —
  owned by role `bootstrap_capn_secret`). New values knobs:
  `apiProxy.image`, `apiProxy.infrastructureSecretName`,
  `apiProxy.lbWaitTimeoutSeconds`.

  **Why a hook Job rather than ClusterClass topology patch:** CAPN
  v1alpha2 declares `LXCCluster.spec.template.spec.loadBalancer.lxc
  .instanceSpec` as a closed CRD schema (only `profiles/image/
  flavor/target` — no `devices` field). A JSON patch through the
  ClusterClass topology API to add the `devices` block fails at
  admission with `field not declared in schema`. A post-install
  Helm hook is the only declarative path that keeps the device
  attach inside chart-owned lifecycle (every consumer — Molecule,
  TF, manual `helm install` — gets it for free).
* Annotation pin bumped `k8s-lab.io/capi-cluster-class-chart-version`
  → `"0.6.3"`. ClusterClass / *Template names rotate to
  `capn-default-0-6-3`.

Memory rules applied in Step 15:
* `feedback_chart_required_values_hardcoded.md` — port computation
  formula hardcoded in helper, override only via legitimate optional
  values knob;
* `feedback_test_artifact_naming.md` — annotation prefix
  `k8s-lab.io/` for project-owned annotation key;
* `feedback_helm_first_no_raw_manifests.md` — runner-reachability
  delivered through the chart's own hook Jobs, not through inline
  shell in Molecule / `null_resource` in TF;
* `feedback_no_bitnami_images.md` — alpine + apk for hook Job
  image, no vendored client tooling.**

**Step 17 (2026-04-28) — bumped to 0.8.0** — the chart takes
full workload-cluster readiness gating on itself, so that TF
module §16.4 does not maintain its own wait loops through bash
scripts. Changes in `templates/api-proxy-attach-job.yaml` (a single
`post-install` hook Job + minimal Role/RoleBinding on the
`<release>-api-proxy-hook` SA with `get` on
`secrets/<cluster>-kubeconfig` in `.Release.Namespace`):

* **Gate 1** — wait for the LB instance to materialise in LXD (was
  there in 0.7.2);
* **Gate 2** — wait for the `<cluster>-kubeconfig` Secret to be
  present (NEW); driven through the mounted SA token +
  `kubernetes.default.svc` REST API, without `kubectl` in the hook
  image (alpine + curl + jq balance preserved);
* **Gate 3** — wait for the LB instance LXD `Running` state +
  idempotent PATCH of the api-proxy device (was in 0.7.2; added
  Running polling);
* **Gate 4** — probe `https://<lb-capi-int-ipv4>:6443/livez` via
  bootstrap-LXC-side curl until 200/401/403 (NEW). Proof that the
  haproxy → CP backend chain is actually serving, not just that the
  LXD entity exists.

`helm install --wait` blocks release deployed status until all 4
gates pass. Downstream chart installs (CNI, MetalLB) can talk to
the workload API immediately. **Memory rule
`feedback_chart_required_values_hardcoded` applied:** the chart owns
the whole readiness contract itself, TF is a consumer.

Annotation pin `k8s-lab.io/capi-cluster-class-chart-version`
stays at `"0.6.3"` — coupling with capi-cluster-class did not
change.

Contains one Cluster CR (`cluster.x-k8s.io/v1beta2`) that references
the ClusterClass from §16.2 via `spec.topology.classRef`, plus
`spec.clusterNetwork` dual-stack CIDRs for pod/service (this is the
only field where network CIDRs are set declaratively in
topology mode). The ClusterClass `patches` block (§16.2) propagates
these `pods` / `services` CIDRs into kubeadm `apiServer.extraArgs.
service-cluster-ip-range` and `controllerManager.extraArgs.
{cluster-cidr,service-cluster-ip-range}` via CAPI v1beta2
`valueFrom.template`. Per-cluster ConfigMaps/Secrets for custom
cloud-init extra-data are not in the chart — the MVP baseline does
not require this.

`Chart.yaml.appVersion` tracks CAPI core (the Cluster CR is a
CAPI-core type), not CAPN.

### Cluster-class compatibility pin (annotation, not values)

The chart renders `spec.topology.classRef.name` by the same slug
formula that §16.2 uses for `metadata.name` of the ClusterClass
(`Chart.Version | replace "." "-"`). **The version of the
cluster-class chart this workload-cluster is compatible with is
pinned in `Chart.yaml`:**

```yaml
# charts/capi-workload-cluster/Chart.yaml
annotations:
  k8s-lab.io/capi-cluster-class-chart-version: "0.4.2"
```

The helper reads it through `.Chart.Annotations[...]`:

```gotemplate
{{- define "capi-workload-cluster.classFullName" -}}
{{- $v := index .Chart.Annotations "k8s-lab.io/capi-cluster-class-chart-version" -}}
{{- $slug := $v | replace "." "-" | lower | trunc 63 | trimSuffix "-" -}}
{{- printf "%s-%s" .Values.clusterClass.name $slug | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

Rotation contract: bumping cluster-class `Chart.version` (e.g.,
`0.4.2 → 0.5.0`) requires a paired bump of the annotation **and**
the workload-cluster `Chart.version` (traceability). The consumer
(Terraform fixture or standalone `helm install`) **does not pass**
the cluster-class version — the coupling is declared in Chart.yaml,
not in values.yaml.

### Values layout

```yaml
# charts/capi-workload-cluster/values.yaml — structural schema
cluster:
  name: lab-default                # §8 k8s_lab_workload_cluster_name
clusterClass:
  name: capn-default               # bind to §16.2 clusterClass.name
  namespace: ""                    # see below about cross-ns classRef
kubernetes:
  version: "v1.35.0"               # chart's own latest-stable pin
                                   # (verified upstream stable.txt
                                   # 2026-04-25; §8 k8s_lab_kubernetes_version
                                   # overrides via workload fixture)
topology:
  controlPlane:
    replicas: 3                    # §8 k8s_lab_workload_controlplane_count
                                   # CAPI invariant: must be odd under stacked etcd
  workers:
    replicas: 2                    # §8 k8s_lab_workload_worker_count
clusterNetwork:
  pods:
    cidrBlocks: ["10.244.0.0/16", "fd42:77:2::/56"]   # dual-stack [v4, v6]
  services:
    cidrBlocks: ["10.96.0.0/16", "fd42:77:3::/112"]   # dual-stack [v4, v6]
tests:
  image: "alpine:3.21"             # see below about the helm test hook
  nodesUpTimeoutSeconds: 1200      # 20 min — realistic budget for CAPN
                                   # provisioning 3CP+2W LXC under cold cache
```

All defaults track the §8 reference deployment so that:

* `helm v4 lint` passes without `-f overrides.yaml` (helm v4
  strictly validates `values.yaml` against `values.schema.json`);
* a standalone `helm install charts/capi-workload-cluster` renders
  a working Cluster CR without operator hooks (the chart is
  self-validating as documentation).

The CAPI invariant (`controlPlane.replicas` odd for stacked etcd) is
**not enforced in the schema** — the schema allows 1+; a developer
can deliberately set `2` for a unit test on CAPI rejection. The
default `3` plus an inline comment cover the working path.

Substrate-required (chart-required, hardcoded in templates, not
exposed in values per memory `feedback_chart_required_values_hardcoded`):

* `apiVersion: cluster.x-k8s.io/v1beta2` + `kind: Cluster`;
* `spec.topology.workers.machineDeployments[0].class: md-0` — must
  match what §16.2 ClusterClass bakes into
  `workers.machineDeployments[].class`. The match is a chart-level
  invariant, not consumer-tunable;
* `spec.topology.workers.machineDeployments[0].name: md-0` —
  single-MD topology is baked into the template as a chart-level
  invariant.

### Namespace ownership: OUT of chart scope

The workload Cluster CR lives in `.Release.Namespace`
(`metadata.namespace` is rendered from `helm install --namespace ...`).
**The chart itself does NOT deliver the namespace.** The owner of
the namespace lifecycle is the workload Terraform fixture (§16.5)
through `helm_release.create_namespace = true` (or the operator
manually for a chart-level smoke).

Reasons for the architectural choice (verified Step 11):

* `helm.sh/hook: pre-install` for a namespace breaks on the second
  install: the default `helm.sh/hook-delete-policy: before-hook-creation`
  removes the existing namespace with all CRs inside before
  re-creation. Alternative delete-policies either delete on success
  or only on failed — all three options are incompatible with the
  long lifecycle of a cluster namespace;
* multi-cluster scenario: `capi-clusters` (or a fleet of namespaces
  from `k8s_lab_capn_identity_namespaces`) is sized for N workload
  Cluster CRs. If a per-cluster chart owned the namespace, a second
  install would fail on ownership conflict (`resource already exists
  outside the release`).

Per-cluster RBAC (`ServiceAccount` + `Role` + `RoleBinding` for the
helm test pod — see below) all scope to `.Release.Namespace` and
ship as regular Helm-managed resources, garbage-collected on
`helm uninstall`.

### Cross-namespace ClusterClass reference

`clusterClass.namespace: ""` (default) → `spec.topology.classRef.namespace`
omitted → CAPI defaults to `Cluster.metadata.namespace` (same-ns
pattern). Set explicitly (e.g. `"capi-system"`) for a cross-namespace
ClusterClass reference — CAPI v1beta2 supports this natively via
`ClusterClassRef.namespace`.

The reference deployment in this repo: ClusterClass installed in
`capi-clusters`, workload Cluster CR — in the same `capi-clusters` →
`clusterClass.namespace: ""` (same-namespace, CAPI defaults).
The cross-namespace variant (e.g. ClusterClass in `capi-system`) is
valid for a consumer with multi-cluster-class deployments.

### CAPN identity Secret prerequisite

The chart does **not** materialise the identity Secret. The owner is
§13.11 `bootstrap_capn_secret`, which through
`k8s_lab_capn_identity_namespaces` fans out the Secret into every
workload-cluster namespace BEFORE the chart is installed.

Architectural invariant (verified Step 11 against the CAPN v0.8.5
controller): CAPN does not read the identity Secret from its
controller namespace (`capn-system`). `LXCCluster.spec.secretRef` in
v1alpha2 has no namespace field; CAPN looks for the Secret in the
namespace of the LXCCluster CR (i.e., in
`Cluster.metadata.namespace`). Therefore the Secret must live in
the same namespace as the Cluster CR. See §13.11 cleanup contract.

### Helm test hook — chart-level acceptance

`charts/capi-workload-cluster/templates/tests/` ships:

* `rbac.yaml` — `ServiceAccount` + `Role` + `RoleBinding` (regular
  Helm-managed). Read scope:
  * `secrets` (resourceNames-restricted to `<cluster.name>-kubeconfig`);
  * `cluster.x-k8s.io/{clusters,machinedeployments,machines}` (get/list/watch);
  * `controlplane.cluster.x-k8s.io/kubeadmcontrolplanes` (get/list/watch);
  * `infrastructure.cluster.x-k8s.io/{lxcclusters,lxcmachines}` (get/list/watch).
* `cluster-ready.yaml` — Pod with `helm.sh/hook: test` +
  `helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded`.

The test pod uses an `alpine:3.21` base + downloads an upstream
kubectl binary at runtime via busybox `wget` from
`https://dl.k8s.io/release/<kubernetes.version>/bin/linux/amd64/kubectl`
(memory rules: "no bitnami", "latest stable").

Two-phase test logic in a single Pod (one `helm test` invocation,
one PASS/FAIL); 10 steps of verification:

* **Phase 1 — bootstrap-side shape (~2 min):**
  * `[1/10]` Cluster CR present in `.Release.Namespace`;
  * `[2/10]` `kubectl wait Cluster --for=condition=TopologyReconciled=True`
    (CAPI accepted topology + spawned owned objects);
  * `[3/10]` owned `KubeadmControlPlane` materialised (label
    `cluster.x-k8s.io/cluster-name=<cluster.name>`);
  * `[4/10]` owned `MachineDeployment` materialised;
  * `[5/10]` owned `LXCCluster` materialised;
  * `[6/10]` LXCCluster carries dual-bind v4+v6
    `customHAProxyConfigTemplate` (regression guard on §16.2 Step 12
    chart-side hardcode — without it the LB listens only on v4).
* **Phase 2 — workload-side authoritative dual-stack check (~20 min default):**
  * `[7/10]` poll until `Cluster.spec.controlPlaneEndpoint` appears
    (CAPN auto-derives it from haproxy LB instance IP; on a
    single-node LXD substrate this is the IPv6 capi-int address on
    :6443);
  * `[8/10]` poll until `<cluster.name>-kubeconfig` Secret appears
    in `.Release.Namespace` (KCP controller emits it post-init of
    the first CP node); decode the Secret → `/tmp/wl.kubeconfig`;
  * `[9/10]` workload API `/livez` succeeds via the selected
    control-plane endpoint — proves the haproxy LB → CP serving
    works on both families (apiserver `--bind-address=::` +
    dual-bind LB template, see §16.2 Step 12);
  * `[10/10]` count `Node` objects through the workload kubeconfig:
    * by label `node-role.kubernetes.io/control-plane=` → must be
      **exactly** `topology.controlPlane.replicas`;
    * by label `!node-role.kubernetes.io/control-plane` → must be
      **exactly** `topology.workers.replicas`;
  * **per-Node asserts on dual-stack contracts (Step 12):**
    `spec.providerID == "lxc:///<node-name>"` (substrate-required
    hardcode from §16.2), `status.addresses` contains exactly one
    IPv4 and at least one global IPv6 `InternalIP`, `spec.podCIDRs`
    contains both families (`10.244.x.x/24` + `fd42:77:2:x::/64`);
  * **runtime probe (Step 12):** apply a `Service` with
    `ipFamilyPolicy: RequireDualStack` in the default namespace and
    verify that the allocator handed out both `spec.clusterIPs` —
    confirms that kube-controller-manager hands out service-CIDR
    from both families; cleanup via `trap EXIT` on `kubectl delete
    service`;
  * **`Node.Ready=True` is NOT required** — CNI is installed by
    §16.4 module as a separate `helm_release` further down the
    chain; workers will be NotReady until then.
    "Came up" == "registered with API server" (kubeadm join
    completed) — that's an authoritative signal from the API server
    that the node has actually joined the cluster.

### Step 12 extensions (2026-04-26)

The Step 11 helm test hook ended on counting `Node`s through the
workload kubeconfig, was `>=` (not `==`), and confirmed neither
dual-stack endpoint family selection, nor per-Node providerID/
InternalIP/podCIDR shape, nor service-CIDR allocator behaviour.
The Step 12 chart-side dual-stack hardening (§16.2 KCPT
`bind-address: "::"` + ClusterClass `patches` for service/pod
CIDRs + LXCCluster dual-bind HAProxy template) is necessary, but
the helm test without runtime confirmation easily misses a
regression: for example, the ClusterClass `patches` block could
have failed to render the service CIDRs (CAPI v1beta2
`valueFrom.template` typing is fairly subtle), and the cluster
would have come up askew — without a runtime check that is
invisible.

The 10-phase form closes this gap:

* `/livez` via the CAPN-selected endpoint proves that the LB binds
  on both families and the apiserver listens on both families
  (ENOREACH on any of these conditions → `[9/10]` fails before we
  even reach the Node count);
* per-Node `providerID = lxc:///<node>` — chart substrate invariant
  (§16.2 hardcode); a regression in the `kubeletExtraArgs`-merge
  logic in KCPT/KCT would break future CCM-style features with an
  empty providerID (subsequent add-on releases inside §16.4);
* per-Node dual-stack `InternalIP` + `podCIDR` — proof of the
  end-to-end chain: kubelet `--node-ip=v4,v6`
  (substrate `preKubeadmCommands` patches the kubeadm config),
  kube-controller-manager `--allocate-node-cidrs=true` (KCPT
  hardcode), Cluster.spec.clusterNetwork.pods CIDRs (via
  ClusterClass `patches` propagated into KCM
  `--cluster-cidr=v4,v6`);
* `RequireDualStack` ClusterIP service probe — runtime confirmation
  that the kube-apiserver service-CIDR allocator is bundled with
  both families and both are handed out on a single Service object;
* Replica counts from `>=` to `==` — `>=` is silent on "extra"
  registered Nodes (orphan Machines, for example), `==` rejects
  any topology drift.

The substrate fix in Step 12 (LXD profile `host-boot` device on
capi-worker — §13.6) is paired; without it the preflight on the
worker fails before the node registers (i.e., before the
counting in `[10/10]`).

Helm-3-only features (TF helm provider 3.1.x compatibility):

* `helm.sh/hook: test` (helm 3+);
* `helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded`
  (helm 3+);
* `.Chart.Annotations` access (helm 3+);
* JSON Schema draft 2020-12 (helm 3.9+).

No helm 4-only features. The chart works with any helm 3 SDK that
the TF provider bundles.

### CRD readiness gate

`requireCAPI` (`cluster.x-k8s.io/v1beta2/Cluster`) is the only gate.
CAPN/Kubeadm gates are **redundant** in this chart: the Cluster CR
references only the ClusterClass; the CAPN/kubeadm-typed templateRefs
live in that ClusterClass (the §16.2 chart owns those gates). If
the ClusterClass is missing or its *Templates are malformed — the
CAPI webhook rejects Cluster admission with an informative error.

## 16.4. Module: `terraform/modules/workload_cluster/`

**Status: done in Step 16 (2026-04-28) — the module shipped
end-to-end on a live Vagrant substrate via `make deploy-workload`.
Files: `versions.tf`, `providers.tf` (mgmt + workload
helm/kubernetes aliases, the workload helm provider parses
kubeconfig fields inline — host / cluster_ca / client_cert /
client_key from the parsed Secret, without config_path and without
writing to FS), `variables.tf` (validation on odd CP count,
dual-stack [v4,v6] arrays, k8s version regex, non-empty
lxd_host_address), `locals.tf` (slug formula matches the chart side,
all 5 chart-values mappings, kubeconfig parse + endpoint rewrite +
inject `tls-server-name: kubernetes.default.svc`), `main.tf` (the
chain of steps 1..10), `outputs.tf`, `scripts/wait_for_secret.sh`,
`scripts/wait_for_workload_api.sh` (deviation, see below),
`scripts/helm_test.sh`. End-to-end timing on a cold Vagrant
substrate (the existing bootstrap from Step 15): ClusterClass 14s +
workload chart 14s + wait_for_kubeconfig_secret 0s + workload_api
wait ~5min (kubeadm init on 3 CPs + API serving) + CNI install 14s +
Gate B 1m43s + MetalLB 32s + MetalLB-config 1s + Gate A 19s ≈ ~9
min total.**

**Step 17 (2026-04-28) — full readiness gating moved inside the
chart `capi-workload-cluster` 0.8.0 hook Job** (see §16.3 Step 17).
Module Step 16 contained two null_resource's with bash scripts
(`wait_for_secret.sh` + `wait_for_workload_api.sh`) to cover the
gap between Secret existence (KCP cert generation) and actual
apiserver /livez serving. Step 17 moves the "I'm fully ready"
contract to the correct owner — the chart's post-install hook —
and the module reduces to pure TF-only orchestration:

* the `scripts/` directory removed entirely (3 files); the
  `helm_test` driver inline'd as a heredoc into the
  `provisioner "local-exec"` of both helm-test null_resource's;
* `null_resource.wait_for_kubeconfig_secret` and
  `null_resource.wait_for_workload_api` removed — the chart's hook
  blocks helm install via 4 gates (LB materialised → Secret
  emitted → LB Running + proxy attached → apiserver /livez
  reachable). After `helm install --wait` returns, the workload API
  is ready out of the box;
* variables `wait_for_kubeconfig_secret_timeout_seconds` and
  `wait_for_workload_api_timeout_seconds` removed;
* `helm_release.capi_workload_cluster.timeout = 1500` (25 min) gives
  the hook a generous budget for cold-cache CAPN provisioning.

The module is now **completely free of `.sh` files** — all 6 files
are `*.tf` plus one `.terraform.lock.hcl`. Memory rule
`feedback_chart_required_values_hardcoded` honored: the chart owns
its full-readiness contract.

The only TF module in the project. A single `terraform apply` brings
up a fully functional workload cluster: ClusterClass + Cluster CR +
CNI + MetalLB + acceptance helm tests. The module is self-contained
— each invocation installs its own independent ClusterClass
(per-workload), and several workloads with different configs/versions
can coexist on a single mgmt cluster without cross-coupling.

The module has **two provider scopes** — mgmt (CAPI controllers
cluster) and workload (the just-created workload cluster). Helm
providers are configured as aliased instances; vassalage shape from
§16.1.

### Inputs

The module does not accept substrate-required CR fields (they are
hardcoded in the §16.2 / §16.3 / §17 charts). Only tunables come in
here:

* **Mgmt-side connection**:
  * `mgmt_kubeconfig_path` (string, required) — path to the single
    runner-side mgmt kubeconfig (`.artifacts/mgmt.kubeconfig`). The
    same file pre- and post-pivot — `pivot_clusterctl_move`
    overwrites it in place after `clusterctl move` (§3.1 / §18). The
    module knows nothing about pivot — it just reads the file by
    path;

* **Cluster identity + sizing**:
  * `cluster_name` (string, required) — binds to §8
    `k8s_lab_workload_cluster_name`;
  * `cluster_namespace` (string, default `capi-clusters`) — must be
    present as one of the values of §8
    `k8s_lab_capn_identity_namespaces` (CAPN reads the identity
    Secret from the Cluster CR namespace, §13.11);
  * `kubernetes_version` (string, required) — §8
    `k8s_lab_kubernetes_version`. Pinned to CAPN simplestreams set
    (§8a Constraint Step 11);
  * `controlplane_count`, `worker_count` (int) — §8
    `k8s_lab_workload_controlplane_count` / `_worker_count`;

* **Per-workload ClusterClass identity**:
  * `cluster_class_chart_version` — `helm_release.version` for
    `charts/capi-cluster-class/`. Tracks §8
    `k8s_lab_capi_cluster_class_chart_version`;
  * `cluster_class_namespace` (string, default `capi-clusters`) —
    same-namespace as the Cluster CR; the per-workload ClusterClass
    lives next to the Cluster CR, not in shared `capi-system`. This
    allows several concurrent workloads with different configs;
  * `class_prefix` (string, default `capn-default`) — binds to the
    chart's `clusterClass.name` values; the module composes the
    final name as `"{class_prefix}-{cluster_name}-{slug-of-version}"`,
    guaranteeing per-workload uniqueness;

* **CAPI cluster networking** (consumed by §16.2 + §16.3 charts):
  * `pod_cidrs` (list(string), 2 elements) — §8
    `k8s_lab_workload_pod_cidr_v4` + `_v6`;
  * `service_cidrs` (list(string), 2 elements) — §8
    `k8s_lab_workload_service_cidr_v4` + `_v6`;

* **Substrate template extras** (passthrough to the §16.2 chart):
  * `infrastructure_secret_name` — §8;
  * `image_controlplane_ref` + `image_controlplane_fingerprint`,
    `image_worker_ref` + `image_worker_fingerprint`;
  * `load_balancer` (map; default `{lxc = {}}`);
  * `controlplane_profiles_extra` / `worker_profiles_extra`;
  * `controlplane_devices_extra` / `worker_devices_extra`;
  * `control_plane_tuning` / `worker_tuning` (objects with
    `feature_gates`, `*_extra_args`, `pre_kubeadm_commands`,
    `post_kubeadm_commands`);
  * `kube_proxy_node_port_addresses`;

* **Add-ons chart versions**:
  * `cni_calico_chart_version` — `helm_release.version` for
    `charts/cni-calico/`. Tracks chart Chart.yaml version;
  * `metallb_chart_version` — `helm_release.version` for
    `charts/metallb/` (subchart wrapper). Tracks chart Chart.yaml
    version (separate from §8 `k8s_lab_metallb_chart_version` which
    pins the upstream subchart inside the Chart.yaml dependency);
  * `metallb_config_chart_version` — `helm_release.version` for
    `charts/metallb-config/`;

* **MetalLB pool / advertisement** (consumed by §17.3 metallb-config
  chart):
  * `metallb_vip_range_v6` — §8 `k8s_lab_metallb_vip_range_v6`;
  * `metallb_interface` (string, default `eth1`) — §8
    `k8s_lab_metallb_interface`;
  * `metallb_extra_node_selectors` (map(string), default `{}`) —
    stacked on top of the substrate-required CP exclusion (§17.3
    chart).

* **Workload kubeconfig endpoint rewrite**:
  * `lxd_host_address` (string, required) — runner-reachable
    address of the LXD host (for local Vagrant — the Vagrant VM IP,
    for prod — the public IP / DNS name of the LXD host). Used for
    kubeconfig server URL rewrite (see §16.7).
  * The module **does not write the kubeconfig to a file**. The
    workload kubeconfig lives in the TF state (sensitive); it
    configures the workload helm provider inline; it is exported
    through `output "kubeconfig" { sensitive = true }`. If the
    consumer wants a file — it is a consumer-side concern:
    `terraform output -raw kubeconfig > path.kubeconfig` or a
    wrapper Makefile target. Details — §16.7 + the architectural
    fence below.

### Internals (helm_release chain)

All 5 releases use `wait = true`, `atomic = true`,
`force_update = false`:

1. `helm_release.capi_cluster_class` — provider mgmt. Installs
   `charts/capi-cluster-class/` into `var.cluster_class_namespace`;
   the chart renders ClusterClass + 5 Templates with per-workload
   names (see `class_prefix` rendering above);
2. `helm_release.capi_workload_cluster` — provider mgmt. Installs
   `charts/capi-workload-cluster/` into `var.cluster_namespace`.
   `depends_on = [helm_release.capi_cluster_class]`;
3. **Wait for workload kubeconfig Secret** — Step 17 update: a black
   box inside the `helm_release.capi_workload_cluster` hook. The
   chart's post-install Job blocks helm install completion until
   the Secret `<cluster_name>-kubeconfig` is materialised + LB
   Running + apiserver /livez serving. Therefore
   `data.kubernetes_resource` with `depends_on =
   helm_release.capi_workload_cluster` is guaranteed to read the
   Secret immediately after helm Creation complete — a separate
   `null_resource` polling shim is not required;
4. **Decode + rewrite kubeconfig**: `data.kubernetes_resource`
   (after wait) reads the Secret. `local.workload_kubeconfig_raw =
   base64decode(...)`. `local.workload_kubeconfig` — a rewritten
   copy with the server URL replaced by
   `https://<lxd_host_address>:<api_proxy_port>` (the port is read
   from the Cluster CR's
   `metadata.annotations["k8s-lab.io/api-proxy-port"]`) + inject
   `tls-server-name: kubernetes.default.svc`. **Not written to
   filesystem** — no `local_file` resources;
5. `provider "helm"` aliased on workload — configured via
   `kubernetes { host=… cluster_ca_certificate=… client_certificate=…
   client_key=… tls_server_name="kubernetes.default.svc" }` —
   individual fields from the parsed kubeconfig (Step 16: the helm
   provider 3.x does not have a `kubernetes.config` inline-content
   field, only `config_path`; parsing yamldecode + base64decode
   into `local.workload_helm_kubernetes` keeps the module
   hermetic). The workload kubeconfig lives only in TF state
   (sensitive=true).
   **Step 17 update**: chart 0.8.0 post-install hook itself blocks
   step (2) until full readiness (LB + Secret + Running + /livez),
   so steps (3)+(4) data sources are guaranteed to succeed without
   separate wait null_resource's;
6. `helm_release.cni_calico` — provider workload. Installs
   `charts/cni-calico/` into namespace `tigera-operator` (the chart
   owns the namespace). `depends_on` on (4);
7. `null_resource.helm_test_cni_calico` — `local-exec` invokes
   `helm test cni-calico --kubeconfig <tmpfile> --namespace
   tigera-operator --timeout 15m --logs`. Failure → TF apply fails
   with a clear output (`triggers` includes chart version + release
   ID, so a repeat apply re-runs the test on upgrade);
8. `helm_release.metallb` — provider workload. Installs
   `charts/metallb/` (a subchart wrapper over upstream) into
   `metallb-system`. `depends_on = [null_resource.helm_test_cni_calico]`
   — CNI green → MetalLB can be installed;
9. `helm_release.metallb_config` — provider workload. Installs
   `charts/metallb-config/` into `metallb-system`. `depends_on =
   [helm_release.metallb]` — split rationale §17.3 (CRDs first,
   CRs second);
10. `null_resource.helm_test_metallb_config` — `local-exec` invokes
    `helm test metallb-config --kubeconfig <tmpfile> --namespace
    metallb-system --timeout 15m --logs`. Failure → TF apply fails.

`null_resource` for the helm tests uses a `triggers` map with
`{chart_version, release_id, kubeconfig_hash}` — re-runs the test
on a chart bump or kubeconfig rotation. Inside `local-exec` the
script writes the workload kubeconfig to a `mktemp` file, runs
helm test, cleans up the temp file in any outcome (trap EXIT).
This keeps in-cluster apply hermetic relative to runner FS state.

### Outputs

* `cluster_name`, `cluster_namespace` — echo inputs for downstream
  consumers (e.g. cleanup orchestration);
* `cluster_class_name` — the rendered final ClusterClass name (for
  introspection / debug);
* `kubeconfig` (sensitive) — workload kubeconfig content (string).
  The consumer may write it themselves via an `output` block or TF
  data pass-through `terraform output -raw kubeconfig > path`;
* `metallb_vip_range_v6` — echo of the input; may be useful for the
  consumer's downstream services;
* `helm_releases` (map(object)) — `{ capi_cluster_class,
  capi_workload_cluster, cni_calico, metallb, metallb_config }`,
  each with `id`, `name`, `namespace`, `chart_version`. Used by
  fixtures for `terraform output | jq` smoke checks.

### Multi-workload usage

Several workloads = several module invocations with different
`cluster_name`. The per-workload ClusterClass is isolated (one of
the manifestations: bumping the KubeadmControlPlaneTemplate in one
workload does not require bumping it in another). The
`cluster_class_namespace = cluster_namespace` default keeps each
workload self-contained.

### Architectural fence: TF module has zero filesystem coupling with Molecule artefacts

This is a hard contract:

* **TF module §16.4 does not write into `.artifacts/clusters/`, nor
  into any other path under `.artifacts/`.** No `local_file`
  resources, no `provisioner "local-exec"` writing files. The
  workload kubeconfig lives only in TF state (sensitive=true) and
  inline in helm provider config.
* **TF module does not read files from `.artifacts/`** (except
  `var.mgmt_kubeconfig_path` which points to the mgmt kubeconfig —
  but it is an input, not an assumption about the Molecule
  pipeline).
* **Molecule e2e-local artefacts in
  `.artifacts/clusters/<cluster>.kubeconfig`** — a debug copy of
  the workload kubeconfig (raw Secret content, internal capi-int
  IPv6 endpoint — NOT rewritten) for operator inspection. No TF /
  Ansible / Helm task consumes this file.
* **If the consumer wants the workload kubeconfig as a file** —
  it is their concern outside the module:
  * `terraform output -raw kubeconfig > path.kubeconfig` in a
    consumer-side wrapper Makefile;
  * or simply `kubectl --context=<...>` through a kubeconfig
    merger from the output stream.

This fence guarantees:
* TF apply is reproducible with zero state on the runner (no
  pre-existing files except `mgmt_kubeconfig_path`);
* Molecule harness and TF flow remain independent — each owns its
  own debug artefacts;
* Multiple TF workspaces / multiple Molecule scenarios can coexist
  without stomping on each other.

### CAPI invariants the module enforces

* `controlplane_count` validation: must be odd (the CAPI KCP
  webhook rejects even replicas under stacked etcd). The module
  validates via a `validation` block: `controlplane_count % 2 == 1`;
* `pod_cidrs` / `service_cidrs` length: exactly 2 elements
  (dual-stack invariant §8). Validation block;
* `kubernetes_version` ∈ supported set (CAPN simplestreams); the
  pinned default §8 is actual; the module does not validate this
  set at runtime — it is the consumer's responsibility via the §8
  default.

## 16.5. Test fixture: `tests/fixtures/terraform/workload-clusters/lab-default/`

**Status: done in Step 16 (2026-04-28) — fixture root + Makefile
targets `deploy-workload` / `workload-kubeconfig` / `destroy-workload`
work end-to-end from the repo root. Files: `providers.tf` (only
`required_providers` without provider configs — the module owns
aliases), `variables.tf` (defaults match the §8 reference deployment
+ 7 unused declared vars to silently consume mgmt-side keys from
auto-tfvars), `main.tf` (derives `lxd_host_address` from
`k8s_lab_mgmt_api_server_url` host component via regex with two
capture groups + `coalesce` — supports both `[ipv6]:port` and
`host:port` forms), `outputs.tf` (passthrough of all module
outputs).**

**Step 16 deviation from the original §16.5 design:
`.artifacts/mgmt.auto.tfvars.json` is **not auto-loaded** by Terraform
from the fixture's cwd.** TF auto-loads `*.auto.tfvars.json` only from
its working directory; the repo keeps the handoff bundle at repo
root (`.artifacts/`), while the fixture cwd is
`tests/fixtures/terraform/workload-clusters/lab-default/`. The Makefile
target `deploy-workload` threads the file explicitly via
`-var-file=$(REPO_ROOT)/.artifacts/mgmt.auto.tfvars.json` +
preflight check that the file exists. The alternative path — a
committed symlink in the fixture — was rejected as hidden filesystem
coupling.

The only TF root of this repo. Invokes module `workload_cluster/`
with default §8 values for the local Vagrant/libvirt loop.

Shape:

```
tests/fixtures/terraform/workload-clusters/lab-default/
  providers.tf
  variables.tf
  main.tf
  outputs.tf
```

### providers.tf

```hcl
terraform {
  required_version = ">= 1.9"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"            # §8 k8s_lab_helm_provider_version
    }
    kubernetes = {                   # read-only: data lookups, status poll
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
```

The provider configurations themselves are defined by the module
inside (mgmt + workload aliases), the fixture does not override
them.

### variables.tf

Accepts `k8s_lab_*` keys from §8. `.artifacts/mgmt.auto.tfvars.json`
(emitted by `export_artifacts` §13.12) is threaded via
`-var-file=...` (see Step 16 deviation above) and fills them in
without manual tfvars. On top of §8 the fixture adds:

* `mgmt_kubeconfig_path` (default `${path.module}/../../../../../.artifacts/mgmt.kubeconfig`)
  — the single runner-side mgmt kubeconfig path. The same file pre-
  and post-pivot — `pivot_clusterctl_move` overwrites it in place
  after `clusterctl move` (§3.1 / §18). The fixture default just
  tracks the reference layout of the `export_artifacts` role;
* `cluster_class_chart_version` (default tracks §8
  `k8s_lab_capi_cluster_class_chart_version`);
* `cluster_workload_chart_version` (default tracks §8
  `k8s_lab_capi_workload_cluster_chart_version`). A bump of this
  variable must coincide with `capi-workload-cluster/Chart.yaml`
  `annotations["k8s-lab.io/capi-cluster-class-chart-version"]` — a
  coupling check inside the chart through the `Chart.Annotations`
  helper;
* `cni_calico_chart_version` (default = `charts/cni-calico/Chart.yaml`
  version);
* `metallb_chart_version` (default = `charts/metallb/Chart.yaml`
  version);
* `metallb_config_chart_version` (default = `charts/metallb-config/Chart.yaml`
  version).

### main.tf

```hcl
module "workload_cluster" {
  source = "../../../../../terraform/modules/workload_cluster"

  mgmt_kubeconfig_path = var.mgmt_kubeconfig_path
  lxd_host_address     = var.k8s_lab_lxd_host_address

  cluster_name        = var.k8s_lab_workload_cluster_name
  cluster_namespace   = "capi-clusters"
  kubernetes_version  = var.k8s_lab_kubernetes_version
  controlplane_count  = var.k8s_lab_workload_controlplane_count
  worker_count        = var.k8s_lab_workload_worker_count

  cluster_class_chart_version  = var.cluster_class_chart_version
  cluster_workload_chart_version = var.cluster_workload_chart_version
  cni_calico_chart_version     = var.cni_calico_chart_version
  metallb_chart_version        = var.metallb_chart_version
  metallb_config_chart_version = var.metallb_config_chart_version

  pod_cidrs     = [var.k8s_lab_workload_pod_cidr_v4,
                   var.k8s_lab_workload_pod_cidr_v6]
  service_cidrs = [var.k8s_lab_workload_service_cidr_v4,
                   var.k8s_lab_workload_service_cidr_v6]

  infrastructure_secret_name     = var.k8s_lab_infrastructure_secret_name
  image_controlplane_ref         = var.k8s_lab_images_controlplane
  image_controlplane_fingerprint = var.k8s_lab_images_controlplane_fingerprint
  image_worker_ref               = var.k8s_lab_images_worker
  image_worker_fingerprint       = var.k8s_lab_images_worker_fingerprint
  controlplane_profiles_extra    = var.k8s_lab_controlplane_profiles_extra
  worker_profiles_extra          = var.k8s_lab_worker_profiles_extra
  controlplane_devices_extra     = var.k8s_lab_controlplane_devices_extra
  worker_devices_extra           = var.k8s_lab_worker_devices_extra
  kube_proxy_node_port_addresses = var.k8s_lab_kube_proxy_nodeport_addresses

  metallb_vip_range_v6 = var.k8s_lab_metallb_vip_range_v6
  metallb_interface    = var.k8s_lab_metallb_interface
}
```

### outputs.tf

* `cluster_name`, `cluster_namespace` — passthrough (for cleanup
  orchestration §19.2);
* `cluster_class_name` — passthrough;
* `kubeconfig` (sensitive) — the rewritten workload kubeconfig
  content as a string. If the consumer needs a file —
  `terraform output -raw kubeconfig > path.kubeconfig` through a
  consumer-side wrapper Makefile target. The module does not write
  the file itself (see §16.4 architectural fence);
* `api_proxy_port` — passthrough of the Cluster annotation
  `k8s-lab.io/api-proxy-port` for downstream consumers
  (e.g., kubectl wrappers with `--server` override);
* `helm_releases` — passthrough (smoke-check fixture).

## 16.6. Apply workload cluster

Orchestration — `make deploy-workload` (target in the root
`Makefile`):

```makefile
deploy-workload:
	cd tests/fixtures/terraform/workload-clusters/lab-default \
	  && terraform init -upgrade \
	  && terraform apply -auto-approve
```

Contract:

* `terraform` is assumed **already installed** on the runner (dev
  machine or CI agent); Ansible/Phase 4 do not install it;
* the operator / agent invokes the target manually after Phase 4
  is green and `.artifacts/mgmt.kubeconfig` +
  `.artifacts/mgmt.auto.tfvars.json` are materialised;
* the `helm` CLI is needed on the runner for the helm tests inside
  the module (`null_resource` + `local-exec`); the version is
  pinned compatible with chart-providers (Helm 3.20+);
* the first apply brings up the workload cluster from scratch
  (CAPI provisioning + LXC instances + kubeadm init/join + CNI +
  MetalLB + helm tests); typically 8-12 minutes on cold cache;
* a repeat apply is a no-op (idempotent helm_releases; helm tests
  re-run because `null_resource.triggers` includes chart version,
  but they are fast if the cluster is already green).

Acceptance:

1. `helm_release.capi_cluster_class` applied: ClusterClass + all 5
   *Templates exist in `<cluster_namespace>` with names
   `{class_prefix}-{cluster_name}-{chart-version-slug}`; webhook
   validated.
2. `helm_release.capi_workload_cluster` applied: Cluster CR in
   `capi-clusters/<cluster_name>` with `spec.topology.classRef.name`
   pointing to the right per-workload ClusterClass.
3. CAPI kubeadm-CP + CAPN controllers picked up the Cluster CR,
   created LXCCluster + LXCMachine's, kubeadm init/join passed,
   workload kubeconfig Secret `<cluster_name>-kubeconfig` appeared
   in `<cluster_namespace>`.
4. `helm_release.cni_calico` applied: tigera-operator + calico-node
   DaemonSet rolled out, all workload Nodes Ready.
5. **Gate B green** (`null_resource.helm_test_cni_calico`) —
   chart-side acceptance (see §17.2): tigera-operator Available,
   calico-system Pods Ready, dual-stack `podCIDRs` per-Node, ICMP4/
   ICMP6 pod-to-pod via kubectl exec.
6. `helm_release.metallb` + `helm_release.metallb_config` applied:
   metallb controller + speaker DS rolled out, IPAddressPool +
   L2Advertisement reconciled.
7. **Gate A green** (`null_resource.helm_test_metallb_config`) —
   chart-side acceptance (see §17.3): a demo Service received a VIP
   from the pool, an in-cluster HTTP probe from the driver Pod to
   the VIP returns 200.
8. `terraform output -raw kubeconfig` returns a working workload
   kubeconfig (as a string) with rewritten server URL
   (`https://<lxd_host_address>:<api_proxy_port>` + injected
   `tls-server-name`). The module **does not write the kubeconfig
   to a file** — this is a consumer-side concern (see §16.4
   architectural fence).
9. Acceptance smoke: `kubectl --kubeconfig <(terraform output -raw
   kubeconfig) get nodes` from the runner returns all workload
   nodes Ready. This is a runner-side verification that the LXD
   proxy device + TLS chain work end-to-end (without an in-cluster
   jump pod, as it was in pre-Step-15 Molecule e2e-local).

Failure of any acceptance criterion → TF apply fails; the state is
marked tainted; a repeat apply re-runs only the failed resources
(helm_release upgrade-no-op for green ones).

Acceptance status history split — Step 11/12 refer to the original
acceptance criteria (1)-(4) which grew into (1)-(8) in Step 13/14
as CNI and MetalLB charts were added. Step 13/14 evidence is
chart-side green via Molecule e2e-local; the TF module wrapper had
not yet been implemented, the implementation is Step 15+.

### Acceptance status (Step 11, 2026-04-26)

(1) and (2) **green** — `helm install` of both charts applied
cleanly, ClusterClass `capn-default-0-3-0` + 5 *Templates in
`capi-system`, Cluster CR in `capi-clusters/lab-default` with
`spec.topology.classRef.name=capn-default-0-3-0` and
`classRef.namespace=capi-system` (cross-ns reference).
`TopologyReconciled=True (ReconcileSucceeded)` on the first apply.

(3) **partially green**: CAPI/CAPN controllers picked up the
Cluster CR, created `LXCCluster` + the first `LXCMachine` (CP) +
`MachineDeployment` with 2 worker `Machine`s; the haproxy LB LXC
instance came up; the CP LXC instance started, kubeadm preflight
passed (after the §13.6 host-boot device fix), certs were
generated, static pods (etcd, kube-apiserver,
kube-controller-manager, kube-scheduler) came up healthy inside CP.
**kubeadm init did not exit fully** — phase
`upload-config/kubeadm` fails creating the admin ClusterRoleBinding
with `client rate limiter Wait returned an error: context deadline
exceeded`. Root cause:

* `kube-apiserver` listens `*:6443` (IPv4 wildcard, kubeadm default
  `--bind-address=0.0.0.0`);
* `Cluster.spec.controlPlaneEndpoint` (CAPN auto-derived from
  LXCCluster status) and `admin.conf.clusters[].cluster.server`
  point to the IPv6 endpoint of the CP node/LB (capi-int dual-stack
  picks IPv6);
* family mismatch → connection refused → kubeadm does not reach
  bootstrap-token / admin RBAC creation.

(4) **not green** — Cluster.status.phase hangs on `Provisioning`,
`AVAILABLE=False`, `nodeRef` not populated, no workload kubeconfig
Secret for subsequent phases.

**Open issue scope Step 12+:** dual-stack kubeadm 1.35.x +
CAPI/CAPN haproxy LB endpoint family selection. A deep research
into reference dual-stack patterns is planned:

* `clusterConfiguration.apiServer.extraArgs.bind-address: "::"`
  hardcoded in the KCPT (along with possible
  `controllerManager.extraArgs.bind-address` / `scheduler.extraArgs.
  bind-address` for healthz endpoints);
* CAPN `loadBalancer.lxc` haproxy.cfg dual-stack frontend (need to
  check whether CAPN ships a default config bind on both families
  or only one);
* `Cluster.spec.controlPlaneEndpoint` family-priority control
  (CAPN auto-derive vs explicit override);
* possibly — kube-vip / external LB instead of CAPN's lxc haproxy
  for cleaner dual-stack semantics.

The Step 11 substrate fixes (see §13.x Step 11 entries) are needed
independently of the dual-stack solution and carry over into Step
12 as-is.

### Acceptance status (Step 12, 2026-04-26)

All four acceptance criteria **green**. Step 12 — close-out of the
dual-stack research block above.

(1) and (2) — unchanged in essence, but with bumped chart versions
0.3.0 → 0.4.2 (see §16.2 / §16.3 status headers): ClusterClass
`capn-default-0-4-2` + 5 *Templates in `capi-system`, Cluster CR
in `capi-clusters/lab-default` with `spec.topology.classRef.name=
capn-default-0-4-2`, `TopologyReconciled=True`.

(3) **green** — kubeadm init on CP completes, the admin
ClusterRoleBinding is created, kubeadm join on 2 CP + 2 worker
LXC instances completes. The implemented fixes (chart-side, see
§16.2 Step 12 explanation):

* `KubeadmControlPlaneTemplate.clusterConfiguration.apiServer.
  extraArgs.bind-address: "::"` hardcoded — kube-apiserver listens
  on both families;
* `LXCClusterTemplate.spec.template.spec.loadBalancer.lxc.
  customHAProxyConfigTemplate` is baked in as a dual-bind v4+v6
  frontend template (the CAPN v0.8.x default haproxy.cfg binds only
  on v4);
* `controllerManager.extraArgs.allocate-node-cidrs: "true"`
  hardcoded in the KCPT (without it, kube-controller-manager does
  not hand out podCIDRs to Node objects, dual-stack or otherwise);
* the ClusterClass `patches` block propagates
  `Cluster.spec.clusterNetwork.{pods,services}` from the Cluster CR
  into kubeadm `apiServer.extraArgs.service-cluster-ip-range` +
  `controllerManager.extraArgs.{cluster-cidr,service-cluster-ip-
  range}` (using CAPI v1beta2 `valueFrom.template`);
* `kubeletExtraArgs.provider-id: lxc:///{{ v1.local_hostname }}`
  hardcoded in both kubeadm templates + dynamic dual-stack
  `node-ip` through substrate `preKubeadmCommands` (LXD DHCP/SLAAC
  hands out addresses dynamically — cannot be hardcoded
  statically);

The CAPI auto-derived `Cluster.spec.controlPlaneEndpoint` remains
single-family (IPv6 in this substrate) — and that's fine, because
both node sides (apiserver listener + LB frontend) now bind on
both families and accept `admin.conf.clusters[].cluster.server` of
any family.

(4) **green** — Cluster.status.phase = Provisioned (on a
CNI-less cluster it cannot reach Ready without CNI; that's by
design — CNI is delivered as a separate Helm release — §17.1),
`helm test` (the 10-phase dual-stack acceptance driver from §16.3)
passes to the end: `cp=3/3 worker=2/2 ALL TOPOLOGY CHECKS
PASSED`. Acceptance evidence: `make -C tests/molecule
e2e-local-vagrant-converge` → `failed=0`, `make -C tests/molecule
e2e-local-vagrant-verify` → `failed=0`. The full path — the
`e2e_local` Molecule scenario (§9.4 Full E2E + §10.2 driver) — is
implemented in the same Step (see PLAN-stage1-1.md Step 12 prose).

The Step 12 substrate-side fix is paired (see §13.6 lxd_profiles):
the capi-worker LXD profile received a `host-boot` read-only
`/boot` mount — `kubeadm join` preflight `SystemVerification` fails
without it for the same reason that Step 11 already solved for
capi-controlplane (`/proc/config.gz` does not physically exist on
Debian 13 kernel — `CONFIG_IKCONFIG=n`).

### Acceptance status (Step 16, 2026-04-28)

All 9 acceptance criteria from §16.6 above **green** on the live
Vagrant substrate (LXD host = 192.168.121.95, initialised through
the Step 15 chain). End-to-end run: `make deploy-workload` → `Apply
complete! Resources: 6 added, 0 changed, 0 destroyed` in ~9 min.

(1)-(2) ✓ — `helm_release.capi_cluster_class` installs
`capn-default-0-6-3` ClusterClass + 5 *Templates in `capi-clusters`
namespace (cluster_class_namespace defaults to cluster_namespace —
per-workload self-contained, no cross-ns reference). The Cluster CR
`lab-default` in the same namespace, `spec.topology.classRef.name=
capn-default-0-6-3`, `TopologyReconciled=True (ReconcileSucceeded)`.

(3)-(4) ✓ — CAPN provisions 3 CP + 2 worker LXC instances + LB
instance `lab-default-j8hvk-deb12-lb` in ~5 min; kubeadm init/join
pass on all of them; KCP `r=3 u=3 r=3`; workload kubeconfig Secret
`lab-default-kubeconfig` materialises in `capi-clusters`. CNI
Calico installation (the same `helm_release.cni_calico` through
workload-aliased helm provider) — all 5 Nodes Ready=True (3 CP +
2 worker), calico-node DS 5/5 ready, calico-typha 3 replicas,
calico-apiserver + calico-kube-controllers up.

(5) ✓ Gate B — `null_resource.helm_test_cni_calico` green in
1m43s; chart-side hook (§17.2) confirms tigera-operator
Available, calico-system Pods Ready, dual-stack `podCIDRs`
per-Node, ICMP4/ICMP6 pod-to-pod across the two workers.

(6)-(7) ✓ Gate A — `helm_release.metallb` (subchart wrapper) +
`helm_release.metallb_config` both deployed. metallb controller +
5 speaker DS replicas Running. IPAddressPool `metallb-config-v6`
with range `2001:db8:42:100::200-2001:db8:42:100::2ff` reconciled.
L2Advertisement `metallb-config-v6` points at eth1.
`null_resource.helm_test_metallb_config` green in 19s; chart-side
hook (§17.3) brings up the demo Service `k8s-lab-metallb-demo`
(nginx backend) — controller allocates VIP
`2001:db8:42:100::200` from the pool; in-cluster HTTP probe
returns 200.

(8) ✓ — `terraform output -raw kubeconfig` emits the rewritten
kubeconfig: `server: https://192.168.121.95:26818` (lxd_host_address
+ Adler-32-derived port from Cluster annotation
`k8s-lab.io/api-proxy-port`), `tls-server-name: kubernetes.default.svc`
(injected, decouples TLS identity from the runner-reachable URL),
full CA + client cert/key from the Secret. The module writes
nothing to FS — the output stays sensitive in TF state.

(9) ✓ Acceptance smoke — after `make workload-kubeconfig`
(materialise `terraform output -raw kubeconfig` into
`.artifacts/clusters/lab-default.kubeconfig` through a
consumer-side wrapper, umask 077), `kubectl --kubeconfig <path>
get nodes -o wide` from the runner returns all 5 workload Nodes
Ready on v1.35.0, ContainerRuntime containerd 2.2.0. This proves
that the LXD proxy device (Helm hook on chart) + haproxy LB → CP
backends + apiserver TLS chain work end-to-end from an external
runner.

**Step 16 secondary deviation for consumer ergonomics**: an
attempt at `kubectl --kubeconfig <(terraform output -raw
kubeconfig)` through process substitution **does not work** —
kubectl does a `seek()` on the kubeconfig file to refresh
credentials, the FIFO from `<(...)` does not support seek and
API errors out on `localhost:8080` (defaults). The module fence
(§16.4 architectural fence) is preserved: TF does not write the
file; for consumer convenience the Makefile target
`workload-kubeconfig` materialises the output into
`.artifacts/clusters/<cluster>.kubeconfig` with `umask 077`. The
subdir is already pre-created by the Phase 4 `export_artifacts`
(§15.6).

Step 16 did NOT require substrate-side fixes — the chart-side and
role-side contracts of Step 11/12/13/15 cover the provisioning
chain in full; the TF module is a declarative orchestrator on top
of ready components without "own" CRs or manifests (memory rule
`feedback_helm_first_no_raw_manifests` honored: zero
`kubernetes_manifest`, zero `kubectl apply -f`, all CRs through
`helm_release`).

## 16.7. Workload kubeconfig pipeline (in-state) + API endpoint rewrite

The workload kubeconfig pipeline is an **internal step of the §16.4
module**, not a separate Phase, **never written to a file**. The
module:

1. waits for Secret `<cluster_name>-kubeconfig` in
   `<cluster_namespace>` via `null_resource` + `kubectl get secret
   -w --timeout=20m` (mgmt kubeconfig);
2. reads the Secret via `data.kubernetes_resource` (server-side,
   native TF), decodes `data.value` (base64) into a local;
3. reads the Cluster CR's annotation
   `k8s-lab.io/api-proxy-port` (which `charts/capi-workload-cluster/`
   writes — see §16.3 Step 15) — this is the computed Adler-32 hash
   port on the LXD haproxy LB instance;
4. **rewrites the kubeconfig server URL** in the local: replace
   `server: https://[<internal-v6>]:6443` →
   `server: https://<lxd_host_address>:<api-proxy-port>`. Also
   injects `tls-server-name: kubernetes.default.svc` into every
   `clusters[].cluster` if not already set, to avoid an x509 SAN
   mismatch (the workload kubeadm SANs do not know about the
   rewritten host);
5. configures the workload-aliased helm provider inline through
   `kubernetes { config = local.workload_kubeconfig_rewritten }`;
6. emits via `output "kubeconfig" { sensitive = true }` a
   sensitive string. No `local_file` resources.

The rewritten kubeconfig is visible to the consumer **only through
TF output**:

```bash
terraform output -raw kubeconfig > /path/to/kubeconfig
```

This is a consumer-side concern. For local-harness the operator
can wrap it in a Makefile target (`make workload-kubeconfig`); for
CI — a pipeline step after `terraform apply`. The module makes no
assumption about where / whether to write at all.

API endpoint reachability path — production-mirror:

* Inside cluster: workload pods → workload kube-apiserver via
  CAPN-managed haproxy LB → CP backends. The CAPN haproxy LB binds
  on capi-int IPv6 (`fd42:77:1::/64`); this is substrate-managed,
  not our scope;
* Outside cluster (runner / consumer's TF apply / kubectl): traffic
  → `<lxd_host_address>:<api-proxy-port>` → LXD `proxy` device on
  the LB instance (`bind=host` listener) → 127.0.0.1:6443 inside
  the LB instance → haproxy → CP backends.

LXD `proxy` device delivery — **owned by `charts/capi-workload-cluster/`
through Helm hook Jobs**, not by Terraform / Molecule:

* `post-install,post-upgrade` Job
  (`templates/api-proxy-attach-job.yaml`) waits for CAPN to
  materialise the haproxy LB LXC instance and then `PATCH`-es
  `/1.0/instances/<lb>?project=<p>` over the LXD HTTPS REST API to
  add the `api-proxy` device. PATCH semantics merge top-level
  `devices` so the LB's pre-existing devices (root disk, NICs)
  stay untouched.
* `pre-delete` Job (`templates/api-proxy-detach-job.yaml`) is the
  symmetric inverse on `helm uninstall <workload>`: `PATCH` with
  `{"devices":{"api-proxy":null}}` removes the key. Best-effort
  (`exit 0` if LB instance has already been torn down by CAPN).
* Image: `alpine:3.21` + `apk add curl jq` at runtime — no incus/
  lxc CLI binary, no vendored client tooling. Driven by the same
  `incus-identity` Secret that CAPN consumes (`server`,
  `client-crt`, `client-key`, `server-crt`, `project` fields per
  CAPN docs); Job mounts it read-only.
* `helm install --wait` blocks on hook Job completion by default,
  so by the time the helm release is reported success the LB
  instance is provisioned AND the proxy device is wired — no race
  window where downstream chart installs see a half-ready cluster.

**Why a Helm hook rather than a ClusterClass topology patch:** CAPN
v1alpha2 declares `LXCCluster.spec.template.spec.loadBalancer.lxc
.instanceSpec` as a closed CRD schema (only `profiles/image/flavor/
target` — no `devices` field). A JSON patch through the
ClusterClass topology API to add the `devices` block fails at
admission with `field not declared in schema`. The proxy device
must therefore be attached post-CAPI on the live LB instance; a
Helm hook Job in the workload chart is the only declarative path
that keeps the device attach inside chart-owned lifecycle.

Several workload clusters on the same LXD host receive **different
ports** via an Adler-32 hash from the cluster name → they do not
conflict. Collision rate on 10 workloads <1%; conflict resolution
via the `loadBalancer.lxc.proxyApiPort` override in the values of
chart `charts/capi-workload-cluster/`.

### Co-existence with the Molecule e2e-local kubeconfig pipeline

The Molecule e2e-local converge.yml + verify.yml owns its own
kubeconfig pipeline — **independent of the TF module pipeline**.
It reuses the same chart artefacts (Cluster CR annotation
`k8s-lab.io/api-proxy-port` + post-install hook attach Job which
wires the LXD `proxy` device on the LB instance) and does the
rewrite via an Ansible-native pipeline:

1. `kubernetes.core.helm` installs `capi-workload-cluster` chart;
   `helm install --wait` blocks until the chart's post-install
   hook Job completes the LXD `proxy` device attach — at that point
   runner-reachability for `<host>:<port>` is already ready;
2. `kubernetes.core.k8s_info` reads the Cluster CR's annotation +
   workload kubeconfig Secret (through the bootstrap kubeconfig);
3. Ansible-side rewrite via `regex_replace` — replaces
   `server: https://...:6443` with
   `https://<K8SLAB_HOST_ADDR>:<api-proxy-port>` + injects
   `tls-server-name: kubernetes.default.svc`;
4. `ansible.builtin.copy` writes the result into
   `.artifacts/clusters/<cluster>.kubeconfig`. This file is the
   single kubeconfig through which Molecule converge.yml installs
   cluster add-ons (cni-calico, metallb, metallb-config) with the
   runner-side `kubernetes.core.helm` (`delegate_to: localhost`);
5. Runner-side acceptance test via `kubernetes.core.k8s_info
   kind=Node` against the rewritten kubeconfig — asserts all
   workload Nodes Ready=True.

This file and the TF module's `terraform output -raw kubeconfig`
are **two independent artefacts** living in parallel:
* the Molecule artefact = debug + runner-side acceptance test,
  rewritten endpoint, written by the Ansible Verify pipeline;
* TF output = production-path delivery, rewritten endpoint, in TF
  state only.

**The TF module neither reads nor writes into `.artifacts/clusters/`**
(see §16.4 architectural fence). Each flow owns its own pipeline
for the kubeconfig endpoint rewrite — Ansible regex_replace in
Molecule, TF locals in the module. No shared filesystem coupling.

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
