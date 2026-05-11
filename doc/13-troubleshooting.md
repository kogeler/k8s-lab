# 13 — Troubleshooting

A recipe-style operator manual for failures that actually came out of
building Stage 1. Every recipe is grounded in a real deviation
recorded in `plans/PLAN-stage1-*.md`; nothing here is speculative.

Each recipe has four blocks: **Symptom** (what you see), **Likely
cause** (observed root cause), **Diagnose** (read-only commands), and
**Fix** (smallest action that returns you to the canonical flow).
Plan citations (`§N.x`) point at the source-of-truth section. If a
recipe and the plan disagree, the **plan wins**.

Organised by phase boundary: Substrate (0..3) → Bootstrap (4) →
Phase 5 helm / TF → Pivot (7) → kube-proxy / MetalLB → image /
cloud-init → diagnostic recipes → reset.

---

## Substrate (Phase 0..3) issues

### LXD storage pool: "device contains existing filesystem signature"

**Symptom.** `lxd_storage_pools` fails with an `mkfs.btrfs` error like
`appears to contain an existing filesystem` (xfs / ext4 / LVM2_member /
…). No pool is created.

**Likely cause.** The block device in
`lxd_storage_pools_pools[].source` carries a stale signature. LXD runs
`mkfs.btrfs` **without** `-f` — the role contract is "hand LXD a clean
device".

**Diagnose.**

```sh
sudo wipefs /dev/disk/by-id/<your-device>
sudo blkid  /dev/disk/by-id/<your-device>
```

Any non-empty output means leftover signatures.

**Fix.** `sudo wipefs -af /dev/disk/by-id/<your-device>`, then re-run.
The Molecule shared task `prepare-clean-disk.yml` does this for the
local harness; prod hosts ship a clean disk via the installer image.
See plan `§13.4` Deviations.

### "Numerical result out of range" creating a libvirt bridge

**Symptom.** `virsh net-define` /
`make -C tests/vagrant/debian13 networks` / Vagrantfile triggers fail
with `error creating bridge interface: Numerical result out of range`.
The VM never comes up.

**Likely cause.** Linux `IFNAMSIZ` ≤15 chars. Names like
`virbr-k8slab-mgmt` (17 chars) are rejected by
`ioctl(SIOCBRADDBR)`.

**Diagnose.**

```sh
grep -r '<bridge ' tests/vagrant/debian13/libvirt-networks/
```

Any `name=` longer than 15 chars is the offender.

**Fix.** Use the shipped short names (`k8slab-mgmt`, `k8slab-ext6`,
`k8slab-probe` — all ≤12 chars). XML files in `tests/vagrant/debian13/`
carry header comments documenting this. See plan `§9.2 Step 1
deviation`.

### `vagrant-libvirt` fails on IPv6-only network: "undefined method 'to_range' for nil"

**Symptom.** `vagrant up` aborts with `NoMethodError: undefined method
'to_range' for nil` inside `vagrant-libvirt`'s `private_network`
plumbing. Specifically on networks intended to carry only IPv6.

**Likely cause.** The plugin's validator unconditionally computes a
DHCPv4 range. No `<ip family="ipv4">` element → `nil.to_range` →
crash.

**Diagnose.** `virsh net-dumpxml k8slab-ext6 | grep '<ip'` — if you
only see `family="ipv6"`, the plugin crashes.

**Fix.** Add a minimal **RFC 5737 TEST-NET-1** (`192.0.2.0/30`) IPv4
block to the network XML — traffic-free, just enough for the
validator. Also pin `type: "dhcp"` on the IPv6-only NIC in the
Vagrantfile; otherwise the plugin's auto-configure crashes the same
way. See plan `§9.2 Deviations`.

### `synced_folder "/vagrant"` requires interactive sudo on host

**Symptom.** `make -C tests/vagrant/debian13 up` blocks on an
interactive `sudo` prompt on the **host** when `vagrant-libvirt`
exports the NFS share backing
`/vagrant`. Unattended runs hang.

