# Backup and disaster recovery of `mgmt-1`

`mgmt-1` holds every Cluster API object — its own and every workload
cluster's. Losing its etcd loses the management of every cluster, while their
nodes keep running.

## When to use

- Regularly, and before any change to `mgmt-1` (Kubernetes or provider
  upgrade, LXD channel change, control-plane scaling).
- To recover from the cases below.

## What to back up

| Item | Where | Why |
|---|---|---|
| etcd snapshot of `mgmt-1` | its control-plane node | everything on `mgmt-1`: Cluster API objects with their status, the Secrets (cluster CAs, kubeconfigs, the CAPN identity), the Helm release records |
| `clusterctl move --to-directory` | host | the Cluster API objects as YAML, without status — readable, and restorable into another management cluster |
| `<k8s_lab_opt_root>/etc` | host | the CAPN client key (its only copy outside `mgmt-1`'s Secrets), `mgmt.kubeconfig`, `clusterctl.yaml` |
| etcd snapshot of each workload cluster | its control-plane node | the workloads' own state |
| Terraform state of every root | its backend | what Terraform owns; without it a root re-creates what exists |
| Playbook, inventory, `group_vars`, Terraform roots | the deployment's repository | everything else is rebuilt from them |

All of it is secret material (keys, CAs, admin credentials): keep it
encrypted and off the host.

## Preconditions

Every cluster `Available` (`clusterctl move` refuses paused clusters and saves
no status). A root shell on the host and `$MGMT` on the runner.

## Steps — backup

1. On the host, a directory for this backup:

   ```bash
   B=/var/backups/k8s-lab/$(date +%F)
   install -d -m 0700 $B $B/move
   ```

2. etcd snapshot of each cluster, taken in its etcd Pod (runner, with the
   cluster's kubeconfig as `KC`), copied to the host and removed from the node
   (host); `<cluster>` names the file:

   ```bash
   POD=$(kubectl --kubeconfig $KC -n kube-system get pods -l component=etcd -o jsonpath='{.items[0].metadata.name}')
   echo "node: ${POD#etcd-}"
   kubectl --kubeconfig $KC -n kube-system exec $POD -- etcdctl --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key snapshot save /var/lib/etcd/k8s-lab-snapshot.db
   kubectl --kubeconfig $KC -n kube-system exec $POD -- etcdutl snapshot status /var/lib/etcd/k8s-lab-snapshot.db -w table
   ```

   ```bash
   NODE=<the node printed above>                                  # host
   lxc file pull --project $PROJECT $NODE/var/lib/etcd/k8s-lab-snapshot.db $B/<cluster>-etcd.db
   lxc exec --project $PROJECT $NODE -- rm /var/lib/etcd/k8s-lab-snapshot.db
   ```

3. The Cluster API objects, once per namespace that holds clusters
   (`k8s_lab_cluster_namespace` and every other one in
   `capn_identity_namespaces`), each into a directory of its own (host):

   ```bash
   O=<k8s_lab_opt_root>
   for ns in $NS <other namespaces>; do
     install -d -m 0700 $B/move/$ns
     $O/bin/clusterctl move --kubeconfig $O/etc/mgmt.kubeconfig \
       --config $O/etc/clusterctl/clusterctl.yaml --namespace $ns --to-directory $B/move/$ns
   done
   ```

   The move pauses every Cluster while it saves and resumes it afterwards: each
   Cluster's generation goes up by two, so the next apply of every add-on root
   runs its convergence check and gates again (half a minute, nothing changes).
4. The host's material (host):

   ```bash
   tar -C $O -czf $B/opt-etc.tar.gz etc
   chmod 0600 $B/*.db $B/opt-etc.tar.gz
   ```

5. Copy `$B` off the host; back up the Terraform states with their backend.

## Recovery — `mgmt-1`'s etcd lost or corrupt, its control-plane node alive

For a `mgmt-1` with one control-plane machine (one etcd member). Everything
runs on the node, without the API, which is down while etcd is. On the host:

```bash
NODE=<mgmt-1's control-plane instance>          # lxc list --project $PROJECT
lxc file push --project $PROJECT $B/mgmt-1-etcd.db $NODE/var/lib/etcd/restore-src.db
lxc exec --project $PROJECT $NODE -- sh
```

On the node: stop etcd (kubelet stops a static Pod whose manifest is gone),
restore the snapshot with `etcdutl` from the node's own etcd image, swap the
data, start etcd:

```bash
mv /etc/kubernetes/manifests/etcd.yaml /etc/kubernetes/etcd.yaml.k8s-lab
while pgrep -x etcd >/dev/null; do sleep 2; done
M=/etc/kubernetes/etcd.yaml.k8s-lab
IMG=$(sed -n 's/^ *image: *//p' $M)
NAME=$(sed -n 's/^ *- --name=//p' $M)
PEER=$(sed -n 's/^ *- --initial-advertise-peer-urls=//p' $M)
ctr -n k8s.io run --rm --mount type=bind,src=/var/lib/etcd,dst=/var/lib/etcd,options=rbind:rw \
  "$IMG" k8s-lab-etcd-restore etcdutl snapshot restore /var/lib/etcd/restore-src.db \
  --data-dir /var/lib/etcd/restored --name "$NAME" --initial-cluster "$NAME=$PEER" \
  --initial-advertise-peer-urls "$PEER" --bump-revision 1000000000 --mark-compacted
[ -d /var/lib/etcd/member ] && mv /var/lib/etcd/member /var/lib/etcd/member.k8s-lab-old
mv /var/lib/etcd/restored/member /var/lib/etcd/member && rmdir /var/lib/etcd/restored
mv $M /etc/kubernetes/manifests/etcd.yaml
```

The API answers again within two minutes. Then run `<playbook>` and apply
every add-on root; remove `member.k8s-lab-old` and `restore-src.db` from the
node. A `mgmt-1` with three control-plane machines keeps working while one
member is lost (two of three keep the quorum); no health check replaces the
broken machine by itself: deleting its Machine makes Kubeadm Control Plane
remove the member and create a replacement (not exercised).

## Recovery — host material lost

Restore `<k8s_lab_opt_root>/etc` from `opt-etc.tar.gz`; for `mgmt.kubeconfig`
alone see [kubeconfig.md](kubeconfig.md).

## Recovery — `mgmt-1` lost entirely, workload nodes alive (outline)

Not exercised; upstream documents the pieces, not this sequence, and states that
`clusterctl move` is not a backup tool. Outline: let the playbook create a new
`mgmt-1` (the host must be left without `mgmt-1`'s instances and without
`mgmt.kubeconfig`); remove `mgmt-1`'s own objects from the saved directory;
`clusterctl move --from-directory` the workload clusters' objects into the new
`mgmt-1`; their `<name>-ca`, `-etcd`, `-sa` and `-kubeconfig` Secrets come with
them; re-adopt their Helm releases by re-applying each cluster root.

## Verify

`etcdutl snapshot status` prints a hash, revision and key count for every
snapshot; the move directory holds a file per object (Clusters, ClusterClasses,
templates, Machines, Secrets — the CAPN identity Secret included); after a
recovery: `kubectl --kubeconfig $MGMT get clusters -A` all `Available`, the
playbook changes nothing, every add-on root's gates pass.

## Rollback

Not applicable.

## Tested

2026-11-16, harness. Backup of both clusters as above: snapshots of 37 MB
(`mgmt-1`) and 26 MB (`lab-default`), 71 object files, `opt-etc.tar.gz` with
the CAPN key and certificate, `mgmt.kubeconfig`, `clusterctl.yaml`; the
Clusters' generations went from 5 and 2 to 7 and 4, the next add-on apply
re-ran its checks in 33 s. Recovery of `mgmt-1`'s etcd with the steps above:
snapshot taken and pulled to the host, a ConfigMap written afterwards, then
etcd stopped and its data moved away (the API down); the snapshot pushed back
and restored on the node — the API answered again 112 s after etcd was
stopped, one member with a new ID, the ConfigMap gone (rolled back to the
snapshot), every node `Ready`. Host-material recovery exercised for
`mgmt.kubeconfig` ([kubeconfig.md](kubeconfig.md)). Not exercised: the loss of
`mgmt-1` as a whole, and the loss of one member of three.
