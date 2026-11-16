# 0009. One ClusterClass per cluster, its templates named after a hash of their content

Status: Accepted, 2026-11-16

## Context

Cluster API rejects most changes to a template once a ClusterClass uses it: a change is a new
template the ClusterClass points at, and Cluster API then rolls the machines that use it. A
template's name therefore has to change exactly when its spec changes — no more often, or
machines roll for nothing, and no less often, or the change is refused — and a value change
should not need a new chart release.

## Decision

- Chart [`capi-cluster-class`](../../charts/capi-cluster-class/) renders one ClusterClass per
  cluster, named after the cluster, in a release of its own (`<cluster>-class`).
- Each template is named `<cluster>-<kind>-<8 hex of the sha256 of its rendered spec>`, kinds
  `infra`, `kcp`, `cp`, `md-0`, `md-0-boot`
  ([`_helpers.tpl`](../../charts/capi-cluster-class/templates/_helpers.tpl)), never after the
  chart version. An unchanged spec keeps its name, a changed spec renames that template only;
  `tests/charts/class-names.sh` in `make check` asserts both.
- A changed value rolls out by rotation: the new template is created, the ClusterClass points
  at it, Cluster API replaces the machines, Helm deletes the old template. `helm rollback`
  restores the previous name and rolls back the same way.
- The Kubernetes version is a field of the Cluster, not of a template. The class release's
  revision goes into the Cluster's `k8s-lab.io/class-revision` annotation, so the add-on root
  sees a template change ([0010](0010-terraform-two-roots.md)).

## Consequences

- A template change replaces machines, never edits them, and needs room on the host for one
  extra machine per rollout.
- Clusters do not share a ClusterClass. Identical specs hash alike, and the cluster prefix
  keeps the names apart (`mgmt-1-kcp-<hash>`, `lab-default-kcp-<hash>`).
- A version of this repository whose templates render differently rotates the machines of
  every cluster on its next playbook run or apply; its changelog has to say so.
- A workload cluster reaches every template value through the module input
  `cluster_class_values`; role `management_cluster` passes only the name, the identity Secret
  and the external prefix, so `mgmt-1`'s other template values are the chart's defaults.
