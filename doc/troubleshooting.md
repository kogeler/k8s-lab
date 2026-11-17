# Troubleshooting

Failures seen while building and operating the lab, with what causes them and
what fixes them. `$MGMT` is the runner's `mgmt.kubeconfig`; commands marked
*host* run as root on the host.

## Host and LXD

### LXD snap: "assumes unsupported features: snapd2.75"

**Cause.** The `lxd` snap on `6/stable` needs a newer snapd than Debian 13
ships. **Fix.** Role `lxd` installs the `snapd` snap first, and the Debian
daemon re-executes into it; re-run the playbook. A fresh snapd may answer
"Snaps not found" for a minute; the role retries.

### Node images: "Image registry … is not allowed in this project"

**Cause.** Since LXD 6.10 a restricted project downloads images only from the
registries in its `restricted.registries`; CAPN asks for
`https://images.linuxcontainers.org/capn/`. **Check** (host):
`lxc query /1.0/image-registries` lists `capn`;
`lxc project get capi-lab restricted.registries` is `builtin,capn`. **Fix.**
Role `lxd` creates both; re-run the playbook. A registry named `capn` with
another URL is set back to CAPN's.

### Storage pool: the role refuses the device

**Cause.** `lxd_storage_source` must be a block device with nothing mounted
from it and no filesystem signature on the first run; afterwards the pool
keeps the device for its whole life. **Fix.** `wipefs -a <device>` (host) on
a new device; for an existing pool, set `lxd_storage_source` back to the
device it was created on.

### "Refusing to bootstrap over a live cluster"

**Cause.** `mgmt-1`'s instances exist, but `<k8s_lab_opt_root>/etc/mgmt.kubeconfig`
on the host is missing or does not reach a cluster that holds `mgmt-1`, and no
bootstrap instance exists. The playbook cannot tell a lost file from a missing
cluster and stops instead of building a second `mgmt-1`. **Fix.** Restore the
file ([kubeconfig.md](runbooks/kubeconfig.md)); if `mgmt-1` really is gone, see
[backup-restore.md](runbooks/backup-restore.md).

## Machines and nodes

### A Machine never gets an instance: image not found

**Symptom.** CAPN logs `The requested image couldn't be found` for
`kubeadm/<version>`. **Cause.** CAPN's image server publishes only some
Kubernetes patch releases. **Check.**
`curl -sS https://images.linuxcontainers.org/capn/streams/v1/images.json | jq -r '.products | keys[]' | grep kubeadm`.
**Fix.** Pick a published version
([upgrade-kubernetes.md](runbooks/upgrade-kubernetes.md)).

### A node never joins: "Dependency failed for kubelet.service"

**Symptom.** The Machine stays `Provisioning`; in the node
(`lxc exec --project capi-lab <node> -- systemctl status kubelet`) the kubelet
did not start because `k8s-lab-ext-reply.service` failed. **Cause.** The node
could not load its `eth1` reply marks, and the kubelet requires them;
`journalctl -u k8s-lab-ext-reply` names the reason: the image has no
`ip6tables-nft-restore`, or the host has not loaded `nft_compat`,
`xt_connmark`, `xt_mark`. **Fix.** An image with `ip6tables-nft` (CAPN's have
it), or the modules on the host (role `host` loads them persistently); then
delete the Machine or let Cluster API replace it.

### A node has no global address on `eth1`

**Cause.** No router advertisement reaches the external network, or the node's
cloud-init did not run. **Check.** In the node: `ip -6 addr show dev eth1`,
`ls /etc/systemd/network/30-capi-ext.network`, `cloud-init status --long`; on
the host: `tcpdump -ni br-ext6 'icmp6 and ip6[40] == 134'` shows the router's
advertisements. **Fix.** Make the router advertise the prefix; an image without
cloud-init cannot be used. `net.ipv6.conf.eth1.accept_ra = 0` is expected:
systemd-networkd handles the advertisements itself.

### `helm upgrade` refused: "field is immutable"

