This file owns §17: chart-side acceptance contracts for Gate A
(external L2) and Gate B (CNI viability) from §6, plus the
contract for invoking helm tests from the single `workload_cluster`
TF module (§16.4). The §N numbering is continuous across all
plan files; cross-references of the form `§<number>` are valid
without naming the file — see `PLAN-stage1-common.md` header for
the full file lineup. The atomic scope of this shard is **only
chart contracts + acceptance gates**; TF module structure +
workload-cluster orchestration live in §16.

```
PLAN-stage1-common.md ............ §1..§12  (project contract, architecture, test harness, risk catalog)
PLAN-stage1-1.md ................. §13..§14 (completed roles + phases)
PLAN-stage1-2.md ................. §15      (Phases 3.5 + 4 bootstrap management cluster)
PLAN-stage1-3.md ................. §16      (workload_cluster TF module)
PLAN-stage1-4.md ................. §17      (Helm test acceptance contracts — Gate A + Gate B chart-side specs)  <-- this file
PLAN-stage1-5.md ................. §18      (pivot mgmt-1 → self-hosted)
PLAN-stage1-6.md ................. §19      (Phase 8 destroy)
PLAN-stage1-7.md ................. §20..§22 (Stage 1 closure + self-review + recommendation)
```

---

# 17. Helm test acceptance contracts — Gate A + Gate B chart-side specs

Acceptance Gate A (external L2 viability) and Gate B (CNI viability)
from §6 are implemented as **chart-side `helm.sh/hook: test` Pods**,
shipped together with the charts that install the corresponding
component:

* Gate B — `charts/cni-calico/templates/tests/cni-ready.yaml` (Step
  13);
* Gate A — `charts/metallb-config/templates/tests/metallb-vip.yaml`
  (Step 14).

Both hooks are invoked **from inside the single TF module** of §16.4
(`terraform/modules/workload_cluster/`) via `null_resource` +
`local-exec helm test <release> --kubeconfig <workload> --logs
--timeout 15m` after the corresponding `helm_release`. A helm test
failure fails `null_resource` with a non-zero exit → TF apply
fails → state is marked tainted; a repeated apply re-runs the test
after the necessary fix. This turns the acceptance gate from
"a manual step after deploy" into a mandatory part of the deploy.

No separate probe charts (`charts/cni-probe/`,
`charts/metallb-probe/`) are shipped — chart-side hooks live
inside the same charts that own the components. If in the future
a CNI-agnostic probe is needed (for swapping to Cilium / kube-router),
a separate `charts/cni-probe/` can be introduced as
chart-independent; for now this is a DRY violation without benefit.

## 17.1. Helm test invocation contract

`null_resource.helm_test_<gate>` for each hook inside the §16.4 module:

```hcl
resource "null_resource" "helm_test_cni_calico" {
  triggers = {
    chart_version = var.cni_calico_chart_version
    release_id    = helm_release.cni_calico.id
    kubeconfig_sha = sha256(local.workload_kubeconfig)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      KUBECONFIG_FILE=$(mktemp)
      trap 'rm -f "$KUBECONFIG_FILE"' EXIT
      printf '%s' "$WORKLOAD_KUBECONFIG" > "$KUBECONFIG_FILE"
      chmod 0600 "$KUBECONFIG_FILE"
      helm test cni-calico \
        --namespace tigera-operator \
        --kubeconfig "$KUBECONFIG_FILE" \
        --logs --timeout 15m
    EOT
    environment = {
      WORKLOAD_KUBECONFIG = local.workload_kubeconfig
    }
  }

  depends_on = [helm_release.cni_calico]
}
```

Contract:

* the `helm` binary must be on the runner (where `terraform
  apply` is executed); the module does not try to install it — this
  is the responsibility of the consumer / CI image;
* the `triggers` map includes chart version + release ID + kubeconfig
  hash, which forces the null_resource to re-execute on any of the
  three changes (chart bump, release re-create, kubeconfig
  rotation). An idempotent re-run on a green cluster passes
  quickly (helm test re-creates the Pod via the `before-hook-creation`
  policy);
