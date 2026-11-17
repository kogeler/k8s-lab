# 0010. A workload cluster is two provider-less modules applied from two roots

Status: Accepted, 2026-11-16

## Context

A workload cluster has a management side, its ClusterClass and Cluster releases on `mgmt-1`,
and a workload side, Calico, MetalLB and the gates, installed through its own API, whose
credentials exist only once the Cluster does. Terraform must know a provider's configuration
when it plans. A provider configured from data that depends on a resource of the same apply
is unknown at plan time whenever that resource changes: a scale or a Kubernetes upgrade
then plans the add-on releases as deleted and to be created, and applying that plan drops
them from the state while they keep running. A configuration with providers inside also
cannot be instantiated with `for_each`.

## Decision

- [`workload_cluster`](../../terraform/modules/workload_cluster/), the management side: the
  class release (`atomic`) and the Cluster release (not `atomic`: rolling back a topology
  change asks Cluster API for a downgrade). It validates an odd control-plane count, at least
  two workers, `[IPv4, IPv6]` CIDRs and an IPv6 external prefix.
- [`workload_addons`](../../terraform/modules/workload_addons/), the workload side: Calico,
  the convergence check, Gate B, MetalLB, Gate A
  ([0014](0014-acceptance-gates-as-helm-tests.md)). Its data-only `modules/access` reads the
  Cluster and its kubeconfig Secret on `mgmt-1` and outputs the connection.
- No module declares a provider. Each cluster has two roots: `cluster` (`helm` on `mgmt-1`),
  then `addons` (`kubernetes` on `mgmt-1` for `access`, `helm` on the workload cluster from
  its outputs, known at plan time). Apply in that order, destroy in reverse. Both read
  `handoff.json`; chart versions come from each `Chart.yaml`
  ([terraform.md](../reference/terraform.md)).

## Consequences

- Scaling and upgrades pass without a workaround, and the add-on apply waits until Cluster API
  has converged.
- Two applies and two states per cluster. The add-on root's state holds the admin kubeconfig
  (redacted in output, present in the file) and must be protected.
- An add-on plan made while the workload API does not answer shows its releases as to be
  created and must not be applied ([troubleshooting.md](../troubleshooting.md));
  `make destroy-workload` skips the add-on root then, since its objects go with the cluster.
- One add-on root per cluster, each with its own workload provider. The runner needs `bash`,
  `kubectl` and the Helm CLI; the modules read the charts from the copy of this repository
  they come with (Terraform's git source fetches it whole).
