# Lost or expired kubeconfig

## When to use

A copy of a cluster's admin kubeconfig is gone, or its client certificate
expired ([certificates.md](certificates.md)). Every copy is derived from the
cluster's `<cluster>-kubeconfig` Secret on `mgmt-1`, which Cluster API keeps
current, with the API server set to the address the host publishes.

| Copy | Where | Made by |
|---|---|---|
| `mgmt.kubeconfig`, host | `<k8s_lab_opt_root>/etc/` | the management playbook, every run |
| `mgmt.kubeconfig`, runner (`$MGMT`) | `<k8s_lab_artifacts_dir>/` | the management playbook, every run |
| Workload cluster | Terraform state of its add-on root | every plan and apply of that root |

## Preconditions

The management playbook can run; for a workload cluster, `$MGMT` works and the
cluster's API answers (`curl -sk "$(terraform -chdir=<root>/addons output
-raw api_server_url)/livez"`). Do not apply an add-on root while
the cluster's API does not answer ([troubleshooting](../troubleshooting.md)).

## Steps — the runner's `mgmt.kubeconfig`

1. Run `<playbook>`. Its first step finds `mgmt-1` through the host's copy and
   writes it to the runner; later in the run both copies are rebuilt from the
   Secret.

## Steps — the host's `mgmt.kubeconfig`

The playbook refuses to run without it once `mgmt-1` exists ("Instances of
mgmt-1 exist … Refusing to bootstrap over a live cluster"): it cannot tell a
lost file from a cluster that is not there.

1. Put the runner's copy back on the host (same content), then run the
   playbook:

   ```bash
   ssh <host> 'sudo install -m 0600 -o root -g root /dev/stdin <k8s_lab_opt_root>/etc/mgmt.kubeconfig' < $MGMT
   ```

   Without a runner copy, restore `<k8s_lab_opt_root>/etc/` from its backup
   ([backup-restore.md](backup-restore.md)).

## Steps — an expired kubeconfig

Cluster API renews the `mgmt-1-kubeconfig` Secret, and every playbook run
copies it; a host that ran no playbook for a year keeps a client certificate
that has expired. The playbook then stops ("mgmt-1 answers but refuses …").
Rebuild the host's copy from a control-plane node, whose `admin.conf` reaches
the API on the internal network (host; not exercised):

```bash
O=<k8s_lab_opt_root>; K=$O/bin/kubectl
lxc exec --project $PROJECT <mgmt-1 control-plane instance> -- cat /etc/kubernetes/admin.conf > /root/admin.conf
PORT=$($K --kubeconfig /root/admin.conf -n $NS get cluster mgmt-1 -o jsonpath='{.metadata.annotations.k8s-lab\.io/api-proxy-port}')
$K --kubeconfig /root/admin.conf -n $NS get secret mgmt-1-kubeconfig -o jsonpath='{.data.value}' | base64 -d > /root/mgmt.kubeconfig
$K --kubeconfig /root/mgmt.kubeconfig config set-cluster mgmt-1 \
  --server=https://<k8s_lab_lxd_host_address>:$PORT --tls-server-name=kubernetes.default.svc
install -m 0600 /root/mgmt.kubeconfig $O/etc/mgmt.kubeconfig && rm /root/admin.conf /root/mgmt.kubeconfig
```

Then run `<playbook>`: it writes both copies anew.

## Steps — a workload cluster's kubeconfig

1. Apply the add-on root; with nothing to change it only re-reads the Secret
   and stores the current kubeconfig:

   ```bash
   terraform -chdir=<root>/addons apply
   ```

2. Write it out:

   ```bash
   (umask 077; terraform -chdir=<root>/addons output -raw kubeconfig > lab-default.kubeconfig)
   ```

## Verify

```bash
kubectl --kubeconfig $MGMT get nodes
kubectl --kubeconfig lab-default.kubeconfig get nodes
```

## Rollback

Not applicable: nothing is changed but the copies.

## Tested

2026-11-16, harness. Runner copy deleted: the run passed and wrote the same
file back (byte for byte). Host copy deleted: the playbook refused as above; restored with
the command above, the next run changed nothing. Workload kubeconfig deleted:
re-exported with the two steps above, `kubectl get nodes` answered.
