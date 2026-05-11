# 10 — Modules and charts

This chapter is a per-component reference for the **single Terraform
module** and the **five Helm charts** that own every Kubernetes object
in the project. Operators read this when they need to know what each
component delivers, what overrides exist, and how the pieces wire
together.

The Terraform module is the single delivery driver for Phase 5+: in
**one `terraform apply`** it installs all five charts in dependency
order and runs the chart-side **Gate A** and **Gate B** helm tests via
`null_resource` + `local-exec helm test`. A red gate fails the apply,
taints the state, and the next apply retries from the failed step.

| Component | Path | Type |
|-----------|------|------|
| `workload_cluster` | `terraform/modules/workload_cluster/` | Terraform module |
| `capi-cluster-class` | `charts/capi-cluster-class/` | Helm chart |
| `capi-workload-cluster` | `charts/capi-workload-cluster/` | Helm chart |
| `cni-calico` | `charts/cni-calico/` | Helm wrapper chart |
| `metallb` | `charts/metallb/` | Helm wrapper chart |
| `metallb-config` | `charts/metallb-config/` | Helm chart |

The plans say *why*. This chapter says *how*. The code under
`terraform/modules/` and `charts/` says *what*.

---

## Terraform module: `workload_cluster`

- **Path**: `terraform/modules/workload_cluster/`
- **Files**: `main.tf`, `variables.tf`, `outputs.tf`, `locals.tf`,
  `providers.tf`, `versions.tf`.
- **Plan reference**: `§16.1` … `§16.7` of `PLAN-stage1-3.md`.

### Purpose

In one `terraform apply`, install the full workload stack — the
**ClusterClass**, the **Cluster CR**, the **CNI** (Calico), **MetalLB**
(controller + speaker), the **MetalLB CRs** (`IPAddressPool`,
`L2Advertisement`), and the **Gate A / Gate B chart-side helm tests** —
on an already-self-hosted mgmt cluster.

This module is **not** part of the bootstrap → pivot path; the
canonical e2e flow installs the same charts directly on the bootstrap
k3s and then on mgmt-1 via `kubernetes.core.helm` calls in the e2e
playbook. The module owns the **post-pivot workload deployment** loop:
`make deploy-workload` and any consumer-repo `terraform apply` that
brings up additional workloads on a self-hosted mgmt-1.

### What is inside (the dependency chain)

The graph below is the entirety of `main.tf`:

```
1. helm_release.capi_cluster_class
       │
       ▼
2. helm_release.capi_workload_cluster   (depends_on 1)
       │  ├ chart-side post-install hook waits for:
       │  │   - LB instance materialised in LXD
       │  │   - kubeconfig Secret emitted by KCP
       │  │   - LB Running + proxy device attached
       │  │   - apiserver /livez=200/401/403
       │  └ helm_release returns "Creation complete"
       │    only after the workload cluster is fully ready
       ▼
3. data.kubernetes_resource.workload_cluster_cr     (depends_on 2)
4. data.kubernetes_resource.workload_kubeconfig_secret  (depends_on 2)
       │  (used to compute the rewritten workload kubeconfig — see §16.7)
       ▼
5. helm_release.cni_calico              (depends_on 4, helm.workload provider)
       │
       ▼
6. null_resource.helm_test_cni_calico   (Gate B — `helm test cni-calico`)
       │
       ▼
7. helm_release.metallb                 (depends_on 6, CRDs+controller+speaker)
       │
       ▼
8. helm_release.metallb_config          (depends_on 7, CRs only)
       │
       ▼
9. null_resource.helm_test_metallb_config  (Gate A — `helm test metallb-config`)
```

Steps 1, 2, 3, 4 run against the **mgmt-aliased** providers
(`provider = helm.mgmt`, `provider = kubernetes.mgmt`). Steps 5, 7, 8
run against the **workload-aliased** helm provider configured inline
from the parsed kubeconfig Secret. The two `null_resource` Gate
drivers shell out to the host `helm` binary with a process-private
kubeconfig file (heredoc + `mktemp -t k8slab-workload-kc.XXXXXXXXXX`,
trapped on EXIT) — workload kubeconfig material lives only in TF
state, never on disk under `.artifacts/` or `$HOME` (`§16.4`).

Step 17 of the plan moved CAPI/CAPN readiness gating **out of TF and
into the chart-side post-install hook** in `capi-workload-cluster ≥
0.8.0`. The module no longer maintains its own wait loops or shell
scripts; `wait = true` + `wait_for_jobs = true` on the
`helm_release.capi_workload_cluster` resource is sufficient (see the
header comment in `main.tf`).

### Inputs

Read from `variables.tf`. Defaults shown only when set; mandatory
inputs have no default.