**Likely cause.** Default `vagrant-libvirt` syncs the project root to
`/vagrant` via NFS, which edits `/etc/exports` via `sudo`. Nothing in
the VM reads `/vagrant` — Ansible drives via SSH — so the export is
pure cost.

**Diagnose.** `grep -n synced_folder
tests/vagrant/debian13/Vagrantfile` — if you do not see `disabled:
true`, the export is wired up.

**Fix.** Disable in the Vagrantfile:

```ruby
config.vm.synced_folder ".", "/vagrant", disabled: true
```

Canonical change in Step 8 — saves first-boot time and removes the
host-side sudo prompt. See plan `§9.2 Step 9`.

---

## Bootstrap (Phase 4) issues

### `clusterctl init` fails with "already an instance of <provider>"

**Symptom.** Re-running `bootstrap_clusterctl`, or `clusterctl init`
manually, fails with `Error: there is already an instance of "incus"
InfrastructureProvider installed in the "capn-system" namespace`. The
play stops on the init task.

**Likely cause.** `clusterctl init` is **not idempotent** at the CLI
level — all-or-nothing.

**Diagnose.**

```sh
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig \
  -n capn-system get deploy capn-controller-manager
```

If the Deployment exists, init has already happened.

**Fix.** Nothing to do — the role's `kubernetes.core.k8s_info`
pre-check against `capn-system/capn-controller-manager` skips the init
task on every subsequent run; canonical re-converge yields
`changed=0`. Do **not** delete providers by hand to "force a clean
init"; you will desync the rest of the role's state. See plan `§13.10`
Implementation notes.

### Bootstrap kubeconfig points at 127.0.0.1

**Symptom.** `kubectl --kubeconfig=.artifacts/mgmt.kubeconfig get
nodes` from the runner fails with `dial tcp 127.0.0.1:6443: connect:
connection refused`. The k3s server in the bootstrap LXC is healthy.

**Likely cause.** k3s' default `server: https://127.0.0.1:6443` is
correct only from the container's own POV. The
`bootstrap_clusterctl` role is the component that rewrites this URL
when materialising the host-side kubeconfig.

**Diagnose.** `grep server .artifacts/mgmt.kubeconfig`. Expect either
`https://<bootstrap-eth0-ipv4>:6443` (default) or
`https://<host-ip>:16443` if `lxd_bootstrap_instance_devices.k3s-api`
is set (LXD proxy device).

**Fix.** Re-run `bootstrap_clusterctl` — its rewrite is byte-stable
and idempotent. For runner reach from outside the LXD host, set
`export_artifacts_mgmt_api_server_url:
"https://<reachable>:16443"` and add the `k3s-api` proxy device on
`lxd_bootstrap_instance` (plan `§15.5`). The kubeconfig already pins
`tls-server-name: kubernetes.default.svc`, so TLS verifies regardless
of which URL you use. See plan `§13.10` Step 8 extensions.

### CAPN identity Secret not found by CAPN controller

**Symptom.** A workload `Cluster` CR is stuck in `Provisioning`. CAPN
controller logs show repeated `failed to get LXCCluster identity
Secret: secrets "<name>" not found`. The Secret **does** exist —
elsewhere.

**Likely cause.** CAPN v1alpha2 looks up the identity Secret in the
**same namespace as the LXCCluster CR**. There is no cross-namespace
lookup. Placing it only in `capn-system` (as some older docs suggest)
will not work for a Cluster in `capi-clusters`.

**Diagnose.**

```sh
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig get clusters,lxcclusters -A
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig \
  -n <cluster-ns> get secret <k8s_lab_infrastructure_secret_name>
```

Missing in `<cluster-ns>` → this recipe.

**Fix.** Add every workload-cluster namespace to
`k8s_lab_capn_identity_namespaces` (default `["capi-clusters"]`) and
re-run `bootstrap_capn_secret`. The role fans the Secret out via
server-side apply, idempotent on re-runs, and cleans stale Secrets at
teardown. See plan `§13.11` and `§15.4`.

