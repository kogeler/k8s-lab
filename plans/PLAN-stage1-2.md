This file owns §15: Phases 3.5 + 4 — bootstrap management cluster.
The §N numbering is continuous across all plan files; cross-references
of the form `§<number>` are valid without naming the file — see the
`PLAN-stage1-common.md` header for the full file lineup. The atomic
scope of this shard is everything needed to take a bare LXC bootstrap
instance and produce a working management cluster with the CAPN
provider (binary fetch, k3s, clusterctl init, CAPN identity secret,
API publishing, artifacts).

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)  <-- this file
PLAN-stage1-3.md ................. §16      (workload_cluster TF module: CAPI topology + add-ons + acceptance)
PLAN-stage1-4.md ................. §17      (Helm test contracts — Gate A + Gate B chart-side specs)
PLAN-stage1-5.md ................. §18      (pivot mgmt-1 → self-hosted)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 closure + self-review + recommendation)
```

---

# 15. Phases 3.5 + 4 — Bootstrap management cluster

This section groups everything needed for standing up the bootstrap
management cluster in LXC: the roles (§15.1..§15.6) and the phases
themselves — 3.5 (binary_fetch, pushed out of Phase 1) and 4
(k3s + clusterctl + CAPN identity secret + API publish + artifacts
export).

## 15.1. Role: `binary_fetch`

**Status: done in Step 4 (2026-04-22) — the full description, deviation
notes and checksum-style breakdown live in §13.8.**

Downloads into `/opt/capi-lab/bin`:

* `kubectl`
* `clusterctl`
* `k3s`

Requirements:

* version pinning (tracks the §8a verified version log)
* checksum verification (see the §13.8 implementation note about the
  three checksum styles: `plain` / `manifest` / `pinned`)
* no custom apt repos
* deterministic owner/group/mode

## 15.2. Role: `bootstrap_k3s`

**Status: done in Step 4 (2026-04-22) — the full description,
substrate-required hardcoded flags, execution-model rationale
(`lxc exec` shell instead of the `community.general.lxd` connection
plugin) and end-to-end verify live in §13.9. Step 4 also required
substrate extensions in §13.3 / §13.6 (interception=allow,
unix-char=allow, `/dev/kmsg` device, syscalls.intercept.*,
raw.lxc apparmor=unconfined, restart-on-profile-change) — see
their Step 4 deviation sections.**

Inside the bootstrap LXC:

* lays down `k3s` (kubectl / clusterctl stay on the host, consumed
  by `bootstrap_clusterctl` §15.3 in subsequent Steps);
* starts `k3s server` with:

  * `--disable-cloud-controller` (substrate-required, hardcoded)
  * `--kubelet-arg=feature-gates=KubeletInUserNamespace=true`
    (substrate-required, hardcoded)
  * `--disable=servicelb` (default)
  * `--disable=traefik` (default)
  * `--tls-san <host IP/FQDN>` optionally via
    `bootstrap_k3s_tls_san: []`
  * `--cluster-cidr` / `--service-cidr` optionally (Step 4 did not
    require them — k3s defaults were sufficient)

K3s docs and FAQ explicitly support disabling packaged components like `traefik` and `servicelb`, and `server` docs support `--tls-san`. ([K3s][18])

## 15.3. Role: `bootstrap_clusterctl`

**Status: done in Step 6 (2026-04-23) — the full description,
implementation notes (k8s_info native-first, idempotence pre-check
against an existing CAPN deployment, async clusterctl init, server URL
rewrite in the host-side kubeconfig, jsonpath quirk for CAPI Provider CR
top-level fields), substrate-required values in `vars/main.yml`
live in §13.10.**

Does the following:

* lays down the pinned `clusterctl.yaml`;
* runs `clusterctl init --infrastructure incus[:version]`;
* enables `CLUSTER_TOPOLOGY=true` if we use the CAPN default
  ClusterClass/topology;
* materialises a host-side kubeconfig from the in-container `k3s.yaml`
  with `clusters[].cluster.server` rewritten to the container-eth0
  IPv4.

`clusterctl init` automatically installs core, kubeadm bootstrap and kubeadm control-plane providers; the clusterctl config file supports repository and cert-manager overrides. ([main.cluster-api.sigs.k8s.io][7])

## 15.4. Role: `bootstrap_capn_secret`

The full description (cross-section invariants, native-first execution,
idempotence model, substrate-required values, cleanup contract) is in
§13.11.

Phase-level summary:

* Materialise the CAPN identity Secret in **every** workload-cluster
  namespace from `k8s_lab_capn_identity_namespaces` (§8 default
  `["capi-clusters"]`). 5 substrate-required keys per CAPN
  identity-secret format ([capn.linuxcontainers.org][19]):
  `server`, `server-crt`, `client-crt`, `client-key`, `project`.
  The label `clusterctl.cluster.x-k8s.io/move: "true"` is present by
  default (`bootstrap_capn_secret_pivot_enabled=true`, canonical
  flow §3 — pivot mandatory).
* Architectural truth (verified by Step 11 chart-level acceptance):
  CAPN v1alpha2 `LXCCluster.spec.secretRef` looks up the Secret in the
  namespace of the LXCCluster CR; cross-ns lookup is not supported.
  Therefore the Secret MUST live in the namespace of each workload
  Cluster CR (we do NOT place it in the controller's namespace — CAPN
  does not read it from there).
* Additionally, the role owns two host/LXD-level operations
  (minimally invasive scope, does not overlap with lxd_host's
  snap/socket ownership):
  * PATCH `core.https_address: <bridge-ipv4>:8443` on the LXD daemon —
    binding only to the `k8s_lab_internal_network_name` LXD-managed
    bridge IP, so that CAPN inside the bootstrap LXC can reach
    `/1.0/...` through the project's internal subnet while nothing is
    exposed on the host's external NICs;
  * registration of the client TLS cert as a `restricted: true +
    projects: ["{{ k8s_lab_project_name }}"]` trust entry — CAPN
    cannot touch other projects even if operator-owned LXD entities
    exist outside `k8s_lab_project_name`.

Public defaults sourced from §8 globals (single-source-of-truth for
coordination with Phase 5+ Cluster CR's `identityRef`, the
`clusterctl move` workflow and chart consumers):

* `bootstrap_capn_secret_name ← k8s_lab_infrastructure_secret_name`;
* `bootstrap_capn_secret_namespaces ← k8s_lab_capn_identity_namespaces`;
* `bootstrap_capn_secret_pivot_enabled` defaults to `true` (canonical
  flow §3, pivot mandatory);
* `bootstrap_capn_secret_lxd_project ← k8s_lab_project_name`;
* `bootstrap_capn_secret_internal_network_name ←
  k8s_lab_internal_network_name`.

## 15.5. Bootstrap API publication (LXD proxy device, not a separate role)

Earlier Stage 1 contained a separate role `bootstrap_api_publish` that
deployed an nftables DNAT + ACL on top of the host firewall. This
solution was removed in Step 7 (2026-04-23) for two reasons:

* **Host firewall — out of scope for this repo** (see §11.4). In
  production the host firewall is the operator's property; the role
  has no right to write to distro-owned nftables tables, even into an
  isolated `table inet k8slab_api_publish`.
* **Source-IP ACL is redundant on top of mTLS** of the kubeconfig.
  The bootstrap API always requires a client cert; an additional
  IP filter provides no useful protection and doubles the error
  surface.

Publishing the bootstrap container's TCP port outward (if the operator
wants to expose the API, for example for Terraform from a dev machine)
is implemented **declaratively via an LXD proxy device** managed by
the already existing `lxd_bootstrap_instance` role (§13.7). The role
passes any dictionary `lxd_bootstrap_instance_devices` to the native
module `community.general.lxd_container`, which patches the instance's
live config via the LXD REST.

Example host_vars publishing the k3s API on `<host>:16443`:

```yaml
lxd_bootstrap_instance_devices:
  k3s-api:
    type:    proxy
    listen:  "tcp:0.0.0.0:16443"
    connect: "tcp:127.0.0.1:6443"
    bind:    host    # LXD daemon listens on the host, forwards into the container