* the kubeconfig is written to an `mktemp` file with mode 0600 and is
  always removed on trap EXIT — keeps the runner FS clean on any outcome;
* `--timeout 15m` is a margin above the most generous chart-side timeout
  (Gate B `nodesReadyTimeoutSeconds: 600` + buffer);
* `--logs` guarantees that test Pod output appears in the TF apply log
  on failure → diagnostics do not require a manual `kubectl logs`.

The memory rule `feedback_ansible_native_first.md` is symmetric for TF:
helm test via `local-exec` is the only portable way (the helm
provider 3.x has no `helm_test` resource); idempotency is provided
through `triggers` + chart-side `hook-delete-policy`.

## 17.2. Gate B — CNI viability acceptance

**Status: shipped in Step 13 (2026-04-26, `charts/cni-calico/`
version 0.2.0); IPv6 `natOutgoing` enable bumped 0.2.0 → 0.2.1
(see substrate hardcoded list below + §3.3 + §20).** Local wrapper
over upstream
`projectcalico/tigera-operator` v3.31.5 via `Chart.yaml`
`dependencies:`. Substrate-required hardcoded values in the Installation CR
(`templates/installation.yaml`):

* `cni.type: Calico`, `ipam.type: Calico` — chart-level invariant;
* `calicoNetwork.bgp: Disabled` — no BGP infra on the CAPN/LXD
  substrate;
* `calicoNetwork.linuxDataplane: Nftables` — native nf_tables, without
  iptables compat layer; paired with kube-proxy `mode: nftables` via
  KubeProxyConfiguration in `charts/capi-cluster-class` KCPT (§16.2
  Step 13). Calico docs formulate this as a contract: kube-proxy
  must match the dataplane mode;
* `calicoNetwork.ipPools[*].encapsulation: VXLAN` — IPIP is IPv4-only,
  no BGP infra, VXLAN is the only dual-stack-capable mode;
* `calicoNetwork.ipPools[*].nodeSelector: all()` — single-tier
  lab, per-pool node tagging is not needed;
* `calicoNetwork.ipPools[*].natOutgoing: Enabled` (on both pools,
  IPv4 and IPv6) — Pod CIDRs of both families are RFC1918 / ULA, with
  no upstream routing to them. Without SNAT Pod→substrate (capi-int
  `fd42:77:1::/64`, host LXD daemon `:8443`, haproxy LB instances
  by `controlPlaneEndpoint.host`) deadlocks on the return path
  (substrate does not know Pod CIDR `fd42:77:2::/56`). Concretely
  this blocks post-pivot CAPI cluster-cache: CAPI controllers
  run in Pods on self-hosted mgmt and connect to the workload
  apiserver via LB IPv6 with Pod source IP — without natOutgoing
  LB replies are lost. The pre-pivot bug was not visible because
  bootstrap k3s = host-network mode, CAPI used the Node IPv6
  directly as source (see §3.3 for architectural symmetry
  bootstrap↔self-hosted);
* `controlPlaneReplicas: 2` — HA pair §2.12 contract for
  calico-kube-controllers + calico-apiserver (operator gives them
  2 replicas + built-in podAntiAffinity).

Subchart toggles (`tigera-operator` dependency): `installation.
enabled: false` (we render our own Installation CR), `apiServer.
enabled: true` (needed for projectcalico.org aggregated APIs),
`goldmane: false` / `whisker: false` (observability extras —
optional, off in the lab footprint). Typha remains auto-deployed
by the operator.

### Acceptance hook shape

The helm test hook `templates/tests/cni-ready.yaml` is the
chart-level acceptance driver. A single Pod, 6 PASS/FAIL phases:

1. install kubectl from dl.k8s.io (alpine + busybox `wget`);
2. tigera-operator Deployment Available;
3. calico-system rollouts + Pods Ready;
4. workload Nodes Ready=True;
5. dual-stack `podCIDRs` per-Node (`spec.podCIDRs` contains both v4
   and v6 CIDR);