### k3s dual-stack node-IP not picked up

**Symptom.** Bootstrap k3s crash-loops; kube-router logs say
`Shutdown request received: failed to start networking: unable to
initialize network policy controller: IPv6 was enabled, but no IPv6
address was found on the node`. systemd shows `Restart=always`
flapping.

**Likely cause.** kubelet auto-detects **one** address from the
default route — IPv4 only — even when `eth0` has both v4 and global
v6. Under dual-stack `--cluster-cidr`, k3s' embedded controllers
refuse to start without a v6 node-IP.

**Diagnose.**

```sh
sudo lxc shell capi-bootstrap-0 --project capi-lab
ip -o addr show dev eth0
systemctl cat k3s.service        # ExecStart should call k3s-server-launcher
journalctl -u k3s.service -n 200
```

`ExecStart=k3s server …` directly (not the launcher wrapper) → wrapper
is missing.

**Fix.** `bootstrap_k3s` drops a wrapper at
`/usr/local/sbin/k3s-server-launcher` that resolves `eth0`'s global v4
+ v6 at start and exec's `k3s server --node-ip=<v4>,<v6> "$@"`.
Re-converge the role to put it back. Do **not** try to set `--node-ip`
via `EnvironmentFile` / `ExecStartPre` — systemd loads
EnvironmentFile **once** before any `Exec*`, before the address is
known. See plan `§13.9` `--node-ip` Implementation note.

### `disable-cloud-controller` missing → bootstrap k3s crash-loops

**Symptom.** Bootstrap k3s in an unprivileged LXC crash-loops with
RBAC errors about `extension-apiserver-authentication`; systemd shows
`activating → failed → activating`.

**Likely cause.** k3s' embedded cloud-controller-manager hits a known
race (`k3s-io/k3s#7328`) in unprivileged LXC — CCM tries to read the
`extension-apiserver-authentication` configmap before
`poststarthook/rbac/bootstrap-roles` creates the RoleBinding. CCM
exits, k3s shuts down, systemd restarts, loop forever.

**Diagnose.**

```sh
sudo lxc shell capi-bootstrap-0 --project capi-lab
journalctl -u k3s.service -n 200 | grep -i 'cloud-controller\|extension-apiserver'
systemctl cat k3s.service | grep -- '--disable-cloud-controller'
```

Missing `--disable-cloud-controller` → this recipe.

**Fix.** The `bootstrap_k3s` template hardcodes
`--disable-cloud-controller`. Re-converge; do **not** strip this flag
via overrides. See plan `§13.9` substrate-required flags.

---

## Phase 5 / Helm / Terraform issues

### `helm upgrade` rejected: "admission webhook denied: field is immutable"

**Symptom.** `terraform apply` (or manual `helm upgrade`) on
`capi-cluster-class` / `capi-workload-cluster` aborts with `admission
webhook "validation.cluster.x-k8s.io" denied the request: ...:
Forbidden: field is immutable`.

**Likely cause.** Once a Cluster CR has referenced a ClusterClass +
`*Template` set, CAPI's admission webhook forbids editing most fields.
Naïve `helm upgrade` with changed values hits the webhook.

**Diagnose.**

```sh
helm --kubeconfig=.artifacts/mgmt.kubeconfig list -A | grep -E 'class|cluster'
helm --kubeconfig=.artifacts/mgmt.kubeconfig get values <release>
```

Confirm the changed values land on a CAPI template field.

**Fix.** Bump `Chart.yaml: version:`. The chart-version-as-CR-name
pattern (`metadata.name = "{prefix}-{Chart.Version | replace "." "-"}"`)
makes Helm create a fresh ClusterClass + `*Templates` under new names;
the workload Cluster CR derives its reference from the same slug by
reading the workload chart's
`Chart.yaml.annotations.k8s-lab.io/capi-cluster-class-chart-version`
pin. The Terraform module only echoes the rendered name in outputs.
Old objects live until cleanup; `helm rollback` restores the previous
pair. See plan `§2.9` and `§12.10`.

