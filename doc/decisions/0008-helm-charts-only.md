# 0008. Helm charts carry every Kubernetes object the repository creates

Status: Accepted, 2026-11-16

## Context

Objects applied with `kubectl apply -f`, `kubernetes_manifest` or `kubernetes.core.k8s
state=present` have no record of what belongs together: nothing upgrades them as a unit,
rolls them back, removes what a newer version dropped, or tests them. The upstream add-ons
ship as Helm charts already, and both owners (Ansible and Terraform) can drive Helm.

## Decision

- Every Kubernetes object this repository creates comes from a chart under
  [`charts/`](../../charts/): the ClusterClass and its templates, the Cluster and its API
  hook, Calico, MetalLB, their configuration and the gates. Ansible installs them with
  `kubernetes.core.helm` (`mgmt-1`), Terraform with `helm_release` (workload clusters).
- Upstream components are wrapped, not copied: `cni-calico` and `metallb` depend on the
  upstream chart at an exact version (`Chart.lock` committed) and set only what differs.
- A chart value exists only for a choice a deployment may make; what the nodes need is
  literal in the templates. Charts with values of their own validate them with
  `values.schema.json`, `additionalProperties: false` at the root
  ([charts.md](../reference/charts.md)).
- Reads are allowed anywhere: `k8s_info`, `kubectl wait`, Terraform data sources, and
  server-side dry runs that store nothing (the MetalLB webhook probe).
- Two exceptions: the providers (Cluster API, CAPN, cert-manager), which `clusterctl`
  installs, upgrades and moves; and the CAPN identity Secrets and their Namespaces, which
  `capn_identity` writes. A Secret carries the client key, which must not land in a Helm
  release record, and every chart that creates a cluster needs it first. The Secret is
  applied server-side and carries the move label, so the pivot takes it along; the
  Namespace is created plainly.

## Consequences

- Each component has one release record. Upgrade, rollback, uninstall and `helm test` work
  the same on `mgmt-1` and on a workload cluster, and a Helm install on `mgmt-1` adopts the
  objects the pivot moved ([0005](0005-one-owner-per-cluster.md)).
- Helm's limits apply. A release record must fit in a Secret (1 MiB), so Calico's CRDs are
  left to its operator; Helm 4 applies server-side and conflicts with an operator that writes
  the same fields, so `cni-calico-config` renders the defaults the operator writes back
  ([0013](0013-calico-and-metallb.md)).
- The add-ons' CRDs exist only once their upstream release runs (MetalLB ships them as
  templates, Calico's operator creates them), so each add-on is two releases with a read-only
  wait between them.
- The runner needs the Helm CLI; `helm test` has no Ansible module or Terraform resource.