6. live pod-to-pod ICMP4 + ICMP6 across two workers — the driver Pod
   creates via `kubectl apply` two ephemeral probe Pods
   (`k8s-lab-cni-probe-a/-b`) on different workers via
   podAntiAffinity + nodeAffinity NotIn control-plane, then
   `kubectl exec` ping/ping -6 from one to the other.

Image: alpine:3.21 + busybox `wget` for kubectl fetch + busybox
`ping` (-6 supported in alpine 3.21).

### RBAC / hook-policy substrate-required choices

* Test SA + ClusterRole + ClusterRoleBinding in
  `templates/tests/rbac.yaml` — **regular release resources**, NOT
  `helm.sh/hook: test`. Hook-annotated non-Pod resources break
  `helm test --logs` with a non-zero exit ("unable to get pod logs for
  <SA-name>"); helm walks the hook list and tries to fetch logs
  for each kind. SA/Role/Binding are installed at `helm install` time,
  torn down only on `helm uninstall`. ClusterRole grants:
  `core/{nodes,namespaces}` (get,list), `core/pods` (get,list,
  create,delete), `core/pods/exec` (create), `apps/{deployments,
  daemonsets}` (get,list,watch — for kubectl rollout status / wait
  gating).
* Test Pod hook-delete-policy = `before-hook-creation` only, NOT
  `before-hook-creation,hook-succeeded`. Race between `Phase:
  Succeeded` and `helm test --logs` log-fetch step: on a short
  test (~15s) hook-succeeded reaps the Pod before helm reaches
  the log pull, exit 1 with "pods not found". The Test Pod survives
  after Succeeded and is reaped via before-hook-creation on the next
  `helm test` or on `helm uninstall`.

### Step 13 acceptance status (2026-04-26)

End-to-end green on a fresh workload cluster, provisioned
via ClusterClass 0.5.0 (kube-proxy `mode: nftables` baked
declarative-style at kubeadm init, see §16.2 Step 13). Run with the
sequence `make clean-local` → `make up` → `make -C
tests/molecule e2e-local-vagrant-converge` → `e2e-local-vagrant-verify`:

* converge — `failed=0 ok=307 changed=4`. Task chain: substrate
  + bootstrap k3s → ClusterClass 0.5.0 + workload-cluster 0.5.0
  → helm CLI install on VM, Chart.yaml slurp, `helm dependency
  update` + `helm package` on the runner, copy .tgz to the VM, poll
  the `<cluster>-kubeconfig` Secret in bootstrap, materialize the workload
  kubeconfig at `/opt/capi-lab/etc/<cluster>.kubeconfig` on the VM,
  `helm install cni-calico` on the VM. All chart helm tasks via
  `kubernetes.core.helm`.
* verify — `failed=0 ok=14 changed=4`. Workload-chart `helm test`
  10-phase → `cp=3/3 worker=2/2 ALL TOPOLOGY CHECKS PASSED`,
  `classRef=capn-default-0-5-0`, AVAILABLE=True. cni-calico
  `helm test` 6-phase → `Phase: Succeeded`: tigera-operator
  Available, calico-node DS + calico-kube-controllers rolled out,
  all Pods in calico-system Ready, all 5 workload Nodes
  Ready=True, dual-stack `podCIDRs` per-Node, dual-stack
  ICMP4/ICMP6 between ephemeral probe Pods on different worker nodes
  via `kubectl exec`.

Chart-level live evidence on a freshly-bootstrapped cluster:
the kube-proxy ConfigMap contains `mode: nftables` +
`conntrack.{maxPerCore: 0, min: 0}` directly from kubeadm init (without
ConfigMap patches), all 5 kube-proxy Pods Running 0 restarts.

TF module §16.4 wrapper integration shipped in Step 16 (2026-04-28 —
see §16.4 / §16.6) — `null_resource.helm_test_cni_calico` invokes
this hook via the `helm test` `local-exec` provisioner inside the same
`terraform apply` as `helm_release.cni_calico`. A hook failure
fails the TF apply (PLAN §17.1 invocation contract).

## 17.3. Gate A — External L2 viability acceptance

**Status: shipped in Step 14 (2026-04-27, `charts/metallb-config/`
version 0.1.3 + `charts/metallb/` version 0.1.0).**

Two-release pair (see §16.4 module helm_release chain):

* `charts/metallb/` — minimal subchart wrapper over upstream
  `metallb/metallb` 0.15.3 ([27]). Upstream version is pinned in Chart.yaml
  `dependencies:` block (§8 `k8s_lab_metallb_chart_version`).
  values.yaml hardcodes substrate-required toggles
  (`crds.enabled: true`, `frrk8s.enabled: false`,
  `speaker.frr.enabled: false`, `speaker.tolerateMaster: true`).
  Wrapper-owned templates: none — the chart exists only to
  ship the upstream subchart with pinned values per the memory rule
  "Chart-required values are hardcoded";
* `charts/metallb-config/` — wrapper-owned IPAddressPool +
  L2Advertisement CRs + helm test driver Pod (Gate A acceptance).
  Binds §8 `k8s_lab_metallb_vip_range_v6` +
  `k8s_lab_metallb_interface` +
  `k8s_lab_metallb_node_selector_labels`. No subchart deps.

Two-release split rationale: upstream metallb 0.15.3 ships CRDs
as regular `templates/crds/` (sub-dependency), not the Helm
`crds/`-folder mechanism. A single-release wrapper with CRDs+CRs fails
Helm 3 pre-apply manifest validation with `no matches for kind
"IPAddressPool"`. The split separates CRDs registration (release 1) from
CR reconciliation (release 2).

**HA pair contract §2.12 deviation specific to MetalLB:** upstream
`metallb` chart 0.15.3 does NOT expose `controller.replicas` —
the controller is a singleton by upstream design (allocates VIPs from the pool
+ validates CRs, no state partitioning). HA is delivered through
the **speaker DaemonSet** (one replica per worker, leader-elected
per-VIP via memberlist gossip).

### Acceptance hook shape

The helm test hook `metallb-config/templates/tests/metallb-vip.yaml`
is the chart-level acceptance driver. A single Pod, 8 PASS/FAIL phases:

1. install kubectl from dl.k8s.io;
2. metallb controller Deployment Available (label-selector
   `app.kubernetes.io/component=controller`, release-name agnostic);
3. metallb speaker DaemonSet rolled out;
4. tear down stale demo Deployment + Service from prior run
   (idempotent re-runs);
5. apply demo Deployment (nginx-on-alpine, dual-family `listen 80;
   listen [::]:80;` via inline `sed` on default.conf) + Service
   type=LoadBalancer, `ipFamilies: [IPv6]` single-stack;
6. backend Pod Ready;
7. `Service.status.loadBalancer.ingress[0].ip` allocated AND
   in-pool (string-prefix sanity vs `pool.rangeV6`);
8. in-cluster HTTP probe FROM the driver Pod (`wget [VIP]:80`).
   **Non-hairpin path**: the driver Pod is not an endpoint of the Service;
   kube-proxy nftables DNAT short-circuits via
   `mark-for-masquerade`+DNAT in the `endpoint-...` chain.
   A `kubectl exec backend-pod -- wget VIP` variant would be hairpin
   (Calico default veth filter drops backend-to-self-via-Service).

### Demo backend image rationale

`nginx:1.27-alpine` (not alpine + busybox httpd) — because:

1. alpine's base busybox build does not include the httpd applet (it lives in
   the `busybox-extras` package — would require apk-add at boot,
   flaky on fresh clusters with slow egress);