**Cause.** An object Cluster API treats as immutable changed in place. The
class chart names every template after a hash of its spec, so a value change
creates a new template; this error means a template was edited by hand or a
chart change outside the hashed specs. **Fix.** Restore the chart's rendering
(`helm rollback`, or revert the change) and change templates through values
([change-node-template.md](runbooks/change-node-template.md)).

## Add-ons and gates

### `cni-calico-config` upgrade: "conflict with \"operator\" … .spec.calicoNetwork.ipPools"

**Cause.** The tigera operator writes its defaults into the `Installation`'s
`ipPools`, an atomic list, so a chart list without those fields conflicts with
it under Helm's server-side apply. **Check.**
`kubectl get installation default -o jsonpath='{.spec.calicoNetwork.ipPools}'`.
**Fix.** The chart renders every field the operator defaults. After a Calico
upgrade that adds one, add it to `templates/installation.yaml`.

### `metallb-config`: "failed calling webhook … connection refused"

**Cause.** The MetalLB controller is Ready, and its CA is in the webhook
configuration, before its serving certificate reaches the Pod (up to a
minute). **Fix.** Both drivers wait with a server-side dry run of an
`IPAddressPool` that must reach the webhook; if it never answers, read the
controller's logs in `metallb-system`.

### Gate B fails

**Cause.** Pods on two workers cannot reach each other over IPv4 or IPv6, or
Calico did not finish rolling out at the chart's version (the gate's first
step waits for it). **Check** (workload kubeconfig):
`kubectl -n calico-system logs ds/calico-node --tail=200`,
`kubectl get installation default -o jsonpath='{.status.calicoVersion}'`,
`kubectl get tigerastatus`, `kubectl get pods -A -o wide | grep -v Running`;
on the host `lxc info --project capi-lab <node> --show-log`. Missing kernel
modules (`vxlan`, `nf_tables`) and AppArmor denials show there.

### Gate A fails: "no address assigned yet"

**Cause.** MetalLB gave the gate's Service no address from the release's pool:
every address of `pool.rangeV6` is taken by other LoadBalancer Services, or the
MetalLB controller does not run. **Check.**
`kubectl -n metallb-system get ipaddresspool -o wide` (assigned and available
counts), `kubectl get svc -A --field-selector spec.type=LoadBalancer`.
**Fix.** A larger range, or release a VIP.

### Gate A passes, but the VIP or a NodePort does not answer from outside

**Cause.** One of: the node holding the VIP has no address on `eth1` (above);
the replies do not leave through `eth1`; the host's firewall drops the
forwarded traffic; the pool is outside the prefix the router advertises.
**Check.**
`kubectl -n metallb-system get l2advertisement -o yaml` (interfaces `[eth1]`);
in the announcing node `tcpdump -ni eth1 'icmp6 and (ip6[40] == 135 or ip6[40] == 136)'`
(neighbor solicitations and advertisements for the VIP),
`ip -6 rule` (the `fwmark 0x100/0x100 lookup 4200` rule), `ip -6 route show table 4200`;
on the host the forward chains of every nftables table. **Fix.** As found;
the host firewall's requirements are in [architecture](architecture.md#network).

### A NodePort answers nowhere after the external prefix changed

**Cause.** Only `kubeadm init` writes kube-proxy's ConfigMap, so
`nodePortAddresses` still holds the old prefix. **Fix.** The kube-proxy step
of [change-external-prefix.md](runbooks/change-external-prefix.md).

## Terraform

### Add-on root: "apply its cluster root first"

**Cause.** The cluster root was not applied (or was destroyed), the name or the
namespace in the two roots' `terraform.tfvars` differs, or Cluster API has not
written the cluster's kubeconfig Secret yet. **Fix.** Apply the cluster root
first and keep `name` and `namespace` equal in both roots.

### Add-on root wants to create releases that exist: "cannot re-use a name that is still in use"

