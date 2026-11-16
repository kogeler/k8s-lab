# Upgrade Kubernetes

## When to use

A workload cluster or `mgmt-1` moves to a newer Kubernetes patch or minor
release. Only the version changes: the machine templates name their image as
`kubeadm/VERSION` and CAPN substitutes the version, so no template rotation is
involved. Cluster API replaces the control-plane machines first, one at a time,
then the workers.

## Preconditions

- CAPN publishes a node image for the target version; only some patch releases
  get one:

  ```bash
  curl -sS https://images.linuxcontainers.org/capn/streams/v1/images.json \
    | jq -r '.products | keys[]' | grep '^kubeadm:' | sort -V
  ```

- The installed Cluster API release supports the target version (its support
  matrix; for `mgmt-1`, the range for management clusters). Upgrade the
  providers first when it does not ([upgrade-providers.md](upgrade-providers.md)).
- Minor versions one at a time: Cluster API refuses to skip one.
- Nothing else changes in the same apply or run (a combined change can roll the
  machines twice).
- The cluster is `Available` (`kubectl --kubeconfig $MGMT get clusters -A`).
- For `mgmt-1`: the backup of [backup-restore.md](backup-restore.md), steps 1–3
  (etcd snapshot, `clusterctl move --to-directory`). With one control-plane
  machine the rollout adds a second etcd member, then removes the old one; a
  failure in between is recovered from that backup.

## Steps — workload cluster

1. Set the version in `<root>/cluster/terraform.tfvars`:

   ```hcl
   kubernetes_version  = "v1.37.0"
   ```

2. Plan and apply the cluster root. The plan shows one update, the Cluster
   release, with only `version` changed in its values; the apply returns in
   seconds, before the rollout:

   ```bash
   terraform -chdir=<root>/cluster plan
   terraform -chdir=<root>/cluster apply
   ```

3. Apply the add-on root. Its convergence check (the Cluster chart's `helm test`
   on `mgmt-1`) waits until every machine is replaced and the topology is
   reconciled, then both gates run again:

   ```bash
   terraform -chdir=<root>/addons apply
   ```

## Steps — `mgmt-1`

1. Take the backup ([backup-restore.md](backup-restore.md), steps 1–3).
2. Set `k8s_lab_kubernetes_version` in `group_vars/all.yml`.
3. Run `<playbook>`. Role `management_cluster` upgrades the Cluster release on
   `mgmt-1`; its gates (the Cluster chart's `helm test`, Gate B, Gate A) wait
   for the rollout and then check the cluster. The check runs on `mgmt-1`
   itself: when the rollout drains the node it runs on, its Job starts it again
   on another node.

   While the control plane changes hands (the new etcd member joins, the old
   one leaves) the `mgmt-1` API can stop answering for a moment; requests time
   out and succeed again on retry.

## Verify

```bash
kubectl --kubeconfig $MGMT get machines -A \
  -o custom-columns=CLUSTER:.spec.clusterName,NAME:.metadata.name,VERSION:.spec.version,PHASE:.status.phase --no-headers
kubectl --kubeconfig <cluster kubeconfig> get nodes
terraform -chdir=<root>/cluster plan -detailed-exitcode
terraform -chdir=<root>/addons plan -detailed-exitcode
```

Every Machine of the cluster at the new version and `Running`, every node
`Ready` at the new version, both plans exit 0.

## Rollback

None: Cluster API does not downgrade a control plane. A failed rollout is
diagnosed and fixed forward ([troubleshooting](../troubleshooting.md)); for
`mgmt-1` the last resort is the restore in [backup-restore.md](backup-restore.md).

## Tested

2026-11-16, harness. Workload `lab-default` (3 control-plane machines,
2 workers) v1.36.4 → v1.37.0: the cluster root applied in 4 s, the add-on
root's convergence check waited 5 min 24 s until all five machines were
replaced, Gate B 27 s, Gate A 4 s; both plans clean. `mgmt-1` (1 control-plane
machine, 2 workers) v1.36.4 → v1.37.0, after the etcd snapshot and
`clusterctl move --to-directory`: the rollout took 5 min 15 s (new control-plane
machine 13 s after the change, the old one gone 3 min later, then the workers);
one API request timed out during the control-plane swap. That the playbook's
convergence check survives `mgmt-1` draining the node it runs on was verified
twice: its Pod evicted on purpose while it waited (replaced, the check passed),
and a full rollout of all three `mgmt-1` machines through the playbook
([change-external-prefix.md](change-external-prefix.md)), whose gates passed.