2. Service `ipFamilies: [IPv6]` requires a v6-listening backend;
   nginx default config has only `listen 80;` (v4); the chart
   driver adds `listen [::]:80;` via inline `sed` on
   default.conf, keeping the rest intact.

Memory rule "Never use bitnami images" — nginx Inc. official, not
bitnami.

### External-segment acceptance (verify-side)

The chart-side hook closes only the in-cluster path to the VIP. The full
Gate A path — **external curl from an endpoint outside the cluster** —
is closed **fixture-side / consumer-side**:

* In the local Vagrant harness: the Molecule e2e-local verify task on the VM
  (NOT delegate_to runner) does `ansible.builtin.uri
  url=http://[<VIP>]:80/` via `ext6-ra-peer`
  (`2001:db8:42:100::1/64`) → bridge `br-ext6` → eth1 speaker
  leader → kube-proxy DNAT → backend Pod;
* In the TF module §16.4: the chart-side helm test via `null_resource` is
  the in-cluster gate; for a consumer who wants an external check,
  the module emits `output "metallb_vip"` which the consumer can
  curl via their external probe endpoint.

The demo Deployment + Service are driver-managed (created by the driver Pod
via `kubectl apply`, not annotated `helm.sh/hook: test`) —
they survive `Phase: Succeeded` and are available for external probing.
They are reaped on the next `helm test` (driver Pod's phase [4/8]
cleanup) or on `helm uninstall`.

