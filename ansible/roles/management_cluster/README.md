# management_cluster

## Purpose

Creates the management cluster (`mgmt-1`) through Helm on the Kubernetes API that
currently holds its `Cluster` object, installs Calico and MetalLB on it, runs the
acceptance gates and writes the handoff file for Terraform roots. Its `state` entry
point decides which API that is. It does not install Cluster API providers or the
CAPN identity (roles `clusterctl`, `capn_identity`).

## Requirements

- `tasks_from: state` earlier in the same play (it publishes
  `k8s_lab_management_state`, `k8s_lab_management_kubeconfig`,
  `k8s_lab_management_kubeconfig_runner`); it runs on the host and needs LXD and
  kubectl under `<opt_root>/bin`.
- The main entry point runs its Kubernetes tasks on the runner
  (`delegate_to: localhost`); the runner needs `helm`, the `kubernetes` Python package
  and the charts of this repository.
- The managing API serves Cluster API with `ClusterTopology` and holds the CAPN
  identity Secret.

## Inputs

Declared in `meta/argument_specs.yml` (entry points `main` and `state`); names, paths
and versions default to common variables and published facts
([variable contract](../../../doc/variable-contract.md)), counts, CIDRs and timeouts
to literals; `management_cluster_external_ipv6_prefix` and
`management_cluster_metallb_vip_range_v6` are required (no default).
`management_cluster_enabled` and
`management_cluster_flow_control_{cluster,kubeconfig,addons,gates,handoff}`.

## What it changes

- Helm releases `<name>-class` and `<name>` (ClusterClass and Cluster) in the cluster
  namespace on the managing API.
- `mgmt.kubeconfig`: `<opt_root>/etc/` on the host and the artifacts directory on the
  runner (0600), rebuilt from the Cluster API kubeconfig Secret. When `mgmt-1` manages
  itself, the `state` entry point first copies the host's copy (which it has just used)
  to the runner, so a lost runner copy does not stop the roles that run before the
  rebuild.
- On the management cluster: releases `cni-calico`, `cni-calico-config`
  (`tigera-operator`), `metallb`, `metallb-config` (`metallb-system`).
- Runner: `handoff.json` (0600) with `lxd_host_address`, `cluster_namespace`,
  `infrastructure_secret_name`, `mgmt_kubeconfig_path`, `external_ipv6_prefix`.

## Re-running

A release whose chart version and values are unchanged is left alone: the Helm
module compares them and does not run Helm, so an object changed by hand is not
repaired by a re-run (a new chart version or value is). A second invocation against
the same managing API in one play ends at once. The gates run on every invocation.
`state` reads, and writes only the runner's copy of `mgmt.kubeconfig`; it refuses
when no API holds `mgmt-1` while its nodes exist, or when `mgmt-1` refuses the
host's kubeconfig.

## Removing

Nothing in this role removes the cluster.

## Tested by

`tests/molecule/bootstrap` (`state`) and `tests/molecule/e2e-local` (through
`tests/playbooks/management.yml`).
