# Runbooks

Day-2 procedures for a deployment built from this repository: one host, the
management playbook that owns the host, LXD and `mgmt-1`, and workload clusters,
each applied from two Terraform roots (the cluster, then its add-ons). Every
runbook was drilled on the local harness; its *Tested* line says when, and
names any step that was not exercised.

## Conventions

| Placeholder | Meaning | On the harness |
|---|---|---|
| `<playbook>` | your management playbook, derived from [`tests/playbooks/management.yml`](../../tests/playbooks/management.yml), with its inventory | `make -C tests/molecule e2e-local-converge [VARS=<file>]` runs `management.yml` and then applies the fixture roots |
| `group_vars/all.yml` | the variables next to your playbook ([variable contract](../variable-contract.md)) | [`tests/playbooks/group_vars/all.yml`](../../tests/playbooks/group_vars/all.yml); a drill's changes come in a `VARS` file on top |
| `<root>` | the directory holding a workload cluster's two roots, `<root>/cluster` and `<root>/addons` | [`tests/fixtures/terraform/workload-clusters/lab-default`](../../tests/fixtures/terraform/workload-clusters/lab-default/) |
| `$MGMT` | the runner's copy of the `mgmt-1` kubeconfig, `<k8s_lab_artifacts_dir>/mgmt.kubeconfig` | `.artifacts/mgmt.kubeconfig` |
| `$NS` | `k8s_lab_cluster_namespace`, where the Cluster objects live | `capi-clusters` |
| `$PROJECT` | `k8s_lab_project_name`, the LXD project of every node | `capi-lab` |

Commands marked *host* run as root on the host; `lxc`, `snap` and the
binaries under `k8s_lab_opt_root` (`/opt/capi-lab/bin`) live there. Every other
command runs on the runner, where the playbook and Terraform run; `jq` is a
runner tool. Other names in the commands — `/opt/capi-lab`, the network
`capi-int`, the pool `capi-fast`, the bridge `br-ext6`, the Secret
`incus-identity` — are the reference values: substitute your deployment's.

## Index

| Operation | Runbook | Owner of the change |
|---|---|---|
| Kubernetes upgrade (workload cluster, `mgmt-1`) | [upgrade-kubernetes.md](upgrade-kubernetes.md) | Terraform input / `group_vars` pin |
| Scale workers or control plane | [scale.md](scale.md) | Terraform input / role input |
| Change the node template | [change-node-template.md](change-node-template.md) | chart values → machine rotation |
| Change the external IPv6 prefix | [change-external-prefix.md](change-external-prefix.md) | role input → every cluster |
| Upgrade Cluster API and CAPN | [upgrade-providers.md](upgrade-providers.md) | `group_vars` pins |
| Upgrade Calico or MetalLB | [upgrade-addons.md](upgrade-addons.md) | chart dependency |
| Host or LXD configuration change | [host-and-lxd.md](host-and-lxd.md) | roles `host`, `lxd` |
| LXD refresh, daemon reload, channel change | [lxd.md](lxd.md) | manual |
| Host reboot | [host-reboot.md](host-reboot.md) | none |
| CAPN identity rotation, a new namespace | [capn-identity.md](capn-identity.md) | role `capn_identity` |
| Lost or expired kubeconfig | [kubeconfig.md](kubeconfig.md) | playbook / Terraform |
| Add or remove a workload cluster | [workload-clusters.md](workload-clusters.md) | a new pair of roots |
| Teardown | [teardown.md](teardown.md) | Terraform; manual for the rest |
| Backup and disaster recovery of `mgmt-1` | [backup-restore.md](backup-restore.md) | manual |
| Certificate expiry | [certificates.md](certificates.md) | automatic + re-export |

Re-running the management playbook on a live host is always safe while the
names stay the same: every role decides from the live state whether it has
work to do, and a run on a self-hosted `mgmt-1` neither re-creates the
bootstrap cluster nor restarts a node. Names are fixed for a deployment's life
([host-and-lxd.md](host-and-lxd.md)).

## Template

Each runbook has the same sections: **When to use** · **Preconditions** ·
**Steps** (the commands as they were run) · **Verify** · **Rollback** ·
**Tested** (date and harness, or "not exercised").
