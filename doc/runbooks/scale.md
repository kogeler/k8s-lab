# Scale workers or the control plane

## When to use

A cluster needs more or fewer workers or control-plane machines. Scaling
changes replica counts only: no template rotation, no other machine replaced.

## Preconditions

- Control-plane counts are odd (stacked etcd: an even count adds no fault
  tolerance, and Kubeadm Control Plane refuses it). Workers are at least 2:
  Gate B spreads its servers over two workers. The Terraform module refuses
  both at plan time.
- On one host more control-plane machines add no availability against the
  host failing; they protect against a single node failing and make every
  rollout longer.
- Room on the host: a node is a container with the memory its workload needs,
  and a control-plane machine needs most (etcd, the API server, the
  controllers — about 1 GiB each at rest). Count every cluster's control
  planes together: on the 12 GiB harness six of them (`mgmt-1` at 3 next to
  a workload cluster at 3) drove the host into memory reclaim — load above
  200, leader elections lost, the Cluster API webhook down — and it did not
  recover within 15 minutes. Four fit.

## Steps — workload cluster

1. Set `worker_count` or `control_plane_count` in
   `<root>/cluster/terraform.tfvars`. One count per apply.
2. Apply both roots:

   ```bash
   terraform -chdir=<root>/cluster apply
   terraform -chdir=<root>/addons apply
   ```

   The cluster root changes the Cluster release only; the add-on root's
   convergence check waits until the new machines are in (or the removed
   ones gone) and both gates run again.

## Steps — `mgmt-1`

1. Set the role inputs `management_cluster_worker_count` or
   `management_cluster_controlplane_count` in `group_vars/all.yml`.
2. Run `<playbook>`: the Cluster release changes, the gates wait for the new
   machines and check the cluster.

## Verify

```bash
kubectl --kubeconfig $MGMT -n $NS get kcp,md \
  -o custom-columns=KIND:.kind,NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas --no-headers
kubectl --kubeconfig <cluster kubeconfig> get nodes
```

The desired, ready and available counts agree, the node list has the new
count, all `Ready`.

## Rollback

Set the previous count and apply or run again: scaling is symmetric. When a
count goes down, Cluster API drains the machines it removes first; on a
control plane it removes their etcd members.

## Tested

2026-11-16, harness, one count per apply. `lab-default`: workers 2 → 3 (the
convergence check waited 25 s; the new node was Ready when the apply
returned), control plane 3 → 1 (1 min 17 s), workers 3 → 2 (20 s; the drained
node's Pods, the Calico operator included, moved to the remaining workers),
control plane 1 → 3 (the check waited 1 min 25 s, until the last new node was
Ready). A plan with 2 control-plane machines or 1 worker is refused. `mgmt-1`:
workers 2 → 3 (the playbook's gates 39 s; the check's Pod was evicted once on
purpose while it waited, and its Job replaced it) and 3 → 2 (gates 24 s), each
run about 2 minutes; control plane 1 → 3 (passed, next to `lab-default` at 3 —
the capacity limit in the preconditions). Not exercised: scaling `mgmt-1`'s
control plane down.
