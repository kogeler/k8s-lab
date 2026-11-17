# 0005. One owner per cluster: Ansible for the host and `mgmt-1`, Terraform for workload clusters

Status: Accepted, 2026-11-16

## Context

`mgmt-1` is created on the bootstrap cluster and moved onto itself by the pivot. Helm keeps a
release's record on the API it was installed through, so after the move `mgmt-1`'s
ClusterClass and Cluster have no Helm release and no state anywhere unless something installs
them again: nothing could upgrade, scale or remove them. An operation that needs both tools,
an Ansible run and a Terraform apply in some order, can fail halfway in a way neither tool
sees.

## Decision

- Ansible owns the host, LXD, the bootstrap cluster and `mgmt-1` for its whole life. Role
  [`management_cluster`](../../ansible/roles/management_cluster/) installs `mgmt-1`'s
  ClusterClass and Cluster releases and its add-ons with `kubernetes.core.helm`. After the
  pivot the reference playbook runs it again against `mgmt-1`, and Helm adopts the moved
  objects into releases stored on `mgmt-1` itself.
- Terraform owns each workload cluster from creation to removal: create, scale, upgrade, a
  template or add-on change, destroy ([0010](0010-terraform-two-roots.md)). None of these needs
  an Ansible run or an inventory change. Publishing the cluster's API server is a Helm hook of
  the Cluster chart for that reason ([0012](0012-api-publication-lxd-proxy.md)).
- The interface between the two is one file, `handoff.json`, written by `management_cluster`
  on the runner: the host address, the cluster namespace, the CAPN identity Secret's name, the
  path of `mgmt.kubeconfig`, the external IPv6 prefix. Terraform roots only read it.

## Consequences

- Every cluster has one tool that changes it and one place for its state: Helm releases on
  `mgmt-1`, or the pair of Terraform states of a workload cluster.
- Changes of the management side are Ansible runs even when workload clusters feel them:
  provider upgrades, a new CAPN identity namespace (needed before a workload cluster can use
  that namespace, [capn-identity.md](../runbooks/capn-identity.md)), a new external prefix
  (followed by an apply of every workload cluster's roots,
  [change-external-prefix.md](../runbooks/change-external-prefix.md)).
- Terraform depends on files Ansible writes on the runner (`handoff.json`, `mgmt.kubeconfig`);
  a deployment that runs Terraform elsewhere copies them there and sets the roots'
  `handoff_path` and `mgmt_kubeconfig_path` to the copies.
