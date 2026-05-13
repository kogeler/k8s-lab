# 03 — Stack

This chapter is the reference list of every external dependency this
repository pins, with the upstream version, where the pin lives in
the source tree, and a one-paragraph rationale per component.

The single source of truth for every pin is the **verified version
log** at `§8a` of
[`../plans/PLAN-stage1-common.md`](../plans/PLAN-stage1-common.md);
this chapter is a curated mirror of that table plus the rationale
required by `§2.11`. If the table here ever diverges from `§8a`, the
plan wins and this page must be regenerated.

For the *why* of the architecture itself (single-host model,
bootstrap-and-pivot, layer ownership), see
[`02-architecture.md`](02-architecture.md). This chapter does not
re-tell that flow — it only enumerates the pieces.

---

## Summary table

| Component | Version | Where pinned | Notes |
|-----------|---------|--------------|-------|
| Kubernetes (workload + mgmt) | `v1.35.0` | `k8s_lab_kubernetes_version` | Bounded by upstream CAPN simplestreams `kubeadm/<ver>` images — `§8a` deviation. |
| k3s (bootstrap cluster only) | `v1.35.3+k3s1` | `k8s_lab_k3s_version` | Single binary, single node, host-network controllers. |
| kubectl | `v1.35.3` | `k8s_lab_kubectl_version` | Fetched into `/opt/capi-lab/bin` by `binary_fetch`. |
| Cluster API (`clusterctl` + core) | `v1.12.5` | `k8s_lab_clusterctl_version` | Drives `clusterctl init` on bootstrap, `clusterctl move` on pivot. |
| CAPN (`cluster-api-provider-incus`) | `v0.8.5` | `k8s_lab_capn_provider_version` | LXD/Incus infrastructure provider. |
| LXD snap channel | `6/stable` | `lxd_host_snap_channel` | Feature-stable track; deviates from Canonical LTS recommendation `5.21/stable` per `§2.11`. |
| Calico (`tigera-operator` chart) | `v3.31.5` | `k8s_lab_calico_chart_version` | Subchart dependency in `charts/cni-calico/`. |
| MetalLB chart | `0.15.3` | `k8s_lab_metallb_chart_version` | Subchart dependency in `charts/metallb/`. |
| Terraform `hashicorp/helm` provider | `3.1.1` | `k8s_lab_helm_provider_version` | Sole driver of CR-creating helm releases. |
| `ansible.posix` collection | `>=2.1.0` | `ansible/requirements.yml` | Lower bound only — no ceiling per `§2.11`. |
| `community.general` collection | `>=12.6.0` | `ansible/requirements.yml` | Used by `lxd_*` roles. |
| `community.crypto` collection | `>=3.2.0` | `ansible/requirements.yml` | CAPN restricted-cert generation. |
| `kubernetes.core` collection | `>=6.4.0` | `ansible/requirements.yml` | `k8s_info` polling on bootstrap k3s and mgmt-1. |
| `python3-kubernetes` (Debian Trixie) | `30.1.0-2` | `tests/molecule/shared/tasks/prepare.yml` | Required on the executor node by `kubernetes.core`. |

---

## Host platform

- **OS target:** Debian or Ubuntu Linux. The pinned production reference
  is Debian 13 Trixie — both the production target host (per plan
  `§2.1`) and the local Vagrant VM run this build. The CI Molecule
  scenario (`tests/molecule/gha`) exercises the same roles on Ubuntu on
  a GitHub Actions runner. Role preflight checks gate on Debian 13+ or
  Ubuntu 22.04+; see role source for the exact assertion.
- **Package source:** only the standard Debian APT repositories.
  Custom APT repositories on the host are forbidden (`§2.2`); every
  non-standard binary (`kubectl`, `clusterctl`, `k3s`) is fetched into
  `/opt/capi-lab/bin` by the `binary_fetch` role, version-pinned and
  checksum-verified.
- **No host-level Kubernetes.** No Docker, no kind, no host kubelet.
  The host runs LXD, the `br-ext6` Linux bridge, and nothing else
  Kubernetes-related.

---

## LXD substrate

- **Distribution channel:** snap, channel `6/stable`
  (`lxd_host_snap_channel`).
- **Why snap, not deb:** Canonical's official recommendation for
  installing LXD on Linux, including Debian, is the snap; the snap
  channel is the documented version-pinning mechanism (`§2.1`).
- **Why `6/stable`, not `5.21/stable` LTS:** `§2.11` reads "latest
  stable" literally, which selects the feature-stable track. The
  `§8a` deviation note records this trade-off explicitly: regression
  risk is higher and CAPN has not declared explicit compatibility
  with LXD 6.x; if a Gate-blocking incompatibility surfaces, the
  fallback is `5.21/stable`, recorded back in the plan change log.
