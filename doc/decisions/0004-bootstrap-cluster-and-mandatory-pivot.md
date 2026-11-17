# 0004. A transient k3s bootstrap cluster in a container, then a mandatory pivot to `mgmt-1`

Status: Accepted, 2026-11-16

## Context

Cluster API needs a Kubernetes API before it can create the first cluster, and the host runs
none of its own. Upstream's pattern is bootstrap and pivot: `clusterctl init` on a temporary
cluster, create the management cluster from it, `clusterctl move` the Cluster API objects
onto that cluster, remove the temporary one. Helm keeps a release's record on the API it was
installed through, and `clusterctl move` does not carry those records: whatever stays managed
from the bootstrap cluster loses its releases when that cluster goes. After the move the
controllers run on `mgmt-1`'s nodes behind Calico instead of in k3s behind flannel, so success
before the pivot proves little about the state after it.

## Decision

- The bootstrap cluster is single-node k3s in the bootstrap instance, an unprivileged LXD
  container ([`bootstrap`](../../ansible/roles/bootstrap/)): the pinned binary from the host,
  dual-stack, without Traefik, ServiceLB, network policy or the cloud controller, its API
  published on the host ([0012](0012-api-publication-lxd-proxy.md)). No Docker, no kind.
- On it: the providers, the CAPN identity, then `mgmt-1` and its add-ons through Helm. The
  gates run on `mgmt-1` before the move, so a broken data plane stops the run before the pivot.
- The pivot always happens: `clusterctl : pivot` installs the providers on `mgmt-1`, moves the
  namespace and asserts that the Cluster is on `mgmt-1` and gone from the source. From then on
  `mgmt-1` manages itself, and every workload cluster is created on it.
- `bootstrap : destroy` removes the instance only when `mgmt-1` is self-hosted, the bootstrap
  API holds no Cluster and LXD answers.

## Consequences

- A rollout of `mgmt-1` drains the nodes its own controllers and checks run on (the
  convergence check is a Job for that reason, [0014](0014-acceptance-gates-as-helm-tests.md)),
  and `mgmt-1` cannot delete its own machines: removing it goes through LXD directly
  ([teardown.md](../runbooks/teardown.md)).
- `mgmt-1`'s etcd holds the management of every cluster; losing it leaves the nodes running
  unmanaged. [backup-restore.md](../runbooks/backup-restore.md) covers etcd snapshots and
  `clusterctl move --to-directory`; a rebuild after losing `mgmt-1` as a whole is outlined,
  not exercised.
- `mgmt-1` defaults to one control-plane machine, one etcd member; a larger odd count is an
  input. Its ClusterClass and Cluster releases are installed again on it after the move
  ([0005](0005-one-owner-per-cluster.md)).
- The first run builds two clusters, and the k3s release must be one Cluster API supports
  for a management cluster.