| Variable | Type | Default | Notes |
|----------|------|---------|-------|
| `mgmt_kubeconfig_path` | `string` | — | Path to mgmt kubeconfig. Always `.artifacts/mgmt.kubeconfig` — same file pre- and post-pivot (`pivot_clusterctl_move` rewrites it in place). |
| `cluster_name` | `string` | — | Workload Cluster CR name. §8 `k8s_lab_workload_cluster_name`. |
| `cluster_namespace` | `string` | `capi-clusters` | Namespace for the workload Cluster CR. Must be one of §8 `k8s_lab_capn_identity_namespaces`. |
| `kubernetes_version` | `string` | — | K8s version. Validated `^v[0-9]+\.[0-9]+\.[0-9]+(\+.+)?$`. Must exist in CAPN simplestreams. |
| `controlplane_count` | `number` | — | KCP replicas. Validated as positive odd integer (CAPI stacked-etcd quorum invariant). |
| `worker_count` | `number` | — | Single-MD worker replicas. Validated > 0. |
| `cluster_class_chart_version` | `string` | — | `helm_release.version` for `charts/capi-cluster-class`. |
| `cluster_workload_chart_version` | `string` | — | `helm_release.version` for `charts/capi-workload-cluster`. Must match the chart's pinned `k8s-lab.io/capi-cluster-class-chart-version` annotation. |
| `cluster_class_namespace` | `string` | `""` | Empty → same as `cluster_namespace` (each workload self-contained). |
| `class_prefix` | `string` | `capn-default` | Logical prefix; final `ClusterClass.metadata.name = <prefix>-<chart-version-slug>`. |
| `pod_cidrs` | `list(string)` | — | `[IPv4, IPv6]`. Validated length=2. |
| `service_cidrs` | `list(string)` | — | `[IPv4, IPv6]`. Validated length=2. |
| `infrastructure_secret_name` | `string` | `incus-identity` | CAPN identity Secret. Must exist in `cluster_namespace` (provisioned by role `bootstrap_capn_secret`). |
| `image_controlplane_ref` | `string` | `capi:kubeadm/VERSION` | CAPN image ref for CP LXC (literal `VERSION` substituted at runtime). |
| `image_controlplane_fingerprint` | `string` | `""` | Optional sha256 pin. |
| `image_worker_ref` | `string` | `capi:kubeadm/VERSION` | CAPN image ref for worker LXC. |
| `image_worker_fingerprint` | `string` | `""` | Optional sha256 pin. |
| `load_balancer` | `any` | `{ lxc = {} }` | `LXCClusterTemplate.spec.template.spec.loadBalancer` — exactly one of `{lxc, oci, ovn, kubeVIP, external}`. |
| `controlplane_profiles_extra` | `list(string)` | `[]` | Consumer-supplied LXD profiles appended after the substrate baseline. |
| `worker_profiles_extra` | `list(string)` | `[]` | Same, for workers. |
| `controlplane_devices_extra` | `list(string)` | `[]` | CAPN v1alpha2 CSV device overrides for CP machines. |
| `worker_devices_extra` | `list(string)` | `[]` | Same, for workers. |
| `control_plane_tuning` | `object` | `{}` | kubeadm tuning for KCPT (`feature_gates`, `*_extra_args`, `pre/postKubeadmCommands`). Substrate-reserved args are rejected by chart-side schema. |
| `worker_tuning` | `object` | `{}` | kubeadm tuning for KubeadmConfigTemplate (worker-join side). |
| `kube_proxy_node_port_addresses` | `list(string)` | `[]` | NodePort bind CIDRs. Empty = bind all. |
| `cni_calico_chart_version` | `string` | — | `helm_release.version` for `charts/cni-calico`. |
| `metallb_chart_version` | `string` | — | `helm_release.version` for `charts/metallb`. |
| `metallb_config_chart_version` | `string` | — | `helm_release.version` for `charts/metallb-config`. |
| `metallb_vip_range_v6` | `string` | — | IPv6 VIP range (`<from>-<to>` or `<ip>/128`). §8 `k8s_lab_metallb_vip_range_v6`. |
| `metallb_interface` | `string` | `eth1` | Interface MetalLB speaker announces VIPs on. |
| `metallb_extra_node_selectors` | `map(string)` | `{}` | Extra label matchers stacked on top of the substrate-required CP-exclusion. |
| `lxd_host_address` | `string` | — | Runner-reachable LXD host address (Vagrant VM IP for local, public IP/DNS for prod). Used to rewrite the workload kubeconfig server URL. Validated non-empty. |
| `helm_test_timeout` | `string` | `15m` | Timeout passed to `helm test` for Gate A / Gate B. |

### Outputs

Read from `outputs.tf`.