- **Auto-refresh:** held via `snap refresh --hold` by the `lxd_host`
  role to prevent unattended snap auto-updates from rolling LXD
  forward mid-deploy (`§2.2`, `§12.5`).
- **Project isolation:** the entire lab lives inside one LXD project
  (`capi-lab`) so it does not collide with hand-managed LXC instances
  on the same host (`§2.3`). CAPN's API access is scoped by a
  project-restricted TLS certificate.

---

## Cluster API stack

| Piece | Version | Source |
|-------|---------|--------|
| `clusterctl` (binary) | `v1.12.5` | upstream `kubernetes-sigs/cluster-api` releases |
| CAPI core / CABPK / KCP controllers | `v1.12.5` | installed by `clusterctl init` from its built-in registry |
| CAPN infrastructure provider | `v0.8.5` | `lxc/cluster-api-provider-incus` |

- The `clusterctl` config used by the `bootstrap_clusterctl` role is
  rendered from
  `ansible/roles/bootstrap_clusterctl/templates/clusterctl.yaml.j2`
  and declares only the CAPN entry; the core, kubeadm-bootstrap, and
  kubeadm-control-plane providers come from `clusterctl`'s built-in
  registry.
- **Upstream docs:**
  - Cluster API: <https://cluster-api.sigs.k8s.io/>
  - CAPN: <https://capn.linuxcontainers.org/>
