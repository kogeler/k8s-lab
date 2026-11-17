# Teardown

## When to use

- **A workload cluster**: it is no longer needed.
- **Everything**: the host leaves the lab — every cluster, `mgmt-1`, and what
  the roles put on the host. There is no playbook for this; the steps below are
  the procedure.

## Preconditions

- Backups taken of anything worth keeping ([backup-restore.md](backup-restore.md)).
- For a workload cluster: `$MGMT` works. Its API should answer; if it does not,
  skip the add-on root (its objects live inside the cluster and go with it).
- For everything: a root shell on the host. If the host serves other LXD
  tenants, keep LXD and the shared host settings (step 4).

## Steps — a workload cluster

```bash
terraform -chdir=<root>/addons destroy
terraform -chdir=<root>/cluster destroy
```

Then delete the pair of roots and their state; retire its namespace if it had
one of its own ([capn-identity.md](capn-identity.md)).

Helm does not track hook objects: a hook or a check that failed earlier leaves
its Job, Pod, ServiceAccount, Role and ConfigMap on `mgmt-1` after the release
is gone (the publication hook's Pod mounts the CAPN identity). Remove what is
left of the cluster's two releases:

```bash
kubectl --kubeconfig $MGMT -n $NS delete job,pod,serviceaccount,role,rolebinding,configmap \
  -l 'app.kubernetes.io/instance in (<cluster>,<cluster>-class)'
```

## Steps — everything

1. Every workload cluster as above.
2. `mgmt-1` and the project (host). `mgmt-1` manages itself and cannot delete
   its own machines, so its instances go through LXD directly:

   The names below are the reference values (`$PROJECT`, the network, the
   pool, the bridge, `<k8s_lab_opt_root>`): substitute your deployment's.

   ```bash
   P=capi-lab
   for i in $(lxc list --project $P --format csv -c n); do lxc delete --project $P --force $i; done
   for f in $(lxc image list --project $P --format csv -c f); do lxc image delete --project $P $f; done
   for p in $(lxc profile list --project $P --format csv -c n | grep -vx default); do lxc profile delete --project $P $p; done
   lxc project delete $P
   ```

3. The LXD objects outside the project (host):

   ```bash
   lxc network delete capi-int
   lxc storage delete capi-fast
   for f in $(lxc config trust list --format csv -c nf | sed -n 's/^k8slab-capn-[0-9a-f]*,//p'); do lxc config trust remove $f; done
   lxc config unset core.https_address
   lxc query -X DELETE /1.0/image-registries/capn
   ```

4. The host (host): the external bridge, the binaries and the identity, the
   pool's device.

   ```bash
   rm /etc/systemd/network/30-br-ext6.netdev /etc/systemd/network/30-br-ext6.network \
      /etc/systemd/network/31-br-ext6-uplink.network
   networkctl reload && ip link delete br-ext6
   rm -rf /opt/capi-lab
   wipefs -a <lxd_storage_source>
   ```

   On a host that is only the lab's, also `snap remove --purge lxd`, the
   `snapd` snap, the APT packages role `host` installed (`snapd`,
   `python3-cryptography`),
   `/etc/sysctl.d/60-k8s-lab.conf` and the module files role `host` wrote
   under `/etc/modules-load.d/` (`overlay`, `br_netfilter`, `nf_conntrack`,
   `nft_compat`, `xt_connmark`, `xt_mark`); on a shared host they may serve
   others (forwarding, the bridge netfilter modules).
5. The runner: `<k8s_lab_artifacts_dir>` (kubeconfigs, the handoff file) and
   the roots' Terraform state.

## Verify

```bash
lxc project list; lxc network list; lxc storage list; lxc config trust list    # host
ip -br link show br-ext6; ls /opt/capi-lab                                     # host: both gone
```

Only the default project; no `capi-int`, no `capi-fast`, no `k8slab-capn-*`
trust entry; `core.https_address` empty; no `br-ext6`, no `/opt/capi-lab`.

## Rollback

None: the deployment is rebuilt from its repository (`<playbook>`, then the
roots) and its backups.

## Tested

2026-11-16, harness, steps 1–5 except the optional removals of step 4:
`lab-default` destroyed in 47 s (add-on root 17 s); `mgmt-1`'s four instances,
three images, four profiles, the project, network, pool, trust entry,
listener, registry, bridge and `/opt/capi-lab` removed, the pool device wiped;
the listing above then showed only LXD's defaults. A workload cluster was also
removed this way in the second-cluster drill
([workload-clusters.md](workload-clusters.md)) and by every e2e run.