```

Semantics of the proxy device with bind=host:

* The LXD daemon raises a userspace listener on `<listen>` on the host,
  accepts connections and does `connect()` into the container at
  `<connect>`. No rules in distro-owned nftables.
* On `lxc delete` of the container or `lxc config device remove` the
  listener is torn down automatically. Rollback is zero-code.
* A source-IP filter, if it is really needed in a specific environment,
  is a job for the external host firewall of the consumer repo (for
  example an `iptables`/`ufw`-based operator role), not for the
  Stage 1 substrate.

The LXD proxy device also supports `bind: instance` (listener inside
the container) and `nat: true` (LXD itself sets up a kernel DNAT in
ITS OWN isolated nftables table). For the Stage 1 lab the simplest
`bind: host` is enough for us.

## 15.6. Role: `export_artifacts`

**Status: done in Step 8 (2026-04-23) — the full description,
execution model (`delegate_to: localhost` with `become: false + run_once:
true` for runner-side files), substrate-required filename conventions
+ file mode contract, the idempotent slurp+copy pattern, optional
server URL rewrite (runner-reach handling via the public
`export_artifacts_mgmt_api_server_url`), the Phase 5 smoke-test via
`kubernetes.core.k8s_info` from the verify scenario — live in §13.12.
The end-to-end run is green (2026-04-23).**

Stage 1 scope:

* `.artifacts/mgmt.kubeconfig` — the single admin kubeconfig of the
  active management cluster. On the first include of the role (through
  the meta-chain) it points to the bootstrap k3s — shipped from the
  host out of the internal staging of the `bootstrap_clusterctl` role
  §15.3, mode 0600 on the runner. On the second include of the role
  with `export_artifacts_run_meta_chain: false` + source-override to
  the pivot host-side staging — the same runner-side file is overwritten
  in place with mgmt-1 credentials (canonical flow §3, pivot mandatory);
* `.artifacts/mgmt.auto.tfvars.json` — a fact-bundle for Phase 5
  Terraform fixtures (TF auto-loads `*.auto.tfvars.json` by glob);
  the keys mirror the §8 `k8s_lab_*` globals 1:1 plus the derived
  `k8s_lab_mgmt_kubeconfig_path` / `k8s_lab_mgmt_api_server_url`;
* `.artifacts/clusters/` — an empty subdir, reserved for per-workload
  debug copies written by the Molecule e2e-local verify.yml
  (raw Secret content, internal endpoint — not rewritten). The TF
  module §16.4 does not write into this subdir (see the §16.4
  architectural fence); the module keeps the rewritten kubeconfig in
  state and emits it via `terraform output -raw kubeconfig`.

## 15.7. Phase 3.5 — binary_fetch (deferred from Phase 1)

**Status: done in Step 4 (2026-04-22) — see §14.5.**

Moved out of Phase 1 in Step 2 — kubectl / clusterctl / k3s are first
needed only at Phase 4 (`bootstrap_k3s`). See §15.1 / §13.8.

Done:

* pinned versions of `kubectl`, `clusterctl`, `k3s` downloaded into
  `/opt/capi-lab/bin` with checksum verification.

Acceptance: reached (see §14.5).

## 15.8. Phase 4 — bootstrap management cluster

**Status: done in Step 4 + Step 6 + Step 8 — see §14.6.**
`bootstrap_k3s` is ready as of Step 4; `bootstrap_clusterctl` +
`bootstrap_capn_secret` are ready as of Step 6. The separate role for
publishing the API (§15.5) was removed in Step 7 (2026-04-23) —
replaced by an LXD proxy device on top of `lxd_bootstrap_instance`.
In Step 8 `export_artifacts` was implemented (§13.12 / §15.6) along
with the `tls-server-name` pin in `bootstrap_clusterctl`
(§13.10 Step 8 deviation) — the runner now genuinely reaches the API
through the LXD proxy on the VM host with a cryptographically clean
TLS identity (no IP in the cert, no `insecure-skip-tls-verify`).

Roles:

* `bootstrap_k3s` ✓ (Step 4 — §13.9)
* `bootstrap_clusterctl` ✓ (Step 6 + Step 8 — §13.10)
* `bootstrap_capn_secret` ✓ (Step 6 — §13.11)
* ~~`bootstrap_api_publish`~~ — removed, §15.5
* `export_artifacts` ✓ (Step 8 — §13.12)

Acceptance (entire phase) — **closed** 2026-04-23:

* `clusterctl init` done                          ✓ (Step 6)
* providers healthy                               ✓ (Step 6)
* LXD identity secret present                     ✓ (Step 6)
* bootstrap API reachable from the runner         ✓ (Step 8 — LXD
  proxy device + shipped kubeconfig with a runner-reachable URL +
  `tls-server-name` pin)
* handoff bundle shipped onto the runner (`.artifacts/mgmt.kubeconfig`
  + `.artifacts/mgmt.auto.tfvars.json`) ✓ (Step 8 — §13.12)

Acceptance of the Step 4 + Step 6 + Step 8 parts (proved by verify
scenarios, end-to-end smoke via `kubernetes.core.k8s_info` with
`delegate_to: localhost`) — see §14.6.

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