- **Image constraint (`§8a`).** `k8s_lab_kubernetes_version` is
  bounded by the set of prebuilt `capi:kubeadm/<ver>` images
  published on the upstream CAPN simplestreams
  (<https://images.linuxcontainers.org/capn/>). The server only mints
  images for selected releases (typically `<minor>.0` plus rare
  patches). Setting `kubernetes.version` to a version with no image
  fails at the first LXCMachine creation with `Failed getting image:
  The requested image couldn't be found for fingerprint
  "kubeadm/<ver>"`. As of the `§8a` verification (2026-04-25), the
  available pins are `v1.33.0`, `v1.33.5`, `v1.34.0`, `v1.35.0`;
  `v1.35.0` is the latest relevant pin. Upstream
  `dl.k8s.io/release/stable.txt` may be ahead, but those releases are
  irrelevant to this repository until CAPN publishes a matching
  image.

---

## Bootstrap cluster runtime

- **Implementation:** k3s `v1.35.3+k3s1`, single binary, single node,
  inside the transient `capi-bootstrap-0` LXC instance.
- **Why k3s, not kind or kubeadm:**
  - `kind` requires Docker on the host, which violates `§2.2` (no
    custom binaries on the host beyond the LXD snap and the fetched
    `/opt/capi-lab/bin` toolchain) and is also inconsistent with the
    "all Kubernetes nodes are LXC containers" model.
  - `kubeadm` for a single throwaway node is far heavier than a
    single-binary k3s server, both in disk and in cold-start time.
  - k3s is a fully compliant lightweight Kubernetes distribution
    shipped as a single binary; `k3s server` exposes the
    `--tls-san`, `--disable=servicelb`, `--disable=traefik` flags and
    a config file that map cleanly onto `bootstrap_k3s` defaults
    (`§2.4`).
- **Lifetime:** transient. Lives only between
  `bootstrap_clusterctl` and `cleanup_bootstrap`. Helm releases on
  bootstrap k3s are *not* migrated by `clusterctl move` — only CAPI
  CRs are — which is why no workload Cluster CR is ever created on
  bootstrap (`02-architecture.md §3.3`).

---

## Workload cluster runtime

- **Bootstrapper:** kubeadm, driven through CAPI's Kubeadm Bootstrap
  Provider (CABPK) and Kubeadm Control Plane Provider (KCP), with
  CAPN as the infrastructure backend.
- **Container image:** the prebuilt CAPN `capi:kubeadm/v1.35.0`
  unprivileged-kubeadm LXC image from the upstream simplestreams.
  These images are built specifically for the unprivileged container
  path and are required from CAPN `v1.32.4` onward (`§2.8`,
  `§12.2`).
- **LXC mode:** **unprivileged only**. A substrate invariant. The
  privileged path is closed by design and will not be added as an
  opt-in (`§2.8`). If a feature does not work in unprivileged LXC,
  the fix is to change the CNI, narrow scope, or move to VM-based
  nodes outside this repo's scope.
- **CAPN profile:** the project ships its own `lxd_profiles`
  (`capi-controlplane` and `capi-worker`), built on the CAPN
  Canonical LXD unprivileged kubeadm baseline:
  `linux.kernel_modules`, `security.nesting=true`,
  `security.idmap.isolated=true` where applicable, host `/boot`
  bind-mount to `/usr/lib/ostree-boot`, and `snapd` / `apparmor`
  systemd units disabled inside the guest (`§2.8`).

---

## CNI

- **Choice:** Calico, delivered by the upstream `tigera-operator`
  Helm chart wrapped by `charts/cni-calico/`.
- **Versions:** chart `v3.31.5`, `appVersion v3.31.5` (subchart
  pinned in lockstep — see `charts/cni-calico/Chart.yaml`).
- **Topology:** dual-stack IPv4 + IPv6, `natOutgoing: Enabled` for
  both families. The IPv6 SNAT is the canonical case of the
  bootstrap → self-hosted **network-surface asymmetry** documented
  in `02-architecture.md §3.4`: invisible pre-pivot, required
  post-pivot.
- **Why an upstream wrapper, not direct chart install:** the wrapper
  disables the operator's default `Installation` CR (`installation.
  enabled=false`) and ships its own with all substrate-required
  fields hardcoded (per the memory rule "chart-required values are
  hardcoded"). The upstream chart's optional knobs that are still
  legitimately tunable are exposed via `values.yaml` of the wrapper.
- **Acceptance:** Gate B (`§6`, `02-architecture.md §8.1`) ships as
  a chart-side `helm.sh/hook: test` Pod inside the same chart, so a
  CNI bring-up failure fails `terraform apply` immediately.
- **Why not Cilium or kube-router:** out of scope for Stage 1.
  Multi-CNI runtime toggles are a non-goal (`01-overview.md`); a CNI
  swap is a deliberate design step (a new wrapper chart), not a
  feature flag.

---

## Load balancing

- **Choice:** MetalLB in **L2 mode**, IPv6 VIP only, announced on
  worker `eth1` (`br-ext6`).
- **Versions:** chart `v0.15.3`, `appVersion v0.15.3` (subchart
  pinned in lockstep — see `charts/metallb/Chart.yaml`).
- **Delivery split:**
  - `charts/metallb/` — wrapper around the upstream chart, installs
    CRDs + controller + speaker, with substrate-required toggles
    hardcoded (`crds.enabled=true`, `frrk8s.enabled=false`,
    `speaker.frr.enabled=false`).
  - `charts/metallb-config/` — owns the `IPAddressPool` and
    `L2Advertisement` CRs and the Gate A acceptance hook. Installed
    as the second Helm release in the pair so CRDs are already
    registered when its CRs are applied.
- **Why L2, not BGP:** there is no BGP infrastructure on a single
  bare-metal host. L2 mode requires only that the upstream segment
  carries NDP correctly, which Gate A asserts. BGP-based Pod IPv6
  routing is in the **Stage 2 backlog** (`01-overview.md`) and not
  part of this v1.0 contract.
- **L2 advertisement contract (`§5.5`):**
  - `IPAddressPool` is sourced from the operator-supplied external
    IPv6 range;
  - `L2Advertisement.spec.interfaces: [eth1]`;
  - `L2Advertisement.spec.nodeSelectors` selects nodes that actually
    have the external NIC. `interfaces` alone does not affect leader
    election in L2 mode, so the node selector is mandatory.
- **Acceptance:** Gate A (`§6`, `02-architecture.md §8.2`) is a
  dual: a chart-side `helm.sh/hook: test` Pod plus a verify-side
  external curl from the Vagrant VM (or a probe in production). A
  broken L2 segment fails `terraform apply` before MetalLB starts
  pretending to serve VIPs (`§12.1`).

---

## Helm provider

- **Provider:** `hashicorp/helm`, `~> 3.1.1`.
- **Why Terraform-driven Helm, not raw `helm` calls:**
  - `02-architecture.md §5` fixes Helm as the only mutation channel
    for Kubernetes objects. Terraform's `helm_release` is the
    declarative front-end that lets every release be planned,
    diffed, and destroyed by `terraform plan` / `terraform destroy`
    rather than by an ad-hoc shell script.
  - `null_resource` + `local-exec helm test` inside the same module
    binds Gate A and Gate B helm tests to the lifecycle of the
    release that publishes them, so a Gate failure fails the apply
    in one tool (`§6`).
- **Why version 3.x:** the 3.x line of the provider supports the
  modern Helm v3 storage format (`sh.helm.release.v1.<release>.<n>`
  Secrets) and is the current upstream feature-stable track per
  `§2.11`.

---

## Ansible collections

Pinned in `ansible/requirements.yml`:

```yaml
collections:
  - name: ansible.posix
    version: ">=2.1.0"
  - name: community.general
    version: ">=12.6.0"
  - name: community.crypto
    version: ">=3.2.0"
  - name: kubernetes.core
    version: ">=6.4.0"
```

| Collection | Used by | Purpose |
|------------|---------|---------|
| `ansible.posix` | shared role plumbing | sysctl, mount, firewalld helpers from POSIX-shaped tasks. |
| `community.general` | `lxd_*` roles, `base_system` | `lxd_*` modules, snap module, miscellaneous host tooling. |
| `community.crypto` | `bootstrap_capn_secret`, `lxd_host` | Generates the CAPN restricted TLS certificate / key. |
| `kubernetes.core` | `bootstrap_clusterctl`, `pivot_clusterctl_move` | `k8s_info` polling of CAPI CRs and Deployments while waiting for `clusterctl init` and `clusterctl move` to settle. The CAPN identity Secret is the single deliberate `kubernetes.core.k8s` create-side use, gated by `02-architecture.md §5.1`. |

**Bounds policy (`§2.11`).** Every entry is a *lower bound only* —
no `<X+1` ceiling — so the next major release is not pre-emptively
locked out. Bumps are driven from upstream releases
(`GET /repos/<owner>/<repo>/releases/latest`) and recorded inline in
the plan plus aggregated in `§8a`.

**Executor-side dependency.** `kubernetes.core` requires the
`kubernetes` PyPI package on the executor node. On Debian Trixie this
is supplied as the system package `python3-kubernetes` (version
`30.1.0-2`), installed by
`tests/molecule/shared/tasks/prepare.yml` so test scenarios get it
for free. A consumer repo deploying to a real host installs the
same package via its host-bootstrap role.

---

## Local harness

The local harness is the only end-to-end driver shipped in this
repository.

- **Hypervisor:** **Vagrant + libvirt** (the
  `vagrant-libvirt` plugin), one Debian 13 VM, defined under
  `tests/vagrant/debian13/`.
- **Test driver:** **Molecule**, in **delegated mode** — the
  developer supplies `create` / `destroy`; Molecule runs
  `prepare`, `converge`, `idempotence`, `verify`. Delegated is
  Molecule's default driver and is the documented place for
  custom-driven scenarios (`§9.1`).
- **Make targets:** the local harness is driven exclusively through
  `make`, never raw `vagrant` / `virsh` / `molecule` invocations:
  `make -C tests/vagrant/debian13 up`, `make -C tests/molecule
  <scenario>-delegated-{create,converge,verify,destroy}`,
  `make test-local-e2e`.
- **External RA source:** an in-VM `radvd` listening on a veth peer
  (`ext6-ra-peer`) attached to `br-ext6` announces
  `2001:db8:42:100::/64`. Delivered by
  `tests/molecule/shared/tasks/ext6-ra-source.yml` and applied in
  every scenario's `prepare`. The node-side RA reception baseline is
  identical between local and prod; only the RA *source* differs
  (`02-architecture.md §4.5`).
- **Image policy:** every consumer image must be cloud-init-capable
  because the RA reception baseline lands as cloud-init `write_files`
  on first boot (`§2.10`, `02-architecture.md §4.4`).

---

## Verification cadence

`§2.11` and `§2.11b` fix how pins are bumped:

1. **At every bump, verify upstream first.** Stale defaults from the
   model's memory or from old documentation do not count. The agent
   must consult the upstream source (`GitHub releases/latest`,
   `snap info`, registry index) and record the verified value.
2. **Pin to the current upstream feature-stable.** If vendor official
   guidance contradicts "the most recent upstream stable" (the LXD
   `5.21/stable` LTS vs `6/stable` case), the bump still takes the
   most recent feature-stable and records the trade-off in the
   `§8a` deviation section. The only exception is when upstream has
   only prereleases — then the previous stable is allowed
   temporarily, with an explicit `§8a` note and a follow-up to
   upgrade at the first stable release.
3. **No artificial upper bound.** Lower bounds only in
   `requirements.yml`, provider blocks, and chart references. Any
   `>=X,<X+1` form is treated as a stale pin and removed at the
   moment of the bump.
4. **Inline + table.** Every bump updates two places: the inline
   pin comment in `§8` of the plan, and the `§8a` aggregated table.
   If the inline date diverges from the table, the inline pin is
   the truth and the table is regenerated at the next review.
5. **No standalone progress / changelog file.** The plan files
   themselves carry the bump history; a separate
   `PLAN-*-progress.md` or `CHANGELOG.md` is forbidden by `§2.11b`.

The CI/lint stage (when it lands) is expected to flag stale pins
against upstream automatically.

---

## Where to read more

| Stack question | Source |
|----------------|--------|
| What version of *X* is pinned today? | `§8a` of [`../plans/PLAN-stage1-common.md`](../plans/PLAN-stage1-common.md). |
| Why is the bump policy this strict? | `§2.11` of the plan. |
| Why this CNI / LB / runtime, not another? | `§2.8`, `§5.5`, `§12.1`, `§12.2` of the plan. |
| What does each role / chart actually do? | [`09-roles-reference.md`](09-roles-reference.md), [`10-modules-and-charts.md`](10-modules-and-charts.md). |
| What is the deployment workflow? | [`07-deployment-guide.md`](07-deployment-guide.md). |