### `helm install metallb-config` Pods Pending on NotReady Nodes

**Symptom.** `terraform apply` hangs on the MetalLB releases; pods
remain `Pending`; nodes are `NotReady` with `container runtime network
not ready`.

**Likely cause.** CNI install (`tigera-operator`) is async: the
operator Deployment goes Available before it has reconciled the
Calico Installation CR + calico-node DaemonSet. `helm install --wait`
only blocks on the operator Deployment, not on the data plane. The
next Helm release schedules pods before nodes go Ready, and they
stick.

**Diagnose.**

```sh
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig get nodes
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig \
  -n calico-system get installation default -o yaml
```

`Installation/default` not Ready → CNI still coming up.

**Fix.** Insert an explicit Nodes-Ready poll
(`kubernetes.core.k8s_info`) between the CNI and MetalLB installs.
The `e2e-local` converge already does this; mirror it in custom
playbooks. The `cni-calico` Gate B helm-test hook is the secondary
barrier — let it run between releases. See plan `§3` step 3.

### `terraform apply` fails on `helm test ... Job exit 1` (Gate B / CNI)

**Symptom.** `terraform apply` runs the `cni-calico` install, then a
`null_resource` calling `helm test cni-calico` returns non-zero with
`Error: pod cni-calico-test-* failed`. Gate B has fired.

**Likely cause.** CNI bring-up is not viable. The unprivileged-LXC
substrate is **fixed** in this repo (plan `§2.8`); the variable is
almost always the CNI itself — kernel modules, BPF, NetworkPolicy
mode, IPv6 handling. The shipped Calico config covers the known cases
(`vxlan` + `nf_tables` data plane, `natOutgoing: Enabled` for both
families); local edits often regress one.

**Diagnose.**

```sh
KUBECONFIG=.artifacts/mgmt.kubeconfig kubectl -n calico-system \
  logs ds/calico-node --tail=400
KUBECONFIG=.artifacts/mgmt.kubeconfig kubectl get pods -A -o wide \
  | grep -v Running
sudo lxc info <node-LXC> --project capi-lab --show-log
```

Look for missing kernel modules (`vxlan`, `nf_tables`,
`nf_conntrack`), AppArmor denials, namespace permission errors.

**Fix.** Diagnose the root cause first. Common cases: a profile lost
`linux.kernel_modules` (`vxlan`, `nf_tables`) → fix `lxd_profiles`; a
consumer override removed `nf_conntrack` from `base_system` extras →
restore baseline; a stealth CNI swap → revert.

A real CNI swap is a deliberate design step: new wrapper chart under
`charts/`, plus a new `cni_*` input on the `workload_cluster` Terraform
module signature. **Not** a runtime toggle. See plan `§2.8`, `§12.2`,
`§13.6`.

### External Gate A curl from VM fails

**Symptom.** The `metallb-config` helm-test hook PASSes, but verify-side
`curl http://[<VIP>]:80/` from the Vagrant VM fails with `No route to
host` / `Network is unreachable`. Only the external acceptance fails.

**Likely cause.** External IPv6 segment is not actually carrying
traffic between VIP-holding node and probe. Two recorded regressions:

1. `radvd` (in-VM RA source on `ext6-ra-peer`, plan `§9.2 Step 9`) is
   not running — node `eth1` has no global IPv6 to bind the VIP to.
2. `br-ext6` is up but does not see the in-VM RA peer — the
   `ext6-ra` ↔ `ext6-ra-peer` veth is broken or never created.

**Diagnose.**