| Output | Type | Sensitive | Notes |
|--------|------|-----------|-------|
| `cluster_name` | `string` | no | Echo of `var.cluster_name`. |
| `cluster_namespace` | `string` | no | Echo of `var.cluster_namespace`. |
| `cluster_class_name` | `string` | no | Rendered `ClusterClass.metadata.name` reproduced from `class_prefix` + chart-version slug. |
| `kubeconfig` | `string` | **yes** | Workload kubeconfig YAML with the server URL rewritten to `<lxd_host_address>:<api_proxy_port>` and `tls-server-name` pinned to `kubernetes.default.svc`. Module never writes it to disk. |
| `api_proxy_port` | `number` | no | Per-cluster Adler-32-derived API proxy port (echoed from the Cluster CR's `k8s-lab.io/api-proxy-port` annotation). |
| `metallb_vip_range_v6` | `string` | no | Echo of the IPv6 VIP range (passthrough). |
| `helm_releases` | `map(object)` | no | Map of `{id, name, ns, version}` for all five helm releases (smoke checks). |

### Provider model

The module **owns** its provider configurations (`providers.tf`); the
fixture root MUST NOT redeclare them. Cite `§16.4`.

- `provider "kubernetes" { alias = "mgmt" }` — `config_path =
  var.mgmt_kubeconfig_path`. Used by the two `data.kubernetes_resource`
  reads only.
- `provider "helm" { alias = "mgmt" }` — same `config_path`. Used by
  `helm_release.capi_cluster_class` and `helm_release.capi_workload_cluster`.
- `provider "helm" { alias = "workload" }` — configured **inline** from
  fields parsed out of the kubeconfig Secret in `locals.tf`
  (`host`, `cluster_ca_certificate`, `client_certificate`, `client_key`,
  `tls_server_name`). When the upstream Secret has not yet materialised
  (first plan/refresh), every field evaluates to `null` via `try(...)`;
  Terraform tolerates that until any workload-scoped resource is
  actually instantiated.

This split is why a future consumer that wants cross-module
`helm.workload` sharing must use `configuration_aliases` plus an
explicit `providers = {...}` map at the call site.

Required versions (`versions.tf`):

| Provider | Version |
|----------|---------|
| Terraform core | `>= 1.9` |
| `hashicorp/helm` | `~> 3.1` |
| `hashicorp/kubernetes` | `~> 2.30` |
| `hashicorp/null` | `~> 3.2` |

### Usage

Minimal call site (a fixture or a consumer root module):

```hcl
module "workload_cluster" {
  source = "github.com/<org>/k8s-lab//terraform/modules/workload_cluster?ref=v1.0.0"

  mgmt_kubeconfig_path           = "${path.root}/.artifacts/mgmt.kubeconfig"

  cluster_name                   = "lab-default"
  cluster_namespace              = "capi-clusters"
  kubernetes_version             = "v1.35.0"
  controlplane_count             = 3
  worker_count                   = 2

  cluster_class_chart_version    = "0.6.3"
  cluster_workload_chart_version = "0.8.0"
  cni_calico_chart_version       = "0.2.1"
  metallb_chart_version          = "0.1.0"
  metallb_config_chart_version   = "0.1.3"

  pod_cidrs                      = ["10.244.0.0/16", "fd42:77:2::/56"]
  service_cidrs                  = ["10.96.0.0/16", "fd42:77:3::/112"]

  metallb_vip_range_v6           = "2001:db8:42:100::100-2001:db8:42:100::1ff"
  lxd_host_address               = "192.168.121.10"
}
```

The mgmt kubeconfig is the **same file** pre- and post-pivot — it is
overwritten in place by `pivot_clusterctl_move`.

### Test fixture

The single TF root that exercises the module is
`tests/fixtures/terraform/workload-clusters/lab-default/`. It contains
`main.tf`, `outputs.tf`, `providers.tf`, `variables.tf` and is the
**only** fixture in the repo (`§16.5`). The fixture intentionally
declares no `helm` / `kubernetes` provider blocks of its own — the
module owns them.

---

## Helm charts

The five charts ship under `charts/`. Two of them
(`capi-cluster-class`, `capi-workload-cluster`) follow the
**chart-version-as-CR-name** rotation contract (`§2.9`, `§16.2`); the
other three are wrapper / config charts whose `Chart.Version` is a
plain release identifier.

The general rule applied by every chart in this repo
(memory rule "Chart-required values are hardcoded, not variables"):
**substrate-required CR fields are baked into `templates/*.yaml`** —
a consumer MUST NOT be able to silently break the chart by overriding
them. `values.yaml` exposes only legitimate optional extensions
(extra profiles, optional fingerprints, extra node selectors,
configurable timeouts, image pins).

### `charts/capi-cluster-class`

**Purpose.** Reusable CAPI topology for the CAPN unprivileged kubeadm
path — a single Helm release renders the `ClusterClass` plus the four
referenced templates so that a workload `Cluster` CR (rendered by
`capi-workload-cluster`) can refer to them through
`spec.topology.classRef`.

**Templates shipped.**

```
charts/capi-cluster-class/templates/
├── _helpers.tpl
├── cluster-class.yaml
├── kubeadm-config-template-worker.yaml
├── kubeadm-control-plane-template.yaml
├── lxc-cluster-template.yaml
├── lxc-machine-template-controlplane.yaml
└── lxc-machine-template-worker.yaml
```

The `KubeadmControlPlaneTemplate` and `KubeadmConfigTemplate (worker)`
deliver the **eth1 RA reception baseline** through
`KubeadmConfigSpec.files` + `preKubeadmCommands` (so it lands as
cloud-init `write_files` on first boot). The two delivered files are:

- `/etc/sysctl.d/99-capi-ra.conf` — `accept_ra=2`,
  `accept_ra_defrtr=1`, `disable_ipv6=0` on `eth1`. `accept_ra=2` is
  required because workload nodes have `forwarding=1` and the kernel
  default `accept_ra=1` ignores RAs on a forwarding host.
- `/etc/systemd/network/30-capi-ext.network` — `[Match] Name=eth1`,
  `[Network] DHCP=no LinkLocalAddressing=ipv6 IPv6AcceptRA=yes`.

`preKubeadmCommands` runs `sysctl --load` + `networkctl reload` so the
configuration is alive before kubeadm starts. See `§16.2` and the
architecture chapter `§4.4` for the full rationale.

**Key values.** Full reference in `08-configuration-reference.md`.
Short table:

| Path | Type | Default | Purpose |
|------|------|---------|---------|
| `clusterClass.name` | string | `capn-default` | Logical prefix; final names = `<prefix>-<chart-version-slug>`. |
| `kubernetes.version` | string | `""` | Bound from §8 `k8s_lab_kubernetes_version`. CAPN substrings literal `VERSION` in image refs. |
| `capn.infrastructureSecretName` | string | `""` | CAPN identity Secret (provisioned by role `bootstrap_capn_secret`). |
| `images.controlplane.ref` / `images.worker.ref` | string | `capi:kubeadm/VERSION` | CAPN image refs. |
| `images.controlplane.fingerprint` / `images.worker.fingerprint` | string | `""` | Optional sha256 pins. |
| `loadBalancer` | any | `{ lxc: {} }` | Exactly one of `{lxc, oci, ovn, kubeVIP, external}`. Schema enforces `maxProperties=1`. |
| `profilesExtra.{controlplane,worker}` | list(string) | `[]` | Extras appended after the substrate baseline (`capi-base` + role profile). |
| `devicesExtra.{controlplane,worker}` | list(string) | `[]` | CSV device overrides on top of profile NICs. |
| `controlPlane.{featureGates,*ExtraArgs,pre/postKubeadmCommands}` | structured | `{}` / `[]` | kubeadm CP tuning. Substrate-reserved args (`bind-address`, `cluster-cidr`, `service-cluster-ip-range`, `node-ip`, `provider-id`, `feature-gates` on kubelet) rejected by template guards. |
| `worker.{featureGates,kubeletExtraArgs,pre/postKubeadmCommands}` | structured | `{}` / `[]` | kubeadm worker tuning. |
| `kubeProxy.nodePortAddresses` | list(string) | `[]` | NodePort bind CIDRs. |

**Chart-required (hardcoded) values.** Per memory rule
*"Chart-required values are hardcoded, not variables"* — the unprivileged
LXC path, skipping CAPN's default kubeadm profile, `instanceType:
container`, CAPN v1alpha2 API selection, the `capi-base` /
`capi-controlplane` / `capi-worker` profile baseline shipped by role
`lxd_profiles`, the dual-bind v4/v6 HAProxy frontend, and the
`md-0` MachineDeployment class name are all baked directly into
`templates/*.yaml`. Consumer overrides cannot remove or rename them.

**Chart.Version policy.** The chart implements the
**chart-version-as-CR-name rotation contract** (`§2.9`, `§16.2`): every
rendered object's `metadata.name` carries a slug derived from
`Chart.Version` (dots → `-`, lowercased, trimmed to 63 chars). Bumping
`Chart.Version` produces a fresh object set and side-steps the CAPI
webhook immutability rule on referenced `ClusterClass` / `*Template`
CRs. Helpers in `templates/_helpers.tpl`:

```
classFullName                         = <prefix>-<slug>
lxcClusterTemplateName                = <prefix>-<slug>-infra
lxcMachineTemplateCPName              = <prefix>-<slug>-cp
lxcMachineTemplateWorkerName          = <prefix>-<slug>-md0
kubeadmControlPlaneTemplateName       = <prefix>-<slug>-kcp
kubeadmConfigTemplateWorkerName       = <prefix>-<slug>-md0-bootstrap
```

The `_helpers.tpl` also enforces three CAPI-availability gates
(`requireCAPI`, `requireCAPN`, `requireKubeadm`) that fail the install
with a readable error if the target cluster has not been
`clusterctl init`-ed (or has a different infrastructure provider).

**Plan reference.** `§16.2`.

### `charts/capi-workload-cluster`

**Purpose.** Renders **exactly one** `Cluster` CR
(`cluster.x-k8s.io/v1beta2`) in topology mode, plus the API-proxy
attach/detach hook Jobs that patch the haproxy LB instance with an LXD
proxy device for runner reachability. One release == one workload
cluster.

**Templates shipped.**

```
charts/capi-workload-cluster/templates/
├── _helpers.tpl
├── api-proxy-attach-job.yaml
├── api-proxy-detach-job.yaml
├── cluster.yaml
└── tests/
    ├── cluster-ready.yaml
    └── rbac.yaml
```

The `api-proxy-attach-job.yaml` is a `helm.sh/hook: post-install,post-upgrade`
Job that runs **four readiness gates** in sequence: (1) LB instance
materialised in LXD, (2) kubeconfig Secret emitted by KCP, (3) LB
Running + proxy device attached, (4) apiserver `/livez` returning
200/401/403. Driving the LXD HTTPS REST API directly with mTLS material
from the `incus-identity` Secret means no `incus`/`lxc` CLI binary is
needed inside the Job container (alpine + apk + curl + jq is enough).

`tests/cluster-ready.yaml` is the Phase 2 helm test: it asserts the
Cluster CR is `Provisioned`, KCP / MD / LXCCluster are owned by CAPI,
and every node in `topology.{controlPlane,workers}.replicas` joined the
workload API. This test runs against the **mgmt cluster**, not the
workload — it is a CR-level acceptance test of the topology, not a
data-plane test.

**Key values.**

| Path | Type | Default | Purpose |
|------|------|---------|---------|
| `cluster.name` | string | `lab-default` | `metadata.name` of the Cluster CR + cluster-name label on every owned object. |
| `clusterClass.name` | string | `capn-default` | Logical prefix matching `capi-cluster-class .Values.clusterClass.name`. |
| `clusterClass.namespace` | string | `""` | Empty omits `classRef.namespace` (same-namespace pattern). |
| `kubernetes.version` | string | `v1.35.0` | `spec.topology.version`. Constrained by CAPN simplestreams images, NOT by `dl.k8s.io/release/stable.txt`. |
| `topology.controlPlane.replicas` | int | `3` | Stacked-etcd KCP — must be odd. |
| `topology.workers.replicas` | int | `2` | Single MD `md-0` (class name hardcoded, must match `capi-cluster-class`). |
| `clusterNetwork.pods.cidrBlocks` | list | `[10.244.0.0/16, fd42:77:2::/56]` | The one place pod CIDRs are declared in topology mode. |
| `clusterNetwork.services.cidrBlocks` | list | `[10.96.0.0/16, fd42:77:3::/112]` | Service CIDRs. |
| `loadBalancer.lxc.proxyApiPort` | int | `0` | Override auto-derived Adler-32 port. `0` = use the hash. |
| `apiProxy.image` | string | `alpine:3.21` | Hook Job base image. |
| `apiProxy.infrastructureSecretName` | string | `incus-identity` | Same Secret CAPN reads. |
| `apiProxy.lbWaitTimeoutSeconds` | int | `600` | Max wait for CAPN to materialise the haproxy LB LXC. |
| `tests.image` | string | `alpine:3.21` | Helm-test pod base image (fetches kubectl from `dl.k8s.io` at runtime). |
| `tests.nodesUpTimeoutSeconds` | int | `1200` | Max wait for workload-side node registration. |

**Chart-required (hardcoded) values.** `apiVersion`/`kind`, the
topology mode itself, the `md-0` MachineDeployment class name, the
post-install hook Job's four-gate sequence, the IPv4+IPv6 CIDR
positional indices ([0]=v4, [1]=v6) and the
`tls-server-name=kubernetes.default.svc` SAN are all hardcoded and not
exposed as values.

**Chart.Version policy.** Like `capi-cluster-class`, this chart
follows the chart-version-as-CR-name pattern but only when explicit
rotation is desired — `Cluster.spec.topology` is largely mutable, so
the default chart uses `Values.cluster.name` verbatim (CAPI tolerates
in-place topology updates). The chart is **pinned to a specific
`capi-cluster-class` chart version** through

```yaml
# charts/capi-workload-cluster/Chart.yaml
annotations:
  k8s-lab.io/capi-cluster-class-chart-version: "0.6.3"
```

The `_helpers.tpl` reads that annotation and reproduces the slug
(`replace "." "-" | lower | trunc 63 | trimSuffix "-"`) to compute
`spec.topology.classRef.name`. Bumping the cluster-class chart
**requires** a paired bump of this annotation + this chart's own
`version:` field. The helper fails the install with a readable error
if the annotation is missing.

**API proxy port.** Default = `add 20000 (mod (atoi (adler32sum
.Values.cluster.name)) 10000)` — deterministic per `cluster.name`,
kept stable across re-applies. Override via
`loadBalancer.lxc.proxyApiPort` to resolve hash collisions
(≈ 0.5 % on 10 workloads on the same LXD host). The chart writes the
computed port into the Cluster CR annotation
`k8s-lab.io/api-proxy-port`; the Terraform module reads that annotation
back as the single-source-of-truth for the kubeconfig server URL
rewrite.

**Plan reference.** `§16.3`.

### `charts/cni-calico`

**Purpose.** Local wrapper around the upstream
`projectcalico/tigera-operator` chart with **dual-stack defaults baked
in** plus a chart-side **Gate B** acceptance hook covering Calico Pod
readiness, workload Node `Ready=True`, dual-stack pod-CIDR allocation,
and live pod-to-pod ICMP across two worker nodes.

**Templates shipped.**

```
charts/cni-calico/templates/
├── _helpers.tpl
├── installation.yaml
└── tests/
    ├── cni-ready.yaml
    └── rbac.yaml
```

`installation.yaml` renders the Calico `Installation` CR
(`operator.tigera.io/v1`) with the substrate-required network policy:

- `cni.type: Calico`, IPAM type, `bgp: Disabled`,
  `linuxDataplane: Iptables`;
- two `IPPool`s (IPv4 + IPv6) with `encapsulation: VXLAN`,
  `natOutgoing: Enabled` for *both* pools (IPv4 because Pod CIDR is
  RFC1918, IPv6 because Pod CIDR is ULA `fd42:77:2::/56` and
  `capi-int` has no return route);
- `controlPlaneReplicas: 2` to satisfy the §2.12 HA-pair contract on
  `calico-kube-controllers` and `calico-apiserver` via the operator's
  built-in podAntiAffinity. Typha is intentionally disabled (lab sizes
  are well under upstream's auto-enable threshold ≈ 50 nodes).

`tests/cni-ready.yaml` deploys two probe pods with
`requiredDuringSchedulingIgnoredDuringExecution` pod-anti-affinity to
force them onto **two distinct workers**, then drives
`kubectl exec` ICMP4 + ICMP6 round-trips between them. Cite `§17.2`.

**Key values.**

| Path | Type | Default | Purpose |
|------|------|---------|---------|
| `calico.pods.cidrBlocks` | list | `[10.244.0.0/16, fd42:77:2::/56]` | Dual-stack pod CIDRs. Indices positional. |
| `tigera-operator.installation.enabled` | bool | `false` | Upstream Installation disabled — we render our own. |
| `tigera-operator.apiServer.enabled` | bool | `true` | Required for projectcalico.org aggregated APIs. |
| `tigera-operator.goldmane.enabled` | bool | `false` | Flow-log aggregator. Optional. |
| `tigera-operator.whisker.enabled` | bool | `false` | Observability UI. Optional. |
| `tests.image` | string | `alpine:3.21` | Probe pod base image. |
| `tests.kubectlVersion` | string | `v1.35.0` | kubectl pinned to the workload k8s minor; fetched from `dl.k8s.io` at runtime. |
| `tests.nodesReadyTimeoutSeconds` | int | `600` | calico-node DS rollout + per-Node CNI install + Ready propagation. |
| `tests.podToPodTimeoutSeconds` | int | `120` | Probe pod creation + ICMP round-trip. |

**Chart-required (hardcoded) values.** `cni.type`, IPAM type,
`bgp: Disabled`, `linuxDataplane: Iptables`, `encapsulation: VXLAN`,
`natOutgoing: Enabled` on both pools, and `controlPlaneReplicas: 2`
all live in `templates/installation.yaml` and are not consumer-tunable.
BGP infra is absent on the CAPN/LXD lab substrate, IPIP encapsulation
does not support IPv6, and unprivileged-LXC Calico needs Iptables
dataplane (eBPF requires kernel privileges that user-namespaces don't
grant) — `§17.1` substrate contract.

**Chart.Version policy.** Local wrapper version. Bumped on every
values/template change so chart-level traceability stays meaningful.
The upstream `tigera-operator` chart is pinned via
`Chart.yaml.dependencies` (`v3.31.5` at the time of writing) — bump in
lockstep.

**Plan reference.** `§17.1`, `§17.2`.

### `charts/metallb`

**Purpose.** Minimal subchart wrapper around upstream
`metallb/metallb` (CRDs + controller + speaker). Pins the
substrate-required toggles via `values.yaml` and ships **no templates
of its own** — the IPAddressPool / L2Advertisement CRs and the Gate A
acceptance hook live in the sibling chart `metallb-config`, installed
as a **separate Helm release** after this one.

**Templates shipped.** None. The chart contains:

```
charts/metallb/
├── Chart.lock
├── Chart.yaml
├── charts/        # populated by `helm dep update` (upstream subchart)
├── values.schema.json
└── values.yaml
```

The two-release split rationale (`§17.3`): the upstream subchart's
CRDs live in `templates/crds/` rather than the Helm `crds/` folder, so
they are applied as part of the regular kind-sorted apply transaction,
but Helm 3 builds the manifest list (and validates kinds against the
API server) **before** that apply. A single-release wrapper carrying
both the subchart and a wrapper-owned `IPAddressPool` fails at first
install with `no matches for kind "IPAddressPool" in version
"metallb.io/v1beta1"`. The fix is two distinct Helm releases.

**Key values.**

| Path | Type | Default | Purpose |
|------|------|---------|---------|
| `metallb.crds.enabled` | bool | `true` | Subchart switch for the CRD sub-dependency. Flipping off would break the two-release contract. |
| `metallb.frrk8s.enabled` | bool | `false` | No BGP / frr-k8s on the lab substrate (`§5.5`). |
| `metallb.speaker.frr.enabled` | bool | `false` | L2 mode only — drops the frrouting sidecar from speaker Pods. |
| `metallb.speaker.tolerateMaster` | bool | `true` | Speaker DS still lands on CP nodes; `L2Advertisement.nodeSelectors` in the sibling chart restricts VIP announcement to workers. |

The rest of the upstream surface stays open (overridable by consumer).

**Chart-required (hardcoded) values.** None of its own — the wrapper
exists only to pin the four substrate-contract toggles above.

**Upstream constraint — controller singleton (§2.12 deviation).**
Upstream `metallb` chart `0.15.3` does not expose
`controller.replicas` (single-replica by upstream design — controller
is a singleton that allocates VIPs from the pool and validates CRs, no
state partitioning). HA is delivered through the speaker DaemonSet
(one replica per worker, leader-elected per-VIP via memberlist) —
that satisfies the failover guarantee `§2.12` actually cares about.
This deviation is documented in `charts/metallb-config/values.yaml`.
Cite `§17.3`.

**Chart.Version policy.** Local wrapper version. Bumped on every
values change. `Chart.yaml.dependencies.metallb.version` is pinned in
lockstep with `appVersion`.

**Plan reference.** `§17.1`, `§17.3`.

### `charts/metallb-config`

**Purpose.** Owns the IPv6 `IPAddressPool` + `L2Advertisement` CRs for
the workload cluster and ships a `helm.sh/hook: test` driver Pod that
drives a **real LoadBalancer demo Service** end-to-end inside the
cluster. Molecule e2e-local adds the verify-side external curl from
outside the cluster to close the local Gate A external segment proof.

Installed as the **second** Helm release in the MetalLB delivery pair —
the sibling `charts/metallb/` registers CRDs + controller + speaker
first, this wrapper then reconciles the CRs against an already-live
`metallb.io` API.

**Templates shipped.**

```
charts/metallb-config/templates/
├── _helpers.tpl
├── ipaddresspool.yaml
├── l2advertisement.yaml
└── tests/
    ├── metallb-vip.yaml
    └── rbac.yaml
```

`tests/metallb-vip.yaml` deploys a real demo `nginx` `Deployment` +
`Service` `type=LoadBalancer` with `ipFamilies: [IPv6]`,
`ipFamilyPolicy: SingleStack`, asserts the VIP is allocated and
in-pool, runs an in-cluster HTTP probe from a sibling driver Pod, and
exits 0 only when both succeed. The verify-side external curl is
outside the Terraform module; the local harness performs it in the
Molecule verify playbook. Cite `§17.3`.

**Key values.**

| Path | Type | Default | Purpose |
|------|------|---------|---------|
| `pool.rangeV6` | string | `""` | IPv6 VIP range (`<from>-<to>` or `<ip>/128`). No safe default. |
| `l2.interface` | string | `eth1` | Interface MetalLB speaker announces VIPs on. |
| `l2.extraNodeSelectors` | map | `{}` | Stacked on top of substrate-required CP-exclusion. |
| `tests.image` | string | `alpine:3.21` | Driver pod base image. |
| `tests.demoImage` | string | `nginx:1.27-alpine` | Backend pod image. nginx listens on `[::]:80` (IPv6 wildcard accepting v4-mapped). |
| `tests.demoName` | string | `k8s-lab-metallb-demo` | Backend basename (project-relevant naming per memory rule). |
| `tests.demoPort` | int | `80` | Demo backend / Service port. |
| `tests.kubectlVersion` | string | `v1.35.0` | kubectl pinned to the workload k8s minor. |
| `tests.vipAllocationTimeoutSeconds` | int | `600` | Speaker rollout + controller Available + VIP allocation + cold image pull. |

**Chart-required (hardcoded) values.** `interfaces:
[<l2.interface>]`, the `L2Advertisement.nodeSelectors` excluding CP
nodes, `IPAddressPool.protocol=L2`, IPv6 single-stack on the demo
Service. VIP announcement only from worker nodes (`§4` CP isolation
from user traffic), L2 mode is the only supported MetalLB protocol on
this lab substrate (no BGP infra) — `§17.1` substrate contract.

**Chart.Version policy.** Local wrapper version. Bumped on every
values/template change. `appVersion` tracks the upstream MetalLB API
surface targeted by the CRs (`metallb.io/v1beta1`).

**Plan reference.** `§17.1`, `§17.3`.

---

## How they wire together

The same five charts back **two** install paths. Only the values
differ.

### Path 1 — mgmt-1 install (pre-pivot, `e2e-local` Molecule converge)

The bootstrap k3s instance hosts the transient mgmt-1 Cluster CR plus
its dependencies. The e2e-local Molecule scenario installs the charts
**directly** with `kubernetes.core.helm` against
`.artifacts/mgmt.kubeconfig` (which still points at bootstrap k3s at
this stage):

```
bootstrap k3s (capi-bootstrap-0)
    │  helm install mgmt-1-class       capi-cluster-class      (mgmt values)
    │  helm install mgmt-1             capi-workload-cluster   (mgmt values)
    │     └── CAPN provisions mgmt-1 nodes + LB
    │
    │  helm install cni-calico         (workload kubeconfig of mgmt-1)
    │  helm test    cni-calico         (Gate B on mgmt-1 itself)
    │
    │  helm install metallb            (workload kubeconfig of mgmt-1)
    │  helm install metallb-config     (workload kubeconfig of mgmt-1)
    │  helm test    metallb-config     (Gate A on mgmt-1 itself)
    │
    └── pivot: clusterctl init + clusterctl move → mgmt-1
        cleanup_bootstrap destroys capi-bootstrap-0
```

There is **no Terraform module** in this path. The mgmt-1 cluster is
provisioned by the same charts but the driver is the e2e Molecule
playbook (or a consumer-repo equivalent). Helm release storage on
bootstrap k3s vanishes with `cleanup_bootstrap`; the post-pivot
Calico/MetalLB releases on **mgmt-1 itself** survive because they were
created against mgmt-1's API, not bootstrap's. See
`02-architecture.md` §7 for the object-lifecycle walkthrough.

### Path 2 — workload install (post-pivot, `terraform/modules/workload_cluster`)

Once mgmt-1 is self-hosted, every additional workload cluster goes
through the Terraform module:

```
self-hosted mgmt-1 (post-pivot)
    │  TF: helm_release.capi_cluster_class      (provider = helm.mgmt)
    │  TF: helm_release.capi_workload_cluster   (provider = helm.mgmt)
    │     └── chart-side hook waits for LB + kubeconfig + apiserver
    │  TF: data.kubernetes_resource.workload_kubeconfig_secret
    │     └── locals.tf parses kc, rewrites server URL → helm.workload provider
    │
    │  TF: helm_release.cni_calico              (provider = helm.workload)
    │  TF: null_resource.helm_test_cni_calico   (Gate B on workload)
    │
    │  TF: helm_release.metallb                 (provider = helm.workload)
    │  TF: helm_release.metallb_config          (provider = helm.workload)
    │  TF: null_resource.helm_test_metallb_config  (Gate A on workload)
    │
    └── module outputs: workload kubeconfig, api_proxy_port, helm_releases map
```

The two paths use identical charts, identical chart-required values,
and identical helm test logic. The only Path-2-specific machinery is
the in-state kubeconfig pipeline (the workload kubeconfig is parsed
from a Secret on mgmt-1, the server URL is rewritten to
`<lxd_host_address>:<api_proxy_port>`, and the rewritten content
becomes the `helm.workload` provider's inline credentials — never
written to disk). See `§16.7` for the full pipeline.

---

## Chart-version-as-CR-name pattern in detail

CAPI's admission webhook forbids mutating most fields of a referenced
`ClusterClass` or `*Template` CR. A naïve `helm upgrade` with changed
values fails on `admission webhook denied: field is immutable`. The
pattern that solves this (`§2.9`, `§12.10`):

In `charts/capi-cluster-class/templates/_helpers.tpl`:

```gotemplate
{{- define "capi-cluster-class.versionSlug" -}}
{{- .Chart.Version | replace "." "-" | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "capi-cluster-class.classFullName" -}}
{{- printf "%s-%s" .Values.clusterClass.name (include "capi-cluster-class.versionSlug" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

Every rendered object's `metadata.name` carries the slug. Bumping
`Chart.Version` produces a fresh object set; `helm upgrade` creates
the new objects and the old ones live until a deliberate cleanup.
`helm rollback` to the previous chart version restores the previous
object set verbatim.

In `charts/capi-workload-cluster/templates/_helpers.tpl`, the same
slug is reproduced from a chart annotation rather than a value:

```gotemplate
{{- define "capi-workload-cluster.clusterClassVersion" -}}
{{- $v := index .Chart.Annotations "k8s-lab.io/capi-cluster-class-chart-version" -}}
{{- if not $v -}}
{{- fail "Chart.yaml is missing annotations[\"k8s-lab.io/capi-cluster-class-chart-version\"]; cannot derive ClusterClass metadata.name." -}}
{{- end -}}
{{- $v -}}
{{- end -}}

{{- define "capi-workload-cluster.classFullName" -}}
{{- $slug := include "capi-workload-cluster.clusterClassVersion" . | replace "." "-" | lower | trunc 63 | trimSuffix "-" -}}
{{- printf "%s-%s" .Values.clusterClass.name $slug | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

`spec.topology.classRef.name` in `cluster.yaml` calls
`capi-workload-cluster.classFullName`. The two charts evolve in
lockstep through `Chart.yaml.annotations.k8s-lab.io/capi-cluster-class-chart-version`
(currently `0.6.3`). The Terraform module reproduces the same slug in
`locals.tf` purely for the `cluster_class_name` output:

```hcl
cluster_class_version_slug = lower(replace(var.cluster_class_chart_version, ".", "-"))
cluster_class_full_name    = substr("${var.class_prefix}-${local.cluster_class_version_slug}", 0, 63)
```

The module does **not** pass the slug back to either chart — both
charts compute it themselves, the module only echoes it for
introspection.

The other three charts (`cni-calico`, `metallb`, `metallb-config`) do
**not** use this pattern: they own no CAPI CRs, their objects can be
mutated in place by the operator / admission webhooks, and their
`Chart.Version` is a plain release identifier (bumped on every
values / template change for traceability, but not load-bearing for
object naming).

---

## Where to read more

| Topic | Source |
|-------|--------|
| Why the single-module + five-chart split | `01-overview.md`, `02-architecture.md` §5 |
| Full configuration reference for every value | `08-configuration-reference.md` |
| Bootstrap → pivot → workload object lifecycle | `02-architecture.md` §7 |
| Acceptance gates A and B in depth | `02-architecture.md` §8, plan `§6`, `§17` |
| TF module spec | plan `§16.1` … `§16.7` of `PLAN-stage1-3.md` |
| Chart-side helm test spec | plan `§17.1` … `§17.3` of `PLAN-stage1-4.md` |
| Chart-required-values rule | memory `feedback_chart_required_values_hardcoded.md` |