**Symptom.** The plan reports `helm_release.… has been deleted` and wants to
create `cni_calico`, `cni_calico_config`, `metallb` and `metallb_config`
although the cluster runs them; `terraform state list` no longer shows them.
**Cause.** The root was refreshed — by an applied plan or `apply
-refresh-only` — while the cluster's API did not answer (a stopped load
balancer, a host out of memory). The Helm provider reads a release it cannot
reach as deleted. A plan made while the API is down shows this before anything
is lost: do not apply it. **Fix.** When the API answers again, import the
releases, then apply (the releases change nothing, the checks run again):

```sh
terraform -chdir=<root>/addons import module.workload_addons.helm_release.cni_calico tigera-operator/cni-calico
terraform -chdir=<root>/addons import module.workload_addons.helm_release.cni_calico_config tigera-operator/cni-calico-config
terraform -chdir=<root>/addons import module.workload_addons.helm_release.metallb metallb-system/metallb
terraform -chdir=<root>/addons import module.workload_addons.helm_release.metallb_config metallb-system/metallb-config
terraform -chdir=<root>/addons apply
terraform -chdir=<root>/addons plan -detailed-exitcode
```

### Add-on destroy: "Unable to uninstall Helm release cni-calico-config: … context deadline exceeded"

**Cause.** The `Installation` carries the tigera operator's finalizers, and
the operator is not running (often: the host is out of memory, below). **Check.**
`kubectl get installation default -o jsonpath='{.metadata.deletionTimestamp} {.metadata.finalizers}'`,
`kubectl -n tigera-operator get pods`. **Fix.** Destroy again once the operator
runs; to remove the cluster anyway, destroy its cluster root (the add-ons go
with it) and delete the add-on root's state.

### Plan of the add-on root: "provider crashed", `panic: ElementKeyInt(0)`

**Cause.** The kubernetes provider (3.5.0) cannot convert a ClusterClass
(`spec.patches` entries of different shapes) into one Terraform type. **Fix.**
Do not read ClusterClasses through it; the module learns about template
changes from the Cluster's `k8s-lab.io/class-revision` annotation.

## Capacity

### Everything times out; controllers restart with "leader election lost"

**Symptom.** `kubectl` times out or returns `EOF`; Cluster API, CAPN,
`kube-controller-manager` and `kube-scheduler` restart; Helm fails on
`failed calling webhook "default.cluster.cluster.x-k8s.io" … connection refused`;
on the host the load is far above the CPU count and `kswapd0` is busy.
**Cause.** The host is out of memory; control-plane machines need about 1 GiB
each. On a 12 GiB host six of them did it, and it did not recover by itself.
**Fix.** Lower the number of control-plane machines as soon as the APIs answer
long enough ([scale.md](runbooks/scale.md)); apply no add-on root meanwhile.

## Diagnostics

Read-only, safe at any time:

```sh
lxc list --project capi-lab                                            # host
lxc exec --project capi-lab <node> -- journalctl -b -n 200            # host
journalctl -u snap.lxd.daemon -n 200                                   # host
kubectl --kubeconfig $MGMT get clusters,machines,kcp,md -A
kubectl --kubeconfig $MGMT -n capn-system logs deploy/capn-controller-manager --tail=200
kubectl --kubeconfig $MGMT -n capi-system logs deploy/capi-controller-manager --tail=200
kubectl --kubeconfig $MGMT -n capi-clusters logs job/<cluster>-test-cluster-ready --all-containers
helm test <release> -n <namespace> --kubeconfig <kubeconfig> --logs
```

[`scripts/collect-diagnostics.sh`](../scripts/collect-diagnostics.sh), run on
the host by a user with sudo (`scripts/collect-diagnostics.sh <k8s_lab_opt_root>`),
prints in one go the host, LXD and its pool, every instance, and every cluster
— the bootstrap cluster, `mgmt-1` with its controllers' logs, each workload
cluster through its kubeconfig Secret: nodes with their pressure conditions,
the Pods that do not run, events. It prints no kubeconfig or Secret (CI runs it
after a failed run). When a failure reproduces on a fresh host, open an issue
with its output.