### Step 14 acceptance status (2026-04-27)

End-to-end green on a fresh workload cluster, provisioned
via ClusterClass 0.5.0 + workload-cluster 0.5.0 + cni-calico
0.2.0 + metallb 0.1.0 + metallb-config 0.1.3.

Run `make -C tests/molecule e2e-local-vagrant-converge` →
`make -C tests/molecule e2e-local-vagrant-verify`:

* converge — `failed=0 ok=318 changed=7`. Task chain: existing
  substrate + bootstrap + ClusterClass + workload + Calico → new
  MetalLB delivery block (read Chart.yaml → helm dep update + helm
  package on the runner → copy .tgz to the VM → helm install on the VM via
  `kubernetes.core.helm`). Two helm installs: upstream metallb
  wrapper (`metallb-system` namespace, `create_namespace: true`),
  then metallb-config wrapper (`create_namespace: false`).
* verify — `failed=0 ok=20 changed=5`. Three helm tests green:
  workload chart (10 phases), cni-calico (6 phases), metallb-config
  (8 phases). Compact-state debug:
  `metallb VIP=2001:db8:42:100::200 external_status=200`. Full
  Gate A path: external curl from VM → `ext6-ra-peer` → bridge
  `br-ext6` → eth1 speaker leader → kube-proxy → backend nginx Pod
  → 200 OK body "ok\n".

Memory rules applied in Step 14:
* `feedback_chart_required_values_hardcoded.md` — IPAddressPool /
  L2Advertisement substrate-required fields in templates;
* `feedback_no_bitnami_images.md` — alpine for driver Pod, nginx
  for backend (no bitnami);
* `feedback_test_artifact_naming.md` — `k8s-lab-metallb-demo-*`
  prefix for the demo stack;
* `feedback_pause_before_role_test.md` — chart code done, tests
  revealed nginx v4-only listen + hairpin avoidance fixes;
* `feedback_plan_is_fallible.md` — single-wrapper precedent
  was attempted to apply here, but the architecture of the metallb subchart CRDs
  (templates/crds/, not Helm crds/) requires a two-release split.
  PLAN was right in the original two-release design; confirmed
  again via runtime evidence.

TF module §16.4 wrapper integration shipped in Step 16 (2026-04-28 —
see §16.4 / §16.6) — `null_resource.helm_test_metallb_config` invokes
the chart-side hook via the `helm test` `local-exec` provisioner inside
the same `terraform apply` as `helm_release.metallb_config`.
The verify-side external curl from the Vagrant VM to the MetalLB-allocated VIP
via `ext6-ra-peer` lives in `tests/molecule/e2e-local/verify.yml`
and is executed during the e2e-local run (§14.7 Step 16 acceptance).

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