```sh
# On the worker that holds the MetalLB VIP:
sudo lxc shell <speaker-leader-node> --project capi-lab
ip -6 addr show dev eth1            # expect 2001:db8:42:100::/64

# On the Vagrant VM:
ip link show ext6-ra-peer
sudo systemctl status radvd
sudo tcpdump -i ext6-ra-peer 'icmp6 && ip6[40] == 134' -n -c 5
```

Only `fe80::/64` on `eth1` → RA reception is broken upstream.

**Fix.**

- Re-run `tests/molecule/shared/tasks/ext6-ra-source.yml` (auto-run by
  every scenario's `prepare.yml`); it recreates the veth, the radvd
  config, and starts the daemon.
- Confirm `lxd_host_ext_bridge_uplink: ext6-ra` in shared group_vars
  — `br-ext6` enslaves `ext6-ra` so RAs reach every container's
  `eth1`.
- Prod: confirm the upstream router actually sends RA (`tcpdump` from
  the host's uplink NIC).

See plan `§9.2 Step 9 pivot`.

### CAPN simplestreams 404 on requested k8s version

**Symptom.** Workload Cluster never gets nodes; CAPN logs say `Failed
getting image: The requested image couldn't be found for fingerprint
"kubeadm/v1.32.1"`.

**Likely cause.** CAPN's default simplestreams server
(`https://images.linuxcontainers.org/capn/`) publishes only `<minor>.0`
plus a small curated set of patch releases. Arbitrary patches 404.

**Diagnose.**

```sh
curl -sSL https://images.linuxcontainers.org/capn/streams/v1/images.json \
  | jq '.products | keys[]' | grep kubeadm
```

Cross-reference against `k8s_lab_kubernetes_version`.

**Fix.** Pin `k8s_lab_kubernetes_version` to a published `<minor>.0`
(safest — plan `§8a` Verified version log), or stand up a private
simplestreams remote with your patch and override CAPN provider config
to point at it (consumer-repo concern). See plan `§8a` and `§12.9`.

---

## Pivot (Phase 7) issues

### `clusterctl move` fails: "ClusterClass not found"

**Symptom.** `pivot_clusterctl_move` fails on `move` with `failed to
retrieve ClusterClass "<name>": ClusterClass.cluster.x-k8s.io "<name>"
not found`. mgmt-1 nodes are Ready; bootstrap still has the Cluster
CR.

**Likely cause.** Step ordering. The mgmt-1 helm releases
(`capi-cluster-class`, `capi-workload-cluster` for mgmt-topology) must
complete on bootstrap before `clusterctl move` — `move` walks the CAPI
CR graph and refuses to relocate a Cluster whose ClusterClass is
missing. The canonical `e2e-local` converge enforces this; a custom
playbook that splits Phase 5 from Phase 7 may not.

**Diagnose.**

```sh
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig get clusterclasses -A
helm --kubeconfig=.artifacts/mgmt.kubeconfig list -A
```

ClusterClass in `Cluster.spec.topology.classRef` absent → this recipe.

**Fix.** Re-run the Phase 5 helm releases on bootstrap, then retry the
pivot — idempotent. Reference: plan `§3.1` (the nine ordered steps).

### Post-pivot CAPI controller cannot reach LB

**Symptom.** Post-pivot, self-hosted CAPI on mgmt-1 reports `failed to
dial control plane endpoint`. Bootstrap k3s reached the same LB
without trouble. The LB LXC is up and listening.

**Likely cause.** Network surface asymmetry. On bootstrap, CAPI
controllers ran host-network as k3s server processes (source IP = the
bootstrap LXC's `eth0` IPv6 on `capi-int`, native L3 to the LB). On
mgmt-1 they run as Pods with Calico-managed Pod IPv6 in
`fd42:77:2::/56`. Pod→substrate IPv6 SNAT must be on, or pod IPs
cannot reach the LB.

**Diagnose.**

```sh
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig \
  -n calico-system get installation default -o yaml | grep -A2 natOutgoing
# Expect 'natOutgoing: Enabled' under both ipPools.
```

**Fix.** The `cni-calico` chart sets `natOutgoing: Enabled` on both
IPv4 and IPv6 IPPools by default. If an override turned it off,
restore the default and `helm upgrade cni-calico`. The mandatory pivot
exists precisely to exercise this surface change in every e2e run. See
plan `§3.3` Network surface asymmetry.

### `cleanup_bootstrap` removes the wrong runner-side directory

**Symptom.** `cleanup_bootstrap` deletes more than expected on the
runner. Files outside the project's `.artifacts/` are gone.

**Likely cause.** `cleanup_bootstrap_artifacts_root` set to a
**relative** path (e.g. `.artifacts` resolved against a different
working directory) or a non-canonical path with `..`. The role's
preflight blocks `/` and `//`, but does not resolve relative paths
against an absolute base.

**Diagnose.**

```sh
grep -rn cleanup_bootstrap_artifacts_root \
  ansible/ tests/molecule/ <consumer-repo>/inventories/
```

**Fix.** Either set `cleanup_bootstrap_artifacts_root` to an absolute,
project-scoped path (e.g. `/home/<runner>/k8s-lab/.artifacts`), or
leave it empty (default — file-deletion skipped; LXC instance still
removed). The Molecule scenario uses
`<repo>/.artifacts-cleanup-bootstrap-test` to keep the test isolated.
See plan `§19.1` Implementation notes.

---

## kube-proxy / NodePort / MetalLB

### NodePort accepted on internal IP, not external

**Symptom.** `curl http://<node-eth1-IPv6>:<nodeport>/` from an
external probe times out, but the same NodePort on `<node-eth0-IP>`
from the host succeeds.

**Likely cause.** kube-proxy default listens on **all** node IPs. The
two-NIC node design (plan `§4`) requires NodePort bound only on the
external IPv6 segment. The cluster-config sets
`--nodeport-addresses=<external IPv6 CIDR>`; if a custom
KubeProxyConfiguration dropped that flag, kube-proxy is back to the
default.

**Diagnose.**

```sh
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig \
  -n kube-system get configmap kube-proxy -o yaml | grep -A1 nodePortAddresses
```

Empty or absent → kube-proxy is listening everywhere.

**Fix.** Restore `nodePortAddresses` to the external IPv6 CIDR. The
shipped `capi-cluster-class` bakes this into KubeadmControlPlaneTemplate;
if a chart-version bump lost your values, re-apply them in the
consumer-side overlay. See plan `§5.4`.

### MetalLB VIP allocated but not reachable

**Symptom.** `kubectl get svc` shows the LoadBalancer Service has an
external IPv6; `kubectl describe svc` shows MetalLB `IpAllocated`
events. But `curl http://[<VIP>]:80/` times out.

**Likely cause.** L2 mode requires NDP on the announcing interface. If
`L2Advertisement.spec.interfaces` does not list `eth1`, MetalLB
announces on the wrong NIC (or none); `nodeSelectors` that exclude the
VIP-holding node mute NDP on it.

**Diagnose.**

```sh
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig \
  -n metallb-system get l2advertisement -o yaml

# On the speaker leader:
sudo lxc shell <speaker-leader-node> --project capi-lab
tcpdump -i eth1 'icmp6 && ip6[40] >= 134 && ip6[40] <= 137' -n -c 10
# 134=RA, 135=NS, 136=NA, 137=Redirect — expect NS/NA for the VIP.
```

No NDP for the VIP → this recipe.

**Fix.** Chart-version-bump `metallb-config` with:

```yaml
spec:
  interfaces:   [eth1]
  nodeSelectors: []   # or a selector that covers all CP+worker
```

Then `helm upgrade metallb-config`. See plan `§5.5`.

---

## Image / cloud-init issues

### Worker node has no global IPv6 on `eth1`

**Symptom.** A new CAPN-spawned worker boots and joins, but
`kubectl get nodes -o wide` shows only a link-local IPv6 on `eth1`.
MetalLB cannot announce VIPs on it; NodePort on `eth1` does not bind.

**Likely cause.** Two sub-causes (plan `§2.10`, `§16.2`):

1. The node image is not cloud-init capable, so the
   `KubeadmConfigSpec.files` payload was never written.
2. The image **is** cloud-init capable but `preKubeadmCommands`
   (`sysctl --load` + `networkctl reload`) did not run — cloud-init
   failed mid-flight.

**Diagnose.**

```sh
sudo lxc shell <node> --project capi-lab
cat /etc/sysctl.d/99-capi-ra.conf       # accept_ra=2, accept_ra_defrtr=1
ls /etc/systemd/network/ | grep capi-ext # 30-capi-ext.network present
cloud-init status --long
journalctl -u cloud-final -n 200
```

Missing files → image not cloud-init capable. Files present but
`sysctl --load` never ran → cloud-init failed.

**Fix.** Switch to a cloud-init capable image (CAPN's
`images:capi/kubeadm/<ver>` line is the supported baseline; plan
`§12.9`). For an already-broken node, hand-run `sudo sysctl --load
/etc/sysctl.d/99-capi-ra.conf && sudo networkctl reload` as a bandage,
but recreate the Machine via CAPI for a real fix — `kubeadm init` may
have baked the wrong addresses into Node objects.

Note: runtime `net.ipv6.conf.eth1.accept_ra = 0` is **expected** under
systemd-networkd — with `IPv6AcceptRA=yes` the daemon processes RAs in
user space, kernel sysctl stays 0. Confirm via `ip -6 addr show dev
eth1`, not the sysctl. See plan `§9.2 Step 9` end-to-end proof.

---

## Diagnostic recipes (always-useful)

All read-only, safe to run any time.

```sh
# Substrate inventory:
sudo lxc list --project capi-lab -f csv -c n,s,t,4,6

# Shell into a node:
sudo lxc shell <instance> --project capi-lab

# LXD daemon logs:
journalctl -u snap.lxd.daemon -n 200

# CAPI snapshot:
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig \
  get clusters,machines,kubeadmcontrolplanes,machinedeployments -A

# CAPN reconciliation:
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig \
  -n capn-system logs deploy/capn-controller-manager --tail=400

# CAPI core reconciliation:
kubectl --kubeconfig=.artifacts/mgmt.kubeconfig \
  -n capi-system logs deploy/capi-controller-manager --tail=400

# Re-run a Gate test interactively:
helm test <release> --logs --kubeconfig=.artifacts/mgmt.kubeconfig

# RA traffic on the external segment:
sudo tcpdump -i br-ext6 'icmp6 && ip6[40] == 134' -n -c 5
```

---

## When all else fails

If a recipe above does not match and you cannot find the cause in 30
minutes of focused investigation, reset and re-run from scratch — the
canonical flow is designed to be cheap to recreate.

```sh
# Local harness (Vagrant VM):
make clean-local

# Production / consumer repo:
# Run the consumer-repo's destroy.yml playbook, which in turn invokes
# `cleanup_bootstrap`, `clusterctl delete --all`, and the LXD-side
# teardown roles in reverse canonical order.
```

Then bring everything back up:

```sh
make test-local-e2e        # local: full Phase 0..9 cycle
# or
make deploy-workload       # add a workload cluster on an
                           # already-self-hosted mgmt-1
```

If the failure reproduces on a clean slate:

1. Capture the relevant logs (`journalctl`, `kubectl logs`, role
   converge output, `terraform apply` transcript).
2. Identify the closest `§N` plan reference for the failing step (the
   table in `01-overview.md` "Where the source of truth lives" maps
   questions to plan sections).
3. File an issue with the logs + the `§N` reference. The plan is the
   single source of truth — if the symptom contradicts a documented
   invariant, that is the bug to chase.

The plan says **why**. The documentation says **how**. The code says
**what**. This chapter is the bridge between the three when something
between them slips.
